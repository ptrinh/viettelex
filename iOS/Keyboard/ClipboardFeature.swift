// Luồng lịch sử clipboard + chip + ẩn danh — THUẦN (không UIKit, không đọc
// UIPasteboard): controller đưa changeCount/nội dung vào, hỏi lại quyết định.
// Tách riêng để test luồng không cần bàn phím thật.
import Foundation

/// Phần clipboard hệ thống bàn phím đọc (UIPasteboard.general; test thay bằng bản giả).
/// changeCount / hasStrings / types không bật hỏi "Cho phép dán?"; `string` thì có.
protocol PasteboardSource: AnyObject {
    var changeCount: Int { get }
    var hasStrings: Bool { get }
    var string: String? { get }
    var types: [String] { get }
}

final class ClipboardFeature {
    /// App Group keys (app ghi, extension chỉ đọc).
    static let historyKey = "clipboardHistory"   // mặc định TẮT
    static let incognitoKey = "incognitoMode"    // mặc định TẮT
    static let ttlKey = ClipboardTTL.key         // "1h" (mặc định) / "24h" / "7d"
    /// "Tự lưu khi sao chép" — mặc định TẮT. Mỗi lần đọc `UIPasteboard.string` iOS hiện
    /// banner "VietTelex đã dán từ…" (kể cả khi đã Cho phép dán) ⇒ tắt thì CHỈ đọc khi
    /// user chủ động: mở bảng clipboard, chạm Dán / chip, vuốt dán.
    static let autoSaveKey = "clipboardAutoSave"

    private(set) var historyEnabled = false
    private(set) var incognito = false
    private(set) var autoSave = false
    /// Chỉ tạo khi bật (0 RAM khi tắt).
    private(set) var history: ClipboardHistory?
    private let fileURL: URL?

    /// Nội dung clipboard đã biết (đọc được) ứng với changeCount nào.
    private(set) var known: (change: Int, text: String)?

    /// Clipboard nâng cao (Plus): số mục ghim tối đa + chip tách số. Test thay được.
    var pinLimit: () -> Int? = { PlusGate.pinnedClipLimit }
    var chipsUnlocked: () -> Bool = { PlusGate.isUnlocked(.advancedClipboard) }

    init(fileURL: URL? = ClipboardHistory.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Đọc công tắc mỗi lần bàn phím hiện. Tắt lịch sử → xoá file + bỏ RAM.
    /// `ttl` = "Giữ lịch sử clipboard" — áp ở lần prune kế tiếp (mở bảng / thêm mục).
    func load(historyEnabled h: Bool, incognito i: Bool, ttl: ClipboardTTL = .default, autoSave a: Bool = false) {
        historyEnabled = h
        incognito = i
        autoSave = a
        if h {
            if history == nil { history = ClipboardHistory(fileURL: fileURL, ttl: ttl.seconds) }
            history?.ttl = ttl.seconds
        } else {
            if history != nil || fileURL.map({ FileManager.default.fileExists(atPath: $0.path) }) == true {
                ClipboardHistory.wipe(at: fileURL)
            }
            history = nil
        }
        if i { known = nil }
    }

    func load(from defaults: UserDefaults?) {
        load(historyEnabled: defaults?.bool(forKey: Self.historyKey) ?? false,
             incognito: defaults?.bool(forKey: Self.incognitoKey) ?? false,
             ttl: ClipboardTTL.parse(defaults?.string(forKey: Self.ttlKey)),
             autoSave: defaults?.bool(forKey: Self.autoSaveKey) ?? false)
    }

    /// Được GHI vào lịch sử không (bật, không ẩn danh, ô không phải mật khẩu,
    /// clipboard không bị đánh dấu "concealed" bởi trình quản lý mật khẩu).
    func canRecord(secureField: Bool, concealed: Bool) -> Bool {
        historyEnabled && !incognito && !secureField && !concealed
    }

    /// Tự đọc clipboard khi thấy changeCount mới? Chỉ khi user bật "Tự lưu khi sao chép"
    /// (mỗi lần đọc iOS hiện banner "đã dán từ…"), được ghi, VÀ iOS không hỏi
    /// "Cho phép dán?" (user đã chọn Cho phép) — không thì mỗi lần hiện bàn phím
    /// sẽ bật hộp thoại.
    func shouldAutoRead(fullAccess: Bool, noPrompt: Bool, secureField: Bool, concealed: Bool) -> Bool {
        autoSave && fullAccess && noPrompt && canRecord(secureField: secureField, concealed: concealed)
    }

    /// Nội dung clipboard vừa đọc được (tự đọc hoặc lúc chạm Dán).
    func captured(_ text: String, change: Int, now: TimeInterval, secureField: Bool, concealed: Bool) {
        guard canRecord(secureField: secureField, concealed: concealed) else { return }
        known = (change, text)
        if let h = history, h.add(text, now: now) { h.prune(now: now); h.save() }
    }

    /// Chip cho clipboard HIỆN TẠI (changeCount khớp nội dung đã biết, chưa dùng).
    /// Tự lưu tắt ⇒ nội dung chỉ "biết" sau lần đọc chủ động (mở bảng clipboard) ⇒ chip
    /// STK/OTP chỉ hiện từ lúc đó — chấp nhận, đổi lại không có banner "đã dán từ…".
    /// Nội dung clipboard hiện tại khi được phép chip (cùng điều kiện `chips`) — nguồn cho AI địa chỉ.
    func chipSource(currentChange: Int, usedChange: Int) -> String? {
        guard !incognito, chipsUnlocked(), let k = known, k.change == currentChange, k.change != usedChange else { return nil }
        return k.text
    }

    func chips(currentChange: Int, usedChange: Int) -> [ClipChip] {
        guard !incognito, chipsUnlocked(), let k = known, k.change == currentChange, k.change != usedChange else { return [] }
        return ClipDetect.detect(k.text)
    }

    func items(now: TimeInterval) -> [ClipItem] {
        guard let h = history else { return [] }
        let changed = h.prune(now: now)
        if changed { h.save() }
        return h.items(now: now)
    }

    /// false = đã đủ số mục ghim miễn phí (không đổi gì).
    @discardableResult
    func togglePin(_ text: String) -> Bool {
        guard let h = history else { return false }
        let ok = h.togglePin(text, limit: pinLimit())
        if ok { h.save() }
        return ok
    }
    func remove(_ text: String) { history?.remove(text); history?.save() }
    func clearUnpinned() { history?.clearUnpinned(); history?.save() }
}
