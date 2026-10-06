// Ngôn ngữ giao diện app + bàn phím (27/09/2026). Chữ gốc tiếng Việt CHÍNH LÀ khoá:
// `L("Gõ tắt")` trả "Gõ tắt" (mặc định) hoặc "Shortcuts" khi người dùng chọn English
// ở Tính Năng → "Ngôn ngữ / Language". Mặc định LUÔN "vi" — không theo ngôn ngữ máy.
// Key App Group `uiLanguage` ("vi" | "en"); bàn phím đọc lại một lần mỗi lần hiện
// (KeyboardViewController.viewWillAppear) — không tốn gì trên đường phím nóng.
// Thêm chuỗi mới: bọc `L("…")` (hoặc `LK("…")` khi chỉ đánh dấu khoá để dịch lúc hiển
// thị) và thêm bản dịch vào `L10n.en` — L10nTests quét mã nguồn, thiếu là đỏ.
// Tham số: `%@` (thay lần lượt bằng "\(arg)"); `%1$@`, `%2$@` khi tiếng Anh đổi thứ tự.
import Foundation

enum L10n {
    static let defaultsKey = "uiLanguage"
    static let suiteName = "group.com.viettelex"
    static let supported = ["vi", "en"]

    /// Ngôn ngữ đang dùng — cache trong RAM, chỉ đổi qua `apply`/`reload`.
    private(set) static var lang: String = stored()

    static var isEnglish: Bool { lang == "en" }

    /// Giá trị đã lưu; thiếu/lạ ⇒ "vi" (KHÔNG nhìn Locale của máy).
    static func stored(_ d: UserDefaults? = UserDefaults(suiteName: suiteName)) -> String {
        normalized(d?.string(forKey: defaultsKey))
    }

    static func normalized(_ v: String?) -> String { v == "en" ? "en" : "vi" }

    /// Đọc lại từ App Group (bàn phím: mỗi lần hiện).
    static func reload(_ d: UserDefaults? = UserDefaults(suiteName: suiteName)) { lang = stored(d) }

    /// Đổi ngôn ngữ trong RAM (app gọi trước khi dựng lại view). Trả Void để dùng `let _ =`.
    static func apply(_ v: String) { lang = normalized(v) }

    /// Đổi + lưu App Group.
    static func set(_ v: String, _ d: UserDefaults? = UserDefaults(suiteName: suiteName)) {
        apply(v)
        d?.set(lang, forKey: defaultsKey)
    }

    static func t(_ vi: String) -> String {
        guard lang == "en" else { return vi }
        return en[vi] ?? vi
    }

    /// Thay `%@` lần lượt / `%n$@` theo vị trí.
    static func format(_ s: String, _ args: [Any]) -> String {
        guard !args.isEmpty, s.contains("%") else { return s }
        var out = s
        for (i, a) in args.enumerated() {
            out = out.replacingOccurrences(of: "%\(i + 1)$@", with: "\(a)")
        }
        var next = 0
        while let r = out.range(of: "%@"), next < args.count {
            out.replaceSubrange(r, with: "\(args[next])")
            next += 1
        }
        return out
    }

    /// Hướng dẫn sử dụng: /hdsd/ (vi) hoặc /en/guide/ (en). Anchor tiếng Việt được đổi
    /// sang id tương ứng của bản tiếng Anh.
    static func guideURL(os: String, anchor: String? = nil) -> URL {
        let base = isEnglish ? "https://viettelex.com/en/guide/?os=\(os)"
                             : "https://viettelex.com/hdsd/?os=\(os)"
        guard let anchor else { return URL(string: base)! }
        let a = isEnglish ? (enAnchors[anchor] ?? anchor) : anchor
        return URL(string: base + "#" + a)!
    }

    static let enAnchors: [String: String] = [
        "sua-dau": "fix-tones", "goi-y": "suggestions", "go-vuot": "swipe", "go-tat": "shortcuts",
        "cu-chi": "gestures", "giao-dien": "look", "clipboard": "clipboard", "sao-luu": "backup",
    ]

