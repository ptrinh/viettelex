// Ba cài đặt macOS › Bàn phím › Nhập văn bản mà input method bên thứ ba phải TỰ làm
// (bàn phím Apple tự làm trong input source của nó; khi VietTelex đang chọn thì không
// ai làm — Phil kiểm chứng trên TextEdit 16/10/2026):
//  • "Thêm dấu chấm khi nhấn đúp phím cách" — NSAutomaticPeriodSubstitutionEnabled
//  • "Tự động viết hoa từ"                    — NSAutomaticCapitalizationEnabled
//  • "Sử dụng dấu ngoặc kép và dấu gạch thông minh" — NSAutomaticQuoteSubstitutionEnabled
//    + NSAutomaticDashSubstitutionEnabled, kiểu ngoặc ở NSUserQuotesArray
//    (["“","”","‘","’"] = mở kép, đóng kép, mở đơn, đóng đơn — đã đối chiếu `defaults
//    read -g` trên macOS 27).
// KHÔNG có công tắc riêng của VietTelex (Phil chốt 16/10/2026): mỗi tính năng đi theo
// đúng cài đặt macOS.
//
// Chi phí: đọc cài đặt ở activateServer (≤ 1 lần/giây; UserDefaults đã cache trong
// process, cfprefsd đẩy thay đổi về) — không bao giờ mỗi phím. Tất cả tắt ⇒ đường phím
// chỉ đọc một Bool dưới khoá ở phím cách / chữ đầu từ / " ' -. Bật ⇒ thêm một phép so
// thời gian + một ký tự trong dòng phím mình đã thấy (ShortcutTail); chỉ khi ĐÃ quyết
// thay mới đọc lại màn hình một lần để xác nhận (giống gõ tắt / gợi ý cạnh con trỏ).
//
// Phạm vi (SystemAutoText.appAllowed + nơi gọi):
//  • Không ở terminal, code editor (gõ "--flag", '"' trong mã) — Apple cũng không làm
//    trong Terminal; Xcode/VS Code tắt substitutions trong vùng mã.
//  • Không ở ô mật khẩu / secure input / app passthrough / remote desktop — các đường
//    đó return trước khi tới đây.
//  • Đường tap: chỉ chế độ ⌫-gõ-lại (.backspace — Electron: Slack, Discord, Notion…);
//    omnibox/Spotlight (.selection) và Excel/ô có autocomplete (.emptyReset) bỏ qua.
//  • Thay chữ ĐÃ CHỐT (". " cho dấu cách, "—" cho "--") chỉ ở app đã chứng minh tôn
//    trọng replacementRange (TelexInputController.replacesCommittedText) và không ở
//    marked — app chưa phân loại có thể append thay vì thay.
import AppKit
import ApplicationServices

enum SystemAutoText {
    static let periodKey = "NSAutomaticPeriodSubstitutionEnabled"
    static let capitalizeKey = "NSAutomaticCapitalizationEnabled"
    static let quoteKey = "NSAutomaticQuoteSubstitutionEnabled"
    static let dashKey = "NSAutomaticDashSubstitutionEnabled"
    static let quotesArrayKey = "NSUserQuotesArray"

    struct Quotes: Equatable {
        var openDouble: String, closeDouble: String, openSingle: String, closeSingle: String
        static let us = Quotes(openDouble: "“", closeDouble: "”", openSingle: "‘", closeSingle: "’")
    }

    struct Settings: Equatable {
        var period = false, capitalize = false, quotes = false, dashes = false
        var quoteChars = Quotes.us
        var any: Bool { period || capitalize || quotes || dashes }
    }

    /// Khoá chưa đặt = BẬT: bốn ô này mặc định được tick trên máy mới cài.
    static func flag(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? true }

    /// NSUserQuotesArray: đúng 4 chuỗi không rỗng, không thì nil (dùng ngoặc của locale).
    static func parseQuotes(_ v: Any?) -> Quotes? {
        guard let a = v as? [String], a.count == 4, !a.contains(where: \.isEmpty) else { return nil }
        return Quotes(openDouble: a[0], closeDouble: a[1], openSingle: a[2], closeSingle: a[3])
    }

