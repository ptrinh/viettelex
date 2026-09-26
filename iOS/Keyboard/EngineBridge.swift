// EngineBridge — pure glue between TelexEngine and an abstract text proxy.
// No UIKit: fully unit-testable with a mock proxy. The keyboard view calls
// press(_:); the bridge feeds the engine and applies the minimal diff
// (deleteBackward × N + insertText) — the exact edit model iOS gives us.
import Foundation
import TelexCore

/// The slice of UITextDocumentProxy the bridge needs.
protocol TextProxyLike {
    func insertText(_ text: String)
    func deleteBackward()
    var isSecure: Bool { get }
    /// Chữ trước con trỏ (UITextDocumentProxy.documentContextBeforeInput). nil =
    /// host không cho biết. Chỉ đọc trước lệnh xoá ≥ CompositionSync.verifyThreshold.
    var contextBeforeInput: String? { get }
    /// Chữ SAU con trỏ (documentContextAfterInput). nil = không biết / hết văn bản.
    /// Chỉ đọc ở đường sửa dấu từ đã gõ (không phải hot path).
    var contextAfterInput: String? { get }
    /// Đang có vùng chọn khác rỗng (selectedText, iOS 16+).
    var hasSelection: Bool { get }
}

/// Shared settings (App Group on device; in-memory defaults in tests).
struct KeyboardSettings {
    // Defaults iOS (user 2026-07-24): Telex đơn giản BẬT + bỏ dấu tự do BẬT +
    // tự khôi phục tiếng Anh BẬT. (Khác macOS: simpleTelex mặc định tắt.)
    var freeMarking = true
    var simpleTelex = true
    var liveSpellCheck = true
    var autoRestore = true
    var quickTelex = false
    var modernTone = false
    /// Chính tả teencode (wá, zui, kó, bíe, thík, gòy, ừk) — mặc định TẮT như macOS
    /// 1.7.11 (maintainer 25/09/2026, issue #94).
    var teencode = false
    var showSuggestions = true
    var learnWords = true      // đi theo showSuggestions (không còn toggle riêng)
    var filterSensitive = true
    var hapticFeedback = false // rung phím — chỉ hoạt động khi có Full Access
    /// Gợi ý sửa lỗi chạm trượt phím kề (AdjacentKeyFixer) — mặc định BẬT (25/09/2026).
    var autoFixAdjacent = true
    /// Quyết định theo ngữ cảnh (như macOS, mặc định BẬT): sau một từ tiếng Anh, từ
    /// mơ hồ kế tiếp giữ tiếng Anh ("he is" → he is, không phải "he í").
    var contextualEnglish = true
    /// Sửa dấu từ đã gõ xong (mặc định BẬT, user 26/09/2026): ⌫ ngay sau space/dấu
    /// câu mở lại từ vừa chốt, và phím dấu thanh ngay sau một từ nạp lại từ đó.
    var reEditWord = true
    /// Gõ vuốt (thử nghiệm, mặc định TẮT): tắt ⇒ không dựng template, không theo dõi
    /// touchesMoved thêm — 0 RAM/CPU.
    var swipeTyping = false

