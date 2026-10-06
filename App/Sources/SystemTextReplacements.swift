// Gõ tắt trùng với "Thay thế văn bản" (Text Replacements) của macOS — issue #117.
//
// Hiện tượng (1.8.11, macOS 27, Lark — đường tap): gõ tắt VietTelex "h" → "giờ" VÀ
// Cài đặt hệ thống › Bàn phím › Thay thế văn bản cũng có "h" → "giờ". Gõ "h␣" ra
// "giờiờ". Log: `tap-emit bs=1 ins=3` rồi `bs=0 ins=1` — mình nở đúng một lần; phần
// thừa là của macOS. Video của reporter cho thấy cơ chế: ngay khi gõ "h", Chromium
// hiện bong bóng gợi ý "giờ ×" (NSSpellChecker, NSTextCheckingTypeReplacement) GẮN
// VỚI RANGE của chữ "h"; tới dấu cách nó chấp nhận gợi ý vào range CŨ đó — lúc này
// range đó đã là "g" của "giờ" mình vừa gõ lại ⇒ "giờ" + "iờ". Video thứ hai (form
// web): gõ "Hoangf" ra "HGIỜoangf" — bong bóng "H"→"GIỜ" nhảy vào giữa từ khi mình
// ⌫-gõ-lại. Reporter tắt `NSAutomaticTextReplacementEnabled` +
// `WebAutomaticTextReplacementEnabled` (defaults -g) ⇒ hết.
//
// Quyết định:
//  • Ở app họ Chromium (Chrome/Edge/Brave…, Electron, CEF, Lark) đang BẬT thay thế văn
//    bản: khoá gõ tắt mà chữ trên màn hình trùng một khoá Text Replacements của macOS
//    ⇒ VietTelex KHÔNG nở, để macOS nở (một lần, đúng chữ). Chromium khớp không phân
//    biệt hoa thường ("H" → "GIỜ" trong video) nên so viết thường.
//  • App Cocoa/WebKit: macOS thay thế đồng bộ trên CHÍNH chữ đang có trước dấu cách
//    (mình đã đổi "h" thành "giờ" thì không còn gì khớp) ⇒ giữ nguyên, không bỏ — chưa
//    có report nào ngoài họ Chromium. Terminal/Office/Firefox không dùng thay thế của
//    macOS ⇒ gõ tắt VietTelex là đường duy nhất, càng phải giữ.
//  • Cài đặt › Gõ tắt liệt kê khoá trùng + khuyên XOÁ BÊN macOS (gõ tắt VietTelex chạy
//    ở mọi app; khoá một chữ cái bên macOS còn làm hỏng chữ Việt giữa từ như video 2 —
//    bỏ nở bên mình không cứu được trường hợp đó).
//
// Chi phí: 0 mỗi phím. Bảng macOS đọc lúc activateServer (≤ 1 lần/30 giây, UserDefaults
// đã cache trong cfprefsd); khi bảng rỗng (đa số máy) kiểm tra chỉ là một lần lock +
// isEmpty, và chỉ chạy khi một khoá gõ tắt ĐÃ khớp. Họ app tính một lần mỗi bundle id
// (đọc thư mục Frameworks), chỉ khi có trùng.
import AppKit

enum SystemTextReplacements {
    /// Khoá global defaults macOS lưu bảng Thay thế văn bản (đồng bộ từ
    /// ~/Library/KeyboardServices/TextReplacements.db — đã đối chiếu 06/10/2026 trên
    /// macOS 27: cùng số mục với NSSpellChecker.userReplacementsDictionary).
    static let defaultsKey = "NSUserDictionaryReplacementItems"

    /// `[{replace, with, on}]` → [khoá VIẾT THƯỜNG: nội dung]. Mục `on = 0` (tắt) hoặc
    /// rỗng bị bỏ.
    static func parse(_ items: [Any]?) -> [String: String] {
        var out: [String: String] = [:]
        for case let item as [String: Any] in items ?? [] {
            guard let key = item["replace"] as? String, let value = item["with"] as? String,
                  !key.isEmpty, !value.isEmpty else { continue }
            if let on = item["on"] as? NSNumber, on.intValue == 0 { continue }
            out[key.lowercased()] = value
        }
        return out
    }

    /// Một khoá gõ tắt VietTelex cũng có trong bảng macOS.
    struct Conflict: Equatable, Identifiable {
        var id: String { key }
        let key: String
        let ours: String
        let system: String
        var sameExpansion: Bool { ours == system }
    }

    /// Khoá trùng (so viết thường như macOS), sắp theo khoá.
    static func conflicts(ours: [String: String], system: [String: String]) -> [Conflict] {
        guard !system.isEmpty else { return [] }
        return ours.compactMap { k, v in
            system[k.lowercased()].map { Conflict(key: k, ours: v, system: $0) }
        }.sorted { $0.key < $1.key }
    }

