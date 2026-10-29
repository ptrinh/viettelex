import XCTest
import UIKit

/// Regression (tester 29/10/2026, Zalo iOS 26/27, VietTelex 1.2.23/1.2.24): đổi từ bàn phím Apple
/// sang VietTelex, thanh nhập của Zalo nằm sau thanh gợi ý — Zalo đặt thanh nhập theo chiều cao
/// ĐẦU TIÊN bàn phím xin và bỏ qua lần đổi sau. Quy tắc: chiều cao xin lúc viewWillAppear (trước
/// lượt layout đầu, host đo ở đây) PHẢI bằng chiều cao ổn định sau layout / didAppear / việc hoãn.
///
/// Gốc lỗi: chiều cao tính theo bề ngang view, mà lúc viewWillAppear KeyboardView chưa layout
/// (bounds 0) ⇒ đoán "iPhone dọc thường" (bước 54) — máy lớn ≥ 420pt (Air / Plus / Pro Max, bước
/// 56, đệm đáy 7) xin THẤP hơn ~19–21pt rồi mới tăng ở lượt layout. Máy nút Home (SE): globe chỉ
/// biết ở didAppear ⇒ tăng 8pt sau khi đã hiện.
final class FirstLayoutHeightTests: XCTestCase {
    private let suite = "vt-first-layout-height-tests"

    // MARK: Hàm thuần

    func testLayoutWidthUsesHintOnlyBeforeLayout() {
        XCTAssertEqual(KeyLayout.layoutWidth(bounds: 0, hint: 440), 440)
        XCTAssertEqual(KeyLayout.layoutWidth(bounds: 402, hint: 440), 402, "đã layout: bề ngang thật thắng")
        XCTAssertEqual(KeyLayout.layoutWidth(bounds: 0, hint: nil), 0)
    }

    func testHomeButtonFromScreen() {
        XCTAssertTrue(KeyLayout.phoneHasHomeButton(screen: CGSize(width: 375, height: 667)))    // SE 2/3
        XCTAssertTrue(KeyLayout.phoneHasHomeButton(screen: CGSize(width: 736, height: 414)))    // 8 Plus ngang
        XCTAssertFalse(KeyLayout.phoneHasHomeButton(screen: CGSize(width: 375, height: 812)))   // mini
        XCTAssertFalse(KeyLayout.phoneHasHomeButton(screen: CGSize(width: 440, height: 956)))   // Pro Max
        XCTAssertFalse(KeyLayout.phoneHasHomeButton(screen: .zero))
    }

