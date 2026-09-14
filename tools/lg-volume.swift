import Foundation

private enum CLIAction: String {
    case pair
    case status
    case up
    case down
    case mute

    var label: String { rawValue }
}

private struct CLISettings {
    let host: String
    let scheme: String
    let port: Int

    var endpoint: URL {
        get throws {
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.port = port
            components.path = "/"
            guard let url = components.url else {
                throw CLIError.invalidConfiguration("The saved TV endpoint is invalid.")
            }
            return url
        }
    }

    static func load(arguments: [String]) throws -> (settings: CLISettings, action: CLIAction) {
        guard let actionName = arguments.first,
              let action = CLIAction(rawValue: actionName) else {
            throw CLIError.usage
        }

        var overrides: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            guard flag == "--host" || flag == "--port" else {
                throw CLIError.usage
            }
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw CLIError.usage
            }
            overrides[flag] = arguments[valueIndex]
            index += 2
        }

        // The CLI intentionally shares the app's domain and Keychain service. `--host` stays
        // available for one-off control without changing the app configuration.
        let domain = UserDefaults.standard.persistentDomain(forName: ProductConfiguration.bundleIdentifier) ?? [:]
        let savedHost = domain["host"] as? String ?? ""
        let savedScheme = domain["scheme"] as? String ?? "wss"
        let savedPort = (domain["port"] as? NSNumber)?.intValue ?? 3_001

        let host = overrides["--host"] ?? savedHost
        let port: Int
        if let portOverride = overrides["--port"] {
            guard let parsedPort = Int(portOverride) else {
                throw CLIError.invalidConfiguration("--port must be a number from 1 to 65535.")
            }
            port = parsedPort
        } else {
            port = savedPort
        }

        guard !host.isEmpty, savedScheme == "wss", (1...65_535).contains(port) else {
            throw CLIError.invalidConfiguration("Set a valid TV address in LG Volume Router first, or pass --host <address> [--port <port>].")
        }

        return (CLISettings(host: host, scheme: savedScheme, port: port), action)
    }
}

private enum CLIError: LocalizedError {
    case usage
    case invalidConfiguration(String)
    case connection(String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: lg-volume <pair|status|up|down|mute> [--host <address>] [--port <port>]"
        case .invalidConfiguration(let message), .connection(let message), .protocolError(let message):
            return message
        }
    }
}

private final class WebOSCLI: NSObject, URLSessionWebSocketDelegate {
    private let settings: CLISettings
    private let action: CLIAction
    private let keychain = KeychainStore()
    private let finished = NSLock()

    private var session: URLSession!
    private var socket: URLSessionWebSocketTask?
    private var clientKey: String?
    private var waitingForPairing = false
    private var exitCode = 1
    private var didFinish = false
    private var timeoutWorkItem: DispatchWorkItem?

    init(settings: CLISettings, action: CLIAction) {
        self.settings = settings
        self.action = action
        super.init()
    }

    func run() -> Int32 {
        do {
            if action == .pair {
                try keychain.deleteClientKey(forHost: settings.host)
                clientKey = nil
                print("Cleared the previous local pairing key. A new pairing request will appear on the TV.")
            } else {
                clientKey = try keychain.clientKey(forHost: settings.host)
            }
            session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            let task = session.webSocketTask(with: try settings.endpoint)
            socket = task
            print("Connecting to the configured LG webOS TV…")
            task.resume()
            scheduleTimeout(seconds: 90)
            while !isFinished {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }
        } catch {
            finish(.failure(error))
        }
        return Int32(exitCode)
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
              let requestPort = requestURL.port,
              task === socket,
              requestHost.caseInsensitiveCompare(settings.host) == .orderedSame,
              requestPort == settings.port,
              challenge.protectionSpace.host.caseInsensitiveCompare(settings.host) == .orderedSame,
              challenge.protectionSpace.port == settings.port else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // LG webOS exposes SSAP on the LAN with a local self-signed certificate.
        // This exception is limited to the exact WSS host and port selected for this invocation.
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard webSocketTask === socket else { return }
        receiveNext()
        sendRegistration()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard task === socket, !didFinish else { return }
        if let error {
            finish(.failure(CLIError.connection("Connection failed: \(error.localizedDescription)")))
        } else {
            finish(.failure(CLIError.connection("The TV closed the connection before returning a result.")))
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard webSocketTask === socket, !didFinish else { return }
        finish(.failure(CLIError.connection("The TV closed the connection (code \(closeCode.rawValue)).")))
    }

    private var isFinished: Bool {
        finished.lock()
        defer { finished.unlock() }
        return didFinish
    }

    private func sendRegistration() {
        var payload: [String: JSONValue] = [
            "pairingType": .string("PROMPT"),
            "manifest": WebOSRegistration.manifest
        ]
        if let clientKey {
            payload["client-key"] = .string(clientKey)
        }
        send(WebOSMessage(
            type: "register",
            id: "register-cli",
            uri: WebOSURIs.register,
            payload: payload
        ))
    }

    private func sendAction() {
        switch action {
        case .pair:
            print("OK: paired for audio control")
            finish(.success(()))
        case .up:
            send(WebOSMessage(type: "request", id: "action-cli", uri: WebOSURIs.volumeUp, payload: [:]))
        case .down:
            send(WebOSMessage(type: "request", id: "action-cli", uri: WebOSURIs.volumeDown, payload: [:]))
        case .mute:
            send(WebOSMessage(type: "request", id: "get-volume-cli", uri: WebOSURIs.getVolume, payload: [:]))
        case .status:
            send(WebOSMessage(type: "request", id: "status-cli", uri: WebOSURIs.getVolume, payload: [:]))
        }
    }

    private func sendMute(_ currentMute: Bool) {
        send(WebOSMessage(
            type: "request",
            id: "action-cli",
            uri: WebOSURIs.setMute,
            payload: ["mute": .bool(!currentMute)]
        ))
    }

    private func send(_ message: WebOSMessage) {
        guard let socket else {
            finish(.failure(CLIError.connection("The webOS socket is not connected.")))
            return
        }
        do {
            let encoded = String(decoding: try message.jsonData(), as: UTF8.self)
            socket.send(.string(encoded)) { [weak self] error in
                if let error {
                    self?.finish(.failure(CLIError.connection("Sending the SSAP request failed: \(error.localizedDescription)")))
                }
            }
        } catch {
            finish(.failure(error))
        }
    }

    private func receiveNext() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(.failure(CLIError.connection("Receiving the SSAP response failed: \(error.localizedDescription)")))
            case .success(let message):
                self.handle(message)
                if !self.didFinish {
                    self.receiveNext()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let value):
            data = value
        @unknown default:
            finish(.failure(CLIError.protocolError("The TV returned an unsupported WebSocket message.")))
            return
        }

