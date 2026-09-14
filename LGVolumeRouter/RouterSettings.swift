import Foundation

struct RouterSettingsSnapshot: Equatable {
    let tvName: String
    let host: String
    let scheme: String
    let port: Int
    let targetDisplay: DisplayIdentity?

    var isConfigured: Bool {
        guard !host.isEmpty,
              targetDisplay != nil,
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
        static let targetDisplay = "targetDisplay"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    var targetDisplay: DisplayIdentity? {
        get {
            guard let data = defaults.data(forKey: Key.targetDisplay) else { return nil }
            return try? JSONDecoder().decode(DisplayIdentity.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.targetDisplay)
                return
            }
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.targetDisplay)
            }
        }
    }

    /// The provider receives immutable snapshots so connection work never observes a partial UI edit.
    var snapshot: RouterSettingsSnapshot {
        RouterSettingsSnapshot(
            tvName: tvName,
            host: host,
            scheme: scheme,
            port: port,
            targetDisplay: targetDisplay
        )
    }

    /// Persists a complete configuration atomically from the configuration window's point of view.
    func update(
        tvName: String,
        host: String,
        scheme: String,
        port: Int,
        targetDisplay: DisplayIdentity
    ) {
        self.tvName = tvName
        self.host = host
        self.scheme = scheme
        self.port = port
        self.targetDisplay = targetDisplay
    }
}