    static func load() -> KeyboardSettings {
        var s = KeyboardSettings()
        guard let d = UserDefaultsProvider.shared else { return s }
        if d.object(forKey: "freeMarking") != nil { s.freeMarking = d.bool(forKey: "freeMarking") }
        if d.object(forKey: "simpleTelex") != nil { s.simpleTelex = d.bool(forKey: "simpleTelex") }
        if d.object(forKey: "liveSpellCheck") != nil { s.liveSpellCheck = d.bool(forKey: "liveSpellCheck") }
        if d.object(forKey: "autoRestore") != nil { s.autoRestore = d.bool(forKey: "autoRestore") }
        if d.object(forKey: "quickTelex") != nil { s.quickTelex = d.bool(forKey: "quickTelex") }
        if d.object(forKey: "modernTone") != nil { s.modernTone = d.bool(forKey: "modernTone") }
        if d.object(forKey: "teencode") != nil { s.teencode = d.bool(forKey: "teencode") }
        if d.object(forKey: "showSuggestions") != nil { s.showSuggestions = d.bool(forKey: "showSuggestions") }
        if d.object(forKey: "filterSensitive") != nil { s.filterSensitive = d.bool(forKey: "filterSensitive") }
        if d.object(forKey: "hapticFeedback") != nil { s.hapticFeedback = d.bool(forKey: "hapticFeedback") }
        if d.object(forKey: "autoFixAdjacent") != nil { s.autoFixAdjacent = d.bool(forKey: "autoFixAdjacent") }
        if d.object(forKey: "contextualEnglish") != nil { s.contextualEnglish = d.bool(forKey: "contextualEnglish") }
        if d.object(forKey: "reEditWord") != nil { s.reEditWord = d.bool(forKey: "reEditWord") }
        if d.object(forKey: "swipeTyping") != nil { s.swipeTyping = d.bool(forKey: "swipeTyping") }
        s.learnWords = s.showSuggestions   // bật gợi ý = bật học (quyết định 2026-07-24)
        return s
    }
}

/// Indirection so tests never touch the real App Group.
enum UserDefaultsProvider {
    nonisolated(unsafe) static var shared: UserDefaults? =
        UserDefaults(suiteName: "group.com.viettelex")
}

final class EngineBridge {
    private var engine = TelexEngine()
    private let settings: KeyboardSettings

    /// Field không autocorrect (mã/username, autocorrectionType == .no): gõ
    /// LITERAL, bỏ qua engine Telex — như field mật khẩu. (Tắt autoRestore thôi
    /// thì diacritic lại DÍNH, ngược ý.) Set theo field ở viewWillAppear.
    var passthrough = false

    /// Cho phép "với" lại từ đã chốt trước con trỏ: ⌫ mở lại từ vừa chốt, và phím
    /// dấu/mũ nạp lại từ ngay trước con trỏ (seed). Controller TẮT ở omnibox
    /// (keyboardType .webSearch): inline autocomplete tự sửa chữ bên dưới mình.
    var reachBackAllowed = true

    /// Thao tác cuối của bridge là chèn ký tự ranh giới → chắc chắn ký tự trước con
    /// trỏ KHÔNG phải chữ: phím đầu từ mới khỏi phải đọc context (XPC) để thử seed.
    private var lastWasOwnBoundary = false

    /// Checkpoint của phím CHỮ gần nhất — để HUỶ đúng phím đó khi nó hoá ra là cử chỉ
    /// (iPad vuốt xuống ra ký tự phụ; sau này gõ vuốt). KHÔNG dùng ⌫: engine.backspace()
    /// xoá chữ cuối ĐANG HIỆN, không gỡ phím vừa gõ — "tieng" + vuốt s từng ra "tiến#"
    /// (26/09/2026). Mọi thao tác khác ngoài letter() đều xoá checkpoint.
    private struct LetterUndo {
        let engine: TelexEngine
        let removed: String      // chữ phím đó đã xoá khỏi màn hình
        let inserted: String     // chữ phím đó đã chèn
        let ownBoundary: Bool
        var swipe: SwipeOpen? = nil
        var settled: SettledCommit? = nil
    }
    private var letterUndo: LetterUndo?

