// VietTelex iOS keyboard — M1: working QWERTY that types Vietnamese via
// TelexEngine diff-edits. UI is programmatic UIKit, laid out to Apple's stock
// metrics (fidelity pass = M2). No Full Access, no network, no timers at idle.
import UIKit
import os.log
import TelexCore

final class KeyboardViewController: UIInputViewController {

    private var bridge = EngineBridge()
    private var keyboard: KeyboardView!
    private let langModel = UserLangModel()
    private var lastWord: String?         // từ liền trước trong câu (context bigram)
    private var lastWord2: String?        // từ trước nữa (context trigram)
    private var learnEnabled = true
    /// Vuốt ⌫: context + từ đang soạn chụp lúc chạm ⌫ (trước lần xoá của chạm đó).
    private var wordSwipeSnapshot: (context: String?, composed: String)?
    /// Chuỗi vừa vuốt xoá + đuôi phần còn lại → ô "Khôi phục" (một lượt).
    private var wordSwipeRestore: (text: String, tail: String)?
    private var filterSensitive = true

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 17.0, *) {
            // traitCollectionDidChange không còn được gọi tin cậy trên iOS 17+.
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: Self, _: UITraitCollection) in
                vc.keyboard?.updateDark(AppearancePolicy.isDark(
                    appearance: vc.textDocumentProxy.keyboardAppearance ?? .default,
                    style: vc.traitCollection.userInterfaceStyle))
            }
        }
        // needsInputModeSwitchKey ở viewDidLoad CHƯA đáng tin (host chưa nối,
        // iOS còn in warning) — khởi tạo false, viewWillAppear set giá trị thật.
        keyboard = KeyboardView(
            needsGlobe: false,
            inputController: self,     // globe key addTarget thẳng vào handleInputModeList
            onKey: { [weak self] key in self?.handle(key) }
        )
        langModel.isKnownWord = { VNSuggest.contains($0) }
        // Datastore trống (lần đầu / vừa reset) → mồi bằng seed corpus để
        // ngày đầu tiên đã có gợi ý hợp lý; dữ liệu học thật vượt seed sau
        // vài ngày (weight seed ≤50, gõ thật +1/lần, decay tuần).
        langModel.seedIfEmpty(unigrams: SeedData.unigrams, bigrams: SeedData.bigrams)
        // Load plist chạy nền — bar mở-đầu refresh khi dữ liệu sẵn sàng.
        langModel.onReady = { [weak self] in self?.updateSuggestions() }
        keyboard.onDeleteWord = { [weak self] in self?.deleteWordBackward() }
        wireWordSwipe()
        keyboard.onBarToggle = { [weak self] in self?.updateSuggestions() }
        keyboard.onTemplate = { [weak self] in self?.insertTemplate($0) }
        keyboard.onOpenTemplates = { [weak self] in self?.openTemplatesInApp() }
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        // Như KeyboardView: nền trong suốt = touch xuyên sang app host (rớt phím).
        view.backgroundColor = KeyboardView.touchableClear
        view.addSubview(keyboard)
        NSLayoutConstraint.activate([
            keyboard.leftAnchor.constraint(equalTo: view.leftAnchor),
            keyboard.rightAnchor.constraint(equalTo: view.rightAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    #if DEBUG
    // Đo chi phí hiện bàn phím (Console filter "VTKB perf"): thân viewWillAppear,
    // thân viewDidAppear, khoảng will→did (gồm animation hệ thống), số lần rebuild.
    private var perfWillStart: CFTimeInterval = 0
    #endif

    override func viewWillAppear(_ animated: Bool) {
        #if DEBUG
        perfWillStart = CACurrentMediaTime()
        KeyboardView.perfFullBuilds = 0; KeyboardView.perfCacheSwaps = 0
        defer {
            NSLog("VTKB perf willAppear body %.2f ms",
                  (CACurrentMediaTime() - perfWillStart) * 1000)
        }
        #endif
        super.viewWillAppear(animated)
        TouchLog.loadSetting()
        bridge = EngineBridge()                       // fresh settings + buffer
        externalChangePending = false
        lastKeyWasEmailTrigger = false
        restoreUndo = nil; undoOfferActive = false
        let settings = KeyboardSettings.load()
        learnEnabled = settings.learnWords
        filterSensitive = settings.filterSensitive
        showSuggestionsSetting = settings.showSuggestions
        // Trait ô (layout, return key, passthrough, bar) — force: mỗi lần hiện áp lại
        // appearance/mẫu câu dù trait y hệt (batchConfigure tự dedupe rebuild).
        refreshFieldTraits(force: true)
        TouchLog.session(fullAccess: hasFullAccess, traits: fieldTraits?.logDescription ?? "")
        // Rung phím: cần cả toggle trong app LẪN Toàn quyền Truy cập (iOS
        // vô hiệu haptics trong extension không có Full Access).
        KeyboardView.hapticsEnabled = settings.hapticFeedback && hasFullAccess
        // Báo trạng thái Full Access cho app chứa (ẩn banner nhắc cấp quyền).
        // Không Full Access thì iOS chặn GHI App Group → cờ giữ nguyên/vắng,
        // banner vẫn hiện — đúng ý.
        reportStatusToApp()
        keyboard.onSuggestion = { [weak self] item in
            if item == KeyboardView.restoreToken { self?.restoreWordSwipe() }
            else { self?.acceptSuggestion(item) }
        }
        updateAutoShift()
        updateSuggestions()            // field trống → gợi mở đầu ngay khi hiện
        keyboard.showLanguageBadge()   // "ViệtTelex" thoáng trên spacebar như stock
    }

    /// Ghi kbFullAccess CHỈ khi đổi; heartbeat kbLastSeen tối đa 1 lần/giờ (app
    /// chỉ kiểm tra kbLastSeen > 0). Trước đây mỗi lần hiện ghi 2 key + synchronize()
    /// trên main. Bỏ synchronize(): lý do cũ là "extension bị suspend ngay sau đó"
    /// nhưng set() đã giao giá trị cho cfprefsd (daemon lo ghi đĩa) — process bị
    /// suspend/kill không làm mất; Apple cũng ghi rõ synchronize() không cần gọi.
    /// Không Full Access thì iOS chặn ghi → giá trị đọc lại không khớp mãi; memo
    /// theo process để không thử ghi lại mỗi lần hiện.
    private static var reportedFullAccess: Bool?
    private static var lastHeartbeatAttempt: TimeInterval = 0
    private func reportStatusToApp() {
        let fa = hasFullAccess
        let now = Date().timeIntervalSince1970
        let heartbeatDue = now - Self.lastHeartbeatAttempt > 3600
        guard Self.reportedFullAccess != fa || heartbeatDue else { return }
        guard let group = UserDefaults(suiteName: "group.com.viettelex") else { return }
        if Self.reportedFullAccess != fa {
            if group.object(forKey: "kbFullAccess") as? Bool != fa {
                group.set(fa, forKey: "kbFullAccess")
            }
            Self.reportedFullAccess = fa
        }
        if heartbeatDue {
            Self.lastHeartbeatAttempt = now
            if now - group.double(forKey: "kbLastSeen") > 3600 {
                group.set(now, forKey: "kbLastSeen")
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        #if DEBUG
        let perfStart = CACurrentMediaTime()
        defer {
            NSLog("VTKB perf willDisappear body %.2f ms", (CACurrentMediaTime() - perfStart) * 1000)
        }
        #endif
        super.viewWillDisappear(animated)
        langModel.saveNow()   // extension có thể bị kill ngay sau disappear
    }

    // Host truyền .default là thường — dark/light thật nằm ở trait hệ thống,
    // đổi giữa chừng (auto dark theo giờ…) phải áp lại appearance.
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            keyboard?.applyAppearance(textDocumentProxy.keyboardAppearance ?? .default, style: traitCollection.userInterfaceStyle)
        }
    }

    /// Apple behavior: shift turns on at sentence start when the field asks for
    /// .sentences autocapitalization (empty context, or after ".!?" + space).
    private func updateAutoShift() {
        guard let auto = FieldPolicy.autoShift(
            autocap: textDocumentProxy.autocapitalizationType ?? nil,
            before: textDocumentProxy.documentContextBeforeInput ?? "") else { return }
        autoShiftOn = auto
        keyboard.setAutoShift(auto)
    }

    /// Trait ô hiện tại (nil = chưa đọc lần nào trong phiên).
    private var fieldTraits: FieldTraits?
    private var showSuggestionsSetting = true

    /// Đọc trait ô và cấu hình lại bàn phím CHỈ khi trait đổi (hoặc `force` ở
    /// viewWillAppear). Host đổi ô trong cùng app không gọi viewWillAppear → gọi
    /// thêm ở textDidChange / selectionDidChange. KHÔNG đọc documentIdentifier.
    private func refreshFieldTraits(force: Bool = false) {
        let p = textDocumentProxy
        let t = FieldTraits(
            keyboardType: p.keyboardType ?? .default,
            returnKeyType: p.returnKeyType ?? .default,
            appearance: p.keyboardAppearance ?? .default,
            autocorrection: p.autocorrectionType ?? .default,
            contentType: p.textContentType ?? nil,
            secure: (p as UITextInputTraits).isSecureTextEntry == true)
        let old = fieldTraits
        guard force || FieldTraits.needsReconfigure(old: old, new: t) else { return }
        fieldTraits = t
        if !force { TouchLog.traits(t.logDescription) }
        // Ô email/URL/username/OTP: gõ literal. KHÔNG dựa vào autocorrect == .no —
        // Safari/Chrome/Spotlight tắt autocorrect ở ô tìm kiếm (xem FieldPolicy).
        // Đổi chế độ giữa từ → bỏ từ đang gõ (engine không còn khớp cách chèn).
        if bridge.passthrough != t.passthrough {
            bridge.reset()
            bridge.passthrough = t.passthrough
        }
        // Omnibox (inline autocomplete tự viết lại chữ): không với lại từ đã chốt.
        bridge.reachBackAllowed = t.keyboardType != .webSearch
        // Một lần rebuild cho cả 3 (và 0 lần nếu field giống lần trước).
        keyboard.batchConfigure {
            keyboard.configureReturnKey(type: t.returnKeyType)
            keyboard.applyAppearance(t.appearance, style: traitCollection.userInterfaceStyle)
            // configureInputKind nhảy plane (số/chữ) — chỉ gọi khi loại ô thật sự đổi
            // (hoặc lúc hiện), kẻo đang ở plane ký hiệu thì bị kéo về.
            if force || old?.inputKind != t.inputKind {
                keyboard.configureInputKind(t.inputKind)
            }
        }
        // Thanh gợi ý: gate qua toggle trong app; tự tắt ở field từ chối
        // gợi ý (mật khẩu, autocorrection = .no) — đúng hành vi stock.
        let active = showSuggestionsSetting && t.allowsSuggestions
        if force || active != suggestionsActive {
            suggestionsActive = active
            keyboard.setSuggestionsEnabled(active)
        }
    }

    /// Host báo text/selection sắp đổi từ NGOÀI handle() — chưa kết luận ngay (lúc
    /// textWillChange context THÁO DỞ); đánh dấu, đối chiếu ở textDidChange / phím kế.
    private var externalChangePending = false

    /// Đối chiếu từ đang gõ với chữ thật trước con trỏ (CompositionSync.verdict):
    /// còn khớp → GIỮ (host gán lại text mỗi phím, textWillChange đến muộn); lệch /
    /// không biết (nil) → reset như trước.
    private func syncComposition(_ event: String) {
        externalChangePending = false
        let ctx = textDocumentProxy.documentContextBeforeInput
        let composed = bridge.composedWord
        var selected: String?
        if #available(iOS 16.0, *) { selected = textDocumentProxy.selectedText }
        let verdict = CompositionSync.verdict(context: ctx, composed: composed, selectedText: selected)
        if TouchLog.enabled {
            let d = CompositionSync.diagnostic(context: ctx, composed: composed)
            TouchLog.sync("\(event) \(verdict)", ctxLen: d.len, suffix: d.suffix,
                          composingLen: composed.count)
        }
        if verdict != .keep {
            bridge.reset(); lastWord = nil; lastWord2 = nil
            restoreUndo = nil; undoOfferActive = false
        }
    }

    override func textWillChange(_ textInput: UITextInput?) {
        // Thay đổi từ NGOÀI edit của mình (tap chỗ khác, đổi ô, host tự gán lại
        // text…). Edit của mình không gọi lại hàm này trong lúc handle() chạy.
        TouchLog.host("textWillChange", applyingEdit: applyingEdit, composing: bridge.isComposing)
        if !applyingEdit { externalChangePending = true }
    }

    // Selection/con trỏ vừa đổi từ NGOÀI (select-all rồi gõ đè, tap chỗ khác,
    // app tự sửa text): quyết định giữ/bỏ từ đang gõ, đọc lại trait ô, tính lại
    // auto-shift như stock — select-all thì documentContextBeforeInput rỗng → viết
    // hoa chữ đầu. Không tính ở textWillChange vì lúc đó context THÁO DỞ.
    override func textDidChange(_ textInput: UITextInput?) {
        TouchLog.host("textDidChange", applyingEdit: applyingEdit, composing: bridge.isComposing)
        if !applyingEdit {
            if externalChangePending { syncComposition("textDidChange") }
            refreshFieldTraits()
            updateAutoShift()
            updateSuggestions()
        }
    }

    override func selectionWillChange(_ textInput: UITextInput?) {
        if !applyingEdit { externalChangePending = true }
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        TouchLog.host("selectionDidChange", applyingEdit: applyingEdit, composing: bridge.isComposing)
        if !applyingEdit {
            if externalChangePending { syncComposition("selectionDidChange") }
            refreshFieldTraits()
        }
    }

    private var applyingEdit = false

    private struct Proxy: TextProxyLike {
        let p: UITextDocumentProxy
        func insertText(_ text: String) { p.insertText(text) }
        func deleteBackward() { p.deleteBackward() }
        var isSecure: Bool { (p as UITextInputTraits).isSecureTextEntry == true }
        var contextBeforeInput: String? { p.documentContextBeforeInput }
        var contextAfterInput: String? { p.documentContextAfterInput }
        var hasSelection: Bool {
            if #available(iOS 16.0, *) { return p.selectedText?.isEmpty == false }
            return false
        }
    }

    /// Được xoá `expected` (đang nằm ngay trước con trỏ) bằng deleteBackward × N?
    /// Lệch → false và ghi log (không nội dung).
    private func canDeleteBefore(_ expected: String, what: String) -> Bool {
        let ok = CompositionSync.canDelete(expected.count, expected: expected,
                                           context: { textDocumentProxy.documentContextBeforeInput })
        if !ok { TouchLog.write("failsafe: \(what) expectedLen=\(expected.count) → skip delete") }
        return ok
    }

    private func handle(_ key: KeyboardView.Key) {
        let proxy = Proxy(p: textDocumentProxy)
        // textWillChange tới mà textDidChange chưa kịp → đối chiếu ngay trước phím.
        if externalChangePending { syncComposition("key") }
        wordSwipeRestore = nil                 // ô "Khôi phục" chỉ sống tới phím kế
        applyingEdit = true
        let t0 = TouchLog.enabled ? CACurrentMediaTime() : 0
        defer {
            applyingEdit = false
            if TouchLog.enabled {
                let kind: String
                var char: String?
                switch key {
                case .letter(let c): kind = "letter"; char = String(c)
                case .text(let t): kind = "text"; char = t
                case .space: kind = "space"
                case .doubleSpacePeriod: kind = "doubleSpace"
                case .backspace: kind = "backspace"
                case .newline: kind = "newline"
                case .moveCursor: kind = "cursor"
                case .clearField: kind = "clear"
                case .replaceLastLetter(let t): kind = "flick"; char = t
                }
                TouchLog.key(kind: kind, composing: bridge.isComposing,
                             lagMs: (CACurrentMediaTime() - t0) * 1000, char: char)
                // Sau edit: độ dài context + context có kết thúc bằng từ đang gõ
                // (bắt host gán lại text / nuốt edit). Chỉ khi Debug mode bật.
                let composed = bridge.composedWord
                let d = CompositionSync.diagnostic(
                    context: textDocumentProxy.documentContextBeforeInput, composed: composed)
                TouchLog.sync("after-\(kind)", ctxLen: d.len, suffix: d.suffix,
                              composingLen: composed.count)
            }
        }
        switch key {
        case .letter(let ch):
            bridge.letter(ch, proxy: proxy)
            restoreUndo = nil; undoOfferActive = false
        case .replaceLastLetter(let s):
            // Huỷ đúng phím chữ vừa gõ (không được thì ⌫ như cũ) rồi chèn như ký hiệu.
            if !bridge.undoLastLetter(proxy: proxy) { bridge.backspace(proxy: proxy) }
            commitAndLearn(bridge.boundary(s, proxy: proxy))
            lastWord = nil; lastWord2 = nil
            restoreUndo = nil; undoOfferActive = false
        case .text(let s):                            // numbers, symbols
            commitAndLearn(bridge.boundary(s, proxy: proxy))
            lastWord = nil; lastWord2 = nil            // dấu câu/ký hiệu = ngắt câu
            restoreUndo = nil; undoOfferActive = false
        case .space:
            let composedBefore = bridge.composedWord
            let committed = bridge.boundary(" ", proxy: proxy)
            // Auto-restore vừa ghi đè dạng có dấu → nhớ lại cho backspace-undo.
            restoreUndo = (!composedBefore.isEmpty && committed != composedBefore)
                ? (raw: committed, composed: composedBefore) : nil
            undoOfferActive = false
            commitAndLearn(committed)
        case .doubleSpacePeriod:
            // Apple: double-space biến space vừa gõ thành ". ". ĐỌC context thật
            // (không phải hot path — gesture hiếm): điều kiện = đang có đúng " "
            // ở cuối và trước nó là ký tự chữ/số. State cũ (lastSpaceAfterText)
            // sai khi từ đã commit sớm → "đôi lúc không ra dấu chấm" (user).
            let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
            if TypingHeuristics.doubleSpaceMakesPeriod(context: ctx, lastWasSpace: lastInsertWasSpace) {
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(". ")
                bridge.forgetLastCommit()         // space đã thành ". " → ⌫ không mở lại từ
                lastWord = nil; lastWord2 = nil
            } else {
                commitAndLearn(bridge.boundary(" ", proxy: proxy))
            }
            restoreUndo = nil; undoOfferActive = false
        case .moveCursor(let delta):
            bridge.reset()                        // caret moved → composition gone
            lastWord = nil; lastWord2 = nil
            restoreUndo = nil; undoOfferActive = false
            textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
        case .newline:
            commitAndLearn(bridge.boundary("\n", proxy: proxy))
            lastWord = nil; lastWord2 = nil
            restoreUndo = nil; undoOfferActive = false
        case .clearField:
            clearAllText()
            bridge.reset(); lastWord = nil; lastWord2 = nil
            restoreUndo = nil; undoOfferActive = false
        case .backspace:
            // Backspace NGAY SAU space có restore → xoá space và chào lại dạng
            // có dấu ở slot literal (trust fix cho collision kiểu "his"≡"hí").
            if !bridge.isComposing, lastInsertWasSpace, restoreUndo != nil {
                undoOfferActive = true
            } else {
                restoreUndo = nil; undoOfferActive = false
            }
            if bridge.backspace(proxy: proxy) {
                // ⌫ mở lại từ vừa chốt: từ đó không còn là "từ trước" trong câu.
                lastWord = lastWord2; lastWord2 = nil
            }
            if !bridge.isComposing { lastWord = nil; lastWord2 = nil }  // xoá lấn vào chữ cũ → context mờ
        }
        switch key {
        case .space, .doubleSpacePeriod: lastInsertWasSpace = true
        default: lastInsertWasSpace = false
        }
        if case .text(let s) = key, s == "@" || s == "." {
            lastKeyWasEmailTrigger = true
        } else {
            lastKeyWasEmailTrigger = false
        }
        // updateAutoShift đọc documentContextBeforeInput (XPC) → cùng khối
        // async với suggestions, coalesce theo generation: gõ nhanh chỉ tính
        // cho phím cuối, ký tự không bao giờ chờ. Sound đã phát ở touch-down.
        let needsAutoShift: Bool
        switch key {
        case .space, .newline, .doubleSpacePeriod, .backspace, .moveCursor, .clearField: needsAutoShift = true
        default: needsAutoShift = false
        }
        suggestionGen += 1
        let gen = suggestionGen
        // Auto-shift TỨC THÌ (ảnh hưởng chữ hoa của phím kế tiếp — không debounce
        // được, kẻo gõ nhanh sau ". " không kịp viết hoa).
        if needsAutoShift {
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.suggestionGen else { return }
                self.updateAutoShift()
            }
        }
        // Gợi ý hoãn ~30ms (gen bỏ lượt cũ nếu phím mới tới trước). Thực tế phím
        // cách nhau 100–200ms nên hiếm khi gộp — phần nặng (VNSuggest + sửa chạm
        // trượt) giờ chạy nền trong updateSuggestions, main chỉ re-rank + vẽ bar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, gen == self.suggestionGen else { return }
            self.updateSuggestions()
        }
    }

    private var suggestionGen = 0
    /// Số lượt updateSuggestions — kết quả nền chỉ áp nếu là lượt mới nhất.
    private var suggestReq = 0
    private static let suggestQueue = DispatchQueue(label: "com.viettelex.suggest",
                                                    qos: .userInitiated)
    private var lastInsertWasSpace = false
    private var autoShiftOn = false
    private var suggestionsActive = true
    /// Phím vừa gõ là "@" hoặc "." → rule email/TLD mới có thể ăn; chỉ khi đó
    /// mới đáng trả giá XPC đọc documentContextBeforeInput.
    private var lastKeyWasEmailTrigger = false
    /// (raw đã chốt, dạng có dấu) khi auto-restore ghi đè — backspace ngay sau đó
    /// mở lại lối thoát: slot literal hiện dạng có dấu để 1 tap đổi từ.
    private var restoreUndo: (raw: String, composed: String)?
    private var undoOfferActive = false
    private var ctxCacheKey: String?
    private var ctxCache: Set<String> = []

    /// iOS defer touch gần mép ~1s để phân xử system gesture — nguồn số 1 của
    /// "ấn phím hàng dưới không ăn". Xin quyền nhận touch trước ở mép dưới.
    /// (A/B 25/09/2026: bật/tắt cờ này không đổi tỉ lệ rớt phím — nguyên nhân thật
    /// là nền trong suốt, xem KeyboardView.touchableClear.)
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.bottom] }

    // needsInputModeSwitchKey chỉ đáng tin sau khi nối host — gọi 1 LẦN ở
    // viewDidAppear (gọi mỗi layout pass làm iOS 26 spam warning; đã dính).
    // Kết luận điều tra khoảng trống 2026-07-24: window extension = đúng chiều
    // cao mình xin, view phủ từ y=0 — dải tối phía trên là chrome container
    // iOS 26 do HOST vẽ, mọi bàn phím bên thứ ba đều có, không can thiệp được.
    override func viewDidAppear(_ animated: Bool) {
        #if DEBUG
        let perfDidStart = CACurrentMediaTime()
        defer {
            let now = CACurrentMediaTime()
            NSLog("VTKB perf didAppear body %.2f ms, will→did %.1f ms, fullBuilds=%d cacheSwaps=%d",
                  (now - perfDidStart) * 1000, (now - perfWillStart) * 1000,
                  KeyboardView.perfFullBuilds, KeyboardView.perfCacheSwaps)
        }
        #endif
        super.viewDidAppear(animated)
        // Trait host đã resolve khi view vào window — sửa sáng/tối nếu lúc
        // viewWillAppear đoán sai (phím sáng trên nền tối).
        keyboard?.updateDark(AppearancePolicy.isDark(
            appearance: textDocumentProxy.keyboardAppearance ?? .default,
            style: traitCollection.userInterfaceStyle))
        keyboard?.setNeedsGlobe(needsInputModeSwitchKey)
        // Clipboard có thể vừa đổi trong lúc bàn phím ẩn: tính lại bar khi đã hiện
        // hẳn (cache 2s của pasteOffer bỏ qua để đọc trạng thái mới).
        // Chỉ tính lại cả bar khi kết quả nút Dán ĐỔI so với lúc viewWillAppear
        // (thường không đổi) — tránh chạy trùng toàn bộ updateSuggestions.
        let pasteBefore = pasteCached
        pasteCheckedAt = .distantPast
        if suggestionsActive, keyboard?.isBarCollapsed != true,
           bridge.composedWord.isEmpty, pasteOffer() != pasteBefore {
            updateSuggestions()
        }
        if let mb = Self.memoryFootprintMB() {
            NSLog("VTKB mem: %.1f MB", mb)   // Console filter "VTKB mem"
        }
        #if DEBUG
        dumpGeometry("didAppear")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dumpGeometry("didAppear+1.5s")
        }
        #endif
    }

    #if DEBUG
    /// Dò hình học iOS 27 (dải kính host phủ đỉnh bàn phím). Đọc bằng:
    /// xcrun simctl spawn <udid> log show --last 5m \
    ///   --predicate 'subsystem == "com.viettelex.ios.keyboard.geom"' --style compact
    private func dumpGeometry(_ tag: String) {
        let log = OSLog(subsystem: "com.viettelex.ios.keyboard.geom", category: "geom")
        let w = view.window
        let inWindow = w.map { view.convert(view.bounds, to: $0) } ?? .zero
        os_log("[%{public}@] view.bounds=%{public}@ inWindow=%{public}@ window.bounds=%{public}@",
               log: log, type: .default, tag,
               NSCoder.string(for: view.bounds), NSCoder.string(for: inWindow),
               NSCoder.string(for: w?.bounds ?? .zero))
        os_log("[%{public}@] safeArea=%{public}@ additional=%{public}@ kbFrame=%{public}@ kbSafe=%{public}@",
               log: log, type: .default, tag,
               NSCoder.string(for: view.safeAreaInsets), NSCoder.string(for: additionalSafeAreaInsets),
               NSCoder.string(for: keyboard?.frame ?? .zero),
               NSCoder.string(for: keyboard?.safeAreaInsets ?? .zero))
        var chain: [String] = []
        var v: UIView? = view
        while let cur = v {
            chain.append("\(type(of: cur))\(NSCoder.string(for: cur.frame)) sa=\(NSCoder.string(for: cur.safeAreaInsets))")
            v = cur.superview
        }
        os_log("[%{public}@] chain: %{public}@", log: log, type: .default, tag,
               chain.joined(separator: " > "))
    }
    #endif

    /// RAM thực của extension (phys_footprint — đúng con số jetsam so với
    /// limit ~60-70MB của keyboard extension).
    private static func memoryFootprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<Int32>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// Mẫu câu từ burger menu: chèn nguyên văn, KHÔNG học vào model (câu
    /// nhiều từ sẽ làm bẩn unigram), reset engine như một lần dán.
    /// Mẫu dạng https:// = "mẫu động": fetch NGAY LÚC TAP, chèn raw response
    /// (cắt 1000 bytes). LƯU Ý: không Full Access thì iOS chặn network của
    /// keyboard extension → fetch fail → fallback chèn chính URL.
    private func insertTemplate(_ s: String) {
        if s.hasPrefix("https://"), let url = URL(string: s) {
            let req = URLRequest(url: url, timeoutInterval: 4)
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                DispatchQueue.main.async {
                    let body = data.map { d in
                        String(decoding: d.prefix(1000), as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } ?? ""
                    self?.rawInsert(body.isEmpty ? s : body)
                }
            }.resume()
            return
        }
        rawInsert(s)
    }

    private func rawInsert(_ s: String) {
        applyingEdit = true
        defer { applyingEdit = false }
        // Lệch (con trỏ đã dời) → không xoá gì, chỉ chèn mẫu tại con trỏ.
        let composed = bridge.composedWord
        if canDeleteBefore(composed, what: "template") {
            for _ in 0..<composed.count { textDocumentProxy.deleteBackward() }
        }
        textDocumentProxy.insertText(s)
        bridge.reset()
        lastWord = nil; lastWord2 = nil
        restoreUndo = nil; undoOfferActive = false
        KeyboardView.clickModifier()
        updateAutoShift()
        updateSuggestions()
    }

    /// Nút 🗑 plane mẫu câu: xoá SẠCH ô nhập. Không có API "clear all" —
    /// đẩy con trỏ về cuối rồi deleteBackward tới khi rỗng. documentContext*
    /// chỉ trả CỬA SỔ quanh con trỏ nên phải lặp; safety chặn treo ở field lạ.
    /// Fail-safe (CompositionSync): lượt nào context không đổi sau khi xoá/dời
    /// (host không cập nhật đồng bộ) thì dừng — không xoá mù 20k lần.
    private func clearAllText() {
        let p = textDocumentProxy
        CompositionSync.moveToEnd(contextAfter: { p.documentContextAfterInput },
                                  adjust: { p.adjustTextPosition(byCharacterOffset: $0) })
        CompositionSync.clearBefore(context: { p.documentContextBeforeInput },
                                    deleteBackward: { p.deleteBackward() })
    }

    /// Bubble ⚙️: mở tab Mẫu Câu trong app qua URL scheme viettelex://maucau.
    /// Keyboard extension không có UIApplication — đi responder chain tìm
    /// openURL: (pattern chuẩn của keyboard bên thứ ba).
    /// LƯU Ý: mở app chứa từ keyboard extension CHỈ chạy khi đã cấp Toàn quyền
    /// Truy cập (Full Access) — iOS chặn hoàn toàn nếu chưa cấp.
    private func openTemplatesInApp() {
        guard let url = URL(string: "viettelex://maucau") else { return }
        let sel = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            // UIApplication vẫn nằm trong responder chain của extension —
            // ưu tiên API hiện đại, fallback selector cũ (openURL:).
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            if r.responds(to: sel) {
                r.perform(sel, with: url)
                return
            }
            responder = r.next
        }
        extensionContext?.open(url)   // đường chính thống, một số iOS chấp nhận
    }

    /// Xoá theo TỪ khi giữ backspace lâu (>3s) — gesture giữ, không phải hot
    /// path nên đọc proxy (XPC) mỗi từ là chấp nhận được.
    private func deleteWordBackward() {
        applyingEdit = true
        defer { applyingEdit = false }
        bridge.reset()
        lastWord = nil; lastWord2 = nil
        restoreUndo = nil; undoOfferActive = false
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        guard !before.isEmpty else { return }
        let count = WordDelete.charsToDelete(context: before, words: 1)
        for _ in 0..<max(count, 1) { textDocumentProxy.deleteBackward() }
        updateAutoShift()
        updateSuggestions()
    }

    /// Từ vừa chốt: nạp vào model cá nhân + trượt cửa sổ context (prev2, prev1).
    /// `accepted` = user bấm nhận suggestion → weight 2 (tín hiệu mạnh hơn).
    private func commitAndLearn(_ word: String, accepted: Bool = false) {
        guard !word.isEmpty else { return }
        if learnEnabled {
            langModel.record(word: word, after: lastWord, prev2: lastWord2,
                             weight: accepted ? 2 : 1)
        }
        if UserLangModel.learnable(word) {
            lastWord2 = lastWord
            lastWord = word
        } else {
            lastWord = nil; lastWord2 = nil
        }
    }

    /// Gợi ý cho từ đang gõ: emoji (khớp cả "yêu" lẫn "love" — bảng
    /// EmojiSuggest) + hoàn thiện từ tiếng Việt từ VNLexicon ("nguoi"/"ng" →
    /// "người"): ưu tiên ứng viên chỉ khác dấu, rồi completion dài hơn.
    /// Đuôi email/domain phổ biến — rule cứng theo ngữ cảnh, không qua datastore
    /// (token chứa @/. không phải "từ" học được).
    private static let emailSuffixes = ["gmail.com", "yahoo.com", "outlook.com"]
    private static let domainTLDs = ["com", "vn", "net"]

    /// đầu câu (auto-shift): gợi ý viết hoa chữ đầu như stock (Em, Anh, Tôi)
    private func caseForContext(_ w: String) -> String {
        autoShiftOn ? w.prefix(1).uppercased() + w.dropFirst() : w
    }

    /// Đệm danh sách gợi ý cho ĐỦ `need` phần tử bằng từ hay dùng nhất (loại
    /// trùng + từ đang gõ) — bar luôn đủ 3, không bao giờ trống/khuyết
    /// (user 2026-07-25). Model đã seed nên topWords luôn đủ.
    private func padWords(_ base: [String], need: Int, typed: String = "") -> [String] {
        guard base.count < need else { return Array(base.prefix(need)) }
        let candidates = SensitiveWords.filter(langModel.topWords(limit: need + 12),
                                               enabled: filterSensitive)
            .map { caseForContext(DisplayCase.apply($0)) }
        return SuggestionFill.pad(base, with: candidates, need: need, excluding: typed)
    }

    private func updateSuggestions() {
        // Bar tắt HOẶC đang thu gọn → khỏi tính toán gì hết (VNSuggest,
        // re-rank, emoji, nextWords) — tiết kiệm CPU/RAM theo đúng nghĩa.
        suggestReq += 1                  // lượt mới → kết quả nền cũ (nếu có) bỏ
        guard suggestionsActive, keyboard?.isBarCollapsed != true else { return }
        let composed = bridge.composedWord
        var set = KeyboardView.SuggestionSet()
        // Backspace-undo sau auto-restore: chào dạng có dấu ở slot literal.
        if composed.isEmpty, undoOfferActive, let u = restoreUndo {
            set.literal = u.composed
        }
        if composed.isEmpty, wordSwipeRestore != nil { set.restoreLabel = "\u{21A9}\u{FE0E} Khôi phục" }
        // Ngữ cảnh email/domain: "phuc@" → gợi đuôi mail; "github." → gợi TLD.
        // Đọc proxy (XPC) chỉ khi phím vừa gõ là @/. — không phải mọi boundary.
        if composed.isEmpty, lastKeyWasEmailTrigger,
           let before = textDocumentProxy.documentContextBeforeInput,
           let last = before.split(separator: " ").last {
            if last.hasSuffix("@"), last.count > 1 {
                keyboard.showSuggestions(.init(nextWords: Self.emailSuffixes))
                return
            }
            if last.hasSuffix("."), last.count > 1,
               last.dropLast().allSatisfy({ $0.isLetter || $0.isNumber }) {
                keyboard.showSuggestions(.init(nextWords: Self.domainTLDs))
                return
            }
        }
        if !composed.isEmpty {
            keyboard.hidePasteCard()   // có phím chữ → thẻ Dán biến mất ngay (user 25/09/2026)
            // VNSuggest + AdjacentKeyFixer chạy NỀN (fixer tới vài ms với từ lạ như
            // "keyboard"/"github"); main chỉ re-rank (model cá nhân) + vẽ bar. Kết
            // quả chỉ áp khi còn hiện hành: không có lượt updateSuggestions mới hơn,
            // không có phím mới (suggestionGen), cùng bridge + cùng từ đang gõ.
            let req = suggestReq, gen = suggestionGen, b = bridge
            let raw = b.rawWord, predicted = b.predictedCommit, wantFix = b.autoFixAdjacent
            Self.suggestQueue.async { [weak self] in
                let pool = VNSuggest.matches(composed, poolLimit: 24,
                                             excluding: composed.lowercased())
                let fix = pool.isEmpty && wantFix
                    ? AdjacentKeyFixer.lexiconCorrection(raw: raw, bridge: b) : nil
                DispatchQueue.main.async {
                    guard let self, req == self.suggestReq, gen == self.suggestionGen,
                          self.bridge === b, b.composedWord == composed,
                          self.suggestionsActive, self.keyboard?.isBarCollapsed != true
                    else { return }
                    self.showComposingSuggestions(composed: composed, raw: raw,
                                                  predicted: predicted, pool: pool, fix: fix)
                }
            }
            return
        } else if let prev = lastWord {
            // vừa space sau một từ → gợi từ KẾ TIẾP (trigram/bigram cá nhân
            // interpolate với seed)
            let next = SensitiveWords.filter(
                langModel.nextWords(after: prev, prev2: lastWord2, limit: 6),
                enabled: filterSensitive
            ).prefix(3).map { caseForContext(DisplayCase.apply($0, after: prev)) }
            set.nextWords = padWords(Array(next), need: 3)
        } else {
            // field trống chưa gõ gì → từ user hay mở đầu nhất
            let top = SensitiveWords.filter(langModel.topWords(limit: 6),
                                            enabled: filterSensitive)
                .prefix(3).map { caseForContext(DisplayCase.apply($0)) }
            set.nextWords = padWords(Array(top), need: 3)
        }
        if composed.isEmpty, pasteOffer() { set.paste = true; set.pasteIsImage = pasteIsImage }
        keyboard.showSuggestions(set)
    }

    /// Phần main của gợi ý khi đang gõ dở: pool (VNSuggest) + fix đã tính nền.
    private func showComposingSuggestions(composed: String, raw: String, predicted: String,
                                          pool: [(word: String, freq: Int)], fix: String?) {
        var set = KeyboardView.SuggestionSet()
        // Slot "nguyên văn" = phương án mà boundary SẼ KHÔNG cho ra —
        // lối thoát cho cả hai chiều collision (user chốt 2026-07-24):
        //   gõ l,o,s,s → boundary restore "loss"  → slot hiện "los" (composed)
        //   gõ l,o,s   → boundary giữ "ló"        → slot hiện "los" (raw)
        // Tap = chèn + reset engine nên boundary sau đó không restore nữa.
        set.literal = predicted == composed ? raw : composed
        // Inline suggestion (research 2026-07-24): pool tương thích dấu từ
        // VNSuggest, re-rank = log(staticFreq) + λ₁·log(personal) +
        // λ₂·context-bonus + λ₃·chỉ-còn-thiếu-dấu.
        if !pool.isEmpty {
            // ctx chỉ đổi khi (lastWord, lastWord2) đổi — cache, khỏi gọi
            // nextWords mỗi keystroke trong lúc đang gõ dở một từ.
            let ctxKey = (lastWord ?? "") + "\u{1}" + (lastWord2 ?? "")
            if ctxKey != ctxCacheKey {
                ctxCache = lastWord.map {
                    Set(langModel.nextWords(after: $0, prev2: lastWord2, limit: 24))
                } ?? []
                ctxCacheKey = ctxKey
            }
            let ctx = ctxCache
            let typedLen = composed.count
            func score(_ w: String, _ f: Int) -> Double {
                log(Double(f) + 1)
                    + 2.5 * log(Double(langModel.count(of: w)) + 1)
                    + (ctx.contains(w) ? 4 : 0)
                    + (w.count == typedLen ? 1.5 : 0)
            }
            // score tính 1 lần/ứng viên rồi sort tuple — không gọi lại
            // trong comparator (2·n·log n lần).
            let scored = pool.map { ($0.word, score($0.word, $0.freq)) }
            let ranked = SensitiveWords.filter(
                scored.sorted { $0.1 > $1.1 }.map { $0.0 },
                enabled: filterSensitive)
            set.word = ranked.first.map { DisplayCase.apply($0, after: lastWord) }
            set.word2 = ranked.dropFirst().first.map { DisplayCase.apply($0, after: lastWord) }
        } else if let fix {
            // Thử nghiệm: không từ nào khớp → nghi chạm trượt phím kề; đưa bản sửa
            // lên slot chính (tap để thay, không tự thay).
            set.word = fix
        }
        // thử cụm 2 từ trước ("hoàn thành", "sinh nhật") rồi mới tới từ đơn.
        // Emoji KHÔNG bị lọc nhạy cảm (user 2026-07-24: gõ "cứt"/"shit"
        // phải ra 💩) — filter chỉ chặn gợi ý TỪ, emoji là cách nói giảm.
        var emojis: [String] = []
        let cLow = composed.lowercased()
        if let prev = lastWord {
            emojis = EmojiSuggest.emojis(for: prev.lowercased() + " " + cLow)
        }
        if emojis.isEmpty { emojis = EmojiSuggest.emojis(for: composed) }
        if emojis.isEmpty { emojis = EmojiSuggest.emojis(for: raw.lowercased()) }
        set.emojis = emojis
        // Không có emoji lấp slot 3 → đệm word/word2 cho đủ (literal + 2 từ).
        if emojis.isEmpty {
            let words = padWords([set.word, set.word2].compactMap { $0 },
                                 need: 2, typed: composed)
            set.word = words.first
            set.word2 = words.count > 1 ? words.last : nil
        }
        keyboard.showSuggestions(set)
    }

    // MARK: Nút Dán (maintainer 25/09/2026, như bàn phím stock/Gboard)
    // Chỉ khi có Full Access (không có thì extension không đọc được clipboard), không
    // gõ dở từ, và clipboard có nội dung MỚI trong 3 phút chưa dán. hasStrings không
    // bật hỏi quyền; nội dung chỉ đọc khi user CHẠM nút. Cache 2s: hasStrings là XPC.
    private var pasteSeenChange = -1
    private var pasteSeenAt = Date.distantPast
    private var pasteUsedChange = -1
    private var pasteCheckedAt = Date.distantPast
    private var pasteCached = false
    private var pasteIsImage = false
    private func pasteOffer() -> Bool {
        guard hasFullAccess else { TouchLog.write("paste: no Full Access"); return false }
        // Chỉ ở "đầu chỗ gõ": ô trống, hoặc ngay trước con trỏ là khoảng trắng/xuống dòng.
        // Bàn phím vừa hiện lại sau "Đang viết" thì engine rỗng nhưng vẫn là gõ dở chữ
        // (user 25/09/2026). documentContextBeforeInput là bản host đẩy sẵn — đọc rẻ.
        if let last = textDocumentProxy.documentContextBeforeInput?.last,
           !last.isWhitespace { return false }
        let now = Date()
        if now.timeIntervalSince(pasteCheckedAt) < 2 { return pasteCached }
        pasteCheckedAt = now
        let pb = UIPasteboard.general
        let cc = pb.changeCount
        if cc != pasteSeenChange { pasteSeenChange = cc; pasteSeenAt = now }
        let has = pb.hasStrings
        // Ảnh: KHÔNG báo (user 25/09/2026) — iOS không cho bàn phím chèn ảnh, thẻ
        // hướng dẫn trông như nút bấm được nên gây hiểu nhầm.
        pasteIsImage = false
        pasteCached = cc != pasteUsedChange && has
            && now.timeIntervalSince(pasteSeenAt) < 180
        if TouchLog.enabled {
            TouchLog.write(String(format: "paste: cc=%d used=%d hasStrings=%d age=%.0fs → %d",
                                  cc, pasteUsedChange, has ? 1 : 0,
                                  now.timeIntervalSince(pasteSeenAt), pasteCached ? 1 : 0))
        }
        return pasteCached
    }

    /// Tap gợi ý (hành vi QuickType): emoji thay hẳn từ; từ tiếng Việt thay
    /// từ + thêm space để gõ tiếp luôn.
    private func acceptSuggestion(_ item: String) {
        applyingEdit = true
        defer { applyingEdit = false }
        if item == KeyboardView.pasteImageToken {       // chỉ hướng dẫn → ẩn thẻ
            pasteUsedChange = UIPasteboard.general.changeCount
            pasteCached = false
            KeyboardView.clickModifier()
            updateSuggestions()
            return
        }
        if item == KeyboardView.pasteToken {
            let pb = UIPasteboard.general
            // Không có API hỏi "đã cho phép dán chưa": khi iOS hiện "Allow Paste?",
            // lệnh đọc BỊ CHẶN tới lúc user chọn (≥ vài trăm ms); đã Cho phép thì gần
            // như tức thì. Ghi kết quả vào App Group để app ẩn hướng dẫn (user 25/09/2026).
            let t0 = CACurrentMediaTime()
            let str = pb.string
            let noPrompt = str != nil && CACurrentMediaTime() - t0 < 0.25
            UserDefaults(suiteName: "group.com.viettelex")?.set(noPrompt, forKey: "pasteNoPrompt")
            if let s = str, !s.isEmpty { textDocumentProxy.insertText(s) }
            pasteUsedChange = pb.changeCount
            pasteCached = false
            bridge.reset(); lastWord = nil; lastWord2 = nil
            KeyboardView.clickModifier()
            updateSuggestions()
            return
        }
        // Undo auto-restore: caret đang đứng ngay sau từ raw đã chốt (space vừa
        // bị backspace) → thay cả từ raw bằng dạng có dấu + space.
        if undoOfferActive, let u = restoreUndo, item == u.composed,
           bridge.composedWord.isEmpty {
            // Chữ trước con trỏ không còn là từ raw vừa chốt → bỏ thao tác (không xoá lan).
            guard canDeleteBefore(u.raw, what: "undo-restore") else {
                restoreUndo = nil; undoOfferActive = false
                bridge.reset(); lastWord = nil; lastWord2 = nil
                updateSuggestions()
                return
            }
            for _ in 0..<u.raw.count { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(u.composed + " ")
            restoreUndo = nil; undoOfferActive = false
            bridge.reset()
            commitAndLearn(u.composed, accepted: true)
            KeyboardView.clickModifier()
            updateAutoShift()
            updateSuggestions()
            return
        }
        restoreUndo = nil; undoOfferActive = false
        let isFragment = item.contains(".") || item.contains("@")   // gmail.com, com…
        let isWord = !isFragment && item.first?.isLetter == true
        let composed = bridge.composedWord
        // Lệch: từ đang gõ không còn ngay trước con trỏ → bỏ lượt nhận gợi ý (thay
        // chữ khác là mất dữ liệu; chèn thêm cạnh từ lạ cũng sai) — reset, vẽ lại bar.
        guard canDeleteBefore(composed, what: "suggestion") else {
            bridge.reset(); lastWord = nil; lastWord2 = nil
            updateAutoShift()
            updateSuggestions()
            return
        }
        for _ in 0..<composed.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(isWord ? item + " " : item)
        bridge.reset()
        if isWord { commitAndLearn(item, accepted: true) } else { lastWord = nil; lastWord2 = nil }
        KeyboardView.clickModifier()
        updateAutoShift()
        updateSuggestions()
    }
}

