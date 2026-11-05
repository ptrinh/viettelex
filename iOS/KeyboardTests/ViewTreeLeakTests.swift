import XCTest
import UIKit

/// Rò rỉ #1 RAM-AUDIT.md: iOS 26+ UIKit giữ `UIInputView` của controller mãi (vòng
/// `UIInputView` ⇄ `_UIInputViewContent` qua associated object — `leaks --traceTree`), nên nếu
/// không xé thì cả cây phím cũ (~1,8 MB) sống theo mỗi lần hiện. Sửa: viewDidDisappear xé cây
/// (KeyboardView.tearDown), viewWillAppear dựng lại nếu cùng controller hiện lại.
final class ViewTreeLeakTests: XCTestCase {

    static func spin(_ sec: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(sec)) }

    final class Weak {
        weak var vc: UIViewController?; weak var view: UIView?; weak var kb: UIView?
        weak var anyKey: UIView?; weak var rows: UIView?
    }

    static func firstButton(in v: UIView) -> UIView? {
        if v is KeyboardView.KeyButton { return v }
        for s in v.subviews { if let b = firstButton(in: s) { return b } }
        return nil
    }

    static func count(_ v: UIView) -> Int { 1 + v.subviews.reduce(0) { $0 + count($1) } }

    @MainActor static func hide(_ vc: UIViewController) {
        vc.beginAppearanceTransition(false, animated: false)
        vc.endAppearanceTransition()
    }

    @MainActor static func show(_ vc: UIViewController) {
        vc.beginAppearanceTransition(true, animated: false)
        vc.view.layoutIfNeeded()
        vc.endAppearanceTransition()
        vc.view.layoutIfNeeded()
    }

    @MainActor private func openClose(_ body: (KeyboardBenchTests.Rig) -> Void = { _ in }) -> Weak {
        let w = Weak()
        autoreleasepool {
            let r = KeyboardBenchTests.Rig()
            body(r)
            w.vc = r.vc; w.view = r.vc.view; w.kb = r.vc.debugKeyboard
            w.anyKey = Self.firstButton(in: r.vc.debugKeyboard)
            w.rows = w.anyKey?.superview?.superview
            r.close()
        }
        return w
    }

    /// iOS tạo controller mới mỗi lần hiện: cây phím lượt trước phải chết (UIKit được phép
    /// níu vỏ UIInputView — nhưng vỏ phải RỖNG).
    @MainActor func testOldTreeReleasedAcrossControllers() {
        var weaks: [Weak] = []
        for i in 0..<4 {
            weaks.append(openClose { r in
                // đi qua các plane nặng: emoji, số, mẫu câu
                switch i {
                case 1: r.vc.debugKeyboard.debugShowEmojiPlane(); r.vc.view.layoutIfNeeded()
                case 2: r.vc.debugKeyboard.debugCycleThroughNumbers()
                case 3: r.vc.debugKeyboard.debugCycleThroughTemplates()
                default: break
                }
            })
            Self.spin(0.05)
        }
        let keep = KeyboardBenchTests.Rig()   // một bàn phím mới đang hiện (như máy thật)
        Self.spin(0.2)
        for (i, w) in weaks.enumerated() {
            XCTAssertNil(w.kb, "KeyboardView lượt \(i) còn sống")
            XCTAssertNil(w.anyKey, "KeyButton lượt \(i) còn sống")
            XCTAssertNil(w.rows, "UIStackView hàng phím lượt \(i) còn sống")
            if let v = w.view { XCTAssertEqual(v.subviews.count, 0, "vỏ UIInputView lượt \(i) còn con") }
        }
        keep.close()
    }

    /// Cùng controller: hiện → ẩn → hiện. Ẩn ⇒ cây xé (không còn subview); hiện lại ⇒
    /// KeyboardView MỚI, đủ phím, gõ được; KeyboardView cũ chết.
    @MainActor func testSameControllerReshowRebuilds() {
        let r = autoreleasepool { KeyboardBenchTests.Rig() }
        weak var oldKB: KeyboardView?
        let installs0 = KeyboardViewController.debugKeyboardInstalls
        var nodesShown = 0
        // Mọi thứ chạm vào cây (subviews trả NSArray autorelease) nằm trong pool riêng, kẻo
        // pool của hàm test giữ KeyboardView cũ tới hết test.
        autoreleasepool {
        oldKB = r.vc.debugKeyboard
        nodesShown = Self.count(r.vc.view)
        Self.hide(r.vc)
        XCTAssertTrue(oldKB?.isTornDown == true)
        XCTAssertEqual(r.vc.view.subviews.count, 0, "ẩn: view gốc phải rỗng")
        XCTAssertEqual(oldKB?.subviews.count, 0)
        // Host vẫn có thể gọi textDidChange… lúc ẩn — không được crash trên view đã xé.
        r.vc.textWillChange(nil); r.vc.textDidChange(nil)
        r.vc.selectionWillChange(nil); r.vc.selectionDidChange(nil)
        Self.show(r.vc)
        }
        // Animation/asyncAfter đang bay (badge ngôn ngữ…) giữ tạm view cũ — chờ chúng xong.
        var waited = 0.0
        while oldKB != nil, waited < 3 { autoreleasepool { Self.spin(0.1) }; waited += 0.1 }
        print("LEAKT old KeyboardView freed after \(waited)s")
        XCTAssertNil(oldKB, "KeyboardView cũ (đã xé) phải được giải phóng khi thay")
        XCTAssertEqual(KeyboardViewController.debugKeyboardInstalls, installs0 + 1)
        XCTAssertFalse(r.vc.debugKeyboard.isTornDown)
        XCTAssertEqual(r.vc.view.subviews.count, 1)
        XCTAssertEqual(Double(Self.count(r.vc.view)), Double(nodesShown), accuracy: Double(nodesShown) / 10,
                       "cây dựng lại cỡ như lần đầu")
        XCTAssertNotNil(r.vc.debugKeyboard.debugLetterFrame("a"))
        XCTAssertEqual(r.vc.debugKeyboard.debugPlaneName, "letters")
        // gõ được sau khi dựng lại
        r.proxy.inserts = 0
        for (i, c) in "xin chaof ".enumerated() { _ = r.key(c, index: i + 1, drain: 0.005) }
        XCTAssertGreaterThan(r.proxy.inserts, 0, "phím sau khi dựng lại không chèn chữ")
        // Ẩn/hiện nhiều lần: KHÔNG dựng thừa khi chưa xé (viewWillAppear hai lần liền)
        let installs1 = KeyboardViewController.debugKeyboardInstalls
        Self.show(r.vc)
        XCTAssertEqual(KeyboardViewController.debugKeyboardInstalls, installs1)
        r.close()
    }

    /// Trạng thái phải qua được một lần ẩn/hiện cùng controller: plane lạ (emoji, mẫu câu,
    /// số) → về chữ như controller mới; panel clipboard đóng; một tay giữ; ngôn ngữ giữ.
    @MainActor func testReshowStateMatchesFreshController() {
        let r = KeyboardBenchTests.Rig()
        for enter in [{ r.vc.debugKeyboard.debugShowEmojiPlane() },
                      { r.vc.debugKeyboard.debugTapBurger() },
                      { r.vc.debugKeyboard.debugSetPlane(numbers: true) }] {
            enter()
            r.vc.view.layoutIfNeeded()
            XCTAssertNotEqual(r.vc.debugKeyboard.debugPlaneName, "letters")
            Self.hide(r.vc); Self.show(r.vc)
            XCTAssertEqual(r.vc.debugKeyboard.debugPlaneName, "letters")
            XCTAssertNotNil(r.vc.debugKeyboard.debugLetterFrame("q"))
        }
        // Một tay: bàn phím tự lưu → hiện lại vẫn một tay (cùng đường controller mới).
        let std = UserDefaults.standard
        let savedSide = std.string(forKey: OneHand.key), savedGroup = std.string(forKey: OneHand.seenGroupKey)
        defer { std.set(savedSide, forKey: OneHand.key); std.set(savedGroup, forKey: OneHand.seenGroupKey) }
        r.vc.debugKeyboard.onOneHandChange?(.right)
        r.vc.debugKeyboard.configureOneHand(.right)
        Self.hide(r.vc); Self.show(r.vc)
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertEqual(r.vc.debugKeyboard.oneHand, .right)
        }
        r.vc.debugKeyboard.onOneHandChange?(.off)
        r.vc.debugKeyboard.configureOneHand(.off)
        r.close()
    }

    /// Lõi RAM: 20 vòng hiện/ẩn cùng controller + 20 controller mới — heap không tăng đều.
    @MainActor func testHeapFlatAcrossShowHide() {
        let r = autoreleasepool { KeyboardBenchTests.Rig() }
        autoreleasepool { for _ in 0..<3 { Self.hide(r.vc); Self.show(r.vc) } }   // làm ấm (cache font, glyph)
        Self.spin(0.2)
        let h0 = RamBreakdownTests.heapBytes()
        var olds: [Weak] = []
        var hideMs: [Double] = [], showMs: [Double] = []
        for _ in 0..<20 {
            autoreleasepool {
                let w = Weak(); w.kb = r.vc.debugKeyboard; olds.append(w)
                let t0 = CACurrentMediaTime()
                Self.hide(r.vc)
                let t1 = CACurrentMediaTime()
                Self.show(r.vc)
                hideMs.append((t1 - t0) * 1000); showMs.append((CACurrentMediaTime() - t1) * 1000)
            }
        }
        Self.spin(0.2)
        let h1 = RamBreakdownTests.heapBytes()
        XCTAssertEqual(olds.filter { $0.kb != nil }.count, 0, "KeyboardView cũ còn sống sau ẩn/hiện")
        autoreleasepool { r.close() }
        // Độ trễ: hiện lại cùng controller (dựng KeyboardView mới) ≈ mở controller mới.
        var fresh: [Double] = []
        for _ in 0..<5 { autoreleasepool { let x = KeyboardBenchTests.Rig(); fresh.append(x.openMs); x.close() } }
        func med(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
        print(String(format: "LEAKT perf median: hide(teardown) %.2f ms, reshow same controller %.2f ms, open new controller %.2f ms",
                     med(hideMs), med(showMs), med(fresh)))
        XCTAssertLessThan(med(showMs), max(med(fresh) * 1.5, 30), "hiện lại chậm hơn hẳn mở mới")
        let perCycleKB = Double(h1 - h0) / 20 / 1024
        print(String(format: "LEAKT same-controller heap/cycle %.1f KB", perCycleKB))
        XCTAssertLessThan(perCycleKB, 30, "mỗi vòng ẩn/hiện giữ lại \(perCycleKB) KB")
    }
}
