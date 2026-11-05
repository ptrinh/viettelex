import XCTest
@testable import VietTelex

// App-side coverage for the field-hardening batch: remote-desktop passthrough
// routing (item 3) and tap-lifecycle safety without Accessibility (item 2).
final class RemoteAndTrustHardeningTests: XCTestCase {

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        // A leaked poll timer would keep calling ensureRunning() every 3s on
        // RunLoop.main for the rest of the test run, across every other suite.
        TerminalTapController.shared._testDisarmTrustPoll()
        super.tearDown()
    }

    /// Issue #128: VM / remote còn thiếu (VirtualBox, Horizon, Parsec, Jump, Parallels Coherence).
    func testVirtualMachinePassthroughRouting() {
        for id in ["org.virtualbox.app.VirtualBoxVM", "com.vmware.horizon", "tv.parsec.www",
                   "com.p5sys.jump.mac.viewer", "com.parallels.desktop.console", "com.vmware.fusion",
                   "com.parallels.winapp.12345.notepad", "com.parallels.macvm"] {
            XCTAssertEqual(AppState.shared.autoResolvedMode(id), .passthrough, id)
        }
    }

    func testRemoteDesktopPassthroughRouting() {
        for id in ["com.carriez.rustdesk", "com.philandro.anydesk"] {
            XCTAssertEqual(AppState.shared.autoResolvedMode(id), .passthrough, id)
            XCTAssertTrue(AppState.builtInPassthroughApps.contains(id), "\(id) missing from plist")
        }
    }

    /// iPhone Mirroring reuses the OLD Screen Sharing bundle id — it used to sit in
    /// the remote-desktop passthrough bucket above, until maintainer field-test
    /// 07/08/2026 confirmed it bridges Continuity to a REAL text field on the phone
    /// (not raw scancodes for a guest OS), so it belongs in inPlace instead.
    func testIPhoneMirroringIsInPlaceNotPassthrough() {
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.apple.ScreenContinuity"), .inPlace)
        XCTAssertFalse(AppState.builtInPassthroughApps.contains("com.apple.ScreenContinuity"))
    }

    /// Spotlight redesign (macOS 26.4+/27): cửa sổ không mang tên process
    /// "Spotlight" nữa, nên CGWindowList scan trả false. Latch từ IMK
    /// (noteFocused/noteUnfocused) phải thắng scan, không thì tap — quyết theo
    /// frontmost = app phía sau overlay — gõ song song với IMKit ("vieejt" →
    /// "vieêệt" khi mở Spotlight từ iTerm, field 16/09/2026).
    func testSpotlightClientLatchOutranksTheWindowScan() {
        SpotlightDetector.noteFocused()
        XCTAssertTrue(SpotlightDetector._testClientFocused)
        XCTAssertTrue(SpotlightDetector.isVisible, "latch phải giữ visible dù scan nói false")
        // Gate của tap: visible + không ép tay họ tap ⇒ tap pass raw, IMKit lo.
        XCTAssertTrue(TerminalTapController.spotlightOverlayForcesRaw(
            visible: SpotlightDetector.isVisible, manualPin: nil))
        SpotlightDetector.noteUnfocused()
        XCTAssertFalse(SpotlightDetector._testClientFocused)
        XCTAssertFalse(SpotlightDetector._testVisible)
        // Seam của test vẫn mô phỏng được verdict thuần từ scan.
        SpotlightDetector._testSetVisible(true)
        XCTAssertFalse(SpotlightDetector._testClientFocused)
    }

    func testChromeRemoteDesktopPWAIsPassthroughNotAxDetect() {
        // Dedicated CRD window (PWA / Chrome App) must not inherit Chrome's axDetect.
        XCTAssertEqual(AppState.shared.autoResolvedMode(
            "com.google.Chrome.app.Default-inomeogfingihgjfjlpeplalcfajhgai"), .passthrough)
        XCTAssertEqual(AppState.shared.autoResolvedMode(
            "com.google.Chrome.app.cmkncekebbebpfilplodngbpllndjkfo"), .passthrough)
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.google.Chrome"), .axDetect)
    }

    func testBundledPlistCarriesTheNewRules() {
        // the SHIPPED resource (not just the repo file) must contain the ids
        guard let url = Bundle(for: TelexInputController.self)
                .url(forResource: "typing-modes", withExtension: "yml"),
              let data = try? Data(contentsOf: url),
              let dict = ShortcutImporter.parse(data)
        else { return XCTFail("bundled typing-modes.yml unreadable") }
        XCTAssertEqual(dict["com.carriez.rustdesk"], "passthrough")
        XCTAssertEqual(dict["com.philandro.anydesk"], "passthrough")
        XCTAssertEqual(dict["com.apple.ScreenContinuity"], "inPlace")
        XCTAssertEqual(dict["ru.keepcoder.Telegram"], "tap")
        XCTAssertEqual(dict["com.facebook.archon.developerID"], "tap")
        // Spark Classic (issue #47): WebView composer — WebKit macOS 26 swallows the
        // tap's synthetic burst (the #44 class); reporter field-verified in-place.
        XCTAssertEqual(dict["com.readdle.smartemail-Mac"], "inPlace")
        // Outlook (Facebook field report 14/08): same WKWebView-compose class —
        // diacritic words died on the tap channel; Word/PowerPoint were already
        // inPlace, Outlook was simply missing from the table.
        XCTAssertEqual(dict["com.microsoft.Outlook"], "inPlace")
        XCTAssertEqual(dict["com.apple.mail"], "inPlace")
    }

    /// Messenger desktop (unofficial Electron wrapper) — field report 2026-08-11:
    /// fell through the safe-unknown-app default and showed marked text/underline.
    func testMessengerDesktopIsTapNotUnknown() {
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.facebook.archon.developerID"), .tap)
        XCTAssertTrue(AppState.builtInFallbackApps.contains("com.facebook.archon.developerID"))
    }

    /// Telegram was on the field-verified in-place batch; maintainer report moved it
    /// to tap (backspace-retype) — same Electron/CEF edge-of-word class as Lark/
    /// Slack/Discord/VSCode above, not actually clean in-place.
    func testTelegramIsTapNotInPlace() {
        XCTAssertEqual(AppState.shared.autoResolvedMode("ru.keepcoder.Telegram"), .tap)
        XCTAssertTrue(AppState.builtInFallbackApps.contains("ru.keepcoder.Telegram"))
    }

    // Watchdog/lifecycle safety: with Accessibility revoked, ensureRunning must
    // be a no-op that never creates a tap (the watchdog calls it every 3s now —
    // it has to be safe to call from any state).
    func testEnsureRunningIsSafeWithoutTrust() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        controller.ensureRunning()          // idempotent
        XCTAssertFalse(controller.isRunning)
    }

    // Field report 2026-08-11: a process already running when the user granted
    // Accessibility never picked up the change — nothing re-attempts start() unless
    // an app/focus switch or the (occasionally missed) TCC notification fires. Fix:
    // ensureRunning() must itself arm a retry poll while untrusted, and disarm it the
    // moment trust returns, so a grant is noticed within one tick with no restart.
    func testEnsureRunningArmsRetryPollWhileUntrusted() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        XCTAssertTrue(controller._testTrustPollIsRunning,
                      "still untrusted after ensureRunning() — the retry poll must be armed")
    }

    func testTrustPollDisarmsExplicitly() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        XCTAssertTrue(controller._testTrustPollIsRunning)
        controller._testDisarmTrustPoll()
        XCTAssertFalse(controller._testTrustPollIsRunning)
    }

    /// Repeated calls while still untrusted (activateServer fires on every app
    /// switch) must reuse the SAME poll timer, not leak a fresh one each time —
    /// a leaked timer would fire ensureRunning() at an ever-increasing rate.
    func testEnsureRunningDoesNotLeakDuplicatePollTimers() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        let firstToken = controller._testTrustPollToken
        XCTAssertNotNil(firstToken)
        controller.ensureRunning()
        controller.ensureRunning()
        XCTAssertEqual(controller._testTrustPollToken, firstToken,
                       "second/third ensureRunning() while untrusted must not replace the poll timer")
    }

    /// A fresh arm after an explicit disarm must actually re-arm (proves the dedup
    /// guard keys off "is one running right now", not off "has one ever run" — a
    /// latched flag would leave the poll permanently disabled after any disarm).
    func testTrustPollCanReArmAfterDisarm() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        XCTAssertNotNil(controller._testTrustPollToken)
        controller._testDisarmTrustPoll()
        XCTAssertNil(controller._testTrustPollToken)

        controller.ensureRunning()
        XCTAssertNotNil(controller._testTrustPollToken, "must re-arm, not stay disarmed forever")
    }
}