    static func localeQuotes(_ l: Locale) -> Quotes {
        Quotes(openDouble: l.quotationBeginDelimiter ?? "“", closeDouble: l.quotationEndDelimiter ?? "”",
               openSingle: l.alternateQuotationBeginDelimiter ?? "‘",
               closeSingle: l.alternateQuotationEndDelimiter ?? "’")
    }

    static func settings(read: (String) -> Any?, locale: Locale = .current) -> Settings {
        Settings(period: flag(read(periodKey)), capitalize: flag(read(capitalizeKey)),
                 quotes: flag(read(quoteKey)), dashes: flag(read(dashKey)),
                 quoteChars: parseQuotes(read(quotesArrayKey)) ?? localeQuotes(locale))
    }

    // MARK: Phạm vi app

    /// Terminal + app mã nguồn: không làm gì (dấu cách đôi, " ' -- và chữ đầu dòng ở đó
    /// là cú pháp, không phải văn xuôi).
    static let excludedApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp",
        "dev.warp.Warp-Preview", "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty",
        "com.github.wez.wezterm", "co.zeit.hyper", "com.mitchellh.ghostty",
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.vscodium", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
        "dev.zed.Zed", "dev.zed.Zed-Preview", "com.sublimetext.4", "com.sublimetext.3",
        "com.panic.Nova", "com.barebones.bbedit", "com.macromates.TextMate",
        "com.google.android.studio",
    ]
    static let excludedPrefixes = ["com.jetbrains."]

    static func appAllowed(_ id: String?) -> Bool {
        guard let id else { return false }
        if excludedApps.contains(id) || AppState.isSpotlight(id) || AppState.isOverlayLauncher(id) {
            return false
        }
        return !excludedPrefixes.contains { id.hasPrefix($0) }
    }

    // MARK: Dấu chấm khi nhấn đúp phím cách

    /// Apple không công bố ngưỡng; AOSP LatinIME dùng 1100 ms
    /// (config_double_space_period_timeout) — cùng cảm giác với iOS: hai lần chạm liền
    /// nhau, không phải dừng nghĩ rồi gõ tiếp.
    static let doubleSpaceWindowNs: UInt64 = 1_100_000_000

    /// Ký tự trước dấu cách đầu được phép kết thúc câu bằng ".": chữ, số, ngoặc/nháy đóng
    /// ("(xem trên)␣␣" → "(xem trên). "). Không sau dấu câu (. , ! ? : ; …), dấu cách,
    /// gạch, ký hiệu.
    static let periodClosers: Set<Character> = [")", "]", "}", "\"", "'", "”", "’", "»", "›"]
    static func periodQualifies(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || periodClosers.contains(c)
    }

    /// Phím cách thứ hai: `before` = văn bản mình biết ngay trước con trỏ (đã gồm dấu
    /// cách đầu), `gapNs` = từ dấu cách đầu tới giờ. Trả ký tự trước dấu cách đầu khi
    /// phải thay " " → ". ", nil = dấu cách thường.
    static func doubleSpacePeriod(before: String, gapNs: UInt64, isRepeat: Bool) -> Character? {
        guard !isRepeat, gapNs <= doubleSpaceWindowNs, before.last == " " else { return nil }
        guard let prev = before.dropLast().last, periodQualifies(prev) else { return nil }
        return prev
    }

    // MARK: Ngoặc kép cong

    /// Mở khi đầu văn bản / sau khoảng trắng, ngoặc mở, ngoặc kép mở, gạch dài; còn lại
    /// đóng — kể cả giữa từ ("don't" → "don’t", nháy đơn đóng là dấu móc lửng).
    static let quoteOpeners: Set<Character> = ["(", "[", "{", "<", "“", "‘", "«", "‹", "—", "–", "/"]
    static func smartQuote(_ typed: Character, prev: Character?, quotes q: Quotes) -> String? {
        let double: Bool
        switch typed {
        case "\"": double = true
        case "'": double = false
        default: return nil
        }
        let open: Bool
        if let p = prev {
            open = p.isWhitespace || p.isNewline || quoteOpeners.contains(p)
                || (double ? p == Character(q.openSingle) : p == Character(q.openDouble))
        } else {
            open = true
        }
        return double ? (open ? q.openDouble : q.closeDouble) : (open ? q.openSingle : q.closeSingle)
    }

    // MARK: Gạch dài

    enum DashEdit: Equatable { case none, emDash, restore }

    /// Phím "-": `before` = văn bản ngay trước con trỏ. "--" → "—" (thay "-" vừa gõ,
    /// nuốt phím này); "—" do CHÍNH mình vừa đổi + "-" → "---" (gạch ngang markdown,
    /// cờ dòng lệnh: gõ tiếp là lấy lại nguyên văn). Không đổi sau "<!" (chú thích
    /// HTML) và không đổi khi đã là chuỗi ≥ 3 gạch.
    static func dash(before: String, lastWasOurEmDash: Bool) -> DashEdit {
        if lastWasOurEmDash, before.last == "—" { return .restore }
        guard before.last == "-" else { return .none }
        let p = before.dropLast().last
        if p == "-" || p == "<" || p == "!" || p == "—" { return .none }
        return .emDash
    }

    // MARK: Viết hoa đầu câu

    enum CapContext: Equatable { case capitalize, keep, unknown }

    /// Viết tắt kết bằng "." mà sau đó KHÔNG phải câu mới (so viết thường, không dấu chấm cuối).
    static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "st", "jr", "sr", "vs", "etc", "e.g", "i.e", "cf",
        "approx", "no", "fig", "inc", "ltd", "co", "corp", "dept", "est", "a.m", "p.m",
        "tp", "ths", "ts", "pgs", "gs", "bs", "ks", "lg", "q", "p", "tx", "đ/c",
    ]
    static let sentenceEnds: Set<Character> = [".", "!", "?"]
    static let capClosers: Set<Character> = [")", "]", "\"", "'", "”", "’", "»", "›"]

    /// Chữ đầu tiên của một từ mới: `before` = văn bản ngay trước con trỏ (nil = không
    /// biết). `atTextStart` = con trỏ ở đầu văn bản (đã đọc được).
    static func capitalization(before: String?, atTextStart: Bool) -> CapContext {
        if atTextStart { return .capitalize }
        guard let b = before else { return .unknown }
        if b.last?.isNewline == true { return .capitalize }       // đoạn mới
        guard let last = b.last, last == " " || last == "\t" else {
            return b.isEmpty ? .unknown : .keep                     // giữa từ / sau ký hiệu
        }
        var s = Substring(b)
        while let c = s.last, c == " " || c == "\t" { s = s.dropLast() }
        if s.isEmpty { return .unknown }                            // chỉ biết khoảng trắng
        if s.last?.isNewline == true { return .capitalize }
        while let c = s.last, capClosers.contains(c) { s = s.dropLast() }
        guard let end = s.last, sentenceEnds.contains(end) else { return .keep }
        if end != "." { return .capitalize }
        s = s.dropLast()
        if s.last == "." { return .keep }                           // "..." — chưa chắc hết câu
        // Từ ngay trước dấu chấm (bỏ ngoặc mở đầu).
        var token = s
        if let i = s.lastIndex(where: { $0.isWhitespace || $0.isNewline }) { token = s[s.index(after: i)...] }
        while let c = token.first, "([{\"'“‘«".contains(c) { token = token.dropFirst() }
        if token.isEmpty { return .capitalize }
        let low = token.lowercased()
        if abbreviations.contains(low) { return .keep }
        // email, URL, tên miền, "U.S." — chưa chắc là hết câu.
        if token.contains("@") || token.contains("/") || token.contains(".") { return .keep }
        // Tên viết tắt một chữ hoa ("J. Smith").
        if token.count == 1, token.first?.isUppercase == true { return .keep }
        return .capitalize
    }

    /// Dòng phím (`recent`) dùng làm ngữ cảnh viết hoa được không. nil = không biết ⇒ đọc
    /// màn hình. Sau phím Return chưa xác nhận (`returnUnverified`), nếu đuôi `recent` chỉ
    /// là "\n" + khoảng trắng thì KHÔNG tin "\n" đó: Enter chọn mention/emoji/lệnh hay gửi
    /// tin không chèn xuống dòng (Discord "@Tuấn" + Enter + "sao" từng ra "Sao").
    static func autoCapKnownText(recent: String, returnUnverified: Bool) -> String? {
        if recent.isEmpty { return nil }
        guard returnUnverified else { return recent }
        var s = Substring(recent)
        while let c = s.last, c == " " || c == "\t" { s = s.dropLast() }
        return s.last?.isNewline == true ? nil : recent
    }

    /// Quyết định viết hoa chữ đầu từ. `known` = ngữ cảnh dòng phím (nil = không biết);
    /// không biết ⇒ `caret` (nil = không đọc được): 0 ⇒ đầu văn bản, chỉ viết hoa ở ô nhiều
    /// dòng (`multiline`); > 0 ⇒ đọc tối đa 24 ký tự trước con trỏ (`readBefore(n)`, nil =
    /// AX mù). Vẫn không biết ⇒ không viết hoa (viết hoa nhầm tệ hơn bỏ sót).
    static func resolveCapitalization(known: String?, caret: Int?,
                                      readBefore: (Int) -> String?,
                                      multiline: () -> Bool) -> CapContext {
        var ctx = capitalization(before: known, atTextStart: false)
        if ctx == .unknown, let loc = caret {
            if loc == 0 {
                ctx = capitalization(before: nil, atTextStart: multiline())
            } else {
                ctx = capitalization(before: readBefore(min(loc, 24)), atTextStart: false)
            }
        }
        return ctx
    }

    /// Chữ ASCII thường → hoa (chỉ phím chữ; số / ngoặc giữ nguyên).
    static func capitalized(_ ch: Character) -> Character {
        guard let a = ch.asciiValue, a >= 97, a <= 122 else { return ch }
        return Character(Unicode.Scalar(a - 32))
    }
}

