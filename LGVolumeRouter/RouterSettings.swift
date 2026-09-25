import Foundation

struct RouterSettingsSnapshot: Equatable {
    let tvName: String
    let host: String
    let scheme: String
    let port: Int
    let targetAudioDevice: AudioOutputDevice?
    let routeOverride: RouteOverride

    var isConfigured: Bool {
        guard !host.isEmpty,
              targetAudioDevice != nil,
              (scheme == "ws" || scheme == "wss"),
              (1...65_535).contains(port) else {
            return false
        }
        return true
    }

    var endpointURL: URL? {
        guard isValidEndpointInput else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/"
        return components.url
    }

    var endpointKey: String {
        "\(scheme)://\(host):\(port)"
    }

    private var isValidEndpointInput: Bool {
        !host.isEmpty && (scheme == "ws" || scheme == "wss") && (1...65_535).contains(port)
    }
}

final class RouterSettings {
    private enum Key {
        static let tvName = "tvName"
        static let host = "host"
        static let scheme = "scheme"
        static let port = "port"
        static let targetAudioDevice = "targetAudioDevice"
        static let routeOverride = "routeOverride"
        /// v0.1.x stored a display identity; v0.2.0 routes by sound output instead.
        static let legacyTargetDisplay = "targetDisplay"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Migration: the v0.1.x display-based selection cannot be reinterpreted as an
        // audio device, so it is cleared and the app asks for the output device once.
        defaults.removeObject(forKey: Key.legacyTargetDisplay)
    }

    var tvName: String {
        get { defaults.string(forKey: Key.tvName) ?? "" }
        set { defaults.set(newValue, forKey: Key.tvName) }
    }

    var host: String {
        get { defaults.string(forKey: Key.host) ?? "" }
        set { defaults.set(newValue, forKey: Key.host) }
    }

    var scheme: String {
        get { defaults.string(forKey: Key.scheme) ?? "wss" }
        set { defaults.set(newValue, forKey: Key.scheme) }
    }

    var port: Int {
        get {
            let stored = defaults.object(forKey: Key.port) as? NSNumber
            return stored?.intValue ?? 3_001
        }
        set { defaults.set(newValue, forKey: Key.port) }
    }

    var targetAudioDevice: AudioOutputDevice? {
        get {
            guard let data = defaults.data(forKey: Key.targetAudioDevice) else { return nil }
            return try? JSONDecoder().decode(AudioOutputDevice.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.targetAudioDevice)
                return
            }
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.targetAudioDevice)
            }
        }
    }

    var routeOverride: RouteOverride {
        get {
            guard let raw = defaults.string(forKey: Key.routeOverride) else { return .auto }
            return RouteOverride(rawValue: raw) ?? .auto
        }
        set { defaults.set(newValue.rawValue, forKey: Key.routeOverride) }
    }

    /// The provider receives immutable snapshots so connection work never observes a partial UI edit.
    var snapshot: RouterSettingsSnapshot {
        RouterSettingsSnapshot(
            tvName: tvName,
            host: host,
            scheme: scheme,
            port: port,
            targetAudioDevice: targetAudioDevice,
            routeOverride: routeOverride
        )
    }

    /// Persists a complete configuration atomically from the configuration window's point of view.
    func update(
        tvName: String,
        host: String,
        scheme: String,
        port: Int,
        targetAudioDevice: AudioOutputDevice,
        routeOverride: RouteOverride
    ) {
        self.tvName = tvName
        self.host = host
        self.scheme = scheme
        self.port = port
        self.targetAudioDevice = targetAudioDevice
        self.routeOverride = routeOverride
    }
}
