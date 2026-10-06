// KeyboardView — programmatic UIKit clone of Apple's Vietnamese keyboard.
// M1: letters plane + shift/caps + backspace (with repeat) + 123 plane +
// globe/space/return. Metrics follow Apple's stock layout; the pixel-perfect
// fidelity pass (balloons, exact colors per appearance, iPad) is M2.
import UIKit
import AudioToolbox
import CoreHaptics

final class KeyboardView: UIView, UIInputViewAudioFeedback {

    enum Key {
        case letter(Character)
        case text(String)
        case space
        case doubleSpacePeriod        // "  " fast → ". " (Apple behavior)
        case newline
        case backspace
        case moveCursor(Int)          // space-hold trackpad mode (ký tự, âm = trái)
        case moveLine(Int)            // trackpad lên/xuống (dòng, âm = lên)
        case clearField               // nút thùng rác plane mẫu câu → xoá sạch ô
        /// Huỷ phím chữ vừa gõ rồi chèn chuỗi (iPad vuốt xuống ra ký tự phụ).
        case replaceLastLetter(String)
    }

    /// emojiSearch = hàng ô tìm emoji + plane chữ (phím chặn vào EmojiSearchSession).
    private enum Plane { case letters, numbers, symbols, emoji, templates, emojiSearch }
    /// Plane có phím chữ qua router (chữ thường + chế độ tìm emoji).
    private var lettersLike: Bool { plane == .letters || plane == .emojiSearch }

    /// Gần-trong-suốt nhưng KHÔNG clear: vùng alpha 0 không nhận touch ở cấp hệ thống
    /// (touch rơi sang app host). Dùng cho mọi nền phủ vùng bàn phím.
    static let touchableClear = UIColor(white: 0, alpha: 0.01)

    /// Strip gợi ý khi mở. 36 → 30 (25/09/2026, so ảnh stock: vùng bar stock ≈53pt,
    /// VietTelex ≈59pt — bàn phím cao hơn stock chủ yếu ở đây).
    static let openStrip: CGFloat = 34
    private static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    /// Bo góc phím như stock iOS 26+ (cũ: 5).
    static let keyRadius: CGFloat = 8
    /// Khe ngang giữa phím: iPad stock rộng hơn (~10pt) iPhone (6).
    private static var keyGap: CGFloat { isPad ? 10 : 6 }
    /// Lề trái/phải hàng phím (iPhone 6.5 như stock — KeyGeometry).
    private static var sideMargin: CGFloat { KeyGeometry.sideMargin(pad: isPad) }
    /// SF Compact như stock iOS 26/27 (KeyGeometry.Typography); nil nếu hệ thống không có
    /// (lọt về font khác) → SF Pro cỡ fallback.
    private static let compactDescriptor: UIFontDescriptor? = {
        let design = UIFontDescriptor.SystemDesign(rawValue: "NSCTFontUIFontDesignCompact")
        guard let d = UIFont.systemFont(ofSize: 20).fontDescriptor.withDesign(design) else { return nil }
        return UIFont(descriptor: d, size: 20).fontName.localizedCaseInsensitiveContains("compact") ? d : nil
    }()
    static var hasCompactFont: Bool { compactDescriptor != nil }
    static func keyFont(_ size: CGFloat) -> UIFont {
        compactDescriptor.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
    }
    /// Nhãn chữ phím iPhone: cỡ theo hoa/thường + canh baseline stock. iPad: cỡ/baseline
    /// theo hướng máy do KeyButton.padRole lo (KeyGeometry.Typography.Pad).
    private func applyKeycapFont(_ b: KeyButton, title: String) {
        guard !Self.isPad else { return }
        let size = KeyGeometry.Typography.size(for: title, compact: Self.hasCompactFont)
        if b.titleLabel?.font.pointSize != size { b.titleLabel?.font = Self.keyFont(size) }
        b.baselineAligned = true
    }
    /// Nhãn chữ phím chức năng iPhone (123/ABC/#+=): SF Compact cỡ stock, cùng baseline.
    private func applyLabelFont(_ b: KeyButton, size: CGFloat) {
        // iPad: nhãn phím đổi plane dạt góc dưới-trái như stock (#+=, 123, ABC).
        guard !Self.isPad else { b.padRole = .corner(left: true); return }
        b.titleLabel?.font = Self.keyFont(size)
        b.baselineAligned = true
    }
    /// Khe shift↔Z, M↔⌫ (khe giữa chữ là 6).
    static let shiftGap: CGFloat = 12
    /// Đệm trên của bar (user 25/09/2026): host có app KHÔNG vẽ dải khung phía trên
    /// cửa sổ bàn phím (Telegram, app VietTelex) → bar dính mép. Không có tín hiệu nào
    /// để phát hiện (log hình học y hệt WhatsApp) → đệm cố định 4pt mọi nơi.
    static let barTopPad: CGFloat = 4
    private enum ShiftState { case off, on, caps }

    var enableInputClicksWhenVisible: Bool { true }

    private let onKey: (Key) -> Void
    private var needsGlobe: Bool
    // Globe key theo hợp đồng Apple: addTarget thẳng vào UIInputViewController
    // với .allTouchEvents — long-press mở picker bàn phím chỉ chạy khi
    // handleInputModeList nhận event THẬT.
    private weak var inputController: UIInputViewController?

    /// M2 suggestion bar: gate qua toggle showSuggestions trong app.
    var onSuggestion: ((String) -> Void)?
    private var heightConstraint: NSLayoutConstraint?
    /// Chiều cao tự xin (KeyLayout.chrome total) — CHƯA cộng hostFillExtra.
    private(set) var baseRequestedHeight: CGFloat = 0
    /// Phần xin thêm để lấp dải container hệ thống lộ phía trên view (HostFill — controller
    /// quyết định). Phím hấp thụ (rowsHeight @900), strip/headroom balloon giữ nguyên.
    var hostFillExtra: CGFloat = 0 {
        didSet { if hostFillExtra != oldValue { updateSuggestionChrome() } }
    }
    /// Nền theme đục / ảnh nền đang vẽ (dải kính hệ thống lộ ra mới thấy khác màu).
    var paintsBackdrop: Bool { !themeBackdrop.isHidden || wallpaperActive }
    /// Debug log: constant + priority của constraint chiều cao xin host.
    var heightRequestInfo: String {
        guard let h = heightConstraint else { return "-" }
        return "\(h.constant)@\(Int(h.priority.rawValue)) base=\(baseRequestedHeight) fill=\(hostFillExtra)"
    }
    private let suggestionBar = SuggestionBar()
    private var suggestionsEnabled = false
    private var stripReserved = false

    private var plane: Plane = .letters {
        didSet {
            // Vào plane số/ký hiệu từ plane khác → đếm lại; 123⇄#+= giữ nguyên.
            if oldValue != .numbers, oldValue != .symbols { typedInSymbolPlane = false }
            // Rời plane chữ sang 123/#+=/emoji: tắt Caps Lock + shift một-lần như stock
            // (Phil 06/10/2026). Về ABC đánh giá lại viết hoa đầu câu (reevaluateShiftForLetters).
            if oldValue == .letters, shift != .off, PlanePolicy.clearsShiftLeavingLetters(to: planeTarget(plane)) {
                shift = .off
            }
        }
    }
    private func planeTarget(_ p: Plane) -> PlanePolicy.Target {
        switch p {
        case .letters: return .letters
        case .numbers, .symbols: return .symbols
        case .emoji: return .emoji
        case .emojiSearch: return .emojiSearch
        case .templates: return .templates
        }
    }
    /// Đã gõ ký tự ở plane 123/#+= → space kế tiếp quay về chữ (PlanePolicy).
    private var typedInSymbolPlane = false
    private var shift: ShiftState = .on          // Apple: sentence start = shifted
    private var returnTitle = "return"
    private var dark = false
    private var lastShiftTap: TimeInterval = 0

    private var rowsContainer = UIStackView()
    private var rowsHeightConstraint: NSLayoutConstraint?
    private var rowsMaxHeightConstraint: NSLayoutConstraint?
    /// Sàn chiều cao vùng hàng (@999, trên rowsTop @998): host cấp THIẾU thì strip gợi ý
    /// nhường trước, hàng phím giữ đủ cao (KeyLayout.chrome).
    private var rowsMinHeightConstraint: NSLayoutConstraint?
    private var rowsMinTopConstraint: NSLayoutConstraint?
    private var rowsTopConstraint: NSLayoutConstraint?
    private var rowsBottomConstraint: NSLayoutConstraint?
    private var rowsLeftConstraint: NSLayoutConstraint?
    private var rowsRightConstraint: NSLayoutConstraint?
    private var repeatTimer: Timer?
    private var lastSuggestionSig = ""
    private var wordDeleteTick = 0
    /// Giữ backspace >3s → xoá theo TỪ (controller đọc proxy, off hot path).
    var onDeleteWord: (() -> Void)?
    private var lastSpaceTap: TimeInterval = 0
    /// Phím nhấc-mới-chốt đang đè — xem KeyCommitQueue (thứ tự khi gõ chồng ngón).
    private let commits = KeyCommitQueue()
    private var trackpadGesture = TrackpadGesture()
    private var backspaceHoldStart: TimeInterval = 0

    // Màu lấy từ theme (KeyboardTheme.swift — token tập trung một chỗ). Theme
    // Hệ thống = fill đục xấp xỉ stock (alpha-white trên nền trong suốt làm phím
    // đổi sắc theo màu app phía sau — chỉ theme Kính cố ý làm vậy).
    private var palette = KeyboardTheme.system.palette(systemDark: false)
    private var systemDark = false
    private var themeSettings = ThemeSettings()
    private var plainFill: UIColor { palette.keyFill.ui }
    private var specialFill: UIColor { palette.specialFill.ui }
    /// Chữ/icon trên phím (đã áp độ trong suốt ký tự). Balloon/popup dùng `palette.ink`.
    private var ink: UIColor { palette.keyInk.ui }
    private func inkFaded(_ a: Double) -> UIColor { palette.keyInk.alpha(a).ui }
    /// Nền theme + ảnh nền + lớp phủ: 3 view phẳng dưới hàng phím (không blur,
    /// không bóng). Ẩn hết ở theme nền trong suốt → giữ touchableClear như cũ.
    private let themeBackdrop = UIView()
    private let wallpaperView = UIImageView()
    private let wallpaperDim = UIView()
    private var wallpaperActive = false
    private var wallpaperLoadedFor: CGSize = .zero