/// Bộ nhớ đệm lúc chạy (đọc được từ main lẫn tap thread).
final class SystemAutoTextSettings {
    static let shared = SystemAutoTextSettings()
    private let lock = NSLock()
    private var value = SystemAutoText.Settings()
    private var lastRefreshNs: UInt64 = 0
    private var loaded = false

    var current: SystemAutoText.Settings {
        if !lock.withLock({ loaded }) { refresh(force: true) }
        return lock.withLock { value }
    }

    /// Phím cách: chỉ một Bool (đường nóng — không chép struct).
    var period: Bool {
        if let v = lock.withLock({ loaded ? value.period : nil }) { return v }
        return current.period
    }

    /// activateServer: đọc lại ≤ 1 lần/giây (đổi trong System Settings rồi quay lại app
    /// là thấy ngay). UserDefaults.standard rơi xuống global domain như SystemReplacementGuard.
    func refresh(force: Bool = false) {
        let now = DispatchTime.now().uptimeNanoseconds
        let stale = lock.withLock { force || !loaded || now &- lastRefreshNs >= 1_000_000_000 }
        guard stale else { return }
        let d = UserDefaults.standard
        let s = SystemAutoText.settings(read: { d.object(forKey: $0) })
        let changed = lock.withLock { () -> Bool in
            let c = value != s || !loaded
            value = s; loaded = true; lastRefreshNs = now
            return c
        }
        if changed {
            DebugLog.log("system auto-text: period=\(s.period) cap=\(s.capitalize) quotes=\(s.quotes) dashes=\(s.dashes)")
        }
    }

