// TerminalTap.swift
// Terminal (tap) mode: apps that ignore insertText replacementRange (iTerm,
// Terminal.app…) can't be edited in place, and marked-text holds each keystroke in
// a composition buffer so the shell never sees partial input — autocomplete /
// zsh-autosuggestions die. Worse, such apps also don't honor IMKit's return-true
// suppression without a marked-text op, so an input method literally cannot stop the
// raw key.
//
// So for terminals we bypass IMKit entirely: a CGEventTap
// intercepts the physical key BEFORE the terminal sees it, and we either let it
// through (plain letters — shell sees them live, autocomplete works) or SUPPRESS it
// (return nil) and synthesize real Backspace + Unicode to apply a tone edit. Needs
// Accessibility to create the tap and post events, so it only runs on the
// non-sandboxed Developer ID build; the sandboxed Mac App Store build can't get the
// permission and terminals fall back to marked text.
//
// Re-entrancy: events we post travel back through the same tap and the IME. They are
// stamped via the event SOURCE's userData (kCGEventSourceUserData) — the per-event
// field does NOT survive posting; the source's value does — and passed straight
// through so they never re-drive the engine (that was a 9× Backspace cascade bug).

import Cocoa
import Carbon.HIToolbox
import ApplicationServices
import TelexCore

/// THIS build's bundle id — never the ship constant hardcoded at a call site.
/// `Scripts/dev-register.sh` installs the same code under a SEPARATE id
/// (`com.tuanhm.inputmethod.telexdev` by default; it must be separate, see rule #4 in
/// docs/MACOS_IME_NOTES.md), remapping CFBundleIdentifier and every TISInputSourceID.
/// A hardcoded ship prefix therefore made `isVietTelexSelected()` answer FALSE for the
/// dev build's own input source — so the TIS notification, the `deactivateServer`
/// hint and the per-key reconcile all declared VietTelex unselected and put the tap
/// DORMANT mid-word, one key at a time (tester log 2026-08-13: "biết" typed in
/// Terminal came out "biêts" — the tone key passed through raw while the tap was
/// dormant, and the reset that comes with dormancy also dropped the buffer, so a ⌫
/// back to "bi" then `s` gave "bis" instead of "bí").
///
/// EMPTY is treated as missing, not just nil: `Bundle.bundleIdentifier` hands back
/// whatever CFBundleIdentifier holds, and an empty prefix would make `hasPrefix`
/// match EVERY input source — `isVietTelexSelected()` would answer true with ABC
/// selected and the tap would compose Vietnamese over English typing, the exact
/// failure the per-key reconcile exists to prevent. The ship id is the fallback
/// (both states are unreachable for a correctly built bundle).
enum OwnBundle {
    static let id: String = {
        let id = Bundle.main.bundleIdentifier ?? ""
        return id.isEmpty ? "com.viettelex.inputmethod.telex" : id
    }()
}

enum Accessibility {
    // AXIsProcessTrusted() is an out-of-process TCC check (~10-15ms when it misses
    // the kernel-side fast path); in Chromium apps it was hit up to twice per
    // keystroke (usesSelectionReplace on the hot path). Cache it — and, since a TTL
    // expiry otherwise lands ON a keystroke, serve the cached answer ALWAYS and
    // refresh in the BACKGROUND: exactly the shape SpotlightDetector /
    // SecureFieldDetector / FocusedFieldDetector below use (stale read + one
    // deduped async rescan). The only synchronous call left is the FIRST-EVER read
    // (launch, before any keystroke) — there is no cached value to serve then.
    //
    // What carries correctness instead of a fresh read per key:
    //  • the com.apple.accessibility.api observer (main.swift) invalidates the
    //    moment the permission changes, which also kicks the refresh immediately;
    //  • the 3s watchdog calls AXIsProcessTrusted() DIRECTLY (never this cache);
    //  • the tapDisabledBy* branch in handle() likewise calls it directly.
    // So a stale answer can only survive for the microseconds until the background
    // refresh lands, and the paths that must not be wrong don't read this at all.
    //
    // Locked: read on BOTH the main thread (controller/Settings) and the tap thread.
    private static let lock = NSLock()
    private static var cached = false
    /// False until the first answer exists — the ONLY state that reads TCC inline.
    private static var hasValue = false
    private static var lastCheckNs: UInt64 = 0
    private static var refreshing = false
    // 5s. History: 2s → 500ms during the revoke-wedge hunt (the cache gates
    // synthetic-event posting), then BACK UP once the real protections landed (see
    // above). With the async refresh the TTL no longer costs the keystroke anything;
    // it only decides how often a background probe runs.
    static let trustTTLNs: UInt64 = 5_000_000_000
    private static let refreshQueue =
        DispatchQueue(label: "com.viettelex.trust-refresh", qos: .userInitiated)

    #if DEBUG
    /// Test-only override for the TCC answer — unit tests can't grant real
    /// Accessibility, and the routing matrix (AppState) must be exercised in BOTH
    /// trust states. nil = ask TCC as normal. Debug builds only; the Release binary
    /// has no override path.
    static var testTrustOverride: Bool?
    #endif

    /// What a read at `nowNs` must do. Split out as a pure function so the TTL /
    /// stale-read contract can be pinned by tests without a live TCC answer.
    enum TrustRead: Equatable {
        /// No cached answer yet: pay the sync TCC call once (startup, not a keystroke).
        case syncFirstRead
        /// Cached answer is fresh (or a refresh is already in flight) — serve it.
        case serveCached
        /// Serve the cached answer NOW, kick one background refresh.
        case serveCachedAndRefresh
    }

    static func trustReadPlan(hasValue: Bool, lastCheckNs: UInt64, nowNs: UInt64,
                              refreshing: Bool, ttlNs: UInt64 = trustTTLNs) -> TrustRead {
        guard hasValue else { return .syncFirstRead }
        if refreshing { return .serveCached }
        // lastCheckNs == 0 means "invalidated" — always stale, so the next read
        // refreshes promptly (the value is still served immediately).
        if lastCheckNs == 0 || nowNs &- lastCheckNs >= ttlNs { return .serveCachedAndRefresh }
        return .serveCached
    }

    /// True when the process may create an event tap / post events. Always false in
    /// the sandboxed build — it can never be granted.
    static var isTrusted: Bool {
        #if DEBUG
        if let forced = testTrustOverride { return forced }
        #endif
        let now = DispatchTime.now().uptimeNanoseconds
        let (plan, value): (TrustRead, Bool) = lock.withLock {
            (trustReadPlan(hasValue: hasValue, lastCheckNs: lastCheckNs,
                           nowNs: now, refreshing: refreshing), cached)
        }
        switch plan {
        case .syncFirstRead: return syncRefresh()
        case .serveCached: return value
        case .serveCachedAndRefresh:
            kickRefresh()
            return value
        }
    }

    /// The one synchronous TCC read (first-ever call). Runs OUTSIDE the lock — a
    /// concurrent duplicate is harmless, a blocked lock on the key path is not.
    @discardableResult
    private static func syncRefresh() -> Bool {
        let trusted = AXIsProcessTrusted()
        lock.withLock {
            cached = trusted
            hasValue = true
            lastCheckNs = DispatchTime.now().uptimeNanoseconds
        }
        return trusted
    }

    /// One background TCC read, deduped by the `refreshing` gate. Never call while
    /// holding `lock` (it takes it itself — the "never nest" rule).
    private static func kickRefresh() {
        let go: Bool = lock.withLock {
            if refreshing { return false }
            refreshing = true
            return true
        }
        guard go else { return }
        refreshQueue.async {
            let trusted = AXIsProcessTrusted()
            lock.withLock {
                cached = trusted
                hasValue = true
                lastCheckNs = DispatchTime.now().uptimeNanoseconds
                refreshing = false
            }
        }
    }

    /// Mark the cached answer stale AND start the refresh right away, so the value
    /// converges within a background round trip instead of waiting for a reader.
    /// The cached value is deliberately KEPT (a reader still gets an answer); the
    /// paths that must not be wrong about a revoke — watchdog, tapDisabledBy* —
    /// call AXIsProcessTrusted() directly.
    static func invalidateCache() {
        lock.withLock { lastCheckNs = 0 }
        kickRefresh()
    }

    /// Synchronous, cache-bypassing read for UI paths (the Settings banner). NEVER
    /// call this from the keystroke path — that is what `isTrusted` and its cache are
    /// for. The distinction matters: a stale-TTL read of `isTrusted` returns
    /// `.serveCachedAndRefresh`, i.e. it hands back the OLD value and only converges
    /// on a background round trip. That is correct for a keystroke (a microsecond of
    /// staleness, and the paths that must not be wrong read TCC directly) and wrong
    /// for a banner the user is staring at one second after ticking the checkbox in
    /// System Settings: nothing re-reads afterwards, so the warning kept claiming
    /// "no permission" until some later event happened to make the window key again.
    @discardableResult
    static func readTrustNow() -> Bool {
        #if DEBUG
        if let forced = testTrustOverride { return forced }
        #endif
        return syncRefresh()
    }

    #if DEBUG
    /// Test seams: drive the cache without a live TCC grant.
    static func _testSetTrustCache(_ value: Bool) {
        lock.withLock {
            cached = value
            hasValue = true
            lastCheckNs = DispatchTime.now().uptimeNanoseconds
            refreshing = false
        }
    }
    static func _testForgetTrustCache() {
        lock.withLock {
            cached = false
            hasValue = false
            lastCheckNs = 0
            refreshing = false
        }
    }
    static var _testTrustCached: Bool { lock.withLock { cached } }
    static var _testTrustIsFresh: Bool { lock.withLock { lastCheckNs != 0 } }
    #endif

    /// GROUND TRUTH for "may I actually post/tap?", unlike `AXIsProcessTrusted()`.
    /// In the stale-grant state AXIsProcessTrusted keeps answering TRUE (Settings shows
    /// the checkbox on, the stored TCC requirement no longer matches this binary), while
    /// the privilege-specific preflight answers correctly — this is what Apple DTS
    /// recommends over the AX call (developer.apple.com/forums/thread/727984, and the
    /// Sequoia case in thread 758554 where tapCreate returned NULL with AX true).
    /// Not cached and not on the keystroke path: called at launch and when a tap fails.
    static var canPostEvents: Bool { CGPreflightPostEventAccess() }
    static var canListenEvents: Bool { CGPreflightListenEventAccess() }

    /// The stale-grant fingerprint: macOS says we're trusted, but the privilege the tap
    /// needs is refused. Either half alone is a normal state (not granted yet / all good).
    static var grantLooksStale: Bool { AXIsProcessTrusted() && !CGPreflightPostEventAccess() }

    /// RESET this app's own TCC rows so the next prompt writes a FRESH row against the
    /// CURRENT code signature — the programmatic equivalent of the minus-button dance we
    /// used to ask users to perform by hand. `tccutil reset <service> <bundle-id>` is
    /// scoped to one bundle id (Quinn, developer.apple.com/forums/thread/696174) and
    /// needs no privileges to reset YOURSELF; it can only ever REMOVE a grant, never
    /// give one. Kept behind an explicit user action (never silent, never on a timer) —
    /// Apple has said they may restrict tccutil if apps abuse it to re-nag users.
    /// Returns true when the reset command succeeded.
    @discardableResult
    static func resetOwnGrant() -> Bool {
        let id = OwnBundle.id
        var ok = false
        // Accessibility covers the tap; ListenEvent (Input Monitoring) can hold a stale
        // row of its own, and resetting a service we never used is a no-op.
        for service in ["Accessibility", "ListenEvent"] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", service, id]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do {
                try p.run()
                p.waitUntilExit()
                DebugLog.log("tccutil reset \(service) \(id) → exit \(p.terminationStatus)")
                if service == "Accessibility" { ok = p.terminationStatus == 0 }
            } catch {
                DebugLog.log("tccutil reset \(service) failed to launch: \(error.localizedDescription)")
            }
        }
        invalidateCache()
        return ok
    }

    /// Prompt for Accessibility permission (opens System Settings). Safe when already
    /// trusted (returns true, no prompt).
    ///
    /// A build that is NOT signed with our Developer ID must never prompt: the row macOS
    /// then writes pins THAT build's identity (an ad-hoc signature pins the cdhash), and
    /// every properly signed release afterwards is refused while the checkbox still shows
    /// allowed — the permanently-stuck state, created by us. `project.yml` builds ad-hoc
    /// (`CODE_SIGN_IDENTITY: "-"`) so a plain `xcodebuild` run of the app can reach here.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        invalidateCache()
        if AXIsProcessTrusted() { return true }
        guard isOurSignedBuild else {
            DebugLog.log("skip AX prompt: this build is not Developer ID-signed by our team "
                + "(would poison the TCC row for every signed release)")
            return false
        }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Team identifier of the RUNNING code, or nil (ad-hoc / unsigned).
    static var ownTeamIdentifier: String? {
        var codeRef: SecCode?
        guard SecCodeCopySelf([], &codeRef) == errSecSuccess, let code = codeRef else { return nil }
        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(code as! SecStaticCode, [], &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else { return nil }
        return info["teamid"] as? String
    }
    static var isOurSignedBuild: Bool { ownTeamIdentifier == "84T567KMYD" }
}

/// Cached frontmost-app bundle id. `NSWorkspace.shared.frontmostApplication` is an
/// XPC round-trip and was being called on EVERY keystroke in both the tap callback
/// (where slowness trips tapDisabledByTimeout) and the IMKit controller. App
/// activation is an event, not a per-key question — observe it once and read a
/// plain property on the hot path. All access is on the main thread (the tap's run
/// loop source and NSWorkspace notifications both live there).
final class FrontmostApp {
    static let shared = FrontmostApp()

    /// Locked: written by the NSWorkspace observer on MAIN, read per-key on the TAP
    /// thread (and by the controller on main).
    private let lock = NSLock()
    private var _bundleID: String?
    var bundleID: String? { lock.withLock { _bundleID } }

    /// Most-recently-activated apps (newest first, distinct), EXCLUDING VietTelex
    /// itself — so Settings can offer "recent apps" to pin without typing a bundle id.
    /// MAIN-thread only (observer writes, Settings UI reads) — no lock needed.
    private(set) var recent: [(id: String, name: String)] = []
    private static let selfID = OwnBundle.id

    private init() {
        _bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let self else { return }
            self.lock.withLock { self._bundleID = app?.bundleIdentifier }
            // New app in front → new focused field: both AX verdicts are about the OLD
            // field until their scans re-run.
            FocusedFieldDetector.invalidate()
            SecureFieldDetector.invalidate()
            guard let id = app?.bundleIdentifier, id != Self.selfID else { return }
            self.recent.removeAll { $0.id == id }
            self.recent.insert((id, app?.localizedName ?? id), at: 0)
            if self.recent.count > 10 { self.recent.removeLast() }
        }
    }
}

/// TTL backoff shared by the three AX/window-list verdict caches below. While the user
/// types continuously each detector's TTL expires over and over (200-300ms), so a long
/// typing run pays ~8 cross-process AX round trips per second on background queues for
/// answers that never change — the focused field is the same field. So: once a detector
/// has re-confirmed the SAME verdict `threshold` times in a row, double its TTL per extra
/// confirmation up to `capNs`. Any verdict CHANGE or an `invalidate()` (focus/app switch)
/// resets the run, so the responsiveness that matters — the first scan after a focus
/// change — is untouched: it always runs at the base TTL.
enum DetectorBackoff {
    /// Never let a verdict go stale for longer than this, however stable it looked.
    static let capNs: UInt64 = 1_000_000_000
    /// Consecutive identical verdicts before the TTL starts growing.
    static let threshold = 3

    static func ttl(base: UInt64, stableRuns: Int) -> UInt64 {
        guard base > 0, stableRuns >= threshold else { return min(base, capNs) }
        // Bounded shift (never let `base << n` overflow), then clamp to the cap.
        let doublings = min(stableRuns - threshold + 1, 16)
        let grown = base << UInt64(doublings)
        return grown >= capNs || grown < base ? capNs : grown
    }
}

/// Spotlight is a system overlay, not the frontmost APP — its bundle id never shows
/// up in NSWorkspace.frontmostApplication. Detect it by scanning the
/// on-screen window list for a window owned by the "Spotlight" process.
enum SpotlightDetector {
    // CGWindowListCopyWindowInfo enumerates every on-screen window — too heavy to run
    // on the keystroke path (it slowed the tap callback enough to trip
    // tapDisabledByTimeout, leaking keys to the broken IMKit path → intermittent
    // garbage). Cache the result with a short TTL; Spotlight visibility doesn't change
    // per keystroke, so a ~200ms lag is invisible.
    //
    // The scan NEVER runs synchronously on the keystroke: isVisible always returns the
    // cached bool immediately, and when the TTL has expired it kicks ONE background
    // refresh (utility queue) whose result lands back on main. So a fresh scan is
    // observed on the NEXT keystroke, not this one — visibility lags at most one key.
    // That is acceptable: Spotlight open/close is a deliberate user action, never
    // simultaneous with typing into it, so being one keystroke stale is invisible while
    // removing a multi-ms spike from the hot path.
    //
    // Threading: read on both the TAP thread (per key) and MAIN (controller), refresh
    // result lands from the utility queue — so the cached bool + timestamp +
    // `refreshing` gate all live under one lock. Only the CGWindowList call itself
    // runs outside it.
    private static let lock = NSLock()
    private static var cached = false
    private static var lastCheckNs: UInt64 = 0
    private static var refreshing = false
    /// Consecutive identical verdicts — see DetectorBackoff.
    private static var stableRuns = 0
    private static let ttlNs: UInt64 = 200_000_000
    private static let scanQueue = DispatchQueue(label: "com.viettelex.spotlight-scan", qos: .utility)

