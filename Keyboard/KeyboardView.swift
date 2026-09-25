// KeyboardView — programmatic UIKit clone of Apple's Vietnamese keyboard.
// M1: letters plane + shift/caps + backspace (with repeat) + 123 plane +
// globe/space/return. Metrics follow Apple's stock layout; the pixel-perfect
// fidelity pass (balloons, exact colors per appearance, iPad) is M2.
import UIKit

final class KeyboardView: UIView, UIInputViewAudioFeedback {

    enum Key {
        case letter(Character)
        case text(String)
        case space
        case doubleSpacePeriod        // "  " fast → ". " (Apple behavior)
        case newline
        case backspace
        case moveCursor(Int)          // space-hold trackpad mode
        case clearField               // nút thùng rác plane mẫu câu → xoá sạch ô
    }

    private enum Plane { case letters, numbers, symbols, emoji, templates }

    /// Gần-trong-suốt nhưng KHÔNG clear: vùng alpha 0 không nhận touch ở cấp hệ thống
    /// (touch rơi sang app host). Dùng cho mọi nền phủ vùng bàn phím.
    static let touchableClear = UIColor(white: 0, alpha: 0.01)

    /// Strip gợi ý khi mở. 36 → 30 (25/09/2026, so ảnh stock: vùng bar stock ≈53pt,
    /// VietTelex ≈59pt — bàn phím cao hơn stock chủ yếu ở đây).
    static let openStrip: CGFloat = 30
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
    private let suggestionBar = UIStackView()
    private var suggestionsEnabled = false

    private var plane: Plane = .letters
    private var shift: ShiftState = .on          // Apple: sentence start = shifted
    private var returnTitle = "return"
    private var dark = false
    private var lastShiftTap: TimeInterval = 0

    private var rowsContainer = UIStackView()
    private var rowsHeightConstraint: NSLayoutConstraint?
    private var rowsMaxHeightConstraint: NSLayoutConstraint?
    private var rowsTopConstraint: NSLayoutConstraint?
    private var repeatTimer: Timer?
    private var lastSuggestionSig = ""
    private var wordDeleteTick = 0
    /// Giữ backspace >3s → xoá theo TỪ (controller đọc proxy, off hot path).
    var onDeleteWord: (() -> Void)?
    private var lastSpaceTap: TimeInterval = 0
    /// Phím nhấc-mới-chốt đang đè — xem KeyCommitQueue (thứ tự khi gõ chồng ngón).
    private let commits = KeyCommitQueue()
    private var spaceHoldX: CGFloat = 0
    private var backspaceHoldStart: TimeInterval = 0

