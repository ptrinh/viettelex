import Foundation

extension Notification.Name {
    /// Posted (main thread) when the "permission not granted" state starts or ends
    /// WITHOUT the system's `com.apple.accessibility.api` notification — the Settings
    /// banner listens so it does not wait for its window to become key again.
    static let telexTrustStateChanged = Notification.Name("com.viettelex.trustStateChanged")
}

/// Schedule of the "Accessibility not granted yet" poll in TerminalTapController.
/// Pure (no timers, no TCC) so the cadence contract is pinned by unit tests.
///
/// Why it exists (field reports 26/10/2026, macOS 27.0.1): granting VietTelex in the
/// renamed pane (Device Control and Data Access) did not reach a running process —
/// the `com.apple.accessibility.api` notification apparently no longer fires from
/// that pane and the old fixed 3s poll asked `AXIsProcessTrusted()` alone, which
/// stayed false until the IME was restarted. Now the tick also asks the PostEvent
/// preflight (`grantDetected`) and the cadence is cheap: 2s while the user is likely
/// in System Settings, 10s after that, and NOTHING while trusted (disarmed).
struct TrustPollSchedule: Equatable {
    static let fastInterval: TimeInterval = 2
    static let slowInterval: TimeInterval = 10
    /// Fast cadence right after the poll arms (permission just went missing / launch).
    static let armFastWindowNs: UInt64 = 60_000_000_000
    /// Fast cadence after the user DID something about it: clicked "Open Settings",
    /// or came back from System Settings.
    static let boostFastWindowNs: UInt64 = 120_000_000_000

    private(set) var isArmed = false
    private(set) var fastUntilNs: UInt64 = 0

    /// Start polling. Re-arming while armed changes nothing — `ensureRunning()` runs on
    /// every app switch and must not keep the fast window alive forever. Returns true
    /// only on a fresh arm.
    @discardableResult
    mutating func arm(nowNs: UInt64) -> Bool {
        guard !isArmed else { return false }
        isArmed = true
        fastUntilNs = nowNs &+ Self.armFastWindowNs
        return true
    }

    /// The user acted on the permission: arm if needed and EXTEND (never shorten) the
    /// fast window to `boostFastWindowNs` from now.
    mutating func boost(nowNs: UInt64) {
        isArmed = true
        fastUntilNs = max(fastUntilNs, nowNs &+ Self.boostFastWindowNs)
    }

    /// Trusted (or a tap exists): no polling at all.
    mutating func disarm() {
        isArmed = false
        fastUntilNs = 0
    }

    /// Delay before the next tick; nil when disarmed (zero cost in the normal state).
    func nextInterval(nowNs: UInt64) -> TimeInterval? {
        guard isArmed else { return nil }
        return nowNs < fastUntilNs ? Self.fastInterval : Self.slowInterval
    }

    /// Does a live read mean "the grant is in"? Either signal suffices: the PostEvent
    /// preflight is answered by TCC directly, while `AXIsProcessTrusted()` can stay
    /// stuck at the launch-time answer when the system notification never arrives.
    /// (The reverse disagreement — AX true, PostEvent false — is the stale-grant
    /// state; it still counts as trusted here, exactly as before, and keeps its own
    /// repair flow.)
    static func grantDetected(axTrusted: Bool, canPostEvents: Bool) -> Bool {
        axTrusted || canPostEvents
    }

    /// System Settings losing focus = the user is coming back from the pane.
    static let systemSettingsBundleIDs: Set<String> = ["com.apple.systempreferences"]
    static func isSystemSettings(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return systemSettingsBundleIDs.contains(bundleID)
    }
}