        guard let response = try? JSONDecoder().decode(WebOSMessage.self, from: data) else {
            finish(.failure(CLIError.protocolError("The TV returned an unreadable SSAP response.")))
            return
        }

        let type = response.type.lowercased()
        if type == "error" || response.payloadValue("returnValue")?.boolValue == false {
            finish(.failure(CLIError.protocolError("The TV rejected the SSAP request (\(errorDetail(from: data))).")))
            return
        }

        if response.id == "register-cli" || type == "registered" || WebOSPairingMessage(message: response) != nil {
            handleRegistration(response)
            return
        }

        switch response.id {
        case "status-cli":
            printStatus(response)
            finish(.success(()))
        case "get-volume-cli":
            guard let mute = muteValue(from: response) else {
                finish(.failure(CLIError.protocolError("The TV did not return its mute state.")))
                return
            }
            sendMute(mute)
        case "action-cli":
            print("OK: \(action.label)")
            finish(.success(()))
        default:
            break
        }
    }

    private func errorDetail(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "unreadable response"
        }
        let type = (object["type"] as? String) ?? "unknown"
        let id = (object["id"] as? String) ?? "none"
        let reason = ["error", "message", "reason", "errorText"]
            .compactMap { object[$0] as? String }
            .first
        return reason.map { "type=\(type), id=\(id), reason=\($0)" }
            ?? "type=\(type), id=\(id)"
    }

    private func handleRegistration(_ response: WebOSMessage) {
        if let key = response.payloadValue("client-key")?.stringValue {
            do {
                try keychain.saveClientKey(key, forHost: settings.host)
                clientKey = key
                print("Authenticated with the LG TV; the client key is available in the local Keychain.")
                sendAction()
            } catch {
                finish(.failure(error))
            }
            return
        }

        let type = response.type.lowercased()
        let pairingRequested = WebOSPairingMessage(message: response) != nil
            || response.payloadValue("pairingType")?.stringValue?.uppercased() == "PROMPT"

        if type == "registered" {
            print("LG TV registration accepted.")
            sendAction()
        } else if pairingRequested && !waitingForPairing {
            waitingForPairing = true
            let message = WebOSPairingMessage(message: response)?.message ?? "Approve the pairing request on the LG TV to continue."
            print("PAIRING REQUIRED: \(message)")
        }
    }

    private func printStatus(_ response: WebOSMessage) {
        let payload = response.payload ?? [:]
        let details = audioStatus(from: payload)
        let volume = displayNumber(details["volume"])
            ?? displayNumber(payload["volume"])
            ?? "unknown"
        let mute = muteValue(from: response).map { $0 ? "on" : "off" } ?? "unknown"
        print("OK: volume=\(volume) mute=\(mute)")
    }

    private func muteValue(from response: WebOSMessage) -> Bool? {
        let payload = response.payload ?? [:]
        let containers = [payload, audioStatus(from: payload)]
        for container in containers {
            for key in ["mute", "muted", "muteStatus", "isMuted"] {
                if let value = container[key]?.boolValue { return value }
            }
        }
        return nil
    }

    private func audioStatus(from payload: [String: JSONValue]) -> [String: JSONValue] {
        payload["volumeStatus"]?.objectValue
            ?? payload["volume"]?.objectValue
            ?? [:]
    }

    private func displayNumber(_ value: JSONValue?) -> String? {
        switch value {
        case .number(let number):
            return String(Int(number))
        case .string(let text):
            return text
        default:
            return nil
        }
    }

    private func scheduleTimeout(seconds: TimeInterval) {
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(CLIError.connection("Timed out waiting for the LG TV. If pairing was requested, approve it on the TV and run the command again.")))
        }
        timeoutWorkItem = timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    private func finish(_ result: Result<Void, Error>) {
        finished.lock()
        guard !didFinish else {
            finished.unlock()
            return
        }
        didFinish = true
        finished.unlock()

        timeoutWorkItem?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()

        switch result {
        case .success:
            exitCode = 0
        case .failure(let error):
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exitCode = 1
        }
        DispatchQueue.main.async {
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }
}

@main
struct LGVolumeCLI {
    static func main() {
        do {
            let parsed = try CLISettings.load(arguments: Array(CommandLine.arguments.dropFirst()))
            exit(WebOSCLI(settings: parsed.settings, action: parsed.action).run())
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exit(2)
        }
    }
}
