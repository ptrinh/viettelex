import XCTest
import TelexCore
@testable import VietTelex

/// Field report 03/11/2026 (WhatsApp desktop, macOS): gõ nhanh "looix" ra "loôiỗi"
/// (đúng: "lỗi"); gõ chậm thì không sao; sau vài lần ⌫ chữ "nhảy" sai chỗ; gõ trộn
/// Anh-Việt gặp nhiều hơn.
///
/// Gốc: WhatsApp nhận insertText nhưng áp vào model BẤT ĐỒNG BỘ, và khi lệnh trước
/// còn chờ thì replacementRange vượt văn bản (chưa cập nhật) của nó bị bỏ ⇒ lệnh
/// thay thành lệnh CHÈN tại con trỏ. FakeIMKClient.asyncApply mô phỏng đúng mô hình
/// đó; `settle()` = run loop của app quay một vòng.
final class AsyncApplyClientTests: XCTestCase {
    private let whatsApp = "net.whatsapp.WhatsApp"
    private var savedBreaker = true
    private var savedAutoRestore = true

    override func setUp() {
        super.setUp()
        Accessibility.testTrustOverride = true
        FocusedFieldDetector._testSetCached(false)
        FocusedFieldDetector._testSetMarked(false)
        FocusedFieldDetector._testSetPassthrough(false)
        SystemInlinePrediction.setForTesting(false)
        // Không viết hoa đầu câu / dấu chấm tự động: test chỉ nói về thứ tự áp lệnh.
        SystemAutoTextSettings.shared._testSet(.init(period: false, capitalize: false, quotes: false, dashes: false))
        savedBreaker = AppState.shared.tapCascadeBreaker
        AppState.shared.tapCascadeBreaker = false
        savedAutoRestore = AppState.shared.autoRestore
        AppState.shared.autoRestore = true
        DebugLog.clear()
    }

    override func tearDown() {
        TelexInputController._testCatchUpSettleHook = nil
        Accessibility.testTrustOverride = nil
        SystemInlinePrediction.setForTesting(nil)
        AppState.shared.tapCascadeBreaker = savedBreaker
        AppState.shared.autoRestore = savedAutoRestore
        AppState.shared.currentBundleID = nil
        FrontmostApp.shared._testSetBundleID(nil)
        super.tearDown()
    }

    /// Harness trên client async; app chỉ "quay run loop" khi controller chờ nó.
    private func asyncHarness(_ bundleID: String, text: String = "") -> ControllerHarness {
        let h = ControllerHarness(bundleID: bundleID, text: text)
        h.client.asyncApply = true
        let c = h.client
        TelexInputController._testCatchUpSettleHook = { c.settle() }
        return h
    }

    private func dump(_ h: ControllerHarness) -> String {
        "text=\(h.client.string.debugDescription)\nclient:\n" + h.client.log.joined(separator: "\n")
            + "\nlog:\n" + DebugLog.snapshot(header: [])
    }

    /// Cùng chuỗi phím trên app đồng bộ (TextEdit) — đáp án tham chiếu.
    private func syncReference(_ steps: (ControllerHarness) -> Void) -> String {
        let saved = TelexInputController._testCatchUpSettleHook
        defer { TelexInputController._testCatchUpSettleHook = saved }
        let h = ControllerHarness(bundleID: "com.apple.TextEdit")
        steps(h)
        return h.client.string
    }

    private func backspace(_ h: ControllerHarness) {
        h.key(code: 51, chars: "\u{7f}", gap: 0.01)
    }

    // MARK: Mô hình tái hiện đúng lỗi field

    /// Đối chứng: cùng client async nhưng app KHÔNG nằm trong asyncApplyApps (không
    /// chờ) ⇒ ra đúng chuỗi rác trong video "loôiỗi". Chứng minh mô hình = lỗi thật.
    func testModelReproducesFieldGarbageWithoutCatchUp() {
        let h = asyncHarness("com.apple.TextEdit")
        h.type("looix", gap: 0.01)
        h.client.settle()
        XCTAssertEqual(h.client.string, "loôiỗi", dump(h))
    }

    // MARK: Regression

    func testFastTypingLooixInWhatsAppComposesLoi() {
        let h = asyncHarness(whatsApp)
        h.type("looix", gap: 0.01)
        h.client.settle()
        XCTAssertEqual(h.client.string, "lỗi", dump(h))
    }

    /// Từ thứ hai: anchor đọc ở đầu từ là caret CŨ (từ trước + dấu cách còn chờ) —
    /// chữ không được chèn vào giữa từ trước, lần thay đầu tiên phải neo lại đúng.
    func testFastSecondWordAfterPendingSpaceLandsAtEnd() {
        let h = asyncHarness(whatsApp)
        h.type("hello looix tieengs vieetj", gap: 0.01)
        h.client.settle()
        XCTAssertEqual(h.client.string, "hello lỗi tiếng việt", dump(h))
    }