extension KeyboardViewController: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

// MARK: vuốt trái trên ⌫ = xoá theo từ (kiểu Gboard) + ô "Khôi phục"
// Tách riêng để không đụng luồng backspace/engine: KeyboardView báo chạm xuống
// (chụp context TRƯỚC lần xoá của chạm), hỏi số từ tối đa khi bắt đầu vuốt, và
// báo số từ khi nhấc tay. Kế hoạch xoá là hàm thuần WordDelete.plan.
extension KeyboardViewController {
    fileprivate func wireWordSwipe() {
        keyboard.onBackspaceTouchDown = { [weak self] in
            guard let self else { return }
            // documentContextBeforeInput là bản host đẩy sẵn — đọc rẻ (xem pasteOffer).
            self.wordSwipeSnapshot = (self.textDocumentProxy.documentContextBeforeInput,
                                      self.bridge.composedWord)
        }
        keyboard.wordSwipeLimit = { [weak self] in
            guard let snap = self?.wordSwipeSnapshot, let ctx = snap.context else { return 0 }
            return WordDelete.availableWords(context: ctx)
        }
        keyboard.onWordSwipeEnd = { [weak self] n in self?.commitWordSwipe(n) }
    }

    fileprivate func commitWordSwipe(_ words: Int) {
        guard let snap = wordSwipeSnapshot else { return }
        wordSwipeSnapshot = nil
        applyingEdit = true
        defer { applyingEdit = false }
        let current = textDocumentProxy.documentContextBeforeInput
        guard let plan = WordDelete.plan(snapshot: snap.context, composed: snap.composed,
                                         current: current, words: words) else {
            TouchLog.write("failsafe: word-swipe words=\(words) ctx=\(current == nil ? "nil" : "mismatch") → skip")
            return
        }
        // Từ đang soạn (nếu có) là từ thứ nhất — engine bỏ nó như một lần dán.
        bridge.reset()
        lastWord = nil; lastWord2 = nil
        restoreUndo = nil; undoOfferActive = false
        for _ in 0..<plan.deleteNow { textDocumentProxy.deleteBackward() }
        if !plan.reinsert.isEmpty { textDocumentProxy.insertText(plan.reinsert) }
        wordSwipeRestore = plan.removed.isEmpty ? nil
            : (text: plan.removed, tail: WordDelete.restoreTail(plan.remaining))
        if TouchLog.enabled {
            TouchLog.write("word-swipe words=\(words) del=\(plan.deleteNow) reins=\(plan.reinsert.count) removed=\(plan.removed.count)")
        }
        updateAutoShift(); updateSuggestions()
    }

    fileprivate func restoreWordSwipe() {
        guard let r = wordSwipeRestore else { return }
        wordSwipeRestore = nil
        applyingEdit = true
        defer { applyingEdit = false }
        guard WordDelete.canRestore(context: textDocumentProxy.documentContextBeforeInput,
                                    tail: r.tail) else {
            TouchLog.write("failsafe: word-swipe restore context moved → skip")
            updateAutoShift(); updateSuggestions()
            return
        }
        bridge.reset()
        lastWord = nil; lastWord2 = nil
        restoreUndo = nil; undoOfferActive = false
        textDocumentProxy.insertText(r.text)
        KeyboardView.clickModifier()
        updateAutoShift(); updateSuggestions()
    }
}
