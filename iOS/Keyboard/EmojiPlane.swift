// EmojiPlane — bàn phím emoji render theo đúng cấu trúc bàn phím US stock
// (đối chiếu video 2026-07-24): lưới emoji lớn
// cuộn NGANG column-major liên tục theo category, hàng dưới
// [ABC][icon 9 category][⌫] với category đang xem được highlight tròn.
// Recents (🕐) lưu App Group, tối đa 30. (Search bar đã bỏ — user 2026-07-24.)
// 27/09/2026: tab kaomoji / ký tự đặc biệt (^‿^) ở cuối dãy category.
// 27/09/2026 (góp ý user: emoji bé, sát nhau): bỏ tiêu đề nhóm nhỏ trên lưới; THANH TÌM
// luôn hiện trên cùng như iOS 26/27 gốc (chạm → KeyboardView dựng ô tìm + phím chữ);
// 28/09/2026 (Hữu Đông: emoji vẫn bé hơn stock): glyph / bước ô / ô tìm / hàng category
// đo khớp stock từng loại máy (iPhone dọc-ngang, iPad dọc-ngang) — EmojiGridMetrics.
// 29/09/2026 (tester 1.2.x): hàng category trải ĐỀU hết bề ngang như stock ([ABC] trái,
// icon chia đều, [⌫] phải — trước đây ABC nằm ở chỗ phím emoji nên icon dồn sang phải);
// emoji to hơn chút + thoáng hơn (bước ô rộng hơn, số hàng chọn theo bước dọc mục tiêu).
import UIKit

/// Hình học lưới emoji (thuần) — số đo bàn phím emoji stock iOS 26/27 (simulator
/// 28/09/2026, XCUITest frame + đo pixel glyph; góp ý Hữu Đông "emoji vẫn bé hơn stock"):
///
/// | máy               | glyph (bbox) | bước ngang | bước dọc     | hàng | ô tìm | hàng category |
/// |-------------------|--------------|------------|--------------|------|-------|---------------|
/// | iPhone 17 dọc     | 29.3pt       | 46         | 38.7         | 5    | 40    | 40            |
/// | iPhone 17 ngang   | 29.3pt       | 40         | 45.3         | 3    | 40    | 41            |
/// | iPad Pro 11" dọc  | 44pt         | 62         | 76           | 3    | —(🔍 ở hàng dưới) | 56 |
/// | iPad Pro 11" ngang| 44pt         | 63         | 59.7         | 5    | —     | 56            |
///
/// Glyph là cỡ CỐ ĐỊNH theo loại máy (Apple Color Emoji: bbox ≈ 0.917 × pointSize — stock dùng đúng
/// 32pt / 48pt = khung phím emoji stock), không co theo ô như trước (ô 41pt iPad → glyph 28pt so với stock 44pt).
/// Bước ngang cố định như stock; bước dọc = chiều cao lưới chia đều cho số hàng lớn
/// nhất mà mỗi hàng ≥ `minPitchH` (bàn phím mình KHÔNG cao thêm khi vào emoji — host
/// relayout, xem KeyboardView.updateSuggestionChrome — nên thường ít hàng hơn stock).
///
/// 29/09/2026: glyph +2pt (iPhone 34 / iPad 52) và bước ngang rộng hơn stock chút (khe ≥ 16pt
/// như stock), số hàng = gần `pitchH` nhất (không dưới `minPitchH`) — bàn phím mình thấp hơn
/// stock nên nhồi đủ hàng tối thiểu làm lưới dày đặc (góp ý "emoji sát nhau").
/// RAM không đổi: cache glyph CoreText ~8,5 KB/emoji ở MỌI cỡ (RAM-AUDIT.md §4), ô to hơn
/// ⇒ mỗi trang vẽ ÍT emoji hơn.
struct EmojiGridMetrics: Equatable {
    struct Spec: Equatable {
        /// pointSize glyph emoji (bbox thật ≈ 0.917×).
        let font: CGFloat
        let pitchW: CGFloat
        /// Bước dọc mục tiêu (chọn số hàng gần nhất) và sàn.
        let pitchH: CGFloat
        let minPitchH: CGFloat
        let maxRows: Int
        /// Lề trái trước cột đầu; khe THÊM giữa hai nhóm (stock tách nhóm rộng hơn).
        let lead: CGFloat
        let sectionGap: CGFloat
        /// Chiều cao ô tìm trên cùng (0 = không có — iPad: 🔍 nằm ở hàng category như stock).
        let searchField: CGFloat
        /// Hàng [ABC][category][⌫] (gồm 2pt đệm đáy).
        let categoryRow: CGFloat
        let iconPoint: CGFloat
    }

