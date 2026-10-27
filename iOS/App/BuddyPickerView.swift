// "Bạn đồng hành" (Plus): lưới chọn Tắt / Cô gái / Chàng trai / Mèo / Gà con — mỗi ô là BuddyView thật
// trên nền theme đang dùng. Mở trang: mọi nhân vật nhảy một tràng (như đang gõ) rồi ngủ; chạm ô là chọn +
// xem lại. Ô Plus bị khoá: mờ + nhãn Plus, chạm mở VietTelex Plus. Lưu App Group `keyboardBuddy`
// (BuddyCharacter.key) — bàn phím đọc lần hiện kế. Dưới lưới: "Kiểu vẽ" Hoạt hình | Vẽ nét của nhân vật đang
// chọn (BuddyStyle, khoá `buddyStyle.<id>`); mỗi ô vẽ theo kiểu của nhân vật đó. "Vị trí & cỡ" (BuddyPlacement:
// cỡ 1…20, lề phải / lề trên −100…100 pt, nấc 5) chung mọi nhân vật. Android: BuddyPage.kt.
import SwiftUI
import UIKit

private let buddyDefaults = UserDefaults(suiteName: AppFlavor.appGroup)

struct BuddyPickerView: View {
    @AppStorage(BuddyCharacter.key, store: buddyDefaults) private var raw = BuddyCharacter.defaultValue.rawValue
    @Environment(\.colorScheme) private var scheme
    @State private var showPlus = false
    /// Số lần chạm từng ô — đổi ⇒ ô diễn lại.
    @State private var plays: [BuddyCharacter: Int] = [:]
    /// Kiểu vẽ từng nhân vật (BuddyStyle.key) — đọc một lần lúc mở trang, ghi thẳng App Group khi đổi.
    @State private var styles: [BuddyCharacter: BuddyStyle] =
        Dictionary(uniqueKeysWithValues: BuddyCharacter.allCases.map { ($0, BuddyStyle.load(buddyDefaults, $0)) })
    @State private var names: [BuddyCharacter: String] =
        Dictionary(uniqueKeysWithValues: BuddyCharacter.allCases.map { ($0, buddyDefaults?.string(forKey: BuddyName.key($0)) ?? "") })
    @AppStorage(BuddyBirthday.monthKey, store: buddyDefaults) private var birthdayMonth = 0
    @AppStorage(BuddyBirthday.dayKey, store: buddyDefaults) private var birthdayDay = 0

    @AppStorage(BuddyPlacement.sizeKey, store: buddyDefaults) private var size = BuddyPlacement.defaultSize
    @AppStorage(BuddyPlacement.padRightKey, store: buddyDefaults) private var padRight = 0
    @AppStorage(BuddyPlacement.padTopKey, store: buddyDefaults) private var padTop = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private var current: BuddyCharacter { BuddyCharacter.parse(raw) }

