import Foundation

/// Public identifiers shared by the macOS app, its CLI, and the webOS pairing manifest.
///
/// Keeping these values together is intentional: the CLI reads the same UserDefaults
/// domain and Keychain service as the app, so both surfaces can use one TV pairing.
enum ProductConfiguration {
    static let displayName = "LG Volume Router"
    static let bundleIdentifier = "io.github.mfang0126.LGVolumeRouter"
    static let webOSVendorIdentifier = "io.github.mfang0126"
    static let releaseVersion = "0.1.0"
}
