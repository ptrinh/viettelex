// SuggestionEmojiTiles — emoji trên THANH GỢI Ý vẽ từ atlas (iOS/docs/RAM-AUDIT.md §4f).
//
// Trước: ô emoji của thanh gợi ý (EmojiSuggest, mặc định BẬT) vẽ bằng CHỮ ⇒ lần đầu có emoji CoreText
// nạp font Apple Color Emoji (~1,8 MB) + cache glyph mỗi emoji khác nhau không bao giờ nhả — đi vòng
// qua atlas vẽ sẵn mà bảng emoji đã dùng từ 14/10/2026 (§4b).
// Giờ: atlas hợp lệ ⇒ ảnh. Trang atlas giải mã Ở NỀN, chép ra ô đúng cỡ bar (20 pt ⇒ 60 px @3x ≈ 14 KB)
// rồi bỏ trang ngay (không giữ trang ~1,3 MB chỉ vì bar); LRU `capacity` ô. Không atlas / emoji không
// có trong atlas ⇒ vẽ chữ như cũ.
//
// Hợp đồng với thanh gợi ý (KeyboardView.showSuggestions):
//   • `lookup` không bao giờ chặn: `.image` (có sẵn trong LRU) / `.text` (chắc chắn không có ảnh) /
//     `.pending` (đang giải mã — ô để TRỐNG một nhịp, KHÔNG BAO GIỜ hiện emoji khác).
//   • Kết quả nền về main chỉ báo qua `onReady(emoji)`: bên gọi tự kiểm ô nào còn muốn ĐÚNG emoji đó.
//     `reset()` (ẩn bàn phím / thiếu RAM) tăng thế hệ ⇒ kết quả đang bay bị bỏ.
//   • Chỉ dùng trên main thread (trừ phần chạy trong `queue`).
import UIKit

final class SuggestionEmojiTiles {
    enum Lookup: Equatable { case image(UIImage), text, pending }

    /// Số ô giữ sẵn (bar hiện ≤ 3 emoji; gõ qua lại vài từ vẫn trúng cache). 12 × ~14 KB.
    static let capacity = 12
    /// Emoji chắc chắn không có ảnh (không có trong atlas) — nhớ ít, khỏi hỏi lại mỗi phím.
    static let missingCapacity = 32

    /// Cỡ chữ ô emoji của bar (KeyButton.titleFont) — ảnh = cạnh glyph khi vẽ chữ ở cỡ này.
    let fontSize: CGFloat
    private let scale: CGFloat
    private let open: () -> EmojiAtlasStore?
    private let queue = DispatchQueue(label: "com.viettelex.bar-emoji", qos: .userInitiated)

    // Phía main
    private enum Atlas: Equatable { case unknown, valid, none }
    private var atlas = Atlas.unknown
    /// Cạnh ảnh (pt) theo atlas — có sau lần giải mã đầu.
    private(set) var side: CGFloat
    private var lru: [(emoji: String, image: UIImage)] = []
    private var missing: [String] = []
    private var queued: [String] = []
    private var inflight = Set<String>()
    private var generation = 0
    /// Ảnh / quyết định cho `emoji` vừa sẵn (main). Bên gọi chỉ áp cho ô còn muốn đúng emoji đó.
    var onReady: ((String) -> Void)?

    // Phía `queue` (chỉ đọc/ghi trong queue)
    private var store: EmojiAtlasStore?
    private var opened = false

    #if DEBUG
    private(set) var debugJobs = 0
    private(set) var debugDroppedStale = 0
    #endif

    /// `open` chạy trên hàng đợi nền (một lần cho tới `reset`) — mở atlas hợp lệ hoặc nil.
    init(fontSize: CGFloat, scale: CGFloat, open: @escaping () -> EmojiAtlasStore?) {
        self.fontSize = fontSize
        self.scale = max(scale, 1)
        self.open = open
        side = fontSize
    }

    /// Bàn phím: atlas trong App Group (KHÔNG đụng `EmojiAtlasStore.current` — đó là của bảng emoji,
    /// chỉ dùng trên main).
    static func keyboardOpener(scale: CGFloat, pad: Bool) -> () -> EmojiAtlasStore? {
        { EmojiAtlas.defaultRoot.flatMap { EmojiAtlasStore(root: $0, expected: EmojiAtlas.expectedKey(scale: scale, pad: pad)) } }
    }

    /// Không chặn. `.pending` ⇒ đã xếp hàng; gọi `flush()` sau khi duyệt hết các ô.
    func lookup(_ e: String) -> Lookup {
        if atlas == .none { return .text }
        if let i = lru.firstIndex(where: { $0.emoji == e }) {
            let hit = lru.remove(at: i)
            lru.append(hit)
            return .image(hit.image)
        }
        if missing.contains(e) { return .text }
        if !inflight.contains(e), !queued.contains(e) { queued.append(e) }
        return .pending
    }

    /// Gửi các emoji đang chờ thành MỘT việc nền (mỗi trang giải mã một lần).
    func flush() {
        guard !queued.isEmpty else { return }
        let batch = queued
        queued.removeAll()
        inflight.formUnion(batch)
        let gen = generation, fontSize = fontSize, scale = scale
        #if DEBUG
        debugJobs += 1
        #endif
        queue.async { [weak self] in
            guard let self else { return }
            if !self.opened { self.store = self.open(); self.opened = true }
            guard let st = self.store else {
                DispatchQueue.main.async { [weak self] in self?.finish(gen, batch, nil, side: 0) }
                return
            }
            let side = st.side(forFont: fontSize)
            let images = st.renderTiles(batch, px: Int((side * scale).rounded(.up)))
            DispatchQueue.main.async { [weak self] in self?.finish(gen, batch, images, side: side) }
        }
    }

    private func finish(_ gen: Int, _ batch: [String], _ images: [String: CGImage]?, side: CGFloat) {
        guard gen == generation else {
            #if DEBUG
            debugDroppedStale += batch.count
            #endif
            return
        }
        for e in batch { inflight.remove(e) }
        guard let images else {
            atlas = .none
            for e in batch { onReady?(e) }
            return
        }
        atlas = .valid
        self.side = side
        for e in batch {
            if let cg = images[e] {
                lru.removeAll { $0.emoji == e }
                lru.append((e, UIImage(cgImage: cg, scale: scale, orientation: .up)))
                if lru.count > Self.capacity { lru.removeFirst(lru.count - Self.capacity) }
            } else {
                missing.append(e)
                if missing.count > Self.missingCapacity { missing.removeFirst(missing.count - Self.missingCapacity) }
            }
            onReady?(e)
        }
    }

    /// Ẩn bàn phím / thiếu RAM: bỏ LRU + atlas đã mở (mở lại lần sau — app có thể vừa dựng lại atlas);
    /// kết quả đang bay bị bỏ. Ảnh ô đang hiện vẫn do ô giữ.
    func reset() {
        generation += 1
        lru.removeAll()
        missing.removeAll()
        queued.removeAll()
        inflight.removeAll()
        atlas = .unknown
        queue.async { [weak self] in self?.store = nil; self?.opened = false }
    }

    var cachedTileCount: Int { lru.count }

    #if DEBUG
    /// Test: chờ hết việc nền rồi chạy callback main đang chờ.
    func debugDrain(timeout: TimeInterval = 5) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            queue.sync {}
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        } while !inflight.isEmpty && Date() < deadline
    }
    var debugAtlasState: String { "\(atlas)" }
    #endif
}
