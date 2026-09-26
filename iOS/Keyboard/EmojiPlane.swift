// EmojiPlane — bàn phím emoji render theo đúng cấu trúc bàn phím US stock
// (đối chiếu video 2026-07-24): lưới emoji lớn
// cuộn NGANG column-major liên tục theo category, hàng dưới
// [ABC][icon 9 category][⌫] với category đang xem được highlight tròn.
// Recents (🕐) lưu App Group, tối đa 30. (Search bar đã bỏ — user 2026-07-24.)
import UIKit

final class EmojiPlane: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    var onEmoji: ((String) -> Void)?
    var onABC: (() -> Void)?
    var onBackspace: (() -> Void)?

    private var dark = false
    private var sections: [(name: String, emoji: [String])] = []
    private var collection: UICollectionView!
    private var categoryButtons: [UIButton] = []
    private var repeatTimer: Timer?

    private static let recentsKey = "emojiRecents"
    private static let categoryIcons: [String] = [
        "clock", "face.smiling", "hare", "fork.knife", "soccerball",
        "car.fill", "lightbulb", "heart", "flag",
    ]
    // Tiêu đề section nhỏ màu xám phía trên cột đầu của category (như stock).
    private static let headerBand: CGFloat = 14
    private static let displayNames: [String: String] = [
        "recents": "THƯỜNG DÙNG", "smileys": "MẶT CƯỜI & NGƯỜI",
        "animals": "ĐỘNG VẬT & THIÊN NHIÊN", "food": "ĐỒ ĂN & ĐỒ UỐNG",
        "activity": "HOẠT ĐỘNG", "travel": "DU LỊCH & ĐỊA ĐIỂM",
        "objects": "ĐỒ VẬT", "symbols": "BIỂU TƯỢNG", "flags": "CỜ",
    ]

    /// Chỗ phím emoji vừa bấm (toạ độ KeyboardView; plane cùng mép trái + đáy):
    /// minX, maxX, top = khoảng từ đáy lên đỉnh phím. ABC đặt ĐÚNG cột đó —
    /// bấm nhầm emoji thì chạm lại chỗ cũ là về chữ (user 26/09/2026).
    struct ABCSlot { var minX: CGFloat; var maxX: CGFloat; var top: CGFloat }
    private let abcSlot: ABCSlot?
    private var abcButton: UIButton?

    /// Vùng chạm nở lên tới đỉnh phím emoji cũ và sang trái tới mép bàn phím.
    private final class ABCButton: UIButton {
        var hitRect: CGRect?   // toạ độ superview
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard let r = hitRect, let sv = superview else { return super.point(inside: point, with: event) }
            return r.contains(convert(point, to: sv))
        }
    }

    init(dark: Bool, abcSlot: ABCSlot? = nil) {
        self.abcSlot = abcSlot
        super.init(frame: .zero)
        self.dark = dark
        isMultipleTouchEnabled = true
        reloadSections()
        buildCollection()
        buildCategoryRow()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { repeatTimer?.invalidate() }

    // UserDefaults.standard: không Full Access → iOS cấm GHI App Group từ
    // extension (ghi group fail âm thầm — recents từng mất qua phiên vì vậy).
    private var recents: [String] {
        UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    private func reloadSections() {
        var s: [(String, [String])] = []
        let r = recents
        if !r.isEmpty { s.append(("recents", r)) }
        s.append(contentsOf: EmojiData.categories.map { ($0.name, $0.emoji) })
        sections = s
    }

    private func noteUsed(_ e: String) {
        var r = recents.filter { $0 != e }
        r.insert(e, at: 0)
        if r.count > 30 { r.removeLast(r.count - 30) }
        UserDefaults.standard.set(r, forKey: Self.recentsKey)
    }

    // MARK: UI

    private func buildCollection() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal        // column-major như stock
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 4
        // dải trống phía trên nhường chỗ cho tiêu đề section
        layout.sectionInset = UIEdgeInsets(top: Self.headerBand, left: 6, bottom: 0, right: 6)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.disableKeyboardEdgeEffects()
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        collection.register(HeaderView.self,
                            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                            withReuseIdentifier: "h")
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.isMultipleTouchEnabled = true
        // Long-press emoji có skin tone → popup 6 biến thể (cancelsTouchesInView
        // mặc định true nên tap thường không bị chèn kèm emoji gốc).
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(cellHold(_:)))
        hold.minimumPressDuration = 0.35
        collection.addGestureRecognizer(hold)
        addSubview(collection)
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            collection.leftAnchor.constraint(equalTo: leftAnchor),
            collection.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    private func buildCategoryRow() {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.alignment = .center
        row.spacing = 2
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
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
        if let slot = abcSlot {
            // ABC nằm ngoài stack (layoutSubviews đặt frame theo slot); stack chừa
            // chỗ bằng spacer để icon category không chui dưới ABC.
            let spacer = UIView()
            spacer.widthAnchor.constraint(equalToConstant: max(slot.maxX - 8 + 2, 44)).isActive = true
            row.addArrangedSubview(spacer)
            addSubview(abc)
            abcButton = abc
        } else {
            row.addArrangedSubview(abc)
            abc.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }

        let iconsStack = UIStackView()
        iconsStack.axis = .horizontal
        iconsStack.distribution = .fillEqually
        for (i, name) in Self.categoryIcons.enumerated() {
            let b = UIButton(type: .custom)
            b.setImage(UIImage(systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
            b.tintColor = ink.withAlphaComponent(0.55)
            b.layer.cornerRadius = 13
            b.addAction(UIAction { [weak self] _ in self?.jumpToCategory(i) }, for: .touchUpInside)
            categoryButtons.append(b)
            iconsStack.addArrangedSubview(b)
        }
        row.addArrangedSubview(iconsStack)

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
        row.addArrangedSubview(del)
        del.widthAnchor.constraint(equalToConstant: 44).isActive = true

        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: collection.bottomAnchor, constant: 2),
            row.leftAnchor.constraint(equalTo: leftAnchor),
            row.rightAnchor.constraint(equalTo: rightAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            row.heightAnchor.constraint(equalToConstant: 32),
        ])
        highlightCategory(sectionOnScreen())
    }

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

    private func highlightCategory(_ icon: Int) {
        let ink: UIColor = dark ? .white : .black
        for (i, b) in categoryButtons.enumerated() {
            let on = i == icon
            b.backgroundColor = on ? ink.withAlphaComponent(0.18) : .clear
            b.tintColor = on ? ink : ink.withAlphaComponent(0.55)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
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

    /// [gốc + 5 tông da] nếu emoji có scalar là modifier base; nil nếu không.
    /// Tông áp cho MỌI base trong chuỗi ZWJ (chọn 1 tông cho cả nhóm — như
    /// lựa chọn nhanh của stock; chưa nhớ tông riêng từng emoji).
    static func toneVariants(of e: String) -> [String]? {
        guard e.unicodeScalars.contains(where: { $0.properties.isEmojiModifierBase })
        else { return nil }
        let tones: [Unicode.Scalar] = (0x1F3FB...0x1F3FF).compactMap { Unicode.Scalar($0) }
        var out = [e]
        for t in tones {
            var v = String.UnicodeScalarView()
            for sc in e.unicodeScalars {
                if (0x1F3FB...0x1F3FF).contains(sc.value) { continue }  // bỏ tông cũ
                v.append(sc)
                if sc.properties.isEmojiModifierBase { v.append(t) }
            }
            out.append(String(v))
        }
        return out
    }

    private var tonePopup: UIView?

    @objc private func cellHold(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let pt = g.location(in: collection)
        guard let ip = collection.indexPathForItem(at: pt),
              let cell = collection.cellForItem(at: ip),
              let variants = Self.toneVariants(of: sections[ip.section].emoji[ip.item])
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
            b.setTitle(v, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 26)
            b.frame = CGRect(x: CGFloat(i) * itemW, y: 0, width: itemW, height: h)
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
        addSubview(pop)
        tonePopup = pop
    }

    private func dismissTonePopup() {
        tonePopup?.removeFromSuperview()
        tonePopup = nil
    }

    // Xoay màn hình / đổi cỡ Split View → cell size tính lại theo chiều cao mới.
    private var lastLayoutWidth: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            dismissTonePopup()
            collection.collectionViewLayout.invalidateLayout()
        }
        if let abc = abcButton as? ABCButton, let slot = abcSlot {
            // Nhìn: cột phím emoji cũ, cao bằng hàng category (32, cách đáy 2).
            abc.frame = CGRect(x: slot.minX, y: bounds.height - 34,
                               width: slot.maxX - slot.minX, height: 32)
            // Chạm: từ mép trái tới hết phím cũ, từ đỉnh phím cũ xuống đáy.
            abc.hitRect = CGRect(x: 0, y: bounds.height - slot.top,
                                 width: slot.maxX, height: slot.top)
            bringSubviewToFront(abc)
        }
    }

    // MARK: collection

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].emoji.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        cell.label.text = sections[indexPath.section].emoji[indexPath.item]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 5 hàng như stock; trừ dải tiêu đề section phía trên
        let rows: CGFloat = 5
        let h = (collectionView.bounds.height - Self.headerBand - (rows - 1) * 4) / rows
        return CGSize(width: max(h, 10), height: max(h, 10))
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        // strip dọc mảnh; label không clip nên nổi ngang qua dải headerBand
        CGSize(width: 8, height: 0)
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let v = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: "h", for: indexPath) as! HeaderView
        let name = sections[indexPath.section].name
        v.label.text = Self.displayNames[name] ?? name.uppercased()
        v.label.textColor = (dark ? UIColor.white : .black).withAlphaComponent(0.5)
        // Giới hạn label trong đúng bề rộng section để KHÔNG tràn đè header
        // section kế (bug section hẹp như "Thường dùng", user 2026-07-25).
        let rows: CGFloat = 5
        let cols = max(ceil(CGFloat(sections[indexPath.section].emoji.count) / rows), 1)
        let itemW = (collectionView.bounds.height - Self.headerBand - (rows - 1) * 4) / rows
        v.maxWidth = cols * itemW + (cols - 1) * 8   // cột × rộng + line-spacing
        return v
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        dismissTonePopup()
        let e = sections[indexPath.section].emoji[indexPath.item]
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

    private final class EmojiCell: UICollectionViewCell {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 30)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leftAnchor.constraint(equalTo: contentView.leftAnchor),
                label.rightAnchor.constraint(equalTo: contentView.rightAnchor),
                label.topAnchor.constraint(equalTo: contentView.topAnchor),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }
    }

    private final class HeaderView: UICollectionReusableView {
        let label = UILabel()
        private var maxW: NSLayoutConstraint!
        /// Bề rộng tối đa của label = bề rộng section (đặt mỗi lần dequeue) —
        /// label vẫn tràn khỏi strip 8pt nhưng KHÔNG tràn sang section kế.
        var maxWidth: CGFloat = 0 { didSet { maxW.constant = max(maxWidth, 8) } }
        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = false          // label rộng hơn strip 8pt — cố ý
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            maxW = label.widthAnchor.constraint(lessThanOrEqualToConstant: 8)
            NSLayoutConstraint.activate([
                label.leftAnchor.constraint(equalTo: leftAnchor, constant: 2),
                label.topAnchor.constraint(equalTo: topAnchor),
                maxW,
            ])
        }
        required init?(coder: NSCoder) { fatalError() }
    }
}