    /// Thay thế văn bản có thể đang chạy ở app không. Chromium đọc
    /// `WebAutomaticTextReplacementEnabled`, AppKit đọc `NSAutomaticTextReplacementEnabled`
    /// (miền app rồi global; chưa đặt = BẬT, mặc định của macOS). Chỉ coi là tắt khi CẢ
    /// HAI tắt hẳn: đoán sai "bật" chỉ làm chữ không nở (thấy ngay, sửa được), đoán sai
    /// "tắt" là nở đôi "giờiờ".
    static func substitutionEnabled(web: Bool?, appKit: Bool?) -> Bool {
        web != false || appKit != false
    }

    /// App họ Chromium: Contents/Frameworks có Electron / CEF, hoặc một
    /// "<Tên> Framework.framework" có thư mục Helpers (Chrome, Edge, Brave, Lark…).
    static func isChromiumFamily(frameworks: [String], hasHelpers: (String) -> Bool) -> Bool {
        for f in frameworks {
            if f == "Electron Framework.framework" || f == "Chromium Embedded Framework.framework" {
                return true
            }
            if f.hasSuffix(" Framework.framework"), hasHelpers(f) { return true }
        }
        return false
    }

    /// Bỏ nở gõ tắt VietTelex để macOS tự nở: chữ TRÊN MÀN HÌNH sắp bị thay (từ đang soạn
    /// / cụm ký hiệu) là một khoá macOS, ở app họ Chromium đang bật thay thế văn bản.
    static func shouldDefer(onScreen: String, systemKeys: [String: String], appSubstitutes: Bool) -> Bool {
        appSubstitutes && !onScreen.isEmpty && systemKeys[onScreen.lowercased()] != nil
    }
}

/// Bộ nhớ đệm lúc chạy của SystemTextReplacements (gọi được từ main lẫn tap thread).
final class SystemReplacementGuard {
    static let shared = SystemReplacementGuard()

    private let lock = NSLock()
    private var table: [String: String] = [:]
    private var lastRefresh: Date = .distantPast
    private var chromium: [String: Bool] = [:]     // theo bundle id, tính một lần
    private var enabled: [String: Bool] = [:]      // theo bundle id, xoá mỗi lần refresh
    static let refreshInterval: TimeInterval = 30

    /// Bảng macOS hiện tại (Cài đặt › Gõ tắt).
    var systemTable: [String: String] { refreshIfStale(force: true); return lock.withLock { table } }

    /// Đọc lại bảng macOS nếu đã cũ. Gọi ở activateServer — không bao giờ mỗi phím.
    func refreshIfStale(force: Bool = false) {
        let now = Date()
        let stale = lock.withLock { force || now.timeIntervalSince(lastRefresh) >= Self.refreshInterval }
        guard stale else { return }
        let parsed = SystemTextReplacements.parse(
            UserDefaults.standard.array(forKey: SystemTextReplacements.defaultsKey))
        lock.withLock { table = parsed; enabled = [:]; lastRefresh = now }
    }

    /// activateServer: làm mới bảng (nếu cũ) và, khi có bảng, tính sẵn họ app NGOÀI
    /// main/tap thread — ranh giới đầu tiên không phải đọc ổ đĩa.
    func activated(bundleID: String?) {
        refreshIfStale()
        guard let id = bundleID, lock.withLock({ !table.isEmpty && enabled[id] == nil }) else { return }
        DispatchQueue.global(qos: .utility).async { _ = self.appSubstitutes(id) }
    }

    /// Ranh giới vừa khớp một khoá gõ tắt: có để macOS nở thay không (issue #117).
    func shouldDefer(onScreen: String, bundleID: String?) -> Bool {
        guard let id = bundleID, !onScreen.isEmpty else { return false }
        let hit = lock.withLock { !table.isEmpty && table[onScreen.lowercased()] != nil }
        guard hit else { return false }
        let subs = appSubstitutes(id)
        let d = lock.withLock {
            SystemTextReplacements.shouldDefer(onScreen: onScreen, systemKeys: table, appSubstitutes: subs)
        }
        if d { DebugLog.log("shortcut \(id): key also in macOS Text Replacements → macOS expands (#117)") }
        return d
    }

    private func appSubstitutes(_ id: String) -> Bool {
        if let e = lock.withLock({ enabled[id] }) { return e }
        let family = lock.withLock { chromium[id] } ?? {
            let v = Self.detectChromium(id)
            lock.withLock { chromium[id] = v }
            return v
        }()
        let on = family && SystemTextReplacements.substitutionEnabled(
            web: Self.bool("WebAutomaticTextReplacementEnabled", id),
            appKit: Self.bool("NSAutomaticTextReplacementEnabled", id))
        lock.withLock { enabled[id] = on }
        return on
    }

    /// Miền app rồi global domain (CFPreferencesCopyAppValue tự rơi xuống global).
    private static func bool(_ key: String, _ id: String) -> Bool? {
        guard let v = CFPreferencesCopyAppValue(key as CFString, id as CFString) else { return nil }
        return (v as? NSNumber)?.boolValue
    }

    private static func detectChromium(_ id: String) -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return false }
        let fw = app.appendingPathComponent("Contents/Frameworks")
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: fw.path)) ?? []
        return SystemTextReplacements.isChromiumFamily(frameworks: names) {
            fm.fileExists(atPath: fw.appendingPathComponent($0).appendingPathComponent("Helpers").path)
        }
    }
}
