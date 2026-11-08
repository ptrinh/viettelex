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
        let settings = ThemeSettings.load(effectDefaults)
        let palette = settings.palette(systemDark: scheme == .dark, wallpaperActive: false)
        let zodiac = settings.variantChoice.zodiac, pride = settings.variantChoice.pride
        let particles = settings.effectiveSpec?.particles
        List {
            if !KeyEffectGate.allows {
                Section {
                    PlusEntryRow()
                }
            }
            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(KeyEffect.allCases, id: \.self) { tile($0, palette: palette, zodiac: zodiac, pride: pride, particles: particles) }
                }
                .padding(.vertical, 6)
            } header: {
                Text(L("Chạm một ô để chọn và xem thử."))
            } footer: {
                // Chỉ mô tả kiểu ĐANG CHỌN (đổi khi chạm ô khác) + một câu chung — thay đoạn liệt kê mọi kiểu (Phil 11/2026).
                VStack(alignment: .leading, spacing: 8) {
                    if let detail = KeyEffect.description(for: current) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.title).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                            Text(detail)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text(L(KeyEffect.generalNoteKey))
                }
            }
        }
        .bottomBarScrollMargin()
        .navigationTitle(L("Hiệu ứng khi bấm phím"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlus) { PlusView(model: PlusShared.model) }
    }

    private func tile(_ e: KeyEffect, palette: KeyboardPalette, zodiac: ZodiacSign, pride: PrideFlag, particles: ThemeParticles?) -> some View {
        let locked = !KeyEffectGate.allows(e)
        let selected = current == e
        return VStack(spacing: 6) {
            Button { tap(e, locked: locked) } label: {
                // Lớp SwiftUI trong suốt PHỦ lên ô xem trước UIKit: hit-test vào UIViewRepresentable
                // không tới được Button ⇒ chạm ô không chọn được (Phil 19/10/2026).
                KeyEffectPreview(effect: e, palette: palette, play: plays[e, default: 0], zodiac: zodiac, pride: pride, themeParticles: particles)
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
    var zodiac: ZodiacSign = .defaultValue
    var pride: PrideFlag = .defaultValue
    var themeParticles: ThemeParticles? = nil

    func makeUIView(context: Context) -> KeyEffectPreviewView { KeyEffectPreviewView() }
    func updateUIView(_ v: KeyEffectPreviewView, context: Context) {
        v.update(effect: effect, palette: palette, play: play, zodiac: zodiac, pride: pride, themeParticles: themeParticles)
    }
}
// KeyEffectPreviewView (UIKit): Keyboard/KeyEffectPreview.swift — dùng chung với test.

