import Foundation

/// User-selected routing trigger override from the configuration window.
enum RouteOverride: String, Codable {
    case auto
    case always
    case never

    var menuIndex: Int {
        switch self {
        case .auto: return 0
        case .always: return 1
        case .never: return 2
        }
    }

    init(menuIndex: Int) {
        switch menuIndex {
        case 1: self = .always
        case 2: self = .never
        default: self = .auto
        }
    }
}

/// A macOS audio output device, reduced to what routing decisions need.
struct AudioOutputDevice: Codable, Equatable {
    let uid: String
    let name: String
    let isAirPlay: Bool

    /// UID is authoritative. Only when BOTH sides report an empty UID
    /// (some virtual devices do) does identity fall back to the device name.
    func matches(_ other: AudioOutputDevice) -> Bool {
        if uid.isEmpty && other.uid.isEmpty {
            return name == other.name
        }
        return uid == other.uid
    }
}

/// Pure routing decision, kept free of AppKit/CoreAudio so `make test`
/// can cover the full decision matrix without a GUI or live hardware.
enum RoutingPolicy {
    /// Media keys go to the TV only when the audio the user is hearing comes
    /// from the configured TV output device (or the user explicitly forces it).
    static func shouldRoute(
        target: AudioOutputDevice?,
        current: AudioOutputDevice?,
        override: RouteOverride
    ) -> Bool {
        // AirPlay output is already adjustable by macOS itself; intercepting
        // there would double-adjust the TV volume. This pass-through holds for
        // every override, including .always.
        guard current?.isAirPlay != true else {
            return false
        }
        switch override {
        case .never:
            return false
        case .always:
            return target != nil
        case .auto:
            guard let target, let current else {
                return false
            }
            return target.matches(current)
        }
    }
}
