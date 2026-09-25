import Foundation

/// Decision-matrix tests for `RoutingPolicy`.
/// Run via `make test` (swiftc direct; the project intentionally has no Xcode test target).
@main
struct RoutingPolicyTests {
    private static var failures = 0

    private static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("PASS \(label)")
        } else {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static func main() {
        let tv = AudioOutputDevice(uid: "uid-tv", name: "LG TV SSCR2", isAirPlay: false)
        let ultra = AudioOutputDevice(uid: "uid-ultra", name: "LG ULTRAWIDE", isAirPlay: false)
        // Same identity as `tv`, but reached over AirPlay: the AirPlay flag must be
        // the ONLY difference that flips the decision.
        let tvViaAirPlay = AudioOutputDevice(uid: "uid-tv", name: "LG TV SSCR2", isAirPlay: true)
        let tvNameOnly = AudioOutputDevice(uid: "", name: "LG TV SSCR2", isAirPlay: false)
        let otherNameOnly = AudioOutputDevice(uid: "", name: "Other Virtual", isAirPlay: false)

        // auto (default): route only when the current sound output is the configured TV.
        expect(
            RoutingPolicy.shouldRoute(target: tv, current: tv, override: .auto),
            "auto: current output is the configured TV routes"
        )
        expect(
            !RoutingPolicy.shouldRoute(target: tv, current: ultra, override: .auto),
            "auto: different output device passes through"
        )
        expect(
            !RoutingPolicy.shouldRoute(target: tv, current: tvViaAirPlay, override: .auto),
            "auto: AirPlay output passes through (macOS adjusts natively)"
        )
        expect(
            !RoutingPolicy.shouldRoute(target: tv, current: nil, override: .auto),
            "auto: missing current output passes through"
        )
        expect(
            !RoutingPolicy.shouldRoute(target: nil, current: tv, override: .auto),
            "auto: unconfigured target passes through"
        )

        // UID fallback: name matching applies only when BOTH sides report empty UIDs.
        expect(
            RoutingPolicy.shouldRoute(target: tvNameOnly, current: tvNameOnly, override: .auto),
            "auto: empty UID on both sides falls back to name match"
        )
        expect(
            !RoutingPolicy.shouldRoute(target: tvNameOnly, current: otherNameOnly, override: .auto),
            "auto: empty UIDs with different names pass through"
        )
        expect(
            !RoutingPolicy.shouldRoute(target: tv, current: tvNameOnly, override: .auto),
            "auto: empty UID on one side only does not name-match"
        )
        expect(
            !RoutingPolicy.shouldRoute(target: tvNameOnly, current: tv, override: .auto),
            "auto: empty UID on target side only does not name-match"
        )

        // always: explicit override routes regardless of the current output…
        expect(
            RoutingPolicy.shouldRoute(target: tv, current: ultra, override: .always),
            "always: routes with a non-TV output"
        )
        expect(
            RoutingPolicy.shouldRoute(target: tv, current: nil, override: .always),
            "always: routes even with no current output"
        )
        expect(
            !RoutingPolicy.shouldRoute(target: nil, current: tv, override: .always),
            "always: unconfigured target still passes through"
        )
        // …except AirPlay, which every override passes through (no double-adjust).
        expect(
            !RoutingPolicy.shouldRoute(target: tv, current: tvViaAirPlay, override: .always),
            "always: AirPlay output still passes through"
        )

        // never: explicit override never intercepts.
        expect(
            !RoutingPolicy.shouldRoute(target: tv, current: tv, override: .never),
            "never: passes through even on an output match"
        )
        expect(
            !RoutingPolicy.shouldRoute(target: tv, current: tvViaAirPlay, override: .never),
            "never: passes through on AirPlay output"
        )

        if failures > 0 {
            print("\(failures) test(s) failed")
            exit(1)
        }
        print("All routing-policy tests passed")
        exit(0)
    }
}
