import XCTest
import UIKit

/// Thời gian HIỆN bàn phím (báo cáo 25/10/2026: iPhone 11 Pro Max chạm ô tìm kiếm Danh bạ
/// 0,5–1 s mới thấy phím). Đo controller THẬT qua cùng đường iOS gọi: init → viewDidLoad →
/// viewWillAppear → layout → commit CA (≈ khung hình đầu) → viewDidAppear, rồi phần việc hoãn
/// (PostFrameWork) chạy sau khung đầu.
///
/// "cold" = lần dựng ĐẦU trong process (static/lazy/cache chưa có — gần với extension vừa
/// khởi động, chưa tính dyld); "warm" = dựng lại trong cùng process (iOS tạo controller mới gần
/// như mỗi lần hiện). Bảng từng bước từ StartupTrace (DEBUG) in ra dòng "STARTUP …".
/// Chạy riêng từng test (-only-testing) để "cold" thật sự lạnh.
///
/// Ngưỡng thời gian RỘNG (simulator dao động, máy chạy test có tải) — chỉ chặn hồi quy nặng.
/// Phần chặt là số lần dựng phím (đếm, không đo): đúng MỘT lần mỗi lần hiện.
final class KeyboardStartupTests: XCTestCase {

    private let suite = "vt-startup-tests"

    @MainActor final class Rig {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
        let vc: KeyboardViewController
        let proxy = KeyboardBenchTests.BenchProxy()
        /// ms: init controller, viewDidLoad, willAppear, layout đầu, commit (khung đầu), didAppear.
        var initMs = 0.0, loadMs = 0.0, willMs = 0.0, layoutMs = 0.0, commitMs = 0.0, didMs = 0.0
        var firstFrameMs: Double { initMs + loadMs + willMs + layoutMs + commitMs }
        /// Số lần xé + dựng cả plane trong lần hiện (KeyboardView.perfFullBuilds).
        var fullBuilds = 0

        /// Host giả: KHÔNG tự chuyển callback hiện/ẩn cho controller con ⇒ rig gọi đúng thứ tự
        /// như iOS với bàn phím: willAppear → layout → commit khung đầu → (bàn phím trượt lên,
        /// runloop quay — việc hoãn chạy) → didAppear. Gắn view thẳng vào window thì UIKit gọi
        /// will+didAppear ĐỒNG BỘ ngay lúc addSubview (didAppear trước khung đầu — sai với máy thật),
        /// thêm begin/endAppearanceTransition tay thì mỗi callback chạy hai lần.
        final class Host: UIViewController {
            override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
        }
        let host = Host()
        /// Thời gian "trượt lên" giả giữa khung đầu và didAppear (runloop quay — việc hoãn chạy).
        static let slideIn: TimeInterval = 0.05
        var deferredMs = 0.0