    #if DEBUG
    func _testSet(_ s: SystemAutoText.Settings) { lock.withLock { value = s; loaded = true; lastRefreshNs = .max } }
    #endif
}

/// Vai trò AX của phần tử đang focus — chỉ đọc khi viết hoa ĐẦU văn bản (một lần mỗi
/// lần focus đầu văn bản): ô một dòng (tên đăng nhập, ô tìm kiếm) không viết hoa, như
/// field editor của Apple; ô nhiều dòng (TextEdit, Notes, Mail, contenteditable) có.
enum FocusedRole {
    #if DEBUG
    static var _testOverride: Bool?
    #endif

    /// Đầu văn bản có được viết hoa không. Chỉ KHÔNG viết hoa khi biết chắc là ô một dòng
    /// (AXTextField / AXSearchField / AXComboBox — tên đăng nhập, ô tìm kiếm, thanh địa
    /// chỉ). Không đọc được vai trò (app không lộ AX, trình duyệt chưa bật AX) ⇒ viết hoa
    /// như ô soạn thảo: bản cũ đòi đúng AXTextArea nên chữ đầu câu đầu tiên hay không viết
    /// hoa (Phil 16/10/2026).
    static func isMultilineText() -> Bool {
        #if DEBUG
        if let v = _testOverride { return v }
        #endif
        // KHÔNG đọc AX trong handle(): app (Notes) đang chờ IME trả phím ⇒ AX hết giờ
        // (-25204, đo 17/10/2026). Dùng vai trò đã đọc lúc kích hoạt ô (refreshAsync).
        let cached = lock.withLock { cachedRole }
        if let cached { return capitalizesAtStart(role: cached.isEmpty ? nil : cached) }
        return capitalizesAtStart(role: nil)
    }