    var body: some View {
        let theme = ThemeSettings.load(buddyDefaults)
        let palette = theme.palette(systemDark: scheme == .dark, wallpaperActive: false)
        // Vẽ nét xem thử mặc trang phục mùa lễ như trên bàn phím (theme lễ / ngày).
        let today = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        let season = BuddySeason.resolve(themeID: theme.effectiveTheme.rawValue,
                                         year: today.year ?? 0, month: today.month ?? 0, day: today.day ?? 0)
        // ĐỌC state ngay trong body: ô lưới (LazyVGrid) dựng lười, đọc ở đó thì SwiftUI không coi body phụ thuộc ⇒
        // đổi kiểu vẽ (chỉ ghi styles / plays) không vẽ lại ô xem thử (Phil: chọn Vẽ nét mà preview không đổi).
        let styles = self.styles, plays = self.plays
        List {
            if !BuddyGate.allows {
                Section { PlusEntryRow() }
            }
            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(BuddyCharacter.allCases, id: \.self) {
                        tile($0, palette: palette, season: season, style: styles[$0, default: .defaultValue].resolved(for: $0),
                             play: plays[$0, default: 0])
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text(L("Chạm một ô để chọn và xem thử."))
            } footer: {
                Text(L("Nhân vật nhỏ ở góc phải thanh gợi ý: gõ thì nhảy — gõ càng nhanh nhảy càng sung — ngừng gõ thì cuộn tròn ngủ. Chỉ chuyển động khi đang gõ; Chế độ nguồn điện thấp chỉ hiện dáng đứng yên."))
            }
            if current != .off && BuddyGate.allows(current) {
                Section {
                    TextField(L("Đặt tên"), text: Binding(
                        get: { names[current, default: ""] },
                        set: { let v = BuddyName.clean($0); names[current] = v; buddyDefaults?.set(v, forKey: BuddyName.key(current)) }))
                        .textInputAutocapitalization(.words)
                } header: { Text(L("Đặt tên") + " · " + current.title) }
                if BuddyStyle.hasAtlas(current) {
                    Section {
                        Picker(L("Kiểu vẽ"), selection: Binding(
                            get: { styles[current, default: .defaultValue] },
                            set: { setStyle($0, for: current) })) {
                            ForEach(BuddyStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    } header: {
                        Text(L("Kiểu vẽ") + " · " + current.title)
                    } footer: {
                        Text(L("Hoạt hình: hình vẽ sẵn, giữ nguyên quanh năm. Vẽ nét: mặc trang phục mùa lễ (Tết, Trung Thu, Halloween, Giáng sinh) và có thêm điệu nhảy."))
                    }
                } else {
                    Section { Text(L("Chỉ có kiểu Vẽ nét")).foregroundStyle(.secondary) }
                }
                Section {
                    Stepper(value: $size, in: BuddyPlacement.sizeRange) {
                        valueRow(L("Cỡ"), "\(size)")
                    }
                    Stepper(value: $padRight, in: BuddyPlacement.padRange, step: BuddyPlacement.padStep) {
                        valueRow(L("Lề phải"), "\(padRight) pt")
                    }
                    Stepper(value: $padTop, in: BuddyPlacement.padRange, step: BuddyPlacement.padStep) {
                        valueRow(L("Lề trên"), "\(padTop) pt")
                    }
                    Button(L("Mặc định")) {
                        size = BuddyPlacement.defaultSize; padRight = 0; padTop = 0
                    }
                    .disabled(size == BuddyPlacement.defaultSize && padRight == 0 && padTop == 0)
                } header: {
                    Text(L("Vị trí & cỡ"))
                } footer: {
                    Text(L("Chung cho mọi nhân vật. Lề phải dương: dời sang trái; lề trên dương: dời xuống. Bàn phím áp dụng lần hiện kế."))
                }
            }
            Section {
                Toggle(L("Sinh nhật của bạn"), isOn: Binding(
                    get: { birthdayMonth > 0 && birthdayDay > 0 },
                    set: { if $0 { birthdayMonth = 1; birthdayDay = 1 } else { birthdayMonth = 0; birthdayDay = 0 } }))
                if birthdayMonth > 0 {
                    Picker(L("Tháng"), selection: $birthdayMonth) {
                        ForEach(1...12, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker(L("Ngày"), selection: $birthdayDay) {
                        ForEach(1...([31,29,31,30,31,30,31,31,30,31,30,31][birthdayMonth - 1]), id: \.self) {
                            Text("\($0)").tag($0)
                        }
                    }
                    .onChange(of: birthdayMonth) { v in
                        if (1...12).contains(v) { birthdayDay = min(birthdayDay, [31,29,31,30,31,30,31,31,30,31,30,31][v - 1]) }
                    }
                }
            } footer: { Text(L("Chỉ lưu trên thiết bị và trong bản sao lưu.")) }
        }
        .bottomBarScrollMargin()
        .navigationTitle(L("Bạn đồng hành"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlus) { PlusView(model: PlusShared.model) }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func tile(_ c: BuddyCharacter, palette: KeyboardPalette, season: BuddySeason?, style: BuddyStyle,
                      play: Int) -> some View {
        let locked = !BuddyGate.allows(c)
        let selected = current == c
        return VStack(spacing: 6) {
            Button { tap(c, locked: locked) } label: {
                BuddyPreview(character: c, style: style, season: season, palette: palette, play: play)
                    .overlay(Color.clear.contentShape(Rectangle()))
                    .frame(height: 96)
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
            .accessibilityLabel(c.title + (selected ? L(", đang chọn") : "") + (locked ? " · Plus" : ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
            HStack(spacing: 4) {
                Text(names[c].flatMap { $0.isEmpty ? nil : $0 } ?? c.title).font(.footnote).lineLimit(1)
                if locked { plusBadge }
                Spacer(minLength: 0)
            }
        }
    }

    private func tap(_ c: BuddyCharacter, locked: Bool) {
        if locked { showPlus = true; return }
        raw = c.rawValue
        plays[c, default: 0] += 1
    }

    /// Đổi kiểu vẽ: ghi App Group (bàn phím đọc lần hiện kế) + ô diễn lại theo kiểu mới.
    private func setStyle(_ s: BuddyStyle, for c: BuddyCharacter) {
        styles[c] = s
        buddyDefaults?.set(s.rawValue, forKey: BuddyStyle.key(c))
        plays[c, default: 0] += 1
    }

    private var plusBadge: some View {
        Text("Plus").font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.85)))
            .foregroundStyle(.white)
    }
}

/// Ô xem thử: nền theme + BuddyView thật (cả người, to hơn trên bàn phím).
struct BuddyPreview: UIViewRepresentable {
    let character: BuddyCharacter
    let style: BuddyStyle
    let season: BuddySeason?
    let palette: KeyboardPalette
    let play: Int

    func makeUIView(context: Context) -> BuddyPreviewView { BuddyPreviewView() }
    func updateUIView(_ v: BuddyPreviewView, context: Context) {
        v.update(character: character, style: style, season: season, palette: palette, play: play)
    }
}

final class BuddyPreviewView: UIView {
    private var buddy: BuddyView?
    private let off = UILabel()
    private var lastPlay = -1
    private var demo: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        off.text = "—"
        off.textAlignment = .center
        off.font = .systemFont(ofSize: 28, weight: .light)
        addSubview(off)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { demo?.invalidate() }

    func update(character: BuddyCharacter, style: BuddyStyle, season: BuddySeason?, palette: KeyboardPalette, play: Int) {
        backgroundColor = palette.background?.ui ?? (palette.isDark ? UIColor(white: 0.16, alpha: 1)
                                                                    : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1))
        off.textColor = palette.barInk.ui.withAlphaComponent(0.5)
        off.isHidden = character != .off
        if character == .off { buddy?.removeFromSuperview(); buddy = nil; return }
        if buddy?.character != character || buddy?.artStyle != style || buddy?.season != season {
            buddy?.halt(); buddy?.removeFromSuperview()
            let b = BuddyView(character: character, bar: palette.buddyBar, lowPower: false, framing: .full,
                              season: season, artStyle: style)
            b.maxFigureHeight = 88
            addSubview(b)
            buddy = b
            setNeedsLayout()
        }
        buddy?.setBar(palette.buddyBar)
        if play != lastPlay { lastPlay = play; startDemo() }
    }

    /// Một tràng "gõ" ~2,6 s nhanh dần (lên tới bậc cao nhất) rồi thôi ⇒ lắc nhẹ ~8 s rồi ngủ.
    private func startDemo() {
        demo?.invalidate()
        var n = 0
        let t = Timer(timeInterval: 0.11, repeats: true) { [weak self] t in
            n += 1
            self?.buddy?.keyPressed()
            if n >= 24 { t.invalidate() }
        }
        RunLoop.main.add(t, forMode: .common)
        demo = t
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        off.frame = bounds
        buddy?.frame = bounds.insetBy(dx: 4, dy: 4)
    }
}
