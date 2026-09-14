import Foundation

enum WebOSProviderState: Equatable {
    case ready
    case connecting
    case connected
    case unavailable
}

struct WebOSAudioState: Equatable {
    let volume: Int
    let isMuted: Bool
}

final class WebOSProvider: NSObject, URLSessionWebSocketDelegate {
    // This serial queue owns every socket, request handler, and state transition.
    // All transport state is owned by one serial queue so pairing, commands, and readbacks cannot race.
    private let stateQueue = DispatchQueue(label: "\(ProductConfiguration.bundleIdentifier).webos-provider")
    private let keychain: KeychainStore
    private var settings: RouterSettingsSnapshot
    private var session: URLSession!

    private var socket: URLSessionWebSocketTask?
    private var isConnecting = false
    private var isRegistered = false
    private var storedClientKey: String?
    private var waitingForPairing = false
    private var nextRequestNumber = 0
    private var pendingActions: [MediaKeyAction] = []
    private var commandInFlight = false
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    private var responseHandlers: [String: (Result<WebOSMessage, Error>) -> Void] = [:]
    private var registrationRequestID: String?
    private var connectionTestCompletion: ((Result<Void, Error>) -> Void)?
    private var pendingAudioRefresh = false
    private var state: WebOSProviderState

    var stateHandler: ((WebOSProviderState) -> Void)?
    var audioStateHandler: ((WebOSAudioState) -> Void)?
    var pairingMessageHandler: ((String) -> Void)?

    var currentState: WebOSProviderState {
        stateQueue.sync { state }
    }

