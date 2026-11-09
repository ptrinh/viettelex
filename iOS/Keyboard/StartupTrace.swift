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
import CryptoKit

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

/// Khoảng thời gian "tới khung hình": mở ngay, đóng ở observer chạy NGAY SAU commit Core
/// Animation của lượt runloop hiện tại (cùng order với PostFrameWork) — tức lúc cây layer đã
/// gửi cho render server. Không gồm phần render server / màn hình (xem iOS/docs/KEYBOARD-STARTUP.md).
///
/// Category `.dynamicTracing`: signpost TẮT mặc định, chỉ bật khi Instruments / xctrace đang
/// ghi ⇒ khi không ghi, mỗi lời gọi chỉ là một lần đọc cờ `isEnabled` (không observer, không
/// cấp phát) — dùng được ở đường mỗi phím.
///
/// Khoảng (tên trong Instruments → os_signpost, subsystem com.viettelex.ios.keyboard):
///  • `appear`  — init controller (hoặc viewWillAppear khi CÙNG controller hiện lại) → commit
///    của khung đầu có phím (bounds > 0). Thông điệp mở: "cold" (controller đầu tiên của process)
///    / "warm" / "reshow"; thông điệp đóng: kích thước view lúc đó.
///  • `key`     — controller nhận phím (handle) → commit khung có kết quả phím đó.
///  • `plane`   — đổi mặt phím (chữ/123/#+=/emoji…) → commit.
/// Mốc (event): `vc.init`, `viewDidLoad`, `viewWillAppear`, `didLayout`, `viewDidAppear`,
/// `height` (mỗi lần chiều cao view gốc đổi — thấy chuỗi 0 → … → chiều cao cuối của host).
enum FrameTrace {
    static let signposter = OSSignposter(logHandle: OSLog(subsystem: "com.viettelex.ios.keyboard",
                                                          category: .dynamicTracing))
    @inline(__always) static var isEnabled: Bool { signposter.isEnabled }

    /// Khoảng đang chờ commit (main thread).
    nonisolated(unsafe) private static var open: [(name: StaticString, state: OSSignpostIntervalState)] = []
    nonisolated(unsafe) private static var observer: CFRunLoopObserver?

    /// Mở khoảng `name` và đóng nó ở commit kế tiếp. Không ghi ⇒ no-op.
    @inline(__always)
    static func untilCommit(_ name: StaticString) {
        guard signposter.isEnabled else { return }
        endAtCommit(name, signposter.beginInterval(name, id: signposter.makeSignpostID()))
    }

    /// Đóng khoảng đã mở ở commit kế tiếp (main thread).
    static func endAtCommit(_ name: StaticString, _ state: OSSignpostIntervalState) {
        open.append((name, state))
        guard observer == nil else { return }
        let o = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue,
            false, PostFrameWork.observerOrder) { _, _ in committed() }
        CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
        observer = o
    }

    private static func committed() {
        if let o = observer { CFRunLoopObserverInvalidate(o); observer = nil }
        let done = open
        open = []
        for (name, state) in done { signposter.endInterval(name, state) }
    }

    @inline(__always)
    static func event(_ name: StaticString) {
        if signposter.isEnabled { signposter.emitEvent(name) }
    }

    /// Số controller đã tạo trong process (cold = 1).
    nonisolated(unsafe) static var controllersCreated = 0
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

// MARK: - Ảnh lưới phím cho khung đầu (KeySnapshot) — docs/KEYBOARD-STARTUP.md §6