    /// IMKit just activated the Spotlight client — authoritative proof the overlay
    /// is up. Stamp the cache TRUE immediately instead of waiting for a keystroke
    /// to kick a CGWindowList scan: a fast first burst arrives before any scan
    /// lands (field repro 2026-07-31: "pas" — the tone key emitted into the overlay
    /// while the cache still said false), and the overlay-raw gate in the tap
    /// callback depends on this value. Backoff resets so the close is re-scanned
    /// at the base TTL.
    static func noteFocused() {
        lock.withLock {
            cached = true
            lastCheckNs = DispatchTime.now().uptimeNanoseconds
            stableRuns = 0
        }
    }

    /// IMKit just activated a DIFFERENT client — authoritative proof the overlay is
    /// gone (closed, or lost keyboard focus to whatever's behind it): macOS would not
    /// route activateServer to another client while Spotlight still owned the
    /// keyboard. Same reasoning as `noteFocused()`, opposite direction. Without this,
    /// DetectorBackoff's growing TTL (built up while Spotlight sat open and stable)
    /// can leave `isVisible` reporting stale-true for 500ms+ after close — long
    /// enough for the tap's overlay-raw gate to keep raw-passthrough-ing the first
    /// several keystrokes of the NEXT word into whatever app now has focus (field
    /// report 2026-08-11: typing "được" in Chrome's omnibox right after closing
    /// Spotlight → "dduwợc", the first four keys landing raw before the stale cache
    /// finally caught up).
    static func noteUnfocused() {
        lock.withLock {
            cached = false
            lastCheckNs = DispatchTime.now().uptimeNanoseconds
            stableRuns = 0
        }
    }

    #if DEBUG
    static func _testSetVisible(_ value: Bool) {
        lock.withLock {
            cached = value
            lastCheckNs = DispatchTime.now().uptimeNanoseconds
        }
    }
    /// Read the cache WITHOUT kicking a refresh (a plain `isVisible` read would).
    static var _testVisible: Bool { lock.withLock { cached } }
    #endif

    static var isVisible: Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let (stale, value): (Bool, Bool) = lock.withLock {
            let ttl = DetectorBackoff.ttl(base: ttlNs, stableRuns: stableRuns)
            let needsRefresh = now &- lastCheckNs >= ttl && !refreshing
            if needsRefresh { refreshing = true }
            return (needsRefresh, cached)
        }
        if stale {
            scanQueue.async {
                let visible = scan()                       // heavy call, off the hot path
                lock.withLock {
                    stableRuns = visible == cached ? stableRuns + 1 : 0
                    cached = visible
                    lastCheckNs = DispatchTime.now().uptimeNanoseconds
                    refreshing = false
                }
            }
        }
        return value
    }

    private static func scan() -> Bool {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        for w in windows {
            // WATCH-ITEM: matches the owning process name literally. This is
            // version-sensitive — a macOS release that renames the Spotlight process
            // would silently break detection (Spotlight edits fall back to Backspace
            // mode) with no error. Revisit if Spotlight support regresses on a new OS.
            if let owner = w[kCGWindowOwnerName as String] as? String, owner == "Spotlight" {
                // Owner name alone is NOT enough: on macOS 15 the menu-bar Spotlight
                // icon is itself an on-screen window owned by "Spotlight" (~40×24,
                // present permanently), so the detector read "Spotlight open" on
                // every keystroke (issue #26 debug log: spotlightVisible=true
                // throughout). Require panel-sized bounds — the real search panel
                // measures ~640pt wide even collapsed; the icon never comes close.
                if let dict = w[kCGWindowBounds as String] as? [String: Any],
                   let width = dict["Width"] as? CGFloat, width >= 300 {
                    return true
                }
            }
        }
        return false
    }
}

/// Is the FOCUSED field a password field? `IsSecureEventInputEnabled()` only covers
/// apps that switch on secure event input (login window, Keychain Access, `sudo` in a
/// terminal, native NSSecureTextField). A web `<input type="password">` normally does
/// NOT — so without this check the engine happily composes inside a browser login form,
/// and any edit strategy that types placeholder/selection keys writes visible junk into
/// the password the user cannot proofread (field report 2026-07-27: "điền password thấy
/// nó inject thêm 1-2 ký tự" — the `.emptyReset` strategy posts U+202F to cancel inline
/// autocomplete, which is exactly one extra character).
///
/// Accessibility exposes it as the SUBROLE `AXSecureTextField` (AppKit's
/// NSSecureTextField and the WebKit/Chromium mapping for password inputs both use it).
/// Same threading/caching shape as FocusedFieldDetector: the AX read never runs on a
/// keystroke, and "unknown" is answered conservatively (see `isSecure`).
enum SecureFieldDetector {
    private static let lock = NSLock()
    private static var cached = false
    private static var lastCheckNs: UInt64 = 0
    private static var refreshing = false
    /// Consecutive identical verdicts — see DetectorBackoff.
    private static var stableRuns = 0
    private static let ttlNs: UInt64 = 300_000_000        // 300ms: focus changes must be seen fast
    private static let scanQueue = DispatchQueue(label: "com.viettelex.secure-scan", qos: .userInitiated)

    /// True when the focused field is a password field. Cached with a short TTL and
    /// refreshed in the background; a focus change is therefore seen at most one
    /// keystroke late — and the first character of a password is the one case where a
    /// stale "false" is harmless (a single letter cannot compose into anything yet: the
    /// engine only rewrites text from the SECOND key of a syllable onward).
    static var isSecure: Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let (stale, value): (Bool, Bool) = lock.withLock {
            let ttl = DetectorBackoff.ttl(base: ttlNs, stableRuns: stableRuns)
            let needsRefresh = now &- lastCheckNs >= ttl && !refreshing
            if needsRefresh { refreshing = true }
            return (needsRefresh, cached)
        }
        if stale {
            scanQueue.async {
                let secure = scan()
                lock.withLock {
                    stableRuns = secure == cached ? stableRuns + 1 : 0
                    cached = secure
                    lastCheckNs = DispatchTime.now().uptimeNanoseconds
                    refreshing = false
                }
            }
        }
        return value
    }

    /// Forget the cached answer (focus/app switch) so the next read re-scans. Unlike
    /// FocusedFieldDetector this does NOT force the answer to a safe default, because the
    /// risk here is asymmetric the other way: a stale `true` costs one raw-ASCII keystroke
    /// in a normal field, while forcing `true` on every app switch would drop the first
    /// Vietnamese character every time. A stale `false` for one key is harmless — the
    /// engine only starts REWRITING text from the second key of a syllable.
    /// Also drops the TTL backoff: the new field must be scanned at the base TTL.
    static func invalidate() { lock.withLock { lastCheckNs = 0; stableRuns = 0 } }

    #if DEBUG
    static func _testSetCached(_ value: Bool) {
        lock.withLock {
            cached = value
            lastCheckNs = DispatchTime.now().uptimeNanoseconds
        }
    }
    static var _testCached: Bool { lock.withLock { cached } }
    static var _testIsFresh: Bool { lock.withLock { lastCheckNs != 0 } }
    #endif

    private static func scan() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.05)
        var subroleRef: CFTypeRef?
        let ok = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success
        return isSecureSubrole(ok ? subroleRef as? String : nil)
    }

    /// The subrole test, split out so it can be pinned by tests. ONLY an explicit
    /// password subrole counts: a missing/unknown subrole must read as "not secure", or a
    /// browser that fails to answer would silently stop composing Vietnamese everywhere.
    static func isSecureSubrole(_ subrole: String?) -> Bool {
        subrole == "AXSecureTextField"
    }
}

/// Per-FIELD mode resolution for apps pinned to `.axDetect` (Bảng chế độ gõ →
/// "Tự dò theo ô"): a browser's address/search bar needs selection-replace (its
/// inline autocomplete races in-place edits — the Safari smart-search bug), while
/// fields INSIDE the page work best on the fast IMKit in-place path. Distinguish
/// them structurally through the Accessibility tree: walk the focused element's
/// ancestors — hit AXWebArea → page content (in-place); hit AXToolbar → a chrome/
/// toolbar field (selection). Unknown → selection, the mode that works everywhere
/// (same "when unsure, pick what always works" rule as the probe).
///
/// Same threading/caching design as SpotlightDetector: the AX walk (cross-process,
/// 50ms-capped calls) never runs on a keystroke — reads return the cached verdict
/// and kick ONE background refresh when the 200ms TTL lapses, so a focus change is
/// seen at most one keystroke late. Cache + gate live under one lock (read on both
/// the tap thread and main).
enum FocusedFieldDetector {
    private static let lock = NSLock()
    private static var cached = true            // unknown → selection (always works)
    /// Canvas-editor field (Google Docs): must be typed with marked text — in-place
    /// appends garbage and the tracked ⌫ dies (see scan()). Rides the same scan/TTL/
    /// invalidation as `cached`; served by `wantsMarkedField` without kicking its own
    /// refresh (every browser keystroke already reads `wantsSelection` first).
    private static var cachedMarked = false

    /// First web-area host seen by the last scan — DIAGNOSTIC ONLY, never read by any
    /// routing decision. Lets a debug log line name the actual site when something
    /// goes wrong on a host the routing policy has no special case for yet.
    private static var cachedHost: String?
    private static var lastCheckNs: UInt64 = 0
    private static var refreshing = false
    /// Consecutive identical verdicts — see DetectorBackoff. Separate counters for the
    /// two verdicts this type caches (selection-replace and "is a real text input").
    private static var stableRuns = 0
    private static var stableTextRuns = 0
    private static let ttlNs: UInt64 = 200_000_000
    private static let scanQueue = DispatchQueue(label: "com.viettelex.field-scan", qos: .userInitiated)

    /// Forget the cached verdict — the FIELD changed (app switch / new IMKit focus), so the
    /// previous field's answer is not evidence about this one. Resets to `false` (in-place)
    /// rather than the `true` default on purpose: carrying a stale "selection-replace" into
    /// a page field is what made the tap Shift+Left-select the text and overtype it — the
    /// user sees their input highlighted and can only replace one character, until they
    /// click away and back (tester report 2026-07-28, v1.4.17: "bấm vào ô input ở trên
    /// trình duyệt thì nó thành bôi đen, rồi gõ chỉ replace"). In-place for the one
    /// keystroke before the async scan answers is the mild failure; selection is not.
    /// Also drops the TTL backoff (both verdicts): the new field must be re-scanned at
    /// the base TTL, however stable the previous field's answer had become.
    static func invalidate() {
        lock.withLock {
            cached = false
            // Same asymmetry as `cached`: one keystroke of in-place in a Docs canvas
            // is the mild failure; forcing marked into an unknown field is not.
            cachedMarked = false
            cachedHost = nil
            lastCheckNs = 0
            stableRuns = 0
            // Backoff only — the timestamps/values of the isTextInput verdict keep the
            // shipped semantics untouched.
            stableTextRuns = 0
        }
    }

    /// Kick ONE background verdict scan NOW instead of waiting for the first
    /// keystroke to do it. Issue #32 follow-up (field report 2026-08-12, v1.5.5):
    /// activateServer → invalidate() resets the verdict to false (page content, the
    /// safe default), and the re-scan used to be kicked only by the FIRST keystroke's
    /// `wantsSelection` read — landing 77–500ms later. Every first word after
    /// refocusing a browser therefore ran on the stale default: an omnibox was
    /// treated as page content, a tone key inside that window emitted a bare
    /// Backspace burst into the omnibox, and inline autocomplete ate the ⌫
    /// ("được" → "ddược", the historical "gooogle" class). Prefetching at
    /// activation means the scan typically lands during the user's focus-to-first-
    /// key gap (~350ms in the field trace) instead of after the first key.
    /// Implementation: a plain read — invalidate() zeroed `lastCheckNs`, so the
    /// read observes staleness and kicks the dedup-guarded async scan.
    static func prefetch() { _ = wantsSelection }

    #if DEBUG
    /// TRUE once a scan (or a test seam) has stamped the cache since the last
    /// invalidate() — lets a test observe that prefetch() really kicked a scan.
    static var _testIsFresh: Bool { lock.withLock { lastCheckNs != 0 } }
    /// Test seam: set the cached verdict AND stamp it fresh, so the invalidation contract
    /// can be pinned without a live Accessibility tree (the scan itself needs one).
    static func _testSetCached(_ value: Bool) {
        lock.withLock {
            cached = value
            lastCheckNs = DispatchTime.now().uptimeNanoseconds
        }
    }
    /// Read the cache WITHOUT kicking a refresh (a plain `wantsSelection` read would).
    static var _testCached: Bool { lock.withLock { cached } }
    /// Same seam for the canvas-editor (marked) verdict.
    static func _testSetMarked(_ value: Bool) {
        lock.withLock {
            cachedMarked = value
            lastCheckNs = DispatchTime.now().uptimeNanoseconds
        }
    }
    /// Same seam for the diagnostic-only host string.
    static func _testSetHost(_ value: String?) {
        lock.withLock {
            cachedHost = value
            lastCheckNs = DispatchTime.now().uptimeNanoseconds
        }
    }
    #endif

    /// True → the focused field is a canvas editor (Google Docs) that must be typed
    /// with marked text. Cache-only read: refreshes piggyback on `wantsSelection`,
    /// which every browser keystroke reads first (tap routing then IMKit routing).
    static var wantsMarkedField: Bool { lock.withLock { cachedMarked } }


    /// Diagnostic-only: the host last seen for the focused field, or nil (not a web
    /// area, or the AX read failed). Never consulted by routing — see `cachedHost`.
    static var debugLastHost: String? { lock.withLock { cachedHost } }

