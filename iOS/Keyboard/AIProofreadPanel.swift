// Bảng xem trước "✨ Sửa lỗi" (Apple Intelligence) — phủ VÙNG PHÍM như panel clipboard
// (KeyboardView.overlayPanel), KHÔNG đổi chiều cao bàn phím (Zalo… xử lý sai khi bàn phím
// đổi cao). Chỉ vẽ + báo sự kiện; quyết định / thay chữ ở AIAssist.
import UIKit

final class AIProofreadPanel: UIView {
    var onApply: (() -> Void)?
    var onCancel: (() -> Void)?

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let scroll = UIScrollView()
    private let textLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let applyButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityViewIsModal = true
        titleLabel.text = L("✨ Sửa lỗi")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 13)
        countLabel.textAlignment = .right
        let header = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        header.axis = .horizontal
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        textLabel.numberOfLines = 0
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.disableKeyboardEdgeEffects()
        scroll.addSubview(textLabel)
        addSubview(scroll)

        for (b, title, bold) in [(cancelButton, L("Huỷ"), false), (applyButton, L("Áp dụng"), true)] {
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 16, weight: bold ? .semibold : .regular)
            b.layer.cornerRadius = 8
            b.layer.cornerCurve = .continuous
        }
        cancelButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        applyButton.addAction(UIAction { [weak self] _ in self?.onApply?() }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [cancelButton, applyButton])
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually
        buttons.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttons)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            header.leftAnchor.constraint(equalTo: leftAnchor, constant: 12),
            header.rightAnchor.constraint(equalTo: rightAnchor, constant: -12),
            header.heightAnchor.constraint(equalToConstant: 24),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.leftAnchor.constraint(equalTo: leftAnchor, constant: 12),
            scroll.rightAnchor.constraint(equalTo: rightAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -6),
            textLabel.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            textLabel.leftAnchor.constraint(equalTo: scroll.frameLayoutGuide.leftAnchor),
            textLabel.rightAnchor.constraint(equalTo: scroll.frameLayoutGuide.rightAnchor),
            buttons.leftAnchor.constraint(equalTo: leftAnchor, constant: 8),
            buttons.rightAnchor.constraint(equalTo: rightAnchor, constant: -8),
            buttons.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            buttons.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `segments` = bản sửa (WordDiff), đoạn đổi được tô. `changed` = 0 ⇒ "Không thấy lỗi"
    /// (chỉ còn nút Đóng).
    func configure(segments: [WordDiffSegment], changed: Int, dark: Bool) {
        let ink: UIColor = dark ? .white : .black
        let accent = UIColor.systemBlue
        backgroundColor = dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
        titleLabel.textColor = ink
        countLabel.textColor = ink.withAlphaComponent(0.6)
        countLabel.text = changed == 0 ? L("Không thấy lỗi") : L("%@ chỗ sửa", changed)
        let body = UIFont.systemFont(ofSize: 16)
        let bold = UIFont.systemFont(ofSize: 16, weight: .semibold)
        let s = NSMutableAttributedString()
        for seg in segments {
            var a: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: ink]
            if seg.changed {
                a[.font] = bold
                a[.backgroundColor] = accent.withAlphaComponent(dark ? 0.45 : 0.25)
            }
            s.append(NSAttributedString(string: seg.text, attributes: a))
        }
        textLabel.attributedText = s
        textLabel.accessibilityLabel = segments.map(\.text).joined()
        let keyBg = dark ? UIColor(white: 0.35, alpha: 1) : UIColor.white
        cancelButton.backgroundColor = keyBg
        cancelButton.tintColor = ink
        cancelButton.setTitle(changed == 0 ? L("Đóng") : L("Huỷ"), for: .normal)
        applyButton.backgroundColor = accent
        applyButton.tintColor = .white
        applyButton.isHidden = changed == 0
        scroll.contentOffset = .zero
    }
}