    static let phonePortrait = Spec(font: 34, pitchW: 50, pitchH: 46, minPitchH: 40, maxRows: 5,
                                    lead: 6, sectionGap: 16, searchField: 40, categoryRow: 40,
                                    iconPoint: 18)
    /// Ngang: bàn phím chỉ 162pt ⇒ giữ ô tìm / hàng category gọn (32/34) để còn 2–3 hàng.
    static let phoneLandscape = Spec(font: 32, pitchW: 46, pitchH: 42, minPitchH: 38, maxRows: 5,
                                     lead: 6, sectionGap: 18, searchField: 32, categoryRow: 34,
                                     iconPoint: 16)
    static let padPortrait = Spec(font: 52, pitchW: 70, pitchH: 70, minPitchH: 60, maxRows: 5,
                                  lead: 16, sectionGap: 30, searchField: 0, categoryRow: 50,
                                  iconPoint: 22)
    static let padLandscape = Spec(font: 52, pitchW: 72, pitchH: 66, minPitchH: 58, maxRows: 5,
                                   lead: 18, sectionGap: 32, searchField: 0, categoryRow: 50,
                                   iconPoint: 22)

    static func spec(pad: Bool, landscape: Bool) -> Spec {
        pad ? (landscape ? padLandscape : padPortrait)
            : (landscape ? phoneLandscape : phonePortrait)
    }

    static let minRows = 2
    /// Khoảng từ đỉnh plane tới ô tìm, và từ ô tìm tới lưới.
    static let searchTop: CGFloat = 6, gridGap: CGFloat = 2

    /// Chiều cao lưới từ chiều cao plane (khớp constraint của EmojiPlane): trên = ô tìm
    /// (iPhone) hoặc 4pt (iPad), dưới = hàng category + 2pt khe + 2pt đáy.
    static func gridHeight(planeHeight h: CGFloat, spec: Spec, pad: Bool) -> CGFloat {
        let top = pad ? 4 : searchTop + spec.searchField + gridGap
        return max(h - top - (spec.categoryRow + 2), 0)
    }

    let rows: Int
    let cellW: CGFloat
    let cellH: CGFloat
    let fontSize: CGFloat

    static func compute(gridHeight h: CGFloat, spec: Spec = phonePortrait) -> EmojiGridMetrics {
        let h = max(h, 0)
        // Gần bước mục tiêu nhất, nhưng không dày hơn sàn minPitchH.
        var rows = Int((h / spec.pitchH).rounded())
        let fit = Int((h / spec.minPitchH).rounded(.down))
        rows = min(max(min(rows, fit), minRows), spec.maxRows)
        let cellH = max((h / CGFloat(rows) * 2).rounded(.down) / 2, 1)   // nửa pt: khỏi rớt hàng
        // Lưới quá thấp (ép tối thiểu 2 hàng) thì glyph co theo ô, không tràn.
        let font = min(spec.font, (min(cellH, spec.pitchW) * 0.92).rounded())
        return EmojiGridMetrics(rows: rows, cellW: spec.pitchW, cellH: cellH, fontSize: font)
    }
}

