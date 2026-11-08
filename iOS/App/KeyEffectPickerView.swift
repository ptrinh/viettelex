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
                    + Text(" ") + Text(L("Rung combo không rung khi bật Giảm chuyển động. Dấu thanh phản ứng theo dấu vừa bỏ; Từ khoá nổ pháo đỏ và lì xì khi gõ \"tết\", thả tim khi gõ \"yêu\"; Chữ bay thả đúng chữ vừa ra; Hạt cát đọng thành đống thấp ở đáy rồi tự tan."))
                    + Text(" ") + Text(L("Biển: mỗi đợt gõ một con sóng vỗ vào bờ dưới đáy bàn phím, gõ càng nhanh sóng càng lớn; thỉnh thoảng có cá bơi ngang."))
                    + Text(" ") + Text(L("Mưa: mưa đêm êm trên ô kính — giọt rơi xuống phím vừa bấm rồi lăn nhẹ; gõ một lúc mưa thưa dần và ánh đèn ấm ở góc sáng lên."))
                    + Text(" ") + Text(L("Sàn nhảy LED thắp phím vừa bấm và các phím quanh thành vòng neon lan ra; gõ thật nhanh, cả bàn phím nháy một nhịp."))
                    + Text(" ") + Text(L("Kính vạn hoa nở một bông đối xứng sắc cầu vồng từ phím vừa bấm, xoay chậm rồi tan."))
                    + Text(" ") + Text(L("Đường hầm: vòng sáng co về phím vừa bấm như rơi vào đường hầm, gõ nhanh thì rơi nhanh hơn. Lơ lửng: phím trôi nhẹ khỏi hàng khi đang gõ rồi về chỗ khi nghỉ; chỉ là hình — chạm vẫn đúng phím; tắt khi bật Giảm chuyển động."))
                    + Text(" ") + Text(L("Công đức thả \"+1 công đức\" bay lên từ phím vừa bấm và đếm số phím trong ngày (về 0 lúc nửa đêm, chỉ lưu trên máy). Nắng qua kính làm ô vừa bấm sáng lên như nắng xuyên qua kính màu; gõ nhanh có ánh nến ấm bập bùng chậm ở mép dưới."))
                    + Text(" ") + Text(L("Rep lấp thanh rep một nấc mỗi phím, đủ 10 phím là xong một hiệp (SET ✓); gõ nhanh bật \"+1 rep 💪\"; gõ \"gym\", \"tập\", \"beast mode\"… để nổ chữ BEAST MODE."))
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

/// Ô xem thử: một phím "V" trên nền theme + overlay hiệu ứng thật.
struct KeyEffectPreview: UIViewRepresentable {
    let effect: KeyEffect
    let palette: KeyboardPalette
    let play: Int

    func makeUIView(context: Context) -> KeyEffectPreviewView { KeyEffectPreviewView() }
    func updateUIView(_ v: KeyEffectPreviewView, context: Context) {
        v.update(effect: effect, palette: palette, play: play)
    }
}
// KeyEffectPreviewView (UIKit): Keyboard/KeyEffectPreview.swift — dùng chung với test.