    // MARK: gõ vuốt — từ vuốt là composition ĐANG MỞ (seed)
    /// Từ vuốt vừa chèn vẫn đang mở trong engine: phím dấu Telex sửa được, gợi ý thay
    /// được, ⌫ ĐẦU TIÊN (`fresh`) xoá cả từ. `accepted` = user đã chọn từ này trên thanh
    /// gợi ý (học weight 2 khi chốt).
    struct SwipeOpen: Equatable {
        var fresh = true
        var accepted = false
    }
    struct SettledCommit: Equatable {
        let word: String
        let accepted: Bool
    }
    private var swipeOpen: SwipeOpen?
    /// Từ vuốt đã chốt bởi phím chữ gõ tiếp (dấu cách treo) nhưng CHƯA giao cho caller
    /// học: phím đó có thể còn bị huỷ (nó là chữ đầu của một cú vuốt mới) — khi đó từ
    /// vuốt mở lại, học sớm là học hai lần. Caller lấy bằng `takeSettledCommit()` ở
    /// thao tác kế tiếp (lúc đó phím chữ kia không còn huỷ được).
    private var settledCommit: SettledCommit?

    init(settings: KeyboardSettings = .load()) {
        self.settings = settings
        engine.freeMarking = settings.freeMarking
        engine.simpleTelex = settings.simpleTelex
        engine.liveSpellCheck = settings.liveSpellCheck
        engine.quickTelex = settings.quickTelex
        engine.modernTone = settings.modernTone
        engine.teencode = settings.teencode
        engine.contextualEnglish = settings.contextualEnglish
    }

    /// A letter key ("a"…"z", already cased by the shift state).
    func letter(_ ch: Character, proxy: TextProxyLike) {
        letterUndo = nil
        guard !proxy.isSecure, !passthrough else {
            proxy.insertText(String(ch))
            letterUndo = LetterUndo(engine: engine, removed: "", inserted: String(ch),
                                    ownBoundary: lastWasOwnBoundary)
            return
        }
        if swipeOpen != nil {
            letterAfterSwipe(ch, proxy: proxy)
            return
        }
        letterCore(ch, proxy: proxy)
        letterUndo?.settled = settledCommit
    }

    /// Phím chữ ngay sau từ vuốt đang mở: phím dấu Telex (s f r x j z w) BIẾN ĐỔI từ ⇒
    /// sửa từ đó (viet vuốt → việt, + s → viết). Phím khác (hoặc phím dấu không đổi
    /// gì) ⇒ dấu cách treo: chốt từ vuốt + " " rồi phím này mở từ mới. Cả hai huỷ được
    /// trọn vẹn bằng undoLastLetter (chữ đầu của một cú vuốt mới).
    private func letterAfterSwipe(_ ch: Character, proxy: TextProxyLike) {
        guard let open = swipeOpen else { return }
        let snapshot = engine
        let before = engine.composed
        if Self.isReEditKey(ch) {
            let action = engine.feed(ch)
            if case .replace(let bs, let insert) = action, bs > 0,
               engine.composed != before + String(ch),
               safeToApply(action, expected: before, proxy: proxy) {
                apply(action, literal: String(ch), proxy: proxy)
                letterUndo = LetterUndo(engine: snapshot, removed: String(before.suffix(bs)),
                                        inserted: insert, ownBoundary: false,
                                        swipe: open, settled: settledCommit)
                swipeOpen = SwipeOpen(fresh: false, accepted: open.accepted)
                lastWasOwnBoundary = false
                return
            }
            engine = snapshot
        }
        let settledBefore = settledCommit
        let final = boundary(" ", proxy: proxy)      // xoá swipeOpen + letterUndo
        settledCommit = SettledCommit(word: final, accepted: open.accepted)
        letterCore(ch, proxy: proxy)
        guard let u = letterUndo, u.removed.isEmpty else { letterUndo = nil; return }
        // Huỷ gộp: màn hình "before" → "final" + " " + chữ phím này.
        letterUndo = LetterUndo(engine: snapshot, removed: before, inserted: final + " " + u.inserted,
                                ownBoundary: false, swipe: open, settled: settledBefore)
    }

    /// Lấy (một lần) từ vuốt đã chốt bởi dấu cách treo — gọi ở đầu thao tác kế tiếp.
    func takeSettledCommit() -> SettledCommit? {
        defer { settledCommit = nil }
        return settledCommit
    }

