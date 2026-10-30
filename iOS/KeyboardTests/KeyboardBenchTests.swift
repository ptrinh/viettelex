import XCTest
import UIKit

/// Bench đường nóng mỗi phím qua controller THẬT (KeyboardView router → KeyboardViewController
/// → EngineBridge → proxy giả → gợi ý nền → auto-shift), cùng RAM / CPU / thời gian mở.
/// Bộ CHẬM (VT_SLOW_TESTS=1). Cấu hình qua VT_BENCH_CONFIG = B (mặc định) | C (mọi tính năng
/// phụ tắt) | D (mọi tính năng bật). Số in ra dòng "BENCH …" để so A/B/C/D (docs/ios-app.md).
///
/// Giới hạn: chạy trong process test (không phải process extension thật) — proxy giả không có
/// chi phí IPC của host, RAM là PHẦN TĂNG so với process test trước khi dựng bàn phím,
/// hasFullAccess = false (nút Dán / clipboard / rung không chạy).
final class KeyboardBenchTests: XCTestCase {

    // MARK: proxy giả (đếm lệnh — thay cho số IPC)

    final class BenchProxy: NSObject, UITextDocumentProxy {
        var text = ""
        var contextReads = 0, inserts = 0, deletes = 0
        /// Lượt đọc trait ô (keyboardType — mỗi lượt refreshFieldTraits đọc đúng một lần) / selectedText.
        var traitReads = 0, selectionReads = 0
        var callers: [String: Int] = [:]
        var documentContextBeforeInput: String? {
            contextReads += 1
            if ProcessInfo.processInfo.environment["VT_BENCH_TRACE"] == "1" {
                let st = Thread.callStackSymbols.dropFirst(2).prefix(3).map { String($0.split(separator: " ").dropFirst(3).first ?? "") }.joined(separator: " < ")
                callers[st, default: 0] += 1
            }
            return String(text.suffix(256))
        }
        var documentContextAfterInput: String? { contextReads += 1; return "" }
        var selectedText: String? { selectionReads += 1; return nil }
        var documentInputMode: UITextInputMode? { nil }
        var documentIdentifier: UUID = UUID()
        func adjustTextPosition(byCharacterOffset offset: Int) {}
        func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
        func unmarkText() {}
        var hasText: Bool { !text.isEmpty }
        /// Từng chuỗi insertText theo thứ tự (LineBreakTests: newline phải đi kèm chữ trong một lệnh).
        var insertLog: [String] = []
        func insertText(_ s: String) { inserts += 1; insertLog.append(s); text += s }
        func deleteBackward() { deletes += 1; if !text.isEmpty { text.removeLast() } }
        var autocapitalizationType: UITextAutocapitalizationType = .sentences
        private var _keyboardType: UIKeyboardType = .default
        var keyboardType: UIKeyboardType {
            get { traitReads += 1; return _keyboardType }
            set { _keyboardType = newValue }
        }
        var returnKeyType: UIReturnKeyType = .default
        var keyboardAppearance: UIKeyboardAppearance = .default
        var autocorrectionType: UITextAutocorrectionType = .default
    }

    // MARK: cấu hình

    static var config: String { ProcessInfo.processInfo.environment["VT_BENCH_CONFIG"] ?? "B" }

