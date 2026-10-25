// StartupTrace — đo thời gian hiện bàn phím theo từng bước (viewDidLoad → viewWillAppear →
// layout đầu → viewDidAppear). Hai đầu ra:
//  • os_signpost (Instruments → "Points of Interest"/os_signpost, subsystem
//    com.viettelex.ios.keyboard, category "startup"): chạy cả Release, chi phí ~0 khi không
//    có Instruments ghi (OSSignposter tự kiểm tra isEnabled).
//  • DEBUG: `recording` != nil ⇒ cộng dồn ms theo tên bước (test/harness đọc lại — KeyboardStartupTests).
import Foundation
import os
import QuartzCore
import UIKit

enum StartupTrace {
    static let signposter = OSSignposter(subsystem: "com.viettelex.ios.keyboard", category: "startup")

    /// Một bước đồng bộ trên main: signpost interval + (DEBUG) cộng dồn vào `recording`.
    @inline(__always)
    static func span<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        #if DEBUG
        guard recording != nil || signposter.isEnabled else { return try body() }
        let t0 = CACurrentMediaTime()
        let state = signposter.beginInterval(name)
        defer {
            signposter.endInterval(name, state)
            add("\(name)", (CACurrentMediaTime() - t0) * 1000)
        }
        return try body()
        #else
        guard signposter.isEnabled else { return try body() }
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
        #endif
    }

    /// Mốc đơn (vd "firstLayout", "deferredDone").
    static func event(_ name: StaticString) {
        if signposter.isEnabled { signposter.emitEvent(name) }
        #if DEBUG
        if recording != nil { add("\(name)#", 0) }
        #endif
    }

    #if DEBUG
    /// Test bật bằng `recording = [:]`; nil = tắt (mặc định).
    nonisolated(unsafe) static var recording: [String: Double]?
    nonisolated(unsafe) static var counts: [String: Int] = [:]
    private static func add(_ name: String, _ ms: Double) {
        guard Thread.isMainThread, recording != nil else { return }
        recording![name, default: 0] += ms
        counts[name, default: 0] += 1
    }
    static func reset() { recording = [:]; counts = [:] }
    #endif
}

/// Việc KHÔNG cần cho khung hình đầu (gợi ý mở đầu, model cá nhân, báo trạng thái App Group,
/// nạp Thay thế văn bản…) — chạy NGAY SAU khi khung đầu đã commit: observer beforeWaiting của
/// runloop main, order sau observer commit của Core Animation (2_000_000), rồi main.async (đánh
/// thức runloop ⇒ thay đổi UI của việc hoãn được commit ở lượt kế, không nằm chờ sự kiện).
/// Phím gõ trước khi việc hoãn chạy vẫn đúng: mọi thứ hoãn đều có đường nạp lười khi cần.
final class PostFrameWork {
    private var pending: [() -> Void] = []
    private var observer: CFRunLoopObserver?
    private var dispatched = false
    private(set) var generation = 0
    var isPending: Bool { !pending.isEmpty }

    /// Order của observer: ngay SAU commit của Core Animation (kCATransactionCommitOrder 2_000_000).
    static let observerOrder: CFIndex = 2_000_001

    deinit { if let o = observer { CFRunLoopObserverInvalidate(o) } }

    func schedule(_ work: @escaping () -> Void) {
        pending.append(work)
        guard observer == nil, !dispatched else { return }
        let o = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue,
            false, Self.observerOrder) { [weak self] _, _ in self?.frameCommitted() }
        CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
        observer = o
    }

    private func frameCommitted() {
        removeObserver()
        guard !pending.isEmpty, !dispatched else { return }
        dispatched = true
        let gen = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == gen else { return }
            self.flush()
        }
    }

    /// Chạy ngay mọi việc còn chờ (viewDidAppear: chắc chắn xong trước khi bàn phím hiện hẳn).
    func flush() {
        removeObserver()
        dispatched = false
        generation += 1
        let w = pending
        pending = []
        StartupTrace.span("postFrame") { w.forEach { $0() } }
    }

    /// Bàn phím ẩn / xé trước khi kịp chạy: bỏ hết.
    func cancel() {
        removeObserver()
        dispatched = false
        generation += 1
        pending = []
    }

    private func removeObserver() {
        if let o = observer { CFRunLoopObserverInvalidate(o); observer = nil }
    }
}

/// Nạp NỀN (song song main) thứ UIKit nạp lần đầu khi dựng phím: catalog SF Symbols + glyph
/// các icon phím (⇧ ⌫ 🌐 ↵ 😊…), phông SF Compact/Pro, logo phím cách. Cache toàn cục của
/// UIKit/CoreText ⇒ main gặp cache nóng (hoặc chờ khoá — không chậm hơn tự nạp). Một lần/process.
enum StartupPrewarm {
    private static let once: Void = {
        DispatchQueue.global(qos: .userInteractive).async { run() }
    }()
    static func start() { _ = once }

    static let symbols = ["shift", "shift.fill", "capslock.fill", "delete.left", "delete.left.fill",
                          "globe", "face.smiling", "return.left", "arrow.right", "line.3.horizontal",
                          "keyboard.onehanded.left", "keyboard.onehanded.right", "doc.on.clipboard"]

    static func run() {
        StartupTrace.signposter.withIntervalSignpost("prewarm") {
            for s in symbols { _ = UIImage(systemName: s) }
            let design = UIFontDescriptor.SystemDesign(rawValue: "NSCTFontUIFontDesignCompact")
            for size in [CGFloat(16), 17, 22, 25] {
                let f = UIFont.systemFont(ofSize: size)
                if let d = f.fontDescriptor.withDesign(design) { _ = UIFont(descriptor: d, size: size) }
            }
            _ = UIFont.systemFont(ofSize: 14, weight: .regular)
            _ = UIImage(named: "SpaceLogo")
        }
    }
}