    /// Từ vuốt đang mở (chưa chốt) — controller hiện thanh biến thể / học weight.
    var isSwipeWordOpen: Bool { swipeOpen != nil }
    /// Từ đang mở là từ user chọn trên thanh gợi ý (học weight 2 khi chốt).
    var openWordAccepted: Bool { swipeOpen?.accepted ?? false }

    /// Chèn từ vuốt. Đang gõ dở một từ (kể cả từ vuốt trước) ⇒ chốt nó + " " (trả về
    /// để caller học); không thì thêm " " nếu ngay trước con trỏ là chữ/dấu câu (dấu
    /// cách treo). Sau đó chèn `word` và SEED engine bằng nó để từ vẫn là composition
    /// đang mở. Seed không round-trip, hoặc boundary sẽ auto-restore nó ⇒ chữ thường
    /// (không mở), vẫn chèn.
    @discardableResult
    func insertSwipeWord(_ word: String, accepted: Bool = false,
                         proxy: TextProxyLike) -> SettledCommit? {
        letterUndo = nil
        var committed = settledCommit
        settledCommit = nil
        if !engine.isEmpty {
            let wasAccepted = swipeOpen?.accepted ?? false
            let final = boundary(" ", proxy: proxy)
            if !final.isEmpty { committed = SettledCommit(word: final, accepted: wasAccepted) }
        } else if SwipeSpacing.needsLeadingSpace(before: proxy.contextBeforeInput) {
            engine.forgetLastCommit()                  // ⌫ không mở lại từ cũ qua " " của mình
            proxy.insertText(" ")
        }
        proxy.insertText(word)
        openSwipeWord(word, accepted: accepted)
        return committed
    }

    /// Thay từ vuốt đang mở bằng `word` (biến thể trên thanh gợi ý). false = không còn
    /// mở / màn hình lệch (caller xử lý như gợi ý thường).
    func replaceSwipeWord(with word: String, proxy: TextProxyLike) -> Bool {
        guard swipeOpen != nil, !engine.isEmpty else { return false }
        let composed = engine.composed
        guard CompositionSync.canDelete(composed.count, expected: composed,
                                        context: { proxy.contextBeforeInput }) else {
            reset()
            return false
        }
        letterUndo = nil
        for _ in 0..<composed.count { proxy.deleteBackward() }
        proxy.insertText(word)
        openSwipeWord(word, accepted: true)
        return true
    }

    private func openSwipeWord(_ word: String, accepted: Bool) {
        lastWasOwnBoundary = false
        if !passthrough, engine.seed(word),
           engine.peekCommitText(autoRestore: settings.autoRestore) == word {
            swipeOpen = SwipeOpen(fresh: true, accepted: accepted)
        } else {
            engine.reset()
            swipeOpen = nil
        }
    }

    private func letterCore(_ ch: Character, proxy: TextProxyLike) {
        let ownBoundary = lastWasOwnBoundary
        lastWasOwnBoundary = false
        if engine.isEmpty, !ownBoundary, settings.reEditWord, reachBackAllowed, Self.isReEditKey(ch),
           seedWordBeforeCaret(then: ch, proxy: proxy) {
            return                                    // sửa từ trên màn hình: không huỷ được
        }
        let before = engine.composed
        let snapshot = engine
        let action = engine.feed(ch)
        guard safeToApply(action, expected: before, proxy: proxy) else {
            // Chữ trước con trỏ không còn là từ đang gõ → bỏ từ cũ, phím này mở từ MỚI
            // (engine trống + 1 phím = chèn literal, không xoá gì).
            reset()
            apply(engine.feed(ch), literal: String(ch), proxy: proxy)
            return
        }
        apply(action, literal: String(ch), proxy: proxy)
        switch action {
        case .replace(let bs, let insert):
            letterUndo = LetterUndo(engine: snapshot, removed: String(before.suffix(bs)),
                                    inserted: insert, ownBoundary: ownBoundary)
        case .passthrough:
            letterUndo = LetterUndo(engine: snapshot, removed: "", inserted: String(ch),
                                    ownBoundary: ownBoundary)
        case .none:
            letterUndo = LetterUndo(engine: snapshot, removed: "", inserted: "",
                                    ownBoundary: ownBoundary)
        }
    }