    private static let lock = NSLock()
    private static var cachedRole: String?          // nil = chưa đọc; "" = đọc không được
    private static var generation = 0

    #if DEBUG
    static func _testSetCachedRole(_ r: String?) { lock.withLock { cachedRole = r } }
    #endif

    /// Gọi ở activateServer (ô mới): xoá vai trò cũ, đọc lại NGOÀI lượt phím (app rảnh).
    /// Chỉ khi cài đặt viết hoa đang bật ⇒ tắt = không tốn gì.
    static func refreshAsync() {
        let gen: Int = lock.withLock { generation += 1; cachedRole = nil; return generation }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            let role = focusedRole() ?? ""
            lock.withLock { if generation == gen { cachedRole = role } }
        }
    }

    static func capitalizesAtStart(role: String?) -> Bool {
        guard let role else { return true }
        return !singleLineRoles.contains(role)
    }

    static let singleLineRoles: Set<String> = [kAXTextFieldRole as String, "AXSearchField",
                                               kAXComboBoxRole as String]

    private static func focusedRole() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.05)
        var ref: CFTypeRef?
        var err = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &ref)
        if err != .success, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            // Hệ thống không trả phần tử focus (Notes: ô tìm / thay thế ⌘F) ⇒ hỏi thẳng app.
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.05)
            err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref)
        }
        guard err == .success, let f = ref, CFGetTypeID(f) == AXUIElementGetTypeID() else {
            if AppState.shared.debugLogging {
                Signposts.log.notice("focused role unavailable err=\(err.rawValue, privacy: .public)")
            }
            return nil
        }
        let el = f as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.05)
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return nil }
        var sub: CFTypeRef?
        let subrole = AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &sub) == .success
            ? sub as? String : nil
        if AppState.shared.debugLogging {
            var parentRole = "-"
            var p: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &p) == .success, let p,
               CFGetTypeID(p) == AXUIElementGetTypeID() {
                var pr: CFTypeRef?
                if AXUIElementCopyAttributeValue(p as! AXUIElement, kAXRoleAttribute as CFString, &pr) == .success {
                    parentRole = (pr as? String) ?? "-"
                }
            }
            var sz = CGSize.zero
            var sv: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success, let sv,
               CFGetTypeID(sv) == AXValueGetTypeID() { AXValueGetValue(sv as! AXValue, .cgSize, &sz) }
            let line = "focused role=\(role) subrole=\(subrole ?? "-") parent=\(parentRole) size=\(Int(sz.width))x\(Int(sz.height))"
            DebugLog.log(line)
            Signposts.log.notice("\(line, privacy: .public)")
        }
        if subrole == (kAXSearchFieldSubrole as String) { return "AXSearchField" }
        return role
    }
}