    init(needsGlobe: Bool, inputController: UIInputViewController?, onKey: @escaping (Key) -> Void) {
        self.needsGlobe = needsGlobe
        self.inputController = inputController
        self.onKey = onKey
        super.init(frame: .zero)
        // Compact (user 2026-07-23): no reserved candidate strip — 4pt breathing
        // room on top, keys, 2pt below. Top-row balloons now overlap the key
        // area (extensions cannot draw outside their own bounds); the strip
        // returns in M2 when suggestions land there.
        // Priority 999, NOT required: during extension load the host briefly
        // imposes its own (much taller) frame — a required constant fought it
        // and Auto Layout broke OUR constraint for those frames.
        let height = heightAnchor.constraint(equalToConstant: 216)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height
        // Fast typists ROLL fingers: the next key is pressed before the previous
        // lifts. Default isMultipleTouchEnabled=false made iOS reject that second
        // touch outright — the missed-keypress bug.
        isMultipleTouchEnabled = true
        // ROOT CAUSE rớt phím khi gõ nhanh (log thiết bị 25/09/2026): nền view TRONG
        // SUỐT → iOS hit-test ở render server THEO PIXEL để chọn process nhận touch;
        // chạm vào khe giữa phím / góc bo rơi xuyên xuống UIRemoteKeyboardWindow của
        // app host (backboardd giao touch cho Notes, không cho extension) → mất phím.
        // Gõ chậm chạm giữa phím nên không bị; gõ nhanh hay lệch vào khe. hitInsets /
        // nearest-key router chỉ có tác dụng SAU khi touch đã tới process này.
        // Alpha 0.01: đủ để render server coi là "có nội dung", mắt không thấy.
        backgroundColor = Self.touchableClear
        rowsContainer.axis = .vertical
        rowsContainer.distribution = .fillEqually
        rowsContainer.spacing = 0
        rowsContainer.isMultipleTouchEnabled = true
        rowsContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsContainer)
        // Host thường cấp NHIỀU hơn mức xin (~25pt trên iOS 26) — để phím hấp
        // thụ phần dư thay vì thành dải trống trên đỉnh (user 2026-07-24):
        // rows height ưu tiên 900 (nhường host), kèm trần +60pt (required) để
        // cú áp frame khổng lồ lúc host đang settle không kéo phím giãn vô hạn
        // (vụ 'flash' cũ) — quá trần thì phần dư mới tràn lên trên.
        let rowsHeight = rowsContainer.heightAnchor.constraint(equalToConstant: 212)
        rowsHeight.priority = UILayoutPriority(900)
        let rowsMax = rowsContainer.heightAnchor.constraint(lessThanOrEqualToConstant: 272)
        // rows.top = view.top + strip — MỘT constraint quyết định vùng gợi ý,
        // không còn dây bar↔rows / margin động (nguồn của mọi conflict cũ).
        // 999: host áp frame khổng lồ lúc settle thì nhả êm, dư tràn lên trên.
        // 998 (dưới sàn rowsMin 999): host cấp thiếu chiều cao thì strip co trước, phím
        // không co (bug 1.2.x: phím lùn ở Notes/Facebook). rows.top ≥ view.top (required)
        // chặn hàng phím tràn khỏi đỉnh khi host cấp thiếu cả keyArea.
        let rowsTop = rowsContainer.topAnchor.constraint(equalTo: topAnchor, constant: 0)
        rowsTop.priority = UILayoutPriority(997)
        let rowsMin = rowsContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 212)
        rowsMin.priority = UILayoutPriority(998)
        // Sàn headroom balloon (999, trên rowsMin): host cấp thiếu thì strip nhường tới sàn
        // này rồi phím mới co — balloon hàng đầu luôn có chỗ (bug Phil 30/09/2026).
        let rowsMinTop = rowsContainer.topAnchor.constraint(greaterThanOrEqualTo: topAnchor,
                                                            constant: KeyLayout.balloonHeadroom)
        rowsMinTop.priority = UILayoutPriority(999)
        rowsMinTopConstraint = rowsMinTop
        // Hai mép là constraint GIỮ LẠI: chế độ một tay thụt vào (applyOneHand).
        // Đáy hàng phím = đáy view − safeBottom (máy gập mở: tránh vạch home — KeyLayout).
        let rowsBottom = rowsContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0)
        let rowsLeft = rowsContainer.leftAnchor.constraint(equalTo: leftAnchor)
        let rowsRight = rowsContainer.rightAnchor.constraint(equalTo: rightAnchor)
        rowsLeftConstraint = rowsLeft
        rowsRightConstraint = rowsRight
        NSLayoutConstraint.activate([
            rowsLeft,
            rowsRight,
            rowsHeight,
            rowsMax,
            rowsTop,
            rowsMin,
            rowsMinTop,
            rowsContainer.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            rowsBottom,
        ])
        rowsBottomConstraint = rowsBottom
        rowsHeightConstraint = rowsHeight
        rowsMinHeightConstraint = rowsMin
        rowsMaxHeightConstraint = rowsMax
        rowsTopConstraint = rowsTop
        // Suggestion bar sống trong "khoảng trống 2" — chỉ hiện khi bật. KHUNG CỐ ĐỊNH
        // (frame đặt ở layoutSubviews, không constraint): xem SuggestionBar.
        suggestionBar.isHidden = true
        addSubview(suggestionBar)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { repeatTimer?.invalidate() }

    /// Bàn phím ẩn hẳn (viewDidDisappear): xé cả cây view. Lý do (RAM-AUDIT.md #1): iOS 26+
    /// UIKit giữ `UIInputView` của controller mãi (vòng `UIInputView` ⇄ `_UIInputViewContent`
    /// qua associated object — tái hiện được với UIInputView RỖNG trong ViewTreeLeakTests),
    /// kèm trait corner-provider trỏ vào UIStackView cũ ⇒ cây phím cũ (~1,8 MB) sống theo mỗi
    /// lần hiện. Xé: dừng timer/display link, bỏ planeCache + ảnh nền, gỡ đệ quy mọi subview —
    /// thứ gì còn bị UIKit níu chỉ là vỏ rỗng vài KB. View đã xé KHÔNG dùng lại: controller
    /// dựng KeyboardView mới nếu cùng controller hiện lại (KeyboardViewController.viewWillAppear).
    private(set) var isTornDown = false
    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        repeatTimer?.invalidate(); repeatTimer = nil
        trackpadLink?.invalidate(); trackpadLink = nil
        altTimer?.cancel(); altTimer = nil
        commaTimer?.cancel(); commaTimer = nil
        dropAltHold()
        planeCache.removeAll()
        EmojiData.dropCaches()
        letterKeys.removeAll(); shiftKeys = []; crossRowConstraints = []
        spaceBar = nil; spaceLogo = nil; spaceCode = nil; indentedRow = nil
        overlayPanel?.removeFromSuperview(); overlayPanel = nil
        wallpaperView.image = nil
        wallpaperLoadedFor = .zero
        Self.stripSubviews(of: self, constraints: true)
        removeFromSuperview()
    }

    /// Cảnh báo bộ nhớ: bỏ các plane KHÔNG hiện (planeCache — plane đang hiện nằm ở
    /// rowsContainer, không trong cache) + bảng emoji (lưới đang mở đã giữ bản riêng).
    func dropCaches() {
        planeCache.removeAll()
        EmojiData.dropCaches()
    }

    #if DEBUG
    var debugPlaneCacheCount: Int { planeCache.count }
    var debugWallpaperImage: UIImage? { wallpaperView.image }
    #endif

    /// Gỡ đệ quy (lá trước): cắt mọi tham chiếu cha→con để phần UIKit còn níu không kéo theo
    /// cả cây. Arranged subview của UIStackView gỡ qua removeFromSuperview là đủ (UIKit bỏ
    /// luôn khỏi arrangedSubviews). `constraints`: gỡ luôn constraint của từng view (chỉ dùng
    /// cho cây của mình — view gốc của controller còn constraint hệ thống, đừng đụng).
    static func stripSubviews(of v: UIView, constraints: Bool = false) {
        for s in v.subviews {
            stripSubviews(of: s, constraints: constraints)
            s.removeFromSuperview()
        }
        if constraints { v.removeConstraints(v.constraints) }
    }

    /// Bật/tắt thanh gợi ý cho ô hiện tại. `reserveStrip` = công tắc toàn cục: ô từ chối
    /// gợi ý vẫn GIỮ dải strip (trống) để chiều cao bàn phím không đổi khi đổi ô.
    func setSuggestionsEnabled(_ on: Bool, reserveStrip: Bool? = nil) {
        suggestionsEnabled = on
        stripReserved = reserveStrip ?? on
        lastSuggestionSig = ""        // chrome đổi → lượt show kế phải ghi lại UI
        updateSuggestionChrome()
    }

    /// Collapse/expand thanh gợi ý bằng chevron (user 2026-07-24): thu gọn còn
    /// strip 14pt chỉ có nút mở lại — bàn phím THẤP XUỐNG 16pt, trả chỗ cho app.
    // UserDefaults.standard (container RIÊNG của extension): không Full Access
    // thì iOS cấm GHI vào App Group — group chỉ để đọc settings từ app.
    private var barCollapsed =
        UserDefaults.standard.bool(forKey: "suggestionBarCollapsed")
    /// Controller đọc để NGỪNG cả pipeline gợi ý khi bar thu gọn (tiết kiệm
    /// CPU/RAM — không chỉ ẩn UI).
    var isBarCollapsed: Bool { barCollapsed }
    var onBarToggle: (() -> Void)?
    private func toggleBarCollapsed() {
        Self.clickModifier()
        barCollapsed.toggle()
        UserDefaults.standard.set(barCollapsed, forKey: "suggestionBarCollapsed")
        lastSuggestionSig = ""
        // Animation 200ms (user 2026-07-24): chiều cao trượt + bar fade +
        // chevron xoay 180° (một icon chevron.down + transform). Chỉ animate
        // CONSTANTS trực tiếp — không gọi chrome trong block (chrome set
        // isHidden sẽ giết fade); completion mới chốt trạng thái qua chrome.
        let collapsing = barCollapsed
        if !collapsing { suggestionBar.isHidden = false; suggestionBar.alpha = 0 }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) {
            let strip: CGFloat = collapsing ? 14 : Self.openStrip
            let c = KeyLayout.chrome(keyArea: self.keyAreaHeight(), strip: strip, mode: self.chromeMode)
            self.rowsTopConstraint?.constant = c.rowsTop
            self.heightConstraint?.constant = c.total + self.safeBottom + self.hostFillExtra
            self.suggestionBar.alpha = collapsing ? 0 : 1
            let flip = CGAffineTransform(rotationAngle: collapsing ? .pi : 0)
            self.chevronIcon?.transform = flip
            self.chevronZone.imageView?.transform = flip
            self.layoutIfNeeded()
        } completion: { _ in
            self.updateSuggestionChrome()   // chốt isHidden/alpha trạng thái cuối
            self.onBarToggle?()             // controller refresh gợi ý sau khi mở lại
        }
    }
    /// Nút nổi CHỈ dùng khi bar thu gọn (strip 14 không còn bar). Khi bar mở,
    /// chevron là một SLOT trong bar (barChevronSlot) — cùng cơ chế touch với
    /// slot gợi ý vốn bấm nhạy, hết cảnh "bấm mãi không ăn".
    private lazy var collapseButton: UIButton = {
        let b = UIButton(type: .custom)
        b.addAction(UIAction { [weak self] _ in self?.toggleBarCollapsed() },
                    for: .touchUpInside)
        addSubview(b)
        b.translatesAutoresizingMaskIntoConstraints = false
        // Chiếm TRỌN chiều cao strip từ mép trên cửa sổ: ngón tay hay đè cao
        // hơn tâm icon (phần đó rơi vào inset hệ thống NGOÀI cửa sổ) — mục
        // tiêu phải phủ hết phần strip còn trong cửa sổ mới dễ trúng. Không
        // tràn xuống vùng phím nên không cướp tap của phím góc phải.
        // Icon là UIImageView định vị RIÊNG theo tâm hàng chữ (10pt) — nút
        // full-height mà align icon theo nút thì icon trôi lên mép trên.
        let height = b.heightAnchor.constraint(equalToConstant: 36)
        NSLayoutConstraint.activate([
            b.rightAnchor.constraint(equalTo: rightAnchor),
            b.topAnchor.constraint(equalTo: topAnchor),
            b.widthAnchor.constraint(equalToConstant: 48),   // hit target ≥44pt
            height,
        ])
        chevronHeight = height
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        b.addSubview(icon)
        let iconY = icon.centerYAnchor.constraint(equalTo: b.topAnchor, constant: 10)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: b.centerXAnchor),
            iconY,
        ])
        chevronIcon = icon
        chevronIconY = iconY
        return b
    }()
    private var chevronHeight: NSLayoutConstraint?
    private var chevronIcon: UIImageView?
    private var chevronIconY: NSLayoutConstraint?
    /// Burger nổi khi thu gọn — đối xứng chevron nổi, để mẫu câu vẫn truy cập
    /// được lúc bar đang ẩn (user 2026-07-24).
    private lazy var floatingBurger: UIButton = {
        let b = UIButton(type: .custom)
        b.addAction(UIAction { [weak self] _ in self?.toggleTemplates() },
                    for: .touchUpInside)
        addSubview(b)
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.leftAnchor.constraint(equalTo: leftAnchor),
            b.topAnchor.constraint(equalTo: topAnchor),
            b.widthAnchor.constraint(equalToConstant: 64),
            b.heightAnchor.constraint(equalToConstant: 18),
        ])
        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        b.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: b.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: b.topAnchor, constant: 7),
        ])
        floatingBurgerIcon = icon
        return b
    }()
    private var floatingBurgerIcon: UIImageView?

    // Burger (☰) + chevron (⌄) khi bar MỞ: 2 nút GHIM CỐ ĐỊNH ở mép, cao trọn
    // strip, tự vẽ icon + nhận tap. Trước nằm trong bar (fillProportionally) nên
    // trôi vào giữa khi hết gợi ý + vùng tap chỉ 20pt sát mép rất khó bấm
    // (user 2026-07-25). Giờ frame lớn, luôn ở mép → bấm đâu trong vùng cũng ăn.
    static let stripZoneWidth: CGFloat = 52
    /// Burger: chạm = mẫu câu; giữ lâu = bật/tắt chế độ một tay (iPhone). Bảng sửa văn
    /// bản (icon con trỏ) đã bỏ 27/09/2026 — ưu tiên gọn/nhẹ; một tay vẫn bật được ở đây
    /// hoặc trong app (Cài đặt → Chế độ một tay).
    private lazy var burgerZone: UIButton = {
        let b = UIButton(type: .custom)
        b.addAction(UIAction { [weak self] _ in self?.toggleTemplates() }, for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(burgerHold(_:)))
        hold.minimumPressDuration = 0.45
        b.addGestureRecognizer(hold)
        addSubview(b)
        return b
    }()
    @objc private func burgerHold(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        toggleOneHandFromKeyboard()
    }
    /// Giữ lâu burger: bật/tắt một tay (iPad bỏ qua). Long-press đã nhận ⇒ UIButton huỷ
    /// touchUpInside nên chạm-giữ không mở mẫu câu.
    private func toggleOneHandFromKeyboard() {
        guard !Self.isPad else { return }
        Self.clickModifier()
        setOneHand(OneHand.toggled(oneHand, preferred: lastOneHandSide))
    }
    private lazy var chevronZone: UIButton = {
        let b = UIButton(type: .custom)
        b.addAction(UIAction { [weak self] _ in self?.toggleBarCollapsed() }, for: .touchUpInside)
        addSubview(b)
        return b
    }()

    /// Bar là HÀNG NỘI DUNG cố định 20pt ghim đỉnh (tâm chữ y=10), thụt 2 mép chừa chỗ
    /// burgerZone/chevronZone (+ nút 📋) — gợi ý nằm giữa, không chồng lên nút mép.
    /// Frame thường không đổi ⇒ SuggestionBar không layout lại.
    private func layoutSuggestionBar() {
        let w = Self.stripZoneWidth
        let right = w + (clipboardButtonVisible ? Self.clipZoneWidth : 0)
        // Host cấp thiếu chiều cao ⇒ strip co (phím giữ nguyên): bar dời lên VỪA đủ để không
        // đè hàng đầu (còn vừa thì đứng yên).
        let h: CGFloat = 20
        let squeeze = rowsContainer.frame.height > 0
            ? min(0, rowsContainer.frame.minY - (Self.barTopPad + h)) : 0
        let f = CGRect(x: w, y: Self.barTopPad + squeeze, width: max(bounds.width - w - right, 0), height: h)
        if suggestionBar.frame != f { suggestionBar.frame = f }
    }

    /// Đặt lại frame + icon + ẩn/hiện 2 nút mép theo trạng thái bar. Gọi mỗi
    /// layoutSubviews. Chiều cao lấy từ HẰNG SỐ constraint (rowsTop), KHÔNG từ
    /// frame — frame có thể chưa kịp cập nhật trong cùng pass → strip=0 → tịt.
    private func layoutStripZones() {
        let open = suggestionsEnabled && !barCollapsed && plane != .emoji && plane != .emojiSearch
        burgerZone.isHidden = !open || !templatesEnabled
        chevronZone.isHidden = !open
        layoutClipboardExtras(stripOpen: open)
        guard open, bounds.width > 0 else { stripZonesKey = nil; return }
        let strip = max(rowsTopConstraint?.constant ?? Self.openStrip, Self.openStrip)
        // layoutSubviews chạy cả khi gõ (shift/balloon) — trạng thái không đổi thì khỏi
        // dựng lại ảnh SF Symbol + insets mỗi lượt.
        let key = StripZonesKey(width: bounds.width, strip: strip, templates: templatesActive, ink: palette.barInk)
        defer { bringSubviewToFront(burgerZone); bringSubviewToFront(chevronZone) }
        guard key != stripZonesKey else { return }
        stripZonesKey = key
        let w = Self.stripZoneWidth
        burgerZone.frame = CGRect(x: 0, y: 0, width: w, height: strip)
        chevronZone.frame = CGRect(x: bounds.width - w, y: 0, width: w, height: strip)
        let ink = palette.barInk.ui
        burgerZone.setImage(UIImage(systemName: "line.3.horizontal",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
        burgerZone.tintColor = ink.withAlphaComponent(templatesActive ? 0.9 : 0.45)
        burgerZone.accessibilityLabel = templatesActive ? L("Đóng mẫu câu") : L("Mẫu câu")
        burgerZone.accessibilityHint = Self.isPad ? nil : L("Giữ lâu để bật hoặc tắt chế độ một tay")
        chevronZone.setImage(UIImage(systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        chevronZone.tintColor = ink.withAlphaComponent(0.45)
        chevronZone.accessibilityLabel = L("Thu gọn thanh gợi ý")
        chevronZone.imageView?.transform = .identity   // bar mở = chevron xuôi
        // Icon canh giữa trong vùng 20pt TRÊN CÙNG (tâm y≈10) để khớp chữ gợi ý,
        // thay vì canh giữa cả strip 36 (tâm y≈18 → icon thấp hơn chữ, user 2026-07-25).
        let bottomInset = max(strip - 20 - Self.barTopPad, 0)
        burgerZone.contentEdgeInsets = UIEdgeInsets(top: Self.barTopPad, left: 0, bottom: bottomInset, right: 0)
        chevronZone.contentEdgeInsets = UIEdgeInsets(top: Self.barTopPad, left: 0, bottom: bottomInset, right: 0)
    }
    private struct StripZonesKey: Equatable {
        let width: CGFloat, strip: CGFloat, templates: Bool, ink: RGBA
    }
    private var stripZonesKey: StripZonesKey?

    private func refreshCollapseButton(visible: Bool) {
        // Nút nổi chỉ hiện khi THU GỌN; bar mở dùng slot trong bar.
        let floating = visible && barCollapsed
        collapseButton.isHidden = !floating
        floatingBurger.isHidden = !floating || !templatesEnabled
        if floating {
            floatingBurgerIcon?.image = UIImage(systemName: "line.3.horizontal",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
            floatingBurgerIcon?.tintColor = palette.barInk.ui.withAlphaComponent(0.45)
            floatingBurger.accessibilityLabel = L("Mẫu câu")
        }
        let chevImg = UIImage(systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        let ink = palette.barInk.ui.withAlphaComponent(0.45)
        if floating {
            // 18 = strip 14 + margin hàng phím (phím bắt đầu ở 19) — mục tiêu
            // to hơn mà không cướp tap phím.
            chevronHeight?.constant = 18
            chevronIconY?.constant = 7
            chevronIcon?.image = chevImg      // một icon duy nhất, xoay bằng transform
            chevronIcon?.tintColor = ink
            collapseButton.accessibilityLabel = L("Mở thanh gợi ý")
        }
        // Bar mở: burger/chevron là burgerZone/chevronZone (ghim mép) — style +
        // frame do layoutStripZones lo. Chỉ cần đảm bảo pool đã dựng.
        if visible && !barCollapsed {
            buildSuggestionPoolIfNeeded()
        }
        // Transform icon nút nổi (thu gọn) khớp trạng thái.
        chevronIcon?.transform = CGAffineTransform(rotationAngle: barCollapsed ? .pi : 0)
    }

    /// User chỉnh ±10pt/hàng qua Settings (Giao diện); 4 hàng nên tổng đổi 4×.
    private var rowHeightAdjust: CGFloat = 0

    /// Hàng phím số 1…0 trên hàng chữ (Settings → Giao diện, mặc định TẮT; khoá
    /// App Group "numberRow"). Nằm trong chữ ký rebuild → đổi là vứt planeCache.
    var numberRowEnabled = false {
        didSet { if numberRowEnabled != oldValue { rebuild() } }
    }
    static let numberRowKey = "numberRow"

    // MARK: giữ phím chữ ra ký tự phụ (KeyAlternates, issue #98)
    private var altNumbersSetting = true
    private var altSymbolsSetting = false
    /// VoiceOver bật ⇒ tắt ký tự phụ (giữ phím là cử chỉ của VoiceOver). Controller đặt.
    var altAccessibility = false {
        didSet { if altAccessibility != oldValue { rebuild() } }
    }
    /// Bảng ký tự phụ của lần dựng hiện tại (rỗng ⇒ không nhãn, không hẹn giờ).
    private var activeAlts: [Character: String] = [:]
    private var builtAlts: [Character: String] = [:]
    /// iPad: đúng nhãn ký tự phụ trên phím (KeyAlternates.padMap) — giữ = vuốt xuống.
    private func currentAlts() -> [Character: String] {
        if Self.isPad { return KeyAlternates.padMap() }
        return KeyAlternates.map(numbers: altNumbersSetting, symbols: altSymbolsSetting,
                          numberRow: numberRowEnabled, isPad: Self.isPad, accessibility: altAccessibility)
    }
    func configureKeyAlternates(numbers: Bool, symbols: Bool) {
        guard numbers != altNumbersSetting || symbols != altSymbolsSetting else { return }
        altNumbersSetting = numbers; altSymbolsSetting = symbols
        rebuild()
    }
    /// Có phím nào ra ký tự phụ không — controller bật checkpoint huỷ phím chữ theo cờ này.
    var altHoldActive: Bool { !currentAlts().isEmpty }
    private var altHold: (id: ObjectIdentifier, button: UIButton, hold: KeyAlternates.Hold)?
    private var altTimer: DispatchWorkItem?

    /// iPhone 216pt dọc / 162pt ngang; iPad 240/300 — GỌN hơn stock (264/352)
    /// theo ý user 2026-07-24, phím vẫn rộng thoải mái nhờ bề ngang iPad.
    /// Tổng key area = base + rowHeightAdjust × 4 hàng — heightConstraint và
    /// rowsContainer cùng đi qua đây nên tổng luôn khớp từng hàng.
    private var landscapeCache: (size: CGSize, landscape: Bool)?
    private var isLandscapeNow: Bool {
        // iPhone: theo bề ngang (KeyLayout.isPhoneLandscape) — orientation scene extension
        // có lúc lệch host ⇒ xin chiều cao ngang 162pt khi đang dọc (phím lùn ngẫu nhiên).
        // Máy gập mở (.unfolded) cũng dùng hình học "ngang": không cắt hàng đáy, khe trên 10.
        if !Self.isPad, bounds.width > 0 { return phoneForm != .portrait }
        // interfaceOrientation chép cả bộ scene settings mỗi lần đọc; xoay/Split View luôn
        // đổi bounds ⇒ cache theo kích thước (chỉ khi đã gắn window).
        if let c = landscapeCache, c.size == bounds.size, window != nil { return c.landscape }
        if let o = window?.windowScene?.interfaceOrientation {
            landscapeCache = (bounds.size, o.isLandscape)
            return o.isLandscape
        }
        return UIDevice.current.userInterfaceIdiom == .phone && bounds.width > 500
    }
    /// Dạng bàn phím iPhone (KeyLayout.phoneForm) — cache theo kích thước view: đọc màn hình
    /// + trait chỉ khi bounds đổi (xoay / gập-mở), không phải mỗi lần tính chiều cao.
    private var phoneFormCache: (size: CGSize, form: KeyLayout.PhoneForm)?
    private var phoneForm: KeyLayout.PhoneForm {
        if let c = phoneFormCache, c.size == bounds.size { return c.form }
        let t = traitCollection
        var screen = window?.windowScene?.screen.bounds.size
        #if DEBUG
        if let s = debugScreenSize { screen = s }
        #endif
        let f = KeyLayout.phoneForm(viewWidth: bounds.width, screenSize: screen,
                                    regularBoth: t.horizontalSizeClass == .regular && t.verticalSizeClass == .regular)
        if window != nil { phoneFormCache = (bounds.size, f) }
        return f
    }
    /// Safe area đáy hàng phím phải tránh (KeyLayout.keyboardSafeBottom): 0 trên iPhone thường
    /// / iPad; vạch home trên máy gập mở. Cập nhật ở safeAreaInsetsDidChange.
    private var safeBottom: CGFloat = 0
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        let s = KeyLayout.keyboardSafeBottom(pad: Self.isPad, viewSafeBottom: safeAreaInsets.bottom)
        if s != safeBottom { safeBottom = s; updateSuggestionChrome() }
    }
    /// iPhone dọc: hàng đáy thấp hơn 4pt để 3 hàng chữ nằm đúng chỗ stock (KeyGeometry).
    private var bottomTrim: CGFloat {
        KeyGeometry.bottomRowTrim(pad: Self.isPad, landscape: isLandscapeNow)
    }
    private func keyAreaHeight() -> CGFloat {
        let landscape = isLandscapeNow
        let base: CGFloat
        if UIDevice.current.userInterfaceIdiom == .pad {
            base = landscape ? 300 : 240
        } else {
            // 216 → 218 (25/09/2026): phím nhỉnh hơn chút; 224 làm cả bàn phím cao
            // hơn stock (user) — phần dư của stock nằm ở vùng đáy, không phải hàng phím.
            // 218 → 216 − 4 (27/09/2026, đo stock iOS 26/27 — KeyGeometry): bước hàng 54
            // như stock, hàng đáy vùng 50 → 3 hàng chữ trùng vị trí stock tính từ đáy.
            // Máy gập mở: 208 (KeyLayout.phoneKeyAreaBase) thay 162 "ngang" — phím lùn.
            base = bounds.width > 0 ? KeyLayout.phoneKeyAreaBase(phoneForm)
                : (landscape ? 162 : KeyGeometry.phonePortraitBase)
        }
        return KeyLayout.keyAreaHeight(base: base, adjust: rowHeightAdjust,
                                       numberRow: numberRowEnabled) - bottomTrim
    }
    /// Chiều cao một hàng phím chuẩn (hàng số = 0.75× cái này).
    private func rowUnitHeight() -> CGFloat {
        (keyAreaHeight() + bottomTrim) / (numberRowEnabled ? 4 + KeyLayout.numberRowRatio : 4)
    }

    // Gắn vào window mới biết interfaceOrientation thật — ép layout lại để
    // chiều cao đúng ngay pass đầu (và sau khi host xoay lúc keyboard ẩn).
    override func didMoveToWindow() {
        super.didMoveToWindow()
        landscapeCache = nil; phoneFormCache = nil
        if window != nil { lastLayoutWidth = -1; setNeedsLayout() }
    }

    private var chromeMode: KeyLayout.ChromeMode {
        switch plane {
        case .emoji: return .emoji
        case .emojiSearch: return .emojiSearch
        default: return .keys
        }
    }

    /// Strip gợi ý chỉ hiện khi bật VÀ đang ở plane chữ/số — trong emoji plane
    /// ẩn đi cho gọn (user 2026-07-24). strip 30pt sát nút; phần dưới hàng
    /// phím cuối là vùng globe/mic hệ thống, không thuộc view mình.
    private func updateSuggestionChrome() {
        let visible = suggestionsEnabled && plane != .emoji && plane != .emojiSearch
        // Strip mở (bar 20pt + đệm trên) / 14 thu gọn / 0 tắt. Plane emoji GIỮ NGUYÊN
        // chiều cao strip (chỉ ẩn bar): đổi chiều cao bàn phím khi vào emoji làm host
        // relayout dở dang — dải trống + vạch đè hàng emoji đầu (Telegram, 25/09/2026).
        let strip = KeyLayout.stripHeight(reserved: stripReserved, collapsed: barCollapsed,
                                          open: Self.openStrip)
        // Lưới emoji chiếm luôn dải strip (thanh tìm nằm đúng chỗ thanh gợi ý như stock):
        // chỉ dời vùng hàng phím, tổng chiều cao GIỮ NGUYÊN → host không relayout.
        // Tìm emoji: ô tìm thế chỗ strip, phím chữ giữ đủ keyArea (KeyLayout.chrome).
        let c = KeyLayout.chrome(keyArea: keyAreaHeight(), strip: strip, mode: chromeMode)
        if rowsTopConstraint?.constant != c.rowsTop { rowsTopConstraint?.constant = c.rowsTop }
        baseRequestedHeight = c.total + safeBottom
        let total = baseRequestedHeight + hostFillExtra
        if heightConstraint?.constant != total { heightConstraint?.constant = total }
        if rowsBottomConstraint?.constant != -safeBottom { rowsBottomConstraint?.constant = -safeBottom }
        if rowsHeightConstraint?.constant != c.rows { rowsHeightConstraint?.constant = c.rows }
        if rowsMinHeightConstraint?.constant != c.rows { rowsMinHeightConstraint?.constant = c.rows }
        if rowsMinTopConstraint?.constant != c.minTop { rowsMinTopConstraint?.constant = c.minTop }
        if rowsMaxHeightConstraint?.constant != c.rows + 60 { rowsMaxHeightConstraint?.constant = c.rows + 60 }
        let barH = KeyLayout.emojiSearchBarHeight(strip: strip)
        if let h = searchBarHeight, h.constant != barH { h.constant = barH }
        suggestionBar.isHidden = !visible || barCollapsed
        suggestionBar.alpha = 1
        if !visible || barCollapsed { pasteCard.isHidden = true; notePasteOffer(false) }   // thu gọn / emoji plane
        lastSuggestionSig = ""   // chrome đổi → lượt show kế ghi lại (kể cả thẻ Dán)
        refreshCollapseButton(visible: visible)
    }

    // Rotation / Split View: indent hàng 2 và chiều cao tính theo bounds THẬT,
    // không dùng UIScreen.main (deprecated, sai trong Split View).
    private var lastLayoutWidth: CGFloat = 0
    override func layoutSubviews() {
        if Self.isPad { KeyButton.padLandscape = isLandscapeNow }   // phím tự áp cỡ chữ theo hướng
        super.layoutSubviews()
        letterGeometryCache = nil
        if bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            updateSuggestionChrome()
        }
        applyOneHand()
        if let r = indentedRow {
            // Thụt theo bề ngang VÙNG PHÍM (một tay: hẹp hơn view) — hàng 2 đúng nửa phím.
            let inset = KeyGeometry.indentedMargin(width: keysWidth, margin: Self.sideMargin,
                                                   gap: Self.keyGap, units: indentedRowInset)
            if r.layoutMargins.left != inset {
                r.layoutMargins = UIEdgeInsets(top: KeyGeometry.rowGap, left: inset, bottom: 0, right: inset)
            }
        }
        applyBottomTrim()
        layoutSuggestionBar()
        layoutStripZones()
        layoutOverlayPanel()
        layoutBackdrop()
        loadWallpaperIfNeeded()
        logGeometryIfChanged()
        if pasteCard.superview != nil, !pasteCard.isHidden {   // xoay màn hình
            let w = Self.stripZoneWidth
            let clipW = clipboardButtonVisible ? Self.clipZoneWidth : 0   // chừa nút 📋
            pasteCard.frame = CGRect(x: w, y: Self.barTopPad, width: max(bounds.width - 2 * w - clipW, 0),
                                     height: Self.openStrip - Self.barTopPad)
        }
    }

    /// Cập nhật gợi ý theo layout stock: ["nguyên văn"] | từ gợi ý | emoji(≤3),
    /// ngăn cách bằng divider mảnh. Mảng rỗng → dọn bar.
    struct SuggestionSet {
        var literal: String? = nil
        var word: String? = nil
        var word2: String? = nil       // ứng viên inline thứ hai (khi không có emoji)
        var emojis: [String] = []
        var nextWords: [String] = []   // gợi ý khi CHƯA gõ (đầu câu / sau space)
        var paste = false               // thẻ Dán thay bar (vừa copy, xem controller)
        var pasteIsImage = false        // clipboard là ẢNH: bàn phím không chèn được → chỉ hướng dẫn
        var restoreLabel: String? = nil // ô "Khôi phục" sau vuốt ⌫ xoá theo từ (slot đầu)
        var restorePayload: String? = nil // payload ô restoreLabel (nil = restoreToken; toolUndoToken = hoàn tác công cụ văn bản)
        var number: String? = nil       // chip số (NumberChips) — luôn ở slot GIỮA, payload numberToken
        var math: String? = nil         // kết quả phép tính "…=" (MathResults) — slot ĐẦU, payload mathToken
        /// Chip tách số từ nội dung vừa copy ("Dán STK 0123…") — thay thẻ Dán.
        var clipChips: [(display: String, insert: String)] = []
        var actionLabel: String? = nil  // chip hành động slot đầu ("Thêm dấu" / "Hoàn tác")…
        var actionPayload: String? = nil // …và payload (addTonesToken / undoTonesToken)
        var isEmpty: Bool {
            literal == nil && word == nil && word2 == nil && emojis.isEmpty && nextWords.isEmpty
                && number == nil && math == nil
        }
    }

    // Pool cố định: 3 nút chính + 2 vạch ngăn + 3 nút emoji con. Mỗi keystroke
    // CHỈ đổi title/hidden của ô nào khác — không removeFromSuperview/addSubview.
    private var slotButtons: [KeyButton] { suggestionBar.slots }
    private var emojiButtons: [KeyButton] { suggestionBar.emojis }
    private var slotDividers: [UIView] { suggestionBar.dividers }
    private static let slotFont = UIFont.systemFont(ofSize: 17, weight: .regular)
    private static let chipFont = UIFont.systemFont(ofSize: 14, weight: .regular)
    private var barInkApplied: UIColor?
    private var barWired = false

    /// Thanh gợi ý theo KHUNG CỐ ĐỊNH (27/09/2026): 3 ô bằng nhau, vạch ngăn ở mép ô 1|2,
    /// 2|3, emoji chia đều ô 3. Frame chỉ tính lại khi bề rộng bar / số emoji đổi — mỗi
    /// phím chỉ đổi chữ. Trước: UIStackView + ô Auto Layout, setTitle đổi intrinsic size
    /// ⇒ giải constraint + layout lại cả KeyboardView mỗi phím (~1.8 ms main/phím, bench B).
    private final class SuggestionBar: UIView {
        let slots: [KeyButton]
        /// Chữ slot: UILabel riêng phủ trọn nút (không setTitle) — UIButton dò lại rect
        /// title/ảnh mỗi lần đổi chữ (~¼ thời gian layout+vẽ bar, Time Profiler 27/09).
        let labels: [UILabel]
        let emojis: [KeyButton]
        let dividers: [UIView]
        private(set) var cellFrames: [CGRect] = []
        private var laidOut: CGSize = .zero
        private var emojiCount = 0
        /// Chip clipboard (1–3): CHIA ĐỀU bar như Android/Gboard; 0 = 3 ô cố định. Trước đây
        /// [Dán SĐT…][Dán] nằm trong 2/3 ô, ô 3 trống ⇒ thanh gợi ý trông "ngắn 1 đoạn"
        /// (Hữu Đông 28/09/2026).
        private(set) var chipCount = 0
        /// Hit-area nở của slot (âm = rộng hơn bar): bar 20pt, nút ăn cả phần strip còn lại.
        var hitInsets: UIEdgeInsets = .zero

        init(makeSlot: () -> KeyButton) {
            slots = (0..<3).map { _ in makeSlot() }
            labels = (0..<3).map { _ in UILabel() }
            emojis = (0..<3).map { _ in makeSlot() }
            dividers = (0..<2).map { _ in UIView() }
            super.init(frame: .zero)
            for (b, l) in zip(slots, labels) {
                l.textAlignment = .center
                l.lineBreakMode = .byTruncatingMiddle   // như titleLabel UIButton cũ
                l.minimumScaleFactor = 0.7              // ô cố định: chữ dài co lại, không nở ô
                l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                b.addSubview(l)
                addSubview(b)
            }
            for b in emojis {
                b.titleLabel?.font = .systemFont(ofSize: 20)   // vừa content box 22pt
                b.isHidden = true
                addSubview(b)
            }
            for d in dividers { d.isUserInteractionEnabled = false; addSubview(d) }
        }
        convenience init() { self.init(makeSlot: { KeyButton(type: .custom) }) }
        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != laidOut else { return }
            laidOut = bounds.size
            let w = bounds.width / 3, h = bounds.height
            cellFrames = (0..<3).map { CGRect(x: CGFloat($0) * w, y: 0, width: w, height: h) }
            layoutSlots()
            layoutEmojis()
        }

        /// Chỉ chạy khi bề rộng bar / số chip đổi — mỗi phím không đụng frame.
        func setChipCount(_ n: Int) {
            let n = min(max(n, 0), 3)
            guard n != chipCount else { return }
            chipCount = n
            layoutSlots()
        }
        private func layoutSlots() {
            guard cellFrames.count == 3 else { return }
            let n = chipCount > 0 ? chipCount : 3
            let cw = bounds.width / CGFloat(n), h = bounds.height
            for (i, b) in slots.enumerated() {
                let cell = i < n ? CGRect(x: CGFloat(i) * cw, y: 0, width: cw, height: h) : cellFrames[i]
                b.frame = cell.insetBy(dx: 3, dy: 0)
                labels[i].frame = b.bounds
                Self.fitShrink(labels[i])
            }
            for (i, d) in dividers.enumerated() {
                let x = i + 1 < n ? CGFloat(i + 1) * cw : cellFrames[i].maxX
                d.frame = CGRect(x: x - 0.5, y: 4, width: 1, height: max(h - 8, 0))
            }
        }
        /// Số vạch ngăn dùng được ở chế độ hiện tại (chip: giữa các chip).
        var usableDividers: Int { chipCount > 0 ? chipCount - 1 : 2 }

        /// Emoji hiện chia đều ô 3 (như stack fillEqually cũ: 1 emoji = cả ô).
        func setEmojiCount(_ n: Int) {
            guard n != emojiCount else { return }
            emojiCount = n
            layoutEmojis()
        }
        private func layoutEmojis() {
            guard cellFrames.count == 3, emojiCount > 0 else { return }
            let c = cellFrames[2], ew = c.width / CGFloat(emojiCount)
            for (i, b) in emojis.enumerated() where i < emojiCount {
                b.frame = CGRect(x: c.minX + CGFloat(i) * ew, y: 0, width: ew, height: c.height)
            }
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            bounds.inset(by: hitInsets).contains(point)
        }

        /// Đặt chữ slot; chỉ ghi khi chữ/font đổi.
        func setText(_ i: Int, _ text: String, font: UIFont) {
            let l = labels[i]
            guard l.text != text || l.font !== font else { return }
            l.text = text
            if l.font !== font { l.font = font }
            slots[i].accessibilityLabel = text
            Self.fitShrink(l)
        }

        /// adjustsFontSizeToFitWidth tốn một lượt đo co chữ mỗi lần vẽ — chỉ bật khi chữ
        /// CÓ THỂ không vừa ô (ước lượng trên: mọi glyph ≤ 0.95em; ô 0 = chưa layout ⇒ bật).
        static func fitShrink(_ l: UILabel) {
            let n = CGFloat(l.text?.count ?? 0)
            let need = l.bounds.width <= 0 || n * l.font.pointSize * 0.95 > l.bounds.width
            if l.adjustsFontSizeToFitWidth != need { l.adjustsFontSizeToFitWidth = need }
        }
    }

    private func buildSuggestionPoolIfNeeded() {
        guard !barWired else { return }
        barWired = true
        // Bar 20pt trong strip openStrip → nút nở hit-area xuống ĐÚNG phần còn lại
        // của strip (34−20−4 = 10pt), không lấn hàng Q–P bên dưới.
        let barHit = UIEdgeInsets(top: -8, left: -3,
                                  bottom: -(Self.openStrip - 20 - Self.barTopPad), right: -3)
        suggestionBar.hitInsets = UIEdgeInsets(top: barHit.top, left: 0, bottom: barHit.bottom, right: 0)
        for b in slotButtons + emojiButtons {
            b.backgroundColor = .clear
            b.isMultipleTouchEnabled = true
            b.hitInsets = barHit
            // Chốt payload lúc CHẠM XUỐNG: gợi ý nền về giữa down/up đổi ô thì vẫn chèn
            // đúng chữ đang hiện dưới ngón tay (bug 27/09/2026).
            b.addAction(UIAction { [weak b] _ in b?.downPayload = b?.payload }, for: .touchDown)
            b.addAction(UIAction { [weak self, weak b] _ in
                guard let b else { return }
                let s = b.downPayload ?? b.payload
                b.downPayload = nil
                if let s { self?.onSuggestion?(s) }
            }, for: .touchUpInside)
            b.addAction(UIAction { [weak b] _ in b?.downPayload = nil }, for: [.touchCancel, .touchUpOutside])
        }
        // Burger + chevron KHÔNG nằm trong bar: 2 nút ghim cố định ở mép
        // (burgerZone / chevronZone — xem layoutStripZones).
    }

    // MARK: mẫu câu nhanh (burger menu, user 2026-07-24)

    /// Mặc định = ios-mau-cau.yml bundle theo build (user 2026-07-24 — sửa file
    /// là build sau có bộ mới); dùng khi user CHƯA tự chỉnh trong app (tab Mẫu
    /// Câu, App Group "userTemplates" = [["label":…, "text":…]]). Bubble hiện
    /// label (👋) nếu có, không thì text truncate đuôi "…".
    static let templates: [(label: String, text: String)] = {
        guard let url = Bundle(for: KeyboardView.self)
                .url(forResource: "ios-mau-cau", withExtension: "yml"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [("👋", "Chào buổi sáng"), ("😴", "Chúc ngủ ngon"), ("", "Miss you")] }
        let parsed = parseTemplatesYAML(text)
        return parsed.isEmpty ? [("👋", "Chào buổi sáng")] : parsed
    }()

    /// Flat YAML: `- "label | text"` hoặc `- text` (cùng format app export).
    static func parseTemplatesYAML(_ text: String) -> [(label: String, text: String)] {
        text.split(separator: "\n").compactMap { line in
            var s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, !s.hasPrefix("#"), s.hasPrefix("- ") else { return nil }
            s = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
                s = String(s.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
            }
            guard !s.isEmpty else { return nil }
            if let r = s.range(of: " | ") {
                let body = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { return nil }
                return (String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces), body)
            }
            return ("", s)
        }
    }

    /// Danh sách mẫu câu — đọc LƯỜI lúc mở plane mẫu câu (nil = chưa đọc). Tắt "Mẫu câu"
    /// (Tính Năng → Gõ tắt) ⇒ không bao giờ đọc App Group / parse YAML bundle (0 chi phí).
    private var userTemplatesCache: [(label: String, text: String)]?
    private var userTemplates: [(label: String, text: String)] {
        if let c = userTemplatesCache { return c }
        let c: [(label: String, text: String)]
        if let raw = UserDefaultsProvider.shared?.array(forKey: "userTemplates") as? [[String: String]] {
            c = raw.compactMap { e in
                guard let t = e["text"], !t.isEmpty else { return nil }
                return (e["label"] ?? "", t)
            }
        } else {
            c = Self.templates
        }
        userTemplatesCache = c
        return c
    }
    #if DEBUG
    var debugTemplatesLoaded: Bool { userTemplatesCache != nil }
    var debugBurgerVisible: Bool { burgerZone.superview != nil && !burgerZone.isHidden }
    var debugInTemplates: Bool { plane == .templates }
    #endif
    private var templatesEnabled = true
    private var templatesActive: Bool { plane == .templates }
    /// Chèn thẳng vào input, KHÔNG qua máy học từ (câu nhiều từ làm bẩn model).
    var onTemplate: ((String) -> Void)?
    /// Bubble ⚙️ cuối lưới → controller mở tab Mẫu Câu của app.
    var onOpenTemplates: (() -> Void)?

    // MARK: công cụ văn bản (Plus) — lối vào: chip đầu lưới mẫu câu (burger): chạm
    // "Aa Công cụ văn bản" → lưới đổi sang danh sách thao tác (áp lên phần đang chọn /
    // câu trước con trỏ), chạm thao tác → về bàn phím chữ.

    /// PlusGate.isUnlocked(.textTools) — controller đặt mỗi lần hiện bàn phím.
    var textToolsEnabled = false {
        didSet {
            if oldValue != textToolsEnabled, templatesActive { rebuildUncachedPlane() }
        }
    }
    var onTextTool: ((TextTool) -> Void)?
    private var textToolsMode = false
    private static let textToolsEntryID = "\u{E000}tools"
    private static let textToolsBackID = "\u{E000}back"

    /// Dựng lại plane mẫu câu (không cache) đang hiện dù chữ ký không đổi —
    /// rebuild() bỏ qua khi builtPlane == plane (lật danh sách công cụ, bật/tắt Plus).
    private func rebuildUncachedPlane() {
        if plane == .templates { builtPlane = nil }
        rebuild()
    }

    private func toggleTemplates() {
        guard templatesEnabled else { return }
        Self.clickModifier()
        textToolsMode = false
        plane = templatesActive ? .letters : .templates
        lastSuggestionSig = ""
        rebuild()
        styleBurger()
    }

    private func styleBurger() {
        // Icon/tint burgerZone do layoutStripZones set theo templatesActive —
        // ép layout lại để đổi trạng thái đậm/nhạt ngay khi bật/tắt mẫu câu.
        setNeedsLayout()
    }

    /// Payload của nút Dán trên bar — ký tự Private Use, không thể là từ thật.
    static let pasteToken = "\u{E000}paste"
    /// Clipboard là ảnh: iOS không cho bàn phím chèn ảnh (chỉ insertText) — thẻ chỉ
    /// hướng dẫn; chạm = ẩn thẻ.
    static let pasteImageToken = "\u{E000}pasteImage"
    /// Payload ô "Khôi phục" (chèn lại đoạn vừa vuốt ⌫ xoá).
    static let restoreToken = "\u{E000}restore"
    /// Payload chip số: controller giữ NumberChip (đuôi cần thay + chữ chèn).
    static let numberToken = "\u{E000}number"
    /// Chip kết quả phép tính (MathResults) — controller giữ chữ cần chèn.
    static let mathToken = "\u{E000}math"
    /// Payload ô "↩︎ Hoàn tác" sau khi áp công cụ văn bản.
    static let toolUndoToken = "\u{E000}toolUndo"
    /// Payload chip "Thêm dấu" / "Hoàn tác" (AddTones — chỉ khi người dùng bấm).
    static let addTonesToken = "\u{E000}addTones"
    static let undoTonesToken = "\u{E000}undoTones"
    /// Payload chip "↩︎ từ cũ": hoàn tác lần vuốt vừa sửa lại từ vuốt trước (SwipeRevise).
    static let undoReviseToken = "\u{E000}undoRevise"
    /// Payload chip "↩︎ chữ gốc": trả lại chữ đã gõ của lần tự sửa vừa rồi (AutoCorrect).
    static let undoAutoCorrectToken = "\u{E000}undoAutoCorrect"

    func showSuggestions(_ set: SuggestionSet) {
        guard suggestionsEnabled, !barCollapsed else { return }
        buildSuggestionPoolIfNeeded()

        // Thứ tự ưu tiên slot (hoàn tác > clipboard > Thêm dấu > chip số > chữ): SuggestionSlots.
        var texts: [(display: String, insert: String)?] = [nil, nil, nil]
        var emojis: [String] = []
        var pasteCardOn = false
        var chipCount = 0
        switch SuggestionSlots.arrange(set) {
        case .slots(let s, let e):
            texts = s.map { $0.map { ($0.label, $0.payload) } }
            emojis = e
        case .chips(let c):
            for (i, x) in c.prefix(3).enumerated() { texts[i] = (x.label, x.payload) }
            chipCount = min(c.count, 3)
        case .pasteCard:
            pasteCardOn = true
        case .pill(let u):
            texts[0] = (u.label, u.payload)
        }
        // Lời mời dán có thực sự lên bar không (PasteOfferOnce: mời một lần mỗi mục).
        notePasteOffer(pasteCardOn || texts.contains { t in
            t.map { $0.insert == Self.pasteToken || $0.insert.hasPrefix(Self.clipTokenPrefix) } ?? false
        })
        // Nội dung không đổi (nextWords thường ổn định giữa các phím) → bỏ qua
        // toàn bộ ghi UI: setTitle trên bar fillProportionally kéo theo một
        // lượt đo text/Auto Layout mỗi keystroke.
        let sig = (dark ? "D" : "L") + themeSettings.theme.rawValue
            + texts.map { $0.map { $0.display + "\u{1}" + $0.insert } ?? "\u{2}" }.joined(separator: "\u{3}")
            + "\u{4}" + emojis.joined()
            + (pasteCardOn ? (set.pasteIsImage ? "\u{5}pasteImg" : "\u{5}paste") : "")
        if sig == lastSuggestionSig { return }
        lastSuggestionSig = sig

        suggestionBar.setChipCount(chipCount)
        let ink = palette.barInk.ui
        let inkChanged = barInkApplied != ink
        barInkApplied = ink
        if inkChanged {
            for d in slotDividers { d.backgroundColor = ink.withAlphaComponent(0.18) }
            for l in suggestionBar.labels { l.textColor = ink }   // cả ô đang ẩn
        }
        // Chỉ ghi thuộc tính THỰC SỰ đổi (chữ literal đổi mỗi phím, 2 ô kia thường giữ).
        for (i, b) in slotButtons.enumerated() {
            if let t = texts[i] {
                let chip = t.insert.hasPrefix(Self.clipTokenPrefix) || (t.insert == Self.pasteToken)
                suggestionBar.setText(i, t.display, font: chip ? Self.chipFont : Self.slotFont)
                b.payload = t.insert
                if b.isHidden { b.isHidden = false }
            } else {
                if !b.isHidden { b.isHidden = true }
                b.payload = nil
            }
        }
        // slot emoji (chỉ ở chế độ đang gõ, khi có emoji)
        suggestionBar.setEmojiCount(emojis.count)
        for (i, b) in emojiButtons.enumerated() {
            if i < emojis.count {
                if b.title(for: .normal) != emojis[i] { b.setTitle(emojis[i], for: .normal) }
                b.payload = emojis[i]
                if b.isHidden { b.isHidden = false }
            } else {
                if !b.isHidden { b.isHidden = true }
                b.payload = nil
            }
        }
        // Vạch ngăn cố định: hiện khi bar có nội dung (ô trống vẫn giữ chỗ — như stock).
        let anyVisible = texts.contains { $0 != nil } || !emojis.isEmpty
        let usable = suggestionBar.usableDividers
        for (i, d) in slotDividers.enumerated() {
            let hide = !anyVisible || pasteCardOn || i >= usable
            if d.isHidden != hide { d.isHidden = hide }
        }
        // Nút Dán kiểu iOS 27: MỘT ô rộng giữa bar, 2 dòng, thay cả 3 slot.
        setPasteCard(visible: pasteCardOn, image: set.pasteIsImage, ink: ink)
    }

    // MARK: Clipboard (lịch sử + chip) — không có chỉ báo ẩn danh (Phil 27/09 bỏ icon mắt gạch)
    /// Payload chip tách số: prefix + giá trị cần chèn.
    static let clipTokenPrefix = "\u{E000}clip:"
    static let clipZoneWidth: CGFloat = 40
    /// Lời mời dán (thẻ Dán / chip clipboard) hiện (true) / rời bar (false). Gọi khi ĐỔI,
    /// và mỗi lượt vẽ khi đang hiện (copy mới giữa chừng vẫn được ghi nhận); lúc gõ chữ
    /// (không có lời mời) không gọi.
    var onPasteOfferVisible: ((Bool) -> Void)?
    private var pasteOfferOn = false
    private func notePasteOffer(_ on: Bool) {
        guard on || on != pasteOfferOn else { return }
        pasteOfferOn = on
        onPasteOfferVisible?(on)
    }
    private var clipboardButtonVisible = false
    var onOpenClipboard: (() -> Void)?
    /// Panel phủ vùng phím: touch trong panel KHÔNG đi qua router phím chữ.
    weak var overlayPanel: UIView?
    var isDarkAppearance: Bool { dark }
    /// Vùng phím (dưới strip) — nơi đặt panel clipboard.
    var keyAreaFrame: CGRect { rowsContainer.frame }

    private var clipZoneMade = false
    private lazy var clipZone: UIButton = {
        clipZoneMade = true
        let b = UIButton(type: .custom)
        b.accessibilityLabel = L("Lịch sử clipboard")
        b.addAction(UIAction { [weak self] _ in
            Self.clickModifier()
            self?.onOpenClipboard?()
        }, for: .touchUpInside)
        addSubview(b)
        return b
    }()
    func setClipboardButton(visible: Bool) {
        guard visible != clipboardButtonVisible else { return }
        clipboardButtonVisible = visible
        setNeedsLayout()   // bề rộng bar (layoutSuggestionBar)
    }

    /// Panel clipboard bám ĐÚNG vùng phím mỗi lượt layout. Trước đây chỉ đặt frame lúc mở
    /// + autoresizing (cao cố định, neo đáy): bàn phím đổi chiều cao khi panel đang mở (xoay,
    /// thu gọn ⌄, host cấp lại khung) ⇒ panel trồi lên đè dải gợi ý / hở hàng phím.
    private func layoutOverlayPanel() {
        guard let p = overlayPanel, p.superview === self else { return }
        let f = rowsContainer.frame
        if p.frame != f { p.frame = f }
        bringSubviewToFront(p)
    }

    private func layoutClipboardExtras(stripOpen: Bool) {
        let showClip = stripOpen && clipboardButtonVisible
        if clipboardButtonVisible || clipZoneMade { clipZone.isHidden = !showClip }
        if showClip, bounds.width > 0 {
            let strip = max(rowsTopConstraint?.constant ?? Self.openStrip, Self.openStrip)
            let w = Self.stripZoneWidth, cw = Self.clipZoneWidth
            clipZone.frame = CGRect(x: bounds.width - w - cw, y: 0, width: cw, height: strip)
            clipZone.setImage(UIImage(systemName: "doc.on.clipboard",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)), for: .normal)
            clipZone.tintColor = palette.barInk.ui.withAlphaComponent(overlayPanel == nil ? 0.45 : 0.9)
            let bottomInset = max(strip - 20 - Self.barTopPad, 0)
            clipZone.contentEdgeInsets = UIEdgeInsets(top: Self.barTopPad, left: 0, bottom: bottomInset, right: 0)
            bringSubviewToFront(clipZone)
        }
    }

    // MARK: Debug — hình học cửa sổ (25/09/2026)
    // Thanh gợi ý "bị cắt" ở Telegram / app VietTelex nhưng không ở WhatsApp/Notes: host
    // có lúc KHÔNG vẽ dải khung phía trên cửa sổ extension. Ghi hình học mỗi khi đổi để
    // tìm dấu hiệu phân biệt (chỉ khi Debug mode bật).
    private var lastGeomKey = ""
    private func logGeometryIfChanged() {
        guard TouchLog.enabled, let w = window else { return }
        let inWin = convert(bounds, to: w)
        let key = "\(w.bounds) \(inWin) \(w.safeAreaInsets) \(safeAreaInsets) \(superview?.frame ?? .zero)"
        guard key != lastGeomKey else { return }
        lastGeomKey = key
        TouchLog.write("geom window=\(NSCoder.string(for: w.bounds)) view=\(NSCoder.string(for: inWin)) "
            + "winSafe=\(NSCoder.string(for: w.safeAreaInsets)) viewSafe=\(NSCoder.string(for: safeAreaInsets)) "
            + "super=\(NSCoder.string(for: superview?.frame ?? .zero)) "
            + "host=\(inputController?.parent.map { String(describing: type(of: $0)) } ?? "-")")
    }

    // MARK: Nút Dán (iOS 27 style, 25/09/2026)
    // Stock hiện nội dung clipboard + "Paste from <App>" — bàn phím bên thứ ba KHÔNG
    // làm vậy được: đọc nội dung = iOS báo/hỏi quyền dán MỖI lần bàn phím hiện, và
    // app nguồn không lộ cho extension. Nên: "Dán" / "Nội dung vừa copy".
    private lazy var pasteCard: KeyButton = {
        let b = KeyButton(type: .custom)
        b.backgroundColor = .clear
        b.hitInsets = UIEdgeInsets(top: -8, left: 0, bottom: 0, right: 0)
        b.accessibilityLabel = L("Dán nội dung vừa copy")
        let title = UILabel(), sub = UILabel()
        title.text = L("Dán")
        title.font = .systemFont(ofSize: 14, weight: .regular)
        sub.text = L("Nội dung vừa copy")
        sub.font = .systemFont(ofSize: 10, weight: .regular)
        title.tag = 91; sub.tag = 92
        let icon = UIImageView(image: UIImage(systemName: "doc.on.clipboard",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)))
        icon.tag = 93
        let text = UIStackView(arrangedSubviews: [title, sub])
        text.axis = .vertical; text.alignment = .leading; text.spacing = -2
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal; row.alignment = .center; row.spacing = 8
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(row)
        // Neo SÁT ĐỈNH (user 25/09/2026: căn giữa strip 30pt làm dòng phụ chạm hàng
        // Q–P). Cả dải phía trên cửa sổ là khung host — không vẽ lên đó được.
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: b.centerXAnchor),
            row.topAnchor.constraint(equalTo: b.topAnchor, constant: 0),
        ])
        b.payload = Self.pasteToken
        b.addAction(UIAction { [weak self, weak b] _ in
            Self.clickModifier()
            if let p = b?.payload { self?.onSuggestion?(p) }
        }, for: .touchUpInside)
        return b
    }()

    /// Đang gõ dở: ẩn thẻ Dán NGAY ở phím (không đợi kết quả gợi ý chạy nền).
    func hidePasteCard() {
        notePasteOffer(false)
        guard !pasteCard.isHidden else { return }
        pasteCard.isHidden = true
        lastSuggestionSig = ""
    }

    private func setPasteCard(visible: Bool, image: Bool = false, ink: UIColor) {
        if visible {
            (pasteCard.viewWithTag(91) as? UILabel)?.text = image ? L("Ảnh vừa copy") : L("Dán")
            (pasteCard.viewWithTag(92) as? UILabel)?.text = image ? L("Giữ ô nhập → Dán") : L("Nội dung vừa copy")
            (pasteCard.viewWithTag(93) as? UIImageView)?.image = UIImage(
                systemName: image ? "photo.on.rectangle" : "doc.on.clipboard",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            pasteCard.payload = image ? Self.pasteImageToken : Self.pasteToken
            pasteCard.accessibilityLabel = image ? L("Ảnh vừa copy — giữ ô nhập rồi chọn Dán")
                                                 : L("Dán nội dung vừa copy")
            if pasteCard.superview == nil { addSubview(pasteCard) }
            let w = Self.stripZoneWidth
            let clipW = clipboardButtonVisible ? Self.clipZoneWidth : 0   // chừa nút 📋
            pasteCard.frame = CGRect(x: w, y: Self.barTopPad, width: max(bounds.width - 2 * w - clipW, 0),
                                     height: Self.openStrip - Self.barTopPad)
            (pasteCard.viewWithTag(91) as? UILabel)?.textColor = ink
            (pasteCard.viewWithTag(92) as? UILabel)?.textColor = ink.withAlphaComponent(0.55)
            (pasteCard.viewWithTag(93) as? UIImageView)?.tintColor = ink.withAlphaComponent(0.8)
            bringSubviewToFront(pasteCard)
        }
        pasteCard.isHidden = !visible
        // Thẻ Dán THAY cả bar: ẩn hẳn nội dung slot (trước đây chỉ alpha=0 cho bar — mọi
        // chỗ đặt lại alpha=1 như updateSuggestionChrome khi rebuild/đổi plane làm chữ
        // gợi ý hiện ĐÈ lên thẻ Dán, user 27/09/2026).
        if visible {
            for b in slotButtons + emojiButtons { b.isHidden = true; b.payload = nil }
            for d in slotDividers { d.isHidden = true }
        }
    }

    func configureReturnKey(type: UIReturnKeyType) {
        switch type {
        case .go: returnTitle = "go"
        case .search, .google, .yahoo: returnTitle = "search"
        case .send: returnTitle = "send"
        case .next: returnTitle = "next"
        case .done: returnTitle = "done"
        case .join: returnTitle = "join"
        default: returnTitle = "return"
        }
        rebuild()   // no-op nếu nhãn không đổi (chữ ký trong rebuild)
    }

    /// Gom cấu hình mỗi lần hiện (return / appearance / input kind) thành MỘT
    /// lần rebuild: trước đây configureReturnKey rồi configureInputKind mỗi hàm
    /// tự rebuild (và configureInputKind còn vứt cache) → xé + dựng ~40 phím
    /// 2 lần mỗi lần hiện dù không có gì đổi. Trong body mọi rebuild() bị hoãn;
    /// cuối cùng rebuild một lần — và rebuild tự bỏ qua khi chữ ký không đổi.
    func batchConfigure(_ body: () -> Void) {
        rebuildDeferred = true
        body()
        rebuildDeferred = false
        rebuild()
    }
    private var rebuildDeferred = false

    /// Loại ô nhập (từ textDocumentProxy.keyboardType) → đổi layout như stock:
    /// number mở thẳng plane số; email đổi hàng đáy thành phím @ và . ; url
    /// thành . / (đuôi .com/.vn… ở giữ "."); search (thanh địa chỉ/tìm kiếm trình duyệt, .webSearch) đổi
    /// "," thành "." như stock. Chỉ ảnh hưởng hàng đáy plane CHỮ + plane mở đầu.
    enum InputKind {
        case normal, number, email, url, search
        /// Ô chữ tự do: gõ tiếng Việt / vuốt / chọn phím theo ngữ cảnh như ô thường.
        var isFreeText: Bool { self == .normal || self == .search }
    }
    private var inputKind: InputKind = .normal

    func configureInputKind(_ kind: InputKind) {
        inputKind = kind
        plane = (kind == .number) ? .numbers : .letters
        let shiftDropped = plane == .letters && shift == .on
        if shiftDropped { shift = .off }
        // Kind nằm trong chữ ký của rebuild: đổi kind → cache vứt + dựng lại;
        // KHÔNG đổi → giữ cache, khỏi xé ~40 phím mỗi lần hiện.
        rebuild()
        // Shift đổi KHÔNG bao giờ rebuild — retitle tại chỗ (rebuild bị bỏ qua
        // thì phím cũ vẫn đang hiện chữ hoa).
        if shiftDropped, plane == .letters { applyShiftAppearance() }
    }

    /// Chỉ đổi sáng/tối (không đọc lại settings) — gọi khi trait host resolve muộn.
    func updateDark(_ isDark: Bool) {
        guard isDark != systemDark else { return }
        systemDark = isDark
        resolvePalette()
        rebuild()
    }

    /// Theme (App Group) + sáng/tối hệ thống + ảnh nền → palette; `dark` đi theo
    /// palette để emoji plane/icon hệ thống chọn đúng nhánh sáng/tối.
    private func resolvePalette() {
        let fileExists = Wallpaper.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        wallpaperActive = themeSettings.wallpaperActive(fileExists: fileExists)
        palette = themeSettings.palette(systemDark: systemDark, wallpaperActive: wallpaperActive)
        dark = palette.isDark
        applyBackdrop()
    }

    private func applyBackdrop() {
        if themeBackdrop.superview == nil {
            for v in [themeBackdrop, wallpaperView, wallpaperDim] {
                v.isUserInteractionEnabled = false
                v.frame = bounds
                v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
            wallpaperView.contentMode = .scaleAspectFill
            wallpaperView.clipsToBounds = true
            insertSubview(themeBackdrop, at: 0)
            insertSubview(wallpaperView, aboveSubview: themeBackdrop)
            insertSubview(wallpaperDim, aboveSubview: wallpaperView)
        }
        // Theme nền trong suốt (mặc định Hệ thống): KHÔNG phủ nền đục — vật liệu bàn phím hệ
        // thống lộ ra nên vùng phím cùng màu dải 🌐/🎤 iOS vẽ bên dưới (ThemeSettings.clearBackground).
        let clear = themeSettings.clearBackground(systemDark: systemDark, wallpaperActive: wallpaperActive)
        themeBackdrop.backgroundColor = clear ? nil : palette.background?.ui
        themeBackdrop.isHidden = clear || palette.background == nil
        // Nền tự vẽ: bo 2 góc trên theo khung kính bàn phím iOS 26+ (không còn góc vuông đen
        // chồng lên góc bo xám của hệ thống). cornerRadius trên view lá màu phẳng / ảnh ⇒ không
        // offscreen pass.
        let r = clear ? 0 : KeyLayout.backdropCornerRadius(phone: !Self.isPad, systemMajor: Self.systemMajor)
        for v in [themeBackdrop, wallpaperView, wallpaperDim] where v.layer.cornerRadius != r {
            v.layer.cornerRadius = r
            v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            v.layer.cornerCurve = .circular   // khớp khung hệ thống (đo pixel, KeyLayout)
        }
        wallpaperView.isHidden = !wallpaperActive
        // Độ trong suốt phím: alpha của một UIImageView lá (không sublayer) → không offscreen.
        wallpaperView.alpha = CGFloat(palette.surfaceAlpha)
        wallpaperDim.isHidden = !wallpaperActive
        wallpaperDim.backgroundColor = palette.wallpaperOverlay
            .alpha(Double(themeSettings.dim) / 100 * palette.surfaceAlpha).ui
        if !wallpaperActive {
            wallpaperView.image = nil          // nhả bitmap ngay khi tắt ảnh nền
            wallpaperLoadedFor = .zero
        } else {
            wallpaperLoadedFor = .zero         // version/cỡ có thể đã đổi → nạp lại
            setNeedsLayout()
        }
    }

    private static let systemMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    /// Nền theme / ảnh nền / lớp phủ phủ TRỌN view (= cả input view: strip, headroom balloon,
    /// phần host cấp dư hoặc thiếu) — đặt frame tường minh mỗi lượt layout, không dựa
    /// autoresizing từ frame lúc chèn (có thể là .zero).
    private func layoutBackdrop() {
        for v in [themeBackdrop, wallpaperView, wallpaperDim] where v.superview === self && v.frame != bounds {
            v.frame = bounds
        }
    }
    #if DEBUG
    /// Test: frame nền theme / ảnh nền / lớp phủ + bán kính bo.
    var debugBackdrop: (frames: [CGRect], radius: CGFloat) {
        ([themeBackdrop.frame, wallpaperView.frame, wallpaperDim.frame], themeBackdrop.layer.cornerRadius)
    }
    #endif

    /// Giải ảnh nền ở đúng cỡ view, ngoài main thread (ImageIO thumbnail).
    private func loadWallpaperIfNeeded() {
        guard wallpaperActive, bounds.width > 0, bounds.height > 0,
              bounds.size != wallpaperLoadedFor else { return }
        wallpaperLoadedFor = bounds.size
        let size = bounds.size
        let scale = Wallpaper.decodeScale(screenScale: window?.screen.scale ?? UIScreen.main.scale)
        let version = themeSettings.version
        Wallpaper.queue.async { [weak self] in
            let img = Wallpaper.loadForKeyboard(version: version, viewSize: size, scale: scale)
            DispatchQueue.main.async {
                guard let self, self.wallpaperActive else { return }
                self.wallpaperView.image = img
            }
        }
    }

    func applyAppearance(_ appearance: UIKeyboardAppearance, style: UIUserInterfaceStyle) {
        systemDark = AppearancePolicy.isDark(appearance: appearance, style: style)
        themeSettings = ThemeSettings.load(UserDefaultsProvider.shared)
        resolvePalette()
        // Chiều cao hàng phím ±10pt (Settings → Giao diện) — đọc mỗi lần hiện.
        let adj = UserDefaultsProvider.shared?.object(forKey: "rowHeightAdjust") as? Int ?? 0
        rowHeightAdjust = CGFloat(max(-10, min(10, adj)))
        numberRowEnabled = UserDefaultsProvider.shared?.bool(forKey: Self.numberRowKey) ?? false
        keyPreviewEnabled = Self.keyPreviewSetting(UserDefaultsProvider.shared)
        if !keyPreviewEnabled { hideBalloon() }
        // Mẫu câu: danh sách user tự quản trong app + toggle bật/tắt.
        let d = UserDefaultsProvider.shared
        templatesEnabled = d?.object(forKey: "templatesEnabled") == nil
            || d?.bool(forKey: "templatesEnabled") == true
        userTemplatesCache = nil      // đọc lại (lười) lần mở plane mẫu câu kế — app có thể vừa sửa
        if !templatesEnabled, plane == .templates { plane = .letters }
        rebuild()
    }

    /// needsInputModeSwitchKey chỉ đáng tin SAU khi extension nối host —
    /// đánh giá lại ở viewWillAppear; đổi thì dựng lại hàng đáy.
    func setNeedsGlobe(_ on: Bool) {
        guard on != needsGlobe else { return }
        needsGlobe = on
        rebuild()   // globe nằm trong chữ ký → cache (hàng đáy cũ) bị vứt
    }

    /// Viết hoa đầu câu theo context hiện tại (controller đọc proxy) — nil = không áp.
    var autoShiftProbe: (() -> Bool?)?

    /// Về plane chữ bằng ABC: đánh giá lại shift (PlanePolicy.shiftOnReturnToLetters)
    /// thay vì ép off — ". " vừa gõ ở plane 123 phải viết hoa chữ kế. CAPS giữ nguyên.
    /// rebuild() ngay sau áp giao diện (cache) hoặc dựng phím theo shift mới.
    private func reevaluateShiftForLetters() {
        guard shift != .caps else { return }
        shift = PlanePolicy.shiftOnReturnToLetters(autoShift: autoShiftProbe?()) ? .on : .off
    }

    /// Sentence-start auto-shift (only upgrades OFF→ON; never downgrades CAPS).
    func setAutoShift(_ on: Bool) {
        guard shift != .caps, plane != .emojiSearch else { return }
        let want: ShiftState = on ? .on : .off
        if shift != want { shift = want; applyShiftAppearance() }
    }


    // Shift changes must NEVER rebuild: tearing the buttons down mid-typing
    // deallocates the key already under the user's finger, so its touch-up
    // never fires (the missed-keypress bug). Retitle in place instead.
    private var letterKeys: [(button: UIButton, base: String)] = []
    private weak var spaceBar: UIButton?
    private weak var spaceLogo: UIImageView?
    /// Mã "VI"/"EN" góc dưới-phải phím cách (thay logo khi bật vuốt đổi ngôn ngữ — SpaceMark).
    private weak var spaceCode: UILabel?
    /// Logo hoặc mã ngôn ngữ đang trên phím cách (ẩn/hiện khi trượt nhãn, badge).
    private var spaceMarkView: UIView? { spaceCode ?? spaceLogo }
    private weak var indentedRow: UIStackView?
    private var indentedRowInset: CGFloat = 0
    private var shiftKeys: [KeyButton] = []   // iPad có 2 shift
    private func applyShiftAppearance() {
        for (b, s) in letterKeys {
            let t = shift == .off ? s : s.uppercased()
            b.setTitle(t, for: .normal)
            if let k = b as? KeyButton { applyKeycapFont(k, title: t) }
        }
        for b in shiftKeys {
            let symbol = shift == .caps ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift")
            b.setImage(UIImage(systemName: symbol), for: .normal)
            // Shift ON/CAPS = phím đảo màu (nền trắng, glyph đen) như stock —
            // cả dark mode, nếu không ON và OFF trông y hệt nhau.
            if shift != .off {
                b.backgroundColor = shiftOnFill
                b.tintColor = shiftOnInk
            } else {
                b.backgroundColor = plainFill
                b.tintColor = ink
            }
            b.normalBackground = b.backgroundColor
        }
        capsKey?.setImage(UIImage(systemName: shift == .caps ? "capslock.fill" : "capslock"),
                          for: .normal)
    }
    private weak var capsKey: KeyButton?
    /// Shift ON = phím trắng glyph đen; phím trong suốt quá nửa thì glyph theo chữ phím.
    private var shiftOnFill: UIColor { RGBA.white.alpha(palette.surfaceAlpha).ui }
    private var shiftOnInk: UIColor {
        palette.surfaceAlpha >= 0.5 ? RGBA.black.alpha(palette.keyInk.a).ui : ink
    }


    // MARK: chế độ một tay (iPhone)

    /// Chế độ hiện tại. Controller đặt lúc hiện (configureOneHand, theo OneHand.resolve);
    /// bàn phím tự đổi qua giữ lâu burger / rail rồi báo
    /// onOneHandChange để controller lưu.
    private(set) var oneHand: OneHandSide = .off
    /// Bên dùng gần nhất — giữ lâu bật lại bên này.
    var lastOneHandSide: OneHandSide = .right
    var onOneHandChange: ((OneHandSide) -> Void)?

    /// Đặt từ controller (không báo lại). iPad luôn tắt.
    func configureOneHand(_ side: OneHandSide) {
        let s = Self.isPad ? .off : side
        guard s != oneHand else { return }
        oneHand = s
        if s != .off { lastOneHandSide = s }
        applyOneHand()
        setNeedsLayout()
    }

    /// Người dùng đổi trên bàn phím.
    private func setOneHand(_ side: OneHandSide) {
        configureOneHand(side)
        onOneHandChange?(oneHand)
    }

    /// Plane hiện tại có thu hẹp không (emoji / mẫu câu tự dàn đầy bề ngang).
    private var oneHandActive: Bool {
        oneHand != .off && !Self.isPad && plane != .emoji && plane != .templates
            && plane != .emojiSearch   // họ emoji: ô tìm + chữ đầy bề ngang (Android y hệt)
    }
    /// Bề ngang vùng phím (thụt hàng 2 tính theo đây).
    private var keysWidth: CGFloat {
        oneHandActive ? bounds.width * OneHand.ratio : bounds.width
    }

    private func applyOneHand() {
        let side: OneHandSide = oneHandActive ? oneHand : .off
        let i = OneHand.insets(width: bounds.width, side: side)
        if rowsLeftConstraint?.constant != i.left { rowsLeftConstraint?.constant = i.left }
        if rowsRightConstraint?.constant != -i.right { rowsRightConstraint?.constant = -i.right }
        layoutRail(side)
    }

    /// Rail: 2 nút tròn ở dải trống — đổi bên (trên) / thoát (dưới). Chỉ tạo khi cần.
    private var railButtons: [KeyButton] = []
    private func layoutRail(_ side: OneHandSide) {
        guard let r = OneHand.rail(width: bounds.width, side: side), r.width >= 24 else {
            railButtons.forEach { $0.isHidden = true }
            return
        }
        if railButtons.isEmpty {
            for (i, symbol) in ["arrow.left.arrow.right", "arrow.up.left.and.arrow.down.right"].enumerated() {
                let b = baseButton(title: "", special: true)
                b.setImage(UIImage(systemName: symbol,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
                b.accessibilityLabel = i == 0 ? L("Đổi bên bàn phím một tay") : L("Thoát chế độ một tay")
                b.addAction(UIAction { _ in Self.clickModifier() }, for: .touchDown)
                b.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.setOneHand(i == 0 ? self.oneHand.switched : .off)
                }, for: .touchUpInside)
                addSubview(b)
                railButtons.append(b)
            }
        }
        let top = rowsTopConstraint?.constant ?? 0
        let h = max(bounds.height - top, 0)
        let size = min(r.width - 12, 44)
        for (i, b) in railButtons.enumerated() {
            let cy = top + h * (i == 0 ? 0.3 : 0.7)
            b.frame = CGRect(x: r.x + (r.width - size) / 2, y: cy - size / 2, width: size, height: size)
            b.layer.cornerRadius = size / 2
            b.backgroundColor = specialFill
            b.normalBackground = specialFill
            b.pressedBackground = plainFill
            b.tintColor = dark ? .white : .black
            b.isHidden = false
            bringSubviewToFront(b)
        }
    }

    // MARK: layout

    // Dedupe: rebuild bị gọi nhiều lần mỗi lần hiện (init, configureReturnKey,
    // applyAppearance, configureInputKind, setNeedsGlobe) — chỉ xé/dựng lại khi
    // có gì đó thật sự đổi. Chữ ký = mọi thứ làm nhãn/màu/inset/hàng đáy của
    // plane khác đi; đổi chữ ký → mọi plane cache đều sai nên vứt hết.
    private var builtPlane: Plane?
    private var builtReturn = ""
    private var builtDark = false
    private var builtPalette = KeyboardTheme.system.palette(systemDark: false)
    private var builtWidth: CGFloat = -1
    private var builtGlobe = false
    private var builtKind: InputKind = .normal
    private var builtNumberRow = false

    // Cache view theo plane: bấm 123/#+=/ABC chỉ tráo arrangedSubviews thay vì
    // xé/dựng lại ~40 button + constraints mỗi lần. Emoji KHÔNG cache (recents
    // phải tươi mỗi lần mở). Đổi return/dark/width → mọi plane cache đều sai
    // nhãn/màu/inset nên vứt hết.
    private struct CachedPlane {
        let rows: [UIView]
        let letterKeys: [(button: UIButton, base: String)]
        let shiftKeys: [KeyButton]
        let spaceBar: UIButton?
        let spaceLogo: UIImageView?
        let spaceCode: UILabel?
        let indentedRow: UIStackView?
        let indentedRowInset: CGFloat
        let crossRow: [NSLayoutConstraint]
        let distribution: UIStackView.Distribution   // .fill khi có hàng số (cao khác nhau)
    }
    /// Ràng buộc GIỮA các hàng (phím hàng dưới neo bề rộng theo q hàng 1). UIKit
    /// tự gỡ chúng khi row rời hierarchy (lúc tráo plane) — lưu lại để bật lại khi
    /// khôi phục từ cache (bug 26/09/2026: về từ mẫu câu, phím lệch cỡ).
    private var crossRowConstraints: [NSLayoutConstraint] = []
    private func crossRow(_ c: NSLayoutConstraint) {
        c.isActive = true
        crossRowConstraints.append(c)
    }
    private var planeCache: [Plane: CachedPlane] = [:]
    #if DEBUG
    static var perfFullBuilds = 0   // xé + dựng mới cả plane (đắt)
    static var perfCacheSwaps = 0   // tráo rows từ planeCache (rẻ)
    #endif

    private func rebuild() {
        guard !rebuildDeferred else { return }   // batchConfigure rebuild 1 lần cuối
        letterGeometryCache = nil
        activeAlts = currentAlts()
        updateSuggestionChrome()
        applyOneHand()                           // plane mới có thể thu hẹp / đầy bề ngang
        let styleChanged = builtReturn != returnTitle || builtDark != dark
            || builtPalette != palette
            || builtGlobe != needsGlobe || builtKind != inputKind
            || builtNumberRow != numberRowEnabled
            || builtAlts != activeAlts
        let widthChanged = builtWidth != bounds.width
        let sigChanged = styleChanged || widthChanged
        if builtPlane == plane, !sigChanged { return }
        // Chỉ bề ngang đổi (view dựng ở init với width 0, rồi viewWillAppear thấy
        // width thật — MỖI lần hiện vì iOS tạo controller mới): phím không phụ
        // thuộc width ngoài inset hàng thụt, mà layoutSubviews tự chỉnh cho plane
        // đang hiện. Khỏi xé/dựng; chỉ vứt cache các plane khác (inset cũ sai).
        // Emoji/mẫu câu không cache, dựng tự do → vẫn dựng lại như cũ.
        if builtPlane == plane, !styleChanged,
           plane != .emoji, plane != .templates, plane != .emojiSearch {
            planeCache.removeAll()
            builtWidth = bounds.width
            return
        }
        if sigChanged {
            planeCache.removeAll()
        } else if let old = builtPlane, old != .emoji, old != .templates, old != .emojiSearch {
            // KHÔNG cache emoji/templates: cả hai đổi distribution sang .fill và
            // dựng layout tự do; khôi phục từ cache (distribution đã bị reset về
            // .fillEqually + constraint chiều cao hàng đáy còn treo) làm plane
            // mẫu câu lần 2 co dúm (bug user 2026-07-25). Dựng lại rẻ.
            planeCache[old] = CachedPlane(
                rows: rowsContainer.arrangedSubviews, letterKeys: letterKeys,
                shiftKeys: shiftKeys, spaceBar: spaceBar, spaceLogo: spaceLogo, spaceCode: spaceCode,
                indentedRow: indentedRow, indentedRowInset: indentedRowInset,
                crossRow: crossRowConstraints,
                distribution: rowsContainer.distribution)
        }
        // Rời lưới emoji: nhả bảng category (lưới không cache, dựng lại lười khi mở lại).
        if builtPlane == .emoji, plane != .emoji { EmojiData.dropCaches() }
        builtPlane = plane; builtReturn = returnTitle
        builtDark = dark; builtPalette = palette; builtWidth = bounds.width
        builtGlobe = needsGlobe; builtKind = inputKind
        builtNumberRow = numberRowEnabled
        builtAlts = activeAlts
        dropAltHold()                            // phím cũ sắp bị gỡ
        commaTimer?.cancel(); commaTimer = nil; commaFired = false
        letterKeys.removeAll()
        shiftKeys = []
        crossRowConstraints = []
        rowsContainer.distribution = .fillEqually
        rowsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let cached = planeCache[plane] {
            rowsContainer.distribution = cached.distribution
            cached.rows.forEach { rowsContainer.addArrangedSubview($0) }
            letterKeys = cached.letterKeys
            shiftKeys = cached.shiftKeys
            spaceBar = cached.spaceBar
            spaceLogo = cached.spaceLogo
            spaceCode = cached.spaceCode
            refreshSpaceMark()                       // ngôn ngữ có thể đã đổi khi plane nằm cache
            indentedRow = cached.indentedRow
            indentedRowInset = cached.indentedRowInset
            crossRowConstraints = cached.crossRow
            NSLayoutConstraint.activate(crossRowConstraints)
            // shift có thể đã đổi trong lúc plane này nằm ngoài màn hình
            if plane == .letters { applyShiftAppearance() }
            #if DEBUG
            Self.perfCacheSwaps += 1
            #endif
            return
        }
        #if DEBUG
        Self.perfFullBuilds += 1
        #endif
        switch plane {
        case .letters: buildLetters()
        case .numbers where Self.isPad: buildPadSymbolic(numbers: true)
        case .symbols where Self.isPad: buildPadSymbolic(numbers: false)
        case .numbers: buildPlane(rows: [
            ["1","2","3","4","5","6","7","8","9","0"],
            // $ ở đúng chỗ bàn phím EN (user 2026-07-23); ₫ chuyển sang plane #+=
            ["-","/",":",";","(",")","$","&","@","\""],
        ], moreKey: "#+=", altKey: "ABC")
        case .symbols: buildPlane(rows: [
            ["[","]","{","}","#","%","^","*","+","="],
            // 3 currencies: EUR, CNY, VND (₫ thế chỗ JPY của layout EN)
            ["_","\\","|","~","<",">","€","¥","₫","•"],
        ], moreKey: "123", altKey: "ABC")
        case .emoji: buildEmoji()
        case .templates: buildTemplates()
        case .emojiSearch: buildEmojiSearch()
        }
    }

    /// Plane mẫu câu (burger menu): BUBBLE chips dàn dòng như tag cloud
    /// (user 2026-07-24 — đỡ tốn chỗ hơn mỗi câu một hàng), cuộn dọc, câu dài
    /// truncate "…", có label thì bubble chỉ hiện label. Hàng đáy giữ
    /// [ABC][space][return] để quay lại như plane số.
    private func buildTemplates() {
        rowsContainer.distribution = .fill
        let tools = textToolsEnabled && textToolsMode
        if !textToolsEnabled { textToolsMode = false }
        let extras: [(display: String, id: String)] = tools
            ? [(L("\u{2039} Mẫu câu"), Self.textToolsBackID)] + TextTool.allCases.map { ($0.label, $0.rawValue) }
            : (textToolsEnabled ? [(L("Aa Công cụ văn bản"), Self.textToolsEntryID)] : [])
        let chips = TemplateChipsView(items: tools ? [] : userTemplates, extras: extras,
                                      showGear: !tools, dark: dark,
                                      plainFill: plainFill,
                                      ink: palette.barInk.ui,
                                      onExtra: { [weak self] id in
            guard let self else { return }
            switch id {
            case Self.textToolsEntryID, Self.textToolsBackID:
                Self.clickModifier()
                self.textToolsMode = id == Self.textToolsEntryID
                self.rebuildUncachedPlane()
            default:
                guard let tool = TextTool(rawValue: id) else { return }
                Self.clickModifier()
                self.textToolsMode = false
                self.plane = .letters
                self.rebuild()
                self.styleBurger()
                self.onTextTool?(tool)
            }
        },
                                      onTap: { [weak self] text in
            guard let self else { return }
            Self.clickLetter()
            self.plane = .letters
            self.rebuild()
            self.styleBurger()
            self.onTemplate?(text)
        }, onGear: { [weak self] in
            Self.clickModifier()
            self?.onOpenTemplates?()   // mở tab Mẫu Câu trong app
        })
        chips.setContentHuggingPriority(.defaultLow, for: .vertical)
        chips.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        rowsContainer.addArrangedSubview(chips)       // giãn hết phần còn lại
        let bottom = bottomRow(planeKey: "ABC", clearInsteadOfEmoji: true)
        rowsContainer.addArrangedSubview(bottom)
        // Hằng số = đúng chiều cao 1 hàng phím thường; multiplier×rows từng làm
        // hàng đáy phình theo phần host cấp dư (user 2026-07-24).
        bottom.heightAnchor.constraint(equalToConstant: rowUnitHeight() - bottomTrim).isActive = true
    }

    /// Lưới bubble mẫu câu — flow layout tự dàn dòng, self-sizing chips.
    private final class TemplateChipsView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
        private let items: [(label: String, text: String)]
        /// Chip đặc biệt đứng ĐẦU lưới (công cụ văn bản) — chạm gửi id qua onExtra.
        private let extras: [(display: String, id: String)]
        private let showGear: Bool
        private let onExtra: (String) -> Void
        private let dark: Bool
        private let fill: UIColor
        private let ink: UIColor
        private let onTap: (String) -> Void
        private let onGear: () -> Void

        init(items: [(label: String, text: String)],
             extras: [(display: String, id: String)] = [], showGear: Bool = true,
             dark: Bool, plainFill: UIColor, ink: UIColor,
             onExtra: @escaping (String) -> Void = { _ in },
             onTap: @escaping (String) -> Void, onGear: @escaping () -> Void) {
            self.items = items
            self.extras = extras
            self.showGear = showGear
            self.onExtra = onExtra
            self.dark = dark
            self.fill = plainFill
            self.ink = ink
            self.onTap = onTap
            self.onGear = onGear
            super.init(frame: .zero)
            let layout = UICollectionViewFlowLayout()
            layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
            layout.minimumInteritemSpacing = 6
            layout.minimumLineSpacing = 8
            layout.sectionInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
            let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
            cv.backgroundColor = .clear
            cv.disableKeyboardEdgeEffects()
            cv.alwaysBounceVertical = true
            cv.dataSource = self
            cv.delegate = self
            cv.register(ChipCell.self, forCellWithReuseIdentifier: "chip")
            cv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(cv)
            NSLayoutConstraint.activate([
                cv.topAnchor.constraint(equalTo: topAnchor),
                cv.bottomAnchor.constraint(equalTo: bottomAnchor),
                cv.leftAnchor.constraint(equalTo: leftAnchor),
                cv.rightAnchor.constraint(equalTo: rightAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }

        // +1: bubble ⚙️ luôn ở cuối — mở tab Mẫu Câu trong app.
        func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int {
            extras.count + items.count + (showGear ? 1 : 0)
        }

        func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "chip", for: ip) as! ChipCell
            let i = ip.item - extras.count
            if ip.item < extras.count {
                cell.set(display: extras[ip.item].display, fill: fill, ink: ink, dark: dark)
                cell.accessibilityLabel = nil
            } else if i == items.count {
                cell.set(display: "⚙️", fill: fill, ink: ink, dark: dark)
                cell.accessibilityLabel = L("Quản lý mẫu câu")
            } else {
                let item = items[i]
                cell.set(display: item.label.isEmpty ? item.text : item.label,
                         fill: fill, ink: ink, dark: dark)
                cell.accessibilityLabel = nil
            }
            return cell
        }

        func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
            let i = ip.item - extras.count
            if ip.item < extras.count { onExtra(extras[ip.item].id) }
            else if i == items.count { onGear() } else { onTap(items[i].text) }
        }

        private final class ChipCell: UICollectionViewCell {
            private let label = UILabel()
            override init(frame: CGRect) {
                super.init(frame: frame)
                contentView.layer.cornerRadius = 16
                contentView.layer.shadowColor = UIColor.black.cgColor
                contentView.layer.shadowOffset = CGSize(width: 0, height: 1)
                contentView.layer.shadowRadius = 0
                label.font = .systemFont(ofSize: 16)
                label.lineBreakMode = .byTruncatingTail   // "Chào buổi s…"
                label.translatesAutoresizingMaskIntoConstraints = false
                contentView.addSubview(label)
                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
                    label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
                    label.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 12),
                    label.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -12),
                    label.widthAnchor.constraint(lessThanOrEqualToConstant: 150),
                ])
            }
            required init?(coder: NSCoder) { fatalError() }
            func set(display: String, fill: UIColor, ink: UIColor, dark: Bool) {
                label.text = display
                label.textColor = ink
                contentView.backgroundColor = fill
                contentView.layer.shadowOpacity = dark ? 0.30 : 0.35
            }
        }
    }

    private func buildLetters() {
        if UIDevice.current.userInterfaceIdiom == .pad { buildLettersPad(); return }
        let r1 = "qwertyuiop".map { String($0) }
        let r2 = "asdfghjkl".map { String($0) }
        let r3 = "zxcvbnm".map { String($0) }
        if numberRowEnabled {
            rowsContainer.addArrangedSubview(row(KeyLayout.digits.map { textButton($0) }))
        }
        let r1btns = r1.map(letterButton)
        rowsContainer.addArrangedSubview(row(r1btns))
        // Apple indents row 2 by half a key on iPhone.
        rowsContainer.addArrangedSubview(row(r2.map(letterButton), sideInset: 0.5))
        let shiftBtn = shiftButton()
        let r3btns = r3.map(letterButton)     // z x c v b n m
        let backBtn = backspaceButton()
        var third: [UIView] = [shiftBtn]
        third += r3btns
        third.append(backBtn)
        let thirdRow = row(third)
        rowsContainer.addArrangedSubview(thirdRow)
        // Như stock: khe shift↔Z và M↔⌫ RỘNG hơn khe giữa chữ (feedback 26/09/2026
        // "bên phải Shift, bên trái Xoá chưa có khoảng trắng"). Chữ hàng 3 = đúng
        // bề rộng hàng 1; shift/⌫ bằng nhau, ăn phần còn lại (~1.4 phím).
        // Khe là vùng chết với UIButton nhưng router trả về phím gần nhất.
        if let z = r3btns.first, let q = r1btns.first, let stack = thirdRow as? UIStackView {
            // Chỉ iPhone: iPad stock giữ khe đều giữa shift và chữ.
            if UIDevice.current.userInterfaceIdiom == .phone {
                stack.setCustomSpacing(Self.shiftGap, after: shiftBtn)
                if let m = r3btns.last { stack.setCustomSpacing(Self.shiftGap, after: m) }
            }
            crossRow(z.widthAnchor.constraint(equalTo: q.widthAnchor))
            shiftBtn.widthAnchor.constraint(equalTo: backBtn.widthAnchor).isActive = true
        }
        rowsContainer.addArrangedSubview(bottomRow(planeKey: "123"))
        applyRowHeights()
    }

    /// Có hàng số / iPhone (hàng đáy cắt bớt): rowsContainer thôi fillEqually — hàng số =
    /// 0.75× hàng chữ, hàng đáy = hàng chữ − bottomTrim, còn lại bằng nhau. Ràng buộc GIỮA
    /// các hàng → crossRow (sống qua planeCache). iPad không số: fillEqually như cũ.
    private func applyRowHeights() {
        let rows = rowsContainer.arrangedSubviews
        let numberRow = numberRowEnabled && rows.count == 5
        guard numberRow || !Self.isPad, rows.count >= 4 else { return }
        rowsContainer.distribution = .fill
        let ref = rows[numberRow ? 1 : 0]
        if numberRow {
            crossRow(rows[0].heightAnchor.constraint(equalTo: ref.heightAnchor,
                                                     multiplier: KeyLayout.numberRowRatio))
        }
        for r in rows[(numberRow ? 2 : 1)..<(rows.count - 1)] {
            crossRow(r.heightAnchor.constraint(equalTo: ref.heightAnchor))
        }
        let last = rows[rows.count - 1].heightAnchor.constraint(equalTo: ref.heightAnchor,
                                                               constant: -bottomTrim)
        last.identifier = Self.bottomTrimID
        crossRow(last)
    }
    private static let bottomTrimID = "vt.bottomTrim"

    /// Xoay máy không dựng lại plane đang hiện (chỉ đổi bề ngang) → chỉnh phần cắt hàng
    /// đáy + khe trên nó theo hướng mới tại chỗ.
    private func applyBottomTrim() {
        guard !Self.isPad, let c = crossRowConstraints.first(where: { $0.identifier == Self.bottomTrimID })
        else { return }
        let trim = bottomTrim
        if c.constant != -trim { c.constant = -trim }
        let top = KeyGeometry.bottomRowTopMargin(pad: false, landscape: isLandscapeNow)
        if let bottom = rowsContainer.arrangedSubviews.last as? UIStackView,
           bottom.layoutMargins.top != top {
            bottom.layoutMargins.top = top
        }
    }

    /// Kiểu bàn phím iPad như stock (KeyLayout.PadStyle): mini = compact. Theo cạnh ngắn
    /// MÀN HÌNH (không theo bề ngang view — Split View không đổi kiểu).
    private lazy var padStyle: KeyLayout.PadStyle = {
        let b = window?.windowScene?.screen.bounds ?? UIScreen.main.bounds
        return KeyLayout.padStyle(screenShortSide: min(b.width, b.height))
    }()
    /// Test: ép kiểu iPad (rồi rebuild).
    func debugSetPadStyle(compact: Bool) {
        padStyle = compact ? .compact : .full
        planeCache.removeAll(); builtPlane = nil; rebuild()
    }

    /// Layout iPad như stock iPadOS 27 (KeyLayout.padLetterRows), đơn vị = bề rộng phím q:
    ///   full:    [tab 1.3] q…p [⌫ 1.3] / [⇪ 1.67] a…l [return] / [⇧ 2.2] z…m [!,] [?.] [⇧]
    ///   compact: q…p [⌫ 1.23] / ␣ a…l [return] / [⇧] z…m [!,] [?.] [⇧ 1.23]
    ///   [🌐][.?123][☺︎][space][,][.?123][⌨︎]   (bottomRow, padLetters)
    /// Mọi phím nền trắng; full: icon/nhãn phím chức năng ở góc dưới (padCorner),
    /// compact: giữa phím (padCenter).
    private func buildLettersPad() {
        let style = padStyle
        func make(_ id: String) -> UIView? {
            switch id {
            case "caps":
                let b = controlButton(title: "") { [weak self] in
                    guard let self else { return }
                    self.shift = (self.shift == .caps) ? .off : .caps
                    self.applyShiftAppearance()
                }
                b.setImage(UIImage(systemName: "capslock"), for: .normal)
                b.accessibilityLabel = "Caps Lock"
                padFunction(b, left: true)
                capsKey = b
                return b
            case "shiftL", "shiftR":
                let b = shiftButton() as! KeyButton
                padFunction(b, left: id == "shiftL")
                return b
            case "-", "=", _ where KeyLayout.digits.contains(id): return textButton(id)
            case "!,": return padPunctButton(lower: ",", upper: "!")
            case "?.": return padPunctButton(lower: ".", upper: "?")
            default: return padCommonKey(id) ?? letterButton(id)
            }
        }
        let layoutRows = (numberRowEnabled ? [KeyLayout.padNumberRow] : []) + KeyLayout.padLetterRows(style)
        buildPadRows(layoutRows, reference: "q", make: make)
        rowsContainer.addArrangedSubview(bottomRow(planeKey: "123"))
        applyRowHeights()
    }

    /// Plane số / ký hiệu iPad đúng stock (KeyLayout.padNumberRows / padSymbolRows): cùng
    /// khung phím plane chữ; phím có ký tự phụ (padNumberHints) vuốt xuống / giữ ra ký tự đó.
    private func buildPadSymbolic(numbers: Bool) {
        let style = padStyle
        let rows = numbers ? KeyLayout.padNumberRows(style) : KeyLayout.padSymbolRows(style)
        func make(_ id: String) -> UIView? {
            switch id {
            case "more", "more2":
                let title = numbers ? "#+=" : "123"
                let b = controlButton(title: title, fire: .down) { [weak self] in
                    guard let self else { return }
                    self.plane = (self.plane == .numbers) ? .symbols : .numbers
                    self.rebuild()
                }
                b.accessibilityLabel = numbers ? L("Ký hiệu") : L("Số")
                padFunction(b, left: id == "more")
                return b
            case "undo", "redo":
                // Ô undo/redo stock: bàn phím bên thứ ba không tới được undo manager của app.
                let b = textButton(KeyLayout.padSlotTitle(id) ?? ",") as! KeyButton
                b.isSpecial = true          // bề rộng theo units, không bằng phím ký tự
                return b
            case "!,": return padPunctButton(lower: ",", upper: "!")
            case "?.": return padPunctButton(lower: ".", upper: "?")
            default:
                if let v = padCommonKey(id) { return v }
                return textButton(id, hint: numbers ? KeyLayout.padNumberHints[id] : nil)
            }
        }
        buildPadRows(rows, reference: "1", make: make)
        rowsContainer.addArrangedSubview(bottomRow(planeKey: "ABC"))
        applyRowHeights()
    }

    /// Phím chung mọi plane iPad: tab, ⌫, return, ô thụt hàng 2 (compact).
    private func padCommonKey(_ id: String) -> UIView? {
        switch id {
        case "tab":
            let b = controlButton(title: "") { [weak self] in self?.tapped(.text("\t")) }
            b.setImage(UIImage(systemName: "arrow.right.to.line"), for: .normal)
            b.accessibilityLabel = "Tab"
            padFunction(b, left: true)
            return b
        case "back":
            let b = backspaceButton() as! KeyButton
            padFunction(b, left: false)
            return b
        case "return":
            let b = returnButton()
            if returnTitle == "return" { padFunction(b, left: false) }
            return b
        case "indent":
            let v = UIView()
            v.isUserInteractionEnabled = false
            return v
        default: return nil
        }
    }

    /// Dựng các hàng iPad theo id rồi neo bề rộng units × phím `reference` (hàng neo).
    private func buildPadRows(_ layoutRows: [[KeyLayout.Key]], reference: String,
                              make: (String) -> UIView?) {
        var views: [String: UIView] = [:]
        var built: [[(KeyLayout.Key, UIView)]] = []
        for keys in layoutRows {
            let pairs = keys.compactMap { k -> (KeyLayout.Key, UIView)? in
                guard let v = make(k.id) else { return nil }
                if views[k.id] == nil { views[k.id] = v }
                return (k, v)
            }
            built.append(pairs)
            rowsContainer.addArrangedSubview(row(pairs.map(\.1)))
        }
        guard let ref = views[reference] else { return }
        for pairs in built {
            for (k, v) in pairs where v !== ref {
                guard let u = k.units else { continue }
                crossRow(v.widthAnchor.constraint(equalTo: ref.widthAnchor, multiplier: u))
            }
        }
    }

    /// Phím chức năng iPad theo kiểu: full → góc dưới (padCorner), compact → giữa phím.
    private func padFunction(_ b: KeyButton, left: Bool) {
        padCorner(b, left: left)
        if padStyle == .compact { b.padRole = .center }
    }

    /// Phím chức năng iPad kiểu stock: nền trắng như phím chữ (đè thì sẫm), icon /
    /// nhãn dạt góc dưới trái hoặc phải.
    private func padCorner(_ b: KeyButton, left: Bool) {
        b.backgroundColor = plainFill
        b.normalBackground = plainFill
        b.pressedBackground = specialFill
        // Cỡ nhãn/icon + lề góc theo hướng máy: KeyGeometry.Typography.Pad (KeyButton.padRole).
        b.padRole = .corner(left: left)
        let ink = self.ink
        b.tintColor = ink            // icon (tab/⇪/⇧/⌫/return…) đậm, không xanh/mờ
        b.setTitleColor(ink, for: .normal)
    }

    /// Ký tự phụ (xám, phía trên) của phím chữ iPad — vuốt xuống trên phím để gõ.
    static let padSecondary: [String: String] =
        Dictionary(uniqueKeysWithValues: KeyAlternates.padHints.map { (String($0.key), $0.value) })

    /// Phím dấu 2 tầng của iPad ("!" trên "," dưới, cùng cỡ như stock). Shift bật →
    /// ra ký tự trên (nhả shift một lần như phím chữ), tắt → ký tự dưới.
    private func padPunctButton(lower: String, upper: String) -> KeyButton {
        let b = baseButton(title: "", special: false)
        b.pressedBackground = specialFill
        // Hai nhãn đặt theo BASELINE quanh tâm phím như stock (Typography.Pad.punct*),
        // cỡ đổi theo hướng máy ở KeyButton.
        for text in [upper, lower] {
            let l = UILabel()
            l.text = text
            l.textColor = ink
            l.translatesAutoresizingMaskIntoConstraints = false
            l.isUserInteractionEnabled = false
            l.isAccessibilityElement = false
            b.addSubview(l)
            let base = l.firstBaselineAnchor.constraint(equalTo: b.centerYAnchor)
            NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: b.centerXAnchor), base])
            b.padPunctLabels.append((l, base))
        }
        b.padRole = .punct
        b.accessibilityLabel = lower
        armPadAlternate(b, alt: upper)          // vuốt xuống / giữ → ký tự trên như stock
        armCommit(b) { [weak self, weak b] in
            guard let self else { return }
            if b?.takePadAlt() == true {
                self.tapped(.text(upper))
            } else if self.shift != .off {
                if self.shift == .on { self.shift = .off; self.applyShiftAppearance() }
                self.tapped(.text(upper))
            } else {
                self.tapped(.text(lower))
            }
        }
        return b
    }

    // Emoji plane render theo stock (video 2026-07-24): search bar + lưới
    // cuộn ngang column-major theo category + hàng [ABC][icons][⌫].
    // rowsContainer là fillEqually — plane emoji cần layout tự do nên đổi
    // distribution sang .fill khi vào plane này (rebuild() phục hồi).
    private var emojiABCSlot: EmojiPlane.ABCSlot?

    private func buildEmoji() {
        rowsContainer.distribution = .fill
        let plane = EmojiPlane(dark: palette.surfaceDark ?? dark, abcSlot: emojiABCSlot)
        plane.onEmoji = { [weak self] e in self?.tapped(.text(e)) }
        plane.onABC = { [weak self] in
            guard let self else { return }
            self.plane = .letters
            self.reevaluateShiftForLetters()     // shift đã tắt lúc vào emoji
            self.rebuild()
        }
        plane.onBackspace = { [weak self] in self?.tapped(.backspace) }
        plane.onKaomoji = { [weak self] s in self?.onKey(.text(s)) }
        plane.onSearch = { [weak self] in
            guard let self else { return }
            self.emojiSearch.clear()
            self.shift = .off
            self.plane = .emojiSearch
            self.rebuild()
        }
        rowsContainer.addArrangedSubview(plane)
    }

    // MARK: tìm emoji (27/09/2026)
    // Hàng ô tìm + kết quả chèn lên đầu plane chữ, thế chỗ strip gợi ý; phần nó cao hơn
    // strip thì bàn phím cao thêm (KeyLayout.chrome .emojiSearch) — phím chữ giữ đủ
    // keyArea (29/09/2026: trước chia 5 hàng trong keyArea, phím bị ép). Mọi phím chữ /
    // space / ⌫ đi vào EmojiSearchSession (Telex riêng), không tới ô nhập; chạm kết
    // quả mới chèn emoji thật. return / phím emoji → về lưới emoji; 123 → plane số.
    private var emojiSearch = EmojiSearchSession()
    private weak var searchBar: EmojiSearchBar?
    private weak var searchBarHeight: NSLayoutConstraint?

    private func buildEmojiSearch() {
        let bar = EmojiSearchBar(dark: palette.surfaceDark ?? dark)
        bar.onPick = { [weak self] e in
            Self.clickLetter()
            EmojiPlane.noteUsed(e)
            self?.onKey(.text(e))
        }
        bar.onClear = { [weak self] in
            guard let self else { return }
            Self.clickModifier()
            self.emojiSearch.clear()
            self.refreshSearchBar()
        }
        searchBar = bar
        buildLetters()
        // iPad (không hàng số) dựng chữ bằng fillEqually → chuyển .fill + hàng bằng nhau,
        // để ô tìm có chiều cao RIÊNG, không chia phần với hàng chữ.
        let letterRows = rowsContainer.arrangedSubviews
        if rowsContainer.distribution != .fill, letterRows.count >= 2 {
            rowsContainer.distribution = .fill
            for r in letterRows.dropFirst() { crossRow(r.heightAnchor.constraint(equalTo: letterRows[0].heightAnchor)) }
        }
        rowsContainer.insertArrangedSubview(bar, at: 0)
        // Ô tìm cao cố định = phần bàn phím cao thêm (KeyLayout.chrome .emojiSearch) — trước
        // đây bằng một hàng chữ và CHIA keyArea với 4 hàng chữ ⇒ phím bị ép (bug 1.2.x).
        let strip = KeyLayout.stripHeight(reserved: stripReserved, collapsed: barCollapsed, open: Self.openStrip)
        let h = bar.heightAnchor.constraint(equalToConstant: KeyLayout.emojiSearchBarHeight(strip: strip))
        crossRow(h)
        searchBarHeight = h
        refreshSearchBar()
    }

    private func refreshSearchBar() {
        let q = emojiSearch.query
        let list = q.trimmingCharacters(in: .whitespaces).isEmpty
            ? EmojiPlane.recents : EmojiSearch.search(q)
        searchBar?.update(query: q, results: list)
    }

    /// Phím trong chế độ tìm: vào ô tìm thay vì ô nhập. true = đã xử lý.
    private func handleSearchKey(_ key: Key) -> Bool {
        guard plane == .emojiSearch else { return false }
        switch key {
        case .letter(let c): emojiSearch.type(c)
        case .text(let t): emojiSearch.insert(t)
        case .space, .doubleSpacePeriod: emojiSearch.space()
        case .backspace: emojiSearch.backspace()
        case .replaceLastLetter(let t): emojiSearch.backspace(); emojiSearch.insert(t)
        case .newline:
            plane = .emoji
            rebuild()
            return true
        case .moveCursor, .moveLine, .clearField: return true
        }
        refreshSearchBar()
        return true
    }

    private func buildPlane(rows planeRows: [[String]], moreKey: String, altKey: String) {
        rowsContainer.addArrangedSubview(row(planeRows[0].map { textButton($0) }))
        rowsContainer.addArrangedSubview(row(planeRows[1].map { textButton($0) }))
        let more = controlButton(title: moreKey, fire: .down) { [weak self] in
            guard let self else { return }
            self.plane = (self.plane == .numbers) ? .symbols : .numbers
            self.rebuild()
        }
        more.accessibilityLabel = moreKey == "#+=" ? L("Ký hiệu") : L("Số")
        applyLabelFont(more, size: KeyGeometry.Typography.rowToggleSize)
        var third: [UIView] = [more]
        third += [".",",","?","!","'"].map { textButton($0) }
        third.append(backspaceButton())
        rowsContainer.addArrangedSubview(row(third, proportional: true))
        rowsContainer.addArrangedSubview(bottomRow(planeKey: altKey))
        applyRowHeights()
    }

    /// Phím return theo returnKeyType của ô (xám + icon, hoặc xanh + chữ/mũi tên).
    private func returnButton() -> KeyButton {
        let ret = controlButton(title: returnTitle == "return" ? "" : returnTitle,
                                armed: true) { [weak self] in
            self?.tapped(.newline)
        }
        ret.accessibilityLabel = returnTitle == "return" ? L("Xuống dòng") : returnTitle
        if Self.isPad, returnTitle == "return" { ret.padRole = .icon }
        if returnTitle == "return" {
            ret.setImage(UIImage(systemName: "return.left",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
            // Đậm như stock iOS 26+ (trước: mờ 0.16 ngang logo Vᴛ — khó thấy).
            ret.tintColor = ink
        } else {
            // Return dạng HÀNH ĐỘNG (go/search/send/done…): nút XANH nổi bật +
            // chữ trắng như stock (Safari search…), thay vì xám lẫn phím thường.
            let accent = palette.accent.ui
            ret.backgroundColor = accent
            ret.normalBackground = accent
            ret.pressedBackground = palette.accent.alpha(0.7).ui
            ret.setTitleColor(palette.accentInk.ui, for: .normal)
            ret.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            // "go"/"search" (Safari, Gmail…): stock hiện MŨI TÊN → trắng, không chữ.
            if returnTitle == "go" || returnTitle == "search" {
                ret.setTitle("", for: .normal)
                ret.setImage(UIImage(systemName: "arrow.right",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
                ret.tintColor = palette.accentInk.ui
            }
        }
        return ret
    }

    private func bottomRow(planeKey: String, clearInsteadOfEmoji: Bool = false) -> UIView {
        var views: [UIView] = []
        let planeBtn = controlButton(title: planeKey, fire: .down) { [weak self] in
            guard let self else { return }
            // Từ ô tìm emoji: 123 ra plane số (thoát tìm).
            self.plane = (self.plane == .letters || self.plane == .emojiSearch) ? .numbers : .letters
            if self.plane == .letters { self.reevaluateShiftForLetters() }
            self.rebuild()
        }
        planeBtn.accessibilityLabel = planeKey == "123" ? L("Số") : L("Chữ")
        applyLabelFont(planeBtn, size: KeyGeometry.Typography.planeKeySize)
        views.append(planeBtn)
        // globe sát bên phải [123] như stock (muscle memory), emoji sau đó
        var globeBtn: KeyButton?
        if needsGlobe {
            let globe = baseButton(title: "", special: true)
            globe.setImage(UIImage(systemName: "globe",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
            globe.tintColor = ink
            globe.accessibilityLabel = L("Bàn phím tiếp theo")
            if Self.isPad { globe.padRole = .icon }
            if let c = inputController {
                // hợp đồng Apple: event thật + allTouchEvents để long-press
                // mở keyboard picker hoạt động
                globe.addTarget(c, action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                                for: .allTouchEvents)
            }
            views.append(globe)
            globeBtn = globe
        }
        // Slot cạnh trái space: bình thường là nút emoji; plane mẫu câu thay
        // bằng THÙNG RÁC = xoá sạch ô nhập (user 2026-07-25). Cùng kiểu nút đơn
        // sắc như ABC nên giữ chung biến emojiBtn để ăn width multiplier 0.10.
        let emojiBtn: KeyButton
        if clearInsteadOfEmoji {
            emojiBtn = controlButton(title: "") { [weak self] in
                self?.tapped(.clearField)
            }
            emojiBtn.setImage(UIImage(systemName: "trash",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
            emojiBtn.tintColor = ink
            emojiBtn.accessibilityLabel = L("Xoá ô nhập")
        } else {
            // Nhấc tay như stock; touch bị hệ thống huỷ (sát vùng 🌐/mic) vẫn mở emoji.
            emojiBtn = controlButton(title: "", fire: .upOrCancel) { [weak self] in
                guard let self else { return }
                self.plane = .emoji
                self.rebuild()
            }
            emojiBtn.setImage(Self.emojiKeyIcon, for: .normal)
            // Nhớ chỗ phím emoji (touchDown chạy trước action đổi plane) → EmojiPlane
            // đặt ABC đúng chỗ đó (Phil 26/09, chốt lại 30/09/2026).
            emojiBtn.addAction(UIAction { [weak self] a in
                guard let self, let v = a.sender as? UIView else { return }
                let r = self.convert(v.bounds, from: v)
                self.emojiABCSlot = .init(minX: r.minX, maxX: r.maxX,
                                          top: self.rowsContainer.frame.maxY - r.minY)
            }, for: .touchDown)
            emojiBtn.tintColor = ink
            emojiBtn.accessibilityLabel = "Emoji"
        }
        views.append(emojiBtn)
        let space = baseButton(title: "", special: true)
        space.backgroundColor = plainFill
        space.normalBackground = plainFill
        space.pressedBackground = specialFill      // space sẫm lại khi đè
        space.accessibilityLabel = L("Dấu cách")
        spaceBar = space
        installSpaceMark(on: space)
        space.addAction(UIAction { _ in Self.clickModifier() }, for: .touchDown)
        space.addTarget(self, action: #selector(spaceTouchDown(_:event:)), for: .touchDown)
        // Vuốt đổi ngôn ngữ (SpaceFlick): theo dõi ngón — công tắc tắt ⇒ handler thoát ngay.
        space.addTarget(self, action: #selector(spaceDrag(_:event:)),
                        for: [.touchDragInside, .touchDragOutside, .touchUpInside, .touchUpOutside])
        // Chốt qua KeyCommitQueue: arm lúc chạm, chốt lúc nhấc / bị huỷ / khi ngón
        // khác chạm xuống trước (gõ chồng ngón). touchUpOutside CŨNG chốt: ngón trượt
        // khỏi mép lúc nhấc là chuyện thường. Trackpad (spaceHold) disarm.
        armCommit(space) { [weak self] in
            guard let self else { return }
            if self.consumeSpaceFlick() { return }    // flick đổi ngôn ngữ: không ra dấu cách
            let now = CACurrentMediaTime()
            if now - self.lastSpaceTap < 0.35 {
                self.tapped(.doubleSpacePeriod)
            } else {
                self.tapped(.space)
            }
            self.lastSpaceTap = now
            if PlanePolicy.returnToLettersOnSpace(
                inSymbolPlane: self.plane == .numbers || self.plane == .symbols,
                typedInPlane: self.typedInSymbolPlane,
                numericField: self.inputKind == .number) {
                self.plane = .letters
                self.rebuild()
            }
        }
        let spacePan = UILongPressGestureRecognizer(target: self, action: #selector(spaceHold(_:)))
        spacePan.minimumPressDuration = 0.3   // 0.4 → 0.3: vào trackpad nhanh hơn (cảm giác stock)
        // KHÔNG delay/cancel touch của phím khác: recognizer mặc định trì hoãn
        // touchesEnded ~0.15s và cancel touch khi nhận diện — nguồn rớt/khựng
        // phím kề khi gõ nhanh. Chỉ theo dõi touch bắt đầu TRÊN space.
        spacePan.delaysTouchesBegan = false
        spacePan.delaysTouchesEnded = false
        spacePan.cancelsTouchesInView = false
        space.addGestureRecognizer(spacePan)
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        views.append(space)
        // Nhóm phím dấu câu bên phải space. Bình thường là dấu phẩy; ô email/url
        // đổi thành phím tắt như stock (@ . cho email; . / cho url). Chỉ áp
        // ở hàng đáy plane CHỮ (planeKey == "123").
        // iPad plane chữ / số / ký hiệu: hàng đáy kiểu stock (KeyLayout.padBottomRow).
        let padLetters = Self.isPad && planeKey == "123"
        let padSym = Self.isPad && !padLetters && !clearInsteadOfEmoji
            && (plane == .numbers || plane == .symbols)
        let padStock = padLetters || padSym
        let puncts: [(title: String, insert: String, mult: CGFloat)]
        if padSym {
            // compact: ô undo/redo stock bên phải space (",", "₫"); full: không có phím.
            let t = KeyLayout.padSlotTitle(plane == .numbers ? "undo" : "redo") ?? ","
            puncts = padStyle == .compact ? [(t, t, KeyLayout.units("slot", in:
                KeyLayout.padBottomRow(.compact, letters: false)) ?? 0.079)] : []
        } else if planeKey == "123" {
            switch inputKind {
            case .email: puncts = [("@", "@", 0.11), (".", ".", 0.09)]
            // Ô URL (issue #113): không phím ".com" riêng — space rộng như stock; đuôi tên
            // miền (.com .vn .com.vn …) ở giữ "." (DomainPopup). Giữ "/".
            case .url:   puncts = [(".", ".", 0.075), ("/", "/", 0.075)]
            // Thanh địa chỉ: stock hiện "." thay "," (gõ tên miền); iPad đã có ".?" riêng.
            case .search: puncts = padLetters ? [] : [(".", ".", 0.075)]
            // iPad plane chữ: không phím "," riêng như stock ("!," hàng 3 đã có).
            default:     puncts = padLetters ? [] : [(",", ",", 0.075)]
            }
        } else {
            puncts = [(",", ",", 0.075)]
        }
        var punctKeys: [(btn: KeyButton, mult: CGFloat)] = []
        for p in puncts {
            let b = baseButton(title: p.title, special: false)
            b.pressedBackground = specialFill
            if Self.isPad { b.padRole = .digit }
            armCommit(b) { [weak self] in self?.tapped(.text(p.insert)) }
            // Bàn chữ iPhone: giữ "," ra "." (KeyAlternates.commaHold — bảng ký tự phụ không
            // rỗng; VoiceOver đã rỗng sẵn; iPad có phím ",/." 2 tầng riêng).
            if !Self.isPad, p.title == ",", planeKey == "123", KeyAlternates.commaHold(alternates: activeAlts) {
                armCommaHold(b)
            }
            // Ô địa chỉ / URL / email: giữ "." ra hàng đuôi tên miền như stock (DomainPopup).
            let tlds = DomainPopup.choices(kind: inputKind, key: p.title, lettersPlane: planeKey == "123")
            if !tlds.isEmpty { armDomainHold(b, choices: tlds) }
            views.append(b)
            punctKeys.append((b, p.mult))
        }
        // iPad: return nằm cuối hàng 2 như stock (buildLettersPad / buildPadSymbolic).
        var ret: KeyButton?
        if !padStock {
            let r = returnButton()
            views.append(r)
            ret = r
        }
        // iPad: 🌐 lên đầu hàng như stock ([🌐][.?123|ABC][☺︎]…) — cả plane số/ký hiệu.
        if padStock, let g = globeBtn, let gi = views.firstIndex(where: { $0 === g }) {
            views.remove(at: gi)
            views.insert(g, at: 0)
        }
        // iPad: phím 123 / ABC thứ hai bên phải space như stock.
        var planeBtn2: KeyButton?
        if padStock {
            let b = controlButton(title: planeKey, fire: .down) { [weak self] in
                guard let self else { return }
                self.plane = padLetters ? .numbers : .letters
                if self.plane == .letters { self.reevaluateShiftForLetters() }
                self.rebuild()
            }
            b.accessibilityLabel = padLetters ? L("Số") : L("Chữ")
            views.append(b)
            planeBtn2 = b
        }
        // iPad: phím ẩn bàn phím góc phải dưới như stock
        var dismissBtn: KeyButton?
        if UIDevice.current.userInterfaceIdiom == .pad {
            let d = baseButton(title: "", special: true)
            d.setImage(UIImage(systemName: "keyboard.chevron.compact.down",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
            d.tintColor = ink
            d.accessibilityLabel = L("Ẩn bàn phím")
            d.padRole = .icon
            d.addAction(UIAction { _ in Self.clickModifier() }, for: .touchDown)
            d.addAction(UIAction { [weak self] _ in
                self?.inputController?.dismissKeyboard()
            }, for: .touchUpInside)
            dismissBtn = d
            views.append(d)
        }

        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .horizontal
        stack.spacing = Self.keyGap
        stack.distribution = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        // Hàng đáy SÁT đáy hơn như stock (so ảnh 25/09/2026: stock cách đáy bàn phím
        // 214px, VietTelex 241px): cùng chiều cao phím, dời xuống 3pt (top 8/bottom 2
        // thay 5/5). Vùng globe/mic dưới đó do host vẽ — không dời được.
        // Phím phẳng không bóng như stock (26/09/2026) → hàng đáy sát đáy 0pt.
        // iPhone dọc: vùng 50 = khe 7 + phím 43 như stock (27/09: phím đáy 44 trông cao
        // hơn stock) — applyBottomTrim chỉnh lại khi xoay.
        // iPad: safe area đáy của view (≈5pt) từng lọt vào layoutMargins → phím hàng đáy thấp
        // hơn 3 hàng trên 5pt (45 thay 50, ngang 60 thay 65) và icon/nhãn sát đáy (đo 27/09).
        if Self.isPad { stack.insetsLayoutMarginsFromSafeArea = false }
        let bottomTop = KeyGeometry.bottomRowTopMargin(pad: Self.isPad, landscape: isLandscapeNow)
        stack.layoutMargins = UIEdgeInsets(top: bottomTop, left: Self.sideMargin,
                                           bottom: 0, right: Self.sideMargin)
        // Tỉ lệ từ KeyLayout (test: đúng một phím co giãn = space).
        let spec = padStock ? KeyLayout.padBottomRow(padStyle, letters: padLetters) : KeyLayout.phoneBottom
        func frac(_ id: String) -> CGFloat { KeyLayout.units(id, in: spec) ?? 0.1 }
        planeBtn.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: frac("plane")).isActive = true
        emojiBtn.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: frac("emoji")).isActive = true
        // Globe PHẢI có width cố định: thiếu thì nó và space cùng "tự do", stack
        // bóp globe còn bề ngang icon và chia lại mỗi lần phím đổi trạng thái —
        // hàng đáy iPad nhảy size khi bấm (feedback 26/09/2026). Chỉ space co giãn.
        globeBtn?.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: frac("globe")).isActive = true
        for pk in punctKeys {
            // iPhone plane chữ: "," hẹp hơn stock (KeyLayout.phoneLettersComma), phần dư cho
            // space — chạm space hay lẹm sang "," (Phil 06/10/2026; thêm KeyHitBias).
            let lettersComma = !padStock && planeKey == "123" && !clearInsteadOfEmoji
            let m = pk.btn.currentTitle != "," ? pk.mult
                : lettersComma ? KeyLayout.phoneLettersComma : (KeyLayout.units("comma", in: spec) ?? pk.mult)
            pk.btn.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: m).isActive = true
        }
        ret?.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: frac("return")).isActive = true
        planeBtn2?.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: frac("plane2")).isActive = true
        dismissBtn?.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                           multiplier: padStock ? frac("dismiss") : 0.07).isActive = true
        if padStock {
            // Stock: plane chữ full ".?123", compact (mini) "123"; plane số/ký hiệu "ABC".
            let t = padLetters ? (padStyle == .compact ? "123" : ".?123") : planeKey
            planeBtn.setTitle(t, for: .normal)
            planeBtn2?.setTitle(t, for: .normal)
            padFunction(planeBtn, left: true)
            if let b = planeBtn2 { padFunction(b, left: false) }   // nhãn phải dạt phải như stock
            if let g = globeBtn { padFunction(g, left: true) }
            padFunction(emojiBtn, left: true)
            if let d = dismissBtn { padFunction(d, left: false) }
            for pk in punctKeys { pk.btn.backgroundColor = plainFill; pk.btn.normalBackground = plainFill }
        }
        return stack
    }

    /// `.fill` + width constraint tường minh (mọi phím chữ bằng nhau, shift/⌫
    /// hàng 3 = 1.5 phím — đặt ở buildLetters): hình học KHÔNG phụ thuộc cỡ
    /// title. `.fillProportionally` đo intrinsic size của title → mỗi lần shift
    /// retitle 26 phím là stack tính lại tỉ lệ và relayout cả bàn phím.
    /// `proportional` chỉ cho hàng 3 plane số/ký hiệu (#+= … ⌫): hàng đó không bao
    /// giờ retitle, giữ nguyên hình học cũ.
    private func row(_ views: [UIView], sideInset: CGFloat = 0,
                     proportional: Bool = false) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .horizontal
        stack.spacing = Self.keyGap
        stack.distribution = proportional ? .fillProportionally : .fill
        stack.isLayoutMarginsRelativeArrangement = true
        if Self.isPad { stack.insetsLayoutMarginsFromSafeArea = false }   // xem bottomRow
        // bounds.width có thể = 0 lúc init — layoutSubviews chỉnh lại ngay
        // pass đầu (và sau mỗi lần xoay / đổi cỡ Split View)
        // 10/0 thay 5/5 (khe giữa hàng vẫn 10): hàng đáy sát đáy (26/09/2026).
        let side = KeyGeometry.indentedMargin(width: keysWidth, margin: Self.sideMargin,
                                              gap: Self.keyGap, units: sideInset)
        stack.layoutMargins = UIEdgeInsets(top: KeyGeometry.rowGap, left: side,
                                           bottom: 0, right: side)
        if sideInset > 0 { indentedRow = stack; indentedRowInset = sideInset }
        // equal widths for plain letter keys
        let letters = views.filter { ($0 as? KeyButton)?.isSpecial == false }
        if let first = letters.first {
            for v in letters.dropFirst() {
                v.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
            }
        }
        return stack
    }

    // MARK: buttons

    private final class KeyButton: UIButton {
        var isSpecial = false
        var payload: String?    // suggestion slot: nội dung sẽ chèn khi bấm
        var downPayload: String? // payload chốt lúc chạm xuống (slot gợi ý)
        var normalBackground: UIColor?
        var pressedBackground: UIColor?   // nil = không đổi màu khi đè (phím chữ dùng balloon)
        /// Hit-area tuỳ biến (âm = nở rộng). Slot trên bar 20pt cần nở XUỐNG
        /// 16pt phủ hết strip 36 — tâm ngón tay hay rơi dưới đáy bar là vùng
        /// chết, nguồn của "chevron/burger bấm mãi không ăn".
        var hitInsets: UIEdgeInsets?
        /// Nhãn chữ đặt theo baseline stock (KeyGeometry.Typography) thay vì căn giữa hộp dòng.
        var baselineAligned = false
        override func titleRect(forContentRect contentRect: CGRect) -> CGRect {
            let r = super.titleRect(forContentRect: contentRect)
            guard baselineAligned, let f = titleLabel?.font, bounds.height > 0 else { return r }
            // Hộp nhãn đang căn giữa phím; dời để baseline về đúng chỗ stock.
            let dy: CGFloat
            if let below = padBaselineBelowCenter {
                let m = KeyGeometry.Typography.Pad.metrics(landscape: Self.padLandscape)
                dy = KeyGeometry.Typography.offsetY(toBaseline: bounds.height / 2 + m.scaled(below, keyHeight: bounds.height),
                                                    keyHeight: bounds.height,
                                                    ascender: f.ascender, descender: f.descender)
            } else {
                dy = KeyGeometry.Typography.titleOffsetY(keyHeight: bounds.height,
                                                         ascender: f.ascender, descender: f.descender)
            }
            return r.offsetBy(dx: 0, dy: (bounds.midY - r.midY) + dy)
        }

        // MARK: iPad — chữ theo KeyGeometry.Typography.Pad, đổi theo hướng máy TẠI CHỖ
        // (xoay không dựng lại plane): KeyboardView đặt `padLandscape` đầu mỗi layout pass,
        // mỗi phím tự áp lại ở layoutSubviews của nó khi hướng khác lần áp trước.
        /// `center`: kiểu compact (iPad mini) — icon/nhãn giữa phím như stock.
        enum PadRole { case letter, digit, corner(left: Bool), icon, punct, center }
        static var padLandscape = false
        var padRole: PadRole? { didSet { padApplied = nil; setNeedsLayout() } }
        /// (hướng máy, chiều cao phím) lần áp trước — số đo quanh tâm co theo chiều cao.
        private var padApplied: (landscape: Bool, height: CGFloat)?
        private var padBaselineBelowCenter: CGFloat?
        weak var padHint: UILabel?
        var padHintBaseline: NSLayoutConstraint?
        /// Ký tự phụ iPad của phím thường (plane số, phím 2 tầng) — armPadAlternate.
        var padAlt: String?
        var padAltChosen = false
        var padAltStart: CGPoint?
        var padAltTimer: DispatchWorkItem?
        var onPadAltChoose: (() -> Void)?
        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            if padAlt != nil { padAltStart = touch.location(in: self) }
            return super.beginTracking(touch, with: event)
        }
        /// Vuốt XUỐNG quá ngưỡng → ký tự phụ; trôi ngang/lên quá slop → huỷ hẹn giờ giữ.
        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            if padAlt != nil, !padAltChosen, let s = padAltStart {
                let p = touch.location(in: self)
                if KeyLayout.isPadFlick(dx: p.x - s.x, dy: p.y - s.y, threshold: KeyboardView.flickDistance) {
                    onPadAltChoose?()
                } else if hypot(p.x - s.x, p.y - s.y) > KeyAlternates.slop {
                    padAltTimer?.cancel(); padAltTimer = nil
                }
            }
            return super.continueTracking(touch, with: event)
        }
        /// Đọc + xoá lựa chọn ký tự phụ lúc phím chốt (lần chạm sau bắt đầu sạch).
        func takePadAlt() -> Bool { defer { padAltChosen = false }; return padAltChosen }
        var padPunctLabels: [(label: UILabel, baseline: NSLayoutConstraint)] = []

        override func layoutSubviews() {
            applyPadTypographyIfNeeded()
            super.layoutSubviews()
        }
        /// Icon SF Symbol cỡ stock iPad (kể cả ảnh đặt lại sau: shift/caps đổi trạng thái).
        private func applyPadSymbolSize(_ m: KeyGeometry.Typography.Pad.Metrics) {
            let c = UIImage.SymbolConfiguration(pointSize: m.iconPointSize, weight: .regular)
            setPreferredSymbolConfiguration(c, forImageIn: .normal)
            setPreferredSymbolConfiguration(c, forImageIn: .highlighted)
            // Ảnh dựng sẵn cỡ riêng (return/🌐/⌨︎ pointSize 17) không nhận preferred config
            // → thay config của chính ảnh.
            for st in [UIControl.State.normal, .highlighted] {
                if let img = image(for: st), img.isSymbolImage,
                   img.symbolConfiguration?.isEqual(to: c) != true {
                    setImage(img.withConfiguration(c), for: st)
                }
            }
        }
        private func applyPadTypographyIfNeeded() {
            guard let role = padRole else { return }
            let land = Self.padLandscape, h = bounds.height
            if let a = padApplied, a.landscape == land, a.height == h { return }
            padApplied = (land, h)
            let m = KeyGeometry.Typography.Pad.metrics(landscape: land)
            switch role {
            case .letter, .digit:
                if case .letter = role { titleLabel?.font = KeyboardView.keyFont(m.letterSize) }
                else { titleLabel?.font = KeyboardView.keyFont(m.digitSize) }
                contentVerticalAlignment = .center
                contentEdgeInsets = .zero
                baselineAligned = true
                if case .letter = role {
                    padBaselineBelowCenter = m.letterBaselineBelowCenter
                    padHint?.font = KeyboardView.keyFont(m.hintSize)
                    padHintBaseline?.constant = -m.scaled(m.hintBaselineAboveCenter, keyHeight: h)
                } else {
                    padBaselineBelowCenter = m.digitBaselineBelowCenter
                }
            case .corner(let left):
                contentHorizontalAlignment = left ? .left : .right
                contentVerticalAlignment = .bottom
                if let t = currentTitle, !t.isEmpty {
                    let f = KeyboardView.keyFont(m.labelSize)
                    titleLabel?.font = f
                    titleLabel?.adjustsFontSizeToFitWidth = true
                    titleLabel?.minimumScaleFactor = 0.7
                    // Đáy hộp nhãn = baseline + descender (descender < 0).
                    let bottom = max(m.labelBaselineAboveBottom + f.descender, 0)
                    contentEdgeInsets = UIEdgeInsets(top: 0, left: m.labelSideInset,
                                                     bottom: bottom, right: m.labelSideInset)
                } else {
                    // Ảnh vẽ tay (☺︎) không có lề trong như SF Symbol → dùng thẳng số đo mép nét.
                    let sym = currentImage?.isSymbolImage ?? true
                    let ins = sym ? KeyGeometry.Typography.Pad.iconContentInsets(m)
                                  : (side: m.iconSideInset, bottom: m.iconBottomInset)
                    contentEdgeInsets = UIEdgeInsets(top: 0, left: ins.side, bottom: ins.bottom, right: ins.side)
                }
                applyPadSymbolSize(m)
            case .icon:
                applyPadSymbolSize(m)
            case .center:
                contentHorizontalAlignment = .center
                contentVerticalAlignment = .center
                contentEdgeInsets = .zero
                if let t = currentTitle, !t.isEmpty {
                    let size = t == "#+=" ? m.centerToggleLabelSize : m.centerLabelSize
                    titleLabel?.font = KeyboardView.keyFont(size)
                    titleLabel?.adjustsFontSizeToFitWidth = true
                    titleLabel?.minimumScaleFactor = 0.6
                }
                var c = m
                c.iconPointSize = m.centerIconPointSize
                applyPadSymbolSize(c)
            case .punct:
                let f = KeyboardView.keyFont(m.punctSize)
                for (i, p) in padPunctLabels.enumerated() {
                    p.label.font = f
                    let v = i == 0 ? m.punctUpperBaselineBelowCenter : m.punctLowerBaselineBelowCenter
                    p.baseline.constant = m.scaled(v, keyHeight: h)
                }
            }
        }
        // Khe hở giữa phím (spacing 6 + padding hàng 5) là VÙNG CHẾT với
        // UIButton thường — chạm trúng khe = mất phím. Stock keyboard route
        // mọi điểm chạm về phím gần nhất; mở rộng hit area phủ nửa khe cho
        // hiệu quả tương đương, không đổi kiến trúc touch.
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if let i = hitInsets { return bounds.inset(by: i).contains(point) }
            return bounds.insetBy(dx: -3, dy: -5.5).contains(point)
        }
    }

    /// Icon phím emoji vẽ tay giống stock iOS (không SF Symbol nào khớp): mặt
    /// cười viền tròn, mắt tròn, miệng mở với dải răng cong theo môi trên.
    /// Template → tintColor tô theo sáng/tối.
    private static let emojiKeyIcon: UIImage = {
        let d: CGFloat = 21, lw: CGFloat = 1.7
        let img = UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { ctx in
            let c = ctx.cgContext
            UIColor.black.set()
            c.setLineWidth(lw)
            c.strokeEllipse(in: CGRect(x: lw / 2, y: lw / 2, width: d - lw, height: d - lw))
            let er: CGFloat = 1.2
            c.fillEllipse(in: CGRect(x: 7.4 - er, y: 8 - er, width: 2 * er, height: 2 * er))
            c.fillEllipse(in: CGRect(x: 13.6 - er, y: 8 - er, width: 2 * er, height: 2 * er))
            // Miệng: môi trên cong nhẹ, môi dưới cong sâu.
            let l = CGPoint(x: 4.3, y: 12.3), r = CGPoint(x: 16.7, y: 12.3)
            let mouth = CGMutablePath()
            mouth.move(to: l)
            mouth.addQuadCurve(to: r, control: CGPoint(x: 10.5, y: 14.9))
            mouth.addCurve(to: l, control1: CGPoint(x: 16.2, y: 19.6),
                           control2: CGPoint(x: 4.8, y: 19.6))
            mouth.closeSubpath()
            c.addPath(mouth); c.fillPath()
            // Răng: đục rỗng dải song song môi trên, rồi vẽ lại viền miệng để
            // dải không phá mép.
            c.saveGState()
            c.addPath(mouth); c.clip()
            c.setBlendMode(.clear)
            let band = CGMutablePath()
            band.move(to: CGPoint(x: 3, y: 12.7))
            band.addQuadCurve(to: CGPoint(x: 18, y: 12.7), control: CGPoint(x: 10.5, y: 15.3))
            band.addLine(to: CGPoint(x: 18, y: 14.7))
            band.addQuadCurve(to: CGPoint(x: 3, y: 14.7), control: CGPoint(x: 10.5, y: 17.3))
            band.closeSubpath()
            c.addPath(band); c.fillPath()
            c.setBlendMode(.normal)
            c.setLineWidth(1.3)
            c.addPath(mouth); c.strokePath()
            c.restoreGState()
        }
        return img.withRenderingMode(.alwaysTemplate)
    }()

    private func baseButton(title: String, special: Bool) -> KeyButton {
        // .custom, not .system: system buttons run tint/highlight animations on
        // the main thread per touch — visible latency on a keyboard.
        let b = KeyButton(type: .custom)
        // ĐẦU TIÊN trong mọi touchDown (kể cả phím chữ qua router sendActions): chốt
        // các phím nhấc-mới-chốt đang đè TRƯỚC khi phím này làm gì — đúng thứ tự
        // khi gõ chồng ngón (KeyCommitQueue).
        b.addAction(UIAction { [weak self, weak b] _ in
            self?.settleAltHold()                 // ký tự phụ đang giữ chốt TRƯỚC phím mới
            self?.commits.flush(except: b.map(ObjectIdentifier.init))
        }, for: .touchDown)
        b.isMultipleTouchEnabled = true
        b.isSpecial = special
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: special ? 16 : 23)
        if !special { applyKeycapFont(b, title: title) }
        b.layer.cornerRadius = Self.keyRadius
        if let border = palette.keyBorder {
            b.layer.borderWidth = 1
            b.layer.borderColor = border.ui.cgColor
        }
        b.setTitleColor(ink, for: .normal)
        // iOS 26+: MỌI phím cùng nền (phím chức năng không còn xám) — 26/09/2026.
        b.backgroundColor = plainFill
        b.normalBackground = b.backgroundColor
        // Pressed state cho phím chức năng: swap màu phẳng, KHÔNG
        // UIView.animate — animation per-touch trên main thread là latency
        // thấy được trên bàn phím (lý do dùng .custom ở trên). Đè = sẫm lại.
        if special { b.pressedBackground = specialFill }
        b.addAction(UIAction { [weak b] _ in
            if let c = b?.pressedBackground { b?.backgroundColor = c }
        }, for: .touchDown)
        b.addAction(UIAction { [weak b] _ in
            if b?.pressedBackground != nil, let c = b?.normalBackground { b?.backgroundColor = c }
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return b
    }

    // Âm click phát ở TOUCH-DOWN như stock (nguồn cảm giác "nhanh").
    // playInputClick tôn trọng Settings→Sounds→Keyboard Clicks (AudioServices
    // trước đây bỏ qua setting); mất phân biệt 3 tông — chấp nhận.
    // Rung: iOS vô hiệu UIFeedbackGenerator trong keyboard extension khi
    // không có Full Access — controller chỉ bật cờ khi setting ON + hasFullAccess.
    nonisolated(unsafe) static var hapticsEnabled = false
    /// "Âm thanh phím" (setting keySound + Full Access): BẬT ⇒ tiếng riêng qua KeySound,
    /// KHÔNG kèm playInputClick (không kêu đôi). TẮT ⇒ y như cũ (click hệ thống).
    nonisolated(unsafe) static var customSoundEnabled = false
    #if DEBUG
    /// Test hook: đường âm lần bấm gần nhất — "system" | "custom:<loại>".
    nonisolated(unsafe) static var debugLastClickRoute: String?
    #endif
    private static func feedback(_ kind: KeySoundKind) {
        if customSoundEnabled {
            KeySound.shared.play(kind)
            #if DEBUG
            debugLastClickRoute = "custom:\(kind)"
            #endif
        } else {
            UIDevice.current.playInputClick()
            #if DEBUG
            debugLastClickRoute = "system"
            #endif
        }
        if hapticsEnabled { impact() }
    }
    /// Rung một nhịp (Core Haptics, độ mạnh theo cài đặt). UIImpactFeedbackGenerator IM LẶNG trong keyboard extension trên
    /// iOS 27 dù đủ setting + Full Access (đo trên iPhone Phil 28/09/2026: App Group có
    /// hapticFeedback=1, kbFullAccess=1 mà không rung) — extension không phải app
    /// "active" nên UIKit bỏ qua. Dùng system sound 1519 (Peek, Taptic nhẹ) — không
    /// phụ thuộc trạng thái app, không phát tiếng.
    private static func impact() {
        if KeyHaptics.shared.play() { return }
        AudioServicesPlaySystemSound(1519)   // dự phòng: Core Haptics không chạy được
    }
    static func clickLetter() { feedback(.letter) }
    static func clickDelete() { feedback(.delete) }
    static func clickModifier() { feedback(.modifier) }
    /// Nấc vuốt ⌫ thêm/bớt một từ: chỉ âm (không rung), theo đường âm đang chọn.
    static func clickWordStep() {
        if customSoundEnabled { KeySound.shared.play(.delete) } else { UIDevice.current.playInputClick() }
    }
    /// Đổi ngôn ngữ bằng vuốt phím cách: chỉ rung nhẹ (theo công tắc Rung phím).
    static func flickFeedback() {
        guard hapticsEnabled else { return }
        impact()
    }

    private func letterButton(_ s: String) -> UIView {
        let title = (shift == .off) ? s : s.uppercased()
        let b = baseButton(title: title, special: false)
        // Touch của phím CHỮ do router (touchesBegan/Ended của KeyboardView)
        // điều phối — nearest-key, không thể miss. Button chỉ còn là visual +
        // hộp action được sendActions() kích.
        b.isUserInteractionEnabled = false
        letterKeys.append((b, s))
        if Self.isPad {
            // Chữ + ký tự phụ căn theo tâm phím như stock (KeyGeometry.Typography.Pad).
            if let sec = Self.padSecondary[s] { addPadHint(sec, to: b) }
            b.padRole = .letter
        } else if let c = s.first, let alt = activeAlts[c] {
            // Nhãn ký tự phụ nhỏ, mờ ở góc trên-phải như Gboard — dựng một lần theo layout.
            let l = UILabel()
            l.text = alt
            l.font = .systemFont(ofSize: 10, weight: .medium)
            l.textColor = inkFaded(0.45)
            l.translatesAutoresizingMaskIntoConstraints = false
            l.isUserInteractionEnabled = false
            l.isAccessibilityElement = false
            b.addSubview(l)
            NSLayoutConstraint.activate([
                l.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -3),
                l.topAnchor.constraint(equalTo: b.topAnchor, constant: 2),
            ])
        }
        // Chèn NGAY touch-down như stock iOS: chữ lên tức thì, không phụ thuộc
        // vào việc giao touch-up (main thread bận → touch-up trễ → "phím không
        // ăn"). Rollover vẫn đúng vì mỗi down tự chèn ký tự của nó.
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            Self.clickLetter()                       // feedback tức thì
            self.showBalloon(over: b, text: b.currentTitle ?? title)
            self.shiftBeforeLastLetter = self.shift
            let cased: Character = (self.shift == .off) ? Character(s) : Character(s.uppercased())
            self.tapped(.letter(cased))
            if self.shift == .on { self.shift = .off; self.applyShiftAppearance() }
        }, for: .touchDown)
        b.addAction(UIAction { [weak self] _ in
            self?.hideBalloon()
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return b
    }

    // MARK: key preview balloon — callout bezier LIỀN KHỐI với phím như stock:
    // bubble loe rộng phía trên, cổ cong ôm xuống trọn footprint phím.
    // (Hàng trên cùng vẫn bị kẹp trong bounds extension — giới hạn đã biết,
    // docs/ios-app.md; bar gợi ý bật thì có 30pt headroom.)
    private final class BalloonView: UIView {
        let label = UILabel()
        private let shape = CAShapeLayer()
        private var pathKey = ""
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            layer.zPosition = 10
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 2
            layer.shadowOpacity = 0.3
            layer.addSublayer(shape)
            label.font = .systemFont(ofSize: 34)
            label.textAlignment = .center
            addSubview(label)
        }
        required init?(coder: NSCoder) { fatalError() }

        /// keyRect trong toạ độ superview. Path cache theo hình dạng — gõ cùng
        /// một hàng phím thì không dựng lại path (không alloc trên hot path).
        func present(keyRect: CGRect, text: String, fill: UIColor, ink: UIColor, topLimit: CGFloat) {
            let bubbleW = max(keyRect.width + 24, 52)
            let top = max(keyRect.minY - 52, topLimit)
            frame = CGRect(x: keyRect.midX - bubbleW / 2, y: top,
                           width: bubbleW, height: keyRect.maxY - top)
            let kx0 = keyRect.minX - frame.minX, kx1 = keyRect.maxX - frame.minX
            let bubbleH = max(keyRect.minY - top - 6, 22)
            let H = frame.height
            let key = "\(bubbleW)|\(kx0)|\(H)|\(bubbleH)"
            if key != pathKey {
                pathKey = key
                let r: CGFloat = 9, kr: CGFloat = KeyboardView.keyRadius, neckY = min(bubbleH + 12, H)
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 0, y: bubbleH))
                p.addLine(to: CGPoint(x: 0, y: r))
                p.addQuadCurve(to: CGPoint(x: r, y: 0), controlPoint: .zero)
                p.addLine(to: CGPoint(x: bubbleW - r, y: 0))
                p.addQuadCurve(to: CGPoint(x: bubbleW, y: r),
                               controlPoint: CGPoint(x: bubbleW, y: 0))
                p.addLine(to: CGPoint(x: bubbleW, y: bubbleH))
                // cổ phải: S-curve từ mép bubble vào mép phím
                p.addCurve(to: CGPoint(x: kx1, y: neckY),
                           controlPoint1: CGPoint(x: bubbleW, y: bubbleH + 7),
                           controlPoint2: CGPoint(x: kx1, y: bubbleH + 5))
                p.addLine(to: CGPoint(x: kx1, y: H - kr))
                p.addQuadCurve(to: CGPoint(x: kx1 - kr, y: H),
                               controlPoint: CGPoint(x: kx1, y: H))
                p.addLine(to: CGPoint(x: kx0 + kr, y: H))
                p.addQuadCurve(to: CGPoint(x: kx0, y: H - kr),
                               controlPoint: CGPoint(x: kx0, y: H))
                p.addLine(to: CGPoint(x: kx0, y: neckY))
                // cổ trái
                p.addCurve(to: CGPoint(x: 0, y: bubbleH),
                           controlPoint1: CGPoint(x: kx0, y: bubbleH + 5),
                           controlPoint2: CGPoint(x: 0, y: bubbleH + 7))
                p.close()
                shape.path = p.cgPath
                layer.shadowPath = p.cgPath
                label.frame = CGRect(x: 0, y: 0, width: bubbleW, height: bubbleH)
                // Bubble thấp (ít headroom): co chữ cho vừa — không để glyph bị cắt nửa.
                let size = min(34, (bubbleH * 0.9).rounded())
                if label.font.pointSize != size { label.font = .systemFont(ofSize: size) }
            }
            shape.fillColor = fill.cgColor
            label.textColor = ink
            label.text = text
            isHidden = false
        }
    }

    /// Ô phóng to chữ khi bấm (Tính năng → Giao diện, App Group "keyPreviewEnabled",
    /// mặc định BẬT). Tắt ⇒ không tạo BalloonView, không vẽ gì khi bấm (bớt CPU/GPU).
    static let keyPreviewKey = "keyPreviewEnabled"
    private(set) var keyPreviewEnabled = true
    /// Đọc cài đặt (nil/không có key = bật như trước).
    static func keyPreviewSetting(_ d: UserDefaults?) -> Bool {
        d?.object(forKey: keyPreviewKey) == nil || d?.bool(forKey: keyPreviewKey) == true
    }
    private var balloonMade = false
    private lazy var balloon: BalloonView = { balloonMade = true; return BalloonView() }()
    var debugBalloonMade: Bool { balloonMade }
    private func showBalloon(over key: UIView, text: String, force: Bool = false) {
        guard keyPreviewEnabled || force else { return }
        let f = convert(key.bounds, from: key)
        // Không bao giờ vượt mép trên view (extension bị cắt ở đó) — headroom luôn có
        // (KeyLayout.balloonHeadroom); bubble thấp thì chữ co cho vừa.
        let topLimit: CGFloat = 0
        if balloon.superview == nil { addSubview(balloon) }
        balloon.present(keyRect: f, text: text, fill: palette.balloon.ui, ink: palette.ink.ui, topLimit: topLimit)
    }
    private func hideBalloon() { if balloonMade { balloon.isHidden = true } }

    private func textButton(_ s: String, hint: String? = nil) -> UIView {
        let b = baseButton(title: s, special: false)
        if Self.isPad { b.padRole = .digit }   // số/ký hiệu: cỡ chữ iPad, căn giữa như stock
        if let hint {
            // Plane số iPad: ký tự phụ xám phía trên như stock, khối chữ theo tâm phím.
            addPadHint(hint, to: b)
            b.padRole = .letter
            armPadAlternate(b, alt: hint)
        }
        b.addAction(UIAction { [weak self, weak b] _ in
            Self.clickLetter()
            if let self, let b { self.showBalloon(over: b, text: s) }
        }, for: .touchDown)
        b.addAction(UIAction { [weak self] _ in self?.hideBalloon() },
                    for: [.touchUpInside, .touchUpOutside, .touchCancel])
        armCommit(b) { [weak self, weak b] in
            self?.typedInSymbolPlane = true
            self?.tapped(.text(b?.takePadAlt() == true ? (hint ?? s) : s))
        }
        // Giữ ra hàng biến thể như stock (KeyVariants) — chỉ bàn số/ký hiệu, phím KHÔNG có
        // nhãn phụ iPad (nhãn phụ đã dùng cử chỉ giữ). Chạm thường vẫn chèn ký tự gốc.
        if hint == nil {
            let v = KeyVariants.variants(for: s, symbolPlane: plane == .numbers || plane == .symbols,
                                         numericField: inputKind == .number)
            if !v.isEmpty { armDomainHold(b, choices: v, variants: true) }
        }
        return b
    }

    /// Nhãn ký tự phụ iPad (xám, trên tâm phím) — cỡ/baseline do KeyButton.padRole áp.
    private func addPadHint(_ text: String, to b: KeyButton) {
        let l = UILabel()
        l.text = text
        l.textColor = inkFaded(Double(KeyGeometry.Typography.Pad.hintAlpha(dark: dark)))
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isUserInteractionEnabled = false
        l.isAccessibilityElement = false
        b.addSubview(l)
        let base = l.firstBaselineAnchor.constraint(equalTo: b.centerYAnchor)
        NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: b.centerXAnchor), base])
        b.padHint = l
        b.padHintBaseline = base
    }

    /// Phím (UIButton thường, không qua router chữ) có ký tự phụ iPad: VUỐT XUỐNG quá
    /// flickDistance hoặc GIỮ holdDelay mà không trôi → chọn ký tự phụ (balloon hiện nó);
    /// phím chốt lúc nhấc như cũ, action đọc `padAltChosen`.
    private func armPadAlternate(_ b: KeyButton, alt: String) {
        b.padAlt = alt
        b.onPadAltChoose = { [weak self, weak b] in
            guard let self, let b else { return }
            self.choosePadAlt(b)
        }
        // Chạm xuống: bắt đầu sạch + hẹn giờ GIỮ (vuốt xuống do KeyButton.continueTracking).
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            b.padAltChosen = false
            b.padAltTimer?.cancel()
            let w = DispatchWorkItem { [weak self, weak b] in
                guard let self, let b, b.isTracking else { return }
                self.choosePadAlt(b)
            }
            b.padAltTimer = w
            DispatchQueue.main.asyncAfter(deadline: .now() + KeyAlternates.holdDelay, execute: w)
        }, for: .touchDown)
        // Nhấc/huỷ: tắt hẹn giờ + ẨN balloon ký tự phụ (trước đây balloon kẹt lại trên
        // phím "?." / "!," sau khi giữ — Phil 27/09).
        b.addAction(UIAction { [weak self, weak b] _ in
            b?.padAltTimer?.cancel(); b?.padAltTimer = nil
            self?.hideBalloon()   // vô điều kiện: takePadAlt() (action chốt) có thể đã reset padAltChosen trước
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    private func choosePadAlt(_ b: KeyButton) {
        guard !b.padAltChosen, let alt = b.padAlt else { return }
        b.padAltChosen = true
        b.padAltTimer?.cancel(); b.padAltTimer = nil
        showBalloon(over: b, text: alt)
    }

    /// Phím ra KÝ TỰ lúc nhấc (space, dấu câu, số/ký hiệu, return): arm lúc chạm,
    /// chốt lúc nhấc — hoặc lúc touch bị hệ thống huỷ (không nuốt phím ở hàng sát
    /// home indicator), hoặc sớm hơn khi ngón khác chạm xuống (baseButton flush).
    private func armCommit(_ b: UIControl, fire: @escaping () -> Void) {
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            self.commits.arm(ObjectIdentifier(b), fire: fire)
        }, for: .touchDown)
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            self.commits.release(ObjectIdentifier(b))
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    /// `fire`: lúc nào chạy action (mặc định nhấc tay). `.down` cho phím đổi plane
    /// (123/ABC/#+=) như stock — không còn phụ thuộc touch-up (bị hệ thống huỷ sát vùng
    /// 🌐/mic, hoặc ngón trượt) — nguồn "chuyển lại không ăn, phải ấn lần nữa".
    private func controlButton(title: String, armed: Bool = false, fire: ControlFire = .up,
                               action: @escaping () -> Void) -> KeyButton {
        let b = baseButton(title: title, special: true)
        b.addAction(UIAction { _ in Self.clickModifier() }, for: .touchDown)
        if armed { armCommit(b, fire: action) }
        else { b.addAction(UIAction { _ in action() }, for: fire.events) }
        return b
    }
    enum ControlFire {
        case up, upOrCancel, down
        var events: UIControl.Event {
            switch self {
            case .up: return [.touchUpInside, .touchUpOutside]
            case .upOrCancel: return [.touchUpInside, .touchUpOutside, .touchCancel]
            case .down: return .touchDown
            }
        }
    }

    private func shiftButton() -> UIView {
        let symbol = shift == .caps ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift")
        let b = baseButton(title: "", special: true)
        b.setImage(UIImage(systemName: symbol), for: .normal)
        if Self.isPad { b.padRole = .icon }
        b.accessibilityLabel = "Shift"
        if shift != .off {
            b.backgroundColor = shiftOnFill
            b.tintColor = shiftOnInk
        } else {
            b.tintColor = ink
        }
        b.normalBackground = b.backgroundColor
        shiftKeys.append(b)
        // Toggle ở TOUCH-DOWN: roll shift+chữ nhanh phải ra chữ hoa —
        // touch-up thì chữ đã kịp chốt trước khi shift bật.
        b.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if now - self.lastShiftTap < 0.3 { self.shift = .caps }
            else { self.shift = (self.shift == .off) ? .on : .off }
            self.lastShiftTap = now
            self.applyShiftAppearance()
        }, for: .touchDown)
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        return b
    }

    private func backspaceButton() -> UIView {
        let b = baseButton(title: "", special: true)
        b.setImage(UIImage(systemName: "delete.left"), for: .normal)
        if Self.isPad { b.padRole = .icon }   // icon cỡ stock iPad (Typography.Pad)
        b.setImage(UIImage(systemName: "delete.left.fill"), for: .highlighted)
        b.tintColor = ink
        b.accessibilityLabel = L("Xoá")
        // touchDown xoá 1 ký tự như cũ; kéo ngang → vuốt xoá theo từ (xem MARK dưới).
        b.addTarget(self, action: #selector(backspaceDown(_:event:)), for: .touchDown)
        b.addTarget(self, action: #selector(backspaceDrag(_:event:)),
                    for: [.touchDragInside, .touchDragOutside])
        b.addTarget(self, action: #selector(backspaceUp(_:event:)),
                    for: [.touchUpInside, .touchUpOutside, .touchCancel])
        // press & hold repeats (starts after 0.5s, ~11 Hz — Apple cadence)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(backspaceHold(_:)))
        long.minimumPressDuration = 0.5
        long.delaysTouchesBegan = false
        long.delaysTouchesEnded = false
        long.cancelsTouchesInView = false
        b.addGestureRecognizer(long)
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        return b
    }

    @objc private func backspaceHold(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            guard !wordSwipe.active else { return }   // đang vuốt → không giữ-lặp
            backspaceHoldStart = CACurrentMediaTime()
            wordDeleteTick = 0
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                guard let self else { return }
                // Apple accelerates a sustained hold: ~1.6s cadence doubles,
                // ~3s chuyển sang xoá theo từ (~2.8 từ/s).
                let held = CACurrentMediaTime() - self.backspaceHoldStart
                if held > 3.0, self.plane != .emojiSearch, let deleteWord = self.onDeleteWord {
                    self.wordDeleteTick += 1
                    if self.wordDeleteTick % 4 == 1 { deleteWord() }
                    return
                }
                self.tapped(.backspace)
                if held > 1.6 { self.tapped(.backspace) }
            }
        case .ended, .cancelled, .failed:
            repeatTimer?.invalidate()
            repeatTimer = nil
        default: break
        }
    }

    // MARK: vuốt trái trên ⌫ = xoá theo từ (kiểu Gboard)
    // Extension không tạo được vùng chọn trong app host → xem trước bằng nhãn nổi
    // trên phím ⌫ ("⌫ 2 từ"), NHẤC TAY mới xoá; kéo về dưới ngưỡng rồi nhấc = huỷ.
    // Chỉ kích hoạt khi chưa giữ-lặp và kéo ngang ≥ WordDelete.swipeActivation.

    /// Chạm ⌫ xuống — controller chụp context TRƯỚC lần xoá của chạm này.
    var onBackspaceTouchDown: (() -> Void)?
    /// Số từ tối đa xoá được (controller đếm trên context đã chụp). 0 = không vuốt.
    var wordSwipeLimit: (() -> Int)?
    /// Nhấc tay sau khi vuốt: số từ đã chọn (0 = huỷ).
    var onWordSwipeEnd: ((Int) -> Void)?

    private struct WordSwipeState {
        var startX: CGFloat = 0
        var tracking = false
        var active = false
        var maxWords = 0
        var words = 0
    }
    private var wordSwipe = WordSwipeState()
    private weak var wordSwipeKey: UIView?
    private var wordSwipePill: UILabel?

    @objc private func backspaceDown(_ sender: UIControl, event: UIEvent) {
        Self.clickDelete()
        // Ô tìm emoji: ⌫ chỉ xoá trong ô tìm — không chụp context / vuốt xoá từ ô nhập.
        if plane == .emojiSearch { tapped(.backspace); return }
        onBackspaceTouchDown?()
        let x = event.allTouches?.first(where: { $0.view === sender })?.location(in: self).x
        wordSwipeKey = sender
        backspaceSwipeBegan(x: x ?? 0)
        tapped(.backspace)
    }

    @objc private func backspaceDrag(_ sender: UIControl, event: UIEvent) {
        guard let x = event.allTouches?.first(where: { $0.view === sender })?.location(in: self).x
        else { return }
        backspaceSwipeMoved(x: x)
    }

    @objc private func backspaceUp(_ sender: UIControl, event: UIEvent) {
        backspaceSwipeEnded()
    }

    private func backspaceSwipeBegan(x: CGFloat) {
        wordSwipe = WordSwipeState(startX: x, tracking: true)
    }

    private func backspaceSwipeMoved(x: CGFloat) {
        guard wordSwipe.tracking else { return }
        let dragLeft = wordSwipe.startX - x
        if !wordSwipe.active {
            // giữ-lặp đã chạy = đã xoá nhiều ký tự → không chuyển sang vuốt nữa
            guard dragLeft >= WordDelete.swipeActivation, repeatTimer == nil else { return }
            let limit = wordSwipeLimit?() ?? 0
            guard limit > 0 else { wordSwipe.tracking = false; return }
            wordSwipe.active = true
            wordSwipe.maxWords = limit
        }
        let step = WordDelete.swipeStep(letterKeyWidth: letterKeys.first?.button.bounds.width)
        let n = WordDelete.words(dragLeft: dragLeft, step: step, max: wordSwipe.maxWords)
        if n != wordSwipe.words {
            wordSwipe.words = n
            Self.clickWordStep()
        }
        showWordSwipePill(words: n)
    }

    private func backspaceSwipeEnded() {
        let s = wordSwipe
        wordSwipe = WordSwipeState()
        hideWordSwipePill()
        guard s.active else { return }
        onWordSwipeEnd?(s.words)
    }

    private func showWordSwipePill(words n: Int) {
        let pill: UILabel
        if let p = wordSwipePill { pill = p } else {
            pill = UILabel()
            pill.font = .systemFont(ofSize: 15, weight: .semibold)
            pill.textAlignment = .center
            pill.layer.cornerRadius = 8
            pill.layer.masksToBounds = true
            pill.isUserInteractionEnabled = false
            wordSwipePill = pill
        }
        pill.text = n > 0 ? L("\u{232B} %@ từ", n) : L("Huỷ")
        pill.textColor = palette.ink.ui
        pill.backgroundColor = palette.balloon.ui
        if pill.superview == nil { addSubview(pill) }
        bringSubviewToFront(pill)
        let key = wordSwipeKey.map { convert($0.bounds, from: $0) }
            ?? CGRect(x: bounds.width - 50, y: bounds.height - 100, width: 44, height: 42)
        let size = pill.intrinsicContentSize
        let w = size.width + 20, h: CGFloat = 32
        pill.frame = CGRect(x: max(4, min(key.maxX - w, bounds.width - w - 4)),
                            y: max(0, key.minY - h - 6), width: w, height: h)
        pill.isHidden = false
    }

    private func hideWordSwipePill() {
        wordSwipePill?.isHidden = true
    }

    @objc private func spaceTouchDown(_ sender: UIControl, event: UIEvent) {
        if spaceFlickEnabled, plane != .emojiSearch,
           let touch = event.allTouches?.first(where: { $0.view === sender }) {
            flickStart = (touch.location(in: self), CACurrentMediaTime())
            flickLast = flickStart?.p
        } else {
            flickStart = nil
        }
        guard TouchLog.enabled else { return }       // Debug mode tắt ⇒ 0 việc mỗi lần space
        TouchLog.buttonDown("space", touchTimestamp: event.allTouches?.first(where: { $0.view === sender })?.timestamp)
    }

    /// Space-hold = trackpad mode: kéo ngang dời con trỏ ~9pt/ký tự (stock), kéo dọc
    /// ~24pt/dòng; kéo nhanh thì tăng tốc. Trục + tăng tốc: TrackpadGesture (thuần).
    @objc private func spaceHold(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: self)
        let t = CACurrentMediaTime()
        switch g.state {
        case .began:
            // Trackpad = không gõ: nhả ra KHÔNG có dấu cách (stock), kể cả khi
            // chưa di con trỏ. cancelsTouchesInView=false nên touchUpInside vẫn tới.
            if let v = g.view { commits.disarm(ObjectIdentifier(v)) }
            if flickStart != nil { flickStart = nil; endFlickPreview(committed: false, animated: false) }
            trackpadBegan(p, t: t)
        case .changed:
            trackpadMoved(p, t: t)
        case .ended, .cancelled, .failed:
            trackpadEnded()
        default: break
        }
    }

    // Làm mượt (góp ý user 27/09/2026 "di con trỏ lag"): bước KHÔNG gửi ngay mỗi touch
    // event — gom vào TrackpadCoalescer, CADisplayLink xả ≤1 adjustTextPosition/frame.
    // Controller được báo bắt đầu/kết thúc để tạm ngưng auto-shift/gợi ý/đọc context
    // mỗi bước (chỉ tính 1 lần lúc nhả tay).
    /// true = bắt đầu trackpad, false = nhả tay (sau lệnh dời cuối).
    var onTrackpad: ((Bool) -> Void)?
    private var trackpadCoalescer = TrackpadCoalescer()
    private var trackpadLink: CADisplayLink?
    private(set) var trackpadActive = false

    private func trackpadBegan(_ p: CGPoint, t: CFTimeInterval) {
        trackpadGesture.begin(x: Double(p.x), y: Double(p.y), t: t)
        _ = trackpadCoalescer.drain()
        trackpadActive = true
        setTrackpadDimmed(true)            // phản hồi thị giác NGAY, không chờ host
        onTrackpad?(true)
    }

    private func trackpadMoved(_ p: CGPoint, t: CFTimeInterval) {
        guard trackpadActive,
              let step = trackpadGesture.move(x: Double(p.x), y: Double(p.y), t: t) else { return }
        trackpadCoalescer.add(step)
        if trackpadLink == nil, window != nil {
            let link = CADisplayLink(target: TrackpadLinkTarget(self), selector: #selector(TrackpadLinkTarget.tick))
            link.add(to: .main, forMode: .common)
            trackpadLink = link
        }
        trackpadLink?.isPaused = false
    }

    /// Một frame: gửi phần đã gom (thường 1 lệnh); hết việc thì dừng link (không đốt pin).
    fileprivate func trackpadFrame() {
        let steps = trackpadCoalescer.drain()
        if steps.isEmpty { trackpadLink?.isPaused = true; return }
        for s in steps {
            tapped(s.axis == .horizontal ? .moveCursor(s.count) : .moveLine(s.count))
        }
    }

    private func trackpadEnded() {
        guard trackpadActive else { return }
        trackpadFrame()                    // bước cuối chưa xả
        trackpadLink?.invalidate(); trackpadLink = nil
        trackpadActive = false
        setTrackpadDimmed(false)
        onTrackpad?(false)
    }

    /// CADisplayLink giữ target mạnh → proxy weak để KeyboardView không bị giữ.
    private final class TrackpadLinkTarget: NSObject {
        weak var owner: KeyboardView?
        init(_ o: KeyboardView) { owner = o }
        @objc func tick() { owner?.trackpadFrame() }
    }

    /// Trackpad mode: mờ keycap + phẳng màu phím như stock — báo hiệu đang
    /// di caret chứ không gõ. Không nằm trên hot path (chỉ chạy khi hold 0.4s).
    private var trackpadDimmed = false
    private func setTrackpadDimmed(_ dim: Bool) {
        guard dim != trackpadDimmed else { return }
        trackpadDimmed = dim
        hideBalloon()
        func walk(_ v: UIView) {
            if let b = v as? KeyButton {
                for sub in b.subviews { sub.alpha = dim ? 0.2 : 1 }
                b.backgroundColor = dim ? plainFill : (b.normalBackground ?? b.backgroundColor)
            } else {
                v.subviews.forEach(walk)
            }
        }
        walk(rowsContainer)
    }

    // MARK: vuốt phím cách đổi Tiếng Việt ↔ Tiếng Anh (SpaceFlick, kiểu HeliBoard)
    // Kéo ngang: nhãn ngôn ngữ hiện tại trượt theo ngón + mờ dần, nhãn kia trượt vào từ
    // phía đối diện. Nhấc nhanh (trước ngưỡng trackpad 0,3 s) đủ ~1 phím ⇒ đổi: nhãn mới
    // vào giữa, sáng một nhịp rồi mờ đi, logo Vᴛ/E đổi theo. Không đủ ⇒ trượt về, mờ đi.
    var onSpaceFlick: (() -> Void)?
    private(set) var spaceFlickEnabled = false
    var spaceLanguage: KeyboardLanguage = .vi {
        didSet { if oldValue != spaceLanguage { refreshSpaceMark() } }
    }
    private var flickStart: (p: CGPoint, t: CFTimeInterval)?
    private var flickLast: CGPoint?
    private var flickCarousel: (box: UIView, cur: UILabel, next: UILabel)?

    func configureSpaceFlick(enabled: Bool, language: KeyboardLanguage) {
        let changed = spaceFlickEnabled != enabled
        spaceFlickEnabled = enabled
        if !enabled { flickStart = nil; endFlickPreview(committed: false, animated: false) }
        spaceLanguage = language
        if changed {
            // logo ↔ mã VI/EN: thay tại chỗ trên plane đang hiện; plane cache dựng lại khi mở.
            planeCache.removeAll()
            if let space = spaceBar { installSpaceMark(on: space) }
        }
        refreshSpaceMark()
    }

    /// Logo Vᴛ hoặc mã VI/EN trên phím cách (SpaceMark). Gọi lúc dựng plane, và tại chỗ khi
    /// công tắc vuốt đổi ngôn ngữ đổi (configureSpaceFlick — không dựng lại cả plane).
    private func installSpaceMark(on space: UIButton) {
        // logo Vᴛ mờ ở mép phải nút space (thay "VI EN" — user 2026-07-23);
        // PNG 2x/3x render từ MenuIcon.pdf nên sắc nét, tint theo appearance.
        // Ẩn được qua Settings của app (showSpaceLogo, App Group).
        // Bật vuốt đổi ngôn ngữ ⇒ mã "VI"/"EN" nhỏ góc dưới-phải như stock (SpaceMark).
        let showLogo = UserDefaultsProvider.shared?.object(forKey: "showSpaceLogo") == nil
            || UserDefaultsProvider.shared?.bool(forKey: "showSpaceLogo") == true
        if spaceLogo?.superview === space { spaceLogo?.removeFromSuperview() }
        if spaceCode?.superview === space { spaceCode?.removeFromSuperview() }
        spaceLogo = nil; spaceCode = nil
        switch SpaceMark.choose(flickEnabled: spaceFlickEnabled, showLogo: showLogo, language: spaceLanguage) {
        case .none: break
        case .code(let code):
            let l = UILabel()
            l.text = code
            l.font = .systemFont(ofSize: Self.isPad ? 13 : 11, weight: .medium)
            l.textColor = inkFaded(0.45)             // mờ như stock; theo độ trong suốt ký tự
            l.isUserInteractionEnabled = false
            l.isAccessibilityElement = false
            l.translatesAutoresizingMaskIntoConstraints = false
            spaceCode = l
            space.addSubview(l)
            NSLayoutConstraint.activate([
                l.rightAnchor.constraint(equalTo: space.rightAnchor, constant: Self.isPad ? -10 : -7),
                l.bottomAnchor.constraint(equalTo: space.bottomAnchor, constant: Self.isPad ? -6 : -4),
            ])
        case .logo:
            let hint = UIImageView(image: spaceLogoImage())
            hint.tintColor = inkFaded(0.16)
            hint.contentMode = .scaleAspectFit
            hint.translatesAutoresizingMaskIntoConstraints = false
            spaceLogo = hint
            space.addSubview(hint)
            NSLayoutConstraint.activate([
                hint.rightAnchor.constraint(equalTo: space.rightAnchor, constant: -10),
                hint.centerYAnchor.constraint(equalTo: space.centerYAnchor),
                hint.widthAnchor.constraint(equalToConstant: 22),
                hint.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
    }

    private func refreshSpaceMark() {
        spaceLogo?.image = spaceLogoImage()
        spaceCode?.text = spaceLanguage.shortCode
    }

    private func spaceLogoImage() -> UIImage? {
        UIImage(named: spaceLanguage == .en ? "SpaceLogoEN" : "SpaceLogo")?.withRenderingMode(.alwaysTemplate)
    }

    private var flickKeyWidth: CGFloat { bounds.width / 10 }

    @objc private func spaceDrag(_ sender: UIControl, event: UIEvent) {
        guard let start = flickStart,
              let touch = event.allTouches?.first(where: { $0.view === sender }) else { return }
        let p = touch.location(in: self)
        flickLast = p
        guard touch.phase == .moved, let space = spaceBar else { return }
        let dx = p.x - start.p.x, dy = p.y - start.p.y
        let q = SpaceFlick.progress(dx: dx, dy: dy, elapsed: CACurrentMediaTime() - start.t,
                                    span: SpaceFlick.previewSpan(keyWidth: flickKeyWidth))
        if q == 0 {
            if flickCarousel != nil { endFlickPreview(committed: false, animated: true) }
            return
        }
        let c = flickCarousel ?? makeFlickCarousel(in: space)
        layoutFlickCarousel(c, q: q)
    }

    /// Lúc space chốt (nhấc tay): true = flick đổi ngôn ngữ (đã xử lý, không chèn dấu cách).
    private func consumeSpaceFlick() -> Bool {
        guard let start = flickStart else { return false }
        flickStart = nil
        let p = flickLast ?? start.p
        let dir = SpaceFlick.classify(dx: p.x - start.p.x, dy: p.y - start.p.y,
                                      duration: CACurrentMediaTime() - start.t, keyWidth: flickKeyWidth)
        guard let dir, spaceFlickEnabled else {
            if flickCarousel != nil { endFlickPreview(committed: false, animated: true) }
            return false
        }
        Self.flickFeedback()
        if flickCarousel == nil, let space = spaceBar {
            layoutFlickCarousel(makeFlickCarousel(in: space), q: dir == .left ? -0.2 : 0.2)
        }
        onSpaceFlick?()
        endFlickPreview(committed: true, animated: true, direction: dir)
        return true
    }

    private func makeFlickCarousel(in space: UIView) -> (box: UIView, cur: UILabel, next: UILabel) {
        let box = UIView(frame: space.bounds)
        box.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.clipsToBounds = true
        box.isUserInteractionEnabled = false
        func label(_ l: KeyboardLanguage) -> UILabel {
            let v = UILabel()
            v.text = l.displayName
            v.font = .systemFont(ofSize: 16, weight: .regular)
            v.textColor = ink
            v.sizeToFit()
            box.addSubview(v)
            return v
        }
        let c = (box, label(spaceLanguage), label(spaceLanguage.toggled))
        space.addSubview(box)
        spaceMarkView?.alpha = 0
        flickCarousel = c
        return c
    }

    /// q ∈ [-1, 1]: nhãn hiện tại lệch q·W/2 theo ngón, nhãn kia theo sau một nửa bề ngang.
    private func layoutFlickCarousel(_ c: (box: UIView, cur: UILabel, next: UILabel), q: CGFloat) {
        let w = c.box.bounds.width, mid = CGPoint(x: w / 2, y: c.box.bounds.height / 2)
        let off = q * w / 2
        c.cur.center = CGPoint(x: mid.x + off, y: mid.y)
        c.next.center = CGPoint(x: mid.x + off - (q < 0 ? -1 : 1) * w / 2, y: mid.y)
        c.cur.alpha = 0.6 * (1 - abs(q))
        c.next.alpha = 0.6 * abs(q)
    }

    private func endFlickPreview(committed: Bool, animated: Bool,
                                 direction: SpaceFlick.Direction = .right) {
        guard let c = flickCarousel else { return }
        flickCarousel = nil
        let restoreLogo = { [weak self] in
            c.box.removeFromSuperview()
            guard let self, self.flickCarousel == nil else { return }
            UIView.animate(withDuration: 0.2) { self.spaceMarkView?.alpha = 1 }
        }
        guard animated else { restoreLogo(); return }
        if committed {
            // nhãn mới vào giữa, sáng một nhịp (~0,5 s) rồi mờ — như HeliBoard
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.layoutFlickCarousel(c, q: direction == .left ? -1 : 1)
                c.next.alpha = 1
            } completion: { _ in
                UIView.animate(withDuration: 0.3, delay: 0.5, options: [.curveEaseOut]) {
                    c.next.alpha = 0
                } completion: { _ in restoreLogo() }
            }
        } else {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.layoutFlickCarousel(c, q: 0.0001)
                c.cur.alpha = 0; c.next.alpha = 0
            } completion: { _ in restoreLogo() }
        }
    }

    /// Stock iOS flashes the layout name ("English (US)") on the spacebar when
    /// the keyboard appears. Same here: "ViệtTelex" for ~700ms, then fade.
    func showLanguageBadge() {
        guard let space = spaceBar else { return }
        let l = UILabel()
        l.text = spaceLanguage == .en ? KeyboardLanguage.en.displayName : "ViệtTelex"
        l.font = .systemFont(ofSize: 16, weight: .regular)
        l.textColor = ink
        l.translatesAutoresizingMaskIntoConstraints = false
        spaceMarkView?.isHidden = true     // logo Vᴛ nhường chỗ, khỏi đè lên badge
        space.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: space.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: space.centerYAnchor),
        ])
        UIView.animate(withDuration: 0.3, delay: 0.7, options: [.curveEaseOut]) {
            l.alpha = 0
        } completion: { [weak self] _ in
            l.removeFromSuperview()
            self?.spaceMarkView?.isHidden = false
        }
    }

    // MARK: touch router cho phím chữ (ForwardingView-style)
    // UIButton event system có các mode fail đã biết (touch bị hệ thống cancel,
    // hit-test theo z-order thay vì khoảng cách, tracking per-control không
    // rollover được). Phím chữ tắt interaction; touch nổi lên đây và được gán
    // cho phím GẦN NHẤT — mọi điểm chạm trong vùng chữ đều trúng một phím.
    private var routedTouches: [ObjectIdentifier: UIButton] = [:]

    // Vùng phím chữ (kể cả khe giữa phím) hit-test về CHÍNH KeyboardView —
    // một mặt touch duy nhất, isMultipleTouchEnabled=true của self có hiệu lực
    // thật. Trước đây hit view là row UIStackView (multipleTouch=false mặc
    // định) rồi forward lên qua responder chain: ngón thứ hai chạm xuống khi
    // ngón trước chưa nhấc bị nuốt ngay ở row stack → gõ nhanh rớt chữ.
    // Button thật (space, shift, backspace, số/ký hiệu, slot bar…) vẫn nhận
    // touch trực tiếp như cũ.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = routedHitTest(point, with: event)
        if TouchLog.enabled, let e = event, e.type == .touches {
            let target: String
            if v === self { target = "router" }
            else if let b = v as? UIButton {
                target = "button[\(b.accessibilityLabel ?? b.currentTitle ?? "?")]"
            } else { target = v.map { String(describing: type(of: $0)) } ?? "nil" }
            TouchLog.hitTest(target: target, y: Double(point.y), stamp: e.timestamp)
        }
        return v
    }

    private func routedHitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        if let p = overlayPanel, !p.isHidden, p.frame.contains(point) { return v }
        // Phím chữ ưu tiên trong FOOTPRINT thật của nó, kể cả khi hit-area nở của
        // shift/backspace kề bên "cướp" điểm chạm — nếu không, chạm mép z/m thành
        // toggle shift / xoá thay vì ra chữ (nguồn rớt phím ở hàng 3, 2026-07-26).
        if lettersLike, letterCoreContains(point) { return self }
        if let c = v as? UIControl {
            // Mép chung (KeyHitBias): space thắng ","/"." kề; chữ thắng ⇧/⌫ kề.
            if let r = biasedHit(c, at: point, time: event?.timestamp) { return r }
            return v
        }
        // Khe / mép trong vùng phím: nút thật GẦN NHẤT (123, emoji, ⇧, ⌫, số…) hoặc phím chữ
        // gần hơn (router). Trước đây khe trên mỗi hàng nút (4.5pt: nút chỉ nở 5.5 trong khe
        // 10) là vùng CHẾT — chạm cao phím 123/ABC/emoji mất hẳn, chạm cao emoji ra chữ z.
        if v != nil, let b = nearestControl(at: point) {
            if let l = nearestLetterDistance(at: TouchGeometry.keySelectionPoint(point, top: rowsContainer.frame.minY)),
               l < b.distance { return self }
            return b.button
        }
        if v != nil, nearestLetterButton(at: point) != nil { return self }
        return v
    }

    /// Ưu tiên ở mép chung (KeyHitBias, iPhone): điểm rơi vào "," / "." nhưng trong dải sát
    /// space ⇒ space; rơi vào ⇧ / ⌫ nhưng trong dải sát phím chữ ⇒ router chữ (self).
    /// nil = giữ `c`. Chỉ chạy khi điểm chạm trúng một trong các nút đó (rẻ).
    private func biasedHit(_ c: UIControl, at point: CGPoint, time: TimeInterval?) -> UIView? {
        guard !Self.isPad else { return nil }
        let since = time.flatMap { t in lastLetterDownTime.map { t - $0 } }
        if let space = spaceBar, c !== space, let b = c as? UIButton,
           let t = b.currentTitle, t == "," || t == ".",
           b.superview != nil, b.superview === space.superview {
            let band = KeyHitBias.spaceBand(sinceLetter: since)
            if KeyHitBias.intrudes(point, loser: convert(b.bounds, from: b),
                                   winner: convert(space.bounds, from: space), band: band) {
                return space
            }
            return nil
        }
        if lettersLike, letterStealing(from: c, at: point, sinceLetter: since) != nil { return self }
        return nil
    }

    /// ⇧ / ⌫ đang hiện ở plane chữ: chỉ số phím chữ kề mà `point` lấn vào (KeyHitBias).
    private func letterStealing(from c: UIControl, at point: CGPoint, sinceLetter: TimeInterval?) -> Int? {
        guard !Self.isPad, lettersLike, !letterKeys.isEmpty,
              shiftKeys.contains(where: { $0 === c }) || c.accessibilityLabel == L("Xoá") else { return nil }
        return KeyHitBias.stealer(point, loser: convert(c.bounds, from: c), winners: letterGeometry().rects,
                                  band: KeyHitBias.letterBand(sinceLetter: sinceLetter))
    }

    /// Router nhận điểm do ⇧/⌫ nhường (KeyHitBias) nhưng nằm ngoài tầm 21pt của phím chữ
    /// gần nhất (khe ⇧↔z rộng 12) ⇒ lấy đúng phím chữ đã lấn.
    private func letterStolenFromControl(at point: CGPoint, time: TimeInterval) -> UIButton? {
        guard !Self.isPad, lettersLike else { return nil }
        let since = lastLetterDownTime.map { time - $0 }
        for row in rowsContainer.arrangedSubviews {
            guard let stack = row as? UIStackView else { continue }
            for case let c as UIControl in stack.arrangedSubviews where !c.isHidden {
                if convert(c.bounds, from: c).insetBy(dx: -3, dy: -5.5).contains(point),
                   let i = letterStealing(from: c, at: point, sinceLetter: since) {
                    return letterKeys[i].button
                }
            }
        }
        return nil
    }

    /// Nút thật (bật tương tác, đang hiện) trong các hàng phím gần `point` nhất — chỉ chạy ở
    /// khe/mép (hiếm), ≤ ~40 rect. Tầm với 22pt như router chữ.
    private func nearestControl(at point: CGPoint) -> (button: UIControl, distance: CGFloat)? {
        guard point.y >= rowsContainer.frame.minY, rowsContainer.frame.contains(point) else { return nil }
        var buttons: [UIControl] = []
        for row in rowsContainer.arrangedSubviews {
            guard let stack = row as? UIStackView else { continue }
            for case let c as UIControl in stack.arrangedSubviews
            where c.isUserInteractionEnabled && !c.isHidden && c.alpha > 0.01 {
                buttons.append(c)
            }
        }
        let rects = buttons.map { convert($0.bounds, from: $0) }
        guard let n = KeyGeometry.nearest(point, in: rects, reach: 22) else { return nil }
        return (buttons[n.index], n.distance)
    }

    private func nearestLetterDistance(at p: CGPoint) -> CGFloat? {
        guard lettersLike, !letterKeys.isEmpty else { return nil }
        let rects = letterKeys.map { convert($0.button.bounds, from: $0.button) }
        return KeyGeometry.nearest(p, in: rects, reach: 22)?.distance
    }

    private func letterCoreContains(_ point: CGPoint) -> Bool {
        guard point.y >= rowsContainer.frame.minY else { return false }
        return letterGeometry().rects.contains { $0.contains(point) }
    }

    /// Frame phím chữ (toạ độ self) + ký tự gốc, CACHE giữa các lần layout: router chạy
    /// hitTest + routeDown (+ smartPick) mỗi chạm — trước đây 2–3 lượt convert 26 phím và
    /// cấp phát 2 mảng mỗi chạm. Vứt ở mỗi layoutSubviews / rebuild (phím dời ⇒ tính lại).
    private var letterGeometryCache: (rects: [CGRect], chars: [Character])?
    private func letterGeometry() -> (rects: [CGRect], chars: [Character]) {
        if let c = letterGeometryCache, c.rects.count == letterKeys.count { return c }
        let g = (letterKeys.map { convert($0.button.bounds, from: $0.button) },
                 letterKeys.map { $0.base.first ?? " " })
        letterGeometryCache = g
        return g
    }

    private func nearestLetterButton(at point: CGPoint) -> UIButton? {
        // Chỉ route touch TRONG vùng phím — touch ở strip gợi ý phía trên là
        // của chevron/slot, router mà cướp thì chevron "bấm mãi không ăn".
        guard lettersLike, !letterKeys.isEmpty,
              point.y >= rowsContainer.frame.minY else { return nil }
        var best: (Int, CGFloat)?
        for (i, f) in letterGeometry().rects.enumerated() {
            if f.insetBy(dx: -3, dy: -5.5).contains(point) { return letterKeys[i].button }
            let dx = max(f.minX - point.x, 0, point.x - f.maxX)
            let dy = max(f.minY - point.y, 0, point.y - f.maxY)
            let d = dx * dx + dy * dy
            if best == nil || d < best!.1 { best = (i, d) }
        }
        // chỉ nhận khi thật sự gần hàng phím chữ (~nửa chiều cao phím)
        if let (i, d) = best, d <= 21 * 21 { return letterKeys[i].button }
        return nil
    }

    /// Chọn phím theo ngữ cảnh (thử nghiệm, TouchTarget): controller trả P(phím | từ đang
    /// gõ) lúc chạm, nil = không biết / tắt. nil (mặc định) ⇒ router gần-nhất như cũ.
    var letterPrior: (() -> ((Character) -> Float?)?)?

    /// Tự sửa (thử nghiệm): điểm chạm của phím chữ sắp chèn — lệch so với tâm phím, theo cỡ
    /// phím. Gọi NGAY TRƯỚC khi phím đó tới controller. nil (tắt) ⇒ không tính gì.
    var onLetterTouch: ((Float, Float) -> Void)?

    /// Vùng biên giữa 2 phím ⇒ TouchTarget.choose; lõi phím ⇒ giữ ngay (0 alloc).
    private func smartPick(_ hit: UIButton, at p: CGPoint,
                           prior lp: () -> ((Character) -> Float?)?) -> UIButton {
        guard plane == .letters,
              let hi = letterKeys.firstIndex(where: { $0.button === hit }),
              !TouchTarget.inCore(p, letterGeometry().rects[hi]) else { return hit }
        // Chốt phím nhấc-mới-chốt đang đè (vd space) TRƯỚC để prior thấy từ đang gõ mới nhất
        // (sendActions(.touchDown) sau đó flush lần nữa = no-op).
        commits.flush(except: nil)
        guard let prior = lp(), let idx = letterKeys.firstIndex(where: { $0.button === hit }) else { return hit }
        let g = letterGeometry()
        return letterKeys[TouchTarget.choose(p, rects: g.rects, keys: g.chars, nearest: idx, prior: prior)].button
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            routeDown(ObjectIdentifier(t), at: t.location(in: self), time: t.timestamp,
                      batch: touches.count)
        }
    }

    /// Chạm xuống vùng chữ: gán phím gần nhất và chèn NGAY (touchDown). Gõ vuốt bật ⇒
    /// touch duy nhất được route bắt đầu phân loại chạm/vuốt (GestureClassifier).
    private func routeDown(_ id: ObjectIdentifier, at raw: CGPoint, time: TimeInterval, batch: Int) {
        let p = TouchGeometry.keySelectionPoint(raw, top: rowsContainer.frame.minY)
        var b = swipeActive ? nil : (nearestLetterButton(at: p) ?? letterStolenFromControl(at: raw, time: time))
        if let hit = b, let lp = letterPrior { b = smartPick(hit, at: p, prior: lp) }
        TouchLog.touchBegan(active: routedTouches.count, batch: batch,
                            touchTimestamp: time, hit: b != nil, y: Double(p.y),
                            key: b?.currentTitle)
        guard let b else { return }
        if classifier != nil {                   // ngón thứ hai lúc chưa quyết ⇒ khoá chạm
            classifier?.secondTouch()
            stopClassifying()
        }
        routedTouches[id] = b
        if Self.isPad { routedStart[id] = raw }
        let since = lastLetterDownTime.map { time - $0 }
        lastLetterDownTime = time
        if let report = onLetterTouch, plane == .letters {          // tự sửa: lệch so với tâm phím
            let r = convert(b.bounds, from: b)
            if r.width > 0, r.height > 0 {
                report(Float((p.x - r.midX) / r.width), Float((p.y - r.midY) / r.height))
            }
        }
        b.sendActions(for: .touchDown)
        if swipeEnabled, plane == .letters, routedTouches.count == 1, let kw = letterKeyPitch() {
            startClassifying(id, at: p, time: time, key: convert(b.bounds, from: b),
                             keyWidth: kw, since: since)
        }
        if !activeAlts.isEmpty { armAltHold(id, button: b, at: raw) }
    }

    /// Chạm phím có ký tự phụ: hẹn giờ `holdDelay`. Chữ đã chèn lúc chạm; hết giờ mà
    /// ngón chưa trôi / chưa thành vuốt ⇒ balloon hiện ký tự phụ, nhấc tay thì thay chữ.
    private func armAltHold(_ id: ObjectIdentifier, button b: UIButton, at raw: CGPoint) {
        guard let base = letterKeys.first(where: { $0.button === b })?.base.first,
              let alt = activeAlts[base] else { return }
        altHold = (id, b, KeyAlternates.Hold(alt: alt, start: raw))
        let w = DispatchWorkItem { [weak self] in self?.fireAltHold() }
        altTimer = w
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyAlternates.holdDelay, execute: w)
    }

    private func fireAltHold() {
        altTimer = nil
        guard var h = altHold, !swipeActive, h.hold.fire() else { return }
        altHold = h
        if swipeTouchID == h.id { stopClassifying() }   // đã là giữ: trôi sau đó không thành vuốt
        Self.flickFeedback()
        showBalloon(over: h.button, text: h.hold.alt, force: true)
    }

    /// Ngón mới chạm (phím bất kỳ): giữ chưa đủ giờ ⇒ chỉ là chạm; đã bắn ⇒ chốt ký tự phụ
    /// NGAY (trước phím mới, kẻo checkpoint huỷ chữ trỏ nhầm phím).
    private func settleAltHold() {
        guard let h = altHold else { return }
        altTimer?.cancel(); altTimer = nil
        altHold = nil
        if let alt = h.hold.commit { commitAlt(alt) }
    }

    private func dropAltHold() {
        altTimer?.cancel(); altTimer = nil
        altHold = nil
    }

    /// Phím "," có giữ ra ".": nhãn nhỏ góc trên-phải như phím chữ; chạm hẹn giờ `holdDelay`,
    /// hết giờ mà "," còn chờ chốt ⇒ đổi thành "." (KeyAlternates.holdComma) + balloon + rung.
    /// Chốt lúc nhấc / khi ngón khác chạm như "," ⇒ từ đang gõ được chốt y hệt.
    private func armCommaHold(_ b: KeyButton) {
        let l = UILabel()
        l.text = KeyAlternates.commaAlt
        l.font = .systemFont(ofSize: 10, weight: .medium)
        l.textColor = inkFaded(0.45)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isUserInteractionEnabled = false
        l.isAccessibilityElement = false
        b.addSubview(l)
        NSLayoutConstraint.activate([
            l.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -3),
            l.topAnchor.constraint(equalTo: b.topAnchor, constant: 2),
        ])
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            self.commaTimer?.cancel()
            let w = DispatchWorkItem { [weak self, weak b] in
                guard let self, let b else { return }
                self.fireCommaHold(b)
            }
            self.commaTimer = w
            DispatchQueue.main.asyncAfter(deadline: .now() + KeyAlternates.holdDelay, execute: w)
        }, for: .touchDown)
        b.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.commaTimer?.cancel(); self.commaTimer = nil
            if self.commaFired { self.commaFired = false; self.hideBalloon() }
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    private func fireCommaHold(_ b: KeyButton) {
        commaTimer = nil
        let fired = KeyAlternates.holdComma(commits, id: ObjectIdentifier(b)) { [weak self] alt in
            self?.hideBalloon()
            self?.tapped(.text(alt))
        }
        guard fired else { return }
        commaFired = true
        Self.flickFeedback()
        showBalloon(over: b, text: KeyAlternates.commaAlt, force: true)
    }
    private var commaTimer: DispatchWorkItem?
    private var commaFired = false

    // MARK: giữ "." ⇒ popup đuôi tên miền (ô .search / .url / .email, bàn chữ)

    /// Hẹn giờ `holdDelay` như giữ ","; hết giờ mà phím còn chờ chốt ⇒ dựng popup (lần đầu
    /// mới tạo view), phím chờ chốt đổi thành "chèn đuôi đang chọn" — chốt lúc nhấc / khi ngón
    /// khác chạm y như "." ⇒ từ đang gõ được chốt cùng đường. Trượt xa ⇒ không chọn ⇒ nhấc
    /// không chèn gì.
    private func armDomainHold(_ b: KeyButton, choices: [String], variants: Bool = false) {
        b.addTarget(self, action: #selector(domainTouch(_:event:)),
                    for: [.touchDown, .touchDragInside, .touchDragOutside])
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b, !UIAccessibility.isVoiceOverRunning else { return }
            self.domainTimer?.cancel()
            let w = DispatchWorkItem { [weak self, weak b] in
                guard let self, let b, b.isTracking else { return }
                self.fireDomainHold(b, choices: choices, variants: variants)
            }
            self.domainTimer = w
            DispatchQueue.main.asyncAfter(deadline: .now() + KeyAlternates.holdDelay, execute: w)
        }, for: .touchDown)
        // Sau armCommit (release chạy trước ⇒ đuôi đã chèn), rồi dọn popup.
        b.addAction(UIAction { [weak self] _ in
            self?.domainTimer?.cancel(); self?.domainTimer = nil
            self?.closeDomainPopup()
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    @objc private func domainTouch(_ sender: UIControl, event: UIEvent) {
        guard let t = event.allTouches?.first(where: { $0.view === sender }) else { return }
        let p = t.location(in: self)
        domainLastPoint = p
        if domainHold?.button === sender { domainMoved(to: p) }
    }

    /// `variants`: hàng biến thể ký tự (KeyVariants) — ô hẹp hơn, chữ to hơn đuôi tên miền.
    private func fireDomainHold(_ b: KeyButton, choices: [String], variants: Bool = false) {
        domainTimer = nil
        let id = ObjectIdentifier(b)
        guard commits.isArmed(id) else { return }       // "." đã chốt (ngón khác chạm trước)
        commits.disarm(id)
        commits.arm(id) { [weak self] in
            guard let self else { return }
            let s = self.domainHold.flatMap { h in h.sel.map { h.choices[$0] } }
            self.closeDomainPopup()
            if let s {
                if variants { self.typedInSymbolPlane = true }   // như chạm thường (space về chữ)
                self.tapped(.text(s))
            }
        }
        let key = convert(b.bounds, from: b)
        let itemW: CGFloat = variants ? (Self.isPad ? 56 : 38) : (Self.isPad ? 68 : 56)
        let l = DomainPopup.layout(keyMidX: key.midX, itemWidth: itemW, count: choices.count,
                                   containerWidth: bounds.width)
        let panelH: CGFloat = Self.isPad ? 52 : 46
        let top = max(key.minY - 8 - panelH, 0)       // không vượt mép trên (bị cắt)
        let p = domainLastPoint ?? CGPoint(x: key.midX, y: key.midY)
        let sel = DomainPopup.index(at: p, startX: p.x, layout: l, top: top, bottom: key.maxY)
        domainHold = (b, choices, l, p.x, top, key.maxY, sel)
        debugLastDomainLayout = l
        hideBalloon()
        domainPopupMade = true
        if domainPopup == nil { domainPopup = DomainPopupView() }
        guard let v = domainPopup else { return }
        if v.superview == nil { addSubview(v) }
        v.present(layout: l, key: key, top: top, panelH: panelH, choices: choices,
                  fill: palette.balloon.ui, ink: palette.ink.ui,
                  fontSize: variants ? (Self.isPad ? 26 : 24) : (Self.isPad ? 20 : 18))
        v.select(sel)
        Self.flickFeedback()
    }

    private func domainMoved(to p: CGPoint) {
        guard var h = domainHold else { return }
        let sel = DomainPopup.index(at: p, startX: h.startX, layout: h.layout, top: h.top, bottom: h.bottom)
        guard sel != h.sel else { return }
        h.sel = sel
        domainHold = h
        domainPopup?.select(sel)
        if sel != nil { Self.flickFeedback() }
    }

    private func closeDomainPopup() {
        domainHold = nil
        domainLastPoint = nil
        domainPopup?.isHidden = true
    }

    private var domainTimer: DispatchWorkItem?
    private var domainLastPoint: CGPoint?
    private var domainHold: (button: KeyButton, choices: [String], layout: DomainPopup.Layout,
                             startX: CGFloat, top: CGFloat, bottom: CGFloat, sel: Int?)?
    private var domainPopup: DomainPopupView?
    private var domainPopupMade = false
    var debugDomainPopupMade: Bool { domainPopupMade }
    private(set) var debugLastDomainLayout: DomainPopup.Layout?
    /// Đuôi đang chọn khi popup mở (nil = đóng / không chọn).
    var debugDomainSelection: String? { domainHold.flatMap { h in h.sel.map { h.choices[$0] } } }
    var debugDomainPopupVisible: Bool { domainPopup.map { !$0.isHidden && $0.superview != nil } ?? false }

    /// Popup đuôi tên miền: panel bo góc liền khối với phím (cùng nền balloon, bóng như
    /// balloon), ô đang chọn nền xanh hệ thống chữ trắng như stock.
    private final class DomainPopupView: UIView {
        private let shape = CAShapeLayer()
        private let highlight = CALayer()
        private var labels: [UILabel] = []
        private var slots: [CGRect] = []
        private var ink: UIColor = .label
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            layer.zPosition = 11
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 3
            layer.shadowOpacity = 0.3
            layer.addSublayer(shape)
            highlight.backgroundColor = UIColor.systemBlue.cgColor
            highlight.cornerRadius = 7
            highlight.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
            layer.addSublayer(highlight)
        }
        required init?(coder: NSCoder) { fatalError() }

        /// Toạ độ `key`, `layout`, `top` theo superview (KeyboardView).
        func present(layout l: DomainPopup.Layout, key: CGRect, top: CGFloat, panelH: CGFloat,
                     choices: [String], fill: UIColor, ink: UIColor, fontSize: CGFloat) {
            let inset: CGFloat = 4
            let panel = CGRect(x: l.originX - inset, y: top, width: l.width + inset * 2, height: panelH)
            let f = panel.union(key)
            frame = f
            let lp = panel.offsetBy(dx: -f.minX, dy: -f.minY)
            let lk = key.offsetBy(dx: -f.minX, dy: -f.minY)
            let path = UIBezierPath(roundedRect: lp, cornerRadius: 10)
            // Cổ nối panel xuống trọn phím (phủ phím như balloon).
            let neck = CGRect(x: lk.minX, y: lp.maxY - 10, width: lk.width, height: lk.maxY - lp.maxY + 10)
            path.append(UIBezierPath(roundedRect: neck, cornerRadius: KeyboardView.keyRadius))
            shape.path = path.cgPath
            shape.fillColor = fill.cgColor
            layer.shadowPath = path.cgPath
            self.ink = ink
            while labels.count < choices.count {
                let lb = UILabel()
                lb.textAlignment = .center
                lb.adjustsFontSizeToFitWidth = true
                lb.minimumScaleFactor = 0.7
                addSubview(lb)
                labels.append(lb)
            }
            slots = []
            for (i, lb) in labels.enumerated() {
                guard i < choices.count else { lb.isHidden = true; continue }
                let r = CGRect(x: l.slotMinX(i) - f.minX, y: lp.minY + inset,
                               width: l.itemWidth, height: panelH - inset * 2)
                slots.append(r)
                lb.isHidden = false
                lb.text = choices[i]
                lb.font = .systemFont(ofSize: fontSize)
                lb.frame = r
            }
            isHidden = false
        }

        func select(_ i: Int?) {
            for (j, lb) in labels.enumerated() { lb.textColor = j == i ? .white : ink }
            guard let i, i < slots.count else { highlight.isHidden = true; return }
            highlight.frame = slots[i].insetBy(dx: 1, dy: 0)
            highlight.isHidden = false
        }
    }

    private func commitAlt(_ alt: String) {
        hideBalloon()
        if shiftBeforeLastLetter == .on, shift == .off { shift = .on; applyShiftAppearance() }
        tapped(.replaceLastLetter(alt))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let h = altHold, !h.hold.fired {
            for t in touches where ObjectIdentifier(t) == h.id {
                if altHold?.hold.move(to: t.location(in: self)) == true { dropAltHold() }
            }
        }
        guard let id = swipeTouchID else { return }     // tắt / không theo dõi ⇒ 0 việc
        for t in touches where ObjectIdentifier(t) == id {
            for c in event?.coalescedTouches(for: t) ?? [t] {
                swipeMoved(to: c.location(in: self), time: c.timestamp)
                if swipeTouchID == nil { return }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            routeUp(ObjectIdentifier(t), at: t.location(in: self), time: t.timestamp, cancelled: false)
        }
    }

    private func routeUp(_ id: ObjectIdentifier, at raw: CGPoint, time: TimeInterval, cancelled: Bool) {
        let swiped = swipeUp(id, at: raw, time: time)
        let b = routedTouches.removeValue(forKey: id)
        let start = routedStart.removeValue(forKey: id)
        TouchLog.touchEnded(cancelled: cancelled, routed: b != nil)
        guard let b else { return }
        var alt: String?
        if let h = altHold, h.id == id { alt = h.hold.commit; dropAltHold() }
        b.sendActions(for: .touchUpInside)
        if let alt, !swiped { commitAlt(alt); return }  // cancel vẫn chốt như chữ thường
        guard !swiped, !cancelled else { return }
        // iPad: vuốt xuống trên phím chữ = ký tự phụ như stock. Chữ đã chèn lúc
        // chạm (touchDown) → HUỶ đúng phím đó (không ⌫: phím dấu Telex đã đổi từ)
        // rồi chèn ký tự phụ; shift một lần mà phím đó đã nhả thì trả lại.
        if let start, KeyLayout.isPadFlick(dx: raw.x - start.x, dy: raw.y - start.y,
                                           threshold: Self.flickDistance),
           let base = letterKeys.first(where: { $0.button === b })?.base,
           let sec = Self.padSecondary[base] {
            if shiftBeforeLastLetter == .on, shift == .off { shift = .on; applyShiftAppearance() }
            tapped(.replaceLastLetter(sec))
        }
    }
    private var routedStart: [ObjectIdentifier: CGPoint] = [:]
    private var shiftBeforeLastLetter: ShiftState = .off
    fileprivate static let flickDistance: CGFloat = 18

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // hệ thống cancel (edge gesture…) — vẫn CHỐT chữ thay vì nuốt phím; cú vuốt
        // đang dở cũng chốt (chữ đầu đã bị huỷ — bỏ ngang là mất chữ).
        for t in touches {
            routeUp(ObjectIdentifier(t), at: t.location(in: self), time: t.timestamp, cancelled: true)
        }
    }

    // MARK: gõ vuốt (thử nghiệm) — router + vệt vuốt
    // Chỉ từ phím chữ ở plane chữ (space/⌫/shift là button riêng, không tới đây).
    // Chữ vẫn chèn ngay lúc chạm; thành vuốt thì controller huỷ chữ đó (onSwipeBegan),
    // nhấc tay giao đường vuốt (onSwipeEnded). Tắt ⇒ không phân loại, không lưu điểm.

    /// Controller bật theo công tắc + SwipePolicy (ô nhập, iPad, VoiceOver).
    var swipeEnabled = false {
        didSet { if !swipeEnabled, oldValue { cancelSwipeTracking() } }
    }
    /// Touch vừa thành vuốt: huỷ chữ đầu (shift đã được trả lại trước khi gọi).
    var onSwipeBegan: (() -> Void)?
    /// Nhấc tay sau vuốt: đường vuốt (toạ độ self, đã dời như điểm chọn phím) + chữ hoa.
    var onSwipeEnded: ((SwipePath, SwipeCase) -> Void)?

    private var swipeTouchID: ObjectIdentifier?
    private var classifier: GestureClassifier?
    private var swipePath: SwipePath?           // cấp một lần, dùng lại
    private var swipeActive = false
    private var swipeCase: SwipeCase = .lower
    private var lastLetterDownTime: TimeInterval?
    private var trail: SwipeTrail?              // chỉ tạo khi có cú vuốt đầu

    /// Bước phím ngang (tâm q → tâm w), nil nếu chưa có layout chữ.
    private func letterKeyPitch() -> CGFloat? {
        guard letterKeys.count >= 2,
              let q = letterKeys.first(where: { $0.base == "q" })?.button,
              let w = letterKeys.first(where: { $0.base == "w" })?.button else { return nil }
        let d = convert(w.bounds, from: w).midX - convert(q.bounds, from: q).midX
        return d > 1 ? d : nil
    }

    /// Layout cho SwipeDecoder: tâm a–z theo toạ độ KeyboardView thật.
    func swipeLayout() -> SwipeLayout? {
        guard plane == .letters, let kw = letterKeyPitch() else { return nil }
        var m: [Character: (x: Float, y: Float)] = [:]
        for (b, s) in letterKeys {
            guard s.count == 1, let c = s.first else { continue }
            let f = convert(b.bounds, from: b)
            m[c] = (Float(f.midX), Float(f.midY))
        }
        guard m.count == 26 else { return nil }
        return SwipeLayout(keyWidth: Float(kw), centers: m)
    }

    private func startClassifying(_ id: ObjectIdentifier, at p: CGPoint, time: TimeInterval,
                                  key: CGRect, keyWidth kw: CGFloat, since: TimeInterval?) {
        classifier = GestureClassifier(start: p, time: time, startKey: key, keyWidth: kw,
                                       sinceLastLetter: since)
        swipeTouchID = id
        let minD = Float(kw / 5)
        if swipePath?.minDistance != minD { swipePath = SwipePath(minDistance: minD) }
        swipePath?.reset()
        swipePath?.add(x: Float(p.x), y: Float(p.y), t: time)
    }

    private func stopClassifying() {
        classifier = nil
        if !swipeActive { swipeTouchID = nil }
    }

    private func swipeMoved(to raw: CGPoint, time: TimeInterval) {
        let p = TouchGeometry.keySelectionPoint(raw)
        swipePath?.add(x: Float(p.x), y: Float(p.y), t: time)
        if swipeActive {
            trail?.add(raw, time)
            trail?.redraw()
            return
        }
        guard var c = classifier else { return }
        let d = c.move(to: p, time: time)
        classifier = c
        switch d {
        case .swipe: beginSwipe()
        case .tap: stopClassifying()
        case .undecided: break
        }
    }

    private func beginSwipe() {
        swipeActive = true
        classifier = nil
        dropAltHold()
        hideBalloon()
        // Phím chữ đầu đã nhả shift một lần — trả lại để từ vuốt viết hoa đúng.
        if shiftBeforeLastLetter == .on, shift == .off { shift = .on; applyShiftAppearance() }
        swipeCase = shift == .caps ? .upper : (shift == .on ? .capitalized : .lower)
        onSwipeBegan?()
        let t = trail ?? SwipeTrail()
        trail = t
        t.begin(color: palette.trail.ui)
        layer.addSublayer(t.layer)               // lên trên cùng
        if let path = swipePath {
            for i in 0..<path.count {
                t.add(CGPoint(x: CGFloat(path.xs[i]), y: CGFloat(path.ys[i]) + TouchGeometry.yOffset),
                      path.ts[i])
            }
        }
        t.redraw()
    }

    /// Nhấc tay: true nếu touch này là một cú vuốt (đã giao cho controller).
    private func swipeUp(_ id: ObjectIdentifier, at raw: CGPoint, time: TimeInterval) -> Bool {
        guard id == swipeTouchID else { return false }
        guard swipeActive, swipePath != nil else { stopClassifying(); return false }
        let p = TouchGeometry.keySelectionPoint(raw)
        swipePath?.add(x: Float(p.x), y: Float(p.y), t: time, force: true)
        guard let path = swipePath else { return false }
        let sc = swipeCase
        swipeActive = false
        swipeTouchID = nil
        classifier = nil
        trail?.fadeOut(reduceMotion: UIAccessibility.isReduceMotionEnabled)
        if shift == .on { shift = .off; applyShiftAppearance() }
        onSwipeEnded?(path, sc)
        return true
    }

    private func cancelSwipeTracking() {
        swipeActive = false
        swipeTouchID = nil
        classifier = nil
        trail?.fadeOut(reduceMotion: true)
    }

    /// Vệt vuốt: MỘT CAShapeLayer phẳng (không bóng), đuôi ~300ms, không animation
    /// ngầm khi vẽ; nhấc tay mờ dần ~200ms (Reduce Motion: tắt ngay).
    private final class SwipeTrail {
        let layer = CAShapeLayer()
        static let tail: TimeInterval = 0.3
        private static let cap = 128
        private var xs = [CGFloat](repeating: 0, count: cap)
        private var ys = [CGFloat](repeating: 0, count: cap)
        private var ts = [TimeInterval](repeating: 0, count: cap)
        private var head = 0, count = 0

        init() {
            layer.fillColor = nil
            layer.lineWidth = 6
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.shadowOpacity = 0
        }

        func begin(color: UIColor) {
            head = 0; count = 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAllAnimations()
            layer.strokeColor = color.cgColor
            layer.opacity = 1
            layer.path = nil
            CATransaction.commit()
        }

        func add(_ p: CGPoint, _ t: TimeInterval) {
            if count == Self.cap { head = (head + 1) % Self.cap; count -= 1 }
            let i = (head + count) % Self.cap
            xs[i] = p.x; ys[i] = p.y; ts[i] = t
            count += 1
            while count > 2, ts[head] < t - Self.tail { head = (head + 1) % Self.cap; count -= 1 }
        }

        func redraw() {
            let path = CGMutablePath()
            for k in 0..<count {
                let i = (head + k) % Self.cap
                let p = CGPoint(x: xs[i], y: ys[i])
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.path = path
            CATransaction.commit()
        }

        func fadeOut(reduceMotion: Bool) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if reduceMotion {
                layer.path = nil
            } else {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1; a.toValue = 0; a.duration = 0.2
                layer.add(a, forKey: "fade")
                layer.opacity = 0
            }
            CATransaction.commit()
        }
    }


    private func tapped(_ key: Key) {
        if handleSearchKey(key) { return }
        onKey(key)
    }

    #if DEBUG
    /// Test hook: đi một vòng sang plane số rồi về chữ (về từ planeCache).
    func debugCycleThroughNumbers() {
        plane = .numbers; rebuild()
        plane = .letters; rebuild()
    }
    /// Test hook: chạm ☰ (burgerZone — bật/tắt mẫu câu), đúng đường người dùng.
    func debugTapBurger() { toggleTemplates() }
    /// Test hook: mở mẫu câu rồi về chữ (đường của bug 26/09/2026).
    func debugCycleThroughTemplates() {
        plane = .templates; rebuild(); layoutIfNeeded()
        plane = .letters; rebuild()
    }
    /// Test hook: mô phỏng chạm ⌫ tại x, kéo qua các điểm `xs`, rồi nhấc tay.
    /// Trả về nhãn xem trước sau điểm cuối (nil = không hiện).
    @discardableResult
    func debugBackspaceSwipe(from x0: CGFloat, through xs: [CGFloat]) -> String? {
        onBackspaceTouchDown?()
        backspaceSwipeBegan(x: x0)
        tapped(.backspace)
        for x in xs { backspaceSwipeMoved(x: x) }
        let label = wordSwipePill?.isHidden == false ? wordSwipePill?.text : nil
        backspaceSwipeEnded()
        return label
    }
    /// Test hook: payload 3 slot chính đang hiện (nil = ẩn).
    /// Test hook: nút slot `i` (chạm xuống/nhấc tay bằng sendActions).
    func debugSlotControl(_ i: Int) -> UIControl { slotButtons[i] }
    /// Test hook: chữ 3 slot đang hiện (nil = ẩn).
    func debugSlotTitles() -> [String?] {
        zip(slotButtons, suggestionBar.labels).map { $0.isHidden ? nil : $1.text }
    }
    func debugSlotPayloads() -> [String?] {
        slotButtons.map { $0.isHidden ? nil : $0.payload }
    }
    /// Test hook thanh gợi ý: frame (toạ độ KeyboardView) của 3 ô slot + 2 vạch ngăn,
    /// frame chữ các slot đang HIỆN (hiện thật = không ẩn và bar alpha > 0), thẻ Dán.
    func debugSuggestionGeometry() -> (cells: [CGRect], dividers: [CGRect],
                                        visibleTitles: [CGRect], pasteCard: CGRect?) {
        layoutIfNeeded()
        let cells = suggestionBar.cellFrames.map { convert($0, from: suggestionBar) }
        let divs = slotDividers.map { convert($0.bounds, from: $0) }
        let barShown = !suggestionBar.isHidden && suggestionBar.alpha > 0
        var titles: [CGRect] = []
        let shown = Array(zip(slotButtons, suggestionBar.labels.map { $0 as UILabel? }))
            + Array(zip(emojiButtons, emojiButtons.map(\.titleLabel)))
        for (b, l) in shown where barShown && !b.isHidden && !(l?.text ?? "").isEmpty {
            b.layoutIfNeeded()
            if let l { titles.append(convert(l.bounds, from: l)) }
        }
        let card = pasteCard.superview != nil && !pasteCard.isHidden ? pasteCard.frame : nil
        return (cells, divs, titles, card)
    }
    /// Test hook dải gợi ý: frame bar, nút 📋 (nil = ẩn/chưa tạo), chevron, ô slot.
    /// `slots`/`dividers`: frame (toạ độ KeyboardView) các ô / vạch ngăn đang HIỆN.
    func debugStripLayout() -> (bar: CGRect, clip: CGRect?, chevron: CGRect, cells: [CGRect],
                                slots: [CGRect], dividers: [CGRect]) {
        layoutIfNeeded()
        let clip: CGRect? = clipZoneMade && !clipZone.isHidden ? clipZone.frame : nil
        return (suggestionBar.frame, clip, chevronZone.frame,
                suggestionBar.cellFrames.map { convert($0, from: suggestionBar) },
                slotButtons.filter { !$0.isHidden }.map { convert($0.bounds, from: $0) },
                slotDividers.filter { !$0.isHidden }.map { convert($0.bounds, from: $0) })
    }
    /// Test hook: mô phỏng rebuild (đổi plane / xoay) — đường từng đặt lại alpha bar.
    func debugRefreshChrome() { updateSuggestionChrome() }
    /// Test hook trackpad: chạy đúng đường began/moved/frame/ended với thời gian giả;
    /// `frameEvery` = số touch event giữa 2 frame (120Hz touch / 60Hz màn = 2).
    /// `coalesce: false` mô phỏng hành vi cũ (mỗi bước gửi ngay).
    func debugTrackpadDrag(_ pts: [(x: CGFloat, y: CGFloat, t: CFTimeInterval)],
                           frameEvery: Int = 2, coalesce: Bool = true) {
        guard let first = pts.first else { return }
        trackpadBegan(CGPoint(x: first.x, y: first.y), t: first.t)
        for (i, e) in pts.dropFirst().enumerated() {
            trackpadMoved(CGPoint(x: e.x, y: e.y), t: e.t)
            if !coalesce || (i + 1) % max(frameEvery, 1) == 0 { trackpadFrame() }
        }
        trackpadEnded()
    }
    var debugTrackpadDimmed: Bool { trackpadDimmed }
    func debugSetKeyPreview(_ on: Bool) { keyPreviewEnabled = on }
    func debugShowEmojiPlane() { plane = .emoji; rebuild() }
    /// Test hook: chạm ABC của plane emoji (đường onABC thật).
    func debugEmojiABC() {
        (rowsContainer.arrangedSubviews.first { $0 is EmojiPlane } as? EmojiPlane)?.onABC?()
    }
    /// Test hook: frame phím emoji (toạ độ self) ở hàng đáy plane đang hiện.
    var debugEmojiKeyFrame: CGRect? { debugControl("Emoji").map { convert($0.bounds, from: $0) } }
    var debugBalloonVisible: Bool { balloonMade && !balloon.isHidden && balloon.superview != nil }
    /// Test hook: một touch chữ chạm tại `p0`, kéo qua `points` (cách nhau `dt` giây),
    /// nhấc tay ở điểm cuối — đi đúng đường router (routeDown → swipeMoved → routeUp).
    /// Trả true nếu touch thành vuốt.
    @discardableResult
    func debugTouch(from p0: CGPoint, through points: [CGPoint], dt: TimeInterval = 0.016,
                    start t0: TimeInterval) -> Bool {
        let token = NSObject()
        let id = ObjectIdentifier(token)
        routeDown(id, at: p0, time: t0, batch: 1)
        var t = t0
        var swiped = false
        for p in points {
            t += dt
            if swipeTouchID == id { swipeMoved(to: p, time: t) }
            if swipeActive { swiped = true }
        }
        routeUp(id, at: points.last ?? p0, time: t, cancelled: false)
        withExtendedLifetime(token) {}
        return swiped
    }
    /// Test hook giữ phím ký tự phụ: chạm tâm phím `s`, trôi `drift` pt, (tuỳ) hết giờ giữ
    /// (gọi thẳng như timer bắn), rồi nhấc — đường router thật. Trả có hẹn giờ không.
    @discardableResult
    func debugHold(_ s: String, drift: CGFloat = 0, fire: Bool = true, secondTouch: String? = nil) -> Bool {
        guard let f = debugLetterFrame(s) else { return false }
        let token = NSObject(), id = ObjectIdentifier(token)
        let c = CGPoint(x: f.midX, y: f.midY)
        routeDown(id, at: c, time: 1, batch: 1)
        let armed = altHold != nil
        if drift > 0, let h = altHold, h.id == id, altHold?.hold.move(to: CGPoint(x: c.x + drift, y: c.y)) == true {
            dropAltHold()
        }
        if fire { altTimer?.cancel(); fireAltHold() }
        if let s2 = secondTouch, let f2 = debugLetterFrame(s2) {
            let t2 = NSObject(), id2 = ObjectIdentifier(t2)
            routeDown(id2, at: CGPoint(x: f2.midX, y: f2.midY), time: 1.1, batch: 1)
            routeUp(id2, at: CGPoint(x: f2.midX, y: f2.midY), time: 1.2, cancelled: false)
            withExtendedLifetime(t2) {}
        }
        routeUp(id, at: CGPoint(x: c.x + drift, y: c.y), time: 2, cancelled: false)
        withExtendedLifetime(token) {}
        return armed
    }
    /// Test hook giữ phím "," hàng đáy: chạm, (tuỳ) hết giờ giữ, (tuỳ) ngón khác chạm phím chữ
    /// `secondTouch`, rồi nhấc — đường action thật của nút. Trả có hẹn giờ không.
    @discardableResult
    func debugCommaHold(fire: Bool = true, secondTouch: String? = nil, secondBeforeFire: Bool = false) -> Bool {
        guard let b = debugCommaButton else { return false }
        b.sendActions(for: .touchDown)
        let armed = commaTimer != nil
        func second() {
            guard let s2 = secondTouch, let f2 = debugLetterFrame(s2) else { return }
            let t2 = NSObject(), id2 = ObjectIdentifier(t2)
            routeDown(id2, at: CGPoint(x: f2.midX, y: f2.midY), time: 1.1, batch: 1)
            routeUp(id2, at: CGPoint(x: f2.midX, y: f2.midY), time: 1.2, cancelled: false)
            withExtendedLifetime(t2) {}
        }
        if secondBeforeFire { second() }
        if fire, armed { commaTimer?.cancel(); fireCommaHold(b) }   // như timer bắn
        if !secondBeforeFire { second() }
        b.sendActions(for: .touchUpInside)
        return armed
    }
    /// Test hook giữ phím "." ô địa chỉ/URL/email: chạm tâm phím, (tuỳ) hết giờ giữ, trượt
    /// (dx, dy), (tuỳ) ngón khác chạm phím chữ, rồi nhấc — đường action thật. Trả có hẹn giờ không.
    @discardableResult
    func debugDomainHold(_ title: String, fire: Bool = true, dx: CGFloat = 0, dy: CGFloat = 0,
                         secondTouch: String? = nil, keepOpen: Bool = false) -> Bool {
        guard let b = debugButton(title) else { return false }
        let key = convert(b.bounds, from: b)
        domainLastPoint = CGPoint(x: key.midX, y: key.midY)
        b.sendActions(for: .touchDown)
        let armed = domainTimer != nil
        if fire, armed {
            domainTimer?.cancel()
            let tlds = DomainPopup.choices(kind: inputKind, key: title, lettersPlane: plane == .letters)
            if tlds.isEmpty {
                fireDomainHold(b, choices: KeyVariants.variants(
                    for: title, symbolPlane: plane == .numbers || plane == .symbols,
                    numericField: inputKind == .number), variants: true)
            } else {
                fireDomainHold(b, choices: tlds)
            }
        }
        if dx != 0 || dy != 0 { domainMoved(to: CGPoint(x: key.midX + dx, y: key.midY + dy)) }
        if let s2 = secondTouch, let f2 = debugLetterFrame(s2) {
            let t2 = NSObject(), id2 = ObjectIdentifier(t2)
            routeDown(id2, at: CGPoint(x: f2.midX, y: f2.midY), time: 1.1, batch: 1)
            routeUp(id2, at: CGPoint(x: f2.midX, y: f2.midY), time: 1.2, cancelled: false)
            withExtendedLifetime(t2) {}
        }
        if !keepOpen { b.sendActions(for: .touchUpInside) }
        return armed
    }
    private func debugButton(_ title: String) -> KeyButton? {
        func find(_ v: UIView) -> KeyButton? {
            if let b = v as? KeyButton, b.currentTitle == title { return b }
            for s in v.subviews { if let b = find(s) { return b } }
            return nil
        }
        return find(rowsContainer)
    }
    private var debugCommaButton: KeyButton? {
        func find(_ v: UIView) -> KeyButton? {
            if let b = v as? KeyButton, b.currentTitle == "," { return b }
            for s in v.subviews { if let b = find(s) { return b } }
            return nil
        }
        return find(rowsContainer)
    }
    /// Nhãn "." nhỏ trên phím "," (nil = không có nhãn).
    var debugCommaHint: String? {
        guard let b = debugCommaButton else { return nil }
        return b.subviews.compactMap { ($0 as? UILabel) }.first { $0 !== b.titleLabel }?.text
    }
    /// Nhãn ký tự phụ đang vẽ trên phím chữ `s` (nil = không có nhãn).
    func debugAltHint(_ s: String) -> String? {
        guard let b = letterKeys.first(where: { $0.base == s })?.button else { return nil }
        return b.subviews.compactMap { ($0 as? UILabel) }.first { $0 !== b.titleLabel }?.text
    }
    /// Test hook: vào chế độ tìm emoji (như bấm 🔍), gõ từng phím chữ/space qua
    /// đường tapped thật; trả (query, kết quả đang hiện).
    func debugEmojiSearch(_ keys: [Key]) -> (query: String, results: [String]) {
        emojiSearch.clear()
        plane = .emojiSearch; rebuild()
        for k in keys { tapped(k) }
        return (emojiSearch.query, searchBar?.shownResults ?? [])
    }
    var debugInEmojiSearch: Bool { plane == .emojiSearch }
    /// Test hook: màn hình giả (máy gập mở 951×669…) cho KeyLayout.phoneForm khi view chưa có window.
    var debugScreenSize: CGSize? { didSet { phoneFormCache = nil; lastLayoutWidth = -1; setNeedsLayout() } }
    /// Test hook: safe area đáy giả (vạch home máy gập mở = 18).
    func debugSetSafeBottom(_ v: CGFloat) {
        safeBottom = KeyLayout.keyboardSafeBottom(pad: Self.isPad, viewSafeBottom: v)
        updateSuggestionChrome()
    }
    /// Test hook: frame các hàng của plane đang hiện (toạ độ self).
    func debugRowFrames() -> [CGRect] {
        rowsContainer.arrangedSubviews.map { convert($0.bounds, from: $0) }
    }
    /// Test hook: plane chữ ↔ số.
    func debugSetPlane(numbers: Bool) {
        plane = numbers ? .numbers : .letters; rebuild()
    }
    /// Test hook: dấu hiệu trên phím cách — "logo", mã "VI"/"EN", nil = không có.
    func debugSpaceMark() -> String? {
        if let c = spaceCode, c.superview != nil { return c.text }
        if let l = spaceLogo, l.superview != nil { return "logo" }
        return nil
    }
    /// Test hook: button phím text (hàng số / plane số) theo nhãn, trong plane đang hiện.
    func debugKeyButton(_ title: String) -> UIButton? {
        func find(_ v: UIView) -> UIButton? {
            if let b = v as? KeyButton, !b.isSpecial, b.currentTitle == title { return b }
            for s in v.subviews { if let r = find(s) { return r } }
            return nil
        }
        return rowsContainer.arrangedSubviews.lazy.compactMap(find).first
    }
    /// Test hook: frame nút rail một tay đang hiện (toạ độ self).
    func debugRailFrames() -> [CGRect] {
        railButtons.filter { !$0.isHidden }.map { $0.frame }
    }
    /// Test hook: bấm nút rail (0 = đổi bên, 1 = thoát).
    func debugTapRail(_ i: Int) {
        railButtons[i].sendActions(for: .touchUpInside)
    }
    /// Test hook: giữ lâu burger (bật/tắt một tay).
    func debugHoldBurger() { toggleOneHandFromKeyboard() }
    /// Bench hook (KeyboardBenchTests): một chạm phím chữ tại `p` đi đúng đường thật —
    /// hitTest (router) → routeDown (smartPick, sendActions touchDown → chèn) → routeUp.
    func benchTap(at p: CGPoint, time: TimeInterval) {
        _ = hitTest(p, with: nil)
        let token = NSObject()
        let id = ObjectIdentifier(token)
        routeDown(id, at: p, time: time, batch: 1)
        routeUp(id, at: p, time: time + 0.06, cancelled: false)
        withExtendedLifetime(token) {}
    }
    /// Bench hook: phím cách (click + lệnh space như lúc nhấc tay).
    func benchSpace() {
        Self.clickModifier()
        tapped(.space)
    }
    /// Test hook: nút thật theo accessibilityLabel ("Số", "Chữ", "Emoji", "Shift"…).
    /// Test: nhãn từng phím theo hàng (trái → phải): ký tự phím / accessibilityLabel phím
    /// chức năng, ô trống (thụt hàng) = "␣".
    func debugRowLabels() -> [[String]] {
        rowsContainer.arrangedSubviews.map { r in
            ((r as? UIStackView)?.arrangedSubviews ?? []).map { v in
                guard let b = v as? KeyButton else { return "␣" }
                if b.isSpecial || (b.currentTitle ?? "").isEmpty {
                    if let t = b.currentTitle, !t.isEmpty, b.accessibilityLabel == nil { return t }
                    return b.accessibilityLabel ?? b.currentTitle ?? "?"
                }
                return b.currentTitle ?? "?"
            }
        }
    }
    /// Test: ký tự phụ (nhãn xám) của phím có tiêu đề `title`.
    func debugPadHint(_ title: String) -> String? {
        (debugKeyButton(title) as? KeyButton)?.padHint?.text
    }
    /// Test: giả lập vuốt xuống / giữ trên phím có ký tự phụ rồi nhấc → ký tự gõ ra.
    func debugPadAlternate(_ title: String) {
        guard let b = debugKeyButton(title) as? KeyButton else { return }
        b.sendActions(for: .touchDown)
        choosePadAlt(b)
        b.sendActions(for: .touchUpInside)
    }
    /// Test: giả lập hết giờ GIỮ trên một phím có ký tự phụ (đang chạm).
    func debugChoosePadAlt(_ c: UIControl) { if let b = c as? KeyButton { choosePadAlt(b) } }
    /// Test: chạm xuống phím có ký tự phụ có hẹn giờ giữ không (rồi huỷ chạm).
    func debugPadAltArmsOnTouchDown(_ title: String) -> Bool {
        guard let b = debugKeyButton(title) as? KeyButton else { return false }
        b.sendActions(for: .touchDown)
        let armed = b.padAltTimer != nil
        b.sendActions(for: .touchCancel)
        return armed
    }
    func debugControl(_ label: String) -> UIControl? {
        func find(_ v: UIView) -> UIControl? {
            if let c = v as? UIControl, c.accessibilityLabel == label { return c }
            for s in v.subviews { if let r = find(s) { return r } }
            return nil
        }
        return find(rowsContainer)
    }
    var debugPlaneName: String { "\(plane)" }
    var debugShiftOn: Bool { shift != .off }
    var debugShiftCaps: Bool { shift == .caps }
    /// Test hook: hiện balloon trên phím chữ `s` (như chạm / giữ ra ký tự phụ `text`), trả
    /// frame balloon + khung chữ + cỡ chữ (toạ độ self).
    func debugBalloon(letter s: String, text: String) -> (frame: CGRect, label: CGRect, fontSize: CGFloat)? {
        guard let b = letterKeys.first(where: { $0.base == s })?.button else { return nil }
        showBalloon(over: b, text: text, force: true)
        let l = balloon.label
        return (balloon.frame, convert(l.bounds, from: l), l.font.pointSize)
    }
    /// Test hook: chiều cao xin host + vùng hàng (constant constraint).
    var debugRequestedHeight: CGFloat { heightConstraint?.constant ?? 0 }
    var debugRowsTop: CGFloat { rowsTopConstraint?.constant ?? 0 }
    func debugEnterEmojiSearch() { plane = .emojiSearch; rebuild() }
    /// Test hook: frame phím chữ (toạ độ self).
    func debugLetterFrame(_ s: String) -> CGRect? {
        letterKeys.first { $0.base == s }.map { convert($0.button.bounds, from: $0.button) }
    }
    #endif
}