        /// `appear` false: dừng ngay sau khung đầu (chưa quay runloop — việc hoãn chưa chạy,
        /// chưa didAppear).
        init(fullAccess: Bool, dark: Bool = false, appear: Bool = true) {
            if dark { win.overrideUserInterfaceStyle = .dark }
            win.rootViewController = host
            win.isHidden = false
            host.view.layoutIfNeeded()
            var t = CACurrentMediaTime()
            func lap() -> Double { let n = CACurrentMediaTime(); defer { t = n }; return (n - t) * 1000 }
            vc = KeyboardViewController()
            initMs = lap()
            vc.debugProxy = proxy
            vc.debugFullAccess = fullAccess
            _ = lap()
            vc.loadViewIfNeeded()
            loadMs = lap()
            host.addChild(vc)
            vc.view.frame = CGRect(x: 0, y: 896 - 300, width: 414, height: 300)
            host.view.addSubview(vc.view)
            vc.didMove(toParent: host)
            _ = lap()
            vc.beginAppearanceTransition(true, animated: true)
            willMs = lap()
            vc.view.layoutIfNeeded()
            layoutMs = lap()
            CATransaction.flush()      // vẽ layer cần vẽ (chữ phím, ảnh) như commit khung đầu
            commitMs = lap()
            guard appear else { return }
            let c0 = Rig.mainCPU()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: Self.slideIn))
            deferredMs = (Rig.mainCPU() - c0) * 1000   // CPU main của việc hoãn (không tính lúc ngủ)
            _ = lap()
            vc.endAppearanceTransition()
            didMs = lap()
            fullBuilds = KeyboardView.perfFullBuilds
        }

        func close() {
            vc.beginAppearanceTransition(false, animated: false)
            vc.endAppearanceTransition()
            vc.willMove(toParent: nil)
            vc.view.removeFromSuperview()
            vc.removeFromParent()
            win.isHidden = true
        }

        /// CPU (giây) của thread main.
        static func mainCPU() -> Double {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let th = pthread_mach_thread_np(pthread_self())
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(th, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            guard kr == KERN_SUCCESS else { return 0 }
            return Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6
                + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
        }
    }

    @MainActor private func defaults(rich: Bool) -> UserDefaults {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        if rich {
            // Theme + nhân vật + âm phím + hiệu ứng (Plus) — cấu hình "nặng" người dùng hay bật.
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
        return d
    }

    private static func spin(_ s: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: s))
    }

    @MainActor private func report(_ tag: String, _ r: Rig) {
        let steps = (StartupTrace.recording ?? [:]).filter { !$0.key.hasSuffix("#") }
            .sorted { $0.value > $1.value }.prefix(40)
            .map { String(format: "%@=%.1f(x%d)", $0.key, $0.value, StartupTrace.counts[$0.key] ?? 0) }
            .joined(separator: " ")
        let ev = StartupTrace.counts.filter { $0.key.hasSuffix("#") }.sorted { $0.key < $1.key }
            .map { "\($0.key)\($0.value)" }.joined(separator: " ")
        let line = String(format: "STARTUP %@ [\(ev)] builds=%d firstFrame=%.1f init=%.1f load=%.1f will=%.1f layout=%.1f commit=%.1f did=%.1f deferredCPU=%.1f | %@",
                          tag, r.fullBuilds, r.firstFrameMs, r.initMs, r.loadMs, r.willMs, r.layoutMs,
                          r.commitMs, r.didMs, r.deferredMs, steps)
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }

    /// Cold rồi 5 lần warm. In bảng; trả (cold, warm trung vị, số lần dựng phím tối đa/lần hiện).
    @MainActor private func runStartup(rich: Bool, dark: Bool = false) -> (cold: Double, warm: Double, builds: Int) {
        let saved = UserDefaultsProvider.shared
        let savedPaywall = PlusGate.paywallEnabled
        UserDefaultsProvider.shared = defaults(rich: rich)
        defer {
            UserDefaultsProvider.shared = saved
            PlusGate.paywallEnabled = savedPaywall
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            StartupTrace.recording = nil
        }
        let tag = (rich ? "rich" : "default") + (dark ? "-dark" : "")
        StartupTrace.reset()
        let cold = Rig(fullAccess: rich, dark: dark)
        report("\(tag) cold", cold)
        var builds = cold.fullBuilds
        // Việc còn lại sau khung đầu (PostFrameWork / nền trả về main).
        StartupTrace.reset()
        Self.spin(1.0)
        report("\(tag) cold+deferred", cold)
        cold.close()
        Self.spin(0.2)
        var warm: [Double] = []
        for i in 0..<5 {
            StartupTrace.reset()
            let r = Rig(fullAccess: rich, dark: dark)
            if i == 4 { report("\(tag) warm", r) }
            warm.append(r.firstFrameMs)
            builds = max(builds, r.fullBuilds)
            Self.spin(0.3)
            r.close()
        }
        warm.sort()
        return (cold.firstFrameMs, warm[warm.count / 2], builds)
    }

    // MARK: thời gian tới khung đầu (hồi quy)

    /// Simulator trên Mac ~ 2–3× nhanh hơn A13. Số đo thật ghi ở commit; ngưỡng ở đây gấp nhiều
    /// lần để không flaky — chỉ bắt hồi quy cỡ "nạp từ điển / giải ảnh lớn trên main".
    @MainActor func testTimeToFirstFrameDefault() {
        let r = runStartup(rich: false)
        XCTAssertLessThan(r.cold, 400, "khung đầu (cold, mặc định) ms")
        XCTAssertLessThan(r.warm, 120, "khung đầu (warm, mặc định) ms")
        XCTAssertEqual(r.builds, 1, "dựng phím đúng MỘT lần mỗi lần hiện")
    }

    @MainActor func testTimeToFirstFrameDark() {
        let r = runStartup(rich: false, dark: true)
        XCTAssertLessThan(r.cold, 400, "khung đầu (cold, tối) ms")
        XCTAssertLessThan(r.warm, 120, "khung đầu (warm, tối) ms")
        XCTAssertEqual(r.builds, 1, "chế độ tối: không dựng sáng rồi dựng lại tối")
    }

    @MainActor func testTimeToFirstFrameRich() {
        let r = runStartup(rich: true)
        XCTAssertLessThan(r.cold, 500, "khung đầu (cold, theme+nhân vật+âm) ms")
        XCTAssertLessThan(r.warm, 150, "khung đầu (warm, theme+nhân vật+âm) ms")
        XCTAssertEqual(r.builds, 1, "theme: không dựng kiểu mặc định rồi dựng lại theo theme")
    }

    // MARK: việc hoãn sau khung đầu

    /// Gõ NGAY sau khung đầu, trước khi việc hoãn (gợi ý, model cá nhân…) chạy: engine Telex sẵn
    /// sàng, chữ đúng; quay runloop xong thì việc hoãn đã chạy và thanh gợi ý được tính.
    @MainActor func testTypingBeforeDeferredWorkRuns() throws {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = defaults(rich: false)
        defer { UserDefaultsProvider.shared = saved; UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let r = Rig(fullAccess: false, appear: false)
        defer { r.close() }
        XCTAssertTrue(r.vc.debugPostFramePending, "gợi ý mở đầu / model hoãn tới sau khung đầu")
        let passes0 = r.vc.debugSuggestionPasses
        XCTAssertEqual(passes0, 0, "khung đầu không tính thanh gợi ý")
        let kb = r.vc.debugKeyboard
        for c in "vieejt" {
            let f = try XCTUnwrap(kb.debugLetterFrame(String(c)), "phím \(c) đã dựng ở khung đầu")
            kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime())
        }
        kb.benchSpace()
        XCTAssertEqual(r.proxy.text, "Việt ", "đầu câu: tự viết hoa")
        Self.spin(0.3)
        XCTAssertFalse(r.vc.debugPostFramePending, "việc hoãn đã chạy")
        XCTAssertGreaterThan(r.vc.debugSuggestionPasses, passes0)
    }

    @MainActor func testPostFrameRunsAfterCommitOnce() {
        let w = PostFrameWork()
        var runs = 0
        w.schedule { runs += 1 }
        w.schedule { runs += 10 }
        XCTAssertEqual(runs, 0, "không chạy đồng bộ")
        XCTAssertTrue(w.isPending)
        Self.spin(0.1)
        XCTAssertEqual(runs, 11, "chạy sau một lượt runloop, theo thứ tự")
        XCTAssertFalse(w.isPending)
        Self.spin(0.1)
        XCTAssertEqual(runs, 11, "không chạy lại")
    }

    @MainActor func testPostFrameFlushAndCancel() {
        let w = PostFrameWork()
        var runs = 0
        w.schedule { runs += 1 }
        w.flush()
        XCTAssertEqual(runs, 1, "flush chạy ngay (viewDidAppear)")
        Self.spin(0.1)
        XCTAssertEqual(runs, 1, "observer / main.async cũ không chạy lặp")
        w.schedule { runs += 100 }
        w.cancel()
        Self.spin(0.1)
        XCTAssertEqual(runs, 1, "cancel (ẩn trước khi kịp chạy) bỏ hết")
        w.schedule { runs += 5 }   // dùng lại sau cancel (lần hiện kế)
        Self.spin(0.1)
        XCTAssertEqual(runs, 6)
    }

    // MARK: âm phím không chặn main lúc hiện

    /// Engine âm đang dựng/dừng trên queue (giữ lock lâu) ⇒ setStyle/setVolume/prepare/
    /// setSqueakEnabled/shutdown từ viewWillAppear KHÔNG chờ; áp sau, đúng thứ tự gọi.
    func testKeySoundConfigNeverBlocksMain() {
        let ks = KeySound.shared
        let style0 = ks.debugStyleRaw
        defer { ks.debugDrain(); ks.setStyle(style0); ks.setVolume(percent: 50); ks.debugDrain() }
        ks.debugHoldLock(for: 0.4)
        Thread.sleep(forTimeInterval: 0.05)   // queue đã giữ lock
        let t0 = CACurrentMediaTime()
        ks.setStyle("wood")
        ks.setVolume(percent: 20)
        ks.setSqueakEnabled(false)
        ks.shutdown()
        ks.setStyle("water")                  // lệnh sau thắng (giữ thứ tự)
        let ms = (CACurrentMediaTime() - t0) * 1000
        XCTAssertLessThan(ms, 50, "main không chờ lock của engine âm")
        ks.debugDrain()
        XCTAssertEqual(ks.debugStyleRaw, "water")
        XCTAssertEqual(ks.debugGain, KeySoundSynth.gain(forPercent: 20))
        // Lock rảnh ⇒ đồng bộ như cũ.
        ks.setStyle("pop")
        XCTAssertEqual(ks.debugStyleRaw, "pop")
    }

    // MARK: dựng phím một lần

    /// deferInitialBuild: init không dựng; batch (controller) dựng MỘT lần với kiểu cuối (tối).
    @MainActor func testDeferredInitialBuildBuildsOnceWithFinalStyle() {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, deferInitialBuild: true) { _ in }
        XCTAssertTrue(kb.initialBuildPending)
        KeyboardView.perfFullBuilds = 0
        kb.beginBatch()
        kb.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        kb.batchConfigure {    // lồng như refreshFieldTraits
            kb.applyAppearance(.dark, style: .dark)
        }
        XCTAssertTrue(kb.initialBuildPending, "batch ngoài còn mở ⇒ chưa dựng")
        kb.endBatch()
        XCTAssertFalse(kb.initialBuildPending)
        XCTAssertEqual(KeyboardView.perfFullBuilds, 1)
        XCTAssertNotNil(kb.debugLetterFrame("a"))
        kb.layoutIfNeeded()
        XCTAssertEqual(KeyboardView.perfFullBuilds, 1, "layout không dựng lại")
    }

    /// Không ai mở batch (willAppear bị nuốt) ⇒ lượt layout đầu tự dựng — không hiện bàn phím rỗng.
    @MainActor func testDeferredInitialBuildFallsBackOnLayout() {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, deferInitialBuild: true) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.layoutIfNeeded()
        XCTAssertFalse(kb.initialBuildPending)
        XCTAssertNotNil(kb.debugLetterFrame("q"))
        kb.tearDown()
    }
}