/// Lần hiện trước (đã yên, chưa chạm) chụp ảnh VÙNG PHÍM — chỉ `rowsContainer` của KeyboardView:
/// không thanh gợi ý, không panel clipboard, không plane emoji / mẫu câu (có nội dung người dùng)
/// — rồi ghi NỀN vào Caches của extension, chỉ khi khoá đổi. Lần mở sau: khoá khớp CHÍNH XÁC
/// trạng thái sắp hiện ⇒ khung đầu chỉ đặt ảnh làm nội dung một CALayer (không dựng ~40 phím),
/// phím thật dựng ngay sau commit khung đầu (PostFrameWork) rồi bỏ ảnh. Không khớp / tắt /
/// VoiceOver ⇒ đường cũ y nguyên.
///
/// Kho đặt ở Caches RIÊNG của extension, không App Group: thiếu Toàn quyền thì iOS chặn ghi
/// App Group (xem reportStatusToApp) — tính năng sẽ không bao giờ có ảnh với người chưa cấp quyền.
enum KeySnapshot {
    /// Công tắc biên dịch (tắt nhanh): false ⇒ đường cũ, không liệt kê thư mục, không chụp.
    static let compiledOn = true
    /// Công tắc chạy (defaults bàn phím / App Group, không có giao diện): true ⇒ tắt.
    static let disableKey = "keySnapshotOff"
    /// Chụp sau viewDidAppear bấy lâu: bàn phím đã trượt xong, nhãn "ViệtTelex" trên phím cách
    /// đã mờ (0,7 + 0,3 s tính từ lúc hiện).
    static let captureDelay: TimeInterval = 1.2
    /// Trần điểm ảnh (~16 MB BGRA) — vượt (iPad lớn lạ) ⇒ không chụp.
    static let maxPixels = 4_000_000
    static let schema = "ks1"

    #if DEBUG
    /// Test: ép bật/tắt (nil = mặc định: TẮT khi chạy trong XCTest — không lẫn sang test khác).
    nonisolated(unsafe) static var debugEnabled: Bool?
    /// Test: giả VoiceOver.
    nonisolated(unsafe) static var debugVoiceOver: Bool?
    #endif

    static var featureOn: Bool {
        guard compiledOn else { return false }
        #if DEBUG
        if let e = debugEnabled { return e }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #endif
        return true
    }

    /// VoiceOver bật ⇒ không dùng ảnh (khung đầu chưa có phần tử a11y nào) và không chụp.
    static var voiceOverRunning: Bool {
        #if DEBUG
        if let v = debugVoiceOver { return v }
        #endif
        return UIAccessibility.isVoiceOverRunning
    }

