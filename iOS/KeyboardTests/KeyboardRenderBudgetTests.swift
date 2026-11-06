import XCTest
import UIKit

/// NGÂN SÁCH RENDER của bàn phím — chặn hồi quy "bàn phím hiện / gõ chậm hơn" bằng ĐẾM việc
/// (không đo giờ ⇒ không flaky khi máy bận). Cách đọc + cách nâng ngân sách có chủ đích:
/// iOS/docs/KEYBOARD-STARTUP.md mục "Ngân sách render".
///
/// Đếm (controller thật, cùng thứ tự callback như iOS — KeyboardStartupTests.Rig):
///  • lúc mở tới khung đầu: số view / layer trong cây, lượt layoutSubviews của KeyboardView và
///    của mọi phím, số lần dựng plane; dữ liệu nặng (model cá nhân, gợi ý, template vuốt, engine
///    âm) CHƯA được xin trước khung đầu;
///  • chuỗi kích thước host gửi khi hiện (0×0 → cả màn hình → 452 → 268 → chiều cao xin): không
///    dựng lại phím, lượt layout có trần;
///  • mỗi lần gõ phím: không tạo view / layer mới, lượt layout có trần;
///  • đổi mặt phím 123 ⇄ ABC;
///  • không layer nào gây offscreen pass (bóng thiếu shadowPath, mask, rasterize, bo góc +
///    cắt mép có sublayer, blur).
///
/// Ngân sách = số đo lúc đặt + một khoảng nhỏ. Vượt ⇒ thay đổi vừa làm thêm việc vào đường hiện /
/// gõ: tối ưu lại, HOẶC (nếu việc thêm là cố ý và đáng) nâng con số trong `Budget` kèm lý do
/// trong commit message.
@MainActor
final class KeyboardRenderBudgetTests: XCTestCase {

    /// Trần đã duyệt. Đo 07/11/2026 (simulator iPhone 17, iOS 27, 414×896 trong rig).
    enum Budget {
        // Mở bàn phím (mặc định) tới khung đầu. Đo: 112 view, 112 layer, 1 / 41 lượt layout.
        static let openViews = 116
        static let openLayers = 116
        static let openKeyboardLayouts = 1
        static let openKeyLayouts = 44
        // Mở với theme + nhân vật + âm + vuốt + hàng số (rich). Đo: 125 view, 127 layer.
        static let openRichViews = 129
        static let openRichLayers = 131
        // Chuỗi kích thước host (0 → 896 → 452 → 268 → chiều cao xin). Đo: 5 / 174
        // (trước 07/11/2026: 5 / 195 — phím chỉ dời chỗ cũng bị layout lại).
        static let sizeSequenceKeyboardLayouts = 6
        static let sizeSequenceKeyLayouts = 180
        // Một phím chữ giữa từ (không đổi shift): tới commit / sau khi thanh gợi ý cập nhật. Đo: 0 / 0 / 0
        // (trước 07/11/2026: KeyboardView layout lại MỖI phím vì ô phóng to đổi cỡ trong nó).
        static let keypressKeyboardLayouts = 0
        static let keypressKeyLayouts = 0
        static let keypressSettledKeyLayouts = 0
        // Đổi mặt phím ABC → 123 → ABC (lần hai: từ cache). Đo: 0.
        static let planeSwitchKeyLayouts = 0
        // Layer gây offscreen pass trên bàn phím đang hiện. Đo: 0 (mặc định + theme, kèm ô phóng to).
        static let offscreenLayers = 0
    }

    private static let howToUpdate = "— vượt ngân sách render. Tối ưu lại, hoặc nếu cố ý: sửa KeyboardRenderBudgetTests.Budget + ghi lý do trong commit (iOS/docs/KEYBOARD-STARTUP.md)."

    private let suite = "vt-render-budget-tests"

    private func useDefaults(rich: Bool) -> () -> Void {
        let saved = UserDefaultsProvider.shared
        let savedPaywall = PlusGate.paywallEnabled
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        if rich {
            PlusGate.paywallEnabled = false
            d.set("peach", forKey: "keyboardTheme")
            d.set(BuddyCharacter.cat.rawValue, forKey: BuddyCharacter.key)
            d.set(true, forKey: "keySound")
            d.set("piano", forKey: "keySoundStyle")
            d.set(true, forKey: "hapticFeedback")
            d.set(true, forKey: "swipeTyping")
            d.set(true, forKey: "numberRow")
            d.set("heart", forKey: KeyEffect.key)
        }
        UserDefaultsProvider.shared = d
        return { [suite] in
            UserDefaultsProvider.shared = saved
            PlusGate.paywallEnabled = savedPaywall
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    private static func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date(timeIntervalSinceNow: s)) }