    /// True → the focused field should use selection-replace; false → in-place.
    static var wantsSelection: Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let (stale, value): (Bool, Bool) = lock.withLock {
            let ttl = DetectorBackoff.ttl(base: ttlNs, stableRuns: stableRuns)
            let needsRefresh = now &- lastCheckNs >= ttl && !refreshing
            if needsRefresh { refreshing = true }
            return (needsRefresh, cached)
        }
        if stale {
            scanQueue.async {
                pokeChromiumAX()
                let (wants, marked, host) = scan()
                // Diagnostic (debug logging only, and off the keystroke path): WHY this
                // verdict. A browser whose AX tree we cannot read falls back to
                // selection-replace for EVERY field — including page content, where each
                // tone edit then shows as a visible flicker (Zen report 2026-07-27, where
                // pinning the app to in-place was "cực kì mượt"). Without the role chain in
                // the log there is no way to tell "toolbar, correctly detected" from "read
                // nothing, guessed". Role names only — never text or values. `host` names
                // the site for a future report on an unrecognized editor (2026-08-06).
                if AppState.shared.debugLogging {
                    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
                    DebugLog.log("field-scan \(front): wantsSelection=\(wants) marked=\(marked) host=\(host ?? "?") roles=[\(roleChain())]")
                }
                lock.withLock {
                    stableRuns = (wants == cached && marked == cachedMarked) ? stableRuns + 1 : 0
                    cached = wants
                    cachedMarked = marked
                    cachedHost = host
                    lastCheckNs = DispatchTime.now().uptimeNanoseconds
                    refreshing = false
                }
            }
        }
        return value
    }

    /// Chromium builds its web-content AX tree only when an assistive client
    /// announces itself — on a machine where nothing ever has, the focused-element
    /// read fails, scan() falls back to "unknown → selection", and a YouTube/
    /// Facebook field gets the selection-replace path whose overtype the web
    /// editor swallows (issue #26: 1.4.11's AXWebArea fix never got to run;
    /// dev machines passed because test tooling had already poked Chrome).
    /// Setting AXManualAccessibility=true on the app element flips the tree on
    /// without VoiceOver side effects (the standard EVKey/Electron switch; apps
    /// that don't know the attribute just return an error). Once per pid, on the
    /// scan queue — never the keystroke path. The tree takes a beat to build, so
    /// the first refresh after the poke may still default to selection; the next
    /// 200ms tick sees the real roles.
    private static var pokedPids = Set<pid_t>()   // guarded by `lock`
    private static func pokeChromiumAX() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              AppState.shared.usesAxDetect(app.bundleIdentifier) else { return }
        pokeFrontmostLazyAX()
    }

    /// Once-per-pid AXManualAccessibility poke for the FRONTMOST app, whatever its
    /// routing. Tap-routed Electron apps need it too: Discord never gets field scans
    /// (those run for axDetect browsers only), so its lazy AX tree stayed OFF and
    /// `AXTextEdit.readCaret()` returned nil — the ⌫ re-open of issue #40 died on
    /// "no AX caret" while the same feature worked in iTerm (real AX) and Chrome
    /// (poked by every field scan). Called from markActive via a background queue
    /// when the re-edit gate is on — never the keystroke path. Apps that don't know
    /// the attribute just return an error; the tree takes a beat to build, so the
    /// FIRST attempt after activation may still miss — the next one sees it.
    static func pokeFrontmostLazyAX() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        guard lock.withLock({ pokedPids.insert(pid).inserted }) else { return }
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.05)
        AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Pure gate for the markActive poke: only when a reach-back feature (re-edit /
    /// ⌫ re-open — one toggle) can actually use the tree, and only for apps whose
    /// keys the tap composes (axDetect browsers are already poked by field scans).
    static func lazyAXPokeWanted(reEditEnabled: Bool, routesTap: Bool) -> Bool {
        reEditEnabled && routesTap
    }

    // MARK: is the focused element a REAL text input? (remote-desktop per-field)
    //
    // Remote-desktop apps forward raw scancodes for the SESSION canvas, but their own
    // chrome (PC-name field, search box) is ordinary Cocoa text input where the IME
    // works fine. Distinguish by the focused element's role. Unknown/unavailable →
    // NOT a text input, i.e. passthrough — misclassifying the canvas as a field would
    // compose garbage into the guest OS, while the reverse merely keeps the status quo
    // (no Vietnamese in a name field).
    private static var cachedTextInput = false
    private static var lastTextCheckNs: UInt64 = 0
    private static var refreshingText = false
    private static let textInputRoles: Set<String> =
        ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]

    static var isTextInput: Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let (stale, value): (Bool, Bool) = lock.withLock {
            let ttl = DetectorBackoff.ttl(base: ttlNs, stableRuns: stableTextRuns)
            let needsRefresh = now &- lastTextCheckNs >= ttl && !refreshingText
            if needsRefresh { refreshingText = true }
            return (needsRefresh, cachedTextInput)
        }
        if stale {
            scanQueue.async {
                let isText = scanTextInput()
                lock.withLock {
                    stableTextRuns = isText == cachedTextInput ? stableTextRuns + 1 : 0
                    cachedTextInput = isText
                    lastTextCheckNs = DispatchTime.now().uptimeNanoseconds
                    refreshingText = false
                }
            }
        }
        return value
    }

    private static func scanTextInput() -> Bool {
        guard let element = focusedElementForScan() else { return false }
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String
        else { return false }
        return textInputRoles.contains(role)
    }

    /// Focused element with the 50ms timeout, or nil (untrusted / no focus). Shared
    /// by both scans. Tries system-wide first, then the frontmost APP element: on
    /// some machines the system-wide read fails against Chrome (kAXErrorCannotComplete,
    /// verified live 2026-07-30) while the app-scoped read answers fine — without the
    /// fallback every Chrome field on such a machine reads "no-focused-element" and
    /// lands in the selection fallback, which page editors swallow (Google Docs
    /// "Quoocs" → "Quoôcốc" class).
    private static func focusedElementForScan() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) != .success {
            focusedRef = nil
            guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
            let appEl = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetMessagingTimeout(appEl, 0.05)
            guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success
            else { return nil }
        }
        guard let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.05)
        return element
    }

    /// The focused element's ancestor ROLES, joined — diagnostics only (see the caller).
    /// Diagnostic-only, dùng cho dòng "Chế độ gõ" trong menu (snapshot decision):
    /// chuỗi role của cây AX tính từ focused element. KHÔNG bao giờ chứa text/giá trị.
    static func debugRoleChain() -> String { roleChain() }

    private static func roleChain() -> String {
        guard var el = focusedElementForScan() else { return "no-focused-element" }
        var roles: [String] = []
        for _ in 0..<FocusedFieldDetector.maxAncestorHops {
            AXUIElementSetMessagingTimeout(el, 0.05)
            var r: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &r) == .success,
               let role = r as? String {
                roles.append(role)
                if role == "AXWebArea" || role == "AXToolbar" { break }
            } else {
                roles.append("?")
            }
            var p: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &p) == .success,
                  let par = p, CFGetTypeID(par) == AXUIElementGetTypeID() else {
                roles.append("no-parent"); break
            }
            el = par as! AXUIElement
        }
        return roles.joined(separator: "→")
    }

    private static func scan() -> (selection: Bool, marked: Bool, host: String?) {
        guard let focused = focusedElementForScan() else { return (selection: true, marked: false, host: nil) }
        // NO role short-circuit on the focused element: an AXComboBox/AXSearchField
        // rule used to run BEFORE the ancestor walk ("a search box inside a web area
        // is autocomplete-prone"), but field evidence killed it — youtube.com's search
        // box (ARIA combobox → AXComboBox) and facebook.com's composer sit INSIDE the
        // page, where the web editor (React/Lexical/EditContext) swallows the synthetic
        // overtype keyDown: Shift+Left selects the vowels and the replacement never
        // lands, leaving them highlighted. In-page suggestion dropdowns are not
        // in-field inline autocomplete, so the backspace race the rule guarded against
        // doesn't exist there — AXWebArea must win. Outside a web area the rule was
        // redundant anyway: the walk's fallback is selection-replace.
        var roleRef: CFTypeRef?
        var element = focused
        // Selection verdict: the FIRST decisive ancestor wins (toolbar → omnibox,
        // web area → page content). Marked verdict: canvas editors (Google Docs)
        // render from their OWN event stream and ignore replacementRange — in-place
        // inserts append and the tracked ⌫ rewrite "succeeds" invisibly on the hidden
        // input (field report 2026-07-30: "Quoocs" → "Quoôcốc", Delete dead). They
        // speak composition events fine, so a Docs field forces marked. The hidden
        // input sits in a NESTED iframe whose own web area may report about:blank —
        // so after the first web area locks in-place, the walk CONTINUES upward and
        // any enclosing web area's URL may still prove Docs.
        var sawWebArea = false
        var marked = false
        // First web-area host seen — DIAGNOSTIC ONLY (never used for routing), so a
        // "stale caret" report names the actual site instead of just
        // "com.google.Chrome" (added after the 2026-08-06 unidentified-tab report).
        //
        // NOTE (policy 2026-08-06): there is deliberately NO per-host tap allowlist
        // here anymore. Page content routes to the TAP path BY POLICY in
        // AppState.gateRouting — the Docs/Discord/Zalo per-host patches of early
        // August all chased the same contract-free `insertText(replacementRange:)`
        // channel, and the Discord case proved the failure is undetectable from
        // inside (every self-report said honored while the visible text appended).
        // Only the marked-class exception (Google Docs) remains URL-based.
        var host: String?
        // Did the walk STOP because it ran out of hops, rather than because it reached
        // the top of the tree? See `exhaustedMeansPageContent` — that distinction is
        // what keeps a deep page from being mistaken for the omnibox.
        var hops = 0
        for _ in 0..<Self.maxAncestorHops {
            hops += 1
            AXUIElementSetMessagingTimeout(element, 0.05)
            roleRef = nil
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, let verdict = Self.roleDecision(role) {
                if verdict {
                    // Toolbar: decisive only BEFORE any web area (an omnibox is never
                    // inside page content — above one, it's just browser chrome).
                    if !sawWebArea { return (selection: true, marked: false, host: nil) }
                } else {
                    sawWebArea = true
                    if !marked {
                        var urlRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &urlRef) == .success {
                            let url = urlRef as? URL
                            if host == nil { host = url?.host }
                            marked = Self.markedFieldURL(url)
                        }
                    }
                    if marked { break }   // verdicts settled
                }
            }
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef, CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { break }
            element = parent as! AXUIElement
        }
        if sawWebArea { return (selection: false, marked: marked, host: host) }
        // No decisive ancestor. A walk that DIED ON THE HOP BUDGET is page content, not
        // chrome (see exhaustedMeansPageContent); one that reached the top without a
        // web area is genuinely unknown → selection, the historical safe default.
        return (selection: !Self.exhaustedMeansPageContent(hops: hops),
                marked: false, host: nil)
    }

    /// Pure: does this web-area URL host an editor that must be typed with marked
    /// text? Google Docs (canvas) + tiktok.com (comment box — field report maintainer
    /// 19/08/2026: Safari page content đi in-place theo carve-out WebKit #44 nhưng
    /// editor của TikTok áp edit theo model JS riêng → mỗi tone edit bị APPEND
    /// ("chuủ tichịch"); tap thì Safari nuốt synthetic trong page content — kênh
    /// đúng còn lại là marked). Widen only with field evidence.
    static func markedFieldURL(_ url: URL?) -> Bool {
        guard let url, let host = url.host else { return false }
        if host == "docs.google.com" && url.path.hasPrefix("/document") { return true }
        return host == "tiktok.com" || host.hasSuffix(".tiktok.com")
    }

    /// Ancestor-walk hop budget. 12 → 24 after field report 2026-07-30 (J2TeamNNL,
    /// 1.4.22): a React composer's AXTextArea sat under ≥11 AXGroups, the walk ran out
    /// of hops BEFORE reaching AXWebArea and fell back to selection-replace, whose
    /// synthetic overtype the web editor swallows ("không gõ được dấu"). 24 → 64 after
    /// the SAME failure recurred 2026-08-14 on facebook.com's comment box, whose chain
    /// is exactly 24 deep (AXTextArea → 6×AXGroup → AXTable → 16×AXGroup → …). Raising
    /// the number is only half a fix — see `exhaustedMeansPageContent` for the rule
    /// that stops this class of bug from returning a third time.
    ///
    /// Cost stays bounded: the walk STOPS at the first decisive ancestor, so only a
    /// genuinely deep page pays for the extra hops, and every refresh runs on the
    /// backoff-limited scan queue (50ms timeout per call), never the keystroke path.
    static let maxAncestorHops = 64

    /// A walk that used up its whole hop budget without finding a decisive ancestor is
    /// PAGE CONTENT, not browser chrome — the structural fact behind it: an omnibox is
    /// SHALLOW (address bar ≈ AXTextField → AXGroup → AXToolbar, a handful of hops),
    /// while only a web document nests dozens of AXGroups deep. Twice now a deep page
    /// exhausted the budget and inherited the "unknown → selection" default, which
    /// hands page content the omnibox strategy — the exact channel web editors swallow
    /// (2026-07-30 React composer, 2026-08-14 Facebook comment box, where it also made
    /// the ⌫ re-open of issue #40 refuse: emitMode came out .emptyReset).
    ///
    /// So the fallback splits by WHY the walk ended: out of hops → page content; top of
    /// tree reached with no web area → genuinely unknown → selection (unchanged).
    /// Pure so the rule is pinned by tests.
    static func exhaustedMeansPageContent(hops: Int) -> Bool { hops >= maxAncestorHops }

    /// One ancestor's vote: page content composes in-place, the browser chrome
    /// (address/search bar) needs selection-replace, anything else keeps walking.
    /// Pure so the polarity is pinned by tests.
    static func roleDecision(_ role: String) -> Bool? {
        if role == "AXWebArea" { return false }   // page content → in-place
        if role == "AXToolbar" { return true }    // address/search bar → selection
        return nil
    }

    /// Pure mirror of scan()'s walk over an already-collected role chain — first
    /// decisive ancestor wins. An undecided chain falls back to selection (the safer
    /// default for the omnibox, where a missed detection breaks every word) UNLESS it
    /// filled the hop budget, which only page content can do (see
    /// `exhaustedMeansPageContent`).
    static func chainDecision<S: Sequence>(_ roles: S) -> Bool where S.Element == String {
        var hops = 0
        for role in roles {
            hops += 1
            if let verdict = roleDecision(role) { return verdict }
            if hops >= maxAncestorHops { break }
        }
        return !exhaustedMeansPageContent(hops: hops)
    }
}

/// How a tone edit is emitted to the app:
/// - `backspace`: Backspace ×N then type (terminals).
/// - `selection`: Shift+Left ×N to select then overtype (Chromium omnibox / Spotlight
///   — where inline autocomplete offsets a plain Backspace).
/// - `emptyReset`: insert U+202F to cancel the inline suggestion, then Backspace ×(N+1)
///   (delete the U+202F too) and type (MS Office — where Shift+Left would select the
///   adjacent cell instead of characters). Only when there IS text to retype: on a pure
///   deletion the placeholder has nothing to protect and only flashes on screen.
enum TapEmit { case backspace, selection, emptyReset }

/// D1 — replace trailing text via the Accessibility API instead of a posted-event
/// burst. For a Chromium omnibox / Spotlight tone edit the `.selection` path posts
/// Shift+Left ×N then an overtype = 2(N+1) window-server round trips (~3ms each, so
/// ~25ms for a 3-char edit). ONE AX edit — set the selected range to the trailing N
/// chars, then set its text — does the same in a single out-of-process round trip.
///
/// ORDERING: the AX write mutates the field the instant it lands, so native letters
/// that already passed the tap and are still queued in the app can reorder against it
/// (the historical "nuwax"→"nuẵ" class). We can't track keys that already went native,
/// which is exactly why the caller gates this on `queueDrained()` and it sits behind a
/// flag. Within one key it is safe: the tap callback is serial and these AX calls are
/// synchronous, so the edit finishes before we return nil for the current keystroke.
enum AXTextEdit {
    /// Replace the `backspaces` chars before the caret with `text` on the system-wide
    /// focused element. Every AX call is checked — ANY failure returns false so the
    /// caller falls back to the posted-events path; returns true only when BOTH the
    /// range set and the text set succeeded.
    static func replaceTrailing(backspaces: Int, with text: String) -> Bool {
        guard backspaces > 0 else { return false }

        // Focused UI element (system-wide, so it works across app boundaries / overlays
        // like Spotlight).
        let systemWide = AXUIElementCreateSystemWide()
        // 50ms messaging timeout — the DEFAULT is seconds, and this runs inside the
        // tap callback: a busy/hung target would block the callback long enough for
        // macOS to disable the tap (leaked keys). Better to time out fast and fall
        // back to the posted-events path than to stall the tap.
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.05)   // same 50ms cap (not inherited)

        // Current selection (normally a caret: length 0). Read it as an AXValue wrapping
        // a CFRange so we know the caret location to reach back from.
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef, CFGetTypeID(rangeVal) == AXValueGetTypeID()
        else { return false }
        var selected = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &selected) else { return false }

        // Target = the N chars before the caret, plus any existing (non-caret) selection.
        // Guard against underflow: if the caret sits at/inside the first N chars we can't
        // reach back that far — bail so the caller uses the posted-events path.
        guard selected.location >= backspaces else { return false }
        var target = CFRange(location: selected.location - backspaces,
                             length: backspaces + selected.length)
        guard let targetVal = AXValueCreate(.cfRange, &target) else { return false }

        // Select the target range, then overwrite it with `text` — one coherent edit.
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, targetVal) == .success
        else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    /// Caret location (0-length selection start) of the system-wide focused element,
    /// or nil on any failure/timeout — same 50ms budget as every other tap-thread AX
    /// call. Factored out of `replaceTrailing` for the re-edit-word feature (below),
    /// which needs the caret WITHOUT immediately writing anything.
    static func readCaret() -> Int? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.05)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef, CFGetTypeID(rangeVal) == AXValueGetTypeID()
        else { return nil }
        var selected = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &selected), selected.length == 0
        else { return nil }   // a live selection (not a caret) — re-edit must not touch it
        return selected.location
    }

    /// Ground-truth read for the in-place probe: the ACTUAL text the focused element
    /// holds at `[start, start+length)`, via the Accessibility tree — a channel
    /// INDEPENDENT of the IMKit read-back (attributedSubstring / selectedRange) that
    /// some apps (Lark) fake or report inconsistently. Returns nil if AX is untrusted
    /// or any read fails, so the caller falls back to the read-back signals. Short 50ms
    /// messaging timeout: this runs on the IMKit key path.
    static func readString(at start: Int, length: Int) -> String? {
        guard start >= 0, length > 0, AXIsProcessTrusted() else { return nil }
        guard let element = focusedElement() else { return nil }
        var range = CFRange(location: start, length: length)
        guard let rangeVal = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, rangeVal, &result) == .success,
              let str = result as? String
        else { return nil }
        return str
    }

    /// Deferred-probe experiment: the focused element's total character count via
    /// kAXNumberOfCharacters. Content-independent append detector — an ignored
    /// replacementRange leaves the field `bs` chars LONGER than a compliant replace
    /// would. Log-only for now (see TelexInputController.reprobeDeferred).
    static func readLength() -> Int? {
        guard AXIsProcessTrusted(), let element = focusedElement() else { return nil }
        var numRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &numRef) == .success,
              let n = numRef as? Int
        else { return nil }
        return n
    }

    /// System-wide focused element with the 50ms messaging timeout applied (the
    /// DEFAULT is seconds; these calls run on key paths, so a hung target must time
    /// out fast). Shared by the read/write helpers above.
    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.05)
        return element
    }
}

enum SyntheticKeyboard {
    /// Stamp identifying events we post. "TLXTAP" packed into an Int64.
    static let magic: Int64 = 0x54_4C_58_54_41_50