    /// Phiên bản build — đổi bản là đổi khoá (cách vẽ phím có thể đã khác).
    static let buildVersion: String = {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] ?? "?")(\(i?["CFBundleVersion"] ?? "?"))"
    }()

    /// Một ảnh đã lưu: khoá trạng thái + khoá khung vùng phím + cỡ điểm ảnh (nằm trong tên tệp
    /// ⇒ quyết định khỏi đọc tệp, chỉ liệt kê thư mục một lần mỗi tiến trình).
    struct Entry: Equatable {
        let hash: String
        let frame: String
        let pixelWidth: Int
        let pixelHeight: Int
        var byteCount: Int { pixelWidth * pixelHeight * 4 }
        var fileName: String { "keysnap-\(hash)-\(frame)-\(pixelWidth)x\(pixelHeight).bgra" }

        static func parse(_ name: String) -> Entry? {
            guard name.hasPrefix("keysnap-"), name.hasSuffix(".bgra") else { return nil }
            let core = name.dropFirst("keysnap-".count).dropLast(".bgra".count)
            let p = core.split(separator: "-", omittingEmptySubsequences: false)
            guard p.count == 3, isHex(p[0]), isHex(p[1]) else { return nil }
            let wh = p[2].split(separator: "x", omittingEmptySubsequences: false)
            guard wh.count == 2, let w = Int(wh[0]), let h = Int(wh[1]), w > 0, h > 0,
                  w * h <= KeySnapshot.maxPixels else { return nil }
            return Entry(hash: String(p[0]), frame: String(p[1]), pixelWidth: w, pixelHeight: h)
        }
        private static func isHex(_ s: Substring) -> Bool {
            !s.isEmpty && s.allSatisfy { $0.isHexDigit && !$0.isUppercase }
        }
    }

    /// Theme / kiểu phím có cho dùng ảnh tĩnh không (thuần). Ảnh lần trước phải TRÙNG hình lúc mở:
    ///  • phím tự chuyển động ("keyMotion" bất kỳ, hiệu ứng "float" — Lạc trôi…) ⇒ không;
    ///  • lớp phủ cần chính view phím (đập chuột) ⇒ không. Viền cầu vồng / cực quang / Ảo giác và hoạ
    ///    tiết / cảnh nền giữa hàng dùng khung phím LƯU KÈM ảnh ⇒ được;
    ///  • bảng màu đổi theo giờ (Theo giờ) KHÔNG cần chặn: bảng màu nằm trong khoá (paletteKey) ⇒ giờ
    ///    khác bảng ⇒ khoá khác ⇒ dựng như cũ. Skin có animation đang chạy thì không bao giờ được chụp
    ///    (snapshotUnstable) ⇒ không có ảnh để dùng.
    ///  • phím phụ thuộc nội dung phía sau (kính "keyShape":"glass", làm mờ) ⇒ không.
    /// Ảnh CHỈ là mặt phím trên nền trong suốt (rowsContainer — nền theme, ảnh nền, đèn, cá, sóng, bạn
    /// đồng hành, hiệu ứng bấm, viền cầu vồng / cực quang / Ảo giác đều là lớp anh em, dựng sống như cũ)
    /// ⇒ chúng không chặn.
    static func themeAllows(keyMotion: String?, keyShape: String?, floatActive: Bool, keyFrameOverlays: Bool) -> Bool {
        keyMotion == nil && keyShape != GlassKeys.shape && !floatActive && !keyFrameOverlays
    }

    /// Số trường lưu của KeyboardPalette mà `paletteKey` liệt kê — test đếm bằng Mirror: thêm
    /// trường vào bảng màu mà quên thêm ở đây ⇒ đỏ (khoá thiếu trường ⇒ ảnh cũ có thể hiện sai màu).
    static let paletteFieldCount = 26

    static func rgbaKey(_ c: RGBA?) -> String { c.map { "\($0.r),\($0.g),\($0.b),\($0.a)" } ?? "-" }

    /// Dấu vân tay bảng màu — liệt kê TAY (không Mirror: tất định giữa tiến trình và rẻ lúc lạnh).
    static func paletteKey(_ p: KeyboardPalette) -> String {
        func b(_ v: Bool) -> String { v ? "1" : "0" }
        return [rgbaKey(p.background), rgbaKey(p.background2), rgbaKey(p.keyFill), rgbaKey(p.specialFill),
                rgbaKey(p.ink), rgbaKey(p.trail), rgbaKey(p.barInk), rgbaKey(p.balloon), rgbaKey(p.accent),
                rgbaKey(p.accentInk), rgbaKey(p.keyBorder), b(p.isDark), rgbaKey(p.keyLabel), "\(p.surfaceAlpha)",
                b(p.keyLabelPinned), p.surfaceDark.map(b) ?? "-", rgbaKey(p.functionFill), rgbaKey(p.functionInk),
                p.decoration == nil ? "-" : "deco", b(p.rainbowBorder), b(p.auroraBorder), b(p.hueFlow),
                b(p.spaceSoundhole), p.cornerGlyph ?? "-",
                p.auroraColors.map { $0.map { String($0) }.joined(separator: ".") } ?? "-",
                b(p.accentShift)].joined(separator: "|")
    }

    /// SHA-256 hex (chữ thường) của các phần, cắt `length` ký tự.
    static func digest(_ parts: [String], length: Int = 32) -> String {
        let d = SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
        return String(d.map { String(format: "%02x", $0) }.joined().prefix(length))
    }

    /// Khoá khung vùng phím: cỡ chính xác + phần lẻ điểm ảnh của gốc (lưới làm tròn mép phím
    /// theo toạ độ chính xác — lệch phần lẻ là lệch mép một điểm ảnh) + scale; 1/64 điểm ảnh.
    static func frameKey(exact: CGRect, scale: CGFloat) -> String {
        func q(_ v: CGFloat) -> Int { Int((v * scale * 64).rounded()) }
        func frac(_ v: CGFloat) -> Int { let p = v * scale; return Int(((p - p.rounded(.down)) * 64).rounded()) }
        return digest(["\(q(exact.width))", "\(q(exact.height))", "\(frac(exact.minX))", "\(frac(exact.minY))",
                       "\(scale)"], length: 16)
    }

    /// Cỡ điểm ảnh của vùng phím (khung đã làm tròn theo điểm ảnh).
    static func pixelSize(_ size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((size.width * scale).rounded()), Int((size.height * scale).rounded()))
    }

    /// Quyết định ở khung đầu.
    enum Use: Equatable {
        /// Đường cũ: dựng phím ngay.
        case build
        /// Có ảnh cùng khoá trạng thái nhưng chưa biết khung (vùng phím 0) — hoãn dựng tới lượt
        /// layout có cỡ.
        case pending
        /// Hiện ảnh này; phím thật dựng sau commit khung đầu.
        case show(Entry)
    }

    /// `frame` nil = vùng phím chưa có cỡ. Mọi điều kiện phải đúng mới dùng ảnh; thiếu một ⇒ dựng.
    static func decide(enabled: Bool, voiceOver: Bool, eligible: Bool, stored: Entry?,
                       hash: String, frame: String?, pixelSize: (width: Int, height: Int)? = nil) -> Use {
        guard enabled, !voiceOver, eligible, let s = stored, s.hash == hash else { return .build }
        guard let frame else { return .pending }
        guard s.frame == frame else { return .build }
        if let p = pixelSize, p.width != s.pixelWidth || p.height != s.pixelHeight { return .build }
        return .show(s)
    }

    /// Chụp khi: bật, không VoiceOver, lưới đủ điều kiện (plane chữ/số/ký hiệu, không lớp phủ
    /// bám khung phím), CHƯA có chạm nào từ lúc hiện (trạng thái mở đầu, không phím đang đè),
    /// không đang hiện ảnh, phím thật đã dựng, không layer nào đang chạy animation / không chụp
    /// được, và khác ảnh đang lưu.
    static func shouldCapture(enabled: Bool, voiceOver: Bool, eligible: Bool, interacted: Bool,
                              showing: Bool, keysBuilt: Bool, unstable: Bool,
                              stored: Entry?, entry: Entry) -> Bool {
        enabled && !voiceOver && eligible && !interacted && !showing && keysBuilt && !unstable
            && entry.pixelWidth * entry.pixelHeight <= maxPixels && stored != entry
    }

    /// Kho MỘT ảnh (tệp BGRA thô — mmap, khỏi giải mã PNG ở khung đầu). Trạng thái chỉ đọc/ghi
    /// trên main; ghi tệp trên `queue`.
    enum Store {
        static let queue = DispatchQueue(label: "com.viettelex.keysnap", qos: .utility)
        #if DEBUG
        /// Test: thư mục riêng (đặt rồi gọi `resetListing`).
        nonisolated(unsafe) static var debugDirectory: URL?
        #endif
        static var directory: URL? {
            #if DEBUG
            if let d = debugDirectory { return d }
            #endif
            return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("KeySnapshot", isDirectory: true)
        }
        nonisolated(unsafe) private static var listed = false
        nonisolated(unsafe) private static var entry: Entry?
        nonisolated(unsafe) private(set) static var saving = false

        /// Ảnh đang lưu (liệt kê thư mục MỘT lần mỗi tiến trình).
        static func current() -> Entry? {
            if !listed {
                listed = true
                entry = directory.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) }?
                    .compactMap(Entry.parse).first
            }
            return entry
        }

        static func resetListing() { listed = false; entry = nil }

        static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                             | CGBitmapInfo.byteOrder32Little.rawValue)

        /// mmap tệp ⇒ CGImage (không giải mã; trang đọc khi Core Animation chép ở commit) + khung
        /// từng phím (đuôi tệp — viền cầu vồng / cực quang vẽ đúng chỗ ngay khung đầu, trên ảnh).
        static func load(_ e: Entry) -> (image: CGImage, outlines: [Outline])? {
            guard let dir = directory,
                  let data = try? NSData(contentsOf: dir.appendingPathComponent(e.fileName), options: .alwaysMapped),
                  data.length >= e.byteCount,
                  let outlines = decodeOutlines(data, from: e.byteCount),
                  let provider = CGDataProvider(data: data as CFData),
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let image = CGImage(width: e.pixelWidth, height: e.pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: e.pixelWidth * 4, space: space, bitmapInfo: bitmapInfo,
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            else { entry = nil; return nil }   // tệp mất / hỏng ⇒ coi như chưa có
            return (image, outlines)
        }

        /// Khung một phím trong vùng phím (toạ độ rowsContainer) + bo góc.
        struct Outline: Equatable {
            var rect: CGRect
            var radius: CGFloat
        }

        /// Đuôi tệp: Float32 LE × (1 + 5n) = n, rồi x y w h r mỗi phím. Thiếu đuôi (n = 0) hợp lệ.
        static func encodeOutlines(_ o: [Outline]) -> Data {
            var f: [Float32] = [Float32(o.count)]
            for k in o { f += [Float32(k.rect.minX), Float32(k.rect.minY), Float32(k.rect.width),
                               Float32(k.rect.height), Float32(k.radius)] }
            return f.withUnsafeBufferPointer { Data(buffer: $0) }
        }

        static func decodeOutlines(_ d: NSData, from offset: Int) -> [Outline]? {
            let tail = d.length - offset
            if tail == 0 { return [] }
            guard tail >= 4, tail % 4 == 0 else { return nil }
            var f = [Float32](repeating: 0, count: tail / 4)
            f.withUnsafeMutableBytes { d.getBytes($0.baseAddress!, range: NSRange(location: offset, length: tail)) }
            let n = Int(f[0])
            guard n >= 0, f.count == 1 + 5 * n else { return nil }
            return (0..<n).map { i in
                let b = 1 + 5 * i
                return Outline(rect: CGRect(x: CGFloat(f[b]), y: CGFloat(f[b + 1]), width: CGFloat(f[b + 2]),
                                            height: CGFloat(f[b + 3])), radius: CGFloat(f[b + 4]))
            }
        }

        /// Ngữ cảnh vẽ đúng định dạng tệp (BGRA premultiplied, sRGB, hàng liền nhau).
        static func makeContext(_ e: Entry) -> CGContext? {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return CGContext(data: nil, width: e.pixelWidth, height: e.pixelHeight, bitsPerComponent: 8,
                             bytesPerRow: e.pixelWidth * 4, space: space, bitmapInfo: bitmapInfo.rawValue)
        }

        /// Ghi NỀN (tệp tạm + đổi tên nguyên tử), xoá ảnh cũ; xong mới báo main có ảnh mới.
        static func save(_ e: Entry, context: CGContext, outlines: [Outline] = [], done: (() -> Void)? = nil) {
            guard !saving, let dir = directory, context.bytesPerRow == e.pixelWidth * 4,
                  context.height == e.pixelHeight else { return }
            saving = true
            queue.async {
                var ok = false
                if let p = context.data {
                    let fm = FileManager.default
                    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    // Ghi thẳng bộ đệm vẽ (không chép thêm 3 MB) vào tệp tạm, rồi đổi tên nguyên tử.
                    let tmp = dir.appendingPathComponent(".keysnap-tmp")
                    fm.createFile(atPath: tmp.path, contents: nil)
                    if let h = try? FileHandle(forWritingTo: tmp) {
                        let written: Void? = try? {
                            try h.write(contentsOf: Data(bytesNoCopy: p, count: e.byteCount, deallocator: .none))
                            try h.write(contentsOf: encodeOutlines(outlines))
                            try h.close()
                        }()
                        if written != nil {
                            ok = rename(tmp.path, dir.appendingPathComponent(e.fileName).path) == 0
                        }
                    }
                    if !ok { try? fm.removeItem(at: tmp) }
                    if ok {
                        for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where n != e.fileName {
                            try? fm.removeItem(at: dir.appendingPathComponent(n))
                        }
                    }
                }
                withExtendedLifetime(context) {}
                DispatchQueue.main.async {
                    saving = false
                    if ok { listed = true; entry = e }
                    done?()
                }
            }
        }

        /// Xoá mọi ảnh (test / công tắc tắt).
        static func clear() {
            if let dir = directory { try? FileManager.default.removeItem(at: dir) }
            listed = true; entry = nil
        }
    }
}