    private static func resetCounters() {
        KeyboardView.perfLayoutPasses = 0
        KeyboardView.perfKeyLayoutPasses = 0
        KeyboardView.perfFullBuilds = 0
        KeyboardView.perfCacheSwaps = 0
    }

    // MARK: đo cây view / layer

    struct Tree { var views = 0; var layers = 0 }
    static func tree(_ v: UIView) -> Tree {
        var t = Tree()
        func walkV(_ v: UIView) { t.views += 1; v.subviews.forEach(walkV) }
        func walkL(_ l: CALayer) {
            // _UILabelContentLayer: UIKit tự tạo (một cái / nhãn) khi chữ của nhãn đổi — không phải việc của mình.
            if !NSStringFromClass(type(of: l)).hasPrefix("_UILabelContentLayer") { t.layers += 1 }
            l.sublayers?.forEach(walkL)
        }
        walkV(v); walkL(v.layer)
        return t
    }

    /// Layer (đang hiện) khiến Core Animation phải vẽ offscreen.
    static func offscreenHazards(_ root: UIView) -> [String] {
        var out: [String] = []
        func walk(_ l: CALayer, _ path: String) {
            guard !l.isHidden, l.opacity > 0 else { return }
            let name = l.delegate.map { String(describing: type(of: $0)) } ?? String(describing: type(of: l))
            let here = path + "/" + name
            if l.shadowOpacity > 0, l.shadowPath == nil { out.append("\(here): bóng không shadowPath") }
            if l.mask != nil { out.append("\(here): mask") }
            if l.shouldRasterize { out.append("\(here): shouldRasterize") }
            if l.masksToBounds, l.cornerRadius > 0, !(l.sublayers ?? []).isEmpty {
                out.append("\(here): bo góc + masksToBounds có sublayer")
            }
            if l.delegate is UIVisualEffectView { out.append("\(here): blur") }
            l.sublayers?.forEach { walk($0, here) }
        }
        walk(root.layer, "")
        return out
    }

    private func line(_ s: String) {
        print("BUDGET " + s)
        XCTContext.runActivity(named: "BUDGET " + s) { _ in }
    }

    // MARK: mở tới khung đầu

    func testOpenToFirstFrameBudget() {
        let restore = useDefaults(rich: false)
        defer { restore() }
        // Lần mở làm nóng (cache cấp process: phông, ảnh, nhãn…) rồi đo lần mở thường gặp.
        KeyboardStartupTests.Rig(fullAccess: false).close()
        Self.spin(0.1)
        Self.resetCounters()
        let r = KeyboardStartupTests.Rig(fullAccess: false, appear: false)
        defer { r.close() }
        let t = Self.tree(r.vc.view)
        let kv = KeyboardView.perfLayoutPasses, keys = KeyboardView.perfKeyLayoutPasses
        line("open views=\(t.views) layers=\(t.layers) kbLayouts=\(kv) keyLayouts=\(keys) builds=\(KeyboardView.perfFullBuilds)")
        XCTAssertEqual(KeyboardView.perfFullBuilds, 1, "dựng phím đúng MỘT lần")
        XCTAssertLessThanOrEqual(t.views, Budget.openViews, "số view lúc mở " + Self.howToUpdate)
        XCTAssertLessThanOrEqual(t.layers, Budget.openLayers, "số layer lúc mở " + Self.howToUpdate)
        XCTAssertLessThanOrEqual(kv, Budget.openKeyboardLayouts, "layoutSubviews KeyboardView lúc mở " + Self.howToUpdate)
        XCTAssertLessThanOrEqual(keys, Budget.openKeyLayouts, "layoutSubviews các phím lúc mở " + Self.howToUpdate)
        // Không có gì nặng trước khung đầu.
        XCTAssertTrue(r.vc.debugPostFramePending, "việc phụ hoãn tới sau khung đầu")
        XCTAssertTrue(r.vc.warmupsDeferred)
        XCTAssertEqual(r.vc.debugSuggestionPasses, 0, "thanh gợi ý chưa tính trước khung đầu")
        XCTAssertFalse(r.vc.debugLangModelLoaded, "model cá nhân chưa nạp trước khung đầu")
    }