    /// Bề ngang 0 (chưa layout, KHÔNG hint — hành vi cũ) cho chiều cao khác máy lớn: lý do phải có hint.
    func testZeroWidthGuessDiffersOnLargePhones() {
        func h(_ width: CGFloat) -> CGFloat {
            let spec = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: width,
                                           base: KeyGeometry.phonePortraitBase, adjust: 0)
            return KeyLayout.requestedHeight(spec: spec, numberRow: true, numberRowFullHeight: false,
                                             strip: 29, headroom: KeyLayout.balloonHeadroom)
        }
        XCTAssertEqual(h(0), h(402), "máy thường: đoán 0 trùng")
        XCTAssertNotEqual(h(0), h(440), "máy lớn: đoán 0 thấp hơn ⇒ host thấy 2 chiều cao")
    }

    /// Chiều cao xin với bề ngang ĐOÁN (hint, bounds 0) = với bề ngang thật — mọi cỡ iPhone dọc,
    /// hàng số bật/tắt, thanh gợi ý bật/tắt.
    func testRequestedHeightFromHintMatchesRealWidth() {
        for (w, home) in [(375, true), (390, false), (402, false), (420, false), (430, false), (440, false)] as [(CGFloat, Bool)] {
            for numberRow in [false, true] {
                for strip in [false, true] {
                    func h(_ width: CGFloat) -> CGFloat {
                        let spec = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: width,
                                                       base: KeyGeometry.phonePortraitBase, adjust: 0, homeButton: home)
                        let open = KeyGeometry.StockSize.openStrip(width: width, landscape: false, homeButton: home)!
                        return KeyLayout.requestedHeight(spec: spec, numberRow: numberRow, numberRowFullHeight: false,
                                                         strip: KeyLayout.stripHeight(reserved: strip, open: open),
                                                         headroom: KeyLayout.balloonHeadroom)
                    }
                    XCTAssertEqual(h(KeyLayout.layoutWidth(bounds: 0, hint: w)), h(w),
                                   "w=\(w) numberRow=\(numberRow) strip=\(strip)")
                }
            }
        }
    }

    // MARK: View: chiều cao trước lượt layout đầu = sau layout

    @MainActor func testViewHeightBeforeFirstLayoutEqualsSteady() {
        let saved = UserDefaultsProvider.shared
        defer {
            UserDefaultsProvider.shared = saved
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        for w: CGFloat in [390, 402, 430, 440] {
            for numberRow in [false, true] {
                for suggestions in [false, true] {
                    UserDefaultsProvider.shared = defaults(numberRow: numberRow, suggestions: suggestions)
                    let kb = KeyboardView(needsGlobe: false, inputController: nil, deferInitialBuild: true) { _ in }
                    kb.layoutHint = KeyboardView.LayoutHint(width: w, screen: CGSize(width: w, height: 932))
                    kb.debugScreenSize = CGSize(width: w, height: 932)
                    kb.debugSetSafeBottom(0)
                    kb.beginBatch()
                    kb.applyAppearance(.default, style: .light)
                    kb.configureInputKind(.normal)
                    kb.setSuggestionsEnabled(suggestions, reserveStrip: suggestions)
                    kb.endBatch()
                    let first = kb.debugRequestedHeight   // host đo ở đây (chưa layout, bounds 0)
                    let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 600))
                    host.addSubview(kb)
                    kb.frame = CGRect(x: 0, y: 600 - first, width: w, height: first)
                    kb.layoutIfNeeded()
                    kb.frame.size.height = kb.debugRequestedHeight
                    kb.setNeedsLayout(); kb.layoutIfNeeded()
                    XCTAssertEqual(first, kb.debugRequestedHeight,
                                   "w=\(w) numberRow=\(numberRow) suggestions=\(suggestions)")
                    kb.tearDown()
                }
            }
        }
    }

    // MARK: Controller thật: willAppear → layout → didAppear → việc hoãn

    /// Host giả không tự chuyển callback hiện/ẩn (như KeyboardStartupTests.Rig).
    final class Host: UIViewController {
        override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
    }

    @MainActor private func appear(width: CGFloat, numberRow: Bool, suggestions: Bool, buddy: Bool)
        -> (willAppear: CGFloat, layout: CGFloat, didAppear: CGFloat, settled: CGFloat) {
        let screenH: CGFloat = width >= 420 ? 956 : 874
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: screenH))
        let host = Host()
        win.rootViewController = host
        win.isHidden = false
        host.view.layoutIfNeeded()
        let vc = KeyboardViewController()
        vc.debugProxy = KeyboardBenchTests.BenchProxy()
        vc.debugFullAccess = false
        vc.loadViewIfNeeded()
        host.addChild(vc)
        vc.view.frame = CGRect(x: 0, y: screenH - 300, width: width, height: 300)
        host.view.addSubview(vc.view)
        vc.didMove(toParent: host)
        vc.debugKeyboard.debugScreenSize = CGSize(width: width, height: screenH)
        // Window giả có vạch home (safe area 34) mà view bàn phím thật thì không (KeyLayout.keyboardSafeBottom).
        vc.debugKeyboard.debugSetSafeBottom(0)
        vc.beginAppearanceTransition(true, animated: true)
        let will = vc.debugKeyboard.debugRequestedHeight
        // Host cấp đúng mức xin ĐẦU (như Zalo) rồi layout.
        vc.view.frame = CGRect(x: 0, y: screenH - will, width: width, height: will)
        vc.view.layoutIfNeeded()
        let layout = vc.debugKeyboard.debugRequestedHeight
        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        vc.endAppearanceTransition()
        let did = vc.debugKeyboard.debugRequestedHeight
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))   // PostFrameWork, HostFill recheck…
        vc.view.layoutIfNeeded()
        let settled = vc.debugKeyboard.debugRequestedHeight
        vc.beginAppearanceTransition(false, animated: false)
        vc.endAppearanceTransition()
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        win.isHidden = true
        return (will, layout, did, settled)
    }

    @MainActor func testControllerFirstHeightIsFinalHeight() {
        let saved = UserDefaultsProvider.shared
        let savedPaywall = PlusGate.paywallEnabled
        defer {
            UserDefaultsProvider.shared = saved
            PlusGate.paywallEnabled = savedPaywall
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        for w: CGFloat in [402, 440] {
            for (numberRow, suggestions, buddy) in [(true, true, false), (true, true, true), (false, true, false),
                                                    (true, false, false)] {
                UserDefaultsProvider.shared = defaults(numberRow: numberRow, suggestions: suggestions, buddy: buddy)
                let r = appear(width: w, numberRow: numberRow, suggestions: suggestions, buddy: buddy)
                let tag = "w=\(w) numberRow=\(numberRow) suggestions=\(suggestions) buddy=\(buddy)"
                XCTAssertEqual(r.willAppear, r.layout, "willAppear → layout: \(tag)")
                XCTAssertEqual(r.willAppear, r.didAppear, "willAppear → didAppear: \(tag)")
                XCTAssertEqual(r.willAppear, r.settled, "willAppear → sau việc hoãn: \(tag)")
            }
        }
    }

    @MainActor private func defaults(numberRow: Bool, suggestions: Bool, buddy: Bool = false) -> UserDefaults {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(numberRow, forKey: KeyboardView.numberRowKey)
        d.set(suggestions, forKey: "showSuggestions")
        if buddy {
            PlusGate.paywallEnabled = false
            d.set(BuddyCharacter.cat.rawValue, forKey: BuddyCharacter.key)
        }
        return d
    }
}
