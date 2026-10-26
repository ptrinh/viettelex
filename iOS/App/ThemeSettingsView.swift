// Chọn theme bàn phím + ảnh nền, có xem trước. Token màu nằm ở
// Keyboard/KeyboardTheme.swift (file dùng chung app + extension).
import SwiftUI
import PhotosUI
import CoreText

private let groupDefaults = UserDefaults(suiteName: "group.com.viettelex")

/// Bản ảnh GỐC chưa mờ, chưa cắt (≤ Wallpaper.sourceMaxEdge; ảnh chọn trước bản có trình
/// chỉnh ≤1080) giữ trong container riêng của app — KHÔNG vào App Group (extension không
/// bao giờ đụng), không vào file sao lưu. Đổi độ mờ / chỉnh khung thì dựng lại ảnh cho bàn
/// phím từ đây, không cần chọn lại ảnh.
private var wallpaperSourceURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("wallpaper-src.jpg")
}

struct ThemeSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var settings = ThemeSettings.load(groupDefaults)
    @State private var pickerItem: PhotosPickerItem?
    @State private var wallpaperImage: UIImage? = Self.loadPreviewImage()
    @State private var busy = false
    @State private var error: String?
    @State private var confirmReset = false
    @State private var editor: EditorInput?
    /// "Tuỳ chỉnh nâng cao" — thu gọn mặc định.
    @State private var advancedOpen = false
    @ObservedObject private var assetCenter = ThemeAssetCenter.shared
    // Tính Năng → Giao diện gộp luôn logo + chiều cao hàng (không thuộc "Khôi phục giao diện gốc").
    @AppStorage("showSpaceLogo", store: groupDefaults) private var showSpaceLogo = true
    /// ±pt mỗi hàng; iPhone: 0 = như bàn phím iPhone của máy (KeyGeometry.RowAdjust — app
    /// chuyển đổi giá trị cũ lúc khởi động, VietTelexApp).
    @AppStorage(KeyGeometry.RowAdjust.key, store: groupDefaults) private var rowHeightAdjust = 0
    /// "Nâng bàn phím" 0…48pt (đệm dưới hàng phím đáy).
    @AppStorage(KeyGeometry.RowAdjust.raiseKey, store: groupDefaults) private var keyboardRaise = 0
    /// "Chiều cao thanh gợi ý" Thấp/Vừa/Cao (SuggestionBarHeight, mặc định Vừa).
    @AppStorage(SuggestionBarHeight.key, store: groupDefaults) private var suggestionBarHeight = SuggestionBarHeight.defaultValue.rawValue
    private var barHeightValue: SuggestionBarHeight { SuggestionBarHeight.parse(suggestionBarHeight) }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    @AppStorage("numberRow", store: groupDefaults) private var numberRow = false
    @AppStorage(KeyGeometry.numberRowFullHeightKey, store: groupDefaults) private var numberRowFullHeight = false
    @AppStorage("showSuggestions", store: groupDefaults) private var showSuggestions = true
    /// Bàn phím tách đôi khi màn hình rộng (SplitLayout.settingKey) — mặc định TẮT.
    @AppStorage("splitKeyboard", store: groupDefaults) private var splitKeyboard = false
    /// "Hiệu ứng khi bấm phím" (Plus, KeyEffect) — trang con KeyEffectPickerView.
    @AppStorage(KeyEffect.key, store: groupDefaults) private var keyEffectRaw = KeyEffect.defaultValue.rawValue
    /// "Bạn đồng hành" (Plus, BuddyCharacter) — trang con BuddyPickerView.
    @AppStorage(BuddyCharacter.key, store: groupDefaults) private var buddyRaw = BuddyCharacter.defaultValue.rawValue
    /// Đã mở trang "Bạn đồng hành" ⇒ nhãn HOT thôi nhún (vẫn hiện).
    @AppStorage("buddyPageSeen") private var buddyPageSeen = false
    /// Thống kê Đập chuột (bàn phím ghi) — đọc lại mỗi lần trang hiện.
    @State private var moleStats = MoleStats.load(groupDefaults)

    /// Ảnh đưa vào trình chỉnh: mới chọn (chưa ghi gì) hoặc bản gốc đã lưu ("Chỉnh ảnh").
    struct EditorInput: Identifiable {
        let id = UUID()
        let image: CGImage
        let crop: WallpaperCrop?
        let isNew: Bool
    }

    /// Cỡ vùng bàn phím dọc hiện tại (khung chỉnh cùng tỉ lệ).
    private var portraitKeyboardSize: CGSize {
        Wallpaper.keyboardSize(screenSize: UIScreen.main.bounds.size,
                               pad: UIDevice.current.userInterfaceIdiom == .pad, landscape: false,
                               rowHeightAdjust: rowHeightAdjust, numberRow: numberRow,
                               suggestions: showSuggestions, raise: keyboardRaise,
                               numberRowFullHeight: numberRowFullHeight, barHeight: barHeightValue)
    }

    /// Strip gợi ý dọc (iPhone: theo bàn phím gốc — KeyGeometry.StockSize.openStrip).
    private var wallpaperStrip: CGFloat {
        let w = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        return Wallpaper.openStrip(width: w, pad: isPad, landscape: false, stock: !isPad, barHeight: barHeightValue)
    }

    private static func loadPreviewImage() -> UIImage? {
        guard let url = Wallpaper.url, let cg = Wallpaper.downsample(url: url, maxPixel: 800) else { return nil }
        return UIImage(cgImage: cg)
    }

    private var hasWallpaperFile: Bool { wallpaperImage != nil }

    var body: some View {
        list.onAppear { moleStats = MoleStats.load(groupDefaults) }
    }

    @ViewBuilder private var list: some View {
        List {
            Section {
                ThemePreview(palette: settings.palette(systemDark: scheme == .dark,
                                                       wallpaperActive: settings.wallpaperActive(fileExists: hasWallpaperFile)),
                             wallpaper: settings.wallpaperActive(fileExists: hasWallpaperFile) ? wallpaperImage : nil,
                             dim: settings.dim, large: true, systemDark: scheme == .dark,
                             keyStyle: settings.effectiveKeyStyle)
                    .frame(height: 190)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text(L("Áp dụng lần mở bàn phím kế tiếp."))
            }

            if !ThemeGate.allowsWallpaper {
                Section {
                    PlusEntryRow()
                } footer: {
                    Text(L("Theme có nhãn Plus và ảnh nền thuộc VietTelex Plus. Hệ thống, Tối OLED và Tương phản cao luôn miễn phí."))
                }
            }

            Section {
                // Bộ theme dài (14) ⇒ chọn ở trang con "Chọn giao diện"; ở đây một dòng tóm tắt.
                NavigationLink {
                    ThemePickerView(settings: $settings, onChange: save)
                } label: {
                    HStack(spacing: 12) {
                        ThemePreview(palette: settings.custom.map { settings.cardPalette(custom: $0, systemDark: scheme == .dark) }
                                        ?? settings.cardPalette(for: settings.theme, systemDark: scheme == .dark),
                                     wallpaper: nil, dim: 0, large: false,
                                     keyStyle: settings.custom.map { settings.effectiveStyle(id: $0.id ?? "", typography: $0.typography) }
                                        ?? settings.effectiveStyle(for: settings.theme))
                            .frame(width: 56, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        Text(L("Giao diện bàn phím"))
                        Spacer()
                        Text(settings.effectiveCustom?.name ?? settings.effectiveTheme.title).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if settings.theme.hasOwnBackground {
                    Toggle(isOn: systemBackdropBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Nền theo hệ thống"))
                            Text(L("Giữ màu phím của theme, nền dùng lớp kính bàn phím của iOS — liền màu với dải 🌐 🎤 bên dưới."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
                    .disabled(settings.wallpaperActive(fileExists: hasWallpaperFile))
                }
            } header: { Text("Theme") }

            // Đập chuột: thẻ thống kê khi theme đang dùng có trò chơi, hoặc đã từng chơi.
            if settings.effectiveKeyStyle.game == MoleGame.themeGame || moleStats.total > 0 {
                Section {
                    MoleStatsCard(stats: moleStats)
                } footer: {
                    Text(L("Gõ như thường — chú chuột thò lên ở phím bạn sắp gõ. Gõ trúng lúc nó đang lên là đập được!"))
                }
            }

            Section {
                NavigationLink {
                    KeyEffectPickerView()
                } label: {
                    HStack(spacing: 6) {
                        Text(L("Hiệu ứng khi bấm phím"))
                        if !KeyEffectGate.allows { plusBadge }
                        Spacer()
                        Text(KeyEffectGate.allows ? KeyEffect.parse(keyEffectRaw).title : KeyEffect.none.title)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                // "Bạn đồng hành" (Plus, KeyboardBuddy) — mục riêng, mặc định Tắt.
                NavigationLink {
                    BuddyPickerView().onAppear { buddyPageSeen = true }
                } label: {
                    HStack(spacing: 6) {
                        Text(L("Bạn đồng hành"))
                        HotBadge(animated: !buddyPageSeen)
                        if !BuddyGate.allows { plusBadge }
                        Spacer()
                        Text(BuddyPolicy.active(setting: BuddyCharacter.parse(buddyRaw),
                                                plus: BuddyGate.allows(BuddyCharacter.parse(buddyRaw))).title)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }

            Section {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(hasWallpaperFile ? L("Đổi ảnh nền") : L("Chọn ảnh nền từ Thư viện"),
                          systemImage: "photo")
                }
                .disabled(busy || !ThemeGate.allowsWallpaper)
                if hasWallpaperFile, hasSourceFile {
                    Button { openEditorForSaved() } label: {
                        Label(L("Chỉnh ảnh"), systemImage: "crop")
                    }
                    .disabled(busy || !ThemeGate.allowsWallpaper)
                }
                if hasWallpaperFile {
                    Toggle(L("Dùng ảnh nền"), isOn: binding(\.wallpaper)).tint(.green)
                    VStack(alignment: .leading) {
                        Text(L("Độ tối lớp phủ: %@%", settings.dim))
                        Slider(value: Binding(get: { Double(settings.dim) },
                                              set: { settings.dim = Int($0); save() }),
                               in: 0...80, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text(L("Độ mờ ảnh: %@", settings.blur))
                        Slider(value: Binding(get: { Double(settings.blur) },
                                              set: { settings.blur = Int($0) }),
                               in: 0...20, step: 1) { editing in
                            if !editing { rerenderBlur() }
                        }
                    }
                    Button(L("Xoá ảnh nền"), role: .destructive) { removeWallpaper() }
                }
                if busy { ProgressView() }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            } header: {
                HStack { Text(L("Ảnh nền")); plusBadge }
            } footer: {
                Text(L("Ảnh được thu nhỏ và nén ngay trên máy, không gửi đi đâu. Lớp phủ giúp chữ trên phím dễ đọc."))
            }

            Section {
                percentSlider(L("Độ trong suốt phím"), \.keyboardTransparency)
                percentSlider(L("Độ trong suốt ký tự"), \.labelTransparency)
            } header: {
                Text(L("Độ trong suốt"))
            } footer: {
                Text(L("Phím: nền và viền phím (cả nền bàn phím khi không dùng ảnh nền) — 100% chỉ còn chữ, ảnh nền vẫn giữ nguyên. Ký tự: chữ và biểu tượng trên phím — 100% là phím trơn không chữ. iOS luôn giữ lớp kính mờ phía sau bàn phím."))
            }

            advancedSection

            Section {
                Stepper(value: $rowHeightAdjust, in: KeyGeometry.RowAdjust.range) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Chiều cao hàng phím"))
                        Text(rowHeightAdjust == 0
                             ? (isPad ? L("Chuẩn") : L("Như bàn phím iPhone"))
                             : String(format: L("%+d pt mỗi hàng (%+d pt cả bàn phím)"),
                                      // phím số = 0.8× phím chữ ⇒ tổng ×4,8 khi bật hàng số (×5 khi cao bằng hàng chữ)
                                      rowHeightAdjust,
                                      Int((Double(rowHeightAdjust) * (numberRow ? 4 + Double(KeyGeometry.numberKeyRatio(fullHeight: numberRowFullHeight)) : 4)).rounded())))
                            .font(.footnote).foregroundStyle(.secondary)
                        if !isPad {
                            Text(L("0 = phím, khe và vị trí như bàn phím gốc của iPhone (theo cỡ máy) — gõ theo thói quen không lệch phím."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Nâng bàn phím"))
                    Text(keyboardRaise == 0 ? L("Tắt") : String(format: L("Cao hơn %d pt"), keyboardRaise))
                        .font(.footnote).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(keyboardRaise) },
                                          set: { v in
                                              let step = Double(KeyGeometry.RowAdjust.raiseStep)
                                              keyboardRaise = KeyGeometry.RowAdjust.clampRaise(Int((v / step).rounded() * step))
                                          }),
                           in: 0...Double(KeyGeometry.RowAdjust.raiseMax),
                           step: Double(KeyGeometry.RowAdjust.raiseStep))
                    Text(L("Thêm khoảng trống dưới hàng phím cuối để bàn phím nằm cao hơn."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Chiều cao thanh gợi ý"))
                    Picker(L("Chiều cao thanh gợi ý"), selection: $suggestionBarHeight) {
                        Text(L("Thấp")).tag(SuggestionBarHeight.low.rawValue)
                        Text(L("Vừa")).tag(SuggestionBarHeight.medium.rawValue)
                        Text(L("Cao")).tag(SuggestionBarHeight.high.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(L("Thanh gợi ý cao hơn thì dễ chạm trúng từ gợi ý hơn; bàn phím cao thêm đúng phần đó. Khi xoay ngang, mức Cao dùng như Vừa."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                settingToggle(L("Hiện logo Vᴛ"), L("Logo mờ ở góc phải phím cách."), isOn: $showSpaceLogo)
                settingToggle(L("Bàn phím tách đôi"), L("Màn hình rộng (iPhone gập khi mở, iPhone xoay ngang, iPad): chia bàn phím làm hai nửa để gõ bằng hai ngón cái. Khi đang tách, gõ vuốt và chế độ một tay tạm tắt."), isOn: $splitKeyboard)
            } header: { Text(L("Bàn phím")) }

            Section {
                Button(L("Khôi phục giao diện gốc"), role: .destructive) { confirmReset = true }
                    .disabled(settings.isDefault)
            } footer: {
                Text(L("Về theme Hệ thống, tắt ảnh nền (ảnh vẫn giữ để bật lại), độ tối/mờ, độ trong suốt và tuỳ chỉnh nâng cao về mặc định. Chiều cao hàng, nâng bàn phím và logo giữ nguyên."))
            }

            GuideLinkSection(page: .giaoDien)
        }
        .navigationTitle(L("Giao diện"))
        .alert(L("Tải tệp giao diện?"), isPresented: assetCenter.binding("settings")) {
            Button(L("Tải")) { if let r = assetCenter.pending { assetCenter.accept(r) } }
            Button(L("Để sau"), role: .cancel) { assetCenter.pending = nil }
        } message: { Text(assetCenter.pending?.prompt ?? "") }
        .navigationBarTitleDisplayMode(.inline)
        .bottomBarScrollMargin()
        .confirmationDialog(L("Khôi phục giao diện gốc?"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Khôi phục"), role: .destructive) { resetAppearance() }
            Button(L("Huỷ"), role: .cancel) {}
        } message: {
            Text(L("Theme, ảnh nền và độ trong suốt về mặc định. Ảnh nền không bị xoá."))
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            importWallpaper(item)
        }
        .fullScreenCover(item: $editor) { input in
            WallpaperEditorView(
                image: input.image, crop: input.crop, keyboardSize: portraitKeyboardSize,
                stripHeight: showSuggestions ? wallpaperStrip : 0,
                bottomPad: CGFloat(KeyGeometry.RowAdjust.clampRaise(keyboardRaise)),
                palette: settings.palette(systemDark: scheme == .dark, wallpaperActive: true),
                dim: settings.dim, blur: settings.blur,
                onCancel: { editor = nil },
                onDone: { crop, dim, blur in
                    editor = nil
                    saveEdited(input, crop: crop, dim: dim, blur: blur)
                })
        }
    }

    // MARK: Tuỳ chỉnh nâng cao (Plus)

    /// Chưa có Plus: hàng mở trang VietTelex Plus (như "VietTelex Plus" đầu trang). Có Plus:
    /// hàng thu gọn mở ra bộ chỉnh. Giá trị đã lưu chỉ áp khi có Plus (ThemeSettings.effectiveKeyStyle).
    @ViewBuilder private var advancedSection: some View {
        Section {
            if ThemeGate.allowsAdvanced {
                DisclosureGroup(isExpanded: $advancedOpen) {
                    advancedControls
                } label: {
                    HStack(spacing: 6) { Text(L("Tuỳ chỉnh nâng cao")); plusBadge }
                }
            } else {
                NavigationLink {
                    PlusView(model: PlusShared.model)
                } label: {
                    HStack(spacing: 6) { Text(L("Tuỳ chỉnh nâng cao")); plusBadge }
                }
            }
        } footer: {
            Text(L("Màu chữ, màu nền phím, màu nhấn, độ bo góc, cỡ chữ, phông và độ đậm — lưu riêng cho từng giao diện. Mỗi màu dùng chung cho sáng lẫn tối; “Theo theme” trả về màu của theme."))
        }
    }

    @ViewBuilder private var advancedControls: some View {
        let palette = settings.palette(systemDark: scheme == .dark,
                                       wallpaperActive: settings.wallpaperActive(fileExists: hasWallpaperFile))
        colorRow(L("Màu chữ trên phím"), \.labelColor, current: palette.keyInk)
        colorRow(L("Màu nền phím"), \.fillColor, current: palette.keyFill)
        // Nhập/hành động, ⇧ bật, vệt gõ vuốt — chữ trên nó tự đổi đen/trắng nếu cần.
        colorRow(L("Màu nhấn"), \.accentColor, current: palette.accent)
        VStack(alignment: .leading) {
            HStack {
                Text(settings.keyStyle.corner.map { L("Độ bo góc phím: %@%", $0) } ?? L("Độ bo góc phím: mặc định"))
                Spacer()
                if settings.keyStyle.corner != nil {
                    Button(L("Mặc định")) { settings.keyStyle.corner = nil; save() }.buttonStyle(.borderless)
                }
            }
            Slider(value: Binding(get: { Double(settings.keyStyle.corner ?? Self.defaultCornerPercent) },
                                  set: { settings.keyStyle.corner = Int($0); save() }),
                   in: 0...100, step: 5) {
                Text(L("Độ bo góc phím"))
            } minimumValueLabel: {
                Image(systemName: "square").accessibilityLabel(L("Vuông"))
            } maximumValueLabel: {
                Image(systemName: "circle").accessibilityLabel(L("Tròn"))
            }
        }
        VStack(alignment: .leading) {
            HStack {
                Text(L("Cỡ chữ trên phím: %@%", settings.keyStyle.fontScale ?? 100))
                Spacer()
                if settings.keyStyle.fontScale != nil {
                    Button(L("Mặc định")) { settings.keyStyle.fontScale = nil; save() }.buttonStyle(.borderless)
                }
            }
            Slider(value: Binding(get: { Double(settings.keyStyle.fontScale ?? 100) },
                                  set: { settings.keyStyle.fontScale = KeyStyle.parseFontScale(Int($0)); save() }),
                   in: Double(KeyStyle.fontScaleMin)...Double(KeyStyle.fontScaleMax), step: 5)
                .accessibilityLabel(L("Cỡ chữ trên phím"))
            Text(L("Phím hẹp tự thu nhỏ chữ cho vừa, dấu không bị cắt."))
                .font(.footnote).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Phông chữ"))
            // Lưới "Vt": phông hệ thống + phông tải về (OFL, viettelex.com). Chọn phông tải về ⇒ HỎI rồi mới tải.
            ThemeFontGrid(selectedSystem: settings.keyStyle.assets.font == nil ? settings.keyStyle.font : nil,
                          selectedAsset: settings.keyStyle.assets.font) { choice in
                switch choice {
                case .system(let f): settings.keyStyle.font = f; settings.keyStyle.assets.font = nil
                case .builtin(let e): settings.keyStyle.font = .standard; settings.keyStyle.assets.font = e.asset
                }
                save()
                ThemeAssetCenter.shared.offer(settings.effectiveKeyStyle.assets, context: "settings")
            }
        }
        Picker(L("Độ đậm"), selection: Binding(get: { settings.keyStyle.weight },
                                              set: { settings.keyStyle.weight = $0; save() })) {
            ForEach(KeyLabelWeight.allCases, id: \.self) { w in Text(w.title).tag(w) }
        }
        // Chỉ theme đang chọn — tuỳ chỉnh của theme khác giữ nguyên.
        Button(L("Đặt lại về mặc định của giao diện"), role: .destructive) { settings.keyStyle = KeyStyle(); save() }
            .disabled(settings.keyStyle.isDefault)
    }

    /// Bo mặc định (8pt trên phím ~42pt) ≈ 40% nửa cạnh ngắn — vị trí thanh trượt khi chưa chỉnh.
    static let defaultCornerPercent = 40

    private func colorRow(_ title: String, _ kp: WritableKeyPath<KeyStyle, UInt32?>, current: RGBA) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { Color(uiColor: settings.keyStyle[keyPath: kp].map { RGBA(hex: $0).ui } ?? RGBA(r: current.r, g: current.g, b: current.b).ui) },
                set: { settings.keyStyle[keyPath: kp] = Self.rgb(UIColor($0)); save() }),
                        supportsOpacity: false)
            if settings.keyStyle[keyPath: kp] != nil {
                Button(L("Theo theme")) { settings.keyStyle[keyPath: kp] = nil; save() }.buttonStyle(.borderless)
            }
        }
    }

    /// UIColor (mọi không gian màu) → 0xRRGGBB sRGB.
    static func rgb(_ c: UIColor) -> UInt32? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func ch(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return ch(r) << 16 | ch(g) << 8 | ch(b)
    }

    @ViewBuilder private var plusBadge: some View {
        Text("Plus").font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.85)))
            .foregroundStyle(.white)
    }

    private func binding(_ kp: WritableKeyPath<ThemeSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: kp] }, set: { settings[keyPath: kp] = $0; save() })
    }

    /// "Nền theo hệ thống" của RIÊNG theme đang chọn.
    private var systemBackdropBinding: Binding<Bool> {
        Binding(get: { settings.systemBackdropThemes.contains(settings.theme) },
                set: { on in
                    if on { settings.systemBackdropThemes.insert(settings.theme) }
                    else { settings.systemBackdropThemes.remove(settings.theme) }
                    save()
                })
    }

    private func save() { settings.save(groupDefaults) }

    private func percentSlider(_ title: String, _ kp: WritableKeyPath<ThemeSettings, Int>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(settings[keyPath: kp])%")
            Slider(value: Binding(get: { Double(settings[keyPath: kp]) },
                                  set: { settings[keyPath: kp] = Int($0); save() }),
                   in: 0...100, step: 5)
                .accessibilityValue("\(settings[keyPath: kp])%")
        }
    }

    private func resetAppearance() {
        let blurChanged = settings.blur != 0
        settings = settings.resetToDefaults()
        // Ảnh đang lưu đã mờ theo độ cũ → dựng lại bản không mờ từ ảnh gốc.
        if blurChanged { rerenderBlur() } else { save() }
    }

    private var hasSourceFile: Bool {
        wallpaperSourceURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Ảnh vừa chọn → trình chỉnh (chưa ghi gì: Huỷ thì ảnh nền cũ còn nguyên).
    private func importWallpaper(_ item: PhotosPickerItem) {
        busy = true; error = nil
        Task {
            // Ảnh gốc chỉ nằm trong RAM của APP (không bao giờ tới extension).
            let data = try? await item.loadTransferable(type: Data.self)
            let image: CGImage? = await Task.detached(priority: .userInitiated) {
                data.flatMap { Wallpaper.downsample(data: $0, maxPixel: Wallpaper.sourceMaxEdge) }
            }.value
            await MainActor.run {
                busy = false
                pickerItem = nil
                guard let image else { error = L("Không đọc được ảnh này."); return }
                editor = EditorInput(image: image, crop: nil, isNew: true)
            }
        }
    }

    /// "Chỉnh ảnh": mở lại bản gốc đã lưu với khung đang dùng (ảnh cũ chưa có khung ⇒
    /// trình chỉnh bắt đầu từ khung cắt giữa — đúng như bàn phím đang hiện).
    private func openEditorForSaved() {
        guard let srcURL = wallpaperSourceURL else { return }
        busy = true; error = nil
        let crop = settings.crop
        Task.detached(priority: .userInitiated) {
            let image = Wallpaper.downsample(url: srcURL, maxPixel: Wallpaper.sourceMaxEdge)
            await MainActor.run {
                busy = false
                guard let image else { error = L("Không đọc được ảnh này."); return }
                editor = EditorInput(image: image, crop: crop, isNew: false)
            }
        }
    }

    /// "Xong": lưu bản gốc (nếu mới chọn) + nướng vùng cắt cho bàn phím.
    private func saveEdited(_ input: EditorInput, crop: WallpaperCrop, dim: Int, blur: Int) {
        busy = true; error = nil
        let image = input.image, isNew = input.isNew
        Task.detached(priority: .userInitiated) {
            let src = isNew ? Wallpaper.encodeSource(image) : nil
            let out = Wallpaper.prepare(source: image, crop: crop, blur: blur)
            await MainActor.run {
                busy = false
                guard let out, !isNew || src != nil else { error = L("Không đọc được ảnh này."); return }
                settings.crop = crop
                settings.dim = dim
                settings.blur = blur
                settings.wallpaper = true
                write(src: src, out: out)
                save()
            }
        }
    }

    private func rerenderBlur() {
        guard let srcURL = wallpaperSourceURL, FileManager.default.fileExists(atPath: srcURL.path) else { save(); return }
        busy = true
        let blur = settings.blur, crop = settings.crop
        Task.detached(priority: .userInitiated) {
            // Khung chuẩn hoá ⇒ đúng với mọi cỡ bản gốc; nil (ảnh cũ) = cả ảnh như trước.
            let out = Wallpaper.downsample(url: srcURL, maxPixel: Wallpaper.sourceMaxEdge)
                .flatMap { Wallpaper.prepare(source: $0, crop: crop, blur: blur) }
            await MainActor.run {
                busy = false
                if let out { write(src: nil, out: out) }
                save()
            }
        }
    }

    private func write(src: Data?, out: Data) {
        do {
            if let src, let u = wallpaperSourceURL {
                try FileManager.default.createDirectory(at: u.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try src.write(to: u, options: .atomic)
            }
            guard let u = Wallpaper.url else { error = L("Không truy cập được App Group."); return }
            try out.write(to: u, options: .atomic)
            settings.version = Date().timeIntervalSince1970   // bàn phím bỏ cache cũ
            wallpaperImage = Self.loadPreviewImage()
        } catch {
            self.error = L("Không lưu được ảnh: %@", error.localizedDescription)
        }
    }

    private func removeWallpaper() {
        if let u = Wallpaper.url { try? FileManager.default.removeItem(at: u) }
        if let u = wallpaperSourceURL { try? FileManager.default.removeItem(at: u) }
        wallpaperImage = nil
        settings.wallpaper = false
        settings.crop = nil
        settings.version = Date().timeIntervalSince1970
        save()
    }
}

/// Bàn phím thu nhỏ vẽ bằng đúng token của theme.
struct ThemePreview: View {
    let palette: KeyboardPalette
    let wallpaper: UIImage?
    let dim: Int
    let large: Bool
    /// Tông backdrop hệ thống giả lập (lộ ra khi nền trong suốt).
    var systemDark: Bool? = nil
    /// Chỉ vẽ phím (lớp phủ trên ảnh trong trình chỉnh ảnh nền).
    var keysOnly = false
    /// Tuỳ chỉnh nâng cao (bo góc, phông, độ đậm, cỡ) — màu đã nằm trong `palette`.
    var keyStyle: KeyStyle = .default
    /// Phông tải về: tải xong (storeVersion đổi) ⇒ vẽ lại bằng phông mới.
    @ObservedObject private var assetCenter = ThemeAssetCenter.shared

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !keysOnly { systemBackdrop }
                if !keysOnly, let bg = palette.background { Color(bg.ui) }
                if !keysOnly, let d = palette.decoration { decoration(d, in: geo.size) }
                if let wallpaper {
                    // Ảnh nền không theo độ trong suốt phím (KeyboardPalette.wallpaperLayer).
                    let wl = palette.wallpaperLayer(dim: dim)
                    Image(uiImage: wallpaper).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .opacity(wl.imageAlpha)
                    Color(wl.overlay.ui)
                }
                keys(in: geo.size)
                // Gaming RGB: viền cầu vồng tĩnh (một gradient che bằng viền phím — như bàn phím thật lúc nghỉ).
                if palette.rainbowBorder {
                    LinearGradient(stops: RainbowBorder.stops().map {
                        Gradient.Stop(color: Color(RGBA(hex: $0.color).ui), location: $0.location)
                    }, startPoint: .leading, endPoint: UnitPoint(x: 2, y: 0.5))
                    .mask(keys(in: geo.size, outline: true))
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// Giả lập backdrop hệ thống (lộ ra ở theme nền trong suốt / khi chỉnh độ trong suốt).
    @ViewBuilder private var systemBackdrop: some View {
        if palette.background?.a == 1 {
            EmptyView()
        } else {
            LinearGradient(colors: systemDark ?? palette.isDark
                           ? [Color(white: 0.16), Color(white: 0.10)]
                           : [Color(red: 0.82, green: 0.84, blue: 0.87), Color(red: 0.76, green: 0.78, blue: 0.82)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// Hoạ tiết nền theo đúng hình học bàn phím thật (KeyboardDecoration), thu theo bề ngang
    /// bàn phím iPhone 390pt để bản thu nhỏ trông như bàn phím thật.
    /// Hoạ tiết ở khe giữa các hàng phím của bản thu nhỏ (cùng lưới `keys(in:)`), cỡ như bàn phím
    /// thật thu theo bề ngang 390pt — chỉ để nhận diện theme.
    private func decoration(_ d: KeyboardDecoration, in size: CGSize) -> some View {
        let gap: CGFloat = large ? 5 : 2, pad: CGFloat = large ? 6 : 3
        let keyH = (size.height - pad * 2 - gap * 3) / 4
        let k = max(size.width, 1) / 390
        // Khe thật của bàn phím ~11pt: phóng khe thu nhỏ về cỡ đó để motif đủ thấy.
        let gaps = (1...3).map { i in
            KeyboardDecoration.Gap(center: Double((pad + CGFloat(i) * keyH + (CGFloat(i) - 0.5) * gap) / k), height: 11)
        }
        let path = d.path(KeyboardDecoration.placements(width: 390, gaps: gaps, density: d.density), width: 390)
        return Path(path).applying(CGAffineTransform(scaleX: k, y: k)).fill(Color(d.color.ui))
    }

    private func keys(in size: CGSize, outline: Bool = false) -> some View {
        let gap: CGFloat = large ? 5 : 2
        let pad: CGFloat = large ? 6 : 3
        let keyW = (size.width - pad * 2 - gap * 9) / 10
        let keyH = (size.height - pad * 2 - gap * 3) / 4
        let radius: CGFloat = large ? 6 : 2.5
        let custom = assetCenter.previewFont(keyStyle.assets.font)
        return VStack(spacing: gap) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(Array(row), id: \.self) { ch in
                        key(large ? String(ch) : "", w: keyW, h: keyH, r: radius, custom: custom, outline: outline)
                    }
                }
            }
            HStack(spacing: gap) {
                key(large ? "123" : "", w: keyW * 2, h: keyH, r: radius, custom: custom,
                    fill: palette.functionFill ?? palette.specialFill, ink: palette.fnInk, outline: outline)
                key(large && !palette.spaceSoundhole ? L("dấu cách") : "", w: keyW * 5 + gap * 4, h: keyH, r: radius, custom: custom,
                    fill: palette.fnFill, outline: outline, soundhole: palette.spaceSoundhole)
                key(large ? "return" : "", w: keyW * 2 + gap, h: keyH, r: radius, custom: custom, fill: palette.accent,
                    ink: palette.accentInk, outline: outline)
            }
        }
        .padding(pad)
    }

    @ViewBuilder
    private func key(_ label: String, w: CGFloat, h: CGFloat, r: CGFloat, custom: CTFontDescriptor?,
                     fill: RGBA? = nil, ink: RGBA? = nil, outline: Bool = false, soundhole: Bool = false) -> some View {
        if outline {
            let rr = KeyStyle.cornerRadius(percent: keyStyle.corner, size: CGSize(width: w, height: h), fallback: r)
            RoundedRectangle(cornerRadius: rr).strokeBorder(Color.black, lineWidth: large ? 1.5 : 1)
                .frame(width: max(w, 1), height: max(h, 1))
        } else if soundhole {
            // Ghi-ta: lỗ thoát âm + hai vành hoa văn (cùng hình học Soundhole của bàn phím thật).
            let rr = CGFloat(Soundhole.radius(width: Double(w), height: Double(h)))
            keyFace(label, w: w, h: h, r: r, custom: custom, fill: fill, ink: ink)
                .overlay(Circle().fill(Color.black.opacity(Soundhole.holeAlpha)).frame(width: 2 * rr, height: 2 * rr))
                .overlay(Circle().stroke(Color(palette.accent.alpha(0.85).ui), lineWidth: CGFloat(Soundhole.rings[0].width) * rr)
                    .frame(width: 2 * rr * CGFloat(Soundhole.rings[0].radius), height: 2 * rr * CGFloat(Soundhole.rings[0].radius)))
                .overlay(Circle().stroke(Color(palette.fnInk.alpha(0.45).ui), lineWidth: CGFloat(Soundhole.rings[1].width) * rr)
                    .frame(width: 2 * rr * CGFloat(Soundhole.rings[1].radius), height: 2 * rr * CGFloat(Soundhole.rings[1].radius)))
        } else {
            keyFace(label, w: w, h: h, r: r, custom: custom, fill: fill, ink: ink)
        }
    }

    private func keyFace(_ label: String, w: CGFloat, h: CGFloat, r: CGFloat, custom: CTFontDescriptor?,
                         fill: RGBA?, ink: RGBA?) -> some View {
        let r = KeyStyle.cornerRadius(percent: keyStyle.corner, size: CGSize(width: w, height: h), fallback: r)
        let base: CGFloat = label.count > 1 ? 11 : 15
        let font: Font = KeyLabelFonts.previewFont(keyStyle, custom: custom,
                                                   size: base * (label.count > 1 ? 1 : keyStyle.labelScale))
            .map { Font($0) } ?? .system(size: base)
        return RoundedRectangle(cornerRadius: r)
            .fill(Color((fill ?? palette.keyFill).ui))
            .overlay(RoundedRectangle(cornerRadius: r)
                .stroke(Color(palette.keyBorder?.ui ?? .clear), lineWidth: palette.keyBorder == nil ? 0 : 1))
            .overlay(Text(label).font(font).minimumScaleFactor(0.5).lineLimit(1)
                .foregroundColor(Color((ink ?? palette.keyInk).ui)))
            .frame(width: max(w, 1), height: max(h, 1))
    }
}

/// Lưới chọn phông: mỗi ô là chữ "Vt" vẽ bằng chính phông đó (không phải "Aa"). Phông tải về chưa tải dùng bản
/// xem trước nhỏ trong app (App/FontPreviews/<id>.ttf — chỉ glyph V, t; OFL như bản đầy đủ).
struct ThemeFontGrid: View {
    enum Choice { case system(KeyLabelFont), builtin(BuiltinFonts.Entry) }
    let selectedSystem: KeyLabelFont?
    let selectedAsset: ThemeFontAsset?
    let onPick: (Choice) -> Void

    private let columns = [GridItem(.adaptive(minimum: 70), spacing: 8)]

    /// Phông xem trước "Vt" (bundle app), nạp một lần.
    static let previews: [String: UIFont] = {
        var out: [String: UIFont] = [:]
        for e in BuiltinFonts.list {
            guard let u = Bundle.main.url(forResource: e.id, withExtension: "ttf"),
                  let ds = CTFontManagerCreateFontDescriptorsFromURL(u as CFURL) as? [CTFontDescriptor],
                  let d = ds.first else { continue }
            out[e.id] = CTFontCreateWithFontDescriptor(d, 26, nil) as UIFont
        }
        return out
    }()

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(KeyLabelFont.allCases, id: \.self) { f in
                tile(Font(KeyLabelFonts.make(f, .regular, size: 26, compact: nil)), title: f.title,
                     selected: selectedSystem == f) { onPick(.system(f)) }
            }
            ForEach(BuiltinFonts.list, id: \.id) { e in
                tile(Self.previews[e.id].map { Font($0) } ?? .system(size: 26), title: e.name,
                     selected: selectedAsset?.ref == e.ref, download: true) { onPick(.builtin(e)) }
            }
        }
    }

    private func tile(_ font: Font, title: String, selected: Bool, download: Bool = false,
                      tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 2) {
                Text(verbatim: "Vt").font(font).lineLimit(1).frame(height: 36)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if download { Image(systemName: "arrow.down.circle").font(.caption2).foregroundStyle(.secondary).padding(3) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + (selected ? L(", đang chọn") : ""))
    }
}

/// "Hôm nay đập N con chuột 🐭" + chuỗi dài nhất / tổng (theme Đập chuột).
struct MoleStatsCard: View {
    let stats: MoleStats
    var body: some View {
        HStack(spacing: 12) {
            Text("🐭").font(.system(size: 34))
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Hôm nay đập %@ con chuột 🐭", stats.count(on: MoleStats.dayNumber())))
                    .font(.headline)
                Text(L("Chuỗi dài nhất: %@ · Tổng: %@", stats.best, stats.total))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Nhãn "HOT" (mục mới cần gây chú ý): viên đỏ-cam, nhún + loé sáng nhẹ tới khi user mở trang lần đầu;
/// Giảm chuyển động ⇒ đứng yên.
struct HotBadge: View {
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let on = animated && !reduceMotion
        Text("HOT").font(.caption2.weight(.heavy))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.23, blue: 0.19), .orange],
                                                      startPoint: .leading, endPoint: .trailing)))
            .foregroundStyle(.white)
            .shadow(color: .orange.opacity(on && pulse ? 0.8 : 0), radius: on && pulse ? 4 : 0)
            .scaleEffect(on && pulse ? 1.12 : 1)
            .animation(on ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = on }
            .onChange(of: on) { v in pulse = v }
            .accessibilityLabel(L("Mới"))
    }
}