    // Fill đục xấp xỉ stock — alpha-white trên nền trong suốt làm phím
    // đổi sắc theo màu app phía sau.
    private var plainFill: UIColor {
        dark ? UIColor(white: 0.42, alpha: 1) : .white
    }
    private var specialFill: UIColor {
        dark ? UIColor(white: 0.26, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
    }

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
        let rowsTop = rowsContainer.topAnchor.constraint(equalTo: topAnchor, constant: 0)
        rowsTop.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            rowsContainer.leftAnchor.constraint(equalTo: leftAnchor),
            rowsContainer.rightAnchor.constraint(equalTo: rightAnchor),
            rowsHeight,
            rowsMax,
            rowsTop,
            rowsContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
        ])
        rowsHeightConstraint = rowsHeight
        rowsMaxHeightConstraint = rowsMax
        rowsTopConstraint = rowsTop
        // Suggestion bar sống trong "khoảng trống 2" — chỉ hiện khi bật.
        suggestionBar.axis = .horizontal
        suggestionBar.distribution = .fillProportionally
        suggestionBar.spacing = 6
        // KHÔNG margins-relative: fillProportionally + UIViewLayoutMarginsGuide
        // là nguồn cảnh báo "Unexpected referenceItem" của iOS 26 VÀ frame slot
        // tính sai (chevron bấm không ăn). Inset trái/phải đi bằng constraint.
        suggestionBar.translatesAutoresizingMaskIntoConstraints = false
        suggestionBar.isHidden = true
        addSubview(suggestionBar)
        // Bar là HÀNG NỘI DUNG cố định 20pt ghim đỉnh (tâm chữ y=10) — vùng
        // strip phía trên phím do rowsTopConstraint quyết định, bar chỉ nằm đó.
        // Thụt 2 mép chừa chỗ cho burgerZone/chevronZone (ghim cố định) — gợi ý
        // nằm giữa, không bao giờ chồng lên 2 nút mép.
        NSLayoutConstraint.activate([
            suggestionBar.leftAnchor.constraint(equalTo: leftAnchor, constant: Self.stripZoneWidth),
            suggestionBar.rightAnchor.constraint(equalTo: rightAnchor, constant: -Self.stripZoneWidth),
            suggestionBar.topAnchor.constraint(equalTo: topAnchor),
            suggestionBar.heightAnchor.constraint(equalToConstant: 20),
        ])
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { repeatTimer?.invalidate() }

    /// Bật/tắt thanh gợi ý: mở rộng khoảng trống phía trên vừa đủ (44pt).
    func setSuggestionsEnabled(_ on: Bool) {
        suggestionsEnabled = on
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
            self.rowsTopConstraint?.constant = strip
            self.heightConstraint?.constant = self.keyAreaHeight() + strip
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
    private lazy var burgerZone: UIButton = {
        let b = UIButton(type: .custom)
        b.addAction(UIAction { [weak self] _ in self?.toggleTemplates() }, for: .touchUpInside)
        addSubview(b)
        return b
    }()
    private lazy var chevronZone: UIButton = {
        let b = UIButton(type: .custom)
        b.addAction(UIAction { [weak self] _ in self?.toggleBarCollapsed() }, for: .touchUpInside)
        addSubview(b)
        return b
    }()

    /// Đặt lại frame + icon + ẩn/hiện 2 nút mép theo trạng thái bar. Gọi mỗi
    /// layoutSubviews. Chiều cao lấy từ HẰNG SỐ constraint (rowsTop), KHÔNG từ
    /// frame — frame có thể chưa kịp cập nhật trong cùng pass → strip=0 → tịt.
    private func layoutStripZones() {
        let open = suggestionsEnabled && !barCollapsed && plane != .emoji
        burgerZone.isHidden = !open || !templatesEnabled
        chevronZone.isHidden = !open
        guard open, bounds.width > 0 else { return }
        let strip = max(rowsTopConstraint?.constant ?? Self.openStrip, Self.openStrip)
        let w = Self.stripZoneWidth
        burgerZone.frame = CGRect(x: 0, y: 0, width: w, height: strip)
        chevronZone.frame = CGRect(x: bounds.width - w, y: 0, width: w, height: strip)
        let ink = (dark ? UIColor.white : .black)
        burgerZone.setImage(UIImage(systemName: "line.3.horizontal",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
        burgerZone.tintColor = ink.withAlphaComponent(templatesActive ? 0.9 : 0.45)
        burgerZone.accessibilityLabel = templatesActive ? "Đóng mẫu câu" : "Mẫu câu"
        chevronZone.setImage(UIImage(systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        chevronZone.tintColor = ink.withAlphaComponent(0.45)
        chevronZone.accessibilityLabel = "Thu gọn thanh gợi ý"
        chevronZone.imageView?.transform = .identity   // bar mở = chevron xuôi
        // Icon canh giữa trong vùng 20pt TRÊN CÙNG (tâm y≈10) để khớp chữ gợi ý,
        // thay vì canh giữa cả strip 36 (tâm y≈18 → icon thấp hơn chữ, user 2026-07-25).
        let bottomInset = max(strip - 20, 0)
        burgerZone.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        chevronZone.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        bringSubviewToFront(burgerZone)
        bringSubviewToFront(chevronZone)
    }

    private func refreshCollapseButton(visible: Bool) {
        // Nút nổi chỉ hiện khi THU GỌN; bar mở dùng slot trong bar.
        let floating = visible && barCollapsed
        collapseButton.isHidden = !floating
        floatingBurger.isHidden = !floating || !templatesEnabled
        if floating {
            floatingBurgerIcon?.image = UIImage(systemName: "line.3.horizontal",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
            floatingBurgerIcon?.tintColor = (dark ? UIColor.white : .black).withAlphaComponent(0.45)
            floatingBurger.accessibilityLabel = "Mẫu câu"
        }
        let chevImg = UIImage(systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        let ink = (dark ? UIColor.white : .black).withAlphaComponent(0.45)
        if floating {
            // 18 = strip 14 + margin hàng phím (phím bắt đầu ở 19) — mục tiêu
            // to hơn mà không cướp tap phím.
            chevronHeight?.constant = 18
            chevronIconY?.constant = 7
            chevronIcon?.image = chevImg      // một icon duy nhất, xoay bằng transform
            chevronIcon?.tintColor = ink
            collapseButton.accessibilityLabel = "Mở thanh gợi ý"
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

    /// iPhone 216pt dọc / 162pt ngang; iPad 240/300 — GỌN hơn stock (264/352)
    /// theo ý user 2026-07-24, phím vẫn rộng thoải mái nhờ bề ngang iPad.
    /// Tổng key area = base + rowHeightAdjust × 4 hàng — heightConstraint và
    /// rowsContainer cùng đi qua đây nên tổng luôn khớp từng hàng.
    private func keyAreaHeight() -> CGFloat {
        let landscape: Bool
        if let o = window?.windowScene?.interfaceOrientation {
            landscape = o.isLandscape
        } else {
            landscape = UIDevice.current.userInterfaceIdiom == .phone && bounds.width > 500
        }
        let base: CGFloat
        if UIDevice.current.userInterfaceIdiom == .pad {
            base = landscape ? 300 : 240
        } else {
            // 216 → 218 (25/09/2026): phím nhỉnh hơn chút; 224 làm cả bàn phím cao
            // hơn stock (user) — phần dư của stock nằm ở vùng đáy, không phải hàng phím.
            base = landscape ? 162 : 218
        }
        return base + rowHeightAdjust * 4
    }

    // Gắn vào window mới biết interfaceOrientation thật — ép layout lại để
    // chiều cao đúng ngay pass đầu (và sau khi host xoay lúc keyboard ẩn).
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { lastLayoutWidth = -1; setNeedsLayout() }
    }

    /// Strip gợi ý chỉ hiện khi bật VÀ đang ở plane chữ/số — trong emoji plane
    /// ẩn đi cho gọn (user 2026-07-24). strip 30pt sát nút; phần dưới hàng
    /// phím cuối là vùng globe/mic hệ thống, không thuộc view mình.
    private func updateSuggestionChrome() {
        let visible = suggestionsEnabled && plane != .emoji
        // Strip 36 mở (bar 20pt ghim đỉnh, chữ tâm 10 — cộng ~22pt inset hệ
        // thống phía trên cửa sổ thì gần giữa vùng tối) / 14 thu gọn / 0 tắt.
        let strip: CGFloat = visible ? (barCollapsed ? 14 : Self.openStrip) : 0
        let keyArea = keyAreaHeight()
        rowsTopConstraint?.constant = strip
        heightConstraint?.constant = keyArea + strip
        rowsHeightConstraint?.constant = keyArea
        rowsMaxHeightConstraint?.constant = keyArea + 60
        suggestionBar.isHidden = !visible || barCollapsed
        suggestionBar.alpha = 1
        if !visible || barCollapsed { pasteCard.isHidden = true }   // thu gọn / emoji plane
        lastSuggestionSig = ""   // chrome đổi → lượt show kế ghi lại (kể cả thẻ Dán)
        refreshCollapseButton(visible: visible)
    }

    // Rotation / Split View: indent hàng 2 và chiều cao tính theo bounds THẬT,
    // không dùng UIScreen.main (deprecated, sai trong Split View).
    private var lastLayoutWidth: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            updateSuggestionChrome()
            if let r = indentedRow {
                let inset = 3 + indentedRowInset * bounds.width / 10
                r.layoutMargins = UIEdgeInsets(top: 5, left: inset, bottom: 5, right: inset)
            }
        }
        layoutStripZones()   // sau super.layoutSubviews → frame slot bar đã đúng
        if pasteCard.superview != nil, !pasteCard.isHidden {   // xoay màn hình
            let w = Self.stripZoneWidth
            pasteCard.frame = CGRect(x: w, y: 0, width: max(bounds.width - 2 * w, 0),
                                     height: Self.openStrip)
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
        var paste = false               // slot 1 = nút "Dán" (vừa copy, xem controller)
        var isEmpty: Bool {
            literal == nil && word == nil && word2 == nil && emojis.isEmpty && nextWords.isEmpty
        }
    }

    // Pool cố định: 3 nút chính + 2 divider + 3 nút emoji con. Mỗi keystroke
    // CHỈ đổi title/hidden — không removeFromSuperview/addSubview (churn view +
    // Auto Layout invalidate mỗi phím chính là nguồn lag/miss touch).
    private var slotButtons: [KeyButton] = []
    private var slotDividers: [UIView] = []
    private var emojiStack = UIStackView()
    private var emojiButtons: [KeyButton] = []

    private func buildSuggestionPoolIfNeeded() {
        guard slotButtons.isEmpty else { return }
        // Bar 20pt trong strip openStrip → nút nở hit-area xuống ĐÚNG phần còn lại
        // của strip (30−20 = 10pt), không lấn hàng phím Q–P bên dưới.
        let barHit = UIEdgeInsets(top: -8, left: -3, bottom: -(Self.openStrip - 20), right: -3)
        func makeSlot() -> KeyButton {
            let b = KeyButton(type: .custom)
            b.backgroundColor = .clear
            b.isMultipleTouchEnabled = true
            b.hitInsets = barHit
            b.addAction(UIAction { [weak self, weak b] _ in
                if let s = b?.payload { self?.onSuggestion?(s) }
            }, for: .touchUpInside)
            return b
        }
        // Burger + chevron KHÔNG còn nằm trong bar (fillProportionally khiến
        // chúng nở/trôi vào giữa khi hết gợi ý — bug user 2026-07-25). Giờ là 2
        // nút ghim cố định ở mép: burgerZone / chevronZone (xem layoutStripZones).
        func makeDivider() -> UIView {
            let v = UIView()
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 1).isActive = true
            let line = UIView()
            line.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(line)
            NSLayoutConstraint.activate([
                line.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                line.widthAnchor.constraint(equalToConstant: 1),
                line.topAnchor.constraint(equalTo: v.topAnchor, constant: 4),
                line.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
            ])
            line.tag = 77   // line lookup (tag phải nằm trên LINE, không phải wrapper)
            return v
        }
        emojiStack.axis = .horizontal
        emojiStack.distribution = .fillEqually
        for _ in 0..<3 {
            let b = makeSlot()
            b.titleLabel?.font = .systemFont(ofSize: 20)   // vừa content box 22pt
            emojiButtons.append(b)
            emojiStack.addArrangedSubview(b)
        }
        for i in 0..<3 {
            let b = makeSlot()
            slotButtons.append(b)
            suggestionBar.addArrangedSubview(b)
            if i < 2 {
                let d = makeDivider()
                slotDividers.append(d)
                suggestionBar.addArrangedSubview(d)
            }
        }
        suggestionBar.addArrangedSubview(emojiStack)
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

    private var userTemplates = KeyboardView.templates
    private var templatesEnabled = true
    private var templatesActive: Bool { plane == .templates }
    /// Chèn thẳng vào input, KHÔNG qua máy học từ (câu nhiều từ làm bẩn model).
    var onTemplate: ((String) -> Void)?
    /// Bubble ⚙️ cuối lưới → controller mở tab Mẫu Câu của app.
    var onOpenTemplates: (() -> Void)?

    private func toggleTemplates() {
        guard templatesEnabled else { return }
        Self.clickModifier()
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

    func showSuggestions(_ set: SuggestionSet) {
        guard suggestionsEnabled, !barCollapsed else { return }
        buildSuggestionPoolIfNeeded()

        // gom nội dung 3 slot chính: nextWords HOẶC literal/word/word2
        var texts: [(display: String, insert: String)?] = [nil, nil, nil]
        if !set.nextWords.isEmpty {
            for (i, w) in set.nextWords.prefix(3).enumerated() { texts[i] = (w, w) }
        } else {
            if let l = set.literal { texts[0] = ("\u{201C}\(l)\u{201D}", l) }
            if let w = set.word { texts[1] = (w, w) }
            if set.emojis.isEmpty, let w2 = set.word2 { texts[2] = (w2, w2) }
        }
        // Nội dung không đổi (nextWords thường ổn định giữa các phím) → bỏ qua
        // toàn bộ ghi UI: setTitle trên bar fillProportionally kéo theo một
        // lượt đo text/Auto Layout mỗi keystroke.
        let sig = (dark ? "D" : "L")
            + texts.map { $0.map { $0.display + "\u{1}" + $0.insert } ?? "\u{2}" }.joined(separator: "\u{3}")
            + "\u{4}" + (set.nextWords.isEmpty ? set.emojis.prefix(3).joined() : "")
            + (set.paste ? "\u{5}paste" : "")
        if sig == lastSuggestionSig { return }
        lastSuggestionSig = sig

        let ink: UIColor = dark ? .white : .black
        for d in slotDividers {
            d.viewWithTag(77)?.backgroundColor = ink.withAlphaComponent(0.18)
        }
        for (i, b) in slotButtons.enumerated() {
            if let t = texts[i] {
                b.setTitle(t.display, for: .normal)
                b.setTitleColor(ink, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
                b.payload = t.insert
                b.isHidden = false
            } else {
                b.isHidden = true
                b.payload = nil
            }
        }
        // slot emoji (chỉ ở chế độ đang gõ, khi có emoji)
        let emojis = set.nextWords.isEmpty ? Array(set.emojis.prefix(3)) : []
        for (i, b) in emojiButtons.enumerated() {
            if i < emojis.count {
                b.setTitle(emojis[i], for: .normal)
                b.payload = emojis[i]
                b.isHidden = false
            } else {
                b.isHidden = true; b.payload = nil
            }
        }
        emojiStack.isHidden = emojis.isEmpty
        // divider hiện giữa các slot đang hiển thị
        let vis0 = !(slotButtons[0].isHidden), vis1 = !(slotButtons[1].isHidden)
        let vis2 = !(slotButtons[2].isHidden) || !emojiStack.isHidden
        slotDividers[0].isHidden = !(vis0 && (vis1 || vis2))
        slotDividers[1].isHidden = !(vis1 && vis2)
        // Nút Dán kiểu iOS 27: MỘT ô rộng giữa bar, 2 dòng, thay cả 3 slot.
        setPasteCard(visible: set.paste, ink: ink)
    }

    // MARK: Nút Dán (iOS 27 style, 25/09/2026)
    // Stock hiện nội dung clipboard + "Paste from <App>" — bàn phím bên thứ ba KHÔNG
    // làm vậy được: đọc nội dung = iOS báo/hỏi quyền dán MỖI lần bàn phím hiện, và
    // app nguồn không lộ cho extension. Nên: "Dán" / "Nội dung vừa copy".
    private lazy var pasteCard: KeyButton = {
        let b = KeyButton(type: .custom)
        b.backgroundColor = .clear
        b.hitInsets = UIEdgeInsets(top: -8, left: 0, bottom: 0, right: 0)
        b.accessibilityLabel = "Dán nội dung vừa copy"
        let title = UILabel(), sub = UILabel()
        title.text = "Dán"
        title.font = .systemFont(ofSize: 15, weight: .regular)
        sub.text = "Nội dung vừa copy"
        sub.font = .systemFont(ofSize: 11, weight: .regular)
        title.tag = 91; sub.tag = 92
        let icon = UIImageView(image: UIImage(systemName: "doc.on.clipboard",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)))
        icon.tag = 93
        let text = UIStackView(arrangedSubviews: [title, sub])
        text.axis = .vertical; text.alignment = .leading; text.spacing = -1
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal; row.alignment = .center; row.spacing = 8
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: b.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: b.centerYAnchor),
        ])
        b.payload = Self.pasteToken
        b.addAction(UIAction { [weak self, weak b] _ in
            Self.clickModifier()
            if let p = b?.payload { self?.onSuggestion?(p) }
        }, for: .touchUpInside)
        return b
    }()

    private func setPasteCard(visible: Bool, ink: UIColor) {
        if visible {
            if pasteCard.superview == nil { addSubview(pasteCard) }
            let w = Self.stripZoneWidth
            pasteCard.frame = CGRect(x: w, y: 0, width: max(bounds.width - 2 * w, 0),
                                     height: Self.openStrip)
            (pasteCard.viewWithTag(91) as? UILabel)?.textColor = ink
            (pasteCard.viewWithTag(92) as? UILabel)?.textColor = ink.withAlphaComponent(0.55)
            (pasteCard.viewWithTag(93) as? UIImageView)?.tintColor = ink.withAlphaComponent(0.8)
            bringSubviewToFront(pasteCard)
        }
        pasteCard.isHidden = !visible
        suggestionBar.alpha = visible ? 0 : 1
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
        rebuild()
    }

    /// Loại ô nhập (từ textDocumentProxy.keyboardType) → đổi layout như stock:
    /// number mở thẳng plane số; email đổi hàng đáy thành phím @ và . ; url
    /// thành . / .com. Chỉ ảnh hưởng hàng đáy plane CHỮ + plane mở đầu.
    enum InputKind { case normal, number, email, url }
    private var inputKind: InputKind = .normal

    func configureInputKind(_ kind: InputKind) {
        inputKind = kind
        plane = (kind == .number) ? .numbers : .letters
        if plane == .letters, shift == .on { shift = .off }
        planeCache.removeAll()          // hàng đáy đổi theo kind → cache cũ sai
        builtPlane = nil                // ép rebuild dù plane không đổi (email/url
                                        // giữ .letters → guard cũ return sớm)
        rebuild()
    }

    func applyAppearance(_ appearance: UIKeyboardAppearance) {
        // Hầu hết host truyền .default — phải dò trait hệ thống, nếu không
        // bàn phím sáng trưng trên máy dark mode.
        dark = (appearance == .dark)
            || (appearance != .light && traitCollection.userInterfaceStyle == .dark)
        // Chiều cao hàng phím ±10pt (Settings → Giao diện) — đọc mỗi lần hiện.
        let adj = UserDefaultsProvider.shared?.object(forKey: "rowHeightAdjust") as? Int ?? 0
        rowHeightAdjust = CGFloat(max(-10, min(10, adj)))
        // Mẫu câu: danh sách user tự quản trong app + toggle bật/tắt.
        let d = UserDefaultsProvider.shared
        templatesEnabled = d?.object(forKey: "templatesEnabled") == nil
            || d?.bool(forKey: "templatesEnabled") == true
        if let raw = d?.array(forKey: "userTemplates") as? [[String: String]] {
            userTemplates = raw.compactMap { e in
                guard let t = e["text"], !t.isEmpty else { return nil }
                return (e["label"] ?? "", t)
            }
        } else {
            userTemplates = Self.templates
        }
        if !templatesEnabled, plane == .templates { plane = .letters }
        rebuild()
    }

    /// needsInputModeSwitchKey chỉ đáng tin SAU khi extension nối host —
    /// đánh giá lại ở viewWillAppear; đổi thì dựng lại hàng đáy.
    func setNeedsGlobe(_ on: Bool) {
        guard on != needsGlobe else { return }
        needsGlobe = on
        builtPlane = nil        // ép rebuild dù plane/dark/return không đổi
        rebuild()
    }

    /// Sentence-start auto-shift (only upgrades OFF→ON; never downgrades CAPS).
    func setAutoShift(_ on: Bool) {
        guard shift != .caps else { return }
        let want: ShiftState = on ? .on : .off
        if shift != want { shift = want; applyShiftAppearance() }
    }


    // Shift changes must NEVER rebuild: tearing the buttons down mid-typing
    // deallocates the key already under the user's finger, so its touch-up
    // never fires (the missed-keypress bug). Retitle in place instead.
    private var letterKeys: [(button: UIButton, base: String)] = []
    private weak var spaceBar: UIButton?
    private weak var spaceLogo: UIImageView?
    private weak var indentedRow: UIStackView?
    private var indentedRowInset: CGFloat = 0
    private var shiftKey: KeyButton?
    private func applyShiftAppearance() {
        for (b, s) in letterKeys {
            b.setTitle(shift == .off ? s : s.uppercased(), for: .normal)
        }
        if let b = shiftKey {
            let symbol = shift == .caps ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift")
            b.setImage(UIImage(systemName: symbol), for: .normal)
            // Shift ON/CAPS = phím đảo màu (nền trắng, glyph đen) như stock —
            // cả dark mode, nếu không ON và OFF trông y hệt nhau.
            if shift != .off {
                b.backgroundColor = .white
                b.tintColor = .black
            } else {
                b.backgroundColor = specialFill
                b.tintColor = dark ? .white : .black
            }
            b.normalBackground = b.backgroundColor
        }
    }


    // MARK: layout

    // Dedupe: rebuild bị gọi 3 lần mỗi lần hiện (init, configureReturnKey,
    // applyAppearance) — chỉ xé/dựng lại khi có gì đó thật sự đổi.
    private var builtPlane: Plane?
    private var builtReturn = ""
    private var builtDark = false
    private var builtWidth: CGFloat = -1

    // Cache view theo plane: bấm 123/#+=/ABC chỉ tráo arrangedSubviews thay vì
    // xé/dựng lại ~40 button + constraints mỗi lần. Emoji KHÔNG cache (recents
    // phải tươi mỗi lần mở). Đổi return/dark/width → mọi plane cache đều sai
    // nhãn/màu/inset nên vứt hết.
    private struct CachedPlane {
        let rows: [UIView]
        let letterKeys: [(button: UIButton, base: String)]
        let shiftKey: KeyButton?
        let spaceBar: UIButton?
        let spaceLogo: UIImageView?
        let indentedRow: UIStackView?
        let indentedRowInset: CGFloat
    }
    private var planeCache: [Plane: CachedPlane] = [:]

    private func rebuild() {
        updateSuggestionChrome()
        if builtPlane == plane, builtReturn == returnTitle,
           builtDark == dark, builtWidth == bounds.width { return }
        if builtReturn != returnTitle || builtDark != dark || builtWidth != bounds.width {
            planeCache.removeAll()
        } else if let old = builtPlane, old != .emoji, old != .templates {
            // KHÔNG cache emoji/templates: cả hai đổi distribution sang .fill và
            // dựng layout tự do; khôi phục từ cache (distribution đã bị reset về
            // .fillEqually + constraint chiều cao hàng đáy còn treo) làm plane
            // mẫu câu lần 2 co dúm (bug user 2026-07-25). Dựng lại rẻ.
            planeCache[old] = CachedPlane(
                rows: rowsContainer.arrangedSubviews, letterKeys: letterKeys,
                shiftKey: shiftKey, spaceBar: spaceBar, spaceLogo: spaceLogo,
                indentedRow: indentedRow, indentedRowInset: indentedRowInset)
        }
        builtPlane = plane; builtReturn = returnTitle
        builtDark = dark; builtWidth = bounds.width
        letterKeys.removeAll()
        shiftKey = nil
        rowsContainer.distribution = .fillEqually
        rowsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let cached = planeCache[plane] {
            cached.rows.forEach { rowsContainer.addArrangedSubview($0) }
            letterKeys = cached.letterKeys
            shiftKey = cached.shiftKey
            spaceBar = cached.spaceBar
            spaceLogo = cached.spaceLogo
            indentedRow = cached.indentedRow
            indentedRowInset = cached.indentedRowInset
            // shift có thể đã đổi trong lúc plane này nằm ngoài màn hình
            if plane == .letters { applyShiftAppearance() }
            return
        }
        switch plane {
        case .letters: buildLetters()
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
        }
    }

    /// Plane mẫu câu (burger menu): BUBBLE chips dàn dòng như tag cloud
    /// (user 2026-07-24 — đỡ tốn chỗ hơn mỗi câu một hàng), cuộn dọc, câu dài
    /// truncate "…", có label thì bubble chỉ hiện label. Hàng đáy giữ
    /// [ABC][space][return] để quay lại như plane số.
    private func buildTemplates() {
        rowsContainer.distribution = .fill
        let chips = TemplateChipsView(items: userTemplates, dark: dark,
                                      plainFill: plainFill,
                                      ink: dark ? .white : .black,
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
        bottom.heightAnchor.constraint(equalToConstant: keyAreaHeight() / 4).isActive = true
    }

    /// Lưới bubble mẫu câu — flow layout tự dàn dòng, self-sizing chips.
    private final class TemplateChipsView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
        private let items: [(label: String, text: String)]
        private let dark: Bool
        private let fill: UIColor
        private let ink: UIColor
        private let onTap: (String) -> Void
        private let onGear: () -> Void

        init(items: [(label: String, text: String)], dark: Bool,
             plainFill: UIColor, ink: UIColor,
             onTap: @escaping (String) -> Void, onGear: @escaping () -> Void) {
            self.items = items
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
            items.count + 1
        }

        func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "chip", for: ip) as! ChipCell
            if ip.item == items.count {
                cell.set(display: "⚙️", fill: fill, ink: ink, dark: dark)
                cell.accessibilityLabel = "Quản lý mẫu câu"
            } else {
                let item = items[ip.item]
                cell.set(display: item.label.isEmpty ? item.text : item.label,
                         fill: fill, ink: ink, dark: dark)
            }
            return cell
        }

        func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
            if ip.item == items.count { onGear() } else { onTap(items[ip.item].text) }
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
        let r1 = "qwertyuiop".map { String($0) }
        let r2 = "asdfghjkl".map { String($0) }
        let r3 = "zxcvbnm".map { String($0) }
        rowsContainer.addArrangedSubview(row(r1.map(letterButton)))
        // Apple indents row 2 by half a key on iPhone.
        rowsContainer.addArrangedSubview(row(r2.map(letterButton), sideInset: 0.5))
        let shiftBtn = shiftButton()
        let r3btns = r3.map(letterButton)     // z x c v b n m
        let backBtn = backspaceButton()
        var third: [UIView] = [shiftBtn]
        third += r3btns
        third.append(backBtn)
        rowsContainer.addArrangedSubview(row(third))
        // Lưới 10 cột như stock: shift + backspace = 1.5 phím chữ → 1.5+7+1.5=10,
        // Z thẳng dưới A/S và M thẳng dưới K (user 2026-07-25).
        if let z = r3btns.first {
            shiftBtn.widthAnchor.constraint(equalTo: z.widthAnchor, multiplier: 1.5).isActive = true
            backBtn.widthAnchor.constraint(equalTo: z.widthAnchor, multiplier: 1.5).isActive = true
        }
        rowsContainer.addArrangedSubview(bottomRow(planeKey: "123"))
    }

    // Emoji plane render theo stock (video 2026-07-24): search bar + lưới
    // cuộn ngang column-major theo category + hàng [ABC][icons][⌫].
    // rowsContainer là fillEqually — plane emoji cần layout tự do nên đổi
    // distribution sang .fill khi vào plane này (rebuild() phục hồi).
    private func buildEmoji() {
        rowsContainer.distribution = .fill
        let plane = EmojiPlane(dark: dark)
        plane.onEmoji = { [weak self] e in self?.tapped(.text(e)) }
        plane.onABC = { [weak self] in
            guard let self else { return }
            self.plane = .letters
            self.rebuild()
        }
        plane.onBackspace = { [weak self] in self?.tapped(.backspace) }
        rowsContainer.addArrangedSubview(plane)
    }

    private func buildPlane(rows planeRows: [[String]], moreKey: String, altKey: String) {
        rowsContainer.addArrangedSubview(row(planeRows[0].map(textButton)))
        rowsContainer.addArrangedSubview(row(planeRows[1].map(textButton)))
        let more = controlButton(title: moreKey) { [weak self] in
            guard let self else { return }
            self.plane = (self.plane == .numbers) ? .symbols : .numbers
            self.rebuild()
        }
        more.accessibilityLabel = moreKey == "#+=" ? "Ký hiệu" : "Số"
        var third: [UIView] = [more]
        third += [".",",","?","!","'"].map(textButton)
        third.append(backspaceButton())
        rowsContainer.addArrangedSubview(row(third, proportional: true))
        rowsContainer.addArrangedSubview(bottomRow(planeKey: altKey))
    }

    private func bottomRow(planeKey: String, clearInsteadOfEmoji: Bool = false) -> UIView {
        var views: [UIView] = []
        let planeBtn = controlButton(title: planeKey) { [weak self] in
            guard let self else { return }
            self.plane = (self.plane == .letters) ? .numbers : .letters
            if self.plane == .letters, self.shift == .on { self.shift = .off }
            self.rebuild()
        }
        planeBtn.accessibilityLabel = planeKey == "123" ? "Số" : "Chữ"
        views.append(planeBtn)
        // globe sát bên phải [123] như stock (muscle memory), emoji sau đó
        if needsGlobe {
            let globe = baseButton(title: "", special: true)
            globe.setImage(UIImage(systemName: "globe"), for: .normal)
            globe.tintColor = dark ? .white : .black
            globe.accessibilityLabel = "Bàn phím tiếp theo"
            if let c = inputController {
                // hợp đồng Apple: event thật + allTouchEvents để long-press
                // mở keyboard picker hoạt động
                globe.addTarget(c, action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                                for: .allTouchEvents)
            }
            views.append(globe)
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
            emojiBtn.tintColor = dark ? .white : .black
            emojiBtn.accessibilityLabel = "Xoá ô nhập"
        } else {
            emojiBtn = controlButton(title: "") { [weak self] in
                guard let self else { return }
                self.plane = .emoji
                self.rebuild()
            }
            emojiBtn.setImage(UIImage(systemName: "face.smiling.inverse",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
            emojiBtn.tintColor = dark ? .white : .black
            emojiBtn.accessibilityLabel = "Emoji"
        }
        views.append(emojiBtn)
        let space = baseButton(title: "", special: true)
        space.backgroundColor = plainFill
        space.normalBackground = plainFill
        space.pressedBackground = specialFill      // space sẫm lại khi đè
        space.accessibilityLabel = "Dấu cách"
        spaceBar = space
        // logo Vᴛ mờ ở mép phải nút space (thay "VI EN" — user 2026-07-23);
        // PNG 2x/3x render từ MenuIcon.pdf nên sắc nét, tint theo appearance.
        // Ẩn được qua Settings của app (showSpaceLogo, App Group).
        let showLogo = UserDefaultsProvider.shared?.object(forKey: "showSpaceLogo") == nil
            || UserDefaultsProvider.shared?.bool(forKey: "showSpaceLogo") == true
        if showLogo {
            let hint = UIImageView(image: UIImage(named: "SpaceLogo")?.withRenderingMode(.alwaysTemplate))
            hint.tintColor = (dark ? UIColor.white : .black).withAlphaComponent(0.16)
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
        space.addAction(UIAction { _ in Self.clickModifier() }, for: .touchDown)
        space.addTarget(self, action: #selector(spaceTouchDown(_:event:)), for: .touchDown)
        // Chốt qua KeyCommitQueue: arm lúc chạm, chốt lúc nhấc / bị huỷ / khi ngón
        // khác chạm xuống trước (gõ chồng ngón). touchUpOutside CŨNG chốt: ngón trượt
        // khỏi mép lúc nhấc là chuyện thường. Trackpad (spaceHold) disarm.
        armCommit(space) { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if now - self.lastSpaceTap < 0.35 {
                self.tapped(.doubleSpacePeriod)
            } else {
                self.tapped(.space)
            }
            self.lastSpaceTap = now
        }
        let spacePan = UILongPressGestureRecognizer(target: self, action: #selector(spaceHold(_:)))
        spacePan.minimumPressDuration = 0.4
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
        // đổi thành phím tắt như stock (@ . cho email; . / .com cho url). Chỉ áp
        // ở hàng đáy plane CHỮ (planeKey == "123").
        let puncts: [(title: String, insert: String, mult: CGFloat)]
        if planeKey == "123" {
            switch inputKind {
            case .email: puncts = [("@", "@", 0.11), (".", ".", 0.09)]
            case .url:   puncts = [(".", ".", 0.075), ("/", "/", 0.075), (".com", ".com", 0.17)]
            default:     puncts = [(",", ",", 0.075)]
            }
        } else {
            puncts = [(",", ",", 0.075)]
        }
        var punctKeys: [(btn: KeyButton, mult: CGFloat)] = []
        for p in puncts {
            let b = baseButton(title: p.title, special: false)
            b.pressedBackground = specialFill
            if p.title == ".com" { b.titleLabel?.font = .systemFont(ofSize: 17) }
            armCommit(b) { [weak self] in self?.tapped(.text(p.insert)) }
            views.append(b)
            punctKeys.append((b, p.mult))
        }
        let ret = controlButton(title: returnTitle == "return" ? "" : returnTitle,
                                armed: true) { [weak self] in
            self?.tapped(.newline)
        }
        ret.accessibilityLabel = returnTitle == "return" ? "Xuống dòng" : returnTitle
        if returnTitle == "return" {
            ret.setImage(UIImage(systemName: "return.left",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
            // mờ ngang logo Vᴛ trên spacebar (user 2026-07-23)
            ret.tintColor = (dark ? UIColor.white : .black).withAlphaComponent(0.16)
        } else {
            // Return dạng HÀNH ĐỘNG (go/search/send/done…): nút XANH nổi bật +
            // chữ trắng như stock (Safari search…), thay vì xám lẫn phím thường.
            ret.backgroundColor = .systemBlue
            ret.normalBackground = .systemBlue
            ret.pressedBackground = UIColor.systemBlue.withAlphaComponent(0.7)
            ret.setTitleColor(.white, for: .normal)
            ret.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            // "go"/"search" (Safari, Gmail…): stock hiện MŨI TÊN → trắng, không chữ.
            if returnTitle == "go" || returnTitle == "search" {
                ret.setTitle("", for: .normal)
                ret.setImage(UIImage(systemName: "arrow.right",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
                ret.tintColor = .white
            }
        }
        views.append(ret)
        // iPad: phím ẩn bàn phím góc phải dưới như stock
        var dismissBtn: KeyButton?
        if UIDevice.current.userInterfaceIdiom == .pad {
            let d = baseButton(title: "", special: true)
            d.setImage(UIImage(systemName: "keyboard.chevron.compact.down",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
            d.tintColor = dark ? .white : .black
            d.accessibilityLabel = "Ẩn bàn phím"
            d.addAction(UIAction { _ in Self.clickModifier() }, for: .touchDown)
            d.addAction(UIAction { [weak self] _ in
                self?.inputController?.dismissKeyboard()
            }, for: .touchUpInside)
            dismissBtn = d
            views.append(d)
        }

        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        // Hàng đáy SÁT đáy hơn như stock (so ảnh 25/09/2026: stock cách đáy bàn phím
        // 214px, VietTelex 241px): cùng chiều cao phím, dời xuống 3pt (top 8/bottom 2
        // thay 5/5). Vùng globe/mic dưới đó do host vẽ — không dời được.
        stack.layoutMargins = UIEdgeInsets(top: 10, left: 3, bottom: 0, right: 3)
        planeBtn.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.12).isActive = true
        emojiBtn.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.10).isActive = true
        for pk in punctKeys {
            pk.btn.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: pk.mult).isActive = true
        }
        ret.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.14).isActive = true
        dismissBtn?.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.07).isActive = true
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
        stack.spacing = 6
        stack.distribution = proportional ? .fillProportionally : .fill
        stack.isLayoutMarginsRelativeArrangement = true
        // bounds.width có thể = 0 lúc init — layoutSubviews chỉnh lại ngay
        // pass đầu (và sau mỗi lần xoay / đổi cỡ Split View)
        let unit = bounds.width / 10
        stack.layoutMargins = UIEdgeInsets(top: 5, left: 3 + sideInset * unit,
                                           bottom: 5, right: 3 + sideInset * unit)
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
        var normalBackground: UIColor?
        var pressedBackground: UIColor?   // nil = không đổi màu khi đè (phím chữ dùng balloon)
        /// Hit-area tuỳ biến (âm = nở rộng). Slot trên bar 20pt cần nở XUỐNG
        /// 16pt phủ hết strip 36 — tâm ngón tay hay rơi dưới đáy bar là vùng
        /// chết, nguồn của "chevron/burger bấm mãi không ăn".
        var hitInsets: UIEdgeInsets?
        // Khe hở giữa phím (spacing 6 + padding hàng 5) là VÙNG CHẾT với
        // UIButton thường — chạm trúng khe = mất phím. Stock keyboard route
        // mọi điểm chạm về phím gần nhất; mở rộng hit area phủ nửa khe cho
        // hiệu quả tương đương, không đổi kiến trúc touch.
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if let i = hitInsets { return bounds.inset(by: i).contains(point) }
            return bounds.insetBy(dx: -3, dy: -5.5).contains(point)
        }
        // Bóng phím KHÔNG dùng layer.shadow*: không shadowPath thì Core Animation
        // render offscreen alpha của layer mỗi frame (~35 phím, 120 Hz = GPU/pin);
        // có shadowPath thì CA vẽ bóng mềm hơn ~1px (đo pixel-diff simulator) —
        // lệch hình. Thay bằng 2 sublayer phẳng dưới title/icon: dropLayer (đen,
        // lệch xuống 1pt = shadowOffset, radius 0) + faceLayer (màu nền phím).
        // Thứ tự vẽ y hệt bóng thật (bóng dưới, nền trên) → pixel như cũ, không
        // offscreen pass. backgroundColor đi vào faceLayer (override bên dưới) nên
        // mọi chỗ gán b.backgroundColor (pressed, shift, return) giữ nguyên.
        private var faceLayer: CALayer?
        private var dropLayer: CALayer?
        private var faceColor: UIColor?
        private static let noActions: [String: CAAction] = [
            "backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull(),
            "frame": NSNull(), "cornerRadius": NSNull(), "hidden": NSNull(),
        ]
        func setKeyShadow(opacity: CGFloat) {
            if faceLayer == nil {
                let drop = CALayer(), face = CALayer()
                drop.actions = Self.noActions; face.actions = Self.noActions
                layer.insertSublayer(drop, at: 0)
                layer.insertSublayer(face, above: drop)
                dropLayer = drop; faceLayer = face
                super.backgroundColor = nil   // màu nền đã nằm trong faceColor
                setNeedsLayout()
            }
            dropLayer?.backgroundColor = UIColor.black.withAlphaComponent(opacity).cgColor
            applyFace()
        }
        override var backgroundColor: UIColor? {
            get { faceLayer == nil ? super.backgroundColor : faceColor }
            set {
                faceColor = newValue
                if faceLayer == nil { super.backgroundColor = newValue } else { applyFace() }
            }
        }
        private func applyFace() {
            faceLayer?.backgroundColor = faceColor?.resolvedColor(with: traitCollection).cgColor
        }
        override func traitCollectionDidChange(_ previous: UITraitCollection?) {
            super.traitCollectionDidChange(previous)
            applyFace()   // màu động (.systemBlue của return) theo light/dark
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let face = faceLayer, let drop = dropLayer else { return }
            // UIButton chèn imageView/titleLabel ở index 0 khi tạo lười (setImage
            // sau init) → kéo 2 layer nền về đáy lại, không thì che mất icon.
            if layer.sublayers?.first !== drop {
                layer.insertSublayer(drop, at: 0)
                layer.insertSublayer(face, above: drop)
            }
            let r = layer.cornerRadius
            if face.frame != bounds || face.cornerRadius != r {
                face.frame = bounds; face.cornerRadius = r
                drop.frame = bounds.offsetBy(dx: 0, dy: 1); drop.cornerRadius = r
            }
        }
    }

    private func baseButton(title: String, special: Bool) -> KeyButton {
        // .custom, not .system: system buttons run tint/highlight animations on
        // the main thread per touch — visible latency on a keyboard.
        let b = KeyButton(type: .custom)
        // ĐẦU TIÊN trong mọi touchDown (kể cả phím chữ qua router sendActions): chốt
        // các phím nhấc-mới-chốt đang đè TRƯỚC khi phím này làm gì — đúng thứ tự
        // khi gõ chồng ngón (KeyCommitQueue).
        b.addAction(UIAction { [weak self, weak b] _ in
            self?.commits.flush(except: b.map(ObjectIdentifier.init))
        }, for: .touchDown)
        b.isMultipleTouchEnabled = true
        b.isSpecial = special
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: special ? 16 : 23)
        b.layer.cornerRadius = 5
        b.setTitleColor(dark ? .white : .black, for: .normal)
        b.backgroundColor = special ? specialFill : plainFill
        b.normalBackground = b.backgroundColor
        // bóng 1pt không offscreen — xem KeyButton.setKeyShadow
        b.setKeyShadow(opacity: dark ? 0.30 : 0.35)
        // Pressed state cho phím chức năng: swap màu phẳng, KHÔNG
        // UIView.animate — animation per-touch trên main thread là latency
        // thấy được trên bàn phím (lý do dùng .custom ở trên).
        if special { b.pressedBackground = plainFill }
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
    private static let haptic = UIImpactFeedbackGenerator(style: .light)
    private static func feedback() {
        UIDevice.current.playInputClick()
        if hapticsEnabled {
            haptic.impactOccurred()
            haptic.prepare()   // giữ Taptic Engine sẵn sàng cho phím kế — không trễ rung
        }
    }
    static func clickLetter() { feedback() }
    static func clickDelete() { feedback() }
    static func clickModifier() { feedback() }

    private func letterButton(_ s: String) -> UIView {
        let title = (shift == .off) ? s : s.uppercased()
        let b = baseButton(title: title, special: false)
        // Touch của phím CHỮ do router (touchesBegan/Ended của KeyboardView)
        // điều phối — nearest-key, không thể miss. Button chỉ còn là visual +
        // hộp action được sendActions() kích.
        b.isUserInteractionEnabled = false
        letterKeys.append((b, s))
        // Chèn NGAY touch-down như stock iOS: chữ lên tức thì, không phụ thuộc
        // vào việc giao touch-up (main thread bận → touch-up trễ → "phím không
        // ăn"). Rollover vẫn đúng vì mỗi down tự chèn ký tự của nó.
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            Self.clickLetter()                       // feedback tức thì
            self.showBalloon(over: b, text: b.currentTitle ?? title)
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
        func present(keyRect: CGRect, text: String, dark: Bool, topLimit: CGFloat) {
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
                let r: CGFloat = 9, kr: CGFloat = 5, neckY = min(bubbleH + 12, H)
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
            }
            shape.fillColor = (dark ? UIColor(white: 0.35, alpha: 1) : .white).cgColor
            label.textColor = dark ? .white : .black
            label.text = text
            isHidden = false
        }
    }

    private let balloon = BalloonView()
    private func showBalloon(over key: UIView, text: String) {
        let f = convert(key.bounds, from: key)
        // Strip gợi ý (36 mở / 14 thu gọn) = headroom phía trên hàng phím đầu —
        // cho balloon leo vào đó thay vì kẹp sát -6.
        let topLimit: CGFloat = (rowsTopConstraint?.constant ?? 0) > 0 ? 0 : -6
        if balloon.superview == nil { addSubview(balloon) }
        balloon.present(keyRect: f, text: text, dark: dark, topLimit: topLimit)
    }
    private func hideBalloon() { balloon.isHidden = true }

    private func textButton(_ s: String) -> UIView {
        let b = baseButton(title: s, special: false)
        b.addAction(UIAction { [weak self, weak b] _ in
            Self.clickLetter()
            if let self, let b { self.showBalloon(over: b, text: s) }
        }, for: .touchDown)
        b.addAction(UIAction { [weak self] _ in self?.hideBalloon() },
                    for: [.touchUpInside, .touchUpOutside, .touchCancel])
        armCommit(b) { [weak self] in self?.tapped(.text(s)) }
        return b
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

    private func controlButton(title: String, armed: Bool = false,
                               action: @escaping () -> Void) -> KeyButton {
        let b = baseButton(title: title, special: true)
        b.addAction(UIAction { _ in Self.clickModifier() }, for: .touchDown)
        if armed { armCommit(b, fire: action) }
        else { b.addAction(UIAction { _ in action() }, for: [.touchUpInside, .touchUpOutside]) }
        return b
    }

    private func shiftButton() -> UIView {
        let symbol = shift == .caps ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift")
        let b = baseButton(title: "", special: true)
        b.setImage(UIImage(systemName: symbol), for: .normal)
        b.accessibilityLabel = "Shift"
        if shift != .off {
            b.backgroundColor = .white
            b.tintColor = .black
        } else {
            b.tintColor = dark ? .white : .black
        }
        b.normalBackground = b.backgroundColor
        shiftKey = b
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
        b.setImage(UIImage(systemName: "delete.left.fill"), for: .highlighted)
        b.tintColor = dark ? .white : .black
        b.accessibilityLabel = "Xoá"
        b.addAction(UIAction { [weak self] _ in
            Self.clickDelete()
            self?.tapped(.backspace)
        }, for: .touchDown)
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
            backspaceHoldStart = CACurrentMediaTime()
            wordDeleteTick = 0
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                guard let self else { return }
                // Apple accelerates a sustained hold: ~1.6s cadence doubles,
                // ~3s chuyển sang xoá theo từ (~2.8 từ/s).
                let held = CACurrentMediaTime() - self.backspaceHoldStart
                if held > 3.0, let deleteWord = self.onDeleteWord {
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

    @objc private func spaceTouchDown(_ sender: UIControl, event: UIEvent) {
        TouchLog.buttonDown("space", touchTimestamp: event.allTouches?.first(where: { $0.view === sender })?.timestamp)
    }

    /// Space-hold = trackpad mode: sliding left/right moves the caret,
    /// one position per ~9pt of travel (stock feel).
    @objc private func spaceHold(_ g: UILongPressGestureRecognizer) {
        let x = g.location(in: self).x
        switch g.state {
        case .began:
            spaceHoldX = x
            setTrackpadDimmed(true)
            // Trackpad = không gõ: nhả ra KHÔNG có dấu cách (stock), kể cả khi
            // chưa di con trỏ. cancelsTouchesInView=false nên touchUpInside vẫn tới.
            if let v = g.view { commits.disarm(ObjectIdentifier(v)) }
        case .changed:
            let delta = Int((x - spaceHoldX) / 9)
            if delta != 0 {
                tapped(.moveCursor(delta))
                spaceHoldX = x
            }
        case .ended, .cancelled, .failed:
            setTrackpadDimmed(false)
        default: break
        }
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

    /// Stock iOS flashes the layout name ("English (US)") on the spacebar when
    /// the keyboard appears. Same here: "ViệtTelex" for ~700ms, then fade.
    func showLanguageBadge() {
        guard let space = spaceBar else { return }
        let l = UILabel()
        l.text = "ViệtTelex"
        l.font = .systemFont(ofSize: 16, weight: .regular)
        l.textColor = dark ? .white : .black
        l.translatesAutoresizingMaskIntoConstraints = false
        spaceLogo?.isHidden = true     // logo Vᴛ nhường chỗ, khỏi đè lên badge
        space.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: space.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: space.centerYAnchor),
        ])
        UIView.animate(withDuration: 0.3, delay: 0.7, options: [.curveEaseOut]) {
            l.alpha = 0
        } completion: { [weak self] _ in
            l.removeFromSuperview()
            self?.spaceLogo?.isHidden = false
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
        // Phím chữ ưu tiên trong FOOTPRINT thật của nó, kể cả khi hit-area nở của
        // shift/backspace kề bên "cướp" điểm chạm — nếu không, chạm mép z/m thành
        // toggle shift / xoá thay vì ra chữ (nguồn rớt phím ở hàng 3, 2026-07-26).
        if plane == .letters, letterCoreContains(point) { return self }
        if v is UIControl { return v }
        if v != nil, nearestLetterButton(at: point) != nil { return self }
        return v
    }

    private func letterCoreContains(_ point: CGPoint) -> Bool {
        guard point.y >= rowsContainer.frame.minY else { return false }
        for (b, _) in letterKeys where convert(b.bounds, from: b).contains(point) {
            return true
        }
        return false
    }

    private func nearestLetterButton(at point: CGPoint) -> UIButton? {
        // Chỉ route touch TRONG vùng phím — touch ở strip gợi ý phía trên là
        // của chevron/slot, router mà cướp thì chevron "bấm mãi không ăn".
        guard plane == .letters, !letterKeys.isEmpty,
              point.y >= rowsContainer.frame.minY else { return nil }
        var best: (UIButton, CGFloat)?
        for (b, _) in letterKeys {
            let f = convert(b.bounds, from: b)
            if f.insetBy(dx: -3, dy: -5.5).contains(point) { return b }
            let dx = max(f.minX - point.x, 0, point.x - f.maxX)
            let dy = max(f.minY - point.y, 0, point.y - f.maxY)
            let d = dx * dx + dy * dy
            if best == nil || d < best!.1 { best = (b, d) }
        }
        // chỉ nhận khi thật sự gần hàng phím chữ (~nửa chiều cao phím)
        if let (b, d) = best, d <= 21 * 21 { return b }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = TouchGeometry.keySelectionPoint(t.location(in: self))
            let b = nearestLetterButton(at: p)
            TouchLog.touchBegan(active: routedTouches.count, batch: touches.count,
                                touchTimestamp: t.timestamp, hit: b != nil, y: Double(p.y),
                                key: b?.currentTitle)
            guard let b else { continue }
            routedTouches[ObjectIdentifier(t)] = b
            b.sendActions(for: .touchDown)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let b = routedTouches.removeValue(forKey: ObjectIdentifier(t))
            TouchLog.touchEnded(cancelled: false, routed: b != nil)
            guard let b else { continue }
            b.sendActions(for: .touchUpInside)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // hệ thống cancel (edge gesture…) — vẫn CHỐT chữ thay vì nuốt phím
        for t in touches {
            let b = routedTouches.removeValue(forKey: ObjectIdentifier(t))
            TouchLog.touchEnded(cancelled: true, routed: b != nil)
            guard let b else { continue }
            b.sendActions(for: .touchUpInside)
        }
    }

    private func tapped(_ key: Key) { onKey(key) }
}
