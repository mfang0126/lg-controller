import ApplicationServices
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
    private let focusResolver: FocusScreenResolver
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
        focusResolver: FocusScreenResolver = FocusScreenResolver()
    ) {
        self.settings = settings
        self.provider = provider
        self.focusResolver = focusResolver
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

        _ = FocusScreenResolver.requestAccessibilityPermission()
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

    /// Returns true only when the event belongs to the configured display.
    /// Returning false leaves the original system media-key event untouched.
    func handleMediaKey(_ action: MediaKeyAction) -> Bool {
        guard isEnabled,
              let target = settings.snapshot.targetDisplay,
              let focusedScreen = focusResolver.focusedScreen() else {
            return false
        }

        let focusedDisplay = DisplayIdentity.from(screen: focusedScreen)
        guard target.matches(focusedDisplay) else {
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