    /// Private source with `magic` in its userData. The source's userData is what
    /// shows up as kCGEventSourceUserData on our events after they are posted and
    /// re-delivered — the mechanism the tap/IME use to recognize their own output.
    private static let source: CGEventSource? = {
        let src = CGEventSource(stateID: .privateState)
        src?.userData = magic
        return src
    }()

    /// True if `event` (CGEvent) is one we posted.
    ///
    /// Recognizing our own output is LOAD-BEARING for loop prevention: if it ever
    /// returns false for an event we posted, that event re-enters handle(), is fed to
    /// the engine as a real key, and emits MORE synthetic events → an unbounded storm
    /// that consumes every keystroke (dead keyboard, live mouse — the reported hang).
    /// So we check the ROBUST signal first: the posting process id. CGEvent.post stamps
    /// the emitting process's pid into `.eventSourceUnixProcessID`, and it round-trips
    /// reliably — unlike the source `userData` magic (which the file header notes is
    /// fragile, and which is simply absent if the private `source` failed to build).
    /// Only OUR process posts synthetic keys, so pid == getpid() is exact. The magic
    /// stays as a secondary check (harmless, and cheap belt-and-suspenders).
    static func isSynthetic(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return true }
        return event.getIntegerValueField(.eventSourceUserData) == magic
    }

    /// True if `event` (NSEvent, in IMKit handle()) is one we posted.
    static func isSynthetic(_ event: NSEvent) -> Bool {
        event.cgEvent.map(isSynthetic) ?? false
    }

    /// Health-probe key: keycode 90 = kVK_F20, which no physical Apple keyboard has.
    /// (It was keycode 127 originally — the OS FILTERS that one, so the probe never
    /// re-entered the tap and every tick read as a miss.) The watchdog posts one per
    /// tick while the user is typing; the callback swallows it and records the arrival.
    /// A probe that never comes back means posts are being DROPPED (Accessibility
    /// grant REMOVED — AXIsProcessTrusted lies true in that state) or the tap is
    /// dead/wedged. No breaker or in-flight bookkeeping: probes are out-of-band.
    static let probeKeycode: Int64 = 90   // kVK_F20 — not on any physical Apple keyboard; keycode 127 gets FILTERED by the OS (never re-enters the tap)

    /// TRUE while the user physically holds ⌘/⌃/⌥ (combined session state). The probe
    /// must never post during a chord: it is created from our PRIVATE source, so it
    /// carries EMPTY flags — a keyDown without ⌘ landing in the session while the
    /// ⌘-Tab switcher is up reads as "⌘ released" to the Dock, which COMMITS the
    /// switcher on whatever app the cursor points at (field report 2026-07-30: holding
    /// ⌘ and tabbing "chỉ được 1 lúc là tự mở app"). ⇧ is deliberately not included —
    /// it is held for whole words during normal typing and starving the probe under it
    /// would blind the watchdog exactly when it matters.
    static let chordFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
    static var chordModifierHeld: Bool {
        !CGEventSource.flagsState(.combinedSessionState).intersection(chordFlags).isEmpty
    }

    /// Pure gate for the health probe, shared by postProbe() and the watchdog's
    /// miss-accounting so the two can never disagree (a probe "sent" by the watchdog
    /// but silently skipped here would read as a miss and tear down a healthy tap).
    static func probeMayPost(secureInput: Bool, secureField: Bool, chordHeld: Bool) -> Bool {
        !(secureInput || secureField || chordHeld)
    }

    static func postProbe() {
        guard let src = source else { return }
        // NEVER post the probe while a password field has focus (under secure input our
        // tap does not receive events, so the marker is not swallowed by us — it lands in
        // the focused app instead; field report 2026-07-27: stray characters while typing
        // a password) NOR while a ⌘/⌃/⌥ chord is held (see chordModifierHeld — it
        // commits the ⌘-Tab switcher). Health monitoring is not worth touching either.
        if !probeMayPost(secureInput: IsSecureEventInputEnabled(),
                         secureField: SecureFieldDetector.isSecure,
                         chordHeld: chordModifierHeld) { return }
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(probeKeycode), keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(probeKeycode), keyDown: false)
        else { return }
        // keyUp as well: a lone keyDown leaves the key logically held in apps that track
        // key state, and an unbalanced function key was observed as a stuck modifier.
        // Stamped like every other post site: back-to-back events can get equal
        // mach-time stamps and the window server reorders same-stamp events — an
        // up-before-down probe pair would read as a stuck key.
        stamp(down)
        stamp(up)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    /// IMKit-path recognizer: match ONLY on the private source's `magic` userData,
    /// never the posting pid. Chromium/Electron apps (Slack, Lark) deliver REAL
    /// keydowns to the input method with `eventSourceUnixProcessID == getpid()`, so
    /// the pid-based `isSynthetic` misread them as our own output and dropped them —
    /// Vietnamese became untypable there (raw "vieejt"). Magic is set only by our
    /// source, so a real key never carries it. A false NEGATIVE here is harmless:
    /// our synthetic output only ever targets tap-mode apps, and the controller
    /// defers those to the tap (usesTapMode) before it would ever compose the event.
    /// The pid signal stays PRIMARY in the tap's own cascade guard (`isSynthetic`),
    /// where a synthetic that lost its magic must still be caught to avoid the hang.
    static func isSyntheticMagic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == magic
    }
    static func isSyntheticMagic(_ event: NSEvent) -> Bool {
        event.cgEvent.map(isSyntheticMagic) ?? false
    }

    /// One lock for every mutable static below (stamp, in-flight counter, breaker
    /// window). The posting paths run on the TAP thread; resetBreaker() is called
    /// from MAIN (start/ensureRunning). Uncontended NSLock is tens of ns — noise
    /// next to a window-server post.
    private static let lock = NSLock()

    /// Strictly-increasing timestamp for posted events. CGEvent.post orders delivery
    /// by timestamp, and events we create back-to-back can get equal/near-equal
    /// mach-time stamps — the window server then reorders same-stamp events, so a
    /// later letter overtakes an earlier tone edit ("nuwax" typed fast came out
    /// "nuẵ" = "nuawx"). Stamping each event mach-time-or-last+1 forces FIFO.
    private static var lastStamp: UInt64 = 0
    private static func stamp(_ event: CGEvent) {
        let stampValue: UInt64 = lock.withLock {
            let now = mach_absolute_time()
            lastStamp = now > lastStamp ? now : lastStamp &+ 1
            return lastStamp
        }
        event.timestamp = CGEventTimestamp(stampValue)
    }

    #if DEBUG
    /// Test seam: stamp through the real path (`stamp` is private). Lets the
    /// strictly-increasing contract be pinned without posting anything — the probe
    /// pair (postProbe) relies on it so the window server cannot deliver up before
    /// down (field report 2026-07-30).
    static func _testStamp(_ event: CGEvent) { stamp(event) }
    #endif

    // MARK: In-flight tracking (native fast-path ordering guard)
    //
    // Synthetic keyDowns that were posted but have not yet re-entered the tap.
    // While > 0 a physical key must NOT pass through natively: a native letter
    // delivered ahead of a still-queued synthetic edit reorders the text (the
    // historical "nuwax"→"nuẵ" corruption). Once the queue is drained, plain
    // letters go through natively again — zero synthetic events on the common
    // path. Guarded by `lock` (tap thread posts/observes; main resets).
    private static var inFlightKeyDowns = 0
    private static var lastPostNs: UInt64 = 0

    // MARK: Cascade circuit breaker (Layer 3)
    //
    // Last-resort guard against the dead-keyboard hang: if self-recognition
    // (isSynthetic) ever fails open, every synthetic event we post re-enters handle()
    // as a "real" key, drives the engine, and posts MORE synthetic events → an
    // unbounded storm that eats every keystroke. This breaker does NOT depend on
    // isSynthetic (the thing that can break); it just counts events we POST in a
    // sliding window. A cascade re-enters handle() and drives NEW posts, so counting
    // at the shared post site (notePostedKeyDown, below) catches the runaway whether or
    // not recognition still works.
    //
    // Threshold has a LARGE margin over any legit burst: one apply() posts at most ~33
    // keyDowns (engine caps a word at 32 chars → ≤32 backspaces + 1 insert), and fast
    // typing can stack a few bursts before they drain — realistically < ~100 posts in
    // any 500ms. A human simply cannot generate hundreds of key events in half a second,
    // so > 256 posts within a 500ms window can ONLY be a runaway. Numbers chosen for a
    // clear gap, not precision. On trip we stop emitting and call the controller to
    // disable the tap + reset (keys go native — Vietnamese-in-terminal off, keyboard
    // never dead). Gated behind AppState.tapCascadeBreaker (default ON) as a kill switch.
    // Window state shares `lock` with the in-flight counter above.
    private static let breakerWindowNs: UInt64 = 500_000_000
    private static let breakerThreshold = 256
    private static var windowStartNs: UInt64 = 0
    private static var postsInWindow = 0
    private static var _tripped = false
    static var tripped: Bool { lock.withLock { _tripped } }

    /// Re-arm after the controller has torn down / rebuilt a healthy tap.
    static func resetBreaker() {
        lock.withLock {
            _tripped = false
            inFlightKeyDowns = 0
            postsInWindow = 0
            windowStartNs = 0
        }
    }

    @inline(__always)
    private static func notePostedKeyDown() {
        let breakerEnabled = AppState.shared.tapCascadeBreaker   // own lock — outside ours
        let justTripped: Bool = lock.withLock {
            inFlightKeyDowns += 1
            let now = DispatchTime.now().uptimeNanoseconds
            lastPostNs = now
            // Count one posted keyDown into the sliding window; trip if the post rate
            // is superhuman (see the breaker doc above).
            guard breakerEnabled, !_tripped else { return false }
            if now &- windowStartNs > breakerWindowNs {
                windowStartNs = now
                postsInWindow = 0
            }
            postsInWindow += 1
            if postsInWindow > breakerThreshold {
                _tripped = true
                return true
            }
            return false
        }
        if justTripped {
            Signposts.log.fault("cascade breaker TRIPPED: >\(breakerThreshold, privacy: .public) synthetic posts within \(breakerWindowNs / 1_000_000, privacy: .public)ms — disabling tap, keys pass through natively")
            // Stop the storm at the source: disable the tap + reset the engine now,
            // rather than waiting for the next re-entered event to reach handle().
            // OUTSIDE the lock: emergencyStop takes the controller's state lock.
            TerminalTapController.shared.emergencyStop()
        }
    }

    /// Called by the tap when one of our own keyDowns comes back around.
    static func noteObservedSynthetic() {
        lock.withLock {
            if inFlightKeyDowns > 0 { inFlightKeyDowns -= 1 }
        }
    }

    /// True when no synthetic keyDown is still in flight. Self-heals: if an event
    /// was dropped (tap flapped mid-burst), a 500ms silence resets the counter so
    /// we can't get wedged in all-synthetic mode.
    static func queueDrained() -> Bool {
        lock.withLock {
            if inFlightKeyDowns == 0 { return true }
            if DispatchTime.now().uptimeNanoseconds &- lastPostNs > 500_000_000 {
                inFlightKeyDowns = 0
                return true
            }
            return false
        }
    }

    /// Replace `backspaces` trailing chars with `text`. Two strategies:
    /// - Default (terminals): Backspace ×N, then type.
    /// - `selectionReplace` (Chrome omnibox / Spotlight): Shift+Left ×N to SELECT the
    ///   chars, then type `text` to OVERTYPE the selection — one coherent edit that
    ///   doesn't fight inline autocomplete (a plain Backspace deletes/offsets the
    ///   suggestion). A pure deletion
    ///   (empty `text`) has nothing to overtype, so it falls back to real Backspaces.
    static func apply(backspaces: Int, insert text: String, mode: TapEmit = .backspace) {
        if tripped { return }   // recognition failed — emitting more would storm the keyboard
        // NEVER post from an untrusted process: CGEvent.post without Accessibility
        // can stall/behave unpredictably, and a tap callback stuck inside a post is
        // an unserviced port = system-wide input wedge. Dropping the edit merely
        // loses one tone change during the revoke transition.
        guard Accessibility.isTrusted else { return }
        // Signpost each synthesized edit burst — this is where a tone edit pays
        // real milliseconds (every posted event round-trips the window server).
        let spState = Signposts.poster.beginInterval("tap.emit",
                                                     id: Signposts.poster.makeSignpostID())
        // privacy: .public — counts only (burst size), no user text; without it the
        // xctrace export shows "<private>" and the bs-bucket analysis can't populate.
        defer { Signposts.poster.endInterval("tap.emit", spState, "bs=\(backspaces, privacy: .public) ins=\(text.count, privacy: .public)") }
        // DebugLog mirror (counts only, never text): the emit burst was previously
        // invisible in tester logs — its keystrokes re-enter IMKit as anonymous
        // 2-4ms "handle ENTER" bursts, indistinguishable from a swallowed edit
        // (web editors that eat synthetic keys, 2026-07-30). One line per burst.
        DebugLog.log("tap-emit mode=\(mode) bs=\(backspaces) ins=\(text.count)")
        if mode == .selection, backspaces > 0, !text.isEmpty {
            // D1 fast path: one AX text edit instead of the Shift+Left ×N select +
            // overtype burst. Only when the synthetic queue is drained — the AX write
            // mutates the field immediately, and native letters that already passed the
            // tap can't be tracked, so taking it mid-burst could reorder ("nuwax"→"nuẵ"
            // class). ANY AX failure → replaceTrailing returns false and we fall through
            // to the posted-events path unchanged. Signpost so measure-signposts.sh can
            // confirm the round trips collapsed to one.
            //
            // SPOTLIGHT ONLY: a Chromium omnibox does NOT register an AX kAXSelectedText
            // mutation as user input, so its autocomplete model keeps the pre-edit text
            // and an immediate Enter submits the stale match ("chó"→"cho"). Browsers must
            // use the posted select+overtype below (real key events Chrome treats as user
            // input). Detect Spotlight (the other .selection app) by the window-list scan;
            // anything else in .selection mode is a browser → skip the AX path.
            if AppState.shared.axSelectionReplace, SpotlightDetector.isVisible,
               SyntheticKeyboard.queueDrained() {
                let axState = Signposts.poster.beginInterval("ax.replace",
                                                             id: Signposts.poster.makeSignpostID())
                let ok = AXTextEdit.replaceTrailing(backspaces: backspaces, with: text)
                // privacy: .public — burst size only, never user text (see tap.emit).
                Signposts.poster.endInterval("ax.replace", axState, "bs=\(backspaces, privacy: .public)")
                if ok { return }
            }
            for _ in 0..<backspaces { postSelectLeft() }
            postUnicode(text)
            return
        }
        // The U+202F dance exists to stop an INLINE SUGGESTION from swallowing the
        // RETYPE. A pure deletion has no retype to protect, so the placeholder would be
        // pure visible garbage: pressing ⌫ in a browser omnibox flashed a stray character
        // before the delete ("ấn nút xóa thì bị thêm ký tự rồi xóa" — tester report
        // 2026-07-27, shipped with the omnibox .emptyReset switch in 1.4.14). Plain
        // Backspace ×N there: the app cancels its own suggestion on a delete anyway.
        if usesPlaceholderDance(mode: mode, backspaces: backspaces, textIsEmpty: text.isEmpty) {
            postUnicode("\u{202F}")                                    // cancel inline autocomplete
            for _ in 0..<(backspaces + 1) { postVirtual(CGKeyCode(kVK_Delete)) }  // +1 deletes the U+202F
            postUnicode(text)
            return
        }
        for _ in 0..<max(0, backspaces) { postVirtual(CGKeyCode(kVK_Delete)) }
        if !text.isEmpty { postUnicode(text) }
    }

    /// Edge-tap variant of apply (.backspace mode only): returns the number of
    /// keyDowns actually posted. The IMKit controller needs the EXACT count —
    /// Electron rebuilds our synthetic events on the way to the IME (magic
    /// userData stripped, "handle ENTER … magic=false" for our own burst), so
    /// recognition by stamp is impossible there and the controller instead
    /// swallows exactly this many laundered echoes (field 06/08: the "ư" echo
    /// hit the boundary path, reset the engine mid-word, "thuwr" → "thưr").
    /// Returns (backspace count, insert chunks) — NOT a single number: whether an
    /// echo re-enters IMKit.handle is APP-DEPENDENT. ⌫ keyDowns always come back;
    /// unicode-string keyDowns come back in Chromium/Electron but are inserted
    /// directly by AppKit in native apps (TextEdit trace 07/08: the "ư" echo never
    /// reached handle and a blind count swallowed the next REAL letter — "thưr"
    /// with 'r' eaten as echo #2). The controller therefore matches echoes by
    /// CONTENT: keycode 51 against the backspace budget, event.characters against
    /// the pending chunk list.
    static func applyForEdge(backspaces: Int, insert text: String) -> (backspaces: Int, chunks: [String]) {
        if tripped || !Accessibility.isTrusted { return (0, []) }
        apply(backspaces: backspaces, insert: text, mode: .backspace)
        return (max(0, backspaces), text.isEmpty ? [] : unicodeInsertChunks(text))
    }

    /// Does this edit need the U+202F placeholder dance? Only `.emptyReset`, only a real
    /// replace, and only when there IS text to retype: the placeholder exists to stop an
    /// inline suggestion from swallowing the RETYPE, so on a pure deletion it protects
    /// nothing and is visible garbage instead — pressing ⌫ in a browser omnibox flashed a
    /// stray character before the delete (tester report 2026-07-27). Pure function so the
    /// rule is pinned by tests; the posting code around it cannot be unit-tested.
    static func usesPlaceholderDance(mode: TapEmit, backspaces: Int, textIsEmpty: Bool) -> Bool {
        mode == .emptyReset && backspaces > 0 && !textIsEmpty
    }

    /// Re-emit a control/whitespace boundary key after a boundary rewrite, so it
    /// lands AFTER the synthesized edit.
    static func postKey(_ key: CGKeyCode) {
        guard Accessibility.isTrusted else { return }   // see apply()
        postVirtual(key)
    }

    /// Re-post the user's boundary key (Return/Tab/Esc) as a FRESH event so it
    /// lands AFTER a synthesized rewrite. History of this function:
    /// - postVirtual (private source) was rejected: Electron editors (Discord/
    ///   Slate) treat a private-source Return as "insert newline" instead of
    ///   firing Enter-to-send.
    /// - `event.copy()` of the real HID event was the replacement — but macOS 26
    ///   silently DROPS a re-posted copy of a hardware key before app delivery
    ///   (repro 2026-08-06: copy posted → passes our tap → never reaches IMKit;
    ///   WhatsApp beeped once, message not sent, shortcut "ko"→"không" needed a
    ///   second Enter).
    /// So: build a NEW event from the .hidSystemState source (hardware-like for
    /// Electron, deliverable on macOS 26), same keycode + flags as the original.
    /// No magic on purpose — when it re-enters IMKit it is handled as a REAL key;
    /// by then the engine is empty (boundary() just ran) so it passes straight
    /// through (`rewrote=false`), no loop. The keyUp is posted too so the app
    /// never sees a keyDown left logically held (the user's physical keyUp
    /// precedes our down and cannot pair with it).
    static func postBoundaryCopy(of event: CGEvent) {
        postBoundaryKey(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
                        flags: event.flags)
    }

    /// Value-based variant for callers that post AFTER the original event's
    /// lifetime (deferred edge-boundary bursts).
    static func postBoundaryKey(_ key: CGKeyCode, flags: CGEventFlags) {
        guard Accessibility.isTrusted else {
            DebugLog.log("boundary-copy: SKIPPED (untrusted)")
            return
        }
        guard let (down, up) = makeBoundaryRepost(key: key, flags: flags) else {
            DebugLog.log("boundary-copy: SKIPPED (create failed)")
            return
        }
        notePostedKeyDown()
        stamp(down); down.post(tap: .cgSessionEventTap)
        stamp(up); up.post(tap: .cgSessionEventTap)
        DebugLog.log("boundary-copy: posted fresh key=\(key)")
    }

    /// Builds the down/up pair postBoundaryCopy sends. Split out so tests can pin
    /// the load-bearing properties without posting: .hidSystemState source (NOT the
    /// private magic source — Electron demotes private-source Return to "newline",
    /// and magic would make IMKit skip it) and NOT a copy of the hardware event
    /// (macOS 26 drops re-posted copies before app delivery).
    static func makeBoundaryRepost(key: CGKeyCode, flags: CGEventFlags) -> (down: CGEvent, up: CGEvent)? {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return nil }
        down.flags = flags
        up.flags = flags
        return (down, up)
    }

    /// Shift+LeftArrow: extend the selection one char left (used by selectionReplace).
    private static func postSelectLeft() {
        // Layer 2: a nil private source means CGEvent(keyboardEventSource: nil,…) would
        // post an UNSTAMPED event — exactly what feeds the re-entrancy cascade. A nil
        // source is near-impossible, but if it ever happens, dropping the edit (the
        // terminal just gets no tone change) is the safe degradation. Same guard in
        // postVirtual/postUnicode.
        guard source != nil else { return }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: false)
        else { return }
        down.flags = .maskShift
        up.flags = .maskShift
        notePostedKeyDown()
        stamp(down); down.post(tap: .cgSessionEventTap)
        stamp(up);   up.post(tap: .cgSessionEventTap)
    }

    private static func postVirtual(_ key: CGKeyCode) {
        guard source != nil else { return }            // Layer 2: never post unstamped (see postSelectLeft)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        notePostedKeyDown()
        stamp(down); down.post(tap: .cgSessionEventTap)
        stamp(up);   up.post(tap: .cgSessionEventTap)
    }

    /// One posted key event per CHARACTER, never a multi-char unicode string:
    /// Chromium delivers a multi-char CGEvent string through a slower composition-ish
    /// path than a plain 1-char keydown, so a following single-char event can
    /// OVERTAKE it inside the renderer — web terminal field report 2026-08-01
    /// ("vim test." → "vim t.est": the boundary "." passed the 3-char "est" insert).
    /// Native terminals are byte pipes and don't care. Pure so the split is pinned
    /// by tests (grapheme-safe: combining pairs stay together).
    static func unicodeInsertChunks(_ text: String) -> [String] {
        text.map(String.init)
    }

    private static func postUnicode(_ text: String) {
        for chunk in unicodeInsertChunks(text) { postUnicodeChunk(chunk) }
    }

    #if DEBUG
    /// Test seam: records the size (in Characters) of every chunk that reaches the
    /// post site, BEFORE the source guard — so a test host (no event source, nothing
    /// actually posted) can still pin the "one character per event" invariant
    /// end-to-end through postUnicode, not just the pure chunker.
    static var _testChunkSizes: [Int] = []
    static func _testPostUnicode(_ text: String) {
        _testChunkSizes = []
        postUnicode(text)
    }
    #endif

    private static func postUnicodeChunk(_ text: String) {
        #if DEBUG
        _testChunkSizes.append(text.count)
        #endif
        guard source != nil else { return }            // Layer 2: never post unstamped (see postSelectLeft)
        let utf16 = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        else { return }
        // Explicitly EMPTY flags: a unicode insert must never carry (or inherit)
        // a modifier. Chromium applies the shift bit it last saw to the inserted
        // text — after our Shift+← selection events, a racy read uppercased the
        // replaced char ("lệch" → "lỆch", tester video 2026-07-23).
        down.flags = []
        utf16.withUnsafeBufferPointer { buf in
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        // Task B2 (experimental, default OFF): skip the keyUp on unicode inserts — post
        // only the keyDown carrying the string, halving posted events per insert. The
        // accounting stays balanced: the tap mask is keyDown-only, and the in-flight
        // counter tracks/observes keyDowns only, so a dropped keyUp is never counted and
        // never awaited. Unlike a virtual Delete (postVirtual, where the up matters for
        // key-repeat semantics), a unicode-string keyUp carries no repeat behaviour.
        let up = AppState.shared.tapSkipSyntheticKeyUp
            ? nil : CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        if let up {
            up.flags = []
            utf16.withUnsafeBufferPointer { buf in
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
        }
        notePostedKeyDown()
        stamp(down); down.post(tap: .cgSessionEventTap)
        if let up { stamp(up); up.post(tap: .cgSessionEventTap) }
    }
}

/// Global keyDown tap that handles terminal-class apps. Owns its own
/// engine, separate from the IMKit controller's (they never process the same app at
/// once: the tap suppresses terminal keys before the IME, and passes everything else
/// through for the IME to handle).
final class TerminalTapController {
    static let shared = TerminalTapController()

    /// Whether VietTelex is the active input source: the tap only transforms keys
    /// while true (so switching to ABC/US inside a terminal really types English).
    /// Driven by IMK activate/deactivate AND the TIS selection notification, resolved
    /// through `IMEActivation` so an out-of-order deactivate can't clobber it (see
    /// IMEActivation.swift). Locked: the mark* lifecycle calls run on MAIN, the
    /// per-key read runs on the TAP thread.
    private let activationLock = NSLock()
    private var activation = IMEActivation()
    var imeActive: Bool { activationLock.withLock { activation.isActive } }

    /// activateServer: VietTelex active for the focused client.
    func markActive() {
        let active = activationLock.withLock { activation.activate(); return activation.isActive }
        DebugLog.log("markActive → imeActive=\(active)")
        // Issue #40 (Discord): tap-routed Electron apps never get the field scans
        // that poke a lazily-built AX tree on, so the reach-back reads (⌫ re-open /
        // re-edit) found no caret there. Poke once per pid, off the main thread.
        if FocusedFieldDetector.lazyAXPokeWanted(
                reEditEnabled: AppState.shared.reEditWord,
                routesTap: AppState.shared.tapRouting(FrontmostApp.shared.bundleID).tap) {
            DispatchQueue.global(qos: .utility).async { FocusedFieldDetector.pokeFrontmostLazyAX() }
        }
    }

    /// deactivateServer: `stillSelected` = is VietTelex still the OS-selected source
    /// right now (queried via TIS by the caller). Ignores a stale late deactivate.
    func markInactive(stillSelected: Bool) {
        let active = activationLock.withLock {
            activation.deactivate(stillSelected: stillSelected); return activation.isActive
        }
        DebugLog.log("markInactive(stillSelected=\(stillSelected)) → imeActive=\(active)")
    }

    /// TIS selection-changed notification: authoritative recompute.
    func selectionChanged(isVietTelex: Bool) {
        let active = activationLock.withLock {
            activation.selectionChanged(isVietTelex: isVietTelex); return activation.isActive
        }
        DebugLog.log("selectionChanged(isVietTelex=\(isVietTelex)) → imeActive=\(active)")
    }

    /// Turn-ON self-heal (tester log 2026-07-23): IMKit routes keys ONLY to the
    /// OS-selected input method, so a REAL key reaching the IMK controller is
    /// authoritative proof VietTelex is selected — stronger than the TIS cache,
    /// whose switch-time query can report the OUTGOING source and latch
    /// imeActive FALSE (per-app input switching). A false latch made the tap
    /// dormant while IMK kept deferring tap-mode apps to it: dead Vietnamese in
    /// the focused field until a focus change fired activateServer. Called from
    /// IMK handle() per real key; no-ops (one lock read) while already active.
    func noteIMKKeyProvesSelected() {
        let healed: Bool = activationLock.withLock {
            guard !activation.isActive else { return false }
            activation.selectionChanged(isVietTelex: true)
            return activation.isActive
        }
        if healed { DebugLog.log("imk-key self-heal: key reached IMK while imeActive=false → imeActive=true") }
    }

    /// TAP-thread confined: only ever touched inside the tap callback (and
    /// emergencyStop, which fires from the posting path on the same thread).
    private var engine = TelexEngine()

    /// Tap machinery. Guarded by `stateLock`: lifecycle (start/ensureRunning/teardown)
    /// runs on MAIN, while the callback's rare tapEnable branches (tripped / re-enable
    /// after timeout) and emergencyStop run on the TAP thread.
    private let stateLock = NSLock()

    // Grant-removal ping-pong detector (tap thread confined).
    private var lastDisableNs: UInt64 = 0
    private var disableBurst = 0

    /// Set by start() on MAIN, consumed by the FIRST keyDown after a (re)enable on the
    /// TAP thread: `engine` is tap-thread confined, so a composition left over from a
    /// previous tap life must be dropped from INSIDE the callback, never from start().
    /// (The old code called engine.reset() on main right before tapEnable — no gap in
    /// practice, since the tap can't deliver before it is enabled, but it was the one
    /// place main touched tap-thread state.) Guarded by `stateLock`.
    private var pendingEngineReset = false

    /// Uptime of the last REAL keyDown seen by the callback, 0 = none yet. Written on
    /// the TAP thread, read by the watchdog on MAIN — guarded by `stateLock` (folded
    /// into the same lock round trip that consumes `pendingEngineReset`, so the hot
    /// path pays one uncontended lock, not two).
    private var lastKeyDownNs: UInt64 = 0
    /// Idle threshold: with no keystroke for this long there is no typing to protect,
    /// so the watchdog skips the health probe and its secure-field precheck (both
    /// cross-process). The trust check always runs.
    private static let watchdogIdleNs: UInt64 = 180_000_000_000   // 3 minutes

    /// Does this keystroke count as "typing to protect" for the watchdog's idle skip?
    /// ONLY while VietTelex is the selected source. The tap sees every key on the
    /// system, so before this gate an afternoon of typing in ABC kept the watchdog
    /// permanently "active": a synthetic F20 post + a cross-process secure-field scan
    /// every 3s, protecting a tap that transforms nothing — and each post tickles the
    /// system activity monitor. Perf audit 17/08/2026.
    static func stampsLiveness(imeActive: Bool) -> Bool { imeActive }

    // Functional health probe (stateLock): watchdog bumps probeSentTick and posts;
    // the callback copies it into probeSeenTick on arrival. Sent != seen for two
    // consecutive watchdog ticks ⇒ posts are dropped or the tap is wedged.
    private var probeSentTick: UInt64 = 0
    private var probeSeenTick: UInt64 = 0
    private var probeMisses = 0
    /// Last idle verdict, for transition-only logging (main-thread confined — only
    /// the watchdog timer touches it).
    private var wasIdle = true

    // Backoff after a FAILED trust cycle (probe missed / tap refused): without
    // it, the stale-TRUE AXIsProcessTrusted drives an infinite create→probe-fail
    // →teardown loop every ~8s (observed live 2026-07-22), eating keys in
    // tap-mode apps during each ~6s window. While quarantined we do NOT
    // auto-retry; an explicit user action (menu repair, grant re-add firing the
    // TCC notification, input-source activation after the window) retries.
    private var quarantineUntilNs: UInt64 = 0
    private func quarantine(_ seconds: UInt64) {
        quarantineUntilNs = DispatchTime.now().uptimeNanoseconds &+ seconds &* 1_000_000_000
    }
    private var quarantined: Bool {
        DispatchTime.now().uptimeNanoseconds < quarantineUntilNs
    }
    /// Menu/diagnostics only: the tap is deliberately paused by the failed-cycle
    /// backoff. Without surfacing this, a quarantined tap looks like "Status: OK"
    /// while every tap-mode app types raw ASCII (field report 2026-07-30).
    var isQuarantined: Bool { quarantined }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// The dedicated thread's run loop, captured at thread start; nil while stopped.
    private var tapRunLoop: CFRunLoop?

    /// True only if the tap exists AND is actually enabled/intercepting. A tap object
    /// can linger after its mach port dies (e.g. Accessibility was toggled off/on),
    /// so `tap != nil` alone is misleading — check `tapIsEnabled`.
    var isRunning: Bool {
        guard let tap = stateLock.withLock({ tap }) else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// LAST-RESORT watchdog (main thread, alive ONLY while a tap exists — created in
    /// start(), invalidated in teardown()). Every 3s it makes a FRESH trust check;
    /// on revoke it forces the unconditional teardown. This is the layer that needs
    /// no cooperation from anything else: not from the TCC notification (may race /
    /// not arrive), not from the tap callback (which can be BLOCKED inside a
    /// synthetic-event post the instant trust vanishes — the suspected build-7 wedge:
    /// a stuck callback never sees tapDisabledBy* and a stuck thread's own runloop
    /// timer would be just as stuck, which is why this lives on MAIN). Worst case the
    /// user's input stalls ≤3s before the port is invalidated and everything flows
    /// natively again. The "no polling" design rule is deliberately bent here: the
    /// timer exists only while an Accessibility-trusted event tap does — the exact
    /// window in which a wedge can take the whole machine's input down.
    private var watchdog: Timer?

    /// Retry loop for the FIRST grant only — alive ONLY while no tap exists BECAUSE
    /// Accessibility isn't trusted yet (mirrors watchdog's "only while a tap does"
    /// shape, at the opposite end of the lifecycle). Without this, nothing re-attempts
    /// `start()` after the user grants Accessibility mid-session unless an app/focus
    /// switch calls `ensureRunning()` (activateServer) or the `com.apple.accessibility.
    /// api` distributed notification fires — field report 2026-08-11: an ALREADY-
    /// RUNNING process kept composing marked text (underlined, needs Space/Enter)
    /// minutes after the grant, with the user staying in the same field the whole
    /// time (no focus switch) — only killing and relaunching the process picked up
    /// the new permission. Polling here means a grant is noticed within one tick
    /// (same 3s cadence as the health watchdog) with no cooperation required from
    /// either of those signals.
    /// Máy nhận diện chord hotkey chuyển bộ gõ — TAP-thread confined (mọi note/disarm
    /// đều từ callback), không cần lock. Xem SwitchHotkey.swift.
    private var chordRecognizer = ModifierChordRecognizer()

    private var trustPoll: Timer?

    private func startTrustPollIfNeeded() {
        guard trustPoll == nil else { return }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.ensureRunning()
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        trustPoll = t
    }

    #if DEBUG
    var _testTrustPollIsRunning: Bool { trustPoll != nil }
    /// Identity of the current poll Timer, or nil if not armed — lets a test prove
    /// a second arm attempt reused the SAME timer instead of leaking a new one.
    var _testTrustPollToken: ObjectIdentifier? { trustPoll.map(ObjectIdentifier.init) }
    // Exercise the poll's start/stop mechanics directly — NOT through ensureRunning()
    // with testTrustOverride=true, which would reach CGEvent.tapCreate in the test
    // host (see GonhanhHardeningTests' testEnsureRunningIsSafeWithoutTrust for why
    // that path is only ever exercised untrusted).
    func _testDisarmTrustPoll() { stopTrustPoll() }
    #endif

    private func stopTrustPoll() {
        trustPoll?.invalidate()
        trustPoll = nil
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !AXIsProcessTrusted() {
                Signposts.log.fault("watchdog: Accessibility revoked with a live tap — forcing teardown")
                self.trustMayHaveChanged()
                return
            }
            // Trusted but the tap silently died: the tapDisabledByTimeout event is
            // NOT guaranteed to arrive (a callback blocked mid-post never sees it —
            // same field data as gonhanh's watchdog). ensureRunning is a single
            // tapIsEnabled read when healthy; re-enables or rebuilds when not.
            // Without this a dead tap only healed on the next activateServer
            // (app switch) — typing in the SAME app stayed broken up to that point.
            self.ensureRunning()

            // FUNCTIONAL probe — the only signal that survives a LYING
            // AXIsProcessTrusted (grant REMOVED via −, field bug 2026-07-22):
            // post an F20 (keycode 90) marker at ourselves; the callback swallows it
            // and acks. Two consecutive unanswered probes ⇒ posts are being
            // dropped (revoked) or the callback is wedged ⇒ unconditional
            // teardown, keys flow natively again.
            // IDLE SKIP: the probe exists to prove that posting still works BEFORE the
            // user's next keystroke needs it. On a machine nobody is typing on there is
            // nothing to protect, and both the probe and its secure-field precheck are
            // cross-process calls on a 3s timer forever. No keyDown for minutes → do the
            // trust check + ensureRunning above and stop there. The probe accounting is
            // skipped too (not just the send): a single miss recorded before going idle
            // would otherwise keep incrementing every tick and tear down a healthy tap.
            let (sent, seen, lastKey): (UInt64, UInt64, UInt64) = self.stateLock.withLock {
                (self.probeSentTick, self.probeSeenTick, self.lastKeyDownNs)
            }
            let nowNs = DispatchTime.now().uptimeNanoseconds
            let idle = lastKey == 0 || nowNs &- lastKey > Self.watchdogIdleNs
            if idle != self.wasIdle {
                // Transition only, never per-tick: with the probe silent while idle, a
                // tap that died DURING idle is invisible until ~2 ticks after typing
                // resumes — the timestamps of these two lines bound that blind window
                // in a tester log (2026-07-30).
                DebugLog.log("watchdog: \(idle ? "idle — probe paused" : "typing resumed — probe active")")
                self.wasIdle = idle
            }
            if idle {
                self.probeMisses = 0
                // The stale-grant HINT still runs while idle: it is a pure local
                // preflight (no post, no AX scan) and the user must be able to see the
                // repair line without typing into a broken app first.
                if self.stateLock.withLock({ self.tap }) == nil,
                   Accessibility.grantLooksStale, !self.trustLooksStale {
                    self.trustLooksStale = true
                    DebugLog.log("watchdog: grant looks stale (trusted but canPost=false) → offer repair")
                }
                return
            }
            if sent != seen {
                self.probeMisses += 1
                if self.probeMisses >= 2 {
                    Signposts.log.fault("health probe unanswered ×\(self.probeMisses) — posts dropped or tap wedged; tearing down (quarantine 60s)")
                    DebugLog.log("health probe missed ×\(self.probeMisses) → teardown + quarantine 60s")
                    self.probeMisses = 0
                    self.trustLooksStale = true          // menu shows the repair line
                    self.quarantine(60)
                    self.trustMayHaveChanged()
                    return
                }
            } else {
                self.probeMisses = 0
            }
            if !SyntheticKeyboard.probeMayPost(secureInput: IsSecureEventInputEnabled(),
                                               secureField: SecureFieldDetector.isSecure,
                                               chordHeld: SyntheticKeyboard.chordModifierHeld) {
                // Password field in focus, or a ⌘/⌃/⌥ chord held: we do not post the
                // probe there (see postProbe), so there is nothing to ack — counting
                // that as a miss would raise a false "stale grant" and tear down a
                // perfectly healthy tap.
                self.probeMisses = 0
            } else if let tap = self.stateLock.withLock({ self.tap }), CGEvent.tapIsEnabled(tap: tap) {
                self.stateLock.withLock { self.probeSentTick &+= 1 }
                SyntheticKeyboard.postProbe()
            } else if Accessibility.grantLooksStale, !self.trustLooksStale {
                // No tap AND the privilege preflight refuses while macOS still calls us
                // trusted: that is the stale row, and we can say so WITHOUT waiting for
                // the user to type into Terminal/Chrome and find nothing works. Marks the
                // menu so the repair is one click away from the moment it breaks.
                self.trustLooksStale = true
                DebugLog.log("watchdog: grant looks stale (trusted but canPost=false) → offer repair")
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    /// Emit mode for the CURRENT key: false = Backspace+retype (terminals), true =
    /// Shift+Left select + overtype (Chrome omnibox / Spotlight). Set per event in
    /// handle() before any edit is emitted. TAP-thread confined.
    private var emitMode: TapEmit = .backspace

    /// TRUE while the most recent physical key was a word BOUNDARY (space/Return/
    /// Tab/Esc/punctuation/navigation) — consulted by the re-edit gate, which must
    /// not seed the word on the far side of a boundary the AX tree may not show
    /// yet (issue #38, see reEditGateOpen). Mouse clicks CLEAR it: clicking at the
    /// end of an existing word then pressing a tone key is re-edit's main use.
    /// TAP-thread confined (mouse/key branches of the same serial callback).
    private var lastTapKeyWasBoundary = false

    /// TRUE → the Spotlight overlay owns the keys and no one may compose: the
    /// routing verdict (from the app BEHIND the overlay) says tap-family, but a
    /// synthetic emit into Spotlight's inline autocomplete garbles the word. Only an
    /// explicit tap-family pin on Spotlight itself opts into composing (that case is
    /// handled by the manual-pin branch BEFORE this gate fires). Pure so the
    /// polarity is pinned by tests.
    static func spotlightOverlayForcesRaw(visible: Bool, manualPin: AppState.AppMode?) -> Bool {
        visible && !(manualPin == .selection || manualPin == .tap || manualPin == .emptyReset)
    }

    // Throttle for the imeActive self-heal reconcile (see handle()). TAP-thread
    // confined (only touched inside the callback).
    private var lastReconcileNs: UInt64 = 0
    private let reconcileWindowNs: UInt64 = 750_000_000

    private let kDelete = 51, kReturn = 36, kEnter = 76, kTab = 48, kEscape = 53

    private init() {}

    /// Create and enable the tap. No-op if already running or not Accessibility-
    /// trusted (sandboxed build, or permission not yet granted). Idempotent — called
    /// at launch and again on activate so granting AX later starts it without relaunch.
    ///
    /// THREADING: the tap's run loop source lives on a DEDICATED thread, not main.
    /// On main it queued behind every ~2ms IMKit XPC round trip and any Settings UI
    /// work — jittering terminal keystrokes and, worse, risking the slow-callback
    /// path where macOS disables the tap (tapDisabledByTimeout → leaked keys). The
    /// thread is event-driven (parked in mach_msg, zero CPU when idle) — it is the
    /// tap's equivalent of the main run loop, not a polling worker, so it does not
    /// violate the "no persistent background work" rule in DESIGN.md.
    /// TRUE when the last tap-create attempt failed WHILE AXIsProcessTrusted said
    /// yes — the classic stale TCC grant after a re-signed upgrade: the checkbox
    /// looks on, but the system refuses the tap. Cleared the moment a tap is
    /// created. The menu turns this into a self-serve repair instruction
    /// (remove + re-add in Accessibility) instead of silently typing English.
    private(set) var trustLooksStale = false

    func start() {
        guard !quarantined else { return }
        guard stateLock.withLock({ tap == nil }), Accessibility.isTrusted else { return }
        // flagsChanged: cho hotkey chuyển bộ gõ chỉ-gồm-modifier (SwitchHotkey).
        // Chi phí khi tắt hotkey: một string compare rồi return pass mỗi lần nhấn/nhả
        // modifier — không chạm engine, không chạm policy.
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue)
                             | (1 << CGEventType.flagsChanged.rawValue)
                             | (1 << CGEventType.leftMouseDown.rawValue)
                             | (1 << CGEventType.rightMouseDown.rawValue))
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<TerminalTapController>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Trusted but the system refused the tap → stale grant (field case
            // 2026-07-22: dev re-sign; can also follow unusual upgrade paths).
            trustLooksStale = true
            // Record WHY: the preflight is the privilege-specific ground truth, so
            // canPost=false with trusted=true names the stale row outright (Apple DTS
            // recommends these over AXIsProcessTrusted — forums/thread/727984).
            Signposts.log.fault("tap create refused: trusted=\(AXIsProcessTrusted(), privacy: .public) canPost=\(Accessibility.canPostEvents, privacy: .public) canListen=\(Accessibility.canListenEvents, privacy: .public)")
            DebugLog.log("tap create refused: trusted=\(AXIsProcessTrusted()) "
                + "canPost=\(Accessibility.canPostEvents) canListen=\(Accessibility.canListenEvents)")
            quarantine(60)
            Signposts.log.fault("tap create FAILED while trusted — stale Accessibility grant; remove + re-add VietTelex in System Settings")
            DebugLog.log("tap create failed while trusted → stale TCC grant (retry in 60s)")
            return
        }
        trustLooksStale = false

        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        // Park the source on the dedicated thread's run loop. Wait (bounded) for the
        // run loop reference so teardown() always has something to stop — the thread
        // reaches the semaphore in microseconds.
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()
            self?.stateLock.withLock { self?.tapRunLoop = rl }
            CFRunLoopAddSource(rl, src, .commonModes)
            ready.signal()
            CFRunLoopRun()   // returns after CFRunLoopStop in teardown()
        }
        thread.name = "com.viettelex.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        // Drop any composition left from a previous tap life — but from the TAP thread:
        // `engine` is tap-thread confined, so arm a flag the first keyDown consumes
        // instead of touching it here on main. Armed BEFORE tapEnable, so no real key
        // can slip past unreset.
        stateLock.withLock {
            self.pendingEngineReset = true
            self.lastKeyDownNs = 0          // fresh tap life: idle until someone types
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        stateLock.withLock {
            self.tap = tap
            self.source = src
        }
        SyntheticKeyboard.resetBreaker()   // fresh machinery — clear any prior trip
        startWatchdog()
        DebugLog.log("tap created + enabled (dedicated thread)")
    }

    /// Ensure a HEALTHY (enabled) tap. Recovers from the two ways a tap silently dies:
    /// (1) disabled by timeout/user-input → re-enable; (2) mach port invalidated after
    /// Accessibility was toggled off/on → the object lingers but `tapEnable` won't
    /// stick, so tear it down and create a fresh one. Called on every activateServer,
    /// so switching input source / focusing a terminal self-heals a dead tap.
    func ensureRunning() {
        guard Accessibility.isTrusted else { startTrustPollIfNeeded(); return }
        stopTrustPoll()   // trusted now — the health watchdog below takes over once start() runs
        if let tap = stateLock.withLock({ tap }) {
            // A tripped breaker disabled the tap on purpose. Re-enabling + re-arming is
            // safe now: pid-based isSynthetic no longer fails open, so the cascade that
            // tripped it can't recur. Clear the breaker whenever we leave with a healthy
            // enabled tap, or the next keystroke would just disable it again.
            if CGEvent.tapIsEnabled(tap: tap), !SyntheticKeyboard.tripped { return }  // healthy
            CGEvent.tapEnable(tap: tap, enable: true)       // try a simple re-enable
            if CGEvent.tapIsEnabled(tap: tap) { SyntheticKeyboard.resetBreaker(); return }
            teardown()                                      // dead port -> recreate
        }
        start()
    }

    /// The Accessibility permission MAY have changed (TCC notification, or a
    /// disabled-tap event with an untrusted read). MAIN thread — lifecycle owner.
    ///
    /// Tear down UNCONDITIONALLY, then re-create after a beat if genuinely trusted.
    /// The build-7 hang taught why there must be no guard here: immediately after
    /// the toggle, tccd can still report the OLD trust value — the previous
    /// `guard !isTrusted else return` skipped the teardown on exactly that race and
    /// left the wedged tap alive. Rebuilding a healthy tap ~1.5s later costs
    /// nothing; guessing wrong costs the user's keyboard and mouse.
    /// Tear the tap down for an imminent bundle replacement (self-update). Also
    /// quarantines, so nothing in this process re-creates a tap against a bundle that is
    /// about to disappear; the process exits right after the swap.
    func stopForUpdate() {
        DebugLog.log("update: tearing down tap before bundle swap")
        quarantine(600)
        teardown()
    }

    /// Called from the menu repair flow / TCC change notification: the user just
    /// DID something about the permission — drop the backoff and re-evaluate now.
    func retryNow() {
        quarantineUntilNs = 0
        trustLooksStale = false
        Accessibility.invalidateCache()
        ensureRunning()
    }

    /// A REAL trust-change signal (TCC notification): outranks the backoff.
    func trustChangedExternally() {
        quarantineUntilNs = 0
        trustMayHaveChanged()
    }

    func trustMayHaveChanged() {
        Accessibility.invalidateCache()
        teardown()
        SyntheticKeyboard.resetBreaker()
        DebugLog.log("trust-change signal → tap torn down; re-checking in 1.5s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            Accessibility.invalidateCache()
            self?.ensureRunning()   // recreates only if AXIsProcessTrusted by then
        }
    }

    private func teardown() {
        watchdog?.invalidate()
        watchdog = nil
        let (tap, source, runLoop) = stateLock.withLock {
            let t = (self.tap, self.source, self.tapRunLoop)
            self.tap = nil
            self.source = nil
            self.tapRunLoop = nil
            return t
        }
        if let tap {
            // Best effort — this CGS call FAILS once Accessibility is revoked…
            CGEvent.tapEnable(tap: tap, enable: false)
            // …so the AUTHORITATIVE removal is invalidating the mach port: the window
            // server unhooks a dead port exactly as if the process had exited, and it
            // needs no permission. Without this line, a revoked process that then
            // stops its tap thread leaves an ENABLED tap nobody services — every
            // keyDown/leftMouseDown/rightMouseDown in the session queues into the
            // void: keyboard dead, clicks dead, mouse still moves (not in the mask),
            // reboot territory. This was the v1.3.0(6) hang: the revoke handler tore
            // the thread down but could no longer disable the tap it orphaned.
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
            CFRunLoopStop(runLoop)   // ONLY after the port is invalid — never orphan a live tap
        }
        DebugLog.log("tap torn down (port invalidated)")
    }

    /// Layer 3 — hard stop when the cascade breaker trips. Disable the tap (keys pass
    /// through NATIVELY — degraded, never a dead keyboard) and drop any composition,
    /// immediately, at the moment of the trip rather than on the next re-entered event.
    /// The tap object is kept so a later activateServer → ensureRunning() can re-enable
    /// and re-arm the breaker once the machinery is healthy again. Called from
    /// SyntheticKeyboard's post site — i.e. on the TAP thread, so touching `engine`
    /// (tap-thread confined) here is safe.
    func emergencyStop() {
        if let tap = stateLock.withLock({ tap }) { CGEvent.tapEnable(tap: tap, enable: false) }
        engine.reset()
        DebugLog.log("EMERGENCY STOP — cascade breaker tripped, tap disabled, keys native")
    }

    /// Rewrite a ⌘/⌃/⌥ chord's keycode so the app resolves it on the PINNED layout.
    ///
    /// Costs one lock-guarded read and two array reads, and only for chords — a plain
    /// keystroke never gets here. Nothing happens at all unless a layout is pinned AND
    /// macOS is on a different one, the same fence the typing path uses.
    ///
    /// TAP THREAD. `KeyboardLayoutOverride.chordRemap` is lock-guarded for exactly this.
    private func remapChordKeyCode(_ event: CGEvent, shift: Bool) {
        guard let remap = KeyboardLayoutOverride.chordRemap else { return }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        guard let substitute = remap.substitute(for: code, shift: shift) else { return }
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(substitute))
    }

    // Returning nil suppresses the key; returning the event passes it through.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // Watchdog health probe (our own F20 / keycode-90 keyDown): swallow it before
        // ANY other logic — no app ever sees it, no counter counts it.
        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventKeycode) == SyntheticKeyboard.probeKeycode,
           SyntheticKeyboard.isSynthetic(event)
            || event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) {
            stateLock.withLock { probeSeenTick = probeSentTick }
            return nil
        }

        // Circuit breaker tripped: synthetic events stopped being recognized as ours
        // and were cascading (the dead-keyboard hang). DISABLE the tap immediately so
        // every key — real and any still-queued synthetic — passes through natively;
        // the keyboard is never dead. A later activateServer → ensureRunning()
        // re-enables and re-arms the breaker once the machinery is healthy again.
        // Checked before the tapDisabled re-enable below so a tripped tap stays down.
        if SyntheticKeyboard.tripped {
            engine.reset()
            if let tap = stateLock.withLock({ tap }) { CGEvent.tapEnable(tap: tap, enable: false) }
            return pass
        }

        // The system disables a tap that is too slow or gets user input; re-enable —
        // but ONLY while still Accessibility-trusted. When the user REVOKES the
        // permission, macOS disables the tap with tapDisabledByUserInput and will
        // disable it again on every re-enable; blindly re-enabling fought the OS in
        // a ping-pong that wedged ALL input (keyboard + mouse are both in our mask)
        // — the reported full-input hang. Revoked → tear the whole tap down (on
        // main; lifecycle is main-owned) and let every event flow natively.
        // Direct AXIsProcessTrusted() call, NOT the TTL cache — the cache serves a
        // STALE answer by design (5s TTL, refreshed in the background off the keystroke
        // path), so right after the toggle it can still say "trusted" and re-arm the
        // fight. Same rule as the watchdog: revoke-critical paths never read the cache.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // GRANT-REMOVAL guard (field bug 2026-07-22): when the user REMOVES the
            // Accessibility entry (−, not a toggle), AXIsProcessTrusted() keeps
            // returning a stale TRUE — so the old code re-enabled, the OS disabled
            // again, and the ping-pong wedged ALL input. Three disables inside 2s
            // can only be that fight: tear down regardless of what trust claims.
            let now = DispatchTime.now().uptimeNanoseconds
            if now &- lastDisableNs < 2_000_000_000 { disableBurst += 1 } else { disableBurst = 1 }
            lastDisableNs = now
            if disableBurst >= 3 {
                engine.reset()
                Signposts.log.fault("tap disable ping-pong (\(self.disableBurst)x/2s) — grant likely REMOVED, tearing down")
                DebugLog.log("tap disable ping-pong → teardown (grant removed?)")
                DispatchQueue.main.async { TerminalTapController.shared.trustMayHaveChanged() }
                return pass
            }
            if AXIsProcessTrusted() {
                if let tap = stateLock.withLock({ tap }) { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                Accessibility.invalidateCache()
                engine.reset()
                DebugLog.log("tap disabled + Accessibility revoked → full teardown, input native")
                DispatchQueue.main.async { TerminalTapController.shared.trustMayHaveChanged() }
            }
            return pass
        }

        // A mouse click moves the caret, so any composition in progress is stale:
        // abandon it. We do NOT emit backspaces/
        // edits — the caret is elsewhere now and the typed text is already real. Also
        // signal the IMKit controller (other apps) to drop its composition.
        // Hotkey chuyển bộ gõ (SwitchHotkey): chord chỉ-gồm-modifier hoàn tất khi nhả.
        // TAP-thread confined recognizer; toggle chạy trên MAIN (TIS không an toàn
        // ngoài main). Sự kiện flagsChanged luôn pass — mình chỉ quan sát, không sửa.
        if type == .flagsChanged {
            if let target = SwitchHotkey.targetFlags(for: AppState.shared.switchHotkey),
               chordRecognizer.note(flags: event.flags, target: target) {
                DispatchQueue.main.async { SwitchHotkey.toggle() }
            }
            return pass
        }

        if type == .leftMouseDown || type == .rightMouseDown {
            engine.reset()
            lastTapKeyWasBoundary = false   // click at a word's end re-arms re-edit
            chordRecognizer.disarm()        // click giữa lúc giữ chord = không phải toggle
            // Sticky-source: click trong dải menu bar = user có thể đang tự đổi input
            // source bằng menu — dấu vết để KHÔNG giành lại (StickyInputSource).
            StickyInputSource.shared.noteClick(at: event.location)
            if imeActive { NotificationCenter.default.post(name: .telexResetComposition, object: nil) }
            return pass
        }

        guard type == .keyDown else { return pass }

        // Our own synthesized output: never re-process it (but note its arrival —
        // it drains the in-flight counter that gates the native fast path).
        if SyntheticKeyboard.isSynthetic(event) {
            SyntheticKeyboard.noteObservedSynthetic()
            return pass
        }

        // One read of the activation latch for the whole key (it is a locked computed
        // property; the stamp below and the self-heal further down both need it).
        let active = imeActive

        // ONE stateLock round trip per real key (uncontended NSLock, tens of ns):
        //  • stamp liveness for the watchdog's idle skip (it must not probe a machine
        //    nobody types on) — ONLY while WE are the selected input source. Typing in
        //    ABC used to stamp too (the stamp sat above the imeActive gate), so a whole
        //    afternoon of English kept the watchdog "typing active": every 3s a synthetic
        //    F20 post + a cross-process secure-field scan, guarding a tap that transforms
        //    nothing — and each post tickles the system activity monitor. Blind window
        //    when switching back is the one already accepted for the idle skip: the
        //    probe re-arms on the first key after activateServer.
        //  • consume the pending post-(re)enable engine reset armed by start() — the
        //    engine is tap-thread confined, so the reset happens HERE, on this thread.
        // Phím thường (đã lọc synthetic ở trên) giữa lúc giữ chord = một shortcut
        // thật, không phải toggle bộ gõ — disarm. Tap-thread confined, plain store.
        chordRecognizer.disarm()

        let needsEngineReset: Bool = stateLock.withLock {
            if Self.stampsLiveness(imeActive: active) {
                lastKeyDownNs = DispatchTime.now().uptimeNanoseconds
            }
            defer { pendingEngineReset = false }
            return pendingEngineReset
        }
        if needsEngineReset { engine.reset() }

        // Self-heal the latched imeActive against the authoritative selected source.
        // imeActive is a cache flipped by activate / deactivate / the TIS notification,
        // and every OFF path depends on isVietTelexSelected() →
        // TISCopyCurrentKeyboardInputSource(), which can still report the OUTGOING
        // source at the instant of a switch. So a VietTelex→English switch can be missed
        // by BOTH the deactivate and notification paths, latching imeActive true — the
        // tap then transforms in English forever ("gõ ra dấu" in English mode). Nothing
        // else re-checks, so re-verify here, throttled. Only while active: the common
        // English case (imeActive already false) returns just below at zero cost; the
        // turn-ON direction stays covered by the unconditional activateServer→markActive.
        // TIS copy runs at most once per window — but TIS is NOT documented safe off
        // the main thread, so with the tap on its own thread the check hops to MAIN
        // asynchronously. The correction lands via the locked selectionChanged() and
        // takes effect on the NEXT keystroke — one key later than the old synchronous
        // check, which is fine for a ≤750ms-throttled self-heal of an already-stale flag.
        if active {
            let now = DispatchTime.now().uptimeNanoseconds
            if now &- lastReconcileNs > reconcileWindowNs {
                lastReconcileNs = now
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !TelexInputController.isVietTelexSelected() {
                        self.selectionChanged(isVietTelex: false)
                        DebugLog.log("reconcile: VietTelex not selected → tap dormant (healed stale imeActive)")
                    }
                }
            }
        }

        guard imeActive else {
            // Went inactive with a word half-composed (e.g. the async reconcile above
            // just corrected a stale flag): abandon it so a later re-activate can't
            // resume a stale composition. `engine` is tap-thread confined — reset here,
            // never from the main-thread paths that flip the flag. An EMPTY engine can
            // still hold the re-open snapshot of the word it just committed, which must
            // not survive an inactive stretch either — hence the second test, kept as a
            // cheap Int compare so an idle machine (VietTelex installed, ABC active)
            // still pays nothing per key.
            if !engine.isEmpty || engine.canReopenLastCommit { engine.reset() }
            return pass
        }

        // A ⌘/⌃/⌥ combo (⌘A select-all, ⌘C, ⌃C…) is never Telex input, and IMK does
        // NOT route ⌘-combos to the IMKit controller — so the controller cannot drop
        // its composition on its own (that was the "⌘A then type edits the old word
        // instead of replacing the selection" bug). The tap sees every key globally:
        // reset our engine AND signal the controller.
        // Runs for ALL apps, before the tap-mode gate.
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            // An empty engine can still hold the re-open snapshot, and ⌘A + ⌫ deletes a
            // SELECTION, not the boundary character that snapshot assumes — so the
            // no-op skip now tests for it too, still without leaving the fast path.
            if !engine.isEmpty || engine.canReopenLastCommit { engine.reset() }
            // ALWAYS notify: the IMKit controller's engine state is invisible from here,
            // so we cannot gate this on our own emptiness.
            NotificationCenter.default.post(name: .telexResetComposition, object: nil)
            // The chord itself is resolved by the APP, through macOS's live layout —
            // never by us, so pinning a layout could not reach it and ⌘R on a pinned
            // QWERTY fired ⌘P while macOS sat on Colemak (VTX fork's measurement).
            // Re-address the event here, the one place that sees every chord.
            remapChordKeyCode(event, shift: flags.contains(.maskShift))
            // Sticky-source: chord = có thể là hotkey đổi input source (⌃Space/custom)
            // — dấu vết để KHÔNG giành lại (StickyInputSource).
            StickyInputSource.shared.noteUserModifierChord()
            return pass
        }

        // Word-table class: cell-navigation keys some apps swallow without telling
        // the IME (see NavKeyWitness). Stamp BEFORE the tap-mode gate — the witness
        // is for the IMKit controller, whatever mode the tap picks for this app.
        // ⌘/⌃/⌥ chords returned above and never stamp; stamp() itself ignores
        // non-navigation keycodes.
        NavKeyWitness.stamp(keycode: event.getIntegerValueField(.keyboardEventKeycode))

        // Decide whether the tap handles this app, and with which emit mode:
        //  - Spotlight (window-list) / Chromium → Shift+Left selection-replace.
        //  - MS Office → empty-char reset (Shift+Left would select adjacent cells).
        //  - Terminals (fallbackApps) → Backspace+retype.
        //  - Anything else → the IMKit in-place path handles it (pass through).
        let id = FrontmostApp.shared.bundleID
        // Spotlight is IN-PLACE by default (builtInInPlaceApps) — the tap engages
        // only for an explicit tap-family manual pick. Manual pin consulted FIRST:
        // isVisible kicks a CGWindowList background scan every 200ms while typing,
        // which nobody should pay for unless Spotlight was actually pinned.
        let spotlightManual = AppState.shared.manualMode(AppState.spotlightBundleID)
        // One-lock snapshot for the whole selection/emptyReset/tap chain below —
        // was 3 separate AppState round trips, two of them re-reading isTrusted.
        let tapKeyRouting = AppState.shared.tapRouting(id)
        if (spotlightManual == .selection || spotlightManual == .tap
                || spotlightManual == .emptyReset),
           SpotlightDetector.isVisible {
            switch spotlightManual {
            case .selection: emitMode = .selection
            case .tap: emitMode = .backspace
            case .emptyReset: emitMode = .emptyReset
            default: engine.reset(); return pass
            }
        } else if tapKeyRouting.selection {
            // Chromium omnibox: inline autocomplete keeps the suggestion SELECTED to the
            // right of the caret, so a Shift+Left select-overtype (.selection) is offset
            // just like a plain Backspace — the first Shift+Left shrinks the suggestion
            // selection instead of grabbing the typed char, desyncing the screen from the
            // engine model ("google"→ screen "goôgle" while engine holds "gôgle", then the
            // boundary restore lands "gooogle"). Route per-field BROWSERS through the
            // U+202F autocomplete-cancel dance Office uses (.emptyReset): type U+202F to
            // dismiss the suggestion, delete it + the stale chars, then retype. Spotlight
            // and manual .selection pins (no such inline-autocomplete selection) stay on
            // .selection. Field-verified in a live omnibox 2026-07-24.
            emitMode = AppState.shared.selectionEmitMode(id)
        } else if tapKeyRouting.emptyReset {
            emitMode = .emptyReset
        } else if tapKeyRouting.tap {
            emitMode = .backspace
        } else if !SyntheticKeyboard.queueDrained(),
                  AppState.shared.manualMode(id) == .inPlace {
            // EDGE-TAP ordering guard (06/08/2026): the IMKit controller just posted
            // a synthetic burst for an offset-0 word in this manually-pinned
            // In-place app (edgeTapWord). A physical key passing through natively
            // NOW would overtake the still-draining burst (repro: "cos " typed with
            // 0ms gaps — the space landed first and the burst's ⌫ ate it → "coó").
            // Re-post it as a fresh NO-MAGIC copy: it queues BEHIND the burst and
            // re-enters IMKit as a real key, so composition continues in order.
            // notePostedKeyDown inside extends the in-flight chain, keeping any
            // further rollover keys ordered too. queueDrained() is true in the
            // common case, so plain typing in pinned apps never reaches the
            // manualMode lookup.
            SyntheticKeyboard.postBoundaryCopy(of: event)
            return nil
        } else {
            engine.reset(); return pass
        }
        // Spotlight overlay WITHOUT an explicit tap-family pin: the routing verdict
        // above belongs to the app BEHIND the overlay (FrontmostApp stays iTerm/
        // Chrome while Spotlight is up), but the keys land in Spotlight's field,
        // whose inline autocomplete breaks every synthetic emit — a backspace eats
        // the SELECTED SUGGESTION instead of the last letter, reordering the word
        // (field report 2026-07-31: "pas" in Spotlight over iTerm → garbled; log
        // showed tap-emit mode=backspace into client=com.apple.Spotlight). The
        // shipped contract (see the tap-defer NOTE in TelexInputController.handle)
        // is RAW PASSTHROUGH here: no composition from either side. isVisible is a
        // cached bool (stale-read + async refresh), read only for keys already
        // routed to a tap-family app — plain in-place apps still never pay for it.
        if Self.spotlightOverlayForcesRaw(visible: SpotlightDetector.isVisible,
                                          manualPin: spotlightManual) {
            engine.reset(); return pass
        }
        // Secure input (native password prompts) OR an AX-reported password field (web
        // login forms, which do NOT switch secure input on): never compose, never emit —
        // pass the raw key through untouched. See SecureFieldDetector.
        if IsSecureEventInputEnabled() || SecureFieldDetector.isSecure {
            engine.reset(); return pass
        }

        // Reflect the current "bỏ dấu tự do" setting (feed/backspace/boundary all
        // re-parse `raw` and honor it).
        engine.apply(AppState.shared.engineFlags())

        // Signpost the tap-handled keystroke; message = emit mode (see Instrumentation).
        let spState = Signposts.poster.beginInterval("tap.handle",
                                                     id: Signposts.poster.makeSignpostID())
        defer {
            let mode = emitMode == .selection ? "selection"
                     : emitMode == .emptyReset ? "emptyReset" : "backspace"
            // privacy: .public — internal emit-mode name, never user text (see imk.handle).
            Signposts.poster.endInterval("tap.handle", spState, "\(mode, privacy: .public)")
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if keyCode == kDelete {
            lastTapKeyWasBoundary = false   // ⌫ is word-adjacent editing, not a boundary
            if engine.isEmpty {
                // ⌫ on the boundary character the last word ended with re-opens that
                // word ("tháy" ␣ ⌫ then `a` → "thấy" — issue #40); the ⌫ still goes
                // through and deletes the boundary character either way.
                if !tryReopenLastCommitTap(id: id) {
                    // Deleting previously-committed text: the "previous word" is now unclear,
                    // so drop the English context (undetermined → Vietnamese). In-word
                    // backspace (buffer non-empty, below) keeps it — prev word unchanged.
                    engine.resetContext()
                }
                // Not composing -> real Backspace, unless a synthetic burst is still
                // draining (it must land first or the delete hits the wrong char).
                if SyntheticKeyboard.queueDrained() { return pass }
                SyntheticKeyboard.postKey(CGKeyCode(kVK_Delete))
                return nil
            }
            if case let .replace(bs, insert) = engine.backspace() {
                SyntheticKeyboard.apply(backspaces: bs, insert: insert, mode: emitMode)
            }
            return nil
        }
        if keyCode == kReturn || keyCode == kEnter || keyCode == kTab || keyCode == kEscape {
            lastTapKeyWasBoundary = true
            // A newline breaks the English run: the first word on the next line has no
            // preceding word, so "is" → "í". Reset AFTER emitBoundary commits (and
            // classifies) the current word — the defer must sit at THIS block's scope;
            // nested inside `if { defer {...} }` it fired immediately and wiped the
            // context BEFORE the restore decision ("early too⏎" → "early tô", same
            // defer-scope bug as the IMKit path — field report 15/08/2026).
            let newlineKey = keyCode == kReturn || keyCode == kEnter
            defer { if newlineKey { engine.resetContext() } }
            // Commit the composed word, then prefer passing the REAL key through: a
            // synthetic (isTrusted=false) Tab/Return doesn't trigger the app's own
            // handling — shell Tab-completion never fires, web/Electron "Enter to send"
            // is ignored (falls back to newline), TUIs (Claude Code) treat it oddly.
            // Since in tap mode EVERY key is composed, the buffer is rarely empty when
            // Tab is pressed mid-token (e.g. "cd Doc⇥"), so the old empty-check wasn't
            // enough. Only when auto-restore ACTUALLY rewrote the word (emitBoundary →
            // true) do we suppress + re-emit synthetically, so the boundary key lands
            // AFTER the async edit; otherwise the real key passes through untouched.
            // None of these leaves ONE character after the word the way a space does
            // (Enter sends the message, Tab moves focus/completes, Esc inserts
            // nothing), so a following ⌫ is not deleting a boundary character and must
            // not re-open the word — see tryReopenLastCommitTap.
            defer { engine.forgetLastCommit() }
            if engine.isEmpty, SyntheticKeyboard.queueDrained() { return pass }
            if emitBoundary(suppressAutoRestore: false) || !SyntheticKeyboard.queueDrained() {
                reemit(keyCode: keyCode, string: nil, original: event)
                return nil
            }
            return pass
        }

        // Read the typed character. Stack tuple, NOT `[UniChar](repeating:)`: an Array
        // literal here was one malloc + free on EVERY key, inside the callback macOS
        // times out — the last allocation left on the tap path after the engine was
        // made zero-alloc. `withUnsafeMutableBufferPointer` on a homogeneous tuple is
        // the documented way to hand C a fixed 4-slot buffer with no heap traffic.
        var len = 0
        var slots: (UniChar, UniChar, UniChar, UniChar) = (0, 0, 0, 0)
        let first: UniChar? = withUnsafeMutableBytes(of: &slots) { raw in
            let buf = raw.bindMemory(to: UniChar.self)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len,
                                           unicodeString: buf.baseAddress)
            return len >= 1 ? buf[0] : nil
        }
        guard let unit = first, let scalar = Unicode.Scalar(unit) else {
            // Dead/function key: flush the word, let the odd key through.
            // (no shortcut expansion — not an explicit text boundary)
            lastTapKeyWasBoundary = true
            emitBoundary(suppressAutoRestore: false, allowShortcuts: false)
            engine.forgetLastCommit()      // nothing predictable landed after the word
            return pass
        }
        // Navigation / function keys (←↑→↓, Home/End/PageUp/PageDown, forward-delete,
        // F1-F12): iTerm delivers arrows as CONTROL chars 0x1C–0x1F (not the 0xF700
        // function-key range as elsewhere). Anything reaching here with a control char
        // (< 0x20; Return/Tab/Esc/Backspace were already handled by keycode) or a
        // function-key codepoint is navigation, NOT text: flush the word and PASS THE
        // REAL KEY THROUGH so cursor/history work — never re-emit it as inserted text
        // (re-emitting arrows as 0x1C killed arrow-key navigation).
        if unit < 0x20 || (unit >= 0xF700 && unit <= 0xF8FF) {
            lastTapKeyWasBoundary = true
            emitBoundary(suppressAutoRestore: false, allowShortcuts: false)
            engine.forgetLastCommit()      // navigation: the caret left the word behind
            return pass
        }
        // Layout remap: the tap is handed the character macOS produced with ITS
        // layout, which is the one the user overrode — re-derive it from the keycode.
        // Modifier combos are excluded (they are shortcuts, not text) and an
        // unmappable key keeps the OS's character, so this can only ever narrow to
        // plain ASCII the pinned layout actually defines.
        var ch = Character(scalar)
        if let translator = KeyboardLayoutOverride.translator,
           flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
           let remapped = translator.character(keyCode: UInt16(keyCode),
                                               shift: flags.contains(.maskShift)) {
            ch = remapped
        }
        // VNI: digits carry the diacritics, so they belong to the WORD, not the boundary
        // (same fix as the IMKit path — issue #28, 2026-07-27).
        guard let ascii = ch.asciiValue,
              isWordKey(ascii, vniMode: engine.vniMode,
                        bracketVowels: engine.bracketVowels) else {
            lastTapKeyWasBoundary = true
            // Non-letter boundary (space, digit outside VNI, punctuation). Brackets skip
            // auto-restore (code context). Mirror the Return/Tab handling above: only
            // when a rewrite ACTUALLY happened (emitBoundary → true) or a synthetic
            // burst is still draining must we suppress + re-emit synthetically, so the
            // boundary key lands AFTER the async edit. Otherwise pass the REAL keyDown
            // through — no two window-server round trips per space, and the app sees a
            // genuine key (keycode intact), not a text-only keycode-0 event. Respects
            // tapNativeFastPath like the letter fast-path below. (modifyInPlace adds
            // nothing here: with no rewrite pending the untouched event is already
            // exactly what should land, in every emit mode.)
            let rewrote = emitBoundary(suppressAutoRestore: isBracketUnichar(ch.utf16.first ?? unit))
            // A plain ascii boundary (space, punctuation, digit) leaves exactly ONE
            // character after the word, which is what makes the next ⌫ re-openable
            // (issue #40). Anything else — an option-key symbol, a multi-scalar
            // sequence — is not worth reasoning about: forget the word.
            if !ch.isASCII { engine.forgetLastCommit() }
            // Layout pinned → the native pass-through would type the OS layout's
            // character, not ours: fall through to reemit, which carries String(ch).
            if !rewrote, AppState.shared.tapNativeFastPath, SyntheticKeyboard.queueDrained(),
               KeyboardLayoutOverride.translator == nil {
                return pass
            }
            reemit(keyCode: keyCode, string: String(ch))
            return nil
        }

        // RE-EDIT (experimental, opt-in): a tone/mark key on an EMPTY engine right
        // after a word means "add this diacritic to that word" — seed from the text
        // already on screen so the replace below edits IT instead of starting fresh.
        if Self.reEditGateOpen(engineIsEmpty: engine.isEmpty, reEditEnabled: AppState.shared.reEditWord,
                               isDiacriticKey: TelexInputController.isDiacriticOnlyKey(ascii, vni: engine.vniMode),
                               emitMode: emitMode,
                               lastKeyWasBoundary: lastTapKeyWasBoundary) {
            tryReEditWordTap(id: id)
        }
        lastTapKeyWasBoundary = false   // this key is a word key

        // Ordering rule: a native letter must never race ahead of a still-queued
        // synthetic edit ("nuwax" showed as "nuẵ" because native 'a' landed before
        // the synthetic ư from 'w'). Historically EVERY key was therefore suppressed
        // and re-emitted synthetically — 2 posted events per plain letter, each a
        // real window-server round trip. The in-flight counter restores the native
        // fast path safely: a NON-TRANSFORMING letter passes through untouched
        // whenever no synthetic keyDown is still in flight (the common case), and
        // only falls back to the synthetic channel while a burst is draining. The
        // tap callback is serial, so the decision itself cannot race.
        switch engine.feed(ch) {
        case .passthrough:
            if AppState.shared.tapNativeFastPath, SyntheticKeyboard.queueDrained(),
               KeyboardLayoutOverride.translator == nil {
                return pass                               // native: zero synthetic events
            }
            SyntheticKeyboard.apply(backspaces: 0, insert: String(ch), mode: emitMode)
        case .none:
            break
        case let .replace(bs, insert):
            // B1: a single-char transform (w→ư) rewrites this event in place; anything
            // with backspaces, multi-char, or a draining burst keeps the synthetic path.
            if modifyInPlace(event: event, backspaces: bs, insert: insert) { return pass }
            SyntheticKeyboard.apply(backspaces: bs, insert: insert, mode: emitMode)
        }
        return nil
    }

    /// Task B1 — modify the physical CGEvent in place instead of suppress + post.
    /// When a tone edit is a pure single-character insert (0 backspaces) in .backspace
    /// emit mode and no synthetic burst is still draining, rewrite the event the tap
    /// callback is holding via keyboardSetUnicodeString and let it PASS. The event
    /// keeps its real keycode and timing, so ZERO synthetic events are posted — two
    /// window-server round trips saved per w→ư / boundary re-emit. Because it is never
    /// posted it does NOT count as in-flight synthetic (correct: nothing to observe).
    /// The modified NSEvent still reaches the IMKit controller, but terminals are
    /// tap-mode-deferred there (usesTapMode → handle returns false) so the app inserts
    /// it natively — never double-composed.
    ///
    /// Restricted to .backspace mode on purpose: .selection needs a Shift+Left select
    /// first and .emptyReset needs the U+202F dance, neither expressible as a single
    /// in-place rewrite. The queueDrained() guard preserves ordering — while a burst is
    /// draining we decline so the caller keeps the old suppress+post path and the edit
    /// still lands after the queued events.
    /// Returns true iff it rewrote `event` (caller should then return it as pass).
    @inline(__always)
    private func modifyInPlace(event: CGEvent, backspaces: Int, insert: String) -> Bool {
        guard AppState.shared.tapModifyEventInPlace,
              emitMode == .backspace,
              backspaces == 0,
              insert.count == 1,               // single character (any UTF-16 length)
              SyntheticKeyboard.queueDrained()
        else { return false }
        let utf16 = Array(insert.utf16)
        utf16.withUnsafeBufferPointer { buf in
            event.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        return true
    }

    // MARK: - Re-edit the word before the caret (tap path)

    /// TAP counterpart of `TelexInputController.tryReEditWord` — same feature ("toan"
    /// + s → toán without retyping), same safety gates, ported for apps that compose
    /// via backspace-retype instead of IMKit insertText (field report 2026-08-07:
    /// worked in TextMate — in-place — but not in Google Chrome page content, which
    /// the 06/08 axDetect policy moved onto THIS path). Reads via Accessibility
    /// instead of `IMKTextInput.attributedSubstring`; needs no anchor/onLen bookkeeping
    /// the way the IMKit version does, because every tap edit already targets the LIVE
    /// caret (backspace N + retype), never a tracked range.
    /// Pure gate, factored out for testing: everything about WHETHER to attempt
    /// re-edit that doesn't need a live Accessibility tree. Same per-field exclusion
    /// as IMKit's version: only the omnibox/search-bar's inline autocomplete makes
    /// re-editing unsafe, so this keys off emitMode (per FIELD), not the app —
    /// page content is exactly where re-edit is wanted, and page content is exactly
    /// what emits .backspace (.selection/.emptyReset are the per-field browser modes
    /// this excludes, matching FocusedFieldDetector.wantsSelection on the IMKit side).
    /// `lastKeyWasBoundary`: the PREVIOUS physical key in this tap ended a word
    /// (space/Return/Tab/Esc/punctuation/navigation). A tone key right after a
    /// boundary must NOT re-edit — the word before the caret is separated from it
    /// by that boundary. The IMKit version gets this for free by reading the REAL
    /// text (a trailing space stops `trailingWord`); the tap reads via AX, and a
    /// laggy AX tree (JetBrains terminals) can still show the text WITHOUT the
    /// just-typed space — issue #38 (2026-08-12): `git st` in PhpStorm's terminal
    /// seeded "git" across the space and the `s` of "st" became sắc → "gít".
    /// The keystream itself is the one boundary signal AX lag can't fake.
    static func reEditGateOpen(engineIsEmpty: Bool, reEditEnabled: Bool,
                              isDiacriticKey: Bool, emitMode: TapEmit,
                              lastKeyWasBoundary: Bool) -> Bool {
        engineIsEmpty && reEditEnabled && isDiacriticKey && emitMode == .backspace
            && !lastKeyWasBoundary
    }

    private func tryReEditWordTap(id: String?) {
        guard let caret = AXTextEdit.readCaret(), caret > 0 else { return }
        let window = min(caret, 24)
        guard let text = AXTextEdit.readString(at: caret - window, length: window) else { return }
        guard text == text.precomposedStringWithCanonicalMapping else {
            DebugLog.log("re-edit(tap) \(id ?? "?"): skipped (field text is not precomposed)")
            return
        }
        guard let word = TelexInputController.trailingWord(text) else { return }
        guard (word as NSString).length <= caret, engine.seed(word) else { return }
        DebugLog.log("re-edit(tap) \(id ?? "?"): seeded \((word as NSString).length) chars before caret")
    }

    // MARK: - Re-open the last committed word on ⌫ (issue #40)

    /// TAP counterpart of `TelexInputController.tryReopenLastCommit`: the ⌫ being
    /// handled deletes the boundary character that ended the last word, so put that
    /// word back in the buffer and keep editing it. No anchor bookkeeping is needed
    /// here — every tap edit targets the live caret — but the same screen check is:
    /// the characters the word should occupy are read through Accessibility and
    /// compared before anything is re-opened, so an app that swallowed the boundary
    /// key or autocorrected the word just gets the old behavior. No AX text (plain
    /// terminals) means no verification, hence no re-open.
    /// `.selection`/`.emptyReset` fields are excluded for the same reason re-edit
    /// excludes them: inline autocomplete rewrites text underneath us.
    private func tryReopenLastCommitTap(id: String?) -> Bool {
        // Same experimental gate as the IMKit side (and as re-edit): one opt-in for
        // every "reach back into the previous word" behavior. Checked before the
        // canReopen Int compare so an opted-out machine pays nothing extra.
        guard AppState.shared.reEditWord else { return false }
        guard engine.canReopenLastCommit else { return false }
        // The silent-exit reasons below each get a debug line (reason only, never
        // text): the Discord field report on #40 died in one of them with nothing in
        // the log to say which — every plain ⌫ passes the canReopen guard above at
        // most once per commit, so these cannot spam.
        guard emitMode == .backspace else {
            engine.forgetLastCommit()
            DebugLog.log("⌫ re-open(tap) \(id ?? "?"): skipped (emitMode not backspace)")
            return false
        }
        guard let caret = AXTextEdit.readCaret() else {
            engine.forgetLastCommit()
            DebugLog.log("⌫ re-open(tap) \(id ?? "?"): skipped (no AX caret)")
            return false
        }
        guard let word = engine.reopenLastCommit() else {
            DebugLog.log("⌫ re-open(tap) \(id ?? "?"): skipped (replay mismatch)")
            return false
        }
        let wordLen = (word as NSString).length
        let start = caret - 1 - wordLen                 // this ⌫ removes the boundary char
        guard start >= 0,
              let text = AXTextEdit.readString(at: start, length: wordLen),
              text == word
        else {
            engine.reset()
            DebugLog.log("⌫ re-open(tap) \(id ?? "?"): skipped (screen disagrees)")
            return false
        }
        DebugLog.log("⌫ re-open(tap) \(id ?? "?"): \(wordLen) chars back in the buffer")
        return true
    }

    /// Emit a shortcut expansion / auto-restore rewrite for the composed word. Returns
    /// true if anything was rewritten (caller then re-emits the boundary key after it).
    @discardableResult
    private func emitBoundary(suppressAutoRestore: Bool, allowShortcuts: Bool = true) -> Bool {
        guard !engine.isEmpty else { engine.reset(); return false }
        // Capture BOTH forms before reset() wipes them. The composed word is what's on
        // screen (drives the backspace count); the raw keystrokes are what the user
        // actually typed.
        let word = engine.composed
        let rawWord = engine.rawKeystrokes
        let onScreen = word.unicodeScalars.count
        // Shortcut expansion: try the COMPOSED form first, then fall back to the RAW
        // keystrokes. A shortcut key containing Telex triggers (s f r x j w, doubled
        // vowels) is transformed by composition and so can NEVER match on `composed`
        // ("ddc" composes to "đc"); the raw form recovers it. Backspaces are always the
        // on-screen composed scalar count regardless of which form matched.
        if allowShortcuts,
           let expansion = (word.isEmpty ? nil : AppState.shared.shortcuts[word])
                        ?? AppState.shared.shortcuts[rawWord] {
            engine.reset()
            SyntheticKeyboard.apply(backspaces: onScreen, insert: expansion, mode: emitMode)
            return true
        }
        let restore = AppState.shared.autoRestore && !suppressAutoRestore
        if case let .replace(bs, insert) = engine.commitBoundary(autoRestore: restore) {
            SyntheticKeyboard.apply(backspaces: bs, insert: insert, mode: emitMode)
            return true
        }
        return false
    }

    private func reemit(keyCode: Int, string: String?, original: CGEvent? = nil) {
        switch keyCode {
        case kReturn, kEnter, kTab, kEscape:
            // Prefer a stamped COPY of the user's own keyDown (HID source intact):
            // Electron editors newline on a private-source synthetic Return but run
            // their real Enter-to-send handler on a hardware-identical one.
            if let original {
                SyntheticKeyboard.postBoundaryCopy(of: original)
            } else if keyCode == kTab {
                SyntheticKeyboard.postKey(CGKeyCode(kVK_Tab))
            } else if keyCode == kEscape {
                SyntheticKeyboard.postKey(CGKeyCode(kVK_Escape))
            } else {
                SyntheticKeyboard.postKey(CGKeyCode(kVK_Return))
            }
        default:              if let s = string { SyntheticKeyboard.apply(backspaces: 0, insert: s, mode: emitMode) }
        }
    }
}

@inline(__always)
private func isLetterAscii(_ c: UInt8) -> Bool {
    (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z")) ||
    (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
}

@inline(__always)
private func isBracketUnichar(_ c: UInt16) -> Bool {
    switch c {
    case UInt16(UInt8(ascii: "[")), UInt16(UInt8(ascii: "]")),
         UInt16(UInt8(ascii: "{")), UInt16(UInt8(ascii: "}")),
         UInt16(UInt8(ascii: "(")), UInt16(UInt8(ascii: ")")):
        return true
    default:
        return false
    }
}
