// VietTelex iOS keyboard — M1: working QWERTY that types Vietnamese via
// TelexEngine diff-edits. UI is programmatic UIKit, laid out to Apple's stock
// metrics (fidelity pass = M2). No Full Access, no network, no timers at idle.
import UIKit
import os.log
import TelexCore

final class KeyboardViewController: UIInputViewController {

    private var bridge = EngineBridge()
    private var keyboard: KeyboardView!
    /// Lấp dải container hệ thống lộ phía trên view (checkHostFill) + dedupe log hình học.
    fileprivate var hostFill = HostFill()
    fileprivate var hostFillRecheckScheduled = false
    fileprivate var lastHostGeomKey = ""
    /// Model học từ cá nhân — tạo LƯỜI khi tính năng cần (thanh gợi ý / gõ vuốt / Thêm dấu).
    /// Tắt hết ⇒ không đọc userlm.plist, không seed, không giữ bảng trong RAM.
    private var langModelStorage: UserLangModel?
    private var langModel: UserLangModel {
        if let m = langModelStorage { return m }
        let m = UserLangModel()
        m.isKnownWord = { VNSuggest.contains($0) }
        // Datastore trống (lần đầu / vừa reset) → mồi bằng seed corpus để
        // ngày đầu tiên đã có gợi ý hợp lý; dữ liệu học thật vượt seed sau
        // vài ngày (weight seed ≤50, gõ thật +1/lần, decay tuần).
        m.seedIfEmpty(unigrams: SeedData.unigrams, bigrams: SeedData.bigrams)
        // Load plist chạy nền — bar mở-đầu refresh khi dữ liệu sẵn sàng.
        m.onReady = { [weak self] in self?.updateSuggestions() }
        langModelStorage = m
        return m
    }
    private var lastWord: String?         // từ liền trước trong câu (context bigram)
    private var lastWord2: String?        // từ trước nữa (context trigram)
    private var learnEnabled = true
    /// Vuốt ⌫: context + từ đang soạn chụp lúc chạm ⌫ (trước lần xoá của chạm đó).
    private var wordSwipeSnapshot: (context: String?, composed: String)?
    /// Chuỗi vừa vuốt xoá + đuôi phần còn lại → ô "Khôi phục" (một lượt).
    private var wordSwipeRestore: (text: String, tail: String)?
    /// Công cụ văn bản vừa áp → ô "↩︎ Hoàn tác" / ⌫ ngay sau (một lượt).
    private var textToolUndo: TextTools.Undo?
    private var filterSensitive = true
    /// Gõ vuốt (thử nghiệm): công tắc trong app; `swipe` chỉ tạo khi bật (0 RAM khi tắt).
    private var swipeSetting = false
    private var swipe: SwipeTyping?
    /// Từ vuốt đang mở + phương án cho thanh gợi ý (hết hiệu lực khi từ đổi / chốt).
    /// `english` = các phương án tiếng Anh (chọn ⇒ chèn nguyên văn).
    private var swipeSuggest: (current: String, alts: [String], english: Set<String>)?
    /// Từ vuốt Việt vừa chèn + ứng viên đã chấm — cú vuốt kế sửa lại được (SwipeRevise).
    private var swipeRevisable: SwipeTyping.Revisable?
    /// Cú vuốt vừa sửa lại từ trước → chip "↩︎ từ cũ" (sống khi từ vuốt mới còn mở).
    private var swipeReviseUndo: SwipeTyping.Revision?
    fileprivate typealias Learned = (word: String, receipt: UserLangModel.Learned?, prev1: String?, prev2: String?)
    /// Từ vuốt Việt còn nguyên vừa được phím chữ (dấu cách treo) / dấu cách chốt ⇒ chờ từ GÕ
    /// PHÍM kế: ranh giới chốt từ đó thì chấm lại từ vuốt (SwipeRevise.reviseTyped). `learned` =
    /// lượt học của từ vuốt (rút khi thay). Sống qua phím chữ / ⌫ trong từ gõ; khác ⇒ bỏ.
    private var swipeTyped: (rev: SwipeRevise.Typed, learned: Learned?)?
    /// Vừa sửa lại từ vuốt theo từ gõ → chip "↩︎ từ cũ" (sống tới phím kế).
    private var swipeTypedUndo: (edit: SwipeRevise.TypedEdit, newLearned: Learned?, sentenceBreak: Bool)?
    /// Công tắc con "Vuốt từ tiếng Anh" (giai đoạn 3).
    private var swipeEnglishSetting = true
    private var swipeFutoSetting = false
    /// Chọn phím theo ngữ cảnh lúc chạm (thử nghiệm, mặc định BẬT) — TouchTarget.
    private var smartTouchSetting = true
    /// Tự sửa từ gõ sai (thử nghiệm, mặc định TẮT; VNI không sửa) — AutoCorrect.
    private var autoCorrectSetting = false
    /// Tự sửa đang chạy ở ô này (công tắc + AutoCorrect.fieldAllows) — tắt ⇒ 0 việc mỗi phím.
    private var autoCorrectActive = false
    /// Điểm chạm từng phím của từ đang gõ; hỏng (ok = false) khi có phím không kèm điểm
    /// chạm, ⌫ giữa từ, từ nạp lại… ⇒ từ đó không tự sửa.
    private var wordTouches: [AutoCorrect.Touch] = []
    private var wordTouchesOk = false
    private var pendingTouch: AutoCorrect.Touch?
    /// Từ từng hoàn tác tự sửa — không bao giờ sửa lại (UserDefaults của bàn phím, không sao lưu).
    private static let rejectedKey = "autoCorrectRejected"
    private lazy var autoCorrectRejected = AutoCorrect.Rejected.decode(
        UserDefaults.standard.string(forKey: Self.rejectedKey))
    /// Thay thế văn bản + tên danh bạ của người dùng (requestSupplementaryLexicon, nạp một
    /// lần mỗi lần hiện khi tự sửa bật) — coi là từ hợp lệ, không sửa.
    private var lexiconWords: Set<String> = []
    /// UILexicon nạp MỘT lần mỗi phiên controller (tự sửa + Thay thế văn bản iOS dùng chung).
    private lazy var supplementaryLexicon = SupplementaryLexiconCache { [weak self] done in
        guard let self else { return }
        self.requestSupplementaryLexicon { lex in
            done(lex.entries.prefix(5000).map { (input: $0.userInput, text: $0.documentText) })
        }
    }
    /// Thay thế văn bản iOS làm gõ tắt (cache theo phiên).
    private lazy var systemReplacements = SystemTextReplacementLoader(cache: supplementaryLexicon)
    /// Biên nhận học của từ vừa chốt — hoàn tác tự sửa rút lại đúng lượt học từ đã sửa.
    private var lastLearned: Learned?
    /// Vài từ tiếng Anh vừa vuốt ra (chữ thường) — ngữ cảnh ngôn ngữ cho cú vuốt kế
    /// (từ trùng chuỗi như "the" vuốt ra dạng Anh vẫn mở mạch Anh).
    private var recentEnglish: [String] = []
    /// ≤ 3 từ vừa chốt (cũ → mới) cho tiền nghiệm liên tục ngôn ngữ của gõ vuốt — KHÔNG xoá ở
    /// dấu câu (đang viết đoạn tiếng Anh thì câu sau vẫn tiếng Anh), chỉ xoá khi hiện lại bàn
    /// phím / chữ trước con trỏ đổi từ ngoài. Chỉ ghi khi bật vuốt + vuốt tiếng Anh.
    private var langRecent: [String] = []
    /// Lịch sử clipboard + chip tách số + ẩn danh (ClipboardFeature.swift).
    private let clip = ClipboardFeature()
    private var clipPanel: ClipboardPanel?
    /// Thêm dấu (AddTones): kế hoạch vừa áp — chip "Hoàn tác" / ⌫ ngay sau (tới phím kế);
    /// đoạn vừa hoàn tác (không mời lại); cache kế hoạch theo văn bản trước con trỏ.
    private var addTonesUndo: AddTones.Plan?
    private var addTonesDismissed: String?
    private var addTonesCache: (before: String, plan: AddTones.Plan?)?
    /// Vuốt phím cách đổi Tiếng Việt ↔ Tiếng Anh (công tắc trong app; tắt ⇒ luôn .vi).
    private var spaceFlickSetting = false
    private var language: KeyboardLanguage = .vi

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 17.0, *) {
            // traitCollectionDidChange không còn được gọi tin cậy trên iOS 17+.
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: Self, _: UITraitCollection) in
                vc.keyboard?.updateDark(AppearancePolicy.isDark(
                    appearance: vtSafe(.default) { vc.textDocumentProxy.keyboardAppearance ?? .default },
                    style: vc.traitCollection.userInterfaceStyle))
            }
        }
        registerObservers()
        installKeyboard()
    }

    /// Dựng KeyboardView + nối callback. Gọi ở viewDidLoad, và ở viewWillAppear khi CÙNG
    /// controller hiện lại sau khi viewDidDisappear đã xé cây view (RAM-AUDIT.md #1). Mọi cấu
    /// hình còn lại (trait ô, theme, một tay, gợi ý, vuốt…) viewWillAppear áp lại như với
    /// controller mới — iOS vốn tạo controller mới gần như mỗi lần hiện.
    private func installKeyboard() {
        // needsInputModeSwitchKey ở viewDidLoad CHƯA đáng tin (host chưa nối,
        // iOS còn in warning) — khởi tạo false, viewWillAppear set giá trị thật.
        keyboard = KeyboardView(
            needsGlobe: false,
            inputController: self,     // globe key addTarget thẳng vào handleInputModeList
            onKey: { [weak self] key in self?.handle(key) }
        )
        keyboard.onDeleteWord = { [weak self] in self?.deleteWordBackward() }
        wireWordSwipe()
        wireSwipeTyping()
        #if DEBUG
        Self.debugKeyboardInstalls += 1
        #endif
        keyboard.onBarToggle = { [weak self] in self?.updateSuggestions() }
        keyboard.onTemplate = { [weak self] in self?.insertTemplate($0) }
        keyboard.onOpenTemplates = { [weak self] in self?.openTemplatesInApp() }
        keyboard.onTextTool = { [weak self] in self?.applyTextTool($0) }
        keyboard.onOneHandChange = { side in
            // Bàn phím tự lưu (không Full Access thì không ghi được App Group).
            UserDefaults.standard.set(side.rawValue, forKey: OneHand.key)
            if side != .off { UserDefaults.standard.set(side.rawValue, forKey: OneHand.lastSideKey) }
        }
        keyboard.onOpenClipboard = { [weak self] in self?.toggleClipboardPanel() }
        keyboard.onPasteOfferVisible = { [weak self] on in
            guard let self else { return }
            if on { self.pasteOnce.displayed(self.pasteSeenChange) } else { self.pasteOnce.ended() }
        }
        keyboard.onSpaceFlick = { [weak self] in self?.toggleLanguage() }
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        // Như KeyboardView: nền trong suốt = touch xuyên sang app host (rớt phím).
        view.backgroundColor = KeyboardView.touchableClear
        view.addSubview(keyboard)
        keyboardEdges = [
            keyboard.leftAnchor.constraint(equalTo: view.leftAnchor),
            keyboard.rightAnchor.constraint(equalTo: view.rightAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(keyboardEdges)
    }
    /// 4 cạnh KeyboardView ↔ view gốc. Xé phải TỰ gỡ: removeFromSuperview không bỏ chúng
    /// khỏi mảng constraint của UIInputView (leaks --traceTree: UIInputView → constraint →
    /// anchor → KeyboardView cũ sống tiếp).
    private var keyboardEdges: [NSLayoutConstraint] = []

    #if DEBUG
    /// Test/bench (KeyboardBenchTests, CompositionSync…): proxy giả thay host. Release không có.
    var debugProxy: UITextDocumentProxy?
    override var textDocumentProxy: UITextDocumentProxy { debugProxy ?? super.textDocumentProxy }
    var debugKeyboard: KeyboardView { keyboard }
    /// Test: số lần dựng KeyboardView (viewDidLoad + mỗi lần hiện lại sau khi xé).
    static var debugKeyboardInstalls = 0
    /// Test: gửi thẳng một phím vào handle() (dấu câu, ⌫…) như KeyboardView gửi.
    func debugHandle(_ key: KeyboardView.Key) { handle(key) }
    /// Test: chạm một ô thanh gợi ý với payload này.
    func debugAcceptSuggestion(_ item: String) { acceptSuggestion(item) }
    #endif

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
        // Cùng controller hiện lại sau viewDidDisappear (cây view đã xé) → dựng mới, rồi phần
        // dưới áp lại toàn bộ cấu hình như lần hiện đầu.
        if keyboard.isTornDown { installKeyboard() }
        L10n.reload()   // ngôn ngữ giao diện app (uiLanguage) — một lần mỗi lần hiện
        TouchLog.loadSetting()
        // Lần hiện mới: không mang phần xin thêm (HostFill) của lần trước sang.
        hostFill.reset(); keyboard.hostFillExtra = 0; lastHostGeomKey = ""
        // Đọc settings MỘT lần mỗi lần hiện (trước đây EngineBridge() tự load lần hai).
        let settings = KeyboardSettings.load()
        bridge = EngineBridge(settings: settings)     // fresh settings + buffer
        externalChangePending = false
        lastKeyWasEmailTrigger = false
        restoreUndo = nil; undoOfferActive = false
        textToolUndo = nil
        keyboard.textToolsEnabled = PlusGate.isUnlocked(.textTools)
        checkExternalDictEdit()
        clip.load(from: UserDefaultsProvider.shared)
        pasteOnce.reload(offeredID: Self.loadPasteOffered())
        // Ẩn danh (thủ công, trong app): không học từ, không lưu clipboard.
        learnWordsSetting = settings.learnWords
        learnEnabled = settings.learnWords && !clip.incognito   // refreshFieldTraits tinh chỉnh theo ô
        suggestAnywaySetting = settings.suggestInNoSuggestFields
        keyboard.setClipboardButton(visible: clip.historyEnabled && hasFullAccess)
        filterSensitive = settings.filterSensitive
        showSuggestionsSetting = settings.showSuggestions
        autoCapitalizeSetting = settings.autoCapitalize
        autoSpaceSetting = settings.autoSpaceAfterPunct
        autoSpacePunct = nil; autoSpaceUnderLetter = nil
        swipeSetting = settings.swipeTyping
        swipeEnglishSetting = settings.swipeEnglish
        swipeFutoSetting = settings.swipeFuto
        smartTouchSetting = settings.smartTouch
        autoCorrectSetting = settings.autoCorrect && !settings.vniMode
        wordTouches.removeAll(); wordTouchesOk = false; pendingTouch = nil
        if autoCorrectSetting { loadSupplementaryLexicon() }
        loadSystemTextReplacements(settings)
        // Tắt ⇒ router không gọi prior (không closure, không cấp phát ở vùng biên phím).
        keyboard.letterPrior = smartTouchSetting ? { [weak self] in self?.smartTouchPrior() } : nil
        if smartTouchSetting { TelexKeyPrior.warmUpInBackground() }
        if !swipeSetting { swipe = nil }              // tắt ⇒ bỏ template (RAM)
        addTonesSetting = settings.addTonesChip && PlusGate.isUnlocked(.sentenceDiacritics)
        numberChipsSetting = settings.numberChips
        mathResultsSetting = settings.mathResults
        mathArmed = false; mathChip = nil
        emojiSuggestSetting = settings.emojiSuggest
        pasteButtonSetting = settings.pasteButton
        spaceFlickSetting = settings.spaceSwipeLanguage
        language = KeyboardLanguage.effective(
            stored: UserDefaults.standard.string(forKey: KeyboardLanguage.storageKey),
            flickEnabled: spaceFlickSetting)
        if language == .en { bridge.setEnglish(true, proxy: Proxy(p: textDocumentProxy)); warmUpEnglish() }
        keyboard.configureSpaceFlick(enabled: spaceFlickSetting, language: language)
        keyboard.configureKeyAlternates(numbers: settings.longPressNumbers, symbols: settings.longPressSymbols)
        warmUpData()
        swipeSuggest = nil
        recentEnglish = []; langRecent = []
        addTonesUndo = nil; addTonesDismissed = nil; addTonesCache = nil
        // Trait ô (layout, return key, passthrough, bar) — force: mỗi lần hiện áp lại
        // appearance/mẫu câu dù trait y hệt (batchConfigure tự dedupe rebuild).
        refreshFieldTraits(force: true)
        applyOneHandSetting()
        TouchLog.session(fullAccess: hasFullAccess, traits: fieldTraits?.logDescription ?? "")
        logHostGeometry("willAppear")
        // Rung phím: cần cả toggle trong app LẪN Toàn quyền Truy cập (iOS
        // vô hiệu haptics trong extension không có Full Access).
        KeyboardView.hapticsEnabled = settings.hapticFeedback && hasFullAccess
        KeyHaptics.log = { TouchLog.write($0) }
        KeyHaptics.shared.setStrength(settings.hapticStrength)
        TouchLog.write("haptics setting=\(settings.hapticFeedback ? 1 : 0) strength=\(settings.hapticStrength) fullAccess=\(hasFullAccess ? 1 : 0)")
        applyKeySound(settings)
        // Báo trạng thái Full Access cho app chứa (ẩn banner nhắc cấp quyền).
        // Không Full Access thì iOS chặn GHI App Group → cờ giữ nguyên/vắng,
        // banner vẫn hiện — đúng ý.
        reportStatusToApp()
        keyboard.onSuggestion = { [weak self] item in
            guard let self else { return }
            if item == KeyboardView.toolUndoToken { self.undoTextTool(); return }
            if let c = self.emailChips.first(where: { $0.label == item }) { self.acceptEmailChip(c); return }
            if self.urlChips.contains(where: { $0.label == item }) { self.acceptURLChip(item); return }
            self.textToolUndo = nil
            if item == KeyboardView.restoreToken { self.restoreWordSwipe() }
            else if item.hasPrefix(KeyboardView.clipTokenPrefix) {
                self.insertClip(String(item.dropFirst(KeyboardView.clipTokenPrefix.count)), chip: true)
            }
            else if item == KeyboardView.addTonesToken { self.applyAddTones() }
            else if item == KeyboardView.undoTonesToken { self.undoAddTones() }
            else if item == KeyboardView.undoReviseToken { self.undoSwipeRevision() }
            else if item == KeyboardView.undoAutoCorrectToken { self.revertAutoCorrect() }
            else if self.acceptSwipeAlternative(item) { return }
            else { self.acceptSuggestion(item) }
        }
        // Chạm ABC: đọc context lúc đó (". " tự thêm ở plane 123 ⇒ viết hoa) — XPC hiếm, không mỗi phím.
        keyboard.autoShiftProbe = { [weak self] in
            guard let self else { return nil }
            return FieldPolicy.autoShift(
                enabled: self.autoCapitalizeSetting,
                autocap: vtSafe(nil) { self.textDocumentProxy.autocapitalizationType ?? nil },
                before: { self.textDocumentProxy.documentContextBeforeInput ?? "" })
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
    /// Mốc "userlmResetAt" (App Group) lần hiện trước. App sửa Từ điển cá nhân / "Xóa từ
    /// đã học" ⇒ mốc đổi ⇒ bỏ bảng trong RAM, nạp lại file app vừa ghi (không ghi đè nó).
    private var seenDictResetAt: Double?
    private func checkExternalDictEdit() {
        let v = UserDefaults(suiteName: "group.com.viettelex")?.double(forKey: "userlmResetAt") ?? 0
        if let seen = seenDictResetAt, seen != v {
            langModelStorage?.reloadAfterExternalEdit()
            ctxCacheKey = nil
        }
        seenDictResetAt = v
    }

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
        pasteOnce.ended()   // ẩn bàn phím: lời mời dán đang hiện coi như đã bỏ qua
        closeClipboardPanel()
        learnSettledSwipe()
        swipe?.releaseFuto()  // FUTO Swipe (thử nghiệm): nhả ~2.5 MB khi ẩn
        KeySound.shared.shutdown()   // âm phím riêng: dừng engine khi ẩn (dựng lại lần hiện sau)
        langModelStorage?.saveNow()   // extension có thể bị kill ngay sau disappear
    }

    /// Âm thanh phím: BẬT + Full Access ⇒ tiếng riêng (engine dựng nền), không kèm click hệ
    /// thống. TẮT hoặc thiếu Full Access ⇒ click hệ thống như cũ, không dựng engine (0 chi phí).
    /// Âm lượng 0 % ⇒ im hẳn (không quay về click hệ thống).
    static func customKeySoundActive(setting: Bool, fullAccess: Bool) -> Bool { setting && fullAccess }

    private func applyKeySound(_ settings: KeyboardSettings) {
        let on = Self.customKeySoundActive(setting: settings.keySound, fullAccess: hasFullAccess)
        KeyboardView.customSoundEnabled = on
        KeySound.shared.setVolume(percent: settings.keySoundVolume)
        KeySound.shared.setStyle(settings.keySoundStyle)
        if on && settings.keySoundVolume > 0 { KeySound.shared.prepare() } else { KeySound.shared.shutdown() }
        if settings.keySound {
            TouchLog.write("keysound setting=1 style=\(settings.keySoundStyle) volume=\(settings.keySoundVolume) fullAccess=\(hasFullAccess ? 1 : 0)")
        }
    }

    /// Nạp NỀN dữ liệu tính năng đang BẬT (tắt ⇒ không nạp gì): model cá nhân + mô hình âm
    /// tiết vnlm.bin (bigram cho thanh gợi ý, trigram cho gõ vuốt — cùng một mmap); dạng không
    /// dấu (SwipeLexicon) chỉ cho gõ vuốt. vnlm: lần chạm đầu hash vnlexicon (~150KB) — đừng để
    /// rơi vào main.
    private func warmUpData() {
        let wantsLM = showSuggestionsSetting || swipeSetting || addTonesSetting
        if wantsLM { _ = langModel }
        let swipeOn = swipeSetting
        if showSuggestionsSetting || swipeOn {
            Self.suggestQueue.async {
                _ = SyllableLM.shared
                if swipeOn { _ = SwipeLexicon.forms }
            }
        }
    }

    /// Ẩn hẳn: bỏ cache/đề xuất tạm (template gõ vuốt GIỮ — dựng lại mỗi lần hiện tốn CPU
    /// hơn; nhả khi hệ thống báo thiếu RAM) và XÉ cây view (RAM-AUDIT.md #1: UIKit giữ
    /// UIInputView cũ mãi ⇒ không xé thì mỗi lần hiện rò ~1,8 MB).
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        swipeSuggest = nil
        addTonesCache = nil
        tearDownKeyboard()
    }

    private func tearDownKeyboard() {
        closeClipboardPanel()
        NSLayoutConstraint.deactivate(keyboardEdges)
        keyboardEdges = []
        keyboard?.tearDown()
        // Phòng hờ: thứ gì khác từng gắn vào view gốc cũng gỡ (view gốc là thứ UIKit níu).
        KeyboardView.stripSubviews(of: view)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        langModelStorage?.saveNow()
        closeClipboardPanel()
        addTonesCache = nil
        // Plane số/ký hiệu/chữ đang nằm cache (dựng lại khi cần), bảng emoji, ảnh nền đã giải
        // (view đang hiện vẫn giữ ảnh của nó — cache tĩnh chỉ để lần hiện sau khỏi giải lại).
        keyboard?.dropCaches()
        Wallpaper.queue.async { Wallpaper.dropCache() }
        if view.window == nil { swipe = nil }
        if view.window == nil { KeySound.shared.shutdown() }
    }

    // Host truyền .default là thường — dark/light thật nằm ở trait hệ thống,
    // đổi giữa chừng (auto dark theo giờ…) phải áp lại appearance.
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            keyboard?.applyAppearance(vtSafe(.default) { self.textDocumentProxy.keyboardAppearance ?? .default }, style: traitCollection.userInterfaceStyle)
        }
    }

    /// Apple behavior: shift turns on at sentence start when the field asks for
    /// .sentences autocapitalization (empty context, or after ".!?" + space).
    private func updateAutoShift() {
        // Tắt viết hoa đầu câu: chỉ hạ shift do chính mình bật trước đó (shift tay giữ nguyên).
        if !autoCapitalizeSetting, autoShiftOn { autoShiftOn = false; keyboard.setAutoShift(false) }
        guard let auto = FieldPolicy.autoShift(
            enabled: autoCapitalizeSetting,
            autocap: vtSafe(nil) { self.textDocumentProxy.autocapitalizationType ?? nil },
            before: { textDocumentProxy.documentContextBeforeInput ?? "" }) else { return }
        autoShiftOn = auto
        keyboard.setAutoShift(auto)
    }

    /// Trait ô hiện tại (nil = chưa đọc lần nào trong phiên).
    private var fieldTraits: FieldTraits?
    private var showSuggestionsSetting = true
    private var autoCapitalizeSetting = true
    /// "Tự thêm dấu cách sau dấu câu" (AutoSpace) — tắt ⇒ không đọc context, không state.
    private var autoSpaceSetting = false
    /// Dấu câu/ngoặc vừa được thêm dấu cách tự động (sống tới phím kế).
    private var autoSpacePunct: Character?
    /// Phím chữ gõ ngay sau dấu cách tự thêm — iPad vuốt xuống / giữ ra dấu câu huỷ phím
    /// chữ đó (replaceLastLetter) thì dấu cách tự thêm lại nằm ngay trước con trỏ.
    private var autoSpaceUnderLetter: Character?

    /// Dấu cách tự thêm sau `p` còn nằm ngay trước con trỏ (host/người dùng chưa đổi gì)?
    private func autoSpaceStillThere(_ p: Character) -> Bool {
        (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(String(p) + " ")
    }

    private func removeAutoSpace() {
        let was = applyingEdit
        applyingEdit = true
        textDocumentProxy.deleteBackward()
        applyingEdit = was
    }

    /// Sau phím chèn `s` (dấu câu, ký hiệu): thêm dấu cách nếu công tắc bật + ô cho phép
    /// + AutoSpace.shouldAdd; `carry` = dời dấu cách tự thêm ra sau ngoặc đóng vừa gõ.
    private func applyAutoSpace(after s: String, carry: Bool) {
        guard autoSpaceSetting, s.count == 1, let c = s.first,
              carry || AutoSpace.triggers.contains(c) else { return }
        guard fieldTraits?.allowsAutoSpace ?? true, !bridge.passthrough,
              vtSafe(false, { (self.textDocumentProxy as UITextInputTraits).isSecureTextEntry == true }) != true else { return }
        if !carry {
            guard AutoSpace.shouldAdd(punct: s, before: textDocumentProxy.documentContextBeforeInput ?? "",
                                      after: textDocumentProxy.documentContextAfterInput) else { return }
        }
        textDocumentProxy.insertText(" ")
        autoSpacePunct = c
    }

    /// Đọc trait ô và cấu hình lại bàn phím CHỈ khi trait đổi (hoặc `force` ở
    /// viewWillAppear). Host đổi ô trong cùng app không gọi viewWillAppear → gọi
    /// thêm ở textDidChange / selectionDidChange. KHÔNG đọc documentIdentifier.
    private var traitsRetryPending = false
    private func refreshFieldTraits(force: Bool = false) {
        let p = textDocumentProxy
        // iOS 27.0: đọc trait lúc proxy chưa sẵn sàng làm UIKit NÉM NSException
        // (_controllerState unrecognized selector) → bàn phím chết. Bắt lỗi, giữ trait
        // cũ và đọc lại sau một nhịp (crash thật 28/09/2026, build 1.2(7)).
        var read: FieldTraits?
        if let e = VTCatchException({
            read = FieldTraits(
                keyboardType: p.keyboardType ?? .default,
                returnKeyType: p.returnKeyType ?? .default,
                appearance: p.keyboardAppearance ?? .default,
                autocorrection: p.autocorrectionType ?? .default,
                contentType: p.textContentType ?? nil,
                secure: (p as UITextInputTraits).isSecureTextEntry == true)
        }) {
            TouchLog.write("traits: UIKit exception \(e.name.rawValue) — thử lại sau")
            if !traitsRetryPending {
                traitsRetryPending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.traitsRetryPending = false
                    self?.refreshFieldTraits(force: force)
                }
            }
            return
        }
        guard let t = read else { return }
        let old = fieldTraits
        guard force || FieldTraits.needsReconfigure(old: old, new: t) else { return }
        fieldTraits = t
        if !force { TouchLog.traits(t.logDescription); pasteOnce.ended() }   // đổi ô
        // Ô email/URL/username/OTP: gõ literal. KHÔNG dựa vào autocorrect == .no —
        // Safari/Chrome/Spotlight tắt autocorrect ở ô tìm kiếm (xem FieldPolicy).
        // Đổi chế độ giữa từ → bỏ từ đang gõ (engine không còn khớp cách chèn).
        if bridge.passthrough != t.passthrough {
            bridge.reset()
            bridge.passthrough = t.passthrough
        }
        // Omnibox (inline autocomplete tự viết lại chữ): không với lại từ đã chốt.
        bridge.reachBackAllowed = t.keyboardType != .webSearch
        bridge.shortcutsAllowed = t.keyboardType != .webSearch   // omnibox: không gõ tắt
        // Tự sửa: công tắc + loại ô (mật khẩu/email/URL/số/omnibox/ô tên ⇒ không).
        let ac = autoCorrectSetting && AutoCorrect.fieldAllows(t)
        if force || ac != autoCorrectActive {
            autoCorrectActive = ac
            bridge.autoCorrector = ac ? { [weak self] raw in self?.autoCorrection(raw) } : nil
            keyboard.onLetterTouch = ac ? { [weak self] dx, dy in self?.pendingTouch = AutoCorrect.Touch(dx: dx, dy: dy) } : nil
        }
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
        // Thanh gợi ý: gate qua toggle trong app. Ô từ chối gợi ý chữ (autocorrection = .no:
        // thanh địa chỉ Safari…) mà không nhạy cảm ⇒ thanh CÔNG CỤ (☰/📋/⌄ + Dán + chip URL)
        // thay vì dải trống; mật khẩu/OTP/ẩn danh/bàn số giữ dải trống (StripMode).
        // #113 "Gợi ý cả khi ứng dụng tắt gợi ý" (mặc định bật): ô .no không nhạy cảm ⇒ gợi ý
        // đầy đủ, nhưng tự sửa vẫn tắt (allowsSuggestions false ở trên) và không học từ.
        let mode = StripMode.of(showSuggestions: showSuggestionsSetting, traits: t,
                                incognito: clip.incognito, suggestAnyway: suggestAnywaySetting)
        learnEnabled = StripMode.learns(learnWords: learnWordsSetting, traits: t, incognito: clip.incognito)
        lowercaseSuggestions = t.lowercaseSuggestions
        let active = mode.shown
        let modeChanged = mode != stripMode
        stripMode = mode
        if force || active != suggestionsActive || modeChanged {
            suggestionsActive = active
            // Strip giữ theo công tắc toàn cục: đổi sang ô không gợi ý không làm bàn phím
            // thấp/cao lại (host không luôn cấp lại ⇒ phím bị ép — bug 1.2.x).
            keyboard.setSuggestionsEnabled(active, reserveStrip: showSuggestionsSetting)
            // Đổi ô giữa chừng (selectionDidChange không tự vẽ lại bar): nội dung theo chế độ mới.
            if !force, active { updateSuggestions() }
        }
        updateSwipeEnabled()
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
            langRecent = []
            restoreUndo = nil; undoOfferActive = false
            swipeTyped = nil; swipeTypedUndo = nil
        }
    }

    override func textWillChange(_ textInput: UITextInput?) {
        // Thay đổi từ NGOÀI edit của mình (tap chỗ khác, đổi ô, host tự gán lại
        // text…). Edit của mình không gọi lại hàm này trong lúc handle() chạy.
        TouchLog.host("textWillChange", applyingEdit: applyingEdit, composing: bridge.isComposing)
        if !applyingEdit, !trackpadActive { externalChangePending = true }
    }

    // Selection/con trỏ vừa đổi từ NGOÀI (select-all rồi gõ đè, tap chỗ khác,
    // app tự sửa text): quyết định giữ/bỏ từ đang gõ, đọc lại trait ô, tính lại
    // auto-shift như stock — select-all thì documentContextBeforeInput rỗng → viết
    // hoa chữ đầu. Không tính ở textWillChange vì lúc đó context THÁO DỞ.
    override func textDidChange(_ textInput: UITextInput?) {
        TouchLog.host("textDidChange", applyingEdit: applyingEdit, composing: bridge.isComposing)
        if !applyingEdit, !trackpadActive {
            if externalChangePending { syncComposition("textDidChange") }
            refreshFieldTraits()
            updateAutoShift()
            updateSuggestions()
        }
    }

    override func selectionWillChange(_ textInput: UITextInput?) {
        if !applyingEdit, !trackpadActive { externalChangePending = true }
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        TouchLog.host("selectionDidChange", applyingEdit: applyingEdit, composing: bridge.isComposing)
        if !applyingEdit, !trackpadActive {
            if externalChangePending { syncComposition("selectionDidChange") }
            refreshFieldTraits()
        }
    }

    // MARK: chế độ một tay

    /// App (App Group) vừa đổi lựa chọn ⇒ theo app; không thì theo trạng thái bàn phím tự lưu.
    private func applyOneHandSetting() {
        let std = UserDefaults.standard
        let group = UserDefaultsProvider.shared?.string(forKey: OneHand.key)
        let seen = std.string(forKey: OneHand.seenGroupKey)
        let side = OneHand.resolve(group: group, seenGroup: seen, local: std.string(forKey: OneHand.key))
        if group != seen {
            std.set(group, forKey: OneHand.seenGroupKey)
            std.set(side.rawValue, forKey: OneHand.key)
        }
        if let last = std.string(forKey: OneHand.lastSideKey).flatMap(OneHandSide.init(rawValue:)), last != .off {
            keyboard.lastOneHandSide = last
        }
        keyboard.configureOneHand(side)
    }

    private var applyingEdit = false

    private struct Proxy: TextProxyLike {
        let p: UITextDocumentProxy
        func insertText(_ text: String) { p.insertText(text) }
        func deleteBackward() { p.deleteBackward() }
        var isSecure: Bool { vtSafe(false) { (p as UITextInputTraits).isSecureTextEntry == true } }
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
        let touch = pendingTouch           // điểm chạm của phím chữ này (tự sửa), dùng một lần
        pendingTouch = nil
        // ⌫ NGAY SAU khi thêm dấu = hoàn tác (một lần); phím khác bỏ lời mời hoàn tác.
        if case .backspace = key, addTonesUndo != nil, !bridge.isComposing, swipeSuggest == nil {
            undoAddTones()
            return
        }
        addTonesUndo = nil
        let proxy = Proxy(p: textDocumentProxy)
        // textWillChange tới mà textDidChange chưa kịp → đối chiếu ngay trước phím.
        if externalChangePending, !trackpadActive { syncComposition("key") }
        // Tự thêm dấu cách sau dấu câu: phím ngay sau quyết định số phận dấu cách đó.
        var autoSpaceCarry = false
        let underLetter = autoSpaceUnderLetter
        autoSpaceUnderLetter = nil
        if let p = autoSpacePunct {
            autoSpacePunct = nil
            if autoSpaceStillThere(p) {
                switch key {
                case .space, .doubleSpacePeriod:
                    return                                // đã có dấu cách: nuốt, không thành 2
                case .backspace:
                    removeAutoSpace()                     // ⌫ chỉ xoá dấu cách tự thêm
                    lastInsertWasSpace = false
                    suggestionGen += 1
                    let gen = suggestionGen
                    DispatchQueue.main.async { [weak self] in
                        guard let self, gen == self.suggestionGen else { return }
                        self.updateAutoShift()
                        if self.suggestionsActive { self.updateSuggestions() }
                    }
                    return
                case .newline:
                    removeAutoSpace()
                case .text(let s):
                    switch AutoSpace.reaction(toText: s) {
                    case .keep: break
                    case .remove: removeAutoSpace()
                    case .carry: removeAutoSpace(); autoSpaceCarry = true
                    }
                case .letter:
                    autoSpaceUnderLetter = p
                default: break
                }
            }
        }
        if textToolUndo != nil {               // ⌫ ngay sau công cụ văn bản = hoàn tác
            if case .backspace = key { undoTextTool(); return }
            textToolUndo = nil
        }
        wordSwipeRestore = nil                 // ô "Khôi phục" chỉ sống tới phím kế
        learnSettledSwipe()                    // từ vuốt chốt bởi phím trước — giờ mới chắc
        let openAccepted = bridge.openWordAccepted   // từ vuốt chọn trên bar → weight 2
        // Sửa lại từ vuốt khi từ kế GÕ PHÍM: phím chữ/dấu cách chốt từ vuốt còn nguyên ⇒ chờ;
        // đang chờ ⇒ phím chữ / ⌫ trong từ gõ giữ, ranh giới thử sửa, phím khác bỏ.
        var typedWait = swipeTyped
        swipeTyped = nil
        swipeTypedUndo = nil
        if let w = typedWait, w.learned == nil, let l = lastLearned, l.word == w.rev.word {
            typedWait = (w.rev, l)             // dấu cách treo: từ vuốt vừa được học ở trên
        }
        let typedArm = typedArmCandidate(key)
        let composingBefore = bridge.isComposing
        var typedCommit: (word: String, boundary: String)?
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
                case .moveLine: kind = "line"
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
            let fresh = !bridge.isComposing
            bridge.letter(ch, proxy: proxy)
            restoreUndo = nil; undoOfferActive = false
            if autoCorrectActive { noteTouch(fresh: fresh, touch) }
        case .replaceLastLetter(let s):
            // Huỷ đúng phím chữ vừa gõ (không được thì ⌫ như cũ) rồi chèn như ký hiệu.
            if !bridge.undoLastLetter(proxy: proxy) { bridge.backspace(proxy: proxy) }
            if let q = underLetter, autoSpaceSetting {
                let r = AutoSpace.reaction(toText: s)
                if r != .keep, autoSpaceStillThere(q) { removeAutoSpace(); autoSpaceCarry = r == .carry }
            }
            if let d = Self.singleDigit(s), bridge.vniDigit(d, proxy: proxy) {
                // VNI: số vuốt xuống (iPad) trong từ = phím dấu
            } else {
                commitAndLearn(bridge.boundary(s, proxy: proxy), accepted: openAccepted)
                lastWord = nil; lastWord2 = nil
                applyAutoSpace(after: s, carry: autoSpaceCarry)
            }
            restoreUndo = nil; undoOfferActive = false
        case .text(let s):                            // numbers, symbols
            if let d = Self.singleDigit(s), bridge.vniDigit(d, proxy: proxy) {
                // VNI: số trong lúc soạn từ (hàng số / plane 123) mang dấu — phím của từ
            } else {
                let final = bridge.boundary(s, proxy: proxy)
                commitAndLearn(final, accepted: openAccepted)
                lastWord = nil; lastWord2 = nil            // dấu câu/ký hiệu = ngắt câu
                typedCommit = (final, s)
                applyAutoSpace(after: s, carry: autoSpaceCarry)
            }
            restoreUndo = nil; undoOfferActive = false
        case .space:
            let composedBefore = bridge.composedWord
            let committed = bridge.boundary(" ", proxy: proxy)
            // Auto-restore vừa ghi đè dạng có dấu → nhớ lại cho backspace-undo.
            // (Gõ tắt vừa bung thì không: ⌫ kế tiếp tự trả lại chữ tắt trong bridge.)
            restoreUndo = (!composedBefore.isEmpty && committed != composedBefore
                           && !bridge.expandedAtLastBoundary)
                ? (raw: committed, composed: composedBefore) : nil
            undoOfferActive = false
            commitAndLearn(committed, accepted: openAccepted)
            typedCommit = (committed, " ")
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
                commitAndLearn(bridge.boundary(" ", proxy: proxy), accepted: openAccepted)
            }
            restoreUndo = nil; undoOfferActive = false
        case .moveCursor(let delta):
            bridge.reset()                        // caret moved → composition gone
            lastWord = nil; lastWord2 = nil
            restoreUndo = nil; undoOfferActive = false
            if trackpadActive {
                // Giữ view context khớp chỗ con trỏ cho bước dọc sau (host trả context trễ).
                _ = trackpadContext.resolve(before: textDocumentProxy.documentContextBeforeInput ?? "",
                                            after: textDocumentProxy.documentContextAfterInput ?? "")
                trackpadContext.moved(by: delta)
            }
            textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
        case .moveLine(let lines):
            // Gần đúng: proxy không biết bố cục host — VerticalMove dựng lại dòng hiển thị
            // (ngắt cứng + tự ngắt theo ký tự/dòng ước lượng), giữ cột grapheme.
            bridge.reset()
            lastWord = nil; lastWord2 = nil
            restoreUndo = nil; undoOfferActive = false
            let ctx = trackpadContext.resolve(before: textDocumentProxy.documentContextBeforeInput ?? "",
                                              after: textDocumentProxy.documentContextAfterInput ?? "")
            if trackpadCharsPerLine == 0 { trackpadCharsPerLine = estimateCharsPerLine() }
            if let off = VerticalMove.offset(before: ctx.before, after: ctx.after, lines: lines,
                                             charsPerLine: trackpadCharsPerLine), off != 0 {
                trackpadContext.moved(by: off)
                textDocumentProxy.adjustTextPosition(byCharacterOffset: off)
            }
            if !trackpadActive { trackpadContext.reset() }
        case .newline:
            let final = bridge.boundary("\n", proxy: proxy)
            commitAndLearn(final, accepted: openAccepted)
            lastWord = nil; lastWord2 = nil
            typedCommit = (final, "\n")
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
            wordTouchesOk = false
            let acUndo = bridge.autoCorrectUndo
            if bridge.backspace(proxy: proxy) {
                // ⌫ mở lại từ vừa chốt: từ đó không còn là "từ trước" trong câu.
                lastWord = lastWord2; lastWord2 = nil
            }
            if !bridge.isComposing { lastWord = nil; lastWord2 = nil }  // xoá lấn vào chữ cũ → context mờ
            if let orig = bridge.revertedAutoCorrect {
                bridge.revertedAutoCorrect = nil
                autoCorrectReverted(orig, fixed: acUndo?.fixed)
            }
        }
        if let a = typedArm {
            // phím chữ: dấu cách treo đã chốt từ vuốt (từ gõ bắt đầu); dấu cách: chốt đúng từ vuốt
            if case .letter = key, !bridge.isSwipeWordOpen, bridge.isComposing { swipeTyped = (a, nil) }
            if case .space = key, typedCommit?.word == a.word {
                swipeTyped = (a, lastLearned.flatMap { $0.word == a.word ? $0 : nil })
            }
        } else if let w = typedWait {
            if let c = typedCommit {
                if composingBefore, !bridge.englishMode {
                    reviseTypedSwipe(w, typed: c.word, boundary: c.boundary, proxy: proxy)
                }
            } else if bridge.isComposing {
                switch key {
                case .letter: swipeTyped = w
                case .backspace where composingBefore: swipeTyped = w
                case .text: if composingBefore { swipeTyped = w }     // VNI: số mang dấu trong từ
                default: break
                }
            }
        }
        // Chip số: chỉ đọc context khi vừa có chữ số/phép tính trong token này hoặc
        // token ngay trước ("2 tỷ", "1250000 ") — không trả XPC cho mọi phím chữ.
        switch key {
        case .text(let s), .replaceLastLetter(let s):
            numberSpaces = s.first.map { $0.isNumber || "=+-*/×÷:%().,".contains($0) } == true ? 0 : 99
        case .space, .doubleSpacePeriod: numberSpaces += 1
        case .backspace: numberSpaces = 0
        case .letter: break
        default: numberSpaces = 99
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
        // Kết quả phép tính: chỉ ngay sau "=" (ô mật khẩu/URL/email: không).
        if case .text("=") = key, mathResultsSetting, fieldTraits?.allowsMathResults != false {
            mathArmed = true
        } else {
            mathArmed = false
        }
        // updateAutoShift đọc documentContextBeforeInput (XPC) → cùng khối
        // async với suggestions, coalesce theo generation: gõ nhanh chỉ tính
        // cho phím cuối, ký tự không bao giờ chờ. Sound đã phát ở touch-down.
        let needsAutoShift: Bool
        switch key {
        case .space, .newline, .doubleSpacePeriod, .backspace, .moveCursor, .moveLine, .clearField: needsAutoShift = true
        default: needsAutoShift = autoSpacePunct != nil      // ". " tự thêm ⇒ viết hoa chữ kế
        }
        suggestionGen += 1
        let gen = suggestionGen
        // Trackpad đang kéo: auto-shift + gợi ý tính một lần lúc nhả tay (trackpadChanged).
        if trackpadActive { return }
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
        // Bar tắt / thu gọn ⇒ không lên lịch gì (0 closure, 0 timer mỗi phím).
        guard suggestionsActive, keyboard?.isBarCollapsed != true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, gen == self.suggestionGen else { return }
            self.updateSuggestions()
        }
    }

    // MARK: tự sửa (AutoCorrect)

    /// Ghi điểm chạm phím chữ vừa gõ; `fresh` = phím đầu của từ mới.
    private func noteTouch(fresh: Bool, _ touch: AutoCorrect.Touch?) {
        if fresh { wordTouches.removeAll(keepingCapacity: true); wordTouchesOk = true }
        if let touch { if wordTouchesOk { wordTouches.append(touch) } } else { wordTouchesOk = false }
        if wordTouches.count != bridge.rawWord.count { wordTouchesOk = false }   // nạp lại từ cũ, phím ngoài engine…
    }

    /// `EngineBridge.autoCorrector`: chỉ khi có đủ điểm chạm cho đúng các phím của từ.
    private func autoCorrection(_ raw: String) -> String? {
        guard wordTouchesOk, wordTouches.count == raw.count else { return nil }
        let b = bridge
        return AutoCorrect.correction(
            raw: raw, touches: wordTouches, compose: { b.composeTrial($0) },
            frequency: { VNSuggest.frequency(of: $0) },
            hasCompletion: { !VNSuggest.matches($0, poolLimit: 1).isEmpty },
            isKnown: { [self] w in
                autoCorrectRejected.contains(w) || lexiconWords.contains(w)
                    || langModel.isUserWord(w) || AutoCorrect.isEnglish(w)
            })
    }

    /// Chip "↩︎ chữ gốc".
    private func revertAutoCorrect() {
        let fixed = bridge.autoCorrectUndo?.fixed
        applyingEdit = true
        let ok = bridge.revertAutoCorrect(proxy: Proxy(p: textDocumentProxy))
        applyingEdit = false
        if ok, let orig = bridge.revertedAutoCorrect {
            bridge.revertedAutoCorrect = nil
            autoCorrectReverted(orig, fixed: fixed)
        }
        KeyboardView.clickModifier()
        updateAutoShift()
        updateSuggestions()
    }

    /// Vừa trả lại chữ gốc: nhớ để không sửa lại, rút lượt học từ đã sửa, học chữ gốc.
    private func autoCorrectReverted(_ original: String, fixed: String?) {
        if autoCorrectRejected.add(original) {
            UserDefaults.standard.set(autoCorrectRejected.encode(), forKey: Self.rejectedKey)
        }
        if let l = lastLearned, l.word == fixed {
            if let r = l.receipt { langModel.retract(r) }
            lastWord = l.prev1; lastWord2 = l.prev2
        }
        lastLearned = nil
        commitAndLearn(original)
    }

    /// Thay thế văn bản (Cài đặt → Bàn phím) + tên danh bạ: không cần Toàn quyền truy cập;
    /// iOS trả bất đồng bộ — nạp một lần mỗi phiên, chỉ khi tự sửa bật.
    private func loadSupplementaryLexicon() {
        guard lexiconWords.isEmpty else { return }
        supplementaryLexicon.get { [weak self] pairs in
            var words: Set<String> = []
            for e in pairs {
                for s in [e.input, e.text] {
                    for w in s.lowercased().split(whereSeparator: { !$0.isLetter }) where w.count >= 2 {
                        words.insert(String(w))
                    }
                }
            }
            self?.lexiconWords = words
        }
    }

    /// Thay thế văn bản iOS làm gõ tắt (SystemTextReplacement): bất đồng bộ, ngoài đường
    /// hiện bàn phím; gộp vào bridge hiện tại khi có. Ghi snapshot cho app (cần Toàn quyền).
    private func loadSystemTextReplacements(_ settings: KeyboardSettings) {
        systemReplacements.load(settings: settings, bridge: { [weak self] in self?.bridge }) { [weak self] entries in
            guard let self else { return }
            TouchLog.write("system text replacement: \(entries.count)")
            if self.hasFullAccess {
                SystemTextReplacement.writeSnapshot(.init(entries), to: UserDefaultsProvider.shared)
            }
        }
    }

    /// "0"…"9" đơn lẻ (phím số) — ứng viên phím dấu VNI; ký hiệu khác ⇒ nil.
    private static func singleDigit(_ s: String) -> Character? {
        guard s.count == 1, let c = s.first, c.isASCII, c.isNumber else { return nil }
        return c
    }

    private var suggestionGen = 0
    /// Công tắc phụ của thanh gợi ý (KeyboardSettings) — đọc mỗi lần hiện.
    private var addTonesSetting = false
    private var numberChipsSetting = true
    /// "Hiện kết quả phép tính" (KeyboardSettings.mathResults).
    private var mathResultsSetting = true
    private var emojiSuggestSetting = true
    private var pasteButtonSetting = true
    /// Đang giữ phím cách di con trỏ (KeyboardView.onTrackpad) — xem trackpadChanged.
    private var trackpadActive = false
    /// Context host đã dời theo lệnh trackpad của mình (host cập nhật bất đồng bộ).
    private var trackpadContext = TrackpadContext()
    /// Ký tự/dòng hiển thị ước lượng cho kéo dọc — tính lúc bắt đầu kéo (0 = chưa).
    private var trackpadCharsPerLine = 0
    /// Câu mẫu đo một lần theo cỡ chữ (Dynamic Type): (category, bề rộng ký tự TB).
    private var trackpadAdvance: (UIContentSizeCategory, Double)?
    /// Số lượt updateSuggestions — kết quả nền chỉ áp nếu là lượt mới nhất.
    private var suggestReq = 0
    private static let suggestQueue = DispatchQueue(label: "com.viettelex.suggest",
                                                    qos: .userInitiated)
    private var lastInsertWasSpace = false
    private var autoShiftOn = false
    private var suggestionsActive = true
    /// Dải gợi ý ở ô hiện tại (StripMode): .tools = chỉ thanh công cụ + Dán + chip URL.
    private var stripMode = StripMode.full
    /// Chip URL đang hiện (ô URL / thanh địa chỉ ở chế độ .tools — URLChips); rỗng ở ô khác.
    private var urlChips: [URLChips.Chip] = []
    /// Cài đặt "Gợi ý cả khi ứng dụng tắt gợi ý" (KeyboardSettings.suggestInNoSuggestFields).
    private var suggestAnywaySetting = true
    /// KeyboardSettings.learnWords — learnEnabled tính lại theo ô (StripMode.learns).
    private var learnWordsSetting = true
    /// Ô địa chỉ / tìm kiếm (FieldTraits.lowercaseSuggestions): gợi ý chữ thường.
    private var lowercaseSuggestions = false
    /// Phím vừa gõ là "@" hoặc "." → rule email/TLD mới có thể ăn; chỉ khi đó
    /// mới đáng trả giá XPC đọc documentContextBeforeInput.
    private var lastKeyWasEmailTrigger = false
    /// Số dấu cách kể từ chữ số/phép tính cuối (≤1 → đáng đọc context tìm chip số).
    private var numberSpaces = 99
    /// Chip số đang hiện (đuôi cần thay + chữ chèn) — payload KeyboardView.numberToken.
    private var numberChip: NumberChip?
    /// Phím vừa gõ là "=" (công tắc bật, ô cho phép) — chỉ khi đó mới đọc context tìm
    /// kết quả phép tính (MathResults); phím khác ⇒ 0 việc.
    private var mathArmed = false
    /// Chip kết quả phép tính đang hiện — payload KeyboardView.mathToken.
    private var mathChip: NumberChip?
    /// Chip đuôi mail đang hiện (ô email — EmailDomains); rỗng ở ô khác.
    private var emailChips: [EmailDomains.Chip] = []
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
            appearance: vtSafe(.default) { self.textDocumentProxy.keyboardAppearance ?? .default },
            style: traitCollection.userInterfaceStyle))
        keyboard?.setNeedsGlobe(needsInputModeSwitchKey)
        pushSwipeLayout(prepare: true)       // frame phím đã thật → dựng template ở nền
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
        addTonesUndo = nil
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
        // Nội dung gõ tắt nhiều từ ("mọi người"): học lần lượt từng từ (bigram trong cụm).
        let parts = ShortcutLearning.words(word)
        if parts.count != 1 || parts.first != word {
            for p in parts { commitAndLearn(p, accepted: accepted) }
            if parts.isEmpty { lastWord = nil; lastWord2 = nil }
            return
        }
        let receipt = learnEnabled ? langModel.record(word: word, after: lastWord, prev2: lastWord2,
                                                      weight: accepted ? 2 : 1) : nil
        lastLearned = (word, receipt, lastWord, lastWord2)
        if UserLangModel.learnable(word) {
            lastWord2 = lastWord
            lastWord = word
            if swipe != nil, swipeEnglishSetting {   // tắt vuốt / vuốt tiếng Anh ⇒ 0 chi phí
                langRecent.append(word)
                if langRecent.count > SwipeLangContext.window { langRecent.removeFirst() }
            }
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
        if lowercaseSuggestions { return w.lowercased() }
        return autoShiftOn ? w.prefix(1).uppercased() + w.dropFirst() : w
    }

    /// DisplayCase (tên riêng) — trừ ô địa chỉ / tìm kiếm: chữ thường (song sinh Android).
    private func displayCase(_ w: String, after prev: String? = nil) -> String {
        lowercaseSuggestions ? w.lowercased() : DisplayCase.apply(w, after: prev)
    }

    /// Đệm danh sách gợi ý cho ĐỦ `need` phần tử bằng từ hay dùng nhất (loại
    /// trùng + từ đang gõ) — bar luôn đủ 3, không bao giờ trống/khuyết
    /// (user 2026-07-25). Model đã seed nên topWords luôn đủ.
    private func padWords(_ base: [String], need: Int, typed: String = "") -> [String] {
        guard base.count < need else { return Array(base.prefix(need)) }
        let top = bridge.englishMode ? SwipeEnglish.top : langModel.topWords(limit: need + 12)
        let candidates = SensitiveWords.filter(top, enabled: filterSensitive)
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
        numberChip = nil; mathChip = nil; emailChips = []; urlChips = []
        // Ô từ chối gợi ý chữ (không nhạy cảm): chỉ thanh công cụ — lời mời Dán + chip URL.
        if stripMode == .tools {
            showToolsOnly(composing: !composed.isEmpty)
            return
        }
        // Ô URL / tìm kiếm ở chế độ đầy đủ (gợi ý bất chấp app, #113): chip URL chỉ ở "vị trí
        // tên miền" (ô trống / token có "." hoặc "://"), còn lại gợi ý chữ.
        if fieldTraits?.wantsURLChips == true {
            let p = textDocumentProxy
            let before = p.documentContextBeforeInput ?? "", after = p.documentContextAfterInput ?? ""
            if StripMode.prefersURLChips(before: before, after: after),
               !URLChips.chips(before: before, after: after).isEmpty {
                showToolsOnly(composing: !composed.isEmpty)
                return
            }
        }
        // Ô email (literal): thanh chỉ hiện chip đuôi mail sau "@" ("@gmail.com" trước) —
        // đọc context mỗi phím CHỈ ở ô email; ô khác không qua nhánh này.
        if fieldTraits?.inputKind == .email {
            emailChips = textDocumentProxy.documentContextBeforeInput
                .map { EmailDomains.chips(before: $0) } ?? []
            keyboard.showSuggestions(.init(nextWords: emailChips.map(\.label)))
            return
        }
        // Ngay sau vuốt: phương án khác (biến thể dấu + dạng không dấu hạng 2/3) —
        // chỉ khi từ vuốt còn mở và chưa bị sửa.
        if let s = swipeSuggest {
            if bridge.isSwipeWordOpen, composed == s.current {
                keyboard.hidePasteCard()
                set.nextWords = s.alts
                if let u = swipeReviseUndo {
                    set.actionLabel = "\u{21A9}\u{FE0E} \(u.old)"
                    set.actionPayload = KeyboardView.undoReviseToken
                }
                keyboard.showSuggestions(set)
                return
            }
            swipeSuggest = nil
            swipeReviseUndo = nil
        }
        // Backspace-undo sau auto-restore: chào dạng có dấu ở slot literal.
        if composed.isEmpty, undoOfferActive, let u = restoreUndo {
            set.literal = u.composed
        }
        if composed.isEmpty, wordSwipeRestore != nil { set.restoreLabel = L("\u{21A9}\u{FE0E} Khôi phục") }
        if composed.isEmpty, textToolUndo != nil {
            set.restoreLabel = L("\u{21A9}\u{FE0E} Hoàn tác")
            set.restorePayload = KeyboardView.toolUndoToken
        }
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
            let prev = lastWord, prev2 = lastWord2, english = b.englishMode
            Self.suggestQueue.async { [weak self] in
                // Chế độ Tiếng Anh: hoàn thành từ enlexicon, không sửa chạm trượt / bigram Việt.
                let pool = english ? SwipeEnglish.completions(composed, limit: 24)
                    : VNSuggest.matches(composed, poolLimit: 24, excluding: composed.lowercased())
                let fix = !english && pool.isEmpty && wantFix
                    ? AdjacentKeyFixer.lexiconCorrection(raw: raw, bridge: b) : nil
                // trượt vào phím thanh mà vẫn ra từ ("casn" → cán, ý là cân)
                let slip = fix == nil && wantFix ? AdjacentKeyFixer.lexiconToneSlip(raw: raw, bridge: b) : nil
                // trigram/bigram âm tiết tĩnh theo 1–2 từ trước (mmap dùng chung với gõ vuốt; tra ~µs)
                let pmi = english ? nil : SuggestRank.inlinePmi(pool, prev: prev, prev2: prev2)
                DispatchQueue.main.async {
                    guard let self, req == self.suggestReq, gen == self.suggestionGen,
                          self.bridge === b, b.composedWord == composed,
                          self.suggestionsActive, self.keyboard?.isBarCollapsed != true
                    else { return }
                    self.showComposingSuggestions(composed: composed, raw: raw, predicted: predicted,
                                                  pool: pool, pmi: pmi, fix: fix, slip: slip)
                }
            }
            return
        } else if bridge.englishMode {
            // Tiếng Anh: từ kế tiếp cá nhân chỉ giữ từ tiếng Anh; đệm bằng từ Anh phổ biến
            let personal = lastWord.map { langModel.nextWords(after: $0, prev2: lastWord2, limit: 12) } ?? []
            let en = SensitiveWords.filter(personal.filter { SwipeEnglish.contains($0.lowercased()) },
                                           enabled: filterSensitive).prefix(3)
            set.nextWords = padWords(en.map { caseForContext($0) }, need: 3)
        } else if let prev = lastWord {
            // vừa space sau một từ → gợi từ KẾ TIẾP (SuggestRank.nextFill): có trigram tĩnh
            // (prev2, prev) ⇒ bộ ba người dùng đã gõ, rồi trigram, rồi cá nhân/seed; không ⇒
            // cá nhân/seed trước, lấp bằng bigram tĩnh; rồi mới tới topWords
            let p2 = lastWord2, lm = langModel, fs = filterSensitive
            let personal = SensitiveWords.filter(lm.nextWords(after: prev, prev2: p2, limit: 6), enabled: fs)
            let next = SuggestRank.nextFill(prev, prev2: p2, personal: personal,
                                            triCount: { w in p2.map { lm.trigramCount($0, prev, w) } ?? 0 },
                                            filter: { SensitiveWords.filter($0, enabled: fs) })
            set.nextWords = padWords(next.map { caseForContext(DisplayCase.apply($0, after: prev)) }, need: 3)
        } else {
            // field trống chưa gõ gì → từ user hay mở đầu nhất
            let top = SensitiveWords.filter(langModel.topWords(limit: 6),
                                            enabled: filterSensitive)
                .prefix(3).map { caseForContext(DisplayCase.apply($0)) }
            set.nextWords = padWords(Array(top), need: 3)
        }
        set.number = refreshNumberChip()
        set.math = refreshMathChip()
        if composed.isEmpty, pasteOffer() {
            // Nút Dán tắt: vẫn ghi lịch sử + chip tách số (thuộc Lịch sử clipboard).
            set.paste = pasteButtonSetting; set.pasteIsImage = pasteIsImage
            let chips = clip.chips(currentChange: pasteSeenChange, usedChange: pasteUsedChange)
            // Chip tách số (≤2) + ô "Dán" nguyên văn ở cuối: SuggestionSlots.arrange.
            set.clipChips = chips.map { ($0.label, KeyboardView.clipTokenPrefix + $0.value) }
        }
        // Thêm dấu: "Hoàn tác" (vừa bấm) thắng thẻ Dán; "Thêm dấu" nhường thẻ Dán
        // (thứ tự slot: SuggestionSlots.arrange).
        if composed.isEmpty, set.literal == nil, !bridge.englishMode || addTonesUndo != nil {
            if addTonesUndo != nil {
                set.actionLabel = L("\u{21A9}\u{FE0E} Hoàn tác"); set.actionPayload = KeyboardView.undoTonesToken
                set.paste = false; set.clipChips = []
            } else if addTonesPlan() != nil {
                set.actionLabel = L("Thêm dấu"); set.actionPayload = KeyboardView.addTonesToken
            }
        }
        // Vừa tự sửa: chip "↩︎ chữ gốc" (một chạm trả lại) thắng mọi chip khác tới phím kế.
        if composed.isEmpty, let u = bridge.autoCorrectUndo {
            set.actionLabel = "\u{21A9}\u{FE0E} \(u.original)"; set.actionPayload = KeyboardView.undoAutoCorrectToken
            set.literal = nil; set.paste = false; set.clipChips = []
        }
        // Vừa sửa lại từ vuốt theo từ gõ: chip "↩︎ từ cũ" tới phím kế.
        if composed.isEmpty, let u = swipeTypedUndo {
            set.actionLabel = "\u{21A9}\u{FE0E} \(u.edit.old)"; set.actionPayload = KeyboardView.undoReviseToken
            set.literal = nil; set.paste = false; set.clipChips = []
        }
        keyboard.showSuggestions(set)
    }

    /// Chip số cho token trước con trỏ (NumberChips — đọc chữ / định dạng tiền / máy tính).
    private func refreshNumberChip() -> String? {
        numberChip = nil
        guard numberChipsSetting, numberSpaces <= 1,
              let before = textDocumentProxy.documentContextBeforeInput else { return nil }
        numberChip = NumberChips.chip(before: before)
        // Không còn chữ số gần con trỏ (vd ⌫ chỉ xoá chữ) ⇒ ngưng đọc context mỗi phím
        // tới khi gõ số / ký hiệu mới (trước đây: sau ⌫ mọi phím chữ tới 2 dấu cách).
        if numberChip == nil, !NumberChips.digitNearCaret(before) { numberSpaces = 99 }
        return numberChip?.display
    }

    /// Chip kết quả phép tính (MathResults) — chỉ đọc context khi phím vừa gõ là "=".
    /// Đọc lại mỗi lượt (không cache) ⇒ con trỏ dời đi chỗ khác thì chip tự mất.
    private func refreshMathChip() -> String? {
        mathChip = nil
        guard mathArmed, let before = textDocumentProxy.documentContextBeforeInput else { return nil }
        mathChip = MathResults.chip(before: before)
        return mathChip?.display
    }

    /// Phần main của gợi ý khi đang gõ dở: pool (VNSuggest) + fix đã tính nền.
    private func showComposingSuggestions(composed: String, raw: String, predicted: String,
                                          pool: [VNSuggest.Match], pmi: [Float]?, fix: String?,
                                          slip: String? = nil) {
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
        // Từ thêm tay (Từ điển cá nhân) khớp tiền tố: đứng đầu pool với freq = trần lexicon
        // (255) — lexicon không có tên riêng/thuật ngữ nên VNSuggest không bao giờ đưa ra.
        let manualHits = langModel.manualCompletions(composed)
        let pool = manualHits.isEmpty ? pool : {
            let low = Set(manualHits.map { $0.lowercased() })
            return manualHits.map { VNSuggest.Match(word: $0, freq: 255) } + pool.filter { !low.contains($0.word.lowercased()) }
        }()
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
            // + bigram âm tiết tĩnh (SuggestRank — logic thuần, test đo trên heldout)
            let lm = langModel
            let ranked = SensitiveWords.filter(
                SuggestRank.rankInline(pool, pmi: pmi, typedLen: composed.count,
                                       count: { lm.count(of: $0) }, ctx: ctxCache),
                enabled: filterSensitive)
            set.word = ranked.first.map { displayCase($0, after: lastWord) }
            set.word2 = ranked.dropFirst().first.map { displayCase($0, after: lastWord) }
        } else if let fix {
            // Thử nghiệm: không từ nào khớp → nghi chạm trượt phím kề; đưa bản sửa
            // lên slot chính (tap để thay, không tự thay).
            set.word = fix
        }
        // Trượt vào phím thanh mà vẫn ra từ ("casn" → cán, ý là cân): bản sửa vào slot 3.
        if let slip, slip != set.word {
            if set.word == nil { set.word = slip } else { set.word2 = slip }
        }
        set.number = refreshNumberChip()
        set.math = refreshMathChip()
        // thử cụm 2 từ trước ("hoàn thành", "sinh nhật") rồi mới tới từ đơn.
        // Emoji KHÔNG bị lọc nhạy cảm (user 2026-07-24: gõ "cứt"/"shit"
        // phải ra 💩) — filter chỉ chặn gợi ý TỪ, emoji là cách nói giảm.
        var emojis: [String] = []
        if emojiSuggestSetting {
            if let prev = lastWord {
                emojis = EmojiSuggest.emojis(for: prev.lowercased() + " " + composed.lowercased())
            }
            if emojis.isEmpty { emojis = EmojiSuggest.emojis(for: composed) }
            // raw ≡ composed (từ không dấu) ⇒ tra lần ba là thừa.
            if emojis.isEmpty, raw != composed { emojis = EmojiSuggest.emojis(for: raw.lowercased()) }
        }
        set.emojis = emojis
        // Không có emoji lấp slot 3 → đệm word/word2 cho đủ (literal + 2 từ).
        if emojis.isEmpty {
            let words = padWords([set.word, set.word2].compactMap { $0 },
                                 need: 2, typed: composed)
            set.word = words.first
            set.word2 = words.count > 1 ? words.last : nil
        }
        // Đang gõ đúng một chữ tắt: slot chính hiện nội dung sẽ bung (chạm = bung ngay).
        // (Nội dung nhiều dòng không lên bar — chạm sẽ chèn sai; gõ ranh giới vẫn bung.)
        if let preview = bridge.shortcutPreview, !preview.contains("\n"), set.word != preview {
            set.word2 = set.word ?? set.word2
            set.word = preview
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
    /// Mời dán MỘT lần mỗi mục clipboard (PasteOfferOnce). Lưu changeCount + mốc khởi động
    /// máy (changeCount đếm lại sau reboot) vào defaults RIÊNG của bàn phím — không cần
    /// Full Access, không bao giờ lưu nội dung.
    private lazy var pasteOnce = PasteOfferOnce(offeredID: Self.loadPasteOffered()) { id in
        let d = UserDefaults.standard
        d.set(id, forKey: Self.pasteOfferedKey)
        d.set(Self.bootEpoch(), forKey: Self.pasteOfferedBootKey)
    }
    private static let pasteOfferedKey = "pasteOfferedChange"
    private static let pasteOfferedBootKey = "pasteOfferedBoot"
    private static func bootEpoch() -> Double {
        Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    }
    private static func loadPasteOffered() -> Int? {
        let d = UserDefaults.standard
        guard d.object(forKey: pasteOfferedKey) != nil,
              abs(d.double(forKey: pasteOfferedBootKey) - bootEpoch()) < 120 else { return nil }
        return d.integer(forKey: pasteOfferedKey)
    }
    private func pasteOffer() -> Bool {
        guard pasteButtonSetting || clip.historyEnabled else { return false }
        guard hasFullAccess else { TouchLog.write("paste: no Full Access"); return false }
        // Chỉ ở "đầu chỗ gõ": ô trống, hoặc ngay trước con trỏ là khoảng trắng/xuống dòng.
        // Bàn phím vừa hiện lại sau "Đang viết" thì engine rỗng nhưng vẫn là gõ dở chữ
        // (user 25/09/2026). documentContextBeforeInput là bản host đẩy sẵn — đọc rẻ.
        if let last = textDocumentProxy.documentContextBeforeInput?.last,
           !last.isWhitespace { return false }
        let now = Date()
        if now.timeIntervalSince(pasteCheckedAt) < 2 { return pasteCached && pasteOnce.canOffer(pasteSeenChange) }
        pasteCheckedAt = now
        let pb = UIPasteboard.general
        let cc = pb.changeCount
        let has = pb.hasStrings
        if cc != pasteSeenChange {
            pasteSeenChange = cc; pasteSeenAt = now
            if has, cc != pasteUsedChange { autoCaptureClipboard(pb, change: cc) }
        }
        // Ảnh: KHÔNG báo (user 25/09/2026) — iOS không cho bàn phím chèn ảnh, thẻ
        // hướng dẫn trông như nút bấm được nên gây hiểu nhầm.
        pasteIsImage = false
        pasteCached = cc != pasteUsedChange && has
            && now.timeIntervalSince(pasteSeenAt) < 180
            && pasteOnce.canOffer(cc)
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
        learnSettledSwipe()
        addTonesUndo = nil
        swipeTyped = nil; swipeTypedUndo = nil
        if item == KeyboardView.pasteImageToken {       // chỉ hướng dẫn → ẩn thẻ
            pasteUsedChange = UIPasteboard.general.changeCount
            pasteOnce.used(pasteUsedChange)
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
            if let s = str, !s.isEmpty {
                textDocumentProxy.insertText(s)
                clip.captured(s, change: pb.changeCount, now: Date().timeIntervalSince1970,
                              secureField: fieldTraits?.secure == true,
                              concealed: Self.isConcealed(pb))
            }
            pasteUsedChange = pb.changeCount
            pasteOnce.used(pasteUsedChange)
            pasteCached = false
            bridge.reset(); lastWord = nil; lastWord2 = nil
            KeyboardView.clickModifier()
            updateSuggestions()
            return
        }
        if item == KeyboardView.numberToken {
            acceptNumberChip()
            return
        }
        if item == KeyboardView.mathToken {
            acceptMathChip()
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

// MARK: chọn phím theo ngữ cảnh (thử nghiệm) — TouchTarget
extension KeyboardViewController {
    /// Gọi lúc chạm phím chữ (main): P(phím | từ đang gõ), nil ⇒ router gần-nhất như cũ.
    /// Ô literal (email/URL/username/mật khẩu), layout số/email/URL: tắt.
    fileprivate func smartTouchPrior() -> ((Character) -> Float?)? {
        guard smartTouchSetting, let t = fieldTraits, !t.passthrough, !t.secure,
              t.inputKind.isFreeText, !bridge.passthrough else { return nil }
        return TelexKeyPrior.sharedIfReady?.forTyping(bridge.rawWord, vniMode: bridge.vniMode)
    }
}

extension KeyboardViewController {
    /// Chạm chip số: thay đúng đuôi đã tính (kiểm lại context trước khi xoá — lệch thì bỏ).
    /// Chạm chip đuôi mail: chèn phần còn thiếu — tính lại từ context lúc chạm, lệch thì bỏ.
    fileprivate func acceptEmailChip(_ c: EmailDomains.Chip) {
        applyingEdit = true
        defer {
            applyingEdit = false
            KeyboardView.clickModifier()
            updateSuggestions()
        }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        guard EmailDomains.chips(before: before, limit: EmailDomains.providers.count).contains(c) else {
            TouchLog.write("failsafe: email chip context mismatch → skip")
            return
        }
        textDocumentProxy.insertText(c.insert)
        bridge.reset()
        lastWord = nil; lastWord2 = nil
    }

    /// StripMode.tools: không gợi ý chữ — chỉ lời mời Dán (cùng luật mời một lần / Full
    /// Access / chip tách số = Plus như dải đầy đủ) và chip URL ở ô địa chỉ. ☰/📋/⌄ do
    /// KeyboardView vẽ sẵn khi dải bật.
    fileprivate func showToolsOnly(composing: Bool) {
        var set = KeyboardView.SuggestionSet()
        if composing {
            keyboard.hidePasteCard()
        } else if pasteOffer() {
            set.paste = pasteButtonSetting; set.pasteIsImage = pasteIsImage
            let chips = clip.chips(currentChange: pasteSeenChange, usedChange: pasteUsedChange)
            set.clipChips = chips.map { ($0.label, KeyboardView.clipTokenPrefix + $0.value) }
        }
        if fieldTraits?.wantsURLChips == true {
            let p = textDocumentProxy
            urlChips = URLChips.chips(before: p.documentContextBeforeInput ?? "",
                                      after: p.documentContextAfterInput ?? "")
            set.nextWords = urlChips.map(\.label)
        }
        keyboard.showSuggestions(set)
    }

    /// Chạm chip URL: tính lại từ context lúc chạm (con trỏ có thể đã dời) — không còn chip
    /// cùng nhãn thì bỏ (không chèn mù). Chữ đang gõ (omnibox gõ Telex) đã nằm sẵn trong ô ⇒
    /// chỉ chốt engine rồi chèn tại con trỏ.
    fileprivate func acceptURLChip(_ label: String) {
        applyingEdit = true
        defer {
            applyingEdit = false
            KeyboardView.clickModifier()
            updateSuggestions()
        }
        let p = textDocumentProxy
        let now = URLChips.chips(before: p.documentContextBeforeInput ?? "",
                                 after: p.documentContextAfterInput ?? "")
        guard let c = now.first(where: { $0.label == label }) else {
            TouchLog.write("failsafe: url chip context mismatch → skip")
            return
        }
        p.insertText(c.insert)
        bridge.reset()
        lastWord = nil; lastWord2 = nil
    }

    fileprivate func acceptNumberChip() {
        defer {
            KeyboardView.clickModifier()
            updateAutoShift()
            updateSuggestions()
        }
        guard let c = numberChip else { return }
        numberChip = nil
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        guard before.hasSuffix(c.replace) else {
            TouchLog.write("failsafe: number chip context mismatch → skip")
            return
        }
        for _ in 0..<c.replace.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(c.insert)
        bridge.reset()
        lastWord = nil; lastWord2 = nil
        restoreUndo = nil; undoOfferActive = false
        numberSpaces = 0            // kết quả mới cũng là số → chip kế trong chuỗi (tiền → chữ)
    }
}

extension KeyboardViewController {
    /// Chạm chip kết quả phép tính: chèn kết quả sau "=" — tính lại từ context lúc chạm,
    /// khác chip đang hiện (con trỏ đã dời / chữ đã đổi) thì bỏ.
    fileprivate func acceptMathChip() {
        defer {
            KeyboardView.clickModifier()
            updateAutoShift()
            updateSuggestions()
        }
        guard let c = mathChip else { return }
        mathChip = nil; mathArmed = false
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        guard MathResults.chip(before: before) == c else {
            TouchLog.write("failsafe: math chip context mismatch → skip")
            return
        }
        textDocumentProxy.insertText(c.insert)
        bridge.reset()
        lastWord = nil; lastWord2 = nil
        restoreUndo = nil; undoOfferActive = false
        numberSpaces = 0            // kết quả là số → chip số (đọc chữ) có thể theo sau
    }
}

// MARK: Lịch sử clipboard — glue ClipboardFeature ↔ UIPasteboard ↔ panel
extension KeyboardViewController {
    /// Trình quản lý mật khẩu đánh dấu clipboard "concealed" (quy ước nspasteboard.org,
    /// 1Password) — đọc `types` không bật hỏi quyền dán.
    fileprivate static func isConcealed(_ pb: UIPasteboard) -> Bool {
        pb.types.contains { $0 == "org.nspasteboard.ConcealedType" || $0.hasPrefix("com.agilebits") }
    }

    /// changeCount mới lúc bàn phím đang hiện: tự đọc + ghi CHỈ khi user đã chọn
    /// "Cho phép dán" (pasteNoPrompt) — nếu iOS vẫn hỏi (đọc chậm) thì ghi nhận lại
    /// pasteNoPrompt=false để lần sau không tự đọc nữa.
    fileprivate func autoCaptureClipboard(_ pb: UIPasteboard, change: Int) {
        let group = UserDefaultsProvider.shared
        let secure = fieldTraits?.secure == true
        let concealed = clip.historyEnabled ? Self.isConcealed(pb) : false
        guard clip.shouldAutoRead(fullAccess: hasFullAccess,
                                  noPrompt: group?.bool(forKey: "pasteNoPrompt") == true,
                                  secureField: secure, concealed: concealed) else { return }
        let t0 = CACurrentMediaTime()
        let str = pb.string
        if CACurrentMediaTime() - t0 >= 0.25 {
            UserDefaults(suiteName: "group.com.viettelex")?.set(false, forKey: "pasteNoPrompt")
        }
        guard let s = str else { return }
        clip.captured(s, change: change, now: Date().timeIntervalSince1970,
                      secureField: secure, concealed: concealed)
        if clipPanel != nil { reloadClipboardPanel() }
    }

    /// Chèn nội dung từ chip / panel: nguyên văn, KHÔNG thêm space, KHÔNG học từ.
    fileprivate func insertClip(_ text: String, chip: Bool) {
        guard !text.isEmpty else { return }
        applyingEdit = true
        defer { applyingEdit = false }
        learnSettledSwipe()
        textDocumentProxy.insertText(text)
        if chip { pasteUsedChange = pasteSeenChange; pasteOnce.used(pasteSeenChange); pasteCached = false }
        bridge.reset(); lastWord = nil; lastWord2 = nil
        KeyboardView.clickModifier()
        updateAutoShift()
        updateSuggestions()
    }

    fileprivate func toggleClipboardPanel() {
        if clipPanel != nil { closeClipboardPanel(); return }
        let p = ClipboardPanel()
        p.onPaste = { [weak self] t in self?.insertClip(t, chip: false); self?.closeClipboardPanel() }
        p.onTogglePin = { [weak self] t in
            guard let self else { return }
            if self.clip.togglePin(t) { self.reloadClipboardPanel(); return }
            let limit = self.clip.pinLimit() ?? 0
            self.reloadClipboardPanel(notice: L("Tối đa %@ mục ghim — VietTelex Plus ghim không giới hạn.", limit))
        }
        p.onDelete = { [weak self] t in self?.clip.remove(t); self?.reloadClipboardPanel() }
        p.onClearAll = { [weak self] in self?.clip.clearUnpinned(); self?.reloadClipboardPanel() }
        p.onClose = { [weak self] in self?.closeClipboardPanel() }
        p.frame = keyboard.keyAreaFrame   // KeyboardView.layoutOverlayPanel bám vùng phím mỗi lượt layout
        keyboard.addSubview(p)
        keyboard.overlayPanel = p
        clipPanel = p
        reloadClipboardPanel()
        keyboard.setNeedsLayout()
    }

    fileprivate func reloadClipboardPanel(notice: String? = nil) {
        guard let p = clipPanel else { return }
        p.frame = keyboard.keyAreaFrame
        p.reload(items: clip.items(now: Date().timeIntervalSince1970),
                 dark: keyboard.isDarkAppearance, incognito: clip.incognito, notice: notice)
    }

    fileprivate func closeClipboardPanel() {
        guard let p = clipPanel else { return }
        p.removeFromSuperview()
        clipPanel = nil
        keyboard?.overlayPanel = nil
        keyboard?.setNeedsLayout()
    }
}

// MARK: gõ vuốt (thử nghiệm) — glue SwipeTyping ↔ bridge ↔ thanh gợi ý
extension KeyboardViewController {
    fileprivate func wireSwipeTyping() {
        keyboard.onSwipeBegan = { [weak self] in self?.swipeBegan() }
        keyboard.onSwipeEnded = { [weak self] path, sc in self?.swipeEnded(path, sc) }
    }

    /// Observer cấp controller — MỘT lần ở viewDidLoad (KeyboardView có thể dựng lại nhiều lần).
    fileprivate func registerObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(voiceOverChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(memoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    /// Áp lực bộ nhớ: nhả model FUTO Swipe (thử nghiệm) nếu đang giữ.
    @objc fileprivate func memoryWarning() { swipe?.releaseFuto() }

    @objc fileprivate func voiceOverChanged() { updateSwipeEnabled() }

    /// Bật/tắt theo công tắc + SwipePolicy (ô nhập, iPad, VoiceOver).
    fileprivate func updateSwipeEnabled() {
        guard let keyboard else { return }
        let on = SwipePolicy.enabled(setting: swipeSetting,
                                     isPad: UIDevice.current.userInterfaceIdiom == .pad,
                                     traits: fieldTraits,
                                     voiceOver: UIAccessibility.isVoiceOverRunning)
        keyboard.swipeEnabled = on
        keyboard.altAccessibility = UIAccessibility.isVoiceOverRunning
        // Checkpoint huỷ phím chữ chỉ có người dùng khi gõ vuốt / iPad vuốt xuống / giữ phím
        // ra ký tự phụ.
        bridge.letterUndoEnabled = on || UIDevice.current.userInterfaceIdiom == .pad
            || keyboard.altHoldActive
        if on, swipe == nil { swipe = SwipeTyping() }
        if on { pushSwipeLayout(prepare: true) }
        if on, swipeEnglishSetting { swipe?.preloadEnglish() }
        if let swipe, on || swipe.futoActive { swipe.setFuto(enabled: on && swipeFutoSetting) }
    }

    /// Tâm phím thật → decoder (đổi layout khi xoay/đổi cỡ; trùng thì no-op).
    fileprivate func pushSwipeLayout(prepare: Bool) {
        guard keyboard?.swipeEnabled == true, let swipe,
              let l = keyboard.swipeLayout() else { return }
        swipe.setLayout(l, prepare: prepare)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pushSwipeLayout(prepare: true)
        // Sáng/tối: iOS 27 đôi khi báo trait SÁNG lúc viewWillAppear/viewDidAppear dù máy
        // tối ⇒ phím trắng trên backdrop tối, chữ gợi ý đen khó đọc (Phil 28/09/2026). Mỗi
        // lần layout so lại với trait hiện tại (chỉ so 2 giá trị đã có — không đọc proxy);
        // updateDark tự bỏ qua khi không đổi.
        keyboard?.updateDark(AppearancePolicy.isDark(
            appearance: fieldTraits?.appearance ?? .default,
            style: view.traitCollection.userInterfaceStyle))
        checkHostFill()
    }

    // MARK: Dải container hệ thống lộ phía trên view (HostFill — Phil 05/10/2026, iOS 27 thật)
    // (trạng thái hostFill / hostFillRecheckScheduled / lastHostGeomKey ở thân class)
    /// Chỉ iPhone iOS 26+ (khung kính) — chỗ khác không đo, không làm gì.
    private static let hostFillEligible = UIDevice.current.userInterfaceIdiom == .phone
        && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26

    /// Đỉnh container hệ thống → đáy view: superview và window, chỉ những cái view NEO ĐÁY và
    /// cao hơn view không quá trần (window cỡ màn hình / khung settle khổng lồ bị loại).
    private func hostAllocatedHeight() -> CGFloat? {
        guard let v = viewIfLoaded else { return nil }
        var candidates: [CGFloat] = []
        if let s = v.superview, let a = HostFill.allocated(viewFrame: v.frame, container: s.bounds) {
            candidates.append(a)
        }
        if let w = v.window,
           let a = HostFill.allocated(viewFrame: v.convert(v.bounds, to: w), container: w.bounds) {
            candidates.append(a)
        }
        return candidates.filter { $0 - v.bounds.height <= HostFill.maxExtra }.max()
    }

    /// Mỗi lượt layout: log hình học (Debug mode) + quyết định HostFill. Theme trong suốt /
    /// iPad / iOS < 26: chỉ một phép so sánh.
    private func checkHostFill() {
        guard let kb = keyboard, !kb.isTornDown else { return }
        if TouchLog.enabled { logHostGeometry("layout") }
        guard Self.hostFillEligible, kb.paintsBackdrop else { return }
        let animating = UIView.inheritedAnimationDuration > 0
            || !(view.layer.animationKeys()?.isEmpty ?? true)
        switch hostFill.observe(base: kb.baseRequestedHeight, viewHeight: view.bounds.height,
                                allocated: hostAllocatedHeight(), width: view.bounds.width,
                                animating: animating) {
        case .none: break
        case .wait: scheduleHostFillRecheck()
        case .apply(let x):
            kb.hostFillExtra = x
            TouchLog.write("hostFill extra=\(x) locked=\(hostFill.locked)")
        }
    }

    /// Xác nhận ở lượt layout SAU (không hành động trên khung tạm của cùng một pass).
    private func scheduleHostFillRecheck() {
        guard !hostFillRecheckScheduled else { return }
        hostFillRecheckScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.hostFillRecheckScheduled = false
            self.viewIfLoaded?.setNeedsLayout()
        }
    }

    /// Debug mode (Giới thiệu → Gỡ lỗi): hình học view ↔ superview ↔ window ↔ màn hình, mức xin
    /// chiều cao, safe area, trait — ghi khi ĐỔI (dedupe), để bắt dải kính hệ thống lộ phía trên.
    private func logHostGeometry(_ tag: String) {
        guard TouchLog.enabled, let v = viewIfLoaded, let kb = keyboard else { return }
        let r = NSCoder.string(for:) as (CGRect) -> String
        let ins = NSCoder.string(for:) as (UIEdgeInsets) -> String
        var chain: [String] = []
        var a = v.superview
        while let s = a, chain.count < 4 {
            chain.append("\(type(of: s)):\(r(s.bounds))")
            a = s.superview
        }
        let w = v.window
        let inWin = w.map { r(v.convert(v.bounds, to: $0)) } ?? "-"
        let winOnScreen = w.flatMap { win in
            win.windowScene.map { r(win.convert(win.bounds, to: $0.screen.coordinateSpace)) }
        } ?? "-"
        let screen = w?.windowScene.map { r($0.screen.bounds) } ?? "-"
        let t = v.traitCollection
        let alloc = hostAllocatedHeight()
        let band = alloc.map { String(format: "%.1f", $0 - v.bounds.height) } ?? "-"
        let body = "view=\(r(v.bounds)) inSuper=\(r(v.frame)) super=[\(chain.joined(separator: " > "))] "
            + "window=\(w.map { r($0.bounds) } ?? "-") inWin=\(inWin) winOnScreen=\(winOnScreen) screen=\(screen) "
            + "inputView=\(inputView.map { r($0.frame) } ?? "-") kb=\(r(kb.frame)) req=\(kb.heightRequestInfo) "
            + "safe=\(ins(v.safeAreaInsets)) winSafe=\(w.map { ins($0.safeAreaInsets) } ?? "-") "
            + "trait=style\(t.userInterfaceStyle.rawValue)/h\(t.horizontalSizeClass.rawValue)"
            + "/v\(t.verticalSizeClass.rawValue)/x\(t.displayScale) "
            + "alloc=\(alloc.map { "\($0)" } ?? "-") band=\(band) fillLocked=\(hostFill.locked) "
            + "backdrop=\(kb.paintsBackdrop) host=\(parent.map { String(describing: type(of: $0)) } ?? "-")"
        guard body != lastHostGeomKey else { return }
        lastHostGeomKey = body
        TouchLog.write("hostgeom[\(tag)] " + body)
    }

    private func isRecentEnglish(_ w: String?) -> Bool {
        guard let w else { return false }
        return recentEnglish.contains(w.lowercased())
    }

    private func noteRecentEnglish(_ w: String) {
        recentEnglish.append(w.lowercased())
        if recentEnglish.count > 4 { recentEnglish.removeFirst() }
    }

    /// Vuốt phím cách: đổi Tiếng Việt ↔ Tiếng Anh. Chốt từ đang gõ trước (học như ranh
    /// giới), lưu trạng thái cho lần hiện sau. KeyboardView đã rung + chạy hiệu ứng nhãn.
    fileprivate func toggleLanguage() {
        guard spaceFlickSetting else { return }
        if externalChangePending { syncComposition("flick") }
        applyingEdit = true
        defer { applyingEdit = false }
        learnSettledSwipe()
        let accepted = bridge.openWordAccepted
        language = language.toggled
        UserDefaults.standard.set(language.rawValue, forKey: KeyboardLanguage.storageKey)
        commitAndLearn(bridge.setEnglish(language == .en, proxy: Proxy(p: textDocumentProxy)),
                       accepted: accepted)
        if language == .en { warmUpEnglish() }
        keyboard.spaceLanguage = language
        swipeSuggest = nil
        restoreUndo = nil; undoOfferActive = false
        suggestionGen += 1
        updateSuggestions()
    }

    /// Nạp enlexicon + bảng từ phổ biến ở nền (lần đầu vào Tiếng Anh), khỏi trễ phím đầu.
    fileprivate func warmUpEnglish() {
        DispatchQueue.global(qos: .utility).async { _ = SwipeEnglish.top }
    }

    /// Từ vuốt được chốt bởi phím chữ trước (dấu cách treo) — học khi chắc chắn.
    fileprivate func learnSettledSwipe() {
        if let s = bridge.takeSettledCommit() { commitAndLearn(s.word, accepted: s.accepted) }
    }

    fileprivate func swipeBegan() {
        guard let swipe else { return }
        pushSwipeLayout(prepare: false)
        if externalChangePending { syncComposition("swipe") }
        applyingEdit = true
        defer { applyingEdit = false }
        swipe.begin(bridge: bridge, proxy: Proxy(p: textDocumentProxy))
        restoreUndo = nil; undoOfferActive = false
        swipeSuggest = nil
        swipeReviseUndo = nil
        swipeTyped = nil; swipeTypedUndo = nil
    }

    fileprivate func swipeEnded(_ path: SwipePath, _ sc: SwipeCase) {
        guard let swipe else { return }
        if externalChangePending { syncComposition("swipe") }
        wordSwipeRestore = nil
        learnSettledSwipe()
        applyingEdit = true
        defer { applyingEdit = false }
        // Ngữ cảnh: từ đang gõ dở (sẽ được chốt trước từ vuốt) hoặc từ liền trước.
        let composing = bridge.isComposing
        let prev = composing ? bridge.predictedCommit : lastWord
        let prev2 = composing ? lastWord : lastWord2
        let ctx = prev.map { langModel.nextWords(after: $0, prev2: prev2, limit: 24) } ?? []
        let lm = langModel
        // Ngôn ngữ theo ≤ 3 từ trước (qua cả dấu câu — liên tục ngôn ngữ): từ Anh vừa vuốt (nhãn)
        // chắc nhất, rồi bảng từ của engine + từ điển; mặc định nghiêng tiếng Việt.
        let englishOnly = bridge.englishMode
        let english: SwipeEnglishPrior? = englishOnly ? SwipeLangContext.onlyEnglishPrior
            : swipeEnglishSetting ? SwipeLangContext.prior(SwipeLangContext.kinds(
                composing: composing, pending: prev,
                pendingEnglish: bridge.isLiteralSwipeWordOpen || isRecentEnglish(prev),
                recent: langRecent, english: { self.isRecentEnglish($0) })) : nil
        // Từ vuốt trước còn nguyên (mở, chưa sửa dấu, chưa chọn phương án) ⇒ cú này sửa lại được.
        let previous = swipeRevisable.flatMap { r -> SwipeTyping.Revisable? in
            bridge.isSwipeWordOpen && bridge.isFreshSwipeWord && !bridge.openWordAccepted
                && !bridge.isLiteralSwipeWordOpen && bridge.composedWord == r.word ? r : nil
        }
        swipeRevisable = nil
        swipeReviseUndo = nil
        let out = swipe.finish(path, case: sc, contextWords: ctx, count: { lm.count(of: $0) },
                               prev: prev, prev2: prev2, english: english, englishOnly: englishOnly,
                               previous: previous,
                               nextWords: { lm.nextWords(after: $0, prev2: $1, limit: 24) },
                               bridge: bridge, proxy: Proxy(p: textDocumentProxy))
        if let out {
            if let c = out.committed { commitAndLearn(c.word, accepted: c.accepted) }
            swipeReviseUndo = out.revised
            if !out.scored.isEmpty, bridge.isSwipeWordOpen {
                swipeRevisable = SwipeTyping.Revisable(word: out.word, scored: out.scored, sc: sc)
            }
            if out.english { noteRecentEnglish(out.word) }
            let alts = SensitiveWords.filter(out.alternatives, enabled: filterSensitive)
            swipeSuggest = alts.isEmpty || !bridge.isSwipeWordOpen ? nil
                : (out.word, alts, out.englishAlternatives)
            KeyboardView.clickLetter()
        }
        lastInsertWasSpace = false
        lastKeyWasEmailTrigger = false
        restoreUndo = nil; undoOfferActive = false
        suggestionGen += 1
        updateAutoShift()
        updateSuggestions()
    }

    /// Chạm phương án trên thanh gợi ý sau vuốt: thay từ, vẫn để mở (không thêm dấu
    /// cách). false = không phải phương án vuốt (caller xử lý như gợi ý thường).
    fileprivate func acceptSwipeAlternative(_ item: String) -> Bool {
        guard let s = swipeSuggest, s.alts.contains(item) else { return false }
        applyingEdit = true
        defer { applyingEdit = false }
        let wasEnglish = bridge.isLiteralSwipeWordOpen
        let itemEnglish = s.english.contains(item)
        guard bridge.replaceSwipeWord(with: item, literal: itemEnglish,
                                      proxy: Proxy(p: textDocumentProxy)) else {
            swipeSuggest = nil
            return false
        }
        if itemEnglish { noteRecentEnglish(item) }
        swipeRevisable = nil                  // user đã chọn: cú vuốt kế không sửa lại từ này
        var english = s.english
        english.remove(item)
        if wasEnglish { english.insert(s.current) }
        swipeSuggest = (item, [s.current] + s.alts.filter { $0 != item }, english)
        KeyboardView.clickModifier()
        suggestionGen += 1
        updateSuggestions()
        return true
    }
}

extension KeyboardViewController {
    /// Chip "↩︎ từ cũ": trả từ vuốt trước về như lúc vuốt; học lại từ cũ như user chọn
    /// (iOS không rút lượt học từ mới — weight 1, phai dần).
    fileprivate func undoSwipeRevision() {
        if let t = swipeTypedUndo {
            swipeTypedUndo = nil
            undoTypedRevision(t)
            return
        }
        guard let u = swipeReviseUndo else { return }
        swipeReviseUndo = nil
        applyingEdit = true
        defer { applyingEdit = false }
        if bridge.restoreRevisedWord(old: u.old, new: u.new, proxy: Proxy(p: textDocumentProxy)),
           lastWord == u.new {
            lastWord = lastWord2; lastWord2 = nil
            commitAndLearn(u.old, accepted: true)
            KeyboardView.clickModifier()
        }
        suggestionGen += 1
        updateSuggestions()
    }
}

extension KeyboardViewController {
    /// Phím này có thể chốt một từ vuốt Việt còn nguyên (mở, chưa sửa dấu, chưa chọn phương án)
    /// ⇒ ứng viên chờ từ gõ kế. nil khi gõ vuốt tắt (swipeRevisable luôn nil) — 0 việc.
    fileprivate func typedArmCandidate(_ key: KeyboardView.Key) -> SwipeRevise.Typed? {
        guard let r = swipeRevisable else { return nil }
        switch key {
        case .letter, .space: break
        default: return nil
        }
        guard bridge.isSwipeWordOpen, bridge.isFreshSwipeWord, !bridge.openWordAccepted,
              !bridge.isLiteralSwipeWordOpen, !bridge.englishMode, bridge.composedWord == r.word else { return nil }
        return SwipeRevise.Typed(word: r.word, scored: r.scored, sc: r.sc, prev: lastWord)
    }

    /// Từ gõ vừa được chốt ngay sau từ vuốt đang chờ: chấm lại từ vuốt; đổi thì thay đúng đuôi
    /// "từ vuốt ␠ từ gõ ranh giới" (đọc lại trước khi xoá) và học lại hai từ theo thứ tự mới.
    fileprivate func reviseTypedSwipe(_ w: (rev: SwipeRevise.Typed, learned: Learned?), typed: String,
                                      boundary: String, proxy: TextProxyLike) {
        guard let e = SwipeRevise.reviseTyped(w.rev, typed: typed, boundary: boundary,
                                              before: proxy.contextBeforeInput),
              SwipeRevise.apply(e, proxy: proxy) else { return }
        let sentenceBreak = boundary != " "
        let newLearned = relearnPair(before: w.learned, first: e.new, typed: typed)
        if sentenceBreak { lastWord = nil; lastWord2 = nil }
        swipeTypedUndo = (e, newLearned, sentenceBreak)
        TouchLog.write("swipe: sửa từ vuốt trước theo từ gõ (\(e.old.count)→\(e.new.count) ký tự)")
    }

    /// Rút lượt học của từ gõ vừa chốt (lastLearned) và của từ đứng trước nó (`before`), học lại
    /// `first` (cùng ngữ cảnh trái cũ) rồi `typed`. Trả lượt học của `first`.
    private func relearnPair(before: Learned?, first: String, typed: String, accepted: Bool = false) -> Learned? {
        if let l = lastLearned, l.word == typed, let r = l.receipt { langModel.retract(r) }
        if let b = before {
            if let r = b.receipt { langModel.retract(r) }
            lastWord = b.prev1; lastWord2 = b.prev2
        } else {
            lastWord = nil; lastWord2 = nil
        }
        commitAndLearn(first, accepted: accepted)
        let firstLearned = lastLearned
        commitAndLearn(typed)
        return firstLearned
    }

    /// Chip "↩︎ từ cũ" sau khi sửa theo từ gõ: trả từ vuốt về như lúc vuốt (đuôi phải khớp).
    fileprivate func undoTypedRevision(_ u: (edit: SwipeRevise.TypedEdit, newLearned: Learned?, sentenceBreak: Bool)) {
        applyingEdit = true
        defer { applyingEdit = false }
        if SwipeRevise.apply(u.edit, undo: true, proxy: Proxy(p: textDocumentProxy)) {
            _ = relearnPair(before: u.newLearned, first: u.edit.old, typed: u.edit.typed, accepted: true)
            if u.sentenceBreak { lastWord = nil; lastWord2 = nil }
            KeyboardView.clickModifier()
        }
        suggestionGen += 1
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
        keyboard.onTrackpad = { [weak self] on in self?.trackpadChanged(on) }
    }

    /// Đang giữ phím cách di con trỏ: mỗi bước chỉ còn bridge.reset + adjustTextPosition.
    /// Auto-shift / gợi ý / đồng bộ composition (đọc context) / đọc lại trait ô do
    /// selectionDidChange của host — tất cả hoãn tới lúc nhả tay, chạy MỘT lần.
    fileprivate func trackpadChanged(_ on: Bool) {
        trackpadActive = on
        trackpadContext.reset()
        trackpadCharsPerLine = 0              // đo lại khi cần (xoay / đổi cỡ chữ)
        guard !on else { return }
        externalChangePending = false      // đổi selection trong lúc kéo là của mình
        updateAutoShift()
        updateSuggestions()
    }

    /// Ký tự/dòng hiển thị ước lượng của ô host (GẦN ĐÚNG — extension không thấy bố cục
    /// host): bề ngang bàn phím trừ lề ô, chia bề rộng TB một ký tự font thân bài theo cỡ
    /// chữ hệ thống. Chỉ chạy ở bước dọc đầu tiên của một lần kéo; đo câu mẫu một lần/cỡ.
    private func estimateCharsPerLine() -> Int {
        let category = traitCollection.preferredContentSizeCategory
        let advance: Double
        if let a = trackpadAdvance, a.0 == category { advance = a.1 }
        else {
            let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
            let w = (VerticalMove.sample as NSString).size(withAttributes: [.font: font]).width
            advance = VerticalMove.avgAdvance(sampleWidth: Double(w))
            trackpadAdvance = (category, advance)
        }
        return VerticalMove.charsPerLine(fieldWidth: Double(view.bounds.width) - VerticalMove.fieldInset,
                                         avgAdvance: advance)
    }

    fileprivate func commitWordSwipe(_ words: Int) {
        guard let snap = wordSwipeSnapshot else { return }
        wordSwipeSnapshot = nil
        addTonesUndo = nil
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

// MARK: công cụ văn bản (Plus) — TextTools/TextToolRunner là logic thuần, đây chỉ là glue.
extension KeyboardViewController {
    /// Nguồn: selectedText (iOS 16+) nếu có, không thì đoạn trước con trỏ (tới xuống dòng).
    fileprivate func applyTextTool(_ tool: TextTool) {
        guard PlusGate.isUnlocked(.textTools) else { return }
        applyingEdit = true
        defer { applyingEdit = false }
        // Từ đang soạn đã nằm trong ô (iOS chèn thẳng) — engine bỏ nó như sau khi dán.
        bridge.reset()
        lastWord = nil; lastWord2 = nil
        restoreUndo = nil; undoOfferActive = false
        wordSwipeRestore = nil
        textToolUndo = nil
        var selected: String?
        if #available(iOS 16.0, *) { selected = textDocumentProxy.selectedText }
        let outcome = TextToolRunner.apply(tool, proxy: Proxy(p: textDocumentProxy), selectedText: selected)
        switch outcome {
        case .applied(let u): textToolUndo = u
        case .failsafe: TouchLog.write("failsafe: text tool \(tool.rawValue) context mismatch/NFD → skip")
        case .unchanged, .noSource: break
        }
        updateAutoShift(); updateSuggestions()
    }

    fileprivate func undoTextTool() {
        guard let u = textToolUndo else { return }
        textToolUndo = nil
        applyingEdit = true
        defer { applyingEdit = false }
        if !TextToolRunner.undo(u, proxy: Proxy(p: textDocumentProxy)) {
            TouchLog.write("failsafe: text tool undo context moved → skip")
        }
        bridge.reset()
        lastWord = nil; lastWord2 = nil
        KeyboardView.clickModifier()
        updateAutoShift(); updateSuggestions()
    }
}

// MARK: thêm dấu cho câu không dấu — chỉ khi người dùng bấm chip (logic thuần: AddTones.swift)
extension KeyboardViewController {
    /// Kế hoạch thêm dấu cho chữ trước con trỏ (cache theo văn bản); nil = không mời.
    /// documentContextBeforeInput là bản host đẩy sẵn — đọc rẻ (xem pasteOffer).
    fileprivate func addTonesPlan() -> AddTones.Plan? {
        guard addTonesSetting, bridge.composedWord.isEmpty,
              let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty else { return nil }
        if let c = addTonesCache, c.before == before { return c.plan }
        let lm = langModel
        let personal = AddTones.Personal(count: { lm.count(of: $0) }, pair: { lm.bigramCount($0, $1) })
        var plan = AddTones.plan(before, personal: personal)
        if plan?.original == addTonesDismissed { plan = nil }
        addTonesCache = (before, plan)
        return plan
    }

    /// Chạm "Thêm dấu": thay đuôi không dấu bằng bản có dấu — fail-safe CompositionSync
    /// (chữ trước con trỏ phải đúng là bản gốc), không xoá mù.
    fileprivate func applyAddTones() {
        addTonesCache = nil
        guard let plan = addTonesPlan() else { updateSuggestions(); return }
        addTonesCache = nil
        applyingEdit = true
        defer { applyingEdit = false }
        guard canDeleteBefore(plan.original, what: "add-tones") else { updateSuggestions(); return }
        for _ in 0..<plan.original.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(plan.replacement)
        bridge.reset()
        lastWord = nil; lastWord2 = nil
        restoreUndo = nil; undoOfferActive = false
        addTonesUndo = plan
        KeyboardView.clickModifier()
        updateAutoShift(); updateSuggestions()
    }

    /// "Hoàn tác" / ⌫ ngay sau: trả bản gốc nếu chữ trước con trỏ vẫn là bản vừa thay.
    fileprivate func undoAddTones() {
        guard let u = addTonesUndo else { return }
        addTonesUndo = nil
        addTonesCache = nil
        applyingEdit = true
        defer { applyingEdit = false }
        // Luôn đối chiếu (kể cả đuôi 1 ký tự): lệch / không đọc được ⇒ bỏ, không xoá mù.
        if textDocumentProxy.documentContextBeforeInput?.hasSuffix(u.replacement) == true {
            for _ in 0..<u.replacement.count { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(u.original)
            addTonesDismissed = u.original
            bridge.reset()
            lastWord = nil; lastWord2 = nil
            restoreUndo = nil; undoOfferActive = false
            KeyboardView.clickModifier()
        }
        updateAutoShift(); updateSuggestions()
    }
}



/// Đọc một thuộc tính của textDocumentProxy mà UIKit có thể NÉM NSException (iOS 27.0,
/// proxy chưa sẵn sàng) — trả `fallback` thay vì để bàn phím crash.
@inline(__always)
func vtSafe<T>(_ fallback: T, _ read: () -> T) -> T {
    var value = fallback
    if VTCatchException({ value = read() }) != nil { return fallback }
    return value
}