    /// Cấu hình vào suite riêng (UserDefaultsProvider) — không đụng App Group thật.
    static func makeDefaults(_ config: String) -> UserDefaults {
        let name = "vt-bench-\(config)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        switch config {
        case "C":
            for k in ["showSuggestions", "smartTouch", "swipeTyping", "reEditWord", "autoFixAdjacent",
                      "contextualEnglish", "shortcutsEnabled", "templatesEnabled", "clipboardHistory",
                      "numberChips", "mathResults", "emojiSuggest", "pasteButton", "addTonesChip", "hapticFeedback"] {
                d.set(false, forKey: k)
            }
        case "D":
            for k in ["showSuggestions", "smartTouch", "swipeTyping", "swipeEnglish", "reEditWord",
                      "autoFixAdjacent", "contextualEnglish", "shortcutsEnabled", "templatesEnabled",
                      "clipboardHistory", "numberChips", "mathResults", "emojiSuggest", "pasteButton", "addTonesChip",
                      "hapticFeedback", "numberRow", "teencode", "wallpaperEnabled"] {
                d.set(true, forKey: k)
            }
            d.set("peach", forKey: "keyboardTheme")
            d.set(["ko": "không", "dc": "được", "vn": "Việt Nam"], forKey: "shortcuts")
        default: break
        }
        // Hiệu ứng khi bấm phím (Plus): VT_BENCH_EFFECT=heart|bubble|ripple|petal|firework — A/B với cùng cfg.
        if let e = ProcessInfo.processInfo.environment["VT_BENCH_EFFECT"], KeyEffect(rawValue: e) != nil {
            d.set(e, forKey: KeyEffect.key)
            PlusGate.paywallEnabled = false
        }
        // Tách chi phí từng tính năng: VT_BENCH_OFF=smartTouch,showSuggestions (tắt thêm).
        for k in (ProcessInfo.processInfo.environment["VT_BENCH_OFF"] ?? "").split(separator: ",") {
            d.set(false, forKey: String(k))
        }
        return d
    }

    // MARK: đo

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<Int32>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// CPU (user+sys) cả process, giây — gồm hàng đợi gợi ý nền.
    static func processCPU() -> Double {
        var r = rusage()
        getrusage(RUSAGE_SELF, &r)
        return Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec)
            + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6
    }

    /// CPU của main thread, giây.
    static func mainThreadCPU() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.user_time.seconds + info.system_time.seconds)
            + Double(info.user_time.microseconds + info.system_time.microseconds) / 1e6
    }

    static func pct(_ xs: [Double], _ p: Double) -> Double {
        let s = xs.sorted()
        guard !s.isEmpty else { return 0 }
        return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
    }

    static func spin(_ sec: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(sec)) }

    /// Telex thường ngày (chữ + dấu cách); ⌫ mỗi 25 phím.
    static let corpus = "xin chaof moij nguowif hoom nay tooi ddi lamf vieecj owr coong ty mowis "
        + "vaf gawpj nhieeuf ddoongf nghieepj raats vui veer chungs tooi cungf nhau baanf veef "
        + "keees hoachj sanr phaamr cho nawm sau "
    /// Nặng phím dấu (s/f/r/x/j + đổi dấu giữa chừng) — VT_BENCH_CORPUS=tones.
    static let toneCorpus = "vieejt tooi ddi hocj cas caf car cax caj vieejt nam tieengs vieetj "
        + "tooi ddi hocj thaatj chawm chir ddaayf nguowif ddepj quas hoir nhuwngx caau hoir "
        + "casf carx vieejts hoocj muoons ddeens tuowngr nhieeuf "
    static var activeCorpus: String {
        ProcessInfo.processInfo.environment["VT_BENCH_CORPUS"] == "tones" ? toneCorpus : corpus
    }
    /// Phím dấu Telex (đo riêng p50/p95 chỉ những phím này).
    static let toneKeys: Set<Character> = ["s", "f", "r", "x", "j"]

    @MainActor final class Rig {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let vc = KeyboardViewController()
        let proxy = BenchProxy()
        var openMs = 0.0

        init() {
            win.isHidden = false
            vc.debugProxy = proxy
            let t0 = CACurrentMediaTime()
            vc.loadViewIfNeeded()
            vc.view.frame = CGRect(x: 0, y: 874 - 290, width: 402, height: 290)
            win.addSubview(vc.view)
            vc.beginAppearanceTransition(true, animated: false)
            vc.view.layoutIfNeeded()
            vc.endAppearanceTransition()
            vc.view.layoutIfNeeded()
            openMs = (CACurrentMediaTime() - t0) * 1000
        }

        func close() {
            vc.beginAppearanceTransition(false, animated: false)
            vc.endAppearanceTransition()
            vc.view.removeFromSuperview()
            win.isHidden = true
        }

        /// Một phím: (thời gian đồng bộ ms, CPU main gồm việc hoãn ms).
        func key(_ c: Character, index: Int, drain: TimeInterval) -> (sync: Double, mainCPU: Double) {
            let kb = vc.debugKeyboard
            let c0 = mainThreadCPU()
            let t0 = CACurrentMediaTime()
            if index > 0, index % 25 == 0 {
                _ = kb.debugBackspaceSwipe(from: 0, through: [])
            } else if c == " " {
                kb.benchSpace()
            } else if let f = kb.debugLetterFrame(String(c)) {
                kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: t0)
            }
            let t1 = CACurrentMediaTime()
            spin(drain)
            return ((t1 - t0) * 1000, (mainThreadCPU() - c0) * 1000)
        }
    }

    @MainActor func testHotPathBench() throws {
        try SlowTests.require()
        let cfg = Self.config
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = Self.makeDefaults(cfg)
        defer { UserDefaultsProvider.shared = saved }
        let idleSec = Double(ProcessInfo.processInfo.environment["VT_BENCH_IDLE"] ?? "") ?? 60
        let drain = 0.05

        // Sàn nhiễu: CPU process khi chỉ quay runloop (XCTest + runloop), cùng nhịp phím.
        Self.spin(0.5)
        let memBase = Self.footprintMB()
        let n0 = Self.processCPU()
        for _ in 0..<100 { Self.spin(drain) }
        let noisePer100 = (Self.processCPU() - n0) * 1000

        // Mở bàn phím: lần đầu (lạnh trong process) + 5 lần ấm.
        let rig = Rig()
        let coldOpen = rig.openMs
        var warm: [Double] = []
        for _ in 0..<5 { let r = Rig(); warm.append(r.openMs); r.close() }
        Self.spin(0.5)
        let memOpen = Self.footprintMB()

        // Làm nóng (nạp lười) rồi đo.
        let keys = Array(Self.activeCorpus)
        for (i, c) in keys.enumerated() { _ = rig.key(c, index: i, drain: 0.01) }
        Self.spin(1)
        rig.proxy.contextReads = 0; rig.proxy.inserts = 0; rig.proxy.deletes = 0
        var sync: [Double] = [], mainCPU: [Double] = [], toneSync: [Double] = [], toneMain: [Double] = []
        let p0 = Self.processCPU()
        var n = 0
        for _ in 0..<2 {
            for (i, c) in keys.enumerated() {
                let r = rig.key(c, index: i, drain: drain)
                sync.append(r.sync); mainCPU.append(r.mainCPU); n += 1
                if Self.toneKeys.contains(c), i % 25 != 0 || i == 0 { toneSync.append(r.sync); toneMain.append(r.mainCPU) }
            }
        }
        let cpuPer100 = (Self.processCPU() - p0) * 1000 / Double(n) * 100
        let memTyped = Self.footprintMB()

        // Idle: không gõ gì — phải ~ sàn (không timer / display link).
        Self.spin(1)
        let i0 = Self.processCPU(), m0 = Self.mainThreadCPU()
        Self.spin(idleSec)
        let idleCPU = (Self.processCPU() - i0) * 1000
        let idleMain = (Self.mainThreadCPU() - m0) * 1000

        let line = String(format: "BENCH cfg=%@ effect=\(rig.vc.debugKeyboard.keyEffects?.effect.rawValue ?? "none") keys=%d sync_p50=%.3f sync_p95=%.3f sync_p99=%.3f "
            + "main_p50=%.3f main_p95=%.3f main_p99=%.3f cpu100=%.1f noise100=%.1f "
            + "open_cold=%.1f open_warm=%.1f mem_base=%.1f mem_open=%.1f mem_typed=%.1f "
            + "idle%.0fs_cpu=%.1f idle_main=%.1f ctx_per_key=%.2f ins_per_key=%.2f del_per_key=%.2f",
            cfg, n, Self.pct(sync, 0.5), Self.pct(sync, 0.95), Self.pct(sync, 0.99),
            Self.pct(mainCPU, 0.5), Self.pct(mainCPU, 0.95), Self.pct(mainCPU, 0.99),
            cpuPer100, noisePer100, coldOpen, Self.pct(warm, 0.5),
            memBase, memOpen, memTyped, idleSec, idleCPU, idleMain,
            Double(rig.proxy.contextReads) / Double(n), Double(rig.proxy.inserts) / Double(n),
            Double(rig.proxy.deletes) / Double(n))
        print(line)
        print(String(format: "BENCH tone_keys=%d tone_sync_p50=%.3f tone_sync_p95=%.3f tone_main_p50=%.3f tone_main_p95=%.3f",
                     toneSync.count, Self.pct(toneSync, 0.5), Self.pct(toneSync, 0.95),
                     Self.pct(toneMain, 0.5), Self.pct(toneMain, 0.95)))
        for (k, v) in rig.proxy.callers.sorted(by: { $0.value > $1.value }).prefix(8) { print("BENCH caller \(v) \(k)") }
        XCTContext.runActivity(named: line) { _ in }
        rig.close()

        // Ngưỡng hồi quy RỘNG (simulator dao động): phím không được chậm cỡ mili-giây,
        // bàn phím không được thêm quá 25MB vào process, idle không được đốt CPU.
        XCTAssertLessThan(Self.pct(sync, 0.95), 4.0, "độ trễ đồng bộ p95 (ms)")
        XCTAssertLessThan(memTyped - memBase, 25, "RAM tăng do bàn phím (MB)")
        XCTAssertLessThan(idleMain, 30 * idleSec / 60, "CPU main khi idle (ms)")
    }
}