    /// Cấu hình nặng: theme + nhân vật + âm phím + gõ vuốt — engine âm, template vuốt chỉ được xin
    /// SAU khung đầu; gõ ngay trước đó vẫn đúng chữ.
    func testOpenRichDefersWarmupsUntilAfterFirstFrame() throws {
        let restore = useDefaults(rich: true)
        defer { restore() }
        KeyboardStartupTests.Rig(fullAccess: true).close()
        Self.spin(0.1)
        KeySound.shared.shutdown(); KeySound.shared.debugDrain()
        Self.resetCounters()
        let r = KeyboardStartupTests.Rig(fullAccess: true, appear: false)
        defer { r.close(); KeySound.shared.shutdown(); KeySound.shared.debugDrain() }
        let t = Self.tree(r.vc.view)
        line("openRich views=\(t.views) layers=\(t.layers) kbLayouts=\(KeyboardView.perfLayoutPasses) keyLayouts=\(KeyboardView.perfKeyLayoutPasses)")
        XCTAssertEqual(KeyboardView.perfFullBuilds, 1, "dựng phím đúng MỘT lần")
        XCTAssertLessThanOrEqual(t.views, Budget.openRichViews, "số view lúc mở (rich) " + Self.howToUpdate)
        XCTAssertLessThanOrEqual(t.layers, Budget.openRichLayers, "số layer lúc mở (rich) " + Self.howToUpdate)
        KeySound.shared.debugDrain()
        XCTAssertFalse(KeySound.shared.debugWanted, "engine âm chưa xin dựng trước khung đầu")
        XCTAssertFalse(r.vc.debugSwipeLayoutPushed, "template vuốt chưa dựng trước khung đầu")
        XCTAssertFalse(r.vc.debugLangModelLoaded)

        // Gõ NGAY (trước khi warm-up chạy): chữ đúng.
        let kb = r.vc.debugKeyboard
        for c in "vieejt" {
            let f = try XCTUnwrap(kb.debugLetterFrame(String(c)))
            kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime())
        }
        XCTAssertEqual(r.proxy.text, "Việt", "phím đầu không mất / không sai khi warm-up chưa chạy")