    // swiftlint:disable line_length
    static let en: [String: String] = [
        // Sao lưu
        "File không phải JSON hợp lệ.": "The file isn’t valid JSON.",
        "Không phải file sao lưu VietTelex.": "Not a VietTelex backup file.",
        "File sao lưu từ phiên bản mới hơn (định dạng %@) — hãy cập nhật VietTelex.": "This backup comes from a newer version (format %@) — please update VietTelex.",
        "%@ cài đặt": "%@ settings",
        "%@ gõ tắt": "%@ shortcuts",
        "%@ mẫu câu mới": "%@ new snippets",
        "%@ từ đã học": "%@ learned words",
        "File không có dữ liệu để nhập.": "The file has nothing to import.",
        "Đã nhập %@.": "Imported %@.",
        "Đồng bộ iCloud": "iCloud sync",
        "Kèm từ đã học khi xuất file": "Include learned words in exports",
        "Từ bàn phím đã học (tần suất gõ) — riêng tư, chỉ bật khi file do chính bạn giữ.": "Words the keyboard has learned (typing frequency) — private; only turn on if you keep the file yourself.",
        "Xuất file sao lưu…": "Export backup…",
        "Đã xuất file sao lưu.": "Backup exported.",
        "Nhập file sao lưu…": "Import backup…",
        "Không đọc được file.": "Couldn’t read the file.",
        "File gồm cài đặt, gõ tắt, mẫu câu (và từ đã học nếu chọn) — mở được trên iPhone, iPad và Android. Nhập: cài đặt theo file, gõ tắt và mẫu câu được gộp thêm.": "The file contains settings, shortcuts, snippets (and learned words if selected) — it opens on iPhone, iPad and Android. Importing takes the file’s settings and merges shortcuts and snippets.",
        "Cài đặt, gõ tắt, mẫu câu giống nhau trên mọi máy cùng tài khoản iCloud. Không đồng bộ từ đã học.": "Settings, shortcuts and snippets stay the same on every device with your iCloud account. Learned words aren’t synced.",
        "Máy chưa đăng nhập iCloud — sẽ đồng bộ khi đăng nhập.": "Not signed in to iCloud — syncing starts once you sign in.",
        "Đang chờ đồng bộ…": "Waiting to sync…",
        "Đồng bộ lần cuối %@.": "Last synced %@.",

        // Tính Năng — nhóm
        "Chính tả & sửa lỗi": "Spelling & corrections",
        "Gợi ý & từ điển": "Suggestions & dictionary",
        "Gõ vuốt": "Swipe typing",
        "Gõ tắt & mẫu câu": "Shortcuts & snippets",
        "Phím & cử chỉ": "Keys & gestures",
        "Giao diện": "Appearance",
        "Riêng tư & clipboard": "Privacy & clipboard",
        "Sao lưu & đồng bộ": "Backup & sync",

        // Tính Năng — mục tìm kiếm
        "Tự khôi phục từ tiếng Anh": "Auto-restore English words",
        "Kiểm tra chính tả khi gõ": "Spell check while typing",
        "Sửa dấu từ đã gõ": "Fix tones of typed words",
        "Chọn phím thông minh": "Smart key selection",
        "Tự sửa từ gõ sai": "Autocorrect typos",
        "Thanh gợi ý": "Suggestion bar",
        "Gợi ý emoji": "Emoji suggestions",
        "Chip số": "Number chips",
        "Hiện kết quả phép tính": "Show maths results",
        "Gợi ý cả khi ứng dụng tắt gợi ý": "Suggest even when the app turns suggestions off",
        "Ô mà ứng dụng tắt gợi ý (vd ô chat, thanh địa chỉ) vẫn gợi ý từ — không tự sửa, không học từ gõ ở đó. Mật khẩu, ẩn danh, ô số không bị ảnh hưởng.": "Fields where the app turns suggestions off (e.g. chat boxes, address bars) still get word suggestions — no auto-correct, and nothing typed there is learned. Passwords, incognito and number fields are unaffected.",
        "Nút Dán": "Paste button",
        "Lọc từ nhạy cảm": "Filter offensive words",
        "Từ điển cá nhân": "Personal dictionary",
        "Xóa từ đã học": "Clear learned words",
        "Vuốt từ tiếng Anh": "Swipe English words",
        "Mô hình neural gõ vuốt": "Neural swipe model",
        "Luyện vuốt": "Swipe practice",
        "Gõ tắt": "Shortcuts",
        "Bảng gõ tắt": "Shortcut table",
        "Dùng Thay thế văn bản của iOS": "Use iOS Text Replacement",
        "Bung cả các mục trong Cài đặt → Cài đặt chung → Bàn phím → Thay thế văn bản. Chỉ đọc — sửa trong Cài đặt iOS; trùng chữ tắt thì bảng của VietTelex thắng.": "Also expand entries from Settings → General → Keyboard → Text Replacement. Read-only — edit them in iOS Settings; on a clash, VietTelex's own table wins.",
        "Đang dùng %@ mục từ Thay thế văn bản của iOS": "Using %@ entries from iOS Text Replacement",
        "Số mục hiện ở đây sau khi mở bàn phím VietTelex (cần Toàn quyền truy cập để báo về app).": "The count shows here after you open the VietTelex keyboard (Full Access is needed to report it to the app).",
        "Mẫu câu": "Snippets",
        "Hàng phím số": "Number row",
        "Giữ phím ra ký tự đặc biệt": "Hold keys for symbols",
        "Vuốt phím cách đổi Tiếng Việt / Tiếng Anh": "Swipe space to switch Vietnamese / English",
        "Phóng to chữ khi bấm": "Key preview on press",
        "Rung phím": "Haptic feedback",
        "Theme & ảnh nền": "Theme & wallpaper",
        "Độ trong suốt phím": "Key transparency",
        "Độ trong suốt ký tự": "Label transparency",
        "Khôi phục giao diện gốc": "Reset appearance",
        "Chiều cao hàng phím": "Key row height",
        "Hiện logo Vᴛ": "Show Vᴛ logo",
        "Bàn phím tách đôi": "Split keyboard",
        "Màn hình rộng (iPhone gập khi mở, iPhone xoay ngang, iPad): chia bàn phím làm hai nửa để gõ bằng hai ngón cái. Khi đang tách, gõ vuốt và chế độ một tay tạm tắt.": "On wide screens (an open foldable iPhone, iPhone in landscape, iPad): splits the keyboard into two halves for thumb typing. While split, swipe typing and one-handed mode are paused.",
        "Lịch sử clipboard": "Clipboard history",
        "Chế độ ẩn danh": "Incognito mode",
        "Xuất / nhập file sao lưu": "Export / import backup",
        "Giữ phím hàng trên để ra số": "Hold top-row keys for numbers",
        "Chế độ một tay": "One-handed mode",
        "Chip “Thêm dấu”": "“Add tones” chip",
        "Thử nghiệm": "Beta",
        "Tìm hiểu thêm trong Hướng dẫn": "Learn more in the Guide",
        "Cài đặt áp dụng ngay lần mở bàn phím kế tiếp.": "Settings apply the next time the keyboard opens.",

        // Tính Năng — tóm tắt
        "Khôi phục tiếng Anh": "English restore",
        "Kiểm tra chính tả": "Spell check",
        "Sửa dấu": "Tone fix",
        "Tự sửa": "Autocorrect",
        "Đang tắt": "Off",
        "Tắt thanh gợi ý": "Suggestion bar off",
        "Bật": "On",
        "Tiếng Anh": "English",
        "Gõ tắt bật": "Shortcuts on",
        "Gõ tắt: %@ mục": "Shortcuts: %@",
        "Gõ tắt tắt": "Shortcuts off",
        "Mẫu câu bật": "Snippets on",
        "Mẫu câu tắt": "Snippets off",
        "Hàng số": "Number row",
        "Vuốt phím cách": "Space swipe",
        "Rung": "Haptics",
        "Một tay": "One-handed",
        "Mặc định": "Default",
        "Ảnh nền": "Wallpaper",
        "Trong suốt": "Transparent",
        "Lịch sử clipboard bật": "Clipboard history on",
        "Lịch sử clipboard tắt": "Clipboard history off",
        "Ẩn danh": "Incognito",
        "Đồng bộ iCloud bật": "iCloud sync on",
        "Xuất / nhập file": "Export / import file",
        "Tìm cài đặt…": "Search settings…",
        "Xoá tìm kiếm": "Clear search",
        "Không tìm thấy cài đặt nào.": "No matching settings.",
        "Kết quả": "Results",

        // Trang con
        "Từ không phải tiếng Việt trả về như đã gõ (google, github…).": "Non-Vietnamese words go back to what you typed (google, github…).",
        "Ngừng bỏ dấu khi từ không thể là tiếng Việt.": "Stop adding tones when a word can’t be Vietnamese.",
        "⌫ ngay sau dấu cách để sửa tiếp từ vừa gõ (tháy ␣ ⌫ a → thấy), hoặc đặt con trỏ sau từ rồi gõ phím dấu: viêt + j → việt.": "Press ⌫ right after a space to keep editing the last word (tháy ␣ ⌫ a → thấy), or put the cursor after a word and type a tone key: viêt + j → việt.",
        "Chính tả": "Spelling",
        "Chạm sát mép giữa hai phím thì chọn phím hợp với chữ đang gõ. Chạm giữa phím luôn ra đúng phím đó.": "A tap on the edge between two keys picks the one that fits the word you’re typing. A tap in the middle of a key always gives that key.",
        "Khi gõ dấu cách, sửa từ lỡ chạm phím kề (tpoi → tôi) nếu chắc chắn. ⌫ ngay sau đó để trả lại chữ gốc.": "On space, fix words with a mistyped neighboring key (tpoi → tôi) when confident. Press ⌫ right after to get the original back.",
        "Chạm trượt": "Mistyped keys",
        "Gợi ý sửa lỗi chạm trượt (hiện trên thanh gợi ý) nằm ở tab Kiểu Gõ.": "Typo suggestions (shown on the suggestion bar) are in the Typing tab.",
        "Gợi ý từ + emoji, tự học từ bạn hay dùng (chỉ trên máy).": "Word + emoji suggestions; learns the words you use (on device only).",
        "Emoji hợp với từ đang gõ (yêu → ❤️).": "Emoji matching the word you’re typing (yêu → ❤️).",
        "Đọc số thành chữ, định dạng tiền (1tr2 → 1.200.000 ₫).": "Spell out numbers, format amounts (1tr2 → 1.200.000 ₫).",
        "Gõ phép tính rồi dấu = (12*3=) → kết quả hiện ở đầu thanh gợi ý, chạm để chèn.": "Type a sum then = (12*3=) → the result appears first in the suggestion bar; tap to insert.",
        "Vừa copy xong thì hiện nút Dán (cần Toàn quyền).": "Show a Paste button right after you copy (needs Full Access).",
        "Gõ không dấu cả câu (hom nay troi dep), gõ dấu cách → chip “Thêm dấu” hiện ở đầu thanh gợi ý, chạm để thành “hôm nay trời đẹp”; chạm “Hoàn tác” để trả lại. Tắt mặc định cho nhẹ máy.": "Type a whole sentence without tones (hom nay troi dep), press space → an “Add tones” chip appears at the start of the suggestion bar; tap it to get “hôm nay trời đẹp”, tap “Undo” to revert. Off by default to save resources.",
        "Không chủ động gợi ý từ tục — gõ tay vẫn bình thường.": "Never suggest vulgar words — typing them yourself still works.",
        "Xem, tìm, xoá từ đã học; thêm tên riêng.": "View, search and delete learned words; add names.",
        "Từ đã học": "Learned words",
        "Vuốt qua các chữ không dấu rồi nhấc tay: v→i→e→t ra “việt”. Gõ phím dấu ngay sau để đổi dấu, ⌫ xoá cả từ. Chỉ trên iPhone.": "Swipe across the letters without tones, then lift: v→i→e→t gives “việt”. Type a tone key right after to change the tone; ⌫ deletes the whole word. iPhone only.",
        "check, mail, meeting… Nét vừa Việt vừa Anh (the/thế) ưu tiên tiếng Việt, phương án kia ở thanh gợi ý.": "check, mail, meeting… Paths that fit both (the/thế) prefer Vietnamese; the other option is on the suggestion bar.",
        "Mạng neural chạy hoàn toàn trên máy, chấm cùng bộ giải mã. Tốn thêm ~3 MB bộ nhớ.": "A neural network that runs entirely on device and scores alongside the decoder. Uses ~3 MB more memory.",
        "Tự tắt khi dùng VoiceOver và ở ô email/mật khẩu/URL.": "Turns off automatically with VoiceOver and in email/password/URL fields.",
        "Vuốt thử từng từ, xem bàn phím đọc đúng bao nhiêu.": "Swipe words one by one and see how often the keyboard gets them right.",
        "Nút ☰ trên bàn phím chèn câu soạn sẵn — quản lý ở tab Mẫu Câu. Tắt: ẩn nút ☰ và tab Mẫu Câu.": "The ☰ button on the keyboard inserts ready-made text — manage it in the Snippets tab. Off: hides the ☰ button and the Snippets tab.",
        "Thêm hàng 1 … 0 trên hàng chữ (bàn phím cao thêm ~¾ hàng).": "Adds a 1 … 0 row above the letters (keyboard gets ~¾ row taller).",
        "Giữ q … p để gõ 1 … 0 (số nhỏ ở góc phím).": "Hold q … p to type 1 … 0 (small digits in the key corners).",
        "Giữ phím hàng 2, 3 để ra ký tự đặc biệt": "Hold row 2, 3 keys for symbols",
        "Giữ a … l, z … m để gõ @ # $ _ & - + ( ) … Giữ , để ra dấu chấm.": "Hold a … l, z … m to type @ # $ _ & - + ( ) … Hold , for a period.",
        "Phím": "Keys",
        "Vuốt nhanh phím cách sang trái/phải. Góc phím cách hiện VI / EN. Tiếng Anh gõ nguyên văn. Giữ rồi kéo vẫn là di con trỏ.": "Flick the space bar left/right. The space bar corner shows VI / EN. English types as-is. Hold and drag still moves the cursor.",
        "Tự thêm dấu cách sau dấu câu": "Add space after punctuation",
        "Gõ . , ? ! ; : tự có dấu cách phía sau. Không thêm trong số (3.5, 1,000), email, đường dẫn. Gõ dấu cách ngay sau không thành hai dấu cách; ⌫ ngay sau chỉ xoá dấu cách đó.": "Typing . , ? ! ; : adds a space after it. Not inside numbers (3.5, 1,000), emails or links. A space typed right after doesn't double up; ⌫ right after removes just that space.",
        "Cách sau dấu câu": "Space after punctuation",
        "Tắt": "Off",
        "Trái": "Left",
        "Phải": "Right",
        "Thu hẹp bàn phím về một bên. Giữ lâu nút ☰ trên thanh gợi ý để bật/tắt nhanh.": "Shrinks the keyboard to one side. Long-press ☰ on the suggestion bar to toggle it quickly.",
        "Cử chỉ": "Gestures",
        "Ô chữ lớn nổi trên phím vừa chạm. Tắt cho gọn, nhẹ máy.": "A large letter pops up above the key you tap. Turn off for a cleaner, lighter keyboard.",
        "Rung nhẹ mỗi lần chạm phím.": "A light vibration on every key tap.",
        "Phản hồi khi chạm": "Tap feedback",

        // Plus
        "Không tải được sản phẩm từ App Store. Kiểm tra kết nối mạng rồi thử lại.": "Couldn’t load products from the App Store. Check your connection and try again.",
        "Đã mở khoá VietTelex Plus. Cảm ơn bạn!": "VietTelex Plus unlocked. Thank you!",
        "Cảm ơn bạn đã ủng hộ VietTelex! ❤️": "Thanks for supporting VietTelex! ❤️",
        "Giao dịch đang chờ duyệt. Plus sẽ tự mở khi được chấp thuận.": "The purchase is pending approval. Plus unlocks automatically once approved.",
        "Giao dịch không thành công. Bạn chưa bị trừ tiền.": "The purchase didn’t go through. You haven’t been charged.",
        "Không kết nối được App Store để khôi phục.": "Couldn’t reach the App Store to restore.",
        "Đã khôi phục VietTelex Plus.": "VietTelex Plus restored.",
        "Không tìm thấy giao dịch Plus nào với Apple ID này.": "No Plus purchase found for this Apple ID.",
        "Đã mở khoá": "Unlocked",
        "Cảm ơn bạn đã ủng hộ VietTelex ★": "Thanks for supporting VietTelex ★",
        "Mua một lần, dùng mãi mãi. Không thuê bao, không quảng cáo.": "Buy once, keep forever. No subscription, no ads.",
        "Trong giai đoạn này mọi tính năng Plus đang mở miễn phí cho tất cả mọi người.": "For now, every Plus feature is free for everyone.",
        "Quyền lợi Plus": "Plus benefits",
        "Toàn bộ phần gõ — Telex/VNI, sửa dấu từ đã gõ, gợi ý, gõ vuốt, gõ tắt, mẫu câu, theme sáng/tối — luôn miễn phí.": "All the typing — Telex/VNI, tone fixing, suggestions, swipe typing, shortcuts, snippets, light/dark themes — is always free.",
        "Bạn đã có VietTelex Plus": "You have VietTelex Plus",
        "Mở khoá Plus": "Unlock Plus",
        "Khôi phục giao dịch": "Restore purchases",
        "Mua": "Purchase",
        "Thanh toán qua Apple ID. Đã mua trên máy khác cùng Apple ID thì bấm Khôi phục.": "Paid with your Apple ID. Bought on another device with the same Apple ID? Tap Restore.",
        "Chưa tải được các mức ủng hộ.": "Couldn’t load the tip options.",
        "Ủng hộ tác giả": "Support the developer",
        "Tuỳ tâm, không mở khoá thêm gì — giúp VietTelex tiếp tục miễn phí và mã nguồn mở.": "Pay what you like; it doesn’t unlock anything — it helps keep VietTelex free and open source.",
        "Giả lập đã mua Plus": "Simulate Plus purchase",
        "Chỉ có trong bản Debug. Bàn phím đọc cùng cờ qua App Group.": "Debug builds only. The keyboard reads the same flag via the App Group.",

        // Luyện vuốt
        "✓ Đúng": "✓ Correct",
        "✗ Bàn phím đọc thành “%@” — thử lại": "✗ The keyboard read “%@” — try again",
        "Phiên này: chưa vuốt": "This session: no swipes yet",
        "Phiên này: %@/%@ đúng (%@%)": "This session: %@/%@ correct (%@%)",
        "Bỏ qua": "Skip",
        "Từ tiếng Anh — vuốt đúng từng chữ.": "English word — swipe every letter.",
        "Vuốt qua các chữ không dấu rồi nhấc tay.": "Swipe across the letters without tones, then lift.",
        "Lưu nét vuốt trên máy": "Save swipe paths on device",
        "Độ mạnh rung": "Vibration strength",
        "Nhẹ": "Light",
        "Mạnh": "Strong",
        "Âm thanh phím": "Key sound",
        "Âm lượng": "Volume",
        "Tiếng phím riêng của VietTelex: chọn kiểu, chỉnh âm lượng. Tắt: dùng tiếng bấm bàn phím của iOS (Cài đặt → Âm thanh). Im khi gạt chế độ im lặng.": "VietTelex's own key sound: pick a style, adjust the volume. Off: uses iOS keyboard clicks (Settings → Sounds). Silent when the ring/silent switch is on.",
        "Kiểu âm": "Sound style",
        "Nhẹ nhàng": "Soft",
        "Gõ gỗ": "Wood tap",
        "Bàn phím cơ": "Mechanical",
        "Máy chữ": "Typewriter",
        "Bong bóng": "Bubble",
        "Âm của bạn": "Your sound",
        "Kéo thanh trượt hoặc chọn kiểu để nghe thử. Không nghe thấy? Tắt gạt im lặng (bàn phím cũng im khi gạt).": "Drag the slider or pick a style to preview. Can't hear it? Turn off the silent switch (the keyboard is silent then too).",
        "OK": "OK",
        "Âm của bạn: %@ giây": "Your sound: %@ s",
        "Chưa có âm — chọn một file âm thanh ngắn (m4a, mp3, wav, caf, aiff).": "No sound yet — pick a short audio file (m4a, mp3, wav, caf, aiff).",
        "Chọn file âm thanh…": "Choose audio file…",
        "Chọn âm khác…": "Choose another…",
        "Âm được cắt lặng đầu, giữ tối đa 0,3 giây và chỉnh độ to an toàn. File chỉ nằm trên máy này (không có trong sao lưu).": "Leading silence is trimmed, at most 0.3 s is kept and loudness is made safe. The file stays on this device (not in backups).",
        "Âm dài hơn 0,3 giây nên đã được cắt ngắn.": "The sound was longer than 0.3 s, so it was shortened.",
        "Không đọc được file âm thanh này. Hãy thử m4a, mp3, wav, caf hoặc aiff.": "Couldn't read this audio file. Try m4a, mp3, wav, caf or aiff.",
        "File quá lớn (tối đa 30 MB).": "File too large (max 30 MB).",
        "File không có tiếng (toàn im lặng).": "The file is silent.",
        "Không lưu được âm (thiếu App Group).": "Couldn't save the sound (App Group unavailable).",
        "Bật \"Lưu nét vuốt trên máy\" rồi vuốt vài từ để xuất được.": "Turn on \"Save swipe paths on device\" and swipe a few words to export.",
        "Đã lưu %@ nét.": "%@ paths saved.",
        "Tắt: chỉ luyện, không lưu gì.": "Off: practice only, nothing is saved.",
        "Xuất JSON…": "Export JSON…",
        "Chạm lần nữa để xoá %@ nét": "Tap again to delete %@ paths",
        "Xoá nét đã lưu": "Delete saved paths",
        "Dữ liệu": "Data",
        "Nét vuốt chỉ nằm trên máy này (không sao lưu iCloud, không tự gửi đi). Xuất JSON để gửi cho nhà phát triển nếu bạn muốn giúp gõ vuốt chính xác hơn.": "Swipe paths stay on this device (no iCloud backup, never sent automatically). Export JSON to send to the developer if you’d like to help make swipe typing more accurate.",

        // Riêng tư
        "Nút clipboard trên thanh gợi ý mở 20 mục vừa copy; ghim để giữ lâu. Mục không ghim tự xoá sau 1 giờ (mật khẩu/OTP: 2 phút). Chỉ lưu trên máy. Plus: vừa copy STK/SĐT/OTP → chip “Dán …” hiện trên thanh gợi ý.": "The clipboard button on the suggestion bar opens your last 20 copies; pin items to keep them. Unpinned items are deleted after 1 hour (passwords/OTP: 2 minutes). Stored on device only. Plus: copy an account/phone number or OTP → a “Paste …” chip appears on the suggestion bar.",
        "iOS chỉ cho bàn phím đọc clipboard khi đang hiện và có Toàn quyền. Để tự ghi mục mới mà không bị hỏi: Cài đặt → VietTelex → Dán từ ứng dụng khác → Cho phép. Bỏ qua ô mật khẩu.": "iOS only lets the keyboard read the clipboard while it’s showing and has Full Access. To record new items without being asked: Settings → VietTelex → Paste from Other Apps → Allow. Password fields are skipped.",
        "Tắt Lịch sử clipboard sẽ xoá toàn bộ mục đã lưu ở lần mở bàn phím kế tiếp.": "Turning off Clipboard history deletes all saved items the next time the keyboard opens.",
        "Bàn phím không học từ bạn gõ và không lưu clipboard.": "The keyboard doesn’t learn from what you type and doesn’t save the clipboard.",
        "Riêng tư": "Privacy",

        // Gõ tắt
        "Gõ chữ tắt rồi dấu cách/dấu câu để bung: ko → không, Ko → Không, KO → KHÔNG. ⌫ ngay sau đó trả lại chữ đã gõ.": "Type a shortcut, then space/punctuation to expand it: ko → không, Ko → Không, KO → KHÔNG. ⌫ right after gives back what you typed.",
        "Trống": "Empty",
        "%@ mục": "%@ items",
        "Chữ tắt không được chứa khoảng trắng.": "Shortcuts can’t contain spaces.",
        "“%@” đã có — chạm dòng đó để sửa.": "“%@” already exists — tap that row to edit it.",
        "“%@” đã có.": "“%@” already exists.",
        "Tìm chữ tắt hoặc nội dung…": "Search shortcuts or text…",
        "Chữ tắt": "Shortcut",
        "Nội dung": "Text",
        "Lưu": "Save",
        "Huỷ": "Cancel",
        "Chưa có gõ tắt nào. Thêm bên dưới, hoặc bấm “Thêm bộ gợi ý”.": "No shortcuts yet. Add one below, or tap “Add suggested set”.",
        "Không tìm thấy.": "Nothing found.",
        "Bảng gõ tắt (%@)": "Shortcut table (%@)",
        "Chạm một dòng để sửa, vuốt trái để xoá.": "Tap a row to edit, swipe left to delete.",
        "Chữ tắt (vd: ko, cty, ->)": "Shortcut (e.g. ko, cty, ->)",
        "Nội dung đầy đủ (được nhiều dòng)": "Full text (multiple lines OK)",
        "Thêm": "Add",
        "Thêm mới": "Add new",
        "Bung khi gõ dấu cách, Enter hoặc dấu câu ngay sau chữ tắt. Viết chữ tắt thường để tự theo hoa/thường khi gõ. Chữ tắt có ký hiệu hoặc số (->, k2) bung khi gõ dấu cách. Không bung khi dính liền sau số hoặc / # @ (5h, /h3), trong ô mật khẩu, email, URL.": "Expands on space, Enter or punctuation right after the shortcut. Write shortcuts in lowercase to follow the case you type. Shortcuts with symbols or digits (->, k2) expand on space. Doesn’t expand right after a digit or / # @ (5h, /h3), or in password, email and URL fields.",
        "Bộ gợi ý đã có đủ.": "The suggested set is already there.",
        "Đã thêm %@ gõ tắt gợi ý.": "Added %@ suggested shortcuts.",
        "Thêm bộ gợi ý": "Add suggested set",
        "Nhập từ file…": "Import from file…",
        "File không có gõ tắt nào.": "The file has no shortcuts.",
        "Đã nhập %@ mục: %@ mới, %@ ghi đè.": "Imported %@ items: %@ new, %@ replaced.",
        "Xuất ra YAML…": "Export as YAML…",
        "Đã xuất %@ gõ tắt.": "Exported %@ shortcuts.",
        "Bộ gợi ý: %@. File YAML “chữ tắt: nội dung” dùng chung với VietTelex trên Mac và Android; nhập sẽ gộp (mục trùng lấy theo file).": "Suggested set: %@. The “shortcut: text” YAML file is shared with VietTelex on Mac and Android; importing merges (duplicates take the file’s value).",

        // Mẫu câu
        "Chưa có nội dung mẫu câu — nhập câu vào ô bên phải label.": "The snippet is empty — type the text in the field right of the label.",
        "Không thêm: mẫu câu này đã có ở dòng %@%@.": "Not added: this snippet already exists on line %@%@.",

        // Giao diện
        "Áp dụng lần mở bàn phím kế tiếp.": "Applies the next time the keyboard opens.",
        "Theme có nhãn Plus và ảnh nền thuộc VietTelex Plus. Hệ thống, Tối OLED và Tương phản cao luôn miễn phí.": "Themes marked Plus and wallpapers are part of VietTelex Plus. System, OLED Dark and High Contrast are always free.",
        "Đổi ảnh nền": "Change wallpaper",
        "Chọn ảnh nền từ Thư viện": "Choose wallpaper from Photos",
        "Dùng ảnh nền": "Use wallpaper",
        "Nền theo hệ thống": "System background",
        "Giữ màu phím của theme, nền dùng lớp kính bàn phím của iOS — liền màu với dải 🌐 🎤 bên dưới.":
            "Keeps the theme's key colors; the background uses the iOS keyboard glass — seamless with the 🌐 🎤 bar below.",
        "Độ tối lớp phủ: %@%": "Overlay darkness: %@%",
        "Độ mờ ảnh: %@": "Blur: %@",
        "Xoá ảnh nền": "Remove wallpaper",
        "Chỉnh ảnh": "Adjust photo",
        "Chỉnh ảnh nền": "Adjust wallpaper",
        "Xong": "Done",
        "Về khung giữa": "Reset to centre",
        "Khung ảnh nền bàn phím": "Keyboard wallpaper frame",
        "Kéo để dời ảnh, chụm hai ngón để phóng to. Chạm hai lần để về khung giữa.": "Drag to move the photo, pinch to zoom. Double-tap to reset to the centre.",
        "Ảnh được thu nhỏ và nén ngay trên máy, không gửi đi đâu. Lớp phủ giúp chữ trên phím dễ đọc.": "The image is resized and compressed on device and never sent anywhere. The overlay keeps key labels readable.",
        "Độ trong suốt": "Transparency",
        "Phím: nền, ảnh nền, nền và viền phím — 100% chỉ còn chữ. Ký tự: chữ và biểu tượng trên phím — 100% là phím trơn không chữ. iOS luôn giữ lớp kính mờ phía sau bàn phím.": "Keys: background, wallpaper, key fill and border — at 100% only the labels remain. Labels: letters and icons on the keys — at 100% the keys are blank. iOS always keeps the frosted glass behind the keyboard.",
        "Chuẩn": "Standard",
        "%+d pt mỗi hàng (%+d pt cả bàn phím)": "%+d pt per row (%+d pt for the keyboard)",
        "Logo mờ ở góc phải phím cách.": "A faint logo in the right corner of the space bar.",
        "Bàn phím": "Keyboard",
        "Về theme Hệ thống, tắt ảnh nền (ảnh vẫn giữ để bật lại), độ tối/mờ và độ trong suốt về mặc định. Chiều cao hàng và logo giữ nguyên.": "Back to the System theme, wallpaper off (the image is kept to turn back on), darkness/blur and transparency to defaults. Row height and logo stay as they are.",
        "Khôi phục giao diện gốc?": "Reset appearance?",
        "Khôi phục": "Reset",
        "Theme, ảnh nền và độ trong suốt về mặc định. Ảnh nền không bị xoá.": "Theme, wallpaper and transparency go back to defaults. The wallpaper image isn’t deleted.",
        ", đang chọn": ", selected",
        "Không đọc được ảnh này.": "Couldn’t read this image.",
        "Không truy cập được App Group.": "Couldn’t access the App Group.",
        "Không lưu được ảnh: %@": "Couldn’t save the image: %@",
        "dấu cách": "space",

        // Từ điển cá nhân
        "Bàn phím chỉ lưu được từ đã học khi bật \"Cho phép Toàn quyền\" (Cài đặt → Chung → Bàn phím → Bàn phím → VietTelex). Từ thêm tay ở đây vẫn dùng được.": "The keyboard can only save learned words with \"Allow Full Access\" on (Settings → General → Keyboard → Keyboards → VietTelex). Words you add here work either way.",
        "Thêm từ": "Add word",
        "Tên riêng, thuật ngữ… (một từ, chỉ chữ cái). Từ thêm tay được gợi ý ngay khi gõ vài chữ đầu.": "Names, terms… (one word, letters only). Words you add are suggested after the first few letters.",
        "thêm tay": "added",
        "Chưa có từ nào — gõ bằng VietTelex để bàn phím học.": "No words yet — type with VietTelex and the keyboard will learn.",
        "Không có từ khớp.": "No matching words.",
        "Từ đã học (%@)": "Learned words (%@)",
        "Kết quả (%@)": "Results (%@)",
        "Vuốt trái để xoá — xoá một từ cũng xoá các cặp/bộ ba từ đi kèm nó. Mọi dữ liệu chỉ nằm trên máy.": "Swipe left to delete — deleting a word also deletes the word pairs/triples that include it. All data stays on device.",
        "Chạm lần nữa để xoá tất cả": "Tap again to delete everything",
        "Xoá tất cả từ đã học": "Delete all learned words",
        "Tìm từ": "Search words",
        "Không mở được dữ liệu (App Group).": "Couldn’t open the data (App Group).",
        "Đã thêm “%@”.": "Added “%@”.",
        "Chỉ nhận một từ gồm chữ cái (tối đa %@ ký tự).": "Only a single word of letters is accepted (up to %@ characters).",

        // App chính
        "Kiểu Gõ": "Typing",
        "Tính Năng": "Features",
        "Mẫu Câu": "Snippets",
        "Giới Thiệu": "About",
        "Thử gõ tại đây…": "Try typing here…",
        "Thử gõ": "Try it",
        "Bấm 🌐 dưới bàn phím để chuyển sang Tiếng Việt (VietTelex), rồi gõ thử: vieejt → việt.": "Tap 🌐 below the keyboard to switch to Tiếng Việt (VietTelex), then try: vieejt → việt.",
        "Bàn phím Telex tiếng Việt": "Vietnamese Telex keyboard",
        "Hướng dẫn sử dụng": "User guide",
        "Học gõ Telex": "Learn Telex",
        "Mã nguồn trên GitHub": "Source code on GitHub",
        "Tài nguyên": "Resources",
        "Phiên bản": "Version",
        "Không thu thập dữ liệu · Không theo dõi · Mã nguồn mở": "No data collection · No tracking · Open source",
        "Dữ liệu gõ vuốt: thống kê từ Wikipedia, Wikisource… tiếng Việt (CC BY-SA 4.0) và Tatoeba (CC BY 2.0 FR)": "Swipe data: statistics from Vietnamese Wikipedia, Wikisource… (CC BY-SA 4.0) and Tatoeba (CC BY 2.0 FR)",
        "Toàn quyền Truy cập là tuỳ chọn — chỉ cần cho Rung phím và Mẫu câu động (https://); VietTelex không dùng quyền này cho bất kỳ việc gì khác.": "Full Access is optional — it’s only needed for Haptic feedback and Dynamic snippets (https://); VietTelex doesn’t use it for anything else.",
        "Giới thiệu": "About",
        "Đã thêm mẫu câu (dòng %@).": "Snippet added (line %@).",
        "Chưa có mẫu câu nào.": "No snippets yet.",
        "Mẫu câu (%@)": "Snippets (%@)",
        "Bấm ☰ trên bàn phím để chèn nhanh. Chạm một dòng để sửa, vuốt trái để xoá. Label (emoji/chữ ngắn) giúp bubble trên bàn phím gọn hơn.": "Tap ☰ on the keyboard to insert quickly. Tap a row to edit, swipe left to delete. A label (emoji/short text) keeps the keyboard bubbles compact.",
        "Thêm mẫu câu…": "Add a snippet…",
        "Thêm mẫu câu": "Add snippet",
        "Ô nhỏ bên trái là label (không bắt buộc).": "The small field on the left is the label (optional).",
        "Mẫu câu động": "Dynamic snippets",
        "Mẫu câu động (https://)": "Dynamic snippets (https://)",
        "Mẫu có nội dung bắt đầu bằng https:// sẽ fetch dữ liệu NGAY LÚC BẤM và chèn kết quả (tối đa 1000 bytes) — ví dụ 🌐 IP chèn địa chỉ IP hiện tại. Chưa cấp Toàn quyền thì bàn phím không có mạng, bấm sẽ chèn chính URL.": "Snippets whose text starts with https:// fetch data THE MOMENT YOU TAP and insert the result (up to 1000 bytes) — e.g. 🌐 IP inserts your current IP address. Without Full Access the keyboard has no network, so tapping inserts the URL itself.",
        "Đã thêm %@/%@ mẫu": "Added %@/%@ snippets",
        " (trùng bị bỏ qua).": " (duplicates skipped).",
        "Đã export %@ mẫu.": "Exported %@ snippets.",
        "YAML phẳng, mỗi dòng “- \"👋 | Chào buổi sáng\"” (label | câu) hoặc “- \"câu\"”. Import gộp thêm, không thay thế.": "Flat YAML, one line each: “- \"👋 | Good morning\"” (label | text) or “- \"text\"”. Import merges, it doesn’t replace.",
        "Để dán nhanh từ thanh gợi ý": "To paste quickly from the suggestion bar",
        "1. Bàn phím → VietTelex → bật Cho phép Toàn quyền": "1. Keyboards → VietTelex → turn on Allow Full Access",
        "2. Dán từ ứng dụng khác → chọn Cho phép": "2. Paste from Other Apps → choose Allow",
        "Nếu chưa thấy mục 2: bấm nút Dán trên bàn phím một lần để iOS hỏi, rồi quay lại đây.": "Don’t see step 2? Tap the Paste button on the keyboard once so iOS asks, then come back here.",
        "Mở Cài đặt VietTelex": "Open VietTelex Settings",
        "Bàn phím đã bật": "Keyboard enabled",
        "Thử gõ ngay bên dưới.": "Try typing below.",
        "Bật bàn phím VietTelex": "Enable the VietTelex keyboard",
        "Bật bàn phím trong Cài đặt": "Enable the keyboard in Settings",
        "Thử gõ ngay bên dưới": "Try typing below",
        "Cài đặt → Cài đặt chung → Bàn phím → Bàn phím": "Settings → General → Keyboard → Keyboards",
        "Thêm bàn phím mới… → Tiếng Việt (VietTelex)": "Add New Keyboard… → Tiếng Việt (VietTelex)",
        "Khi gõ, bấm 🌐 để chuyển sang VietTelex": "While typing, tap 🌐 to switch to VietTelex",
        "Mở Cài đặt": "Open Settings",
        "Đã cấp Toàn quyền Truy cập.": "Full Access granted.",
        "Nếu đã bật rồi: mở bàn phím VietTelex một lần (gõ ở app bất kỳ) để app nhận trạng thái quyền.": "Already on? Open the VietTelex keyboard once (type in any app) so the app picks up the permission.",
        "%@ cần Toàn quyền Truy cập. Bật trong Cài đặt → Bàn phím → Cho phép Toàn quyền Truy cập. VietTelex không thu thập dữ liệu.": "%@ needs Full Access. Turn it on in Settings → Keyboards → Allow Full Access. VietTelex doesn’t collect any data.",
        "Mở Cài đặt để cấp Toàn quyền": "Open Settings to grant Full Access",
        "Kiểu gõ": "Input method",
        "Gõ dấu bằng số khi đang gõ một từ: 1 sắc, 2 huyền, 3 hỏi, 4 ngã, 5 nặng, 6 mũ (â ê ô), 7 móc (ơ ư), 8 trăng (ă), 9 đ, 0 xoá dấu — tie6ng1 vie6t5 → tiếng việt. Ngoài từ, phím số vẫn gõ ra số. Chọn VNI tự bật Hàng phím số (tắt được ở Tính năng → Phím & cử chỉ).": "Type tones with digits inside a word: 1 sắc, 2 huyền, 3 hỏi, 4 ngã, 5 nặng, 6 circumflex (â ê ô), 7 horn (ơ ư), 8 breve (ă), 9 đ, 0 removes the tone — tie6ng1 vie6t5 → tiếng việt. Outside a word, digit keys type digits. Choosing VNI turns on the Number row (turn it off in Features → Keys & gestures).",
        "Telex đơn giản": "Simple Telex",
        "Phím w đứng lẻ giữ nguyên là w, không thành ư.": "A lone w stays w instead of becoming ư.",
        "Bỏ dấu tự do": "Free tone placement",
        "Phím dấu đặt đâu cũng được, không cần đúng thứ tự.": "Tone keys can go anywhere in the word, in any order.",
        "Gõ nhanh (Quick Telex)": "Quick Telex",
        "Phụ âm đôi đầu từ thành phụ âm ghép: cc → ch, nn → ng, tt → th…": "Doubled initial consonants become digraphs: cc → ch, nn → ng, tt → th…",
        "Bỏ dấu kiểu mới": "Modern tone placement",
        "hoà, thuý thay vì hòa, thúy.": "hoà, thuý instead of hòa, thúy.",
        "Tự động viết hoa đầu câu": "Auto-capitalize sentences",
        "Bật shift ở đầu ô, sau . ! ? và khi xuống dòng. Công tắc “Tự động viết hoa” trong Cài đặt → Bàn phím của iOS không áp dụng cho bàn phím bên thứ ba — tắt ở đây.": "Turns on shift at the start of a field, after . ! ? and on new lines. The iOS “Auto-Capitalization” switch in Settings → Keyboard doesn’t apply to third-party keyboards — turn it off here.",
        "Quyết định theo ngữ cảnh": "Context-aware decisions",
        "Sau một từ tiếng Anh, từ nhập nhằng kế tiếp mà chuỗi phím tạo thành một từ tiếng Anh sẽ được giữ tiếng Anh thay vì tiếng Việt — “he is” → “he is”, không phải “he í”. Sau từ tiếng Việt hoặc không rõ thì để tiếng Việt — “sao í”.": "After an English word, an ambiguous next word whose keys spell an English word stays English instead of Vietnamese — “he is” → “he is”, not “he í”. After a Vietnamese or unclear word it stays Vietnamese — “sao í”.",
        "Gợi ý sửa lỗi chạm trượt": "Typo suggestions",
        "Khi từ đang gõ không phải tiếng Việt, gợi ý từ đúng nếu bạn lỡ chạm phím bên cạnh: nbjeeuf → nhiều, ohims → phím, cahcs → cách. Chạm gợi ý để thay.": "When the word you’re typing isn’t Vietnamese, suggest the right word if you hit a neighboring key: nbjeeuf → nhiều, ohims → phím, cahcs → cách. Tap the suggestion to replace.",
        "Chính tả teencode": "Teencode spelling",
        "Chấp nhận cách viết khi chat: w/z/k thay cho qu/d/c (wá, zui zẻ, kó) và bíe, thík, gòy, ừk. Tắt = chỉ chính tả chuẩn, từ tiếng Anh như was, war, zoo giữ nguyên.": "Accept chat-style spelling: w/z/k for qu/d/c (wá, zui zẻ, kó) and bíe, thík, gòy, ừk. Off = standard spelling only; English words like was, war, zoo stay as typed.",
        "Debug mode — ghi log chạm phím": "Debug mode — log key taps",
        "Ghi thời điểm chạm, độ trễ và số phím vào log trong app — KHÔNG ghi nội dung bạn gõ. Cần \"Cho phép Toàn quyền\" cho bàn phím. Tắt + Xoá log khi xong.": "Logs tap times, latency and key counts in the app — NOT what you type. Needs \"Allow Full Access\" for the keyboard. Turn off + Clear log when done.",
        "Hiện log (tự copy vào clipboard)": "Show log (copies to clipboard)",
        "Bật để xem log bên dưới và copy toàn bộ — tắt rồi bật lại để tải log mới.": "Turn on to view the log below and copy all of it — toggle off and on to reload.",
        "Xoá log": "Clear log",
        "Bật để xoá log cũ trước khi thử lại.": "Turn on to clear the old log before trying again.",
        "Chưa có log. Bật \"Cho phép Toàn quyền\" cho bàn phím VietTelex (Cài đặt → Chung → Bàn phím → Bàn phím → VietTelex), rồi gõ thử.": "No log yet. Turn on \"Allow Full Access\" for the VietTelex keyboard (Settings → General → Keyboard → Keyboards → VietTelex), then type something.",
        "%@ dòng — đã copy vào clipboard.\n\n": "%@ lines — copied to the clipboard.\n\n",
        "Gỡ lỗi": "Debugging",

        // Bàn phím
        "Dán OTP %@": "Paste OTP %@",
        "Dán SĐT %@": "Paste phone %@",
        "Dán STK %@": "Paste account %@",
        "iOS chỉ cho bàn phím đọc clipboard khi bàn phím đang hiện, có Toàn quyền truy cập và đã chọn \"Cho phép dán\". Mục copy lúc bàn phím ẩn được ghi khi bạn mở lại bàn phím (hoặc khi chạm Dán). Lưu chỉ trên máy; mục không ghim tự xoá sau 1 giờ.": "iOS only lets the keyboard read the clipboard while it’s showing, with Full Access and \"Allow Paste\" chosen. Things copied while the keyboard is hidden are recorded when you open it again (or tap Paste). Stored on device only; unpinned items are deleted after 1 hour.",
        "Xoá hết": "Clear all",
        "Đóng clipboard": "Close clipboard",
        "Clipboard · ẩn danh (không lưu)": "Clipboard · incognito (not saved)",
        "Chưa có mục nào. Copy nội dung rồi mở bàn phím để ghi lại.": "Nothing here yet. Copy something, then open the keyboard to record it.",
        "Mục ẩn, chạm để dán": "Hidden item, tap to paste",
        "Dán: %@": "Paste: %@",
        "Bỏ ghim": "Unpin",
        "Xoá mục": "Delete item",
        "Tìm emoji": "Search emoji",
        "Kaomoji và ký tự đặc biệt": "Kaomoji and symbols",
        "Xoá ô tìm": "Clear search",
        "Gõ để tìm: tim, chó, cười…": "Type to search: heart, dog, laugh…",
        "Không thấy emoji": "No emoji found",
        "Hệ thống": "System",
        "Tối OLED": "OLED Dark",
        "Tương phản cao": "High Contrast",
        "Hồng đào": "Peach",
        "Bạc hà": "Mint",
        "Trời xanh": "Sky",
        "Oải hương": "Lavender",
        "Kính": "Glass",
        "Đóng mẫu câu": "Close snippets",
        "Giữ lâu để bật hoặc tắt chế độ một tay": "Long-press to toggle one-handed mode",
        "Thu gọn thanh gợi ý": "Collapse suggestion bar",
        "Mở thanh gợi ý": "Expand suggestion bar",
        "Dán nội dung vừa copy": "Paste what you just copied",
        "Dán": "Paste",
        "Nội dung vừa copy": "Just copied",
        "Ảnh vừa copy": "Image just copied",
        "Giữ ô nhập → Dán": "Hold the field → Paste",
        "Ảnh vừa copy — giữ ô nhập rồi chọn Dán": "Image just copied — hold the text field, then choose Paste",
        "Đổi bên bàn phím một tay": "Switch one-handed side",
        "Thoát chế độ một tay": "Exit one-handed mode",
        "\u{2039} Mẫu câu": "\u{2039} Snippets",
        "Aa Công cụ văn bản": "Aa Text tools",
        "Quản lý mẫu câu": "Manage snippets",
        "Ký hiệu": "Symbols",
        "Số": "Numbers",
        "Xuống dòng": "Return",
        "Chữ": "Letters",
        "Bàn phím tiếp theo": "Next keyboard",
        "Xoá ô nhập": "Clear field",
        "Dấu cách": "Space",
        "Ẩn bàn phím": "Hide keyboard",
        "Xoá": "Delete",
        "\u{232B} %@ từ": "\u{232B} %@ words",
        "\u{21A9}\u{FE0E} Khôi phục": "\u{21A9}\u{FE0E} Restore",
        "\u{21A9}\u{FE0E} Hoàn tác": "\u{21A9}\u{FE0E} Undo",
        "Thêm dấu": "Add tones",
        "Tối đa %@ mục ghim — VietTelex Plus ghim không giới hạn.": "Up to %@ pinned items — VietTelex Plus pins without limit.",
        "thường": "lower",
        "Hoa Đầu Từ": "Title Case",
        "Hoa đầu câu": "Sentence case",
        "Xoá dấu": "Remove tones",

        // Plus — tính năng
        "Theme cao cấp & ảnh nền": "Premium themes & wallpaper",
        "Thêm dấu cả câu": "Add tones to a sentence",
        "Clipboard nâng cao": "Advanced clipboard",
        "Công cụ văn bản": "Text tools",
        "Huy hiệu cảm ơn": "Thank-you badge",
        "Thêm bộ màu bàn phím và đặt ảnh riêng làm nền.": "More keyboard color themes and your own photo as the background.",
        "Gõ không dấu cả câu, một chạm thêm dấu.": "Type a whole sentence without tones, add them with one tap.",
        "Ghim không giới hạn, chip tách số tài khoản, số điện thoại, mã OTP.": "Unlimited pins; chips that pick out account numbers, phone numbers and OTP codes.",
        "Cài đặt, gõ tắt và từ đã học theo bạn sang máy khác.": "Settings, shortcuts and learned words follow you to other devices.",
        "Đổi HOA/thường, hoa đầu từ/đầu câu, xoá dấu tiếng Việt.": "Switch UPPER/lower case, title/sentence case, strip Vietnamese tones.",
        "Dấu ★ nhỏ trong app — lời cảm ơn vì đã ủng hộ.": "A small ★ in the app — a thank-you for your support.",
        // Plus — cách dùng (28/09/2026)
        "Cách dùng: Tính Năng → Giao diện → chọn theme hoặc ảnh nền.": "How to use: Features → Appearance → pick a theme or a wallpaper.",
        "Cách dùng: gõ không dấu cả câu (hom nay troi dep), gõ dấu cách rồi chạm chip “Thêm dấu” ở đầu thanh gợi ý. Cần bật chip bên dưới.": "How to use: type a whole sentence without tones (hom nay troi dep), press space, then tap the “Add tones” chip at the start of the suggestion bar. Turn the chip on below.",
        "Cách dùng: bật Lịch sử clipboard (Tính Năng → Riêng tư & clipboard), chạm nút clipboard trên thanh gợi ý. Copy STK/SĐT/OTP → chip “Dán …” hiện trên thanh gợi ý.": "How to use: turn on Clipboard history (Features → Privacy & clipboard), then tap the clipboard button on the suggestion bar. Copy an account/phone number or OTP → a “Paste …” chip appears on the suggestion bar.",
        "Cách dùng: Tính Năng → Sao lưu & đồng bộ → bật Đồng bộ iCloud.": "How to use: Features → Backup & sync → turn on iCloud sync.",
        "Cách dùng: chạm ☰ trên thanh gợi ý → chip “Aa Công cụ văn bản” đầu lưới mẫu câu. Áp lên đoạn đang chọn hoặc câu trước con trỏ.": "How to use: tap ☰ on the suggestion bar → the “Aa Text tools” chip at the top of the templates grid. Applies to the selection or the sentence before the cursor.",
        "Tự hiện sau khi mua.": "Shows up automatically after purchase.",
        "Bật chip “Thêm dấu”": "Turn on the “Add tones” chip",
        "Bật chip “Thêm dấu”?": "Turn on the “Add tones” chip?",
        "Bật ngay": "Turn on",
        "Để sau": "Later",
        "Gõ không dấu cả câu, gõ dấu cách rồi chạm chip “Thêm dấu” ở đầu thanh gợi ý. Chip đang tắt — bật ngay? (Đổi lại ở Tính Năng → Gợi ý & từ điển.)": "Type a whole sentence without tones, press space, then tap the “Add tones” chip at the start of the suggestion bar. The chip is off — turn it on now? (Change it later in Features → Suggestions & dictionary.)",
    ]
    // swiftlint:enable line_length
}

/// Chuỗi giao diện theo ngôn ngữ đã chọn (khoá = chữ tiếng Việt gốc).
func L(_ vi: String) -> String { L10n.t(vi) }

/// Như trên, thay `%@` bằng tham số.
func L(_ vi: String, _ args: Any...) -> String { L10n.format(L10n.t(vi), args) }

/// Chỉ đánh dấu khoá cần dịch (trả nguyên văn) — dịch lúc hiển thị bằng `L(key)`.
func LK(_ vi: String) -> String { vi }