    /// Huỷ phím chữ vừa gõ (chỉ khi chưa có thao tác nào khác xen vào): trả màn hình và
    /// engine về đúng trước phím đó. false = không huỷ được (caller tự xử lý).
    func undoLastLetter(proxy: TextProxyLike) -> Bool {
        guard let u = letterUndo else { return false }
        letterUndo = nil
        if let ctx = proxy.contextBeforeInput, !ctx.hasSuffix(u.inserted) { return false }
        for _ in 0..<u.inserted.count { proxy.deleteBackward() }
        if !u.removed.isEmpty { proxy.insertText(u.removed) }
        engine = u.engine
        lastWasOwnBoundary = u.ownBoundary
        swipeOpen = u.swipe
        settledCommit = u.settled
        return true
    }

    /// Space / return / punctuation: word boundary → auto-restore, then the char.
    /// Returns the FINAL committed word (post auto-restore) — the
    /// personalization model must learn what actually landed on screen.
    @discardableResult
    func boundary(_ text: String, proxy: TextProxyLike) -> String {
        letterUndo = nil
        swipeOpen = nil
        guard !proxy.isSecure, !passthrough else { proxy.insertText(text); return "" }
        let before = engine.composed
        var action = engine.commitBoundary(autoRestore: settings.autoRestore)
        if !safeToApply(action, expected: before, proxy: proxy) {
            // Lệch: KHÔNG auto-restore (sẽ xoá nhầm chữ khác) — chỉ chèn ký tự ngắt.
            reset()
            action = .none
        }
        var final = before
        if case let .replace(bs, insert) = action {
            final = String(before.dropLast(bs)) + insert
        }
        apply(action, literal: "", proxy: proxy)
        proxy.insertText(text)
        lastWasOwnBoundary = text.last.map { !$0.isLetter } ?? false
        return final
    }

    /// Backspace. Trả true khi ⌫ này MỞ LẠI từ vừa chốt (engine lại đang gõ từ đó).
    @discardableResult
    func backspace(proxy: TextProxyLike) -> Bool {
        letterUndo = nil
        lastWasOwnBoundary = false
        let open = swipeOpen
        swipeOpen = nil
        guard !proxy.isSecure, !passthrough else { proxy.deleteBackward(); return false }
        if open?.fresh == true, !engine.isEmpty {
            // ⌫ đầu tiên ngay sau vuốt: xoá cả từ (như Gboard/QuickPath). Lệch ⇒ ⌫ thường.
            let composed = engine.composed
            engine.reset()
            if CompositionSync.canDelete(composed.count, expected: composed,
                                         context: { proxy.contextBeforeInput }) {
                for _ in 0..<composed.count { proxy.deleteBackward() }
            } else {
                TouchLog.write("failsafe: swipe-word ⌫ len=\(composed.count) → ⌫ thường")
                proxy.deleteBackward()
            }
            return false
        }
        guard !engine.isEmpty else {
            if engine.canReopenLastCommit { return reopenLastCommit(proxy: proxy) }
            proxy.deleteBackward()
            return false
        }
        let before = engine.composed
        let action = engine.backspace()
        guard safeToApply(action, expected: before, proxy: proxy) else {
            reset()                    // lệch → xoá thường 1 ký tự, không vẽ lại từ
            proxy.deleteBackward()
            return false
        }
        switch action {
        case .replace(let bs, let insert):
            for _ in 0..<bs { proxy.deleteBackward() }
            if !insert.isEmpty { proxy.insertText(insert) }
        case .passthrough, .none:
            proxy.deleteBackward()
        }
        return false
    }