    /// Trộn Anh-Việt: tự khôi phục từ tiếng Anh ở ranh giới là một lần thay CÓ RANGE.
    func testMixedEnglishRestoreInWhatsApp() {
        let h = asyncHarness(whatsApp)
        h.type("goog looix ", gap: 0.01)
        h.client.settle()
        XCTAssertEqual(h.client.string, "goog lỗi ", dump(h))
    }

    /// ⌫ giữa từ là một lần viết lại CÓ RANGE (anchor, onLen): phải đợi app áp xong,
    /// không được nối thêm vào cuối ("chữ nhảy sai chỗ").
    func testBackspaceMidWordThenRetypeInWhatsApp() {
        let steps: (ControllerHarness) -> Void = { h in
            h.type("ddi tieengs", gap: 0.01)
            self.backspace(h)
            self.backspace(h)
            h.type("t vieetj", gap: 0.01)
            self.backspace(h)
            h.type("tj", gap: 0.01)
        }
        let expected = syncReference(steps)
        XCTAssertFalse(expected.contains("\u{7f}"), expected)
        let h = asyncHarness(whatsApp)
        steps(h)
        h.client.settle()
        XCTAssertEqual(h.client.string, expected, dump(h))
    }

    /// Ở app thường (đồng bộ) không có phép chờ nào: không thêm XPC đọc caret.
    func testSyncClientNeverWaits() {
        var settles = 0
        TelexInputController._testCatchUpSettleHook = { settles += 1 }
        let h = ControllerHarness(bundleID: "com.apple.TextEdit")
        h.type("looix tieengs", gap: 0.01)
        XCTAssertEqual(h.client.string, "lỗi tiếng", dump(h))
        XCTAssertEqual(settles, 0)
    }

    // MARK: Pure loop

    func testAwaitCatchUpExits() {
        var clock: UInt64 = 0
        let now = { clock }
        // Đuổi kịp sau 2 vòng.
        var carets = [3, 4, 5]
        var r = TelexInputController.awaitClientCatchUp(
            expected: 5, budgetNs: 100, readCaret: { carets.removeFirst() }, settle: { clock += 1 }, now: now)
        XCTAssertTrue(r.caughtUp); XCTAssertEqual(r.polls, 3)
        // Không có caret ⇒ không chờ.
        r = TelexInputController.awaitClientCatchUp(
            expected: 5, budgetNs: 100, readCaret: { nil }, settle: { XCTFail("no settle") }, now: now)
        XCTAssertTrue(r.caughtUp); XCTAssertEqual(r.polls, 1)
        // Hết ngân sách khi vẫn tụt ⇒ false.
        clock = 0
        r = TelexInputController.awaitClientCatchUp(
            expected: 5, budgetNs: 10, readCaret: { 2 }, settle: { clock += 3 }, now: now)
        XCTAssertFalse(r.caughtUp); XCTAssertEqual(r.caret, 2)
        // requireStable: đã ≥ expected nhưng còn đang chạy (6 → 8) ⇒ chờ tới khi đứng yên.
        clock = 0
        carets = [6, 8, 8]
        r = TelexInputController.awaitClientCatchUp(
            expected: 5, budgetNs: 100, requireStable: true,
            readCaret: { carets.removeFirst() }, settle: { clock += 1 }, now: now)
        XCTAssertTrue(r.caughtUp); XCTAssertEqual(r.caret, 8); XCTAssertEqual(r.polls, 3)
    }

    func testCatchUpGateOnlyForAsyncAppsAndBreaksAfterStrikes() {
        XCTAssertTrue(TelexInputController.shouldAwaitCatchUp(bundleID: whatsApp, consecutiveTimeouts: 0))
        XCTAssertFalse(TelexInputController.shouldAwaitCatchUp(
            bundleID: whatsApp, consecutiveTimeouts: TelexInputController.catchUpMaxTimeouts))
        XCTAssertFalse(TelexInputController.shouldAwaitCatchUp(bundleID: "com.apple.TextEdit", consecutiveTimeouts: 0))
        XCTAssertFalse(TelexInputController.shouldAwaitCatchUp(bundleID: nil, consecutiveTimeouts: 0))
        XCTAssertTrue(TelexInputController.insertsAtCaret(bundleID: whatsApp))
        XCTAssertFalse(TelexInputController.insertsAtCaret(bundleID: "com.apple.TextEdit"))
    }
}
