// "Hiệu ứng khi bấm phím" (Plus): lưới 3 cột như "Chọn giao diện" — mỗi ô một phím thu nhỏ trên nền
// theme đang dùng; chạm là chọn + xem thử ngay (cùng KeyEffectOverlay của bàn phím). Ô Plus bị khoá:
// mờ + nhãn Plus, chạm mở màn VietTelex Plus. Lưu App Group `keyEffect` (KeyEffect.key) — bàn phím đọc
// lần hiện kế. Android: KeyEffectPage.kt.
import SwiftUI
import UIKit

private let effectDefaults = UserDefaults(suiteName: AppFlavor.appGroup)

struct KeyEffectPickerView: View {
    @AppStorage(KeyEffect.key, store: effectDefaults) private var raw = KeyEffect.defaultValue.rawValue
    @Environment(\.colorScheme) private var scheme
    @State private var showPlus = false
    /// Số lần chạm từng ô — đổi ⇒ ô phát hiệu ứng một lượt.
    @State private var plays: [KeyEffect: Int] = [:]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private var current: KeyEffect { KeyEffect.parse(raw) }

    var body: some View {
        let palette = ThemeSettings.load(effectDefaults).palette(systemDark: scheme == .dark, wallpaperActive: false)
        List {
            if !KeyEffectGate.allows {
                Section {
                    PlusEntryRow()
                }
            }
            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(KeyEffect.allCases, id: \.self) { tile($0, palette: palette) }
                }
                .padding(.vertical, 6)
            } header: {
                Text(L("Chạm một ô để chọn và xem thử."))
            } footer: {
                Text(L("Hình nhỏ bay ra từ phím vừa bấm, theo màu nhấn của giao diện. Vẽ sau khi chữ đã vào ô nên không làm chậm gõ; tự tắt khi bật Chế độ nguồn điện thấp."))
                    + Text(" ") + Text(L("Matrix, Mực loang, Sóng nước chạy dưới phím; Matrix chỉ chạy khi đang gõ. Nháy sáng được giới hạn nhịp và độ sáng cho dịu mắt. Emoji theo chữ hiện khi vừa gõ xong từ như \"haha\", \"cảm ơn\", \"chúc mừng\"."))
            }
        }
        .bottomBarScrollMargin()
        .navigationTitle(L("Hiệu ứng khi bấm phím"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlus) { PlusView(model: PlusShared.model) }
    }

    private func tile(_ e: KeyEffect, palette: KeyboardPalette) -> some View {
        let locked = !KeyEffectGate.allows(e)
        let selected = current == e
        return VStack(spacing: 6) {
            Button { tap(e, locked: locked) } label: {
                // Lớp SwiftUI trong suốt PHỦ lên ô xem trước UIKit: hit-test vào UIViewRepresentable
                // không tới được Button ⇒ chạm ô không chọn được (Phil 19/10/2026).
                KeyEffectPreview(effect: e, palette: palette, play: plays[e, default: 0])
                    .overlay(Color.clear.contentShape(Rectangle()))
                    .frame(height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, Color.accentColor).font(.body).padding(4)
                        }
                    }
                    .opacity(locked ? 0.5 : 1)
            }
            .buttonStyle(.borderless)   // nhiều nút trong MỘT hàng List: .plain để List nuốt chạm
            .accessibilityLabel(e.title + (selected ? L(", đang chọn") : "") + (locked ? " · Plus" : ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
            HStack(spacing: 4) {
                Text(e.title).font(.footnote).lineLimit(1)
                if locked { plusBadge }
                Spacer(minLength: 0)
            }
        }
    }

    private func tap(_ e: KeyEffect, locked: Bool) {
        if locked { showPlus = true; return }
        raw = e.rawValue
        plays[e, default: 0] += 1
    }

    private var plusBadge: some View {
        Text("Plus").font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.85)))
            .foregroundStyle(.white)
    }
}

/// Ô xem thử: một phím "a" trên nền theme + overlay hiệu ứng thật.
struct KeyEffectPreview: UIViewRepresentable {
    let effect: KeyEffect
    let palette: KeyboardPalette
    let play: Int

    func makeUIView(context: Context) -> KeyEffectPreviewView { KeyEffectPreviewView() }
    func updateUIView(_ v: KeyEffectPreviewView, context: Context) {
        v.update(effect: effect, palette: palette, play: play)
    }
}

final class KeyEffectPreviewView: UIView {
    private let key = UIView()
    private let label = UILabel()
    private var overlay: KeyEffectOverlay?
    private var lastPlay = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        key.layer.cornerRadius = 6
        key.isUserInteractionEnabled = false
        label.text = "a"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 20)
        key.addSubview(label)
        addSubview(key)
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(effect: KeyEffect, palette: KeyboardPalette, play: Int) {
        backgroundColor = palette.background?.ui ?? (palette.isDark ? UIColor(white: 0.16, alpha: 1)
                                                                    : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1))
        key.backgroundColor = palette.keyFill.ui
        label.textColor = palette.keyInk.ui
        // Matrix / Mực loang / Sóng nước: dưới phím mẫu (như bàn phím thật).
        overlay = KeyEffectOverlay.install(effect, color: palette.accent.alpha(1).ui, keyFill: palette.keyFill.ui,
                                           dark: palette.isDark, in: self, keys: key, existing: overlay)
        if play != lastPlay {
            lastPlay = play
            layoutIfNeeded()
            if effect == .emojiword { overlay?.queueEmoji("😂") }   // như vừa gõ "haha" + dấu cách
            if effect == .combo {
                // Xem thử combo: một tràng phím nhanh ⇒ lên mức lửa cao nhất.
                for _ in 0..<ComboMeter.thresholds[2] { overlay?.emit(key: key.frame); overlay?.flush() }
            }
            overlay?.emit(key: key.frame)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w: CGFloat = 34, h: CGFloat = 42
        key.frame = CGRect(x: (bounds.width - w) / 2, y: bounds.height - h - 8, width: w, height: h)
        label.frame = key.bounds
    }
}