    // MARK: - Sửa dấu từ đã gõ xong (như macOS: reopenLastCommit + seed)

    /// ⌫ ngay sau ký tự ranh giới vừa chốt một từ: xoá ranh giới (luôn — đó là việc
    /// của ⌫) và nạp lại từ vào engine để gõ tiếp dấu ("tháy" ␣ ⌫ a → "thấy").
    /// Chỉ khi màn hình XÁC NHẬN: context trước con trỏ = …từ + 1 ký tự không phải chữ,
    /// khớp ĐÚNG từng scalar (NFD / host tự sửa chữ ⇒ lệch ⇒ bỏ). Context nil, có vùng
    /// chọn, ô omnibox ⇒ quên snapshot, ⌫ thường. Snapshot tiêu thụ 1 lần. Từ bị
    /// auto-restore ("google") engine không capture → không bao giờ tới đây, nên luồng
    /// backspace-undo (restoreUndo) của controller giữ nguyên.
    private func reopenLastCommit(proxy: TextProxyLike) -> Bool {
        guard settings.reEditWord, reachBackAllowed, !proxy.hasSelection,
              let ctx = proxy.contextBeforeInput,
              let boundaryChar = ctx.last, !boundaryChar.isLetter else {
            engine.forgetLastCommit()
            proxy.deleteBackward()
            return false
        }
        guard let word = engine.reopenLastCommit() else {     // setting đổi → replay lệch
            proxy.deleteBackward()
            return false
        }
        guard CompositionSync.endsWithWord(String(ctx.dropLast()), word) else {
            engine.reset()
            TouchLog.write("reopen: context lệch → bỏ")
            proxy.deleteBackward()
            return false
        }
        proxy.deleteBackward()
        // Đọc lại sau khi xoá: host nuốt/đổi lệnh xoá → không giữ từ (nil = không biết,
        // đã xác minh trước khi xoá nên giữ).
        if let after = proxy.contextBeforeInput, !CompositionSync.endsWithWord(after, word) {
            engine.reset()
            TouchLog.write("reopen: context sau xoá lệch → bỏ")
            return false
        }
        return true
    }

    /// Phím được nạp lại từ trước con trỏ: CHỈ dấu thanh / huỷ dấu / móc (s f r x j
    /// z w). KHÔNG a e o d (user 26/09/2026): "to" + o phải ra "too" chứ không "tô" —
    /// mũ/đ chỉ sửa được qua ⌫ mở lại từ. Lọc rẻ trước khi trả giá đọc context.
    static func isReEditKey(_ ch: Character) -> Bool {
        switch ch {
        case "s", "f", "r", "x", "j", "z", "w",
             "S", "F", "R", "X", "J", "Z", "W": return true
        default: return false
        }
    }

    /// Engine rỗng, con trỏ đứng NGAY SAU một từ (không ở giữa từ, không vùng chọn):
    /// seed engine bằng từ đó rồi feed `ch`. Chỉ áp khi seed round-trip VÀ phím thật sự
    /// biến đổi từ ("viet" + j → "việt"); không thì engine reset, trả false → caller
    /// chèn literal như cũ. Context trước nil ⇒ không áp. Context SAU nil được coi là
    /// hết văn bản (host iOS hay trả nil thay cho "" ở cuối ô).
    private func seedWordBeforeCaret(then ch: Character, proxy: TextProxyLike) -> Bool {
        guard !proxy.hasSelection,
              let ctx = proxy.contextBeforeInput,
              let word = CompositionSync.trailingWord(ctx) else { return false }
        if let after = proxy.contextAfterInput, let next = after.first, next.isLetter {
            return false                               // đang ở giữa từ
        }
        guard engine.seed(word) else { return false }  // seed tự reset khi không khớp
        let action = engine.feed(ch)
        guard case .replace(let bs, let insert) = action, bs > 0,
              engine.composed != word + String(ch) else {
            engine.reset()
            return false
        }
        guard safeToApply(action, expected: word, proxy: proxy) else {
            engine.reset()
            return false
        }
        TouchLog.edit(bs: bs, insertLen: insert.count, insert: insert)
        for _ in 0..<bs { proxy.deleteBackward() }
        if !insert.isEmpty { proxy.insertText(insert) }
        return true
    }

