// "Hiệu ứng nét vuốt" (Gõ vuốt → Hiệu ứng nét vuốt): lưới 2 cột — mỗi ô một nét vuốt mẫu vẽ bằng CHÍNH
// renderer của bàn phím (SwipeTrailRenderer) trên nền theme đang dùng; chạm là chọn + xem thử. Ô Plus bị
// khoá: mờ + nhãn Plus, chạm mở VietTelex Plus. Lưu App Group `swipeTrail` — bàn phím đọc lần hiện kế.
// Android: SwipeTrailPage.kt.
import SwiftUI
import UIKit

private let trailDefaults = UserDefaults(suiteName: AppFlavor.appGroup)

struct SwipeTrailPickerView: View {
    @AppStorage(SwipeTrailStyle.key, store: trailDefaults) private var raw = SwipeTrailStyle.defaultValue.rawValue
    @Environment(\.colorScheme) private var scheme
    @State private var showPlus = false
    /// Số lần chạm từng ô — đổi ⇒ ô vẽ lại nét mẫu một lượt.
    @State private var plays: [SwipeTrailStyle: Int] = [:]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        let settings = ThemeSettings.load(trailDefaults)
        let palette = settings.palette(systemDark: scheme == .dark, wallpaperActive: false)
        let themeSwipe = settings.effectiveKeyStyle.swipe
        List {
            if !SwipeTrailGate.allows {
                Section { PlusEntryRow() }
            }
            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SwipeTrailStyle.allCases, id: \.self) { tile($0, palette: palette, themeSwipe: themeSwipe) }
                }
                .padding(.vertical, 6)
            } header: {
                Text(L("Chạm một ô để chọn và xem thử."))
            } footer: {
                Text(L("Nét vẽ theo ngón tay khi gõ vuốt. Tắt: không vẽ gì. Lửa, Điện, Bút lông, Cầu vồng, Neon, Bụi sao, Pháo hoa cuối nét và Theo giao diện thuộc VietTelex Plus. Theo giao diện: dùng nét vuốt của giao diện đang chọn (Đơn giản nếu giao diện không có)."))
                    + Text(" ") + Text(L("Vẽ trên lớp riêng, không làm chậm nhận diện nét vuốt; tự về Đơn giản khi bật Chế độ nguồn điện thấp."))
            }
        }
        .bottomBarScrollMargin()
        .navigationTitle(L("Hiệu ứng nét vuốt"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlus) { PlusView(model: PlusShared.model) }
    }

    private func tile(_ s: SwipeTrailStyle, palette: KeyboardPalette, themeSwipe: String?) -> some View {
        let locked = !SwipeTrailGate.allows(s)
        let selected = SwipeTrailStyle.displayed(raw) == s
        // Xem thử luôn vẽ đúng kiểu (kể cả khi khoá); "Theo giao diện" ⇒ nét của theme đang dùng.
        let drawn = SwipeTrailPolicy.active(setting: s, plus: true, themeSwipe: themeSwipe, lowPower: false)
        return VStack(spacing: 6) {
            Button { tap(s, locked: locked) } label: {
                // Lớp SwiftUI trong suốt PHỦ lên ô xem trước UIKit (hit-test như KeyEffectPickerView).
                SwipeTrailPreview(style: drawn, palette: palette, play: plays[s, default: 0])
                    .overlay(Color.clear.contentShape(Rectangle()))
                    .frame(height: 76)
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
            .buttonStyle(.borderless)
            .accessibilityLabel(s.title + (selected ? L(", đang chọn") : "") + (locked ? " · Plus" : ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
            HStack(spacing: 4) {
                Text(s.title).font(.footnote).lineLimit(1)
                if locked { SwipeTrailPlusBadge() }
                Spacer(minLength: 0)
            }
        }
        .onAppear { if plays[s] == nil { plays[s] = 1 } }   // vẽ mẫu một lượt khi mở trang
    }

    private func tap(_ s: SwipeTrailStyle, locked: Bool) {
        if locked { showPlus = true; return }
        raw = s.rawValue
        plays[s, default: 0] += 1
    }
}

/// Nhãn "Plus" nhỏ (dòng cài đặt + ô khoá).
struct SwipeTrailPlusBadge: View {
    var body: some View {
        Text("Plus").font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.85)))
            .foregroundStyle(.white)
    }
}

/// Ô xem thử: nền theme + một nét vuốt mẫu (sóng ngang) vẽ dần trong ~0,5 s rồi nhấc tay.
struct SwipeTrailPreview: UIViewRepresentable {
    let style: SwipeTrailStyle
    let palette: KeyboardPalette
    let play: Int

    func makeUIView(context: Context) -> SwipeTrailPreviewView { SwipeTrailPreviewView() }
    func updateUIView(_ v: SwipeTrailPreviewView, context: Context) { v.update(style: style, palette: palette, play: play) }
}

final class SwipeTrailPreviewView: UIView {
    private var renderer: SwipeTrailRenderer?
    private var style: SwipeTrailStyle = .none
    private var lastPlay = 0
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private static let duration: CFTimeInterval = 0.55

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(style: SwipeTrailStyle, palette: KeyboardPalette, play: Int) {
        backgroundColor = palette.background?.ui ?? (palette.isDark ? UIColor(white: 0.16, alpha: 1)
                                                                    : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1))
        self.style = style
        if style == .none {
            stop(); renderer?.settleNow(); renderer?.layer.removeFromSuperlayer(); renderer = nil
        } else {
            let r = renderer ?? SwipeTrailRenderer()
            if renderer == nil { layer.addSublayer(r.layer); renderer = r }
            r.configure(style: style, trail: palette.trail, accent: palette.accent.alpha(1), dark: palette.isDark)
        }
        if play != lastPlay {
            lastPlay = play
            if bounds.width > 0 { run() } else { DispatchQueue.main.async { [weak self] in self?.run() } }
        }
    }

    private func run() {
        guard let r = renderer, bounds.width > 0 else { return }
        stop()
        r.begin(bounds: bounds)
        start = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// Điểm mẫu ở tỉ lệ f (0…1): sóng ngang qua giữa ô.
    private func point(_ f: CGFloat) -> CGPoint {
        CGPoint(x: bounds.width * (0.1 + 0.8 * f), y: bounds.height * (0.5 + 0.25 * sin(f * 2 * .pi)))
    }

    @objc private func step() {
        guard let r = renderer else { stop(); return }
        let now = CACurrentMediaTime()
        let f = min(1, CGFloat((now - start) / Self.duration))
        r.add(point(f), now)
        r.redraw()
        if f >= 1 {
            stop()
            r.fadeOut(reduceMotion: false)
            r.commitBurst()
        }
    }

    private func stop() { link?.invalidate(); link = nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop(); renderer?.settleNow() }
    }
}
