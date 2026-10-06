// Chọn theme bàn phím + ảnh nền, có xem trước. Token màu nằm ở
// Keyboard/KeyboardTheme.swift (file dùng chung app + extension).
import SwiftUI
import PhotosUI

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
    // Tính Năng → Giao diện gộp luôn logo + chiều cao hàng (không thuộc "Khôi phục giao diện gốc").
    @AppStorage("showSpaceLogo", store: groupDefaults) private var showSpaceLogo = true
    @AppStorage("rowHeightAdjust", store: groupDefaults) private var rowHeightAdjust = 0
    @AppStorage("numberRow", store: groupDefaults) private var numberRow = false
    @AppStorage("showSuggestions", store: groupDefaults) private var showSuggestions = true
    /// Bàn phím tách đôi khi màn hình rộng (SplitLayout.settingKey) — mặc định TẮT.
    @AppStorage("splitKeyboard", store: groupDefaults) private var splitKeyboard = false

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
                               suggestions: showSuggestions)
    }

    private static func loadPreviewImage() -> UIImage? {
        guard let url = Wallpaper.url, let cg = Wallpaper.downsample(url: url, maxPixel: 800) else { return nil }
        return UIImage(cgImage: cg)
    }

    private var hasWallpaperFile: Bool { wallpaperImage != nil }

    var body: some View {
        List {
            Section {
                ThemePreview(palette: settings.palette(systemDark: scheme == .dark,
                                                       wallpaperActive: settings.wallpaperActive(fileExists: hasWallpaperFile)),
                             wallpaper: settings.wallpaperActive(fileExists: hasWallpaperFile) ? wallpaperImage : nil,
                             dim: settings.dim, large: true, systemDark: scheme == .dark)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(KeyboardTheme.allCases, id: \.self) { t in
                        themeTile(t)
                    }
                }
                .padding(.vertical, 6)
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
                Text(L("Phím: nền, ảnh nền, nền và viền phím — 100% chỉ còn chữ. Ký tự: chữ và biểu tượng trên phím — 100% là phím trơn không chữ. iOS luôn giữ lớp kính mờ phía sau bàn phím."))
            }

            Section {
                Stepper(value: $rowHeightAdjust, in: -10...10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Chiều cao hàng phím"))
                        Text(rowHeightAdjust == 0
                             ? L("Chuẩn")
                             : String(format: L("%+d pt mỗi hàng (%+d pt cả bàn phím)"),
                                      // hàng số cao ¾ hàng chữ ⇒ tổng ×4,75 khi bật
                                      rowHeightAdjust,
                                      Int((Double(rowHeightAdjust) * (numberRow ? 4.75 : 4)).rounded())))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                settingToggle(L("Hiện logo Vᴛ"), L("Logo mờ ở góc phải phím cách."), isOn: $showSpaceLogo)
                settingToggle(L("Bàn phím tách đôi"), L("Màn hình rộng (iPhone gập khi mở, iPhone xoay ngang, iPad): chia bàn phím làm hai nửa để gõ bằng hai ngón cái. Khi đang tách, gõ vuốt và chế độ một tay tạm tắt."), isOn: $splitKeyboard)
            } header: { Text(L("Bàn phím")) }

            Section {
                Button(L("Khôi phục giao diện gốc"), role: .destructive) { confirmReset = true }
                    .disabled(settings.isDefault)
            } footer: {
                Text(L("Về theme Hệ thống, tắt ảnh nền (ảnh vẫn giữ để bật lại), độ tối/mờ và độ trong suốt về mặc định. Chiều cao hàng và logo giữ nguyên."))
            }

            GuideLinkSection(page: .giaoDien)
        }
        .navigationTitle(L("Giao diện"))
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
                stripHeight: showSuggestions ? Wallpaper.suggestionStrip : 0,
                palette: settings.palette(systemDark: scheme == .dark, wallpaperActive: true),
                dim: settings.dim, blur: settings.blur,
                onCancel: { editor = nil },
                onDone: { crop, dim, blur in
                    editor = nil
                    saveEdited(input, crop: crop, dim: dim, blur: blur)
                })
        }
    }

    @ViewBuilder private var plusBadge: some View {
        Text("Plus").font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.85)))
            .foregroundStyle(.white)
    }

    private func themeTile(_ t: KeyboardTheme) -> some View {
        let selected = settings.theme == t
        let locked = !ThemeGate.allows(t)
        return Button {
            guard !locked else { return }
            settings.theme = t
            save()
        } label: {
            VStack(spacing: 6) {
                ThemePreview(palette: t.palette(systemDark: scheme == .dark),
                             wallpaper: nil, dim: 0, large: false)
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: selected ? 3 : 1))
                HStack(spacing: 3) {
                    Text(t.title).font(.caption).lineLimit(1)
                    if t.isPlus { plusBadge }
                }
                .foregroundStyle(.primary)
            }
            .opacity(locked ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title + (selected ? L(", đang chọn") : ""))
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

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !keysOnly { systemBackdrop }
                if !keysOnly, let bg = palette.background { Color(bg.ui) }
                if let wallpaper {
                    Image(uiImage: wallpaper).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .opacity(palette.surfaceAlpha)
                    Color(palette.wallpaperOverlay.alpha(Double(dim) / 100 * palette.surfaceAlpha).ui)
                }
                keys(in: geo.size)
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

    private func keys(in size: CGSize) -> some View {
        let gap: CGFloat = large ? 5 : 2
        let pad: CGFloat = large ? 6 : 3
        let keyW = (size.width - pad * 2 - gap * 9) / 10
        let keyH = (size.height - pad * 2 - gap * 3) / 4
        let radius: CGFloat = large ? 6 : 2.5
        return VStack(spacing: gap) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(Array(row), id: \.self) { ch in
                        key(large ? String(ch) : "", w: keyW, h: keyH, r: radius)
                    }
                }
            }
            HStack(spacing: gap) {
                key(large ? "123" : "", w: keyW * 2, h: keyH, r: radius, fill: palette.specialFill)
                key(large ? L("dấu cách") : "", w: keyW * 5 + gap * 4, h: keyH, r: radius)
                key(large ? "return" : "", w: keyW * 2 + gap, h: keyH, r: radius, fill: palette.accent,
                    ink: palette.accentInk)
            }
        }
        .padding(pad)
    }

    private func key(_ label: String, w: CGFloat, h: CGFloat, r: CGFloat,
                     fill: RGBA? = nil, ink: RGBA? = nil) -> some View {
        RoundedRectangle(cornerRadius: r)
            .fill(Color((fill ?? palette.keyFill).ui))
            .overlay(RoundedRectangle(cornerRadius: r)
                .stroke(Color(palette.keyBorder?.ui ?? .clear), lineWidth: palette.keyBorder == nil ? 0 : 1))
            .overlay(Text(label).font(.system(size: label.count > 1 ? 11 : 15))
                .foregroundColor(Color((ink ?? palette.keyInk).ui)))
            .frame(width: max(w, 1), height: max(h, 1))
    }
}
