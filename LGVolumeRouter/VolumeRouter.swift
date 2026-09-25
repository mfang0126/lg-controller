import Foundation

enum RouterStatus: Equatable {
    case disabled
    case ready
    case connecting
    case connected
    case unavailable
}

final class VolumeRouter {
    private let settings: RouterSettings
    private let provider: WebOSProvider
    private let audioOutputResolver: AudioOutputResolver
    private lazy var mediaKeyCapture: MediaKeyCapture = {
        MediaKeyCapture { [weak self] action in
            self?.handleMediaKey(action) ?? false
        }
    }()

    private var providerState: WebOSProviderState
    private(set) var isEnabled = false
    var statusHandler: ((RouterStatus) -> Void)?

    init(
        settings: RouterSettings,
        provider: WebOSProvider,
        audioOutputResolver: AudioOutputResolver = AudioOutputResolver()
    ) {
        self.settings = settings
        self.provider = provider
        self.audioOutputResolver = audioOutputResolver
        self.providerState = provider.currentState

        provider.stateHandler = { [weak self] state in
            self?.providerStateChanged(state)
        }
    }

    var status: RouterStatus {
        guard isEnabled else { return .disabled }
        guard settings.snapshot.isConfigured else { return .unavailable }
        switch providerState {
        case .ready: return .ready
        case .connecting: return .connecting
        case .connected: return .connected
        case .unavailable: return .unavailable
        }
    }

    @discardableResult
    func enable() -> Bool {
        guard !isEnabled else { return true }
        guard settings.snapshot.isConfigured else {
            publishStatus()
            return false
        }

        _ = MediaKeyCapture.requestAccessibilityPermission()
        guard mediaKeyCapture.start() else {
            providerState = .unavailable
            publishStatus()
            return false
        }

        isEnabled = true
        provider.update(settings: settings.snapshot)
        publishStatus()
        return true
    }

    func disable() {
        guard isEnabled else {
            provider.disconnect()
            publishStatus()
            return
        }
        isEnabled = false
        mediaKeyCapture.stop()
        provider.disconnect()
        publishStatus()
    }

    func reloadConfiguration() {
        provider.update(settings: settings.snapshot)
        publishStatus()
    }

    func resetPairing() {
        provider.resetPairing()
    }

    /// Returns true only when the audio the user is hearing belongs to the configured
    /// TV output device (or the user forced routing). Returning false leaves the
    /// original system media-key event untouched.
    func handleMediaKey(_ action: MediaKeyAction) -> Bool {
        guard isEnabled else { return false }
        let snapshot = settings.snapshot
        guard RoutingPolicy.shouldRoute(
            target: snapshot.targetAudioDevice,
            current: audioOutputResolver.currentDefaultOutput(),
            override: snapshot.routeOverride
        ) else {
            return false
        }

        provider.send(action)
        return true
    }

    private func providerStateChanged(_ state: WebOSProviderState) {
        providerState = state
        publishStatus()
    }

    private func publishStatus() {
        let currentStatus = status
        DispatchQueue.main.async { [weak self] in
            self?.statusHandler?(currentStatus)
        }
    }
}
