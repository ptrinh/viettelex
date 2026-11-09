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
        /// Khung đầu là ảnh lưới phím (KeySnapshot); ms dựng phím thật sau khung đầu (kv.snapshotLive,
        /// gồm commit vẽ phím); footprint (MB) ngay sau khung đầu / sau didAppear.
        var snapshotShown = false
        var liveMs = 0.0
        var memFirstFrame = 0.0, memDid = 0.0
        /// Phím nhận chạm từ lúc nào (ms từ init): đường cũ = khung đầu; ảnh = khung đầu + dựng thật.
        var keysReadyMs: Double { firstFrameMs + (snapshotShown ? liveMs : 0) }

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
            snapshotShown = vc.debugKeyboard.debugSnapshotShowing
            memFirstFrame = Rig.footprintMB()
            _ = lap()
            guard appear else { return }
            let c0 = Rig.mainCPU()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: Self.slideIn))
            deferredMs = (Rig.mainCPU() - c0) * 1000   // CPU main của việc hoãn (không tính lúc ngủ)
            _ = lap()
            vc.endAppearanceTransition()
            didMs = lap()
            fullBuilds = KeyboardView.perfFullBuilds
            liveMs = StartupTrace.recording?["kv.snapshotLive"] ?? 0
            memDid = Rig.footprintMB()
        }

        /// phys_footprint (MB) — số Jetsam tính cho extension.
        static func footprintMB() -> Double {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<Int32>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
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
        let line = String(format: "STARTUP %@ [\(ev)] builds=%d firstFrame=%.1f init=%.1f load=%.1f will=%.1f layout=%.1f commit=%.1f did=%.1f deferredCPU=%.1f snap=%d keysReady=%.1f memFF=%.1f memDid=%.1f | %@",
                          tag, r.fullBuilds, r.firstFrameMs, r.initMs, r.loadMs, r.willMs, r.layoutMs,
                          r.commitMs, r.didMs, r.deferredMs, r.snapshotShown ? 1 : 0, r.keysReadyMs,
                          r.memFirstFrame, r.memDid, steps)
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

    // MARK: đọc cài đặt một lần

    /// Cài đặt (~45 key App Group) đọc đúng MỘT lần mỗi lần hiện: init controller không đọc
    /// (bridge lười), viewWillAppear đọc rồi truyền xuống EngineBridge.
    @MainActor func testSettingsLoadedOncePerAppearance() {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = defaults(rich: false)
        defer { UserDefaultsProvider.shared = saved; UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        KeyboardSettings.debugLoadCount = 0
        let vc = KeyboardViewController()
        XCTAssertEqual(KeyboardSettings.debugLoadCount, 0, "init không đọc cài đặt")
        vc.loadViewIfNeeded()
        XCTAssertEqual(KeyboardSettings.debugLoadCount, 0, "viewDidLoad không đọc cài đặt")
        let r = Rig(fullAccess: false)
        XCTAssertEqual(KeyboardSettings.debugLoadCount, 1, "một lần hiện = một lần đọc")
        // Cài đặt đổi giữa hai lần hiện (app vừa sửa): lần hiện sau đọc lại, đúng một lần.
        UserDefaultsProvider.shared?.set(true, forKey: "autoCorrect")
        r.close()
        Self.spin(0.1)
        let r2 = Rig(fullAccess: false)
        XCTAssertEqual(KeyboardSettings.debugLoadCount, 2)
        r2.close()
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

    // MARK: ảnh lưới phím cho khung đầu (KeySnapshot)

    /// Bật ảnh lưới phím với thư mục riêng (`keep`: giữ ảnh giữa các tiến trình — đo lạnh có ảnh).
    @MainActor private func withSnapshot(dir name: String, keep: Bool = false, _ body: () throws -> Void) rethrows {
        let savedDir = KeySnapshot.Store.debugDirectory
        KeySnapshot.debugEnabled = true
        KeySnapshot.Store.debugDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
        if !keep { KeySnapshot.Store.clear() }
        KeySnapshot.Store.resetListing()
        defer {
            if !keep { KeySnapshot.Store.clear() }
            KeySnapshot.debugEnabled = nil
            KeySnapshot.debugVoiceOver = nil
            KeySnapshot.Store.debugDirectory = savedDir
            KeySnapshot.Store.resetListing()
        }
        try body()
    }

    @MainActor private func withDefaults(rich: Bool, _ body: () throws -> Void) rethrows {
        let saved = UserDefaultsProvider.shared
        let savedPaywall = PlusGate.paywallEnabled
        UserDefaultsProvider.shared = defaults(rich: rich)
        defer {
            UserDefaultsProvider.shared = saved
            PlusGate.paywallEnabled = savedPaywall
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        try body()
    }

    /// Chụp từ bàn phím đang hiện (chờ yên: nhãn "ViệtTelex" trên phím cách mờ dần ~1 s đầu — layer
    /// đang animation thì không chụp, như controller chụp sau captureDelay) và chờ ghi nền xong.
    @MainActor private func capture(_ r: Rig) -> Bool {
        var done = false
        var started = false
        let settle = Date(timeIntervalSinceNow: 3)
        while !started, Date() < settle {
            started = r.vc.debugKeyboard.captureSnapshotIfNeeded(done: { done = true })
            // Controller tự chụp trước (viewDidAppear + captureDelay) — cùng ảnh.
            if !started, KeySnapshot.Store.current() != nil, !KeySnapshot.Store.saving { return true }
            if !started { Self.spin(0.1) }
        }
        guard started else { return false }
        let until = Date(timeIntervalSinceNow: 5)
        while !done, Date() < until { Self.spin(0.02) }
        return done && KeySnapshot.Store.current() != nil
    }

    private static let alphabet = "qwertyuiopasdfghjklzxcvbnm"

    /// Lần hiện 1: đường cũ + chụp; trả khung từng phím chữ (đóng rig, liệt kê lại thư mục như tiến trình mới).
    /// `after`: chạy trên bàn phím đường cũ SAU khi chụp (vd gõ để lấy số đối chứng).
    @MainActor private func prime(dark: Bool = false, fullAccess: Bool = false,
                                  after: ((Rig) -> Void)? = nil) throws -> [Character: CGRect] {
        let r = Rig(fullAccess: fullAccess, dark: dark)
        XCTAssertFalse(r.snapshotShown, "chưa có ảnh ⇒ đường cũ")
        XCTAssertTrue(capture(r), "chụp + ghi nền")
        var frames: [Character: CGRect] = [:]
        for c in Self.alphabet { frames[c] = try XCTUnwrap(r.vc.debugKeyboard.debugLetterFrame(String(c))) }
        after?(r)
        r.close()
        Self.spin(0.1)
        KeySnapshot.Store.resetListing()
        KeyboardView.perfFullBuilds = 0
        return frames
    }

    func testSnapshotEntryFileNameRoundTrip() {
        let e = KeySnapshot.Entry(hash: KeySnapshot.digest(["a"]), frame: KeySnapshot.digest(["b"], length: 16),
                                  pixelWidth: 1206, pixelHeight: 648)
        XCTAssertEqual(KeySnapshot.Entry.parse(e.fileName), e)
        XCTAssertEqual(e.byteCount, 1206 * 648 * 4)
        for bad in ["", "keysnap-.bgra", "keysnap-ab-cd-10x.bgra", "keysnap-AB-cd-10x10.bgra", "keysnap-ab-cd-0x10.bgra",
                    "keysnap-ab-cd-10x10.png", "other-ab-cd-10x10.bgra", "keysnap-ab-cd-99999x99999.bgra",
                    "keysnap-ab-cd-ef-10x10.bgra", "keysnap-ab-zz-10x10.bgra", "keysnap-ab-cd-10x10.bgra.tmp"] {
            XCTAssertNil(KeySnapshot.Entry.parse(bad), bad)
        }
    }

    /// Khoá tất định + đủ trường: bảng màu liệt kê tay phải phủ MỌI trường lưu (Mirror đếm — thêm
    /// trường mà quên khoá ⇒ đỏ), mỗi trường đổi là khoá đổi.
    func testSnapshotPaletteKeyCoversAllFields() {
        let light = KeyboardTheme.system.palette(systemDark: false)
        XCTAssertEqual(Mirror(reflecting: light).children.count, KeySnapshot.paletteFieldCount,
                       "KeyboardPalette đổi số trường ⇒ cập nhật KeySnapshot.paletteKey")
        XCTAssertEqual(Mirror(reflecting: RGBA(r: 0, g: 0, b: 0)).children.count, 4, "RGBA đổi ⇒ cập nhật rgbaKey")
        XCTAssertEqual(KeySnapshot.paletteKey(light), KeySnapshot.paletteKey(light))
        XCTAssertNotEqual(KeySnapshot.paletteKey(light), KeySnapshot.paletteKey(KeyboardTheme.system.palette(systemDark: true)))
        var seen: Set<String> = [KeySnapshot.paletteKey(light)]
        func differs(_ what: String, _ change: (inout KeyboardPalette) -> Void) {
            var p = light
            change(&p)
            XCTAssertTrue(seen.insert(KeySnapshot.paletteKey(p)).inserted, what)
        }
        differs("background") { $0.background = RGBA(r: 0.1, g: 0.2, b: 0.3) }
        differs("background2") { $0.background2 = RGBA(r: 0.1, g: 0.2, b: 0.3) }
        differs("keyFill") { $0.keyFill.r += 0.01 }
        differs("specialFill") { $0.specialFill.g += 0.01 }
        differs("ink") { $0.ink.b += 0.01 }
        differs("trail") { $0.trail.a -= 0.01 }
        differs("barInk") { $0.barInk.r += 0.02 }
        differs("balloon") { $0.balloon.r += 0.02 }
        differs("accent") { $0.accent.r += 0.02 }
        differs("accentInk") { $0.accentInk.r += 0.02 }
        differs("keyBorder") { $0.keyBorder = RGBA(r: 1, g: 0, b: 0) }
        differs("isDark") { $0.isDark.toggle() }
        differs("keyLabel") { $0.keyLabel = RGBA(r: 0, g: 1, b: 0) }
        differs("surfaceAlpha") { $0.surfaceAlpha = 0.5 }
        differs("keyLabelPinned") { $0.keyLabelPinned.toggle() }
        differs("surfaceDark") { $0.surfaceDark = true }
        differs("functionFill") { $0.functionFill = RGBA(r: 0, g: 0, b: 1) }
        differs("functionInk") { $0.functionInk = RGBA(r: 0, g: 0.5, b: 1) }
        differs("rainbowBorder") { $0.rainbowBorder.toggle() }
        differs("auroraBorder") { $0.auroraBorder.toggle() }
        differs("hueFlow") { $0.hueFlow.toggle() }
        differs("spaceSoundhole") { $0.spaceSoundhole.toggle() }
        differs("cornerGlyph") { $0.cornerGlyph = "★" }
        differs("auroraColors") { $0.auroraColors = [0xFF0000, 0x00FF00] }
        differs("accentShift") { $0.accentShift.toggle() }
        XCTAssertEqual(KeySnapshot.digest(["a", "b"]), KeySnapshot.digest(["a", "b"]))
        XCTAssertNotEqual(KeySnapshot.digest(["a", "b"]), KeySnapshot.digest(["ab"]))
        XCTAssertEqual(KeySnapshot.digest(["a"]).count, 32)
        // SHA-256("") — cố định giữa các lần chạy / máy.
        XCTAssertEqual(KeySnapshot.digest([""], length: 64),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testSnapshotFrameKey() {
        let r = CGRect(x: 0, y: 100, width: 402, height: 216)
        let k = KeySnapshot.frameKey(exact: r, scale: 3)
        XCTAssertEqual(KeySnapshot.frameKey(exact: r, scale: 3), k)
        XCTAssertEqual(KeySnapshot.frameKey(exact: r.offsetBy(dx: 0, dy: 1), scale: 3), k, "dời nguyên điểm ảnh: cùng hình")
        XCTAssertNotEqual(KeySnapshot.frameKey(exact: r.offsetBy(dx: 0, dy: 0.5), scale: 3), k, "lệch phần lẻ: mép phím khác")
        XCTAssertNotEqual(KeySnapshot.frameKey(exact: r.insetBy(dx: 0, dy: 1), scale: 3), k, "cỡ khác")
        XCTAssertNotEqual(KeySnapshot.frameKey(exact: r, scale: 2), k, "scale khác")
        XCTAssertTrue(KeySnapshot.pixelSize(CGSize(width: 402, height: 216), scale: 3) == (1206, 648))
    }

    /// Mọi điều kiện phải đúng mới dùng ảnh; thiếu một ⇒ dựng như cũ.
    func testSnapshotDecision() {
        let e = KeySnapshot.Entry(hash: "aa", frame: "bb", pixelWidth: 10, pixelHeight: 5)
        func dec(_ enabled: Bool = true, vo: Bool = false, eligible: Bool = true, noStore: Bool = false,
                 hash: String = "aa", frame: String? = "bb", px: (width: Int, height: Int)? = (10, 5)) -> KeySnapshot.Use {
            KeySnapshot.decide(enabled: enabled, voiceOver: vo, eligible: eligible, stored: noStore ? nil : e,
                               hash: hash, frame: frame, pixelSize: px)
        }
        XCTAssertEqual(dec(), .show(e))
        XCTAssertEqual(dec(frame: nil), .pending, "chưa có khung: hoãn")
        XCTAssertEqual(dec(false), .build, "tắt")
        XCTAssertEqual(dec(false, frame: nil), .build)
        XCTAssertEqual(dec(vo: true), .build, "VoiceOver")
        XCTAssertEqual(dec(vo: true, frame: nil), .build)
        XCTAssertEqual(dec(eligible: false), .build, "plane emoji / lớp phủ bám phím")
        XCTAssertEqual(dec(noStore: true), .build, "chưa có ảnh")
        XCTAssertEqual(dec(noStore: true, frame: nil), .build)
        XCTAssertEqual(dec(hash: "ab"), .build, "trạng thái khác")
        XCTAssertEqual(dec(hash: "ab", frame: nil), .build)
        XCTAssertEqual(dec(frame: "bc"), .build, "khung khác")
        XCTAssertEqual(dec(px: (10, 6)), .build, "cỡ điểm ảnh khác")
    }

    func testSnapshotCaptureDecision() {
        let e = KeySnapshot.Entry(hash: "aa", frame: "bb", pixelWidth: 10, pixelHeight: 5)
        func cap(enabled: Bool = true, vo: Bool = false, eligible: Bool = true, interacted: Bool = false,
                 showing: Bool = false, built: Bool = true, unstable: Bool = false, stored: KeySnapshot.Entry? = nil,
                 entry: KeySnapshot.Entry? = nil) -> Bool {
            KeySnapshot.shouldCapture(enabled: enabled, voiceOver: vo, eligible: eligible, interacted: interacted,
                                      showing: showing, keysBuilt: built, unstable: unstable,
                                      stored: stored, entry: entry ?? e)
        }
        XCTAssertTrue(cap())
        XCTAssertTrue(cap(stored: KeySnapshot.Entry(hash: "zz", frame: "bb", pixelWidth: 10, pixelHeight: 5)),
                      "khoá đổi ⇒ chụp lại")
        XCTAssertFalse(cap(stored: e), "đã có đúng ảnh này ⇒ không ghi lại")
        XCTAssertFalse(cap(enabled: false))
        XCTAssertFalse(cap(vo: true))
        XCTAssertFalse(cap(eligible: false), "emoji / mẫu câu (nội dung người dùng), lớp phủ bám phím")
        XCTAssertFalse(cap(interacted: true), "đã chạm ⇒ không phải trạng thái mở đầu")
        XCTAssertFalse(cap(showing: true))
        XCTAssertFalse(cap(built: false))
        XCTAssertFalse(cap(unstable: true), "đang animation / layer không chụp được")
        XCTAssertFalse(cap(entry: KeySnapshot.Entry(hash: "aa", frame: "bb", pixelWidth: 4000, pixelHeight: 1001)),
                       "quá trần điểm ảnh")
    }

    /// Khoá đổi theo mọi thứ làm đổi hình lưới phím; giữ nguyên khi không gì đổi.
    @MainActor func testSnapshotKeyCoversVisualState() {
        withDefaults(rich: false) {
            let lang0 = L10n.lang
            defer { L10n.apply(lang0) }
            let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
            win.isHidden = false
            let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
            kb.frame = CGRect(x: 0, y: 596, width: 414, height: 300)
            win.addSubview(kb)
            kb.layoutIfNeeded()
            defer { kb.tearDown(); win.isHidden = true }
            var h = kb.debugSnapshotHash
            XCTAssertEqual(kb.debugSnapshotHash, h, "tất định")
            func changes(_ what: String, _ body: () -> Void) {
                body()
                let n = kb.debugSnapshotHash
                XCTAssertNotEqual(n, h, what)
                h = n
            }
            changes("shift") { kb.setAutoShift(false) }
            changes("sáng/tối") { kb.updateDark(true) }
            kb.updateDark(true)
            XCTAssertEqual(kb.debugSnapshotHash, h, "không đổi gì ⇒ cùng khoá")
            changes("phím Return") { kb.configureReturnKey(type: .send) }
            changes("ngôn ngữ phím cách") { kb.configureSpaceFlick(enabled: true, language: .en) }
            changes("phím 🌐") { kb.setNeedsGlobe(true) }
            changes("loại ô") { kb.configureInputKind(.email) }
            changes("hàng số") { kb.numberRowEnabled = true }
            changes("theme") {
                UserDefaultsProvider.shared?.set("peach", forKey: "keyboardTheme")
                kb.applyAppearance(.dark, style: .dark)
            }
            changes("ngôn ngữ giao diện") { L10n.apply(lang0 == "en" ? "vi" : "en") }
            changes("plane") { kb.debugSetPlane(numbers: true) }
        }
    }

    /// Lần mở có ảnh khớp: khung đầu là ảnh (không dựng phím); ngay sau commit phím thật dựng đúng
    /// chỗ, ảnh nhả; điểm ảnh của phím thật = ảnh (khoá đủ ⇒ không đổi hình lúc tráo).
    @MainActor func testSnapshotShownAtFirstFrameThenLiveKeys() throws {
        try withDefaults(rich: false) {
            try withSnapshot(dir: "vt-keysnap-test") {
                let frames = try prime()
                let stored = try XCTUnwrap(KeySnapshot.Store.current())
                let r = Rig(fullAccess: false, appear: false)
                defer { r.close() }
                let kb = r.vc.debugKeyboard
                XCTAssertTrue(r.snapshotShown, "khung đầu = ảnh")
                XCTAssertTrue(kb.firstFrameReady)
                XCTAssertTrue(kb.initialBuildPending)
                XCTAssertNil(kb.debugLetterFrame("a"), "khung đầu chưa dựng phím")
                XCTAssertEqual(KeyboardView.perfFullBuilds, 0)
                XCTAssertEqual(kb.debugSnapshotImage?.width, stored.pixelWidth)
                Self.spin(0.1)
                XCTAssertFalse(kb.debugSnapshotShowing, "phím thật ngay sau khung đầu")
                XCTAssertNil(kb.debugSnapshotImage, "ảnh đã nhả")
                XCTAssertEqual(KeyboardView.perfFullBuilds, 1, "dựng đúng một lần")
                for c in Self.alphabet {
                    XCTAssertEqual(kb.debugLetterFrame(String(c)), frames[c], "phím \(c) đúng chỗ ảnh")
                }
                let live = try XCTUnwrap(kb.debugRenderRows())
                XCTAssertEqual(live.entry, stored, "cùng khoá + khung")
                let file = try Data(contentsOf: try XCTUnwrap(KeySnapshot.Store.directory)
                    .appendingPathComponent(stored.fileName))
                XCTAssertGreaterThanOrEqual(file.count, live.bytes.count, "điểm ảnh + đuôi khung phím")
                var diff = 0
                file.prefix(live.bytes.count).withUnsafeBytes { a in
                    live.bytes.withUnsafeBytes { b in
                        for i in 0..<min(a.count, b.count) where a[i] != b[i] { diff += 1 }
                    }
                }
                let frac = Double(diff) / Double(max(file.count, 1))
                print(String(format: "SNAPDIFF bytes=%d frac=%.5f", diff, frac))
                XCTAssertLessThan(frac, 0.005, "ảnh ≈ phím thật")
            }
        }
    }

    /// Chạm khi khung còn là ảnh (trước lượt runloop dựng phím thật): hit-test dựng phím NGAY, chữ đúng.
    @MainActor func testSnapshotTouchBeforeLiveKeysIsNotLost() throws {
        try withDefaults(rich: false) {
            try withSnapshot(dir: "vt-keysnap-test") {
                let frames = try prime()
                let r = Rig(fullAccess: false, appear: false)
                defer { r.close() }
                let kb = r.vc.debugKeyboard
                XCTAssertTrue(kb.debugSnapshotShowing)
                let first = try XCTUnwrap(frames["v"])
                XCTAssertTrue(kb.hitTest(CGPoint(x: first.midX, y: first.midY), with: nil) === kb,
                              "chạm đầu tiên rơi vào router phím chữ (phím thật đã dựng)")
                XCTAssertFalse(kb.debugSnapshotShowing, "hit-test dựng phím thật ngay")
                for c in "vieejt" {
                    let f = try XCTUnwrap(frames[c])
                    kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime())
                }
                kb.benchSpace()
                XCTAssertEqual(r.proxy.text, "Việt ", "không mất chạm nào")
                Self.spin(0.2)
                XCTAssertEqual(KeyboardView.perfFullBuilds, 1, "không dựng lại lần hai")
                XCTAssertFalse(kb.captureSnapshotIfNeeded(), "đã gõ ⇒ không chụp")
            }
        }
    }

    /// Theme động: phím tự chuyển động / lớp phủ bám khung phím ⇒ không dùng ảnh; còn lại cho phép.
    func testSnapshotThemeGate() {
        XCTAssertTrue(KeySnapshot.themeAllows(keyMotion: nil, keyShape: nil, floatActive: false, keyFrameOverlays: false))
        XCTAssertFalse(KeySnapshot.themeAllows(keyMotion: "float", keyShape: nil, floatActive: false, keyFrameOverlays: false),
                       "keyMotion (Lạc trôi) — kể cả khi chưa Plus/tiết kiệm pin")
        XCTAssertFalse(KeySnapshot.themeAllows(keyMotion: "mới-chưa-biết", keyShape: nil, floatActive: false, keyFrameOverlays: false),
                       "keyMotion lạ cũng chặn")
        XCTAssertFalse(KeySnapshot.themeAllows(keyMotion: nil, keyShape: nil, floatActive: true, keyFrameOverlays: false),
                       "hiệu ứng float")
        XCTAssertFalse(KeySnapshot.themeAllows(keyMotion: nil, keyShape: nil, floatActive: false, keyFrameOverlays: true),
                       "đập chuột (cần view phím thật)")
        XCTAssertFalse(KeySnapshot.themeAllows(keyMotion: nil, keyShape: "glass", floatActive: false, keyFrameOverlays: false),
                       "phím kính: phụ thuộc nội dung phía sau")
        XCTAssertTrue(KeySnapshot.themeAllows(keyMotion: nil, keyShape: "pixel", floatActive: false, keyFrameOverlays: false),
                      "phím pixel: skin tĩnh")
    }

    /// Bàn phím thật: theme Lạc trôi (keyMotion float) ⇒ không đủ điều kiện; theme tĩnh ⇒ đủ.
    /// Theo giờ: bảng màu nằm trong khoá ⇒ giờ khác = khoá khác (không hiện ảnh của giờ trước).
    @MainActor func testSnapshotSkippedForMovingThemes() {
        withDefaults(rich: false) {
            PlusGate.paywallEnabled = false
            let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
            win.isHidden = false
            let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
            kb.frame = CGRect(x: 0, y: 596, width: 414, height: 300)
            win.addSubview(kb)
            defer { kb.tearDown(); win.isHidden = true }
            kb.applyAppearance(.default, style: .light)
            kb.layoutIfNeeded()
            XCTAssertTrue(kb.debugSnapshotEligible, "Hệ thống: tĩnh")
            UserDefaultsProvider.shared?.set("peach", forKey: "keyboardTheme")
            kb.applyAppearance(.default, style: .light)
            XCTAssertTrue(kb.debugSnapshotEligible, "theme tĩnh")
            UserDefaultsProvider.shared?.set("drift", forKey: "keyboardTheme")
            kb.applyAppearance(.default, style: .light)
            XCTAssertFalse(kb.debugSnapshotEligible, "Lạc trôi: phím lơ lửng")
            UserDefaultsProvider.shared?.set("stainedGlass", forKey: "keyboardTheme")
            kb.applyAppearance(.default, style: .light)
            XCTAssertFalse(kb.debugSnapshotEligible, "Kính màu: phím kính")
            for t in ["rgb", "ai", "trippy", "nightclub"] {
                UserDefaultsProvider.shared?.set(t, forKey: "keyboardTheme")
                kb.applyAppearance(.default, style: .light)
                XCTAssertTrue(kb.debugSnapshotEligible, "\(t): mặt phím tĩnh, viền / nền / đèn là lớp riêng")
            }
            UserDefaultsProvider.shared?.set("peach", forKey: "keyboardTheme")
            kb.applyAppearance(.default, style: .light)
            XCTAssertTrue(kb.debugSnapshotEligible, "về theme tĩnh")
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let day = cal.startOfDay(for: Date())
        let keys = Set([3, 9, 13, 19, 23].map { h in
            KeySnapshot.paletteKey(KeyboardTheme.timeOfDay.palette(systemDark: false, at: day.addingTimeInterval(Double(h) * 3600)))
        })
        XCTAssertGreaterThan(keys.count, 1, "Theo giờ: bảng màu (và khoá) đổi theo giờ")
    }

    /// Hiệu ứng bấm phím là lớp riêng: chạm lúc khung còn là ảnh vẫn ra hiệu ứng như đường cũ.
    @MainActor func testSnapshotTouchKeepsKeyEffects() throws {
        try withDefaults(rich: true) {
            try withSnapshot(dir: "vt-keysnap-test") {
                var baseline = -1
                let word = "vieejt"
                var frames: [Character: CGRect] = [:]
                frames = try prime(fullAccess: true) { r in
                    let kb = r.vc.debugKeyboard
                    let e0 = kb.debugKeyEffectEmits
                    for c in word {
                        guard let f = kb.debugLetterFrame(String(c)) else { continue }
                        kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime())
                    }
                    baseline = kb.debugKeyEffectEmits - e0
                }
                XCTAssertGreaterThan(baseline, 0, "theme rich có hiệu ứng bấm phím")
                let r = Rig(fullAccess: true, appear: false)
                defer { r.close() }
                let kb = r.vc.debugKeyboard
                XCTAssertTrue(kb.debugSnapshotShowing, "theme rich (tĩnh) dùng ảnh")
                let e0 = max(kb.debugKeyEffectEmits, 0)
                for c in word {
                    let f = try XCTUnwrap(frames[c])
                    kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime())
                }
                XCTAssertEqual(kb.debugKeyEffectEmits - e0, baseline, "chạm lúc còn ảnh: hiệu ứng như đường cũ")
                XCTAssertEqual(r.proxy.text, "Việt")
            }
        }
    }

    /// Ảnh CHỈ là mặt phím trên nền trong suốt: theme Gaming RGB (nền đục + viền cầu vồng) — khe giữa
    /// phím alpha 0 (không nền), viền cầu vồng không nằm trong ảnh (lớp riêng TRÊN ảnh, viền theo khung
    /// phím lưu kèm ngay khung đầu), điểm ảnh = vùng phím thật.
    @MainActor func testSnapshotIsKeysOnlyOnTransparentBackground() throws {
        try withDefaults(rich: false) {
            PlusGate.paywallEnabled = false
            UserDefaultsProvider.shared?.set("rgb", forKey: "keyboardTheme")
            try withSnapshot(dir: "vt-keysnap-test") {
                var outlinesLive = 0
                let frames = try prime(fullAccess: true) { r in
                    outlinesLive = r.vc.debugKeyboard.debugRainbowLayering?.outlines ?? -1
                }
                XCTAssertGreaterThan(outlinesLive, 26, "theme rgb có viền cầu vồng trên mọi phím")
                let e = try XCTUnwrap(KeySnapshot.Store.current())
                let file = try Data(contentsOf: try XCTUnwrap(KeySnapshot.Store.directory).appendingPathComponent(e.fileName))
                let r = Rig(fullAccess: true, appear: false)
                defer { r.close() }
                let kb = r.vc.debugKeyboard
                XCTAssertTrue(kb.debugSnapshotShowing, "Gaming RGB dùng ảnh")
                let rows = kb.keyAreaFrame
                let scale = CGFloat(e.pixelWidth) / rows.width
                func alpha(_ p: CGPoint) -> UInt8 {
                    let x = Int(((p.x - rows.minX) * scale).rounded(.down)), y = Int(((p.y - rows.minY) * scale).rounded(.down))
                    return file[(y * e.pixelWidth + x) * 4 + 3]
                }
                let q = try XCTUnwrap(frames["q"]), w = try XCTUnwrap(frames["w"]), a = try XCTUnwrap(frames["a"])
                XCTAssertEqual(alpha(CGPoint(x: (q.maxX + w.minX) / 2, y: q.midY)), 0, "khe ngang giữa phím: trong suốt")
                XCTAssertEqual(alpha(CGPoint(x: q.midX + 4, y: (q.maxY + a.minY) / 2)), 0, "khe giữa hàng: trong suốt")
                XCTAssertGreaterThan(alpha(CGPoint(x: q.midX, y: q.midY)), 0, "mặt phím có trong ảnh")
                let layering = try XCTUnwrap(kb.debugRainbowLayering)
                XCTAssertTrue(layering.aboveKeys, "viền nằm TRÊN ảnh")
                XCTAssertFalse(layering.insideKeys, "viền không thuộc vùng phím ⇒ không vào ảnh")
                XCTAssertEqual(layering.outlines, outlinesLive, "khung đầu (ảnh) đã có viền đủ phím")
                Self.spin(0.1)
                XCTAssertFalse(kb.debugSnapshotShowing)
                XCTAssertEqual(kb.debugRainbowLayering?.outlines, outlinesLive, "phím thật: viền như cũ")
                let live = try XCTUnwrap(kb.debugRenderRows())
                XCTAssertTrue(file.prefix(live.bytes.count) == live.bytes, "ảnh = vùng phím thật (không viền, không nền)")
            }
        }
    }

    /// Trạng thái sắp hiện khác ảnh (tối vs sáng) ⇒ đường cũ: dựng phím ở khung đầu.
    @MainActor func testSnapshotNotUsedWhenStateDiffers() throws {
        try withDefaults(rich: false) {
            try withSnapshot(dir: "vt-keysnap-test") {
                _ = try prime(dark: false)
                let r = Rig(fullAccess: false, dark: true, appear: false)
                defer { r.close() }
                XCTAssertFalse(r.snapshotShown)
                XCTAssertFalse(r.vc.debugKeyboard.initialBuildPending, "dựng ở khung đầu như cũ")
                XCTAssertNotNil(r.vc.debugKeyboard.debugLetterFrame("a"))
            }
        }
    }

    /// VoiceOver ⇒ không dùng ảnh, không chụp. Công tắc tắt (biên dịch/test hoặc defaults) ⇒ đường cũ.
    @MainActor func testSnapshotSkippedForVoiceOverAndKillSwitch() throws {
        try withDefaults(rich: false) {
            try withSnapshot(dir: "vt-keysnap-test") {
                _ = try prime()
                KeySnapshot.debugVoiceOver = true
                let r1 = Rig(fullAccess: false)
                XCTAssertFalse(r1.snapshotShown, "VoiceOver: khung đầu là phím thật")
                XCTAssertFalse(r1.vc.debugKeyboard.captureSnapshotIfNeeded(), "VoiceOver: không chụp")
                r1.close()
                KeySnapshot.debugVoiceOver = nil
                UserDefaultsProvider.shared?.set(true, forKey: KeySnapshot.disableKey)
                let r2 = Rig(fullAccess: false)
                XCTAssertFalse(r2.snapshotShown, "công tắc defaults tắt")
                r2.close()
                UserDefaultsProvider.shared?.removeObject(forKey: KeySnapshot.disableKey)
                KeySnapshot.debugEnabled = false
                let r3 = Rig(fullAccess: false)
                XCTAssertFalse(r3.snapshotShown, "công tắc tắt")
                XCTAssertFalse(r3.vc.debugKeyboard.captureSnapshotIfNeeded())
                r3.close()
                KeySnapshot.debugEnabled = true
                let r4 = Rig(fullAccess: false)
                XCTAssertTrue(r4.snapshotShown, "bật lại ⇒ dùng ảnh")
                r4.close()
            }
        }
    }

    /// Đã chạm từ lúc hiện ⇒ không chụp (ảnh chỉ là trạng thái mở đầu, không có phím đang đè).
    @MainActor func testSnapshotNotCapturedAfterInteraction() throws {
        try withDefaults(rich: false) {
            try withSnapshot(dir: "vt-keysnap-test") {
                let r = Rig(fullAccess: false)
                defer { r.close() }
                let kb = r.vc.debugKeyboard
                let f = try XCTUnwrap(kb.debugLetterFrame("a"))
                kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime())
                XCTAssertFalse(kb.captureSnapshotIfNeeded())
                XCTAssertNil(KeySnapshot.Store.current())
            }
        }
    }

    // MARK: đo — lạnh CÓ ảnh cần tiến trình mới: chạy mỗi test HAI lần (-only-testing), lượt đầu chụp.

    @MainActor private func runSnapshotStartup(_ tag: String, rich: Bool, dark: Bool) {
        withDefaults(rich: rich) {
            withSnapshot(dir: "vt-keysnap-bench-\(tag)", keep: true) {
                let primed = KeySnapshot.Store.current() != nil
                KeySnapshot.Store.resetListing()   // liệt kê thư mục tính vào khung đầu như máy thật
                StartupTrace.reset()
                let cold = Rig(fullAccess: rich, dark: dark)
                report("snap-\(tag) cold primed=\(primed ? 1 : 0)", cold)
                if !cold.snapshotShown {   // chưa có / ảnh cũ (bản build khác) ⇒ chụp cho lượt sau
                    KeySnapshot.Store.clear()
                    _ = capture(cold)
                }
                Self.spin(0.3)
                cold.close()
                Self.spin(0.2)
                for i in 0..<5 {
                    StartupTrace.reset()
                    let r = Rig(fullAccess: rich, dark: dark)
                    if i == 4 { report("snap-\(tag) warm", r) }
                    Self.spin(0.3)
                    r.close()
                }
                StartupTrace.recording = nil
            }
        }
    }

    @MainActor func testTimeToFirstFrameSnapshotDefault() { runSnapshotStartup("default", rich: false, dark: false) }
    @MainActor func testTimeToFirstFrameSnapshotDark() { runSnapshotStartup("dark", rich: false, dark: true) }
    @MainActor func testTimeToFirstFrameSnapshotRich() { runSnapshotStartup("rich", rich: true, dark: false) }
}