        Self.spin(0.2)   // commit khung đầu ⇒ PostFrameWork chạy warm-up
        KeySound.shared.debugDrain()
        XCTAssertFalse(r.vc.warmupsDeferred)
        XCTAssertTrue(KeySound.shared.debugWanted, "sau khung đầu: engine âm được dựng")
        XCTAssertTrue(r.vc.debugSwipeLayoutPushed, "sau khung đầu: layout vuốt đã gửi decoder")
    }

    // MARK: chuỗi kích thước host

    /// iOS đổi khung view bàn phím nhiều lần khi hiện (0×0 → cả màn hình → 452 → 268 —
    /// Apple Forums 813579). Mỗi lần chỉ được xếp lại khung, không dựng lại phím.
    func testHostSizeSequenceBudget() {
        let restore = useDefaults(rich: false)
        defer { restore() }
        let r = KeyboardStartupTests.Rig(fullAccess: false)
        defer { r.close() }
        Self.spin(0.1)
        let final = r.vc.view.frame
        let before = Self.tree(r.vc.view)
        Self.resetCounters()
        for h: CGFloat in [0, 896, 452, 268, final.height] {
            r.vc.view.frame = CGRect(x: 0, y: 896 - h, width: 414, height: h)
            r.vc.view.layoutIfNeeded()
            CATransaction.flush()
        }
        let after = Self.tree(r.vc.view)
        let kv = KeyboardView.perfLayoutPasses, keys = KeyboardView.perfKeyLayoutPasses
        line("sizeSequence kbLayouts=\(kv) keyLayouts=\(keys) builds=\(KeyboardView.perfFullBuilds) views \(before.views)→\(after.views)")
        XCTAssertEqual(KeyboardView.perfFullBuilds, 0, "đổi chiều cao không dựng lại phím")
        XCTAssertEqual(after.views, before.views, "đổi chiều cao không tạo view")
        XCTAssertLessThanOrEqual(kv, Budget.sizeSequenceKeyboardLayouts, "layoutSubviews KeyboardView qua chuỗi kích thước " + Self.howToUpdate)
        XCTAssertLessThanOrEqual(keys, Budget.sizeSequenceKeyLayouts, "layoutSubviews các phím qua chuỗi kích thước " + Self.howToUpdate)
    }

    // MARK: mỗi phím

    func testKeypressBudget() throws {
        let restore = useDefaults(rich: false)
        defer { restore() }
        let r = KeyboardStartupTests.Rig(fullAccess: false)
        defer { r.close() }
        Self.spin(0.2)
        let kb = r.vc.debugKeyboard
        func tap(_ c: Character) throws {
            let f = try XCTUnwrap(kb.debugLetterFrame(String(c)))
            kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime())
        }
        // Hai phím đầu: shift đầu câu tắt, balloon tạo lười — không tính.
        try tap("v"); try tap("i")
        CATransaction.flush(); Self.spin(0.2)

        let before = Self.tree(r.vc.view)
        Self.resetCounters()
        // Ai làm KeyboardView cần layout lại (để chẩn đoán khi test đỏ): call stack mỗi lần.
        KeyboardView.debugNeedsLayoutLog = []
        defer { KeyboardView.debugNeedsLayoutLog = nil }
        try tap("e")
        let invalidations = KeyboardView.debugNeedsLayoutLog ?? []
        CATransaction.flush()
        let kv = KeyboardView.perfLayoutPasses, keys = KeyboardView.perfKeyLayoutPasses
        Self.spin(0.2)   // thanh gợi ý (hoãn 30 ms) cập nhật
        CATransaction.flush()
        let settledKeys = KeyboardView.perfKeyLayoutPasses
        let after = Self.tree(r.vc.view)
        line("keypress kbLayouts=\(kv) keyLayouts=\(keys) settledKeyLayouts=\(settledKeys) kbLayoutsSettled=\(KeyboardView.perfLayoutPasses) views \(before.views)→\(after.views) layers \(before.layers)→\(after.layers)")
        XCTAssertEqual(r.proxy.text, "Vie")
        XCTAssertEqual(KeyboardView.perfFullBuilds, 0, "gõ phím không dựng lại plane")
        XCTAssertLessThanOrEqual(after.views, before.views, "gõ phím không tạo view mới " + Self.howToUpdate)
        XCTAssertLessThanOrEqual(after.layers, before.layers, "gõ phím không tạo layer mới " + Self.howToUpdate)
        XCTAssertLessThanOrEqual(kv, Budget.keypressKeyboardLayouts, "layoutSubviews KeyboardView mỗi phím " + Self.howToUpdate
                                 + "\nNguồn setNeedsLayout:\n" + invalidations.joined(separator: "\n----\n"))
        XCTAssertLessThanOrEqual(keys, Budget.keypressKeyLayouts, "layoutSubviews phím mỗi lần gõ " + Self.howToUpdate)
        XCTAssertLessThanOrEqual(settledKeys, Budget.keypressSettledKeyLayouts, "layoutSubviews phím mỗi lần gõ (gồm thanh gợi ý) " + Self.howToUpdate)
    }

    // MARK: đổi mặt phím

    func testPlaneSwitchBudget() {
        let restore = useDefaults(rich: false)
        defer { restore() }
        let r = KeyboardStartupTests.Rig(fullAccess: false)
        defer { r.close() }
        Self.spin(0.1)
        let kb = r.vc.debugKeyboard
        // Lượt đầu dựng plane số (lười) — lượt hai phải lấy từ cache.
        XCTAssertTrue(kb.debugTapPlaneKey()); r.vc.view.layoutIfNeeded()
        XCTAssertTrue(kb.debugTapPlaneKey()); r.vc.view.layoutIfNeeded()
        CATransaction.flush()
        let before = Self.tree(r.vc.view)
        Self.resetCounters()
        XCTAssertTrue(kb.debugTapPlaneKey()); r.vc.view.layoutIfNeeded(); CATransaction.flush()
        XCTAssertTrue(kb.debugTapPlaneKey()); r.vc.view.layoutIfNeeded(); CATransaction.flush()
        let after = Self.tree(r.vc.view)
        let keys = KeyboardView.perfKeyLayoutPasses
        line("planeSwitch builds=\(KeyboardView.perfFullBuilds) swaps=\(KeyboardView.perfCacheSwaps) kbLayouts=\(KeyboardView.perfLayoutPasses) keyLayouts=\(keys) views \(before.views)→\(after.views)")
        XCTAssertEqual(KeyboardView.perfFullBuilds, 0, "123 ⇄ ABC lần hai: tráo từ cache, không dựng")
        XCTAssertEqual(after.views, before.views)
        XCTAssertLessThanOrEqual(keys, Budget.planeSwitchKeyLayouts, "layoutSubviews phím khi đổi mặt phím " + Self.howToUpdate)
    }

    // MARK: offscreen pass

    func testNoOffscreenRenderingLayers() {
        for rich in [false, true] {
            let restore = useDefaults(rich: rich)
            let r = KeyboardStartupTests.Rig(fullAccess: rich)
            Self.spin(0.1)
            let kb = r.vc.debugKeyboard
            // Balloon (xem trước phím) cũng phải rẻ.
            if let f = kb.debugLetterFrame("g") {
                kb.debugShowBalloon(over: kb.hitTest(CGPoint(x: f.midX, y: f.midY), with: nil) ?? kb, text: "g")
            }
            let hazards = Self.offscreenHazards(r.vc.view)
            line("offscreen rich=\(rich) count=\(hazards.count) \(hazards.joined(separator: "; "))")
            XCTAssertLessThanOrEqual(hazards.count, Budget.offscreenLayers,
                                     "layer vẽ offscreen (rich=\(rich)): \(hazards) " + Self.howToUpdate)
            r.close()
            restore()
        }
    }

    // MARK: đo giờ (phụ — bộ CHẬM, VT_SLOW_TESTS=1)

    /// Thời gian (đồng hồ + CPU) mở bàn phím tới khung đầu rồi đóng, và đổi mặt phím. Số giờ dao
    /// động theo tải máy ⇒ chỉ chạy trong bộ chậm (scheme VietTelexKeyboardSlowTests) với trần RỘNG
    /// (~3× số đo); kết quả measure{} xem trong báo cáo test để so giữa các bản.
    static let timingCeilingOpenMs = 60.0       // trung vị mở ấm (đo 07/11/2026 Debug simulator: ~15–20 ms)
    static let timingCeilingPlaneMs = 15.0      // trung vị 123 ⇄ ABC từ cache (đo: ~1–3 ms)

    func testTimingOpenToFirstFrame() throws {
        try SlowTests.require()
        let restore = useDefaults(rich: false)
        defer { restore() }
        KeyboardStartupTests.Rig(fullAccess: false).close()   // làm nóng
        var samples: [Double] = []
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(limitingToCurrentThread: true)]) {
            let t0 = CACurrentMediaTime()
            let r = KeyboardStartupTests.Rig(fullAccess: false, appear: false)
            samples.append((CACurrentMediaTime() - t0) * 1000)
            r.close()
        }
        samples.sort()
        let median = samples[samples.count / 2]
        line(String(format: "timing open median=%.1fms samples=%@", median, samples.map { String(format: "%.1f", $0) }.joined(separator: ",")))
        XCTAssertLessThan(median, Self.timingCeilingOpenMs, "mở bàn phím (ấm) chậm hẳn " + Self.howToUpdate)
    }

    func testTimingPlaneSwitch() throws {
        try SlowTests.require()
        let restore = useDefaults(rich: false)
        defer { restore() }
        let r = KeyboardStartupTests.Rig(fullAccess: false)
        defer { r.close() }
        let kb = r.vc.debugKeyboard
        kb.debugTapPlaneKey(); kb.debugTapPlaneKey(); r.vc.view.layoutIfNeeded()   // plane số vào cache
        var samples: [Double] = []
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(limitingToCurrentThread: true)]) {
            let t0 = CACurrentMediaTime()
            kb.debugTapPlaneKey(); r.vc.view.layoutIfNeeded(); CATransaction.flush()
            kb.debugTapPlaneKey(); r.vc.view.layoutIfNeeded(); CATransaction.flush()
            samples.append((CACurrentMediaTime() - t0) * 1000 / 2)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        line(String(format: "timing plane median=%.2fms", median))
        XCTAssertLessThan(median, Self.timingCeilingPlaneMs, "đổi mặt phím chậm hẳn " + Self.howToUpdate)
    }
}