    /// Ký tự ranh giới vừa chèn đã bị controller viết lại (double-space → ". ") —
    /// ⌫ kế tiếp không còn xoá đúng ký tự đã chốt từ.
    func forgetLastCommit() { engine.forgetLastCommit(); lastWasOwnBoundary = false }

    /// Field switch / selection moved / keyboard dismissed → forget the word.
    /// Cũng xoá ngữ cảnh tiếng Anh: đổi ô / con trỏ nhảy → từ trước không còn là
    /// "từ ngay trước" nữa (macOS làm y hệt khi activateServer / đổi field).
    func reset() {
        engine.reset(); engine.resetContext(); lastWasOwnBoundary = false; letterUndo = nil
        swipeOpen = nil
    }

    var isComposing: Bool { !engine.isEmpty }

    /// Current word for the suggestion bar: on-screen composed form + raw keys.
    var composedWord: String { engine.composed }
    var rawWord: String { engine.rawKeystrokes }
    var autoFixAdjacent: Bool { settings.autoFixAdjacent }
    /// Cache kết quả AdjacentKeyFixer theo raw — sống cùng bridge (cùng setting).
    let adjacentFixCache = AdjacentKeyFixer.Cache()

    /// Dạng hiển thị engine SẼ ra cho chuỗi phím `raw`, với đúng setting hiện tại —
    /// engine scratch riêng, không đụng từ đang gõ (AdjacentKeyFixer). Chỉ đọc
    /// `settings` (let) → gọi được từ hàng đợi gợi ý nền.
    func composeTrial(_ raw: String) -> String {
        var e = TelexEngine()
        e.freeMarking = settings.freeMarking
        e.simpleTelex = settings.simpleTelex
        e.liveSpellCheck = settings.liveSpellCheck
        e.quickTelex = settings.quickTelex
        e.modernTone = settings.modernTone
        e.teencode = settings.teencode
        for ch in raw { _ = e.feed(ch) }
        return e.composed
    }

    /// Từ mà boundary SẼ chốt (auto-restore tính sẵn) — peek non-mutating trực
    /// tiếp trên engine. KHÔNG copy struct: bản copy cũ kích hoạt COW copy ~10
    /// buffer cố định mỗi phím khi commitText mutate (reset + scratch).
    var predictedCommit: String {
        engine.peekCommitText(autoRestore: settings.autoRestore)
    }

    /// Fail-safe trước khi xoá: action định xoá `bs` ký tự của `expected` (từ đang gõ
    /// lúc trước phím) — chỉ cho khi chữ trước con trỏ đúng là `expected`.
    private func safeToApply(_ action: TelexAction, expected: String, proxy: TextProxyLike) -> Bool {
        guard case .replace(let bs, _) = action, bs > 0 else { return true }
        let ok = CompositionSync.canDelete(bs, expected: expected,
                                           context: { proxy.contextBeforeInput })
        if !ok { TouchLog.write("failsafe: bs=\(bs) expectedLen=\(expected.count) → reset") }
        return ok
    }

    private func apply(_ action: TelexAction, literal: String, proxy: TextProxyLike) {
        switch action {
        case .replace(let bs, let insert):
            TouchLog.edit(bs: bs, insertLen: insert.count, insert: insert)
            for _ in 0..<bs { proxy.deleteBackward() }
            if !insert.isEmpty { proxy.insertText(insert) }
        case .passthrough:
            TouchLog.edit(bs: 0, insertLen: literal.count, insert: literal)
            if !literal.isEmpty { proxy.insertText(literal) }
        case .none:
            break
        }
    }
}