final class EmojiPlane: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    var onEmoji: ((String) -> Void)?
    var onABC: (() -> Void)?
    var onBackspace: (() -> Void)?
    /// Bấm 🔍 — KeyboardView chuyển sang chế độ tìm emoji.
    var onSearch: (() -> Void)?
    /// Chạm một kaomoji / ký tự đặc biệt — chèn nguyên văn (không vào Recents).
    var onKaomoji: ((String) -> Void)?

    private var dark = false
    /// Một nhóm của lưới: category = id vào emoji.bin (không giữ String), Recents = chuỗi.
    struct Section {
        let name: String
        let ids: [UInt16]
        let strings: [String]
        init(name: String, ids: [UInt16]) { self.name = name; self.ids = ids; strings = [] }
        init(name: String, strings: [String]) { self.name = name; ids = []; self.strings = strings }
        var count: Int { strings.isEmpty ? ids.count : strings.count }
        subscript(i: Int) -> String { strings.isEmpty ? EmojiData.emoji(Int(ids[i])) : strings[i] }
    }
    private var sections: [Section] = []
    private var collection: UICollectionView!
    /// Ảnh emoji app chủ vẽ sẵn (EmojiAtlas) — nil ⇒ vẽ chữ như cũ. Mở TRƯỚC reloadSections:
    /// lọc glyph hỏi atlas thay vì CoreText.
    private(set) var atlas: EmojiAtlasStore?
    private var categoryButtons: [CategoryButton] = []
    private var kaomojiButton: CategoryButton?

    /// Ô icon category: vùng chạm = cả ô chia đều; highlight = CHẤM TRÒN giữa ô như stock
    /// (không phải viên thuốc giãn theo bề ngang ô — iPad ô ~64pt).
    private final class CategoryButton: UIButton {
        let ring = UIView()
        override init(frame: CGRect) {
            super.init(frame: frame)
            ring.isUserInteractionEnabled = false
            insertSubview(ring, at: 0)
        }
        required init?(coder: NSCoder) { fatalError() }
        var ringColor: UIColor = .clear { didSet { ring.backgroundColor = ringColor } }
        override func layoutSubviews() {
            super.layoutSubviews()
            let d = max(min(bounds.height - 4, bounds.width - 2, 40), 0)
            ring.frame = CGRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
            ring.layer.cornerRadius = d / 2
            sendSubviewToBack(ring)
        }
    }
    private var kaomojiView: KaomojiView?
    private var repeatTimer: Timer?

    private static let recentsKey = "emojiRecents"
    private static let categoryIcons: [String] = [
        "clock", "face.smiling", "hare", "fork.knife", "soccerball",
        "car.fill", "lightbulb", "heart", "flag",
    ]
    /// Thanh tìm luôn hiện trên cùng (chạm → onSearch).
    private(set) var searchField: UIControl!

    /// Chỗ phím emoji vừa bấm (toạ độ KeyboardView; plane cùng mép trái + đáy):
    /// minX, maxX, top = khoảng từ đáy lên đỉnh phím. ABC đặt ĐÚNG cột đó —
    /// bấm nhầm emoji thì chạm lại chỗ cũ là về chữ (Phil 26/09/2026, chốt lại 30/09).
    struct ABCSlot: Equatable { var minX: CGFloat; var maxX: CGFloat; var top: CGFloat }
    private let abcSlot: ABCSlot?
    private(set) var abcButton: UIButton?
    private weak var categoryRowView: UIStackView?

    /// Vùng chạm nở lên tới đỉnh phím emoji cũ và sang trái tới mép bàn phím.
    private final class ABCButton: UIButton {
        var hitRect: CGRect?   // toạ độ superview
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard let r = hitRect, let sv = superview else { return super.point(inside: point, with: event) }
            return r.contains(convert(point, to: sv))
        }
    }

    /// iPad: không ô tìm trên cùng — 🔍 nằm ở hàng category như stock iPad.
    let pad: Bool
    private(set) var spec: EmojiGridMetrics.Spec
    private var searchHeight: NSLayoutConstraint?
    private var rowHeight: NSLayoutConstraint?

    init(dark: Bool, abcSlot: ABCSlot? = nil,
         pad: Bool = UIDevice.current.userInterfaceIdiom == .pad) {
        self.abcSlot = abcSlot
        self.pad = pad
        self.spec = EmojiGridMetrics.spec(pad: pad, landscape: false)
        super.init(frame: .zero)
        self.dark = dark
        isMultipleTouchEnabled = true
        atlas = EmojiAtlas.loadForKeyboard(scale: UIScreen.main.scale, pad: pad)
        reloadSections()
        buildSearchField()
        buildCollection()
        buildCategoryRow()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { repeatTimer?.invalidate() }

    // UserDefaults.standard: không Full Access → iOS cấm GHI App Group từ
    // extension (ghi group fail âm thầm — recents từng mất qua phiên vì vậy).
    private var recents: [String] { Self.recents }
    static var recents: [String] {
        UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    private func reloadSections() {
        var s: [Section] = []
        let r = recents
        if !r.isEmpty { s.append(Section(name: "recents", strings: r)) }
        s.append(contentsOf: EmojiData.categories.map { Section(name: $0.name, ids: $0.ids) })
        sections = s
    }

    private func noteUsed(_ e: String) { Self.noteUsed(e) }
    /// Dùng chung với kết quả tìm emoji (KeyboardView).
    static func noteUsed(_ e: String) {
        var r = recents.filter { $0 != e }
        r.insert(e, at: 0)
        if r.count > 30 { r.removeLast(r.count - 30) }
        UserDefaults.standard.set(r, forKey: recentsKey)
    }

    // MARK: UI

    /// Ô tìm dạng viên thuốc như stock iOS 26/27 ("Tìm emoji" + kính lúp). Không
    /// phải ô nhập thật (extension không có bàn phím cho chính nó): chạm là sang chế
    /// độ tìm (EmojiSearchBar + phím chữ VietTelex).
    private func buildSearchField() {
        let ink: UIColor = dark ? .white : .black
        if pad {
            // iPad stock: 🔍 là một nút ở hàng category (buildCategoryRow chèn sau ABC).
            let b = UIButton(type: .custom)
            b.setImage(UIImage(systemName: "magnifyingglass",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: spec.iconPoint, weight: .medium)),
                for: .normal)
            b.tintColor = ink
            b.accessibilityLabel = L("Tìm emoji")
            b.accessibilityTraits = .searchField
            b.addAction(UIAction { [weak self] _ in
                KeyboardView.clickModifier()
                self?.onSearch?()
            }, for: .touchUpInside)
            searchField = b
            return
        }
        let f = UIControl()
        // ≈ tertiarySystemFill (118,118,128) — nền ô tìm stock trên bàn phím.
        f.backgroundColor = UIColor(red: 118 / 255, green: 118 / 255, blue: 128 / 255,
                                    alpha: dark ? 0.24 : 0.12)
        f.layer.cornerRadius = spec.searchField / 2
        f.accessibilityLabel = L("Tìm emoji")
        f.accessibilityTraits = .searchField
        f.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)))
        icon.tintColor = ink.withAlphaComponent(0.5)
        let label = UILabel()
        label.text = L("Tìm emoji")
        label.font = .systemFont(ofSize: 17)
        label.textColor = ink.withAlphaComponent(0.5)
        for v in [icon, label] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.isUserInteractionEnabled = false
            f.addSubview(v)
        }
        f.addAction(UIAction { [weak self] _ in
            KeyboardView.clickModifier()
            self?.onSearch?()
        }, for: .touchUpInside)
        addSubview(f)
        searchField = f
        let fh = f.heightAnchor.constraint(equalToConstant: spec.searchField)
        searchHeight = fh
        NSLayoutConstraint.activate([
            f.topAnchor.constraint(equalTo: topAnchor, constant: EmojiGridMetrics.searchTop),
            f.leftAnchor.constraint(equalTo: leftAnchor, constant: 8),
            f.rightAnchor.constraint(equalTo: rightAnchor, constant: -8),
            fh,
            icon.leftAnchor.constraint(equalTo: f.leftAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: f.centerYAnchor),
            label.leftAnchor.constraint(equalTo: icon.rightAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: f.centerYAnchor),
        ])
    }

    private var metrics = EmojiGridMetrics.compute(gridHeight: 0)

    private func buildCollection() {
        let layout = EmojiGridLayout()
        layout.scrollDirection = .horizontal        // column-major như stock
        layout.minimumLineSpacing = 0               // khe = khoảng trắng quanh glyph
        layout.minimumInteritemSpacing = 0
        // lề trái / khe giữa nhóm theo stock: collectionView(_:layout:insetForSectionAt:)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.disableKeyboardEdgeEffects()
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.isMultipleTouchEnabled = true
        // Không dựng/vẽ trước cột ngoài màn hình: mỗi emoji MỚI vẽ ra để lại ~8,5 KB cache glyph
        // CoreText suốt đời process (RAM-AUDIT.md §4) — chỉ vẽ cái người dùng thật sự lướt tới.
        collection.isPrefetchingEnabled = false
        // Long-press emoji có skin tone → popup 6 biến thể (cancelsTouchesInView
        // mặc định true nên tap thường không bị chèn kèm emoji gốc).
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(cellHold(_:)))
        hold.minimumPressDuration = 0.35
        collection.addGestureRecognizer(hold)
        addSubview(collection)
        NSLayoutConstraint.activate([
            pad ? collection.topAnchor.constraint(equalTo: topAnchor, constant: 4)
                : collection.topAnchor.constraint(equalTo: searchField.bottomAnchor,
                                                  constant: EmojiGridMetrics.gridGap),
            collection.leftAnchor.constraint(equalTo: leftAnchor),
            collection.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    private func buildCategoryRow() {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.alignment = .center
        row.spacing = 0
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        row.translatesAutoresizingMaskIntoConstraints = false

        let ink: UIColor = dark ? .white : .black
        let abc = ABCButton(type: .custom)
        abc.setTitle("ABC", for: .normal)
        abc.setTitleColor(ink, for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        abc.addAction(UIAction { [weak self] _ in
            KeyboardView.clickModifier()
            self?.onABC?()
        }, for: .touchDown)
        abc.accessibilityLabel = L("Chữ")
        abcButton = abc
        if let slot = abcSlot {
            // ABC nằm ngoài stack, ĐÚNG cột phím emoji (layoutSubviews đặt frame); stack chừa
            // chỗ tới hết cột đó bằng spacer — icon chia đều phần còn lại tới ⌫. Phần trái cột
            // (chỗ phím 123) thuộc vùng chạm của ABC.
            let spacer = UIView()
            spacer.widthAnchor.constraint(equalToConstant: max(slot.maxX - row.layoutMargins.left, 0)).isActive = true
            row.addArrangedSubview(spacer)
            addSubview(abc)
        } else {
            // Không biết chỗ phím emoji (mở bằng code): như stock, ABC sát mép trái.
            row.addArrangedSubview(abc)
            abc.widthAnchor.constraint(equalToConstant: Self.edgeKeyWidth(pad: pad)).isActive = true
        }

        if pad {
            row.addArrangedSubview(searchField)
            searchField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        }

        let iconsStack = UIStackView()
        iconsStack.axis = .horizontal
        iconsStack.distribution = .fillEqually
        for (i, name) in Self.categoryIcons.enumerated() {
            let b = CategoryButton(type: .custom)
            b.setImage(UIImage(systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: spec.iconPoint, weight: .medium)), for: .normal)
            b.tintColor = ink.withAlphaComponent(0.55)
            b.addAction(UIAction { [weak self] _ in self?.jumpToCategory(i) }, for: .touchUpInside)
            categoryButtons.append(b)
            iconsStack.addArrangedSubview(b)
        }
        let kao = CategoryButton(type: .custom)
        kao.setTitle("^‿^", for: .normal)
        kao.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        kao.titleLabel?.adjustsFontSizeToFitWidth = true
        kao.setTitleColor(ink.withAlphaComponent(0.55), for: .normal)
        kao.accessibilityLabel = L("Kaomoji và ký tự đặc biệt")
        kao.addAction(UIAction { [weak self] _ in self?.showKaomoji() }, for: .touchUpInside)
        kaomojiButton = kao
        iconsStack.addArrangedSubview(kao)
        row.addArrangedSubview(iconsStack)
        // Ô icon cao hết hàng (row căn giữa theo intrinsic) ⇒ chấm highlight tròn đủ lớn.
        iconsStack.heightAnchor.constraint(equalTo: row.heightAnchor).isActive = true

        let del = UIButton(type: .custom)
        del.setImage(UIImage(systemName: "delete.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        del.tintColor = ink
        del.addAction(UIAction { [weak self] _ in
            KeyboardView.clickDelete()
            self?.onBackspace?()
        }, for: .touchDown)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(backspaceHold(_:)))
        long.minimumPressDuration = 0.5
        del.addGestureRecognizer(long)
        del.accessibilityLabel = L("Xoá")
        row.addArrangedSubview(del)
        del.widthAnchor.constraint(equalToConstant: Self.edgeKeyWidth(pad: pad)).isActive = true

        addSubview(row)
        categoryRowView = row
        if abcSlot != nil { bringSubviewToFront(abc) }
        let rh = row.heightAnchor.constraint(equalToConstant: spec.categoryRow - 2)
        rowHeight = rh
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: collection.bottomAnchor, constant: 2),
            row.leftAnchor.constraint(equalTo: leftAnchor),
            row.rightAnchor.constraint(equalTo: rightAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            rh,
        ])
        highlightCategory(sectionOnScreen())
    }

    #if DEBUG
    /// Test: frame (toạ độ plane) của ABC, các icon category (+ kaomoji), ⌫.
    var debugCategoryRow: (abc: CGRect, icons: [CGRect], delete: CGRect)? {
        guard let abc = abcButton, let row = categoryRowView,
              let del = row.arrangedSubviews.last else { return nil }
        let icons = (categoryButtons + [kaomojiButton].compactMap { $0 }).map { convert($0.bounds, from: $0) }
        return (convert(abc.bounds, from: abc), icons, convert(del.bounds, from: del))
    }
    #endif

    /// Bề ngang ABC / ⌫ ở hàng category (stock iPhone ≈ 48, iPad ≈ 64).
    static func edgeKeyWidth(pad: Bool) -> CGFloat { pad ? 64 : 48 }

    @objc private func backspaceHold(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                self?.onBackspace?()
            }
        case .ended, .cancelled, .failed:
            repeatTimer?.invalidate(); repeatTimer = nil
        default: break
        }
    }

    // MARK: category nav

    /// Map icon index (0 = recents) → section index thực (recents có thể vắng).
    private func sectionIndex(forIcon i: Int) -> Int? {
        let hasRecents = sections.first?.name == "recents"
        if i == 0 { return hasRecents ? 0 : nil }
        let idx = i - 1 + (hasRecents ? 1 : 0)
        return idx < sections.count ? idx : nil
    }

    private func iconIndex(forSection s: Int) -> Int {
        let hasRecents = sections.first?.name == "recents"
        if hasRecents { return s == 0 ? 0 : s }
        return s + 1
    }

    private var pendingIcon: Int?

    private func jumpToCategory(_ i: Int) {
        hideKaomoji()
        guard let s = sectionIndex(forIcon: i), collection.numberOfItems(inSection: s) > 0 else { return }
        // Giữ highlight ở icon vừa bấm: các section cuối (tim, cờ) không thể
        // cuộn tới mép trái (clamp contentSize) nên leftmost-visible sẽ báo
        // section trước đó — scroll callback không được đè trong lúc animate.
        pendingIcon = i
        collection.scrollToItem(at: IndexPath(item: 0, section: s), at: .left, animated: true)
        highlightCategory(i)
    }

    private func sectionOnScreen() -> Int {
        let visible = collection.indexPathsForVisibleItems.sorted()
        return visible.first?.section ?? 0
    }

    /// icon = -1 → không category nào (đang ở tab kaomoji).
    private func highlightCategory(_ icon: Int) {
        let ink: UIColor = dark ? .white : .black
        for (i, b) in categoryButtons.enumerated() {
            let on = i == icon
            b.ringColor = on ? ink.withAlphaComponent(0.18) : .clear
            b.tintColor = on ? ink : ink.withAlphaComponent(0.55)
        }
        let kao = kaomojiView != nil
        kaomojiButton?.ringColor = kao ? ink.withAlphaComponent(0.18) : .clear
        kaomojiButton?.setTitleColor(kao ? ink : ink.withAlphaComponent(0.55), for: .normal)
    }

    // MARK: kaomoji

    private func showKaomoji() {
        KeyboardView.clickModifier()
        dismissTonePopup()
        if kaomojiView == nil {
            let v = KaomojiView(groups: EmojiData.kaomoji, dark: dark)
            v.onPick = { [weak self] s in
                KeyboardView.clickLetter()
                self?.onKaomoji?(s)
            }
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: collection.topAnchor),
                v.bottomAnchor.constraint(equalTo: collection.bottomAnchor),
                v.leftAnchor.constraint(equalTo: collection.leftAnchor),
                v.rightAnchor.constraint(equalTo: collection.rightAnchor),
            ])
            kaomojiView = v
        }
        collection.isHidden = true
        highlightCategory(-1)
    }

    private func hideKaomoji() {
        guard let v = kaomojiView else { return }
        v.removeFromSuperview()
        kaomojiView = nil
        collection.isHidden = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collection, kaomojiView == nil else { return }
        guard pendingIcon == nil else { return }
        highlightCategory(iconIndex(forSection: sectionOnScreen()))
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        pendingIcon = nil          // user cuộn tay tiếp thì highlight lại bám theo
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pendingIcon = nil
        dismissTonePopup()
    }

    // MARK: skin tones

    /// [gốc + 5 tông da] — xem EmojiData.toneVariants (atlas dựng sẵn đúng các biến thể này).
    static func toneVariants(of e: String) -> [String]? { EmojiData.toneVariants(of: e) }

    private var tonePopup: UIView?

    @objc private func cellHold(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let pt = g.location(in: collection)
        guard let ip = collection.indexPathForItem(at: pt),
              let cell = collection.cellForItem(at: ip),
              let variants = Self.toneVariants(of: sections[ip.section][ip.item])
        else { return }
        showTonePopup(variants, over: cell)
    }

    private func showTonePopup(_ variants: [String], over cell: UIView) {
        dismissTonePopup()
        KeyboardView.clickModifier()
        let itemW: CGFloat = 36, h: CGFloat = 44
        let pop = UIView()
        pop.backgroundColor = dark ? UIColor(white: 0.25, alpha: 1) : .white
        pop.layer.cornerRadius = 10
        pop.layer.shadowColor = UIColor.black.cgColor
        pop.layer.shadowOffset = CGSize(width: 0, height: 1)
        pop.layer.shadowRadius = 3
        pop.layer.shadowOpacity = 0.3
        pop.layer.zPosition = 20
        for (i, v) in variants.enumerated() {
            let b = UIButton(type: .custom)
            b.frame = CGRect(x: CGFloat(i) * itemW, y: 0, width: itemW, height: h)
            Self.setEmoji(v, on: b, font: 26, atlas: atlas)
            b.addAction(UIAction { [weak self] _ in
                KeyboardView.clickLetter()
                self?.noteUsed(v)
                self?.onEmoji?(v)
                self?.dismissTonePopup()
            }, for: .touchUpInside)
            pop.addSubview(b)
        }
        let w = CGFloat(variants.count) * itemW
        let cf = convert(cell.bounds, from: cell)
        // trên cell, kẹp trong bounds của plane
        let x = min(max(cf.midX - w / 2, 4), bounds.width - w - 4)
        let y = max(cf.minY - h - 6, 2)
        pop.frame = CGRect(x: x, y: y, width: w, height: h)
        // Nền đục bo góc ⇒ bóng theo đúng hình đó, không cần vẽ offscreen.
        pop.layer.shadowPath = UIBezierPath(roundedRect: pop.bounds, cornerRadius: pop.layer.cornerRadius).cgPath
        addSubview(pop)
        tonePopup = pop
    }

    /// Nút một emoji (popup tông da, kết quả tìm): ảnh atlas nếu có, không thì chữ.
    static func setEmoji(_ e: String, on b: UIButton, font: CGFloat, atlas: EmojiAtlasStore?) {
        b.accessibilityLabel = e
        if let atlas, let img = atlas.tile(e) {
            let side = atlas.side(forFont: font)
            let iv = UIImageView(image: UIImage(cgImage: img, scale: atlas.scale, orientation: .up))
            iv.contentMode = .scaleAspectFit
            iv.isUserInteractionEnabled = false
            iv.frame = CGRect(x: (b.bounds.width - side) / 2, y: (b.bounds.height - side) / 2, width: side, height: side)
            iv.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
            b.addSubview(iv)
        } else {
            b.setTitle(e, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: font)
        }
    }

    #if DEBUG
    /// Test: số ô đang hiện vẽ bằng ảnh atlas / bằng chữ.
    var debugVisibleCellModes: (image: Int, text: Int) {
        var img = 0, txt = 0
        for case let c as EmojiCell in collection.visibleCells { if c.usesImage { img += 1 } else { txt += 1 } }
        return (img, txt)
    }
    var debugVisibleCellLabels: [String?] {
        collection.visibleCells.map { $0.accessibilityLabel }
    }
    #endif

    private func dismissTonePopup() {
        tonePopup?.removeFromSuperview()
        tonePopup = nil
    }

    /// Dọc/ngang đổi ô tìm, hàng category, bước ô (chỉ đổi hằng số constraint).
    private func applySpecIfNeeded() {
        let landscape: Bool
        let sceneLandscape = window?.windowScene?.interfaceOrientation.isLandscape
        if !pad { landscape = KeyLayout.isPhoneLandscape(width: bounds.width, sceneLandscape: sceneLandscape) }
        else if let o = sceneLandscape { landscape = o }
        else { landscape = bounds.width > 1000 }
        let s = EmojiGridMetrics.spec(pad: pad, landscape: landscape)
        guard s != spec else { return }
        spec = s
        metricsHeight = -1
        searchHeight?.constant = s.searchField
        searchField.layer.cornerRadius = s.searchField / 2
        rowHeight?.constant = s.categoryRow - 2
        let cfg = UIImage.SymbolConfiguration(pointSize: s.iconPoint, weight: .medium)
        for (b, name) in zip(categoryButtons, Self.categoryIcons) {
            b.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
        }
        collection.collectionViewLayout.invalidateLayout()
    }

    // Xoay màn hình / đổi cỡ Split View → cell size tính lại theo chiều cao mới.
    private var lastLayoutWidth: CGFloat = 0
    private var appliedMetrics: EmojiGridMetrics?
    override func layoutSubviews() {
        applySpecIfNeeded()
        super.layoutSubviews()
        if let abc = abcButton as? ABCButton, let slot = abcSlot {
            // Nhìn: cột phím emoji cũ, cao bằng hàng category (cách đáy 2).
            abc.frame = CGRect(x: slot.minX, y: bounds.height - spec.categoryRow,
                               width: slot.maxX - slot.minX, height: spec.categoryRow - 2)
            // Chạm: từ mép trái tới hết phím cũ, từ đỉnh phím cũ xuống đáy.
            abc.hitRect = CGRect(x: 0, y: bounds.height - max(slot.top, spec.categoryRow),
                                 width: slot.maxX, height: max(slot.top, spec.categoryRow))
        }
        let m = currentMetrics()
        if bounds.width != lastLayoutWidth || m != appliedMetrics {
            let resized = appliedMetrics != nil
            lastLayoutWidth = bounds.width
            appliedMetrics = m
            dismissTonePopup()
            for case let c as EmojiCell in collection.visibleCells { c.setFont(m.fontSize, atlas: atlas) }
            // Lưới đổi cỡ giữa chừng: flow layout trong CÙNG pass có thể chia hàng theo cỡ cũ
            // (đo 29/09: đủ ô 46pt mà chỉ xếp 3/4 hàng, khe giãn). Xếp lại một lượt ở nhịp kế —
            // chỉ khi đổi cỡ (xoay/host co), không phải mỗi layout.
            if resized {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.appliedMetrics == m else { return }
                    self.collection.collectionViewLayout.invalidateLayout()
                    self.collection.layoutIfNeeded()
                }
            }
        }
    }

    /// Ô theo chiều cao lưới HIỆN TẠI (delegate hỏi lúc flow layout prepare). Host co bàn
    /// phím sau lượt đầu (vd. 300 → 274 lúc settle): trước đây ô tính ở layoutSubviews còn
    /// flow layout xếp lại theo bounds mới với ô CŨ (81pt ⇒ 2 hàng hở 137pt) và invalidate
    /// sau đó bị nuốt — đo 29/09/2026. Xem EmojiGridLayout.
    private var metricsHeight: CGFloat = -1
    private func currentMetrics() -> EmojiGridMetrics {
        let h = collection.bounds.height
        if h != metricsHeight {
            metricsHeight = h
            metrics = EmojiGridMetrics.compute(gridHeight: h, spec: spec)
        }
        return metrics
    }

    /// Flow layout ngang: đổi CỠ lưới ⇒ hỏi lại cỡ ô từ delegate (mặc định bounds change
    /// giữ cỡ ô đã cache).
    private final class EmojiGridLayout: UICollectionViewFlowLayout {
        override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
            let ctx = super.invalidationContext(forBoundsChange: newBounds)
            // Chỉ tới đây khi CỠ đổi (shouldInvalidate bên dưới) — cuộn không tốn gì.
            (ctx as? UICollectionViewFlowLayoutInvalidationContext)?.invalidateFlowLayoutDelegateMetrics = true
            return ctx
        }
        override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
            newBounds.size != collectionView?.bounds.size
        }
    }

    // MARK: collection

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        cell.show(sections[indexPath.section][indexPath.item], font: currentMetrics().fontSize, atlas: atlas)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let m = currentMetrics()
        return CGSize(width: m.cellW, height: m.cellH)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        UIEdgeInsets(top: 0, left: section == 0 ? spec.lead : 0, bottom: 0,
                     right: section == sections.count - 1 ? spec.lead : spec.sectionGap)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        dismissTonePopup()
        let e = sections[indexPath.section][indexPath.item]
        KeyboardView.clickLetter()
        let hadRecents = sections.first?.name == "recents"
        noteUsed(e)
        onEmoji?(e)
        if !hadRecents {
            // lần dùng đầu tiên trong phiên: section 🕐 xuất hiện ngay,
            // không phải đợi mở lại plane
            reloadSections()
            collection.reloadData()
        }
    }

    /// Tab kaomoji: cuộn dọc, mỗi nhóm một tiêu đề xám + các "viên" chữ dàn dòng.
    final class KaomojiView: UIScrollView {
        var onPick: ((String) -> Void)?
        private(set) var chips: [(button: UIButton, text: String)] = []
        private var headers: [UILabel] = []
        private var groupStarts: [Int] = []
        private var lastW: CGFloat = 0

        init(groups: [(name: String, items: [String])], dark: Bool) {
            super.init(frame: .zero)
            showsVerticalScrollIndicator = false
            alwaysBounceVertical = true
            disableKeyboardEdgeEffects()
            let ink: UIColor = dark ? .white : .black
            let fill = dark ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 1, alpha: 0.9)
            for g in groups {
                let h = UILabel()
                h.text = g.name.uppercased()
                h.font = .systemFont(ofSize: 11, weight: .semibold)
                h.textColor = ink.withAlphaComponent(0.5)
                addSubview(h)
                headers.append(h)
                groupStarts.append(chips.count)
                for item in g.items {
                    let b = UIButton(type: .custom)
                    b.setTitle(item, for: .normal)
                    b.setTitleColor(ink, for: .normal)
                    b.titleLabel?.font = .systemFont(ofSize: 17)
                    b.backgroundColor = fill
                    b.layer.cornerRadius = 8
                    b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
                    b.accessibilityLabel = item
                    b.addAction(UIAction { [weak self] _ in self?.onPick?(item) }, for: .touchUpInside)
                    addSubview(b)
                    chips.append((b, item))
                }
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width != lastW else { return }
            lastW = bounds.width
            let side: CGFloat = 8, gap: CGFloat = 6, h: CGFloat = 34
            var y: CGFloat = 2
            for (gi, header) in headers.enumerated() {
                header.frame = CGRect(x: side + 2, y: y, width: bounds.width - 2 * side, height: 14)
                y += 18
                var x = side
                let end = gi + 1 < groupStarts.count ? groupStarts[gi + 1] : chips.count
                for ci in groupStarts[gi]..<end {
                    let b = chips[ci].button
                    let w = min(max(b.intrinsicContentSize.width, h), bounds.width - 2 * side)
                    if x + w > bounds.width - side, x > side { x = side; y += h + gap }
                    b.frame = CGRect(x: x, y: y, width: w, height: h)
                    x += w + gap
                }
                y += h + 12
            }
            contentSize = CGSize(width: bounds.width, height: y)
        }
    }

    /// Ô emoji: ẢNH từ atlas (UIImageView — layer.contents trỏ thẳng CGImage của ô, không backing
    /// store, không đụng cache glyph CoreText) hoặc, khi chưa có atlas / thiếu emoji, chữ như cũ.
    private final class EmojiCell: UICollectionViewCell {
        let label = UILabel()
        private let imageView = UIImageView()
        private var imageSide: CGFloat = 0
        private(set) var usesImage = false
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 32)
            label.textAlignment = .center
            // KHÔNG adjustsFontSizeToFitWidth: cỡ glyph đã tính vừa ô (EmojiGridMetrics, ≤ 0.92 ×
            // ô); bật co chữ làm UILabel đo/dựng layout thêm mỗi ô (RAM-AUDIT.md §4).
            label.lineBreakMode = .byClipping
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            imageView.contentMode = .scaleAspectFit
            imageView.isHidden = true
            contentView.addSubview(imageView)
            NSLayoutConstraint.activate([
                label.leftAnchor.constraint(equalTo: contentView.leftAnchor),
                label.rightAnchor.constraint(equalTo: contentView.rightAnchor),
                label.topAnchor.constraint(equalTo: contentView.topAnchor),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
            // VoiceOver: ô là một phần tử, nhãn = chuỗi emoji (VoiceOver tự đọc tên emoji —
            // emoji.bin không có trường tên CLDR riêng).
            isAccessibilityElement = true
            accessibilityTraits = .keyboardKey
        }
        required init?(coder: NSCoder) { fatalError() }

        func show(_ e: String, font: CGFloat, atlas: EmojiAtlasStore?) {
            accessibilityLabel = e
            if let atlas, let img = atlas.tile(e) {
                usesImage = true
                label.text = nil
                label.isHidden = true
                imageView.image = UIImage(cgImage: img, scale: atlas.scale, orientation: .up)
                imageView.isHidden = false
                setFont(font, atlas: atlas)
            } else {
                usesImage = false
                imageView.image = nil
                imageView.isHidden = true
                label.isHidden = false
                label.text = e
                setFont(font, atlas: nil)
            }
        }

        func setFont(_ size: CGFloat, atlas: EmojiAtlasStore?) {
            if usesImage, let atlas {
                let side = atlas.side(forFont: size)
                if side != imageSide { imageSide = side; setNeedsLayout() }
            } else if label.font.pointSize != size {
                label.font = .systemFont(ofSize: size)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard usesImage else { return }
            let b = contentView.bounds
            imageView.frame = CGRect(x: (b.width - imageSide) / 2, y: (b.height - imageSide) / 2,
                                     width: imageSide, height: imageSide)
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            imageView.image = nil      // ô ra khỏi màn hình không giữ ảnh
        }
    }
}