    init(settings: RouterSettingsSnapshot, keychain: KeychainStore = KeychainStore()) {
        self.settings = settings
        self.keychain = keychain
        self.state = settings.isConfigured ? .ready : .unavailable
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func update(settings newSettings: RouterSettingsSnapshot) {
        stateQueue.async {
            let endpointChanged = self.settings.endpointKey != newSettings.endpointKey
            self.settings = newSettings
            guard endpointChanged else {
                if newSettings.isConfigured, self.state == .unavailable {
                    self.publish(.ready)
                }
                return
            }
            self.disconnectLocked(publishReady: newSettings.isConfigured)
        }
    }

    func send(_ action: MediaKeyAction) {
        stateQueue.async {
            guard self.settings.isConfigured else {
                self.publish(.unavailable)
                return
            }
            self.pendingActions.append(action)
            if self.isRegistered {
                self.flushPendingActionsLocked()
            } else {
                self.connectLocked()
            }
        }
    }

    /// Verifies pairing and audio-read access without changing the TV volume.
    func testConnection(completion: @escaping (Result<Void, Error>) -> Void) {
        stateQueue.async {
            guard self.settings.isConfigured else {
                DispatchQueue.main.async {
                    completion(.failure(ProviderError.notConfigured))
                }
                return
            }
            guard self.connectionTestCompletion == nil else {
                DispatchQueue.main.async {
                    completion(.failure(ProviderError.testAlreadyInProgress))
                }
                return
            }

            self.connectionTestCompletion = completion
            if self.isRegistered {
                self.flushPendingActionsLocked()
            } else {
                self.connectLocked()
            }
        }
    }

    /// Refreshes the menu-bar audio state without changing TV audio.
    /// Requests are coalesced and serialized behind active media-key commands.
    func refreshAudioState() {
        stateQueue.async {
            guard self.settings.isConfigured else { return }
            self.pendingAudioRefresh = true
            if self.isRegistered {
                self.flushPendingActionsLocked()
            } else {
                self.connectLocked()
            }
        }
    }

    func disconnect() {
        stateQueue.async {
            self.disconnectLocked(publishReady: self.settings.isConfigured)
        }
    }

    func resetPairing() {
        stateQueue.async {
            do {
                try self.keychain.deleteClientKey(forHost: self.settings.host)
                self.disconnectLocked(publishReady: self.settings.isConfigured)
            } catch {
                self.publish(.unavailable)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        stateQueue.async {
            guard self.socket === webSocketTask else { return }
            self.isConnecting = false
            self.receiveNextLocked(from: webSocketTask)
            self.sendRegistrationLocked()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let requestURL = task.currentRequest?.url,
              let requestHost = requestURL.host,
              let requestPort = requestURL.port else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let isConfiguredSocket = stateQueue.sync {
            guard let webSocketTask = task as? URLSessionWebSocketTask else { return false }
            return socket === webSocketTask
                && settings.scheme == "wss"
                && settings.host.caseInsensitiveCompare(requestHost) == .orderedSame
                && requestPort == settings.port
                && challenge.protectionSpace.host.caseInsensitiveCompare(requestHost) == .orderedSame
                && challenge.protectionSpace.port == settings.port
        }

        guard isConfiguredSocket else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // webOS exposes SSAP over TLS with a local, self-signed certificate.
        // Trust only the certificate presented by the actively configured TV WSS host and port.
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        stateQueue.async {
            guard let webSocketTask = task as? URLSessionWebSocketTask,
                  self.socket === webSocketTask else { return }
            self.failConnectionLocked()
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        stateQueue.async {
            guard self.socket === webSocketTask else { return }
            self.failConnectionLocked()
        }
    }

    private func connectLocked() {
        guard !isConnecting, !isRegistered else { return }
        if let socket, socket.state == .running {
            return
        }
        socket = nil

        guard let endpoint = settings.endpointURL else {
            pendingActions.removeAll()
            publish(.unavailable)
            return
        }

        do {
            storedClientKey = try keychain.clientKey(forHost: settings.host)
        } catch {
            pendingActions.removeAll()
            publish(.unavailable)
            return
        }

        isConnecting = true
        publish(.connecting)
        let task = session.webSocketTask(with: endpoint)
        socket = task
        task.resume()
        scheduleConnectionTimeoutLocked(for: task)
    }

    private func sendRegistrationLocked() {
        guard socket != nil else { return }

        var payload: [String: JSONValue] = [
            "pairingType": .string("PROMPT"),
            "manifest": WebOSRegistration.manifest
        ]
        if let storedClientKey {
            payload["client-key"] = .string(storedClientKey)
        }

        let requestID = nextID(prefix: "register")
        registrationRequestID = requestID
        sendRequestLocked(
            type: "register",
            id: requestID,
            uri: WebOSURIs.register,
            payload: payload
        ) { [weak self] result in
            self?.handleRegistrationResultLocked(result)
        }
    }

    /// A routed key has priority over a passive icon refresh; all requests remain serialized.
    private func flushPendingActionsLocked() {
        guard isRegistered, socket?.state == .running, !commandInFlight else { return }

        if connectionTestCompletion != nil {
            sendConnectionTestLocked()
            return
        }

        if !pendingActions.isEmpty {
            let action = pendingActions.removeFirst()
            commandInFlight = true
            switch action {
            case .volumeUp:
                sendCommandLocked(uri: WebOSURIs.volumeUp, payload: [:])
            case .volumeDown:
                sendCommandLocked(uri: WebOSURIs.volumeDown, payload: [:])
            case .mute:
                sendMuteCommandLocked()
            }
            return
        }

        guard pendingAudioRefresh else { return }
        pendingAudioRefresh = false
        sendAudioStateReadLocked()
    }

    private func sendConnectionTestLocked() {
        guard isRegistered, !commandInFlight else { return }
        commandInFlight = true
        sendRequestLocked(
            type: "request",
            id: nextID(prefix: "connection-test"),
            uri: WebOSURIs.getVolume,
            payload: [:]
        ) { [weak self] result in
            guard let self else { return }
            self.commandInFlight = false
            switch result {
            case .success(let response):
                guard self.requestWasAccepted(response) else {
                    self.finishConnectionTestLocked(.failure(ProviderError.audioReadRejected))
                    self.failConnectionLocked()
                    return
                }
                self.publishAudioState(from: response)
                self.publish(.connected)
                self.finishConnectionTestLocked(.success(()))
                self.flushPendingActionsLocked()
            case .failure(let error):
                self.finishConnectionTestLocked(.failure(error))
                self.failConnectionLocked()
            }
        }
    }

    private func sendAudioStateReadLocked() {
        guard isRegistered, !commandInFlight else { return }
        commandInFlight = true
        sendRequestLocked(
            type: "request",
            id: nextID(prefix: "audio-state"),
            uri: WebOSURIs.getVolume,
            payload: [:]
        ) { [weak self] result in
            guard let self else { return }
            self.commandInFlight = false
            if case .success(let response) = result, self.requestWasAccepted(response) {
                self.publishAudioState(from: response)
                self.publish(.connected)
            }
            self.flushPendingActionsLocked()
        }
    }

    /// Read back after mutation so the icon reports the TV's state, not an assumed local value.
    private func completeCommandWithAudioRefreshLocked() {
        sendRequestLocked(
            type: "request",
            id: nextID(prefix: "audio-state"),
            uri: WebOSURIs.getVolume,
            payload: [:]
        ) { [weak self] result in
            guard let self else { return }
            self.commandInFlight = false
            self.pendingAudioRefresh = false
            if case .success(let response) = result, self.requestWasAccepted(response) {
                self.publishAudioState(from: response)
            }
            self.publish(.connected)
            self.flushPendingActionsLocked()
        }
    }

    private func sendMuteCommandLocked() {
        sendRequestLocked(
            type: "request",
            id: nextID(prefix: "mute-state"),
            uri: WebOSURIs.getVolume,
            payload: [:]
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.commandInFlight = false
                self.failConnectionLocked()
            case .success(let response):
                guard self.requestWasAccepted(response), let currentMute = self.muteValue(from: response) else {
                    self.commandInFlight = false
                    self.failConnectionLocked()
                    return
                }
                self.publishAudioState(from: response)
                self.sendRequestLocked(
                    type: "request",
                    id: self.nextID(prefix: "mute"),
                    uri: WebOSURIs.setMute,
                    payload: ["mute": .bool(!currentMute)]
                ) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let response) where self.requestWasAccepted(response):
                        self.completeCommandWithAudioRefreshLocked()
                    default:
                        self.commandInFlight = false
                        self.failConnectionLocked()
                    }
                }
            }
        }
    }

    private func sendCommandLocked(uri: String, payload: [String: JSONValue]) {
        sendRequestLocked(
            type: "request",
            id: nextID(prefix: "audio"),
            uri: uri,
            payload: payload
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response) where self.requestWasAccepted(response):
                self.completeCommandWithAudioRefreshLocked()
            default:
                self.commandInFlight = false
                self.failConnectionLocked()
            }
        }
    }

    private func sendRequestLocked(
        type: String,
        id: String,
        uri: String?,
        payload: [String: JSONValue],
        completion: @escaping (Result<WebOSMessage, Error>) -> Void
    ) {
        guard let task = socket else {
            completion(.failure(ProviderError.notConnected))
            return
        }

        let message = WebOSMessage(type: type, id: id, uri: uri, payload: payload)
        responseHandlers[id] = completion
        do {
            let data = try message.jsonData()
            let string = String(decoding: data, as: UTF8.self)
            task.send(.string(string)) { [weak self] error in
                guard let self else { return }
                self.stateQueue.async {
                    guard let error else { return }
                    let handler = self.responseHandlers.removeValue(forKey: id)
                    handler?(.failure(error))
                }
            }
        } catch {
            responseHandlers.removeValue(forKey: id)
            completion(.failure(error))
        }
    }

    private func receiveNextLocked(from task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self, let task else { return }
            self.stateQueue.async {
                guard self.socket === task else { return }
                switch result {
                case .success(let message):
                    self.handleIncomingLocked(message)
                    self.receiveNextLocked(from: task)
                case .failure:
                    self.failConnectionLocked()
                }
            }
        }
    }

    private func handleIncomingLocked(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let string):
            data = string.data(using: .utf8)
        case .data(let value):
            data = value
        @unknown default:
            data = nil
        }
        guard let data,
              let decoded = try? JSONDecoder().decode(WebOSMessage.self, from: data) else {
            return
        }

        if let pairing = WebOSPairingMessage(message: decoded) {
            presentPairingRequestLocked(decoded)
            if let key = pairing.clientKey {
                persistClientKeyLocked(key)
            }
            return
        }

        if let id = decoded.id,
           let handler = responseHandlers.removeValue(forKey: id) {
            handler(.success(decoded))
            return
        }

        if decoded.type.lowercased() == "registered" {
            completeRegistrationLocked(decoded)
        }
    }

    private func handleRegistrationResultLocked(_ result: Result<WebOSMessage, Error>) {
        registrationRequestID = nil
        switch result {
        case .failure:
            failConnectionLocked()
        case .success(let message):
            if message.type.lowercased() == "error" || message.payloadValue("returnValue")?.boolValue == false {
                failConnectionLocked()
                return
            }

            if message.type.lowercased() == "registered" || message.payloadValue("client-key")?.stringValue != nil {
                completeRegistrationLocked(message)
            } else if isPairingRequested(message) {
                presentPairingRequestLocked(message)
            }
        }
    }

    private func isPairingRequested(_ message: WebOSMessage) -> Bool {
        WebOSPairingMessage(message: message) != nil
            || message.payloadValue("pairingType")?.stringValue?.uppercased() == "PROMPT"
    }

    private func presentPairingRequestLocked(_ message: WebOSMessage) {
        guard !waitingForPairing else { return }
        waitingForPairing = true
        let prompt = WebOSPairingMessage(message: message)?.message
            ?? "Approve the pairing request on the LG TV to continue."
        let handler = pairingMessageHandler
        DispatchQueue.main.async {
            handler?(prompt)
        }
    }

    private func completeRegistrationLocked(_ message: WebOSMessage) {
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        if let key = message.payloadValue("client-key")?.stringValue {
            persistClientKeyLocked(key)
        }
        isRegistered = true
        waitingForPairing = false
        publish(.connected)
        if connectionTestCompletion != nil {
            sendConnectionTestLocked()
        }
        flushPendingActionsLocked()
    }

    private func finishConnectionTestLocked(_ result: Result<Void, Error>) {
        guard let completion = connectionTestCompletion else { return }
        connectionTestCompletion = nil
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func persistClientKeyLocked(_ clientKey: String) {
        guard !clientKey.isEmpty else { return }
        do {
            try keychain.saveClientKey(clientKey, forHost: settings.host)
            storedClientKey = clientKey
        } catch {
            failConnectionLocked()
        }
    }

    private func requestWasAccepted(_ message: WebOSMessage) -> Bool {
        message.type.lowercased() != "error"
            && message.payloadValue("returnValue")?.boolValue != false
    }

    private func publishAudioState(from message: WebOSMessage) {
        guard let audioState = audioState(from: message) else { return }
        let handler = audioStateHandler
        DispatchQueue.main.async {
            handler?(audioState)
        }
    }

    private func audioState(from message: WebOSMessage) -> WebOSAudioState? {
        let payload = message.payload ?? [:]
        let containers = [payload, audioStatus(from: payload)]
        let volume = containers.compactMap { $0["volume"]?.integerValue }.first
        let mute = containers.lazy.compactMap { container in
            ["mute", "muted", "muteStatus", "isMuted"]
                .compactMap { container[$0]?.boolValue }
                .first
        }.first
        guard let volume, let mute else { return nil }
        return WebOSAudioState(volume: min(max(volume, 0), 100), isMuted: mute)
    }

    private func muteValue(from message: WebOSMessage) -> Bool? {
        let payload = message.payload ?? [:]
        for container in [payload, audioStatus(from: payload)] {
            for key in ["mute", "muted", "muteStatus", "isMuted"] {
                if let value = container[key]?.boolValue {
                    return value
                }
            }
        }
        return nil
    }

    private func audioStatus(from payload: [String: JSONValue]) -> [String: JSONValue] {
        payload["volumeStatus"]?.objectValue
            ?? payload["volume"]?.objectValue
            ?? [:]
    }

    private func persistOrIgnorePairingMessage(_ message: WebOSMessage) {
        if let key = WebOSPairingMessage(message: message)?.clientKey {
            persistClientKeyLocked(key)
        }
    }

    private func failConnectionLocked() {
        finishConnectionTestLocked(.failure(ProviderError.connectionFailed))
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isConnecting = false
        isRegistered = false
        storedClientKey = nil
        waitingForPairing = false
        commandInFlight = false
        responseHandlers.removeAll()
        registrationRequestID = nil
        pendingActions.removeAll()
        pendingAudioRefresh = false
        publish(.unavailable)
    }

    private func disconnectLocked(publishReady: Bool) {
        finishConnectionTestLocked(.failure(ProviderError.notConnected))
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isConnecting = false
        isRegistered = false
        storedClientKey = nil
        waitingForPairing = false
        commandInFlight = false
        responseHandlers.removeAll()
        registrationRequestID = nil
        pendingActions.removeAll()
        pendingAudioRefresh = false
        publish(publishReady ? .ready : .unavailable)
    }

    private func publish(_ newState: WebOSProviderState) {
        state = newState
        let handler = stateHandler
        DispatchQueue.main.async {
            handler?(newState)
        }
    }

    private func scheduleConnectionTimeoutLocked(for task: URLSessionWebSocketTask) {
        connectionTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self, weak task] in
            guard let self, let task,
                  self.socket === task,
                  !self.isRegistered else { return }
            self.failConnectionLocked()
        }
        connectionTimeoutWorkItem = timeout
        stateQueue.asyncAfter(deadline: .now() + 10, execute: timeout)
    }

    private func nextID(prefix: String) -> String {
        nextRequestNumber += 1
        return "\(prefix)-\(nextRequestNumber)"
    }

    private enum ProviderError: LocalizedError {
        case notConnected
        case notConfigured
        case testAlreadyInProgress
        case audioReadRejected
        case connectionFailed

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "The LG webOS socket is not connected."
            case .notConfigured:
                return "Set a TV address and target display before testing."
            case .testAlreadyInProgress:
                return "A connection test is already in progress."
            case .audioReadRejected:
                return "The LG TV rejected audio read access."
            case .connectionFailed:
                return "The LG TV connection failed."
            }
        }
    }

    deinit {
        session.invalidateAndCancel()
    }
}
