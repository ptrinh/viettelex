import XCTest
@testable import VietTelex

// Issue #141 (macOS 27.2, 1.8.32): M365 Copilot side panel in Excel/Word/PowerPoint.
// The panel is a web view inside the SAME bundle id, so Excel's per-app emptyReset
// (U+202F + ⌫ + retype, meant for the cell grid / formula bar) ran inside a web
// editor that reverts the synthetic edits — "Gox tieengs Vieetj trong Exxcel
// Copilot" → "Go tieng Viet trong E cel Copilot". Fix: a focused field under an
// AXWebArea in an Office host skips the tap and composes marked via IMKit; the
// grid/body keeps its rule.
final class OfficeWebPanelTests: XCTestCase {

    private typealias W = AppState.TapWants
    private typealias R = AppState.TapRouting

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        FocusedFieldDetector.invalidate()
        super.tearDown()
    }

    // MARK: pure decision

    func testOfficeHostsInWebAreaAreWebPanels() {
        for id in ["com.microsoft.Excel", "com.microsoft.Word", "com.microsoft.Powerpoint"] {
            XCTAssertTrue(AppState.officeWebPanel(id, manualPin: nil, inWebArea: { true }), id)
            XCTAssertFalse(AppState.officeWebPanel(id, manualPin: nil, inWebArea: { false }),
                           "\(id): lưới/thân văn bản giữ rule cũ")
        }
    }

    func testOutlookAndBrowsersAreNotOfficeWebPanels() {
        // Outlook compose IS a web view and in-place is field-verified there — it must
        // not be dragged to marked. Browsers have their own per-field policy.
        for id in ["com.microsoft.Outlook", "com.google.Chrome", "com.apple.Safari",
                   "com.microsoft.edgemac"] {
            XCTAssertFalse(AppState.officeWebPanel(id, manualPin: nil, inWebArea: { true }), id)
        }
        XCTAssertFalse(AppState.officeWebPanel(nil, manualPin: nil, inWebArea: { true }))
    }

    func testManualPinWins() {
        XCTAssertFalse(AppState.officeWebPanel("com.microsoft.Excel", manualPin: .tap,
                                               inWebArea: { true }))
        XCTAssertFalse(AppState.officeWebPanel("com.microsoft.Word", manualPin: .inPlace,
                                               inWebArea: { true }))
    }

    func testDetectorIsNotReadForOtherApps() {
        // Laziness: a key in any non-Office app must never pay for the AX verdict.
        var reads = 0
        _ = AppState.officeWebPanel("com.apple.Terminal", manualPin: nil,
                                    inWebArea: { reads += 1; return true })
        _ = AppState.officeWebPanel("com.microsoft.Excel", manualPin: .emptyReset,
                                    inWebArea: { reads += 1; return true })
        XCTAssertEqual(reads, 0)
    }

    // MARK: gate

    func testExcelGridKeepsEmptyResetButWebPanelSkipsTap() {
        let excel = W(tap: false, sel: .no, empty: true)
        let grid = AppState.gateRouting(excel, trusted: { true }, wantsSelection: { false },
                                        wantsMarkedField: { false },
                                        officeWebPanel: { false })
        XCTAssertEqual(grid, R(tap: false, selection: false, emptyReset: true))
        let panel = AppState.gateRouting(excel, trusted: { true }, wantsSelection: { false },
                                         wantsMarkedField: { false },
                                         officeWebPanel: { true })
        XCTAssertEqual(panel, R(), "Copilot panel: không ⌫+U+202F+gõ-lại tổng hợp")
        XCTAssertFalse(panel.tapDefer, "IMKit phải compose")
    }

    func testInPlaceAppNeverReadsTheDetectorOnTheTapSide() {
        // Word/PowerPoint want nothing from the tap: the gate returns before the
        // office closure (the IMKit side decides marked instead).
        var reads = 0
        let r = AppState.gateRouting(W(), trusted: { true }, wantsSelection: { false },
                                     wantsMarkedField: { false },
                                     officeWebPanel: { reads += 1; return true })
        XCTAssertEqual(r, R())
        XCTAssertEqual(reads, 0)
    }

    // MARK: end to end (real AppState + detector cache)

    func testEndToEndExcelCopilotPanel() {
        Accessibility.testTrustOverride = true
        FocusedFieldDetector._testSetWebArea(false)       // cell grid / formula bar
        let grid = AppState.shared.tapRouting("com.microsoft.Excel", front: "com.microsoft.Excel")
        XCTAssertTrue(grid.emptyReset, "lưới Excel vẫn đi U+202F dance")
        XCTAssertTrue(grid.tapDefer)

        FocusedFieldDetector._testSetWebArea(true)        // Copilot side panel
        let panel = AppState.shared.tapRouting("com.microsoft.Excel", front: "com.microsoft.Excel")
        XCTAssertFalse(panel.tapDefer, "panel Copilot phải về IMKit (log #141: tap-defer empty=true)")
        XCTAssertTrue(AppState.shared.isOfficeWebPanel("com.microsoft.Excel"))
        let c = TelexInputController()
        XCTAssertTrue(c._testUsesMarkedNow("com.microsoft.Excel"), "Copilot panel → marked")
    }

    func testEndToEndWordAndPowerPointPanelsAreMarkedBodiesStayInPlace() {
        Accessibility.testTrustOverride = true
        let c = TelexInputController()
        for id in ["com.microsoft.Word", "com.microsoft.Powerpoint"] {
            FocusedFieldDetector._testSetWebArea(false)
            XCTAssertFalse(c._testUsesMarkedNow(id), "\(id): thân văn bản giữ in-place")
            FocusedFieldDetector._testSetWebArea(true)
            XCTAssertTrue(c._testUsesMarkedNow(id), "\(id): panel Copilot → marked")
            XCTAssertFalse(AppState.shared.tapRouting(id).tapDefer, id)
        }
        FocusedFieldDetector._testSetWebArea(true)
        XCTAssertFalse(c._testUsesMarkedNow("com.microsoft.Outlook"),
                       "Outlook compose (WKWebView) giữ in-place")
    }

    // MARK: cache contract

    func testInvalidateResetsWebAreaToNative() {
        // After a focus change the safe default is "native field": one key on the
        // app's own rule is mild; forcing marked into Excel's grid draws its heavy
        // underline.
        FocusedFieldDetector._testSetWebArea(true)
        XCTAssertTrue(FocusedFieldDetector.inWebArea)
        FocusedFieldDetector.invalidate()
        XCTAssertFalse(FocusedFieldDetector.inWebArea)
    }
}
