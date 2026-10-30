// "Chọn giao diện": lưới 2 cột thẻ xem trước (vẽ bằng token theme, không ảnh), chia "Miễn phí" / "Plus" /
// "Giao diện của bạn". Chạm là chọn ngay và ở lại trang (thẻ đang chọn có viền + dấu ✓). Theme Plus bị
// khoá: mờ + nhãn Plus, chạm mở màn VietTelex Plus (như Android).
// Mỗi thẻ có menu ⋯ ("Giao diện JSON"): Chép JSON (miễn phí) · Sửa · Đặt lại mặc định (theme có sẵn đã
// chỉnh) · Xoá (theme tự tạo) — trừ Chép, mọi mục cần Plus. "Dán giao diện" chỉ đọc clipboard khi bấm.
import SwiftUI
import UIKit

private let pickerDefaults = UserDefaults(suiteName: AppFlavor.appGroup)

struct ThemePickerView: View {
    @Binding var settings: ThemeSettings
    let onChange: () -> Void
    @Environment(\.colorScheme) private var scheme
    /// Chạm thẻ Plus bị khoá ⇒ mở màn VietTelex Plus (cùng màn PlusEntryRow mở).
    @State private var showPlus = false
    @State private var store = CustomThemeStore.load(pickerDefaults)
    @State private var editing: Editing?
    @State private var pasteText: PasteText?
    @State private var toast: String?
    @State private var confirmDelete: String?
    /// Theme vừa chọn có âm riêng mà Âm thanh phím đang tắt ⇒ gợi ý (không chặn) + nút "Bật".
    @State private var soundHint = false
    /// Tệp tải về của theme (hỏi → tải → lỗi). Dán / sửa JSON không bao giờ tự tải.
    @ObservedObject private var assets = ThemeAssetCenter.shared

    struct Editing: Identifiable { let id = UUID(); let target: ThemeEditTarget; let title: String; let text: String }
    struct PasteText: Identifiable { let id = UUID(); let text: String }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var customs: [ThemeSpec] {
        store.values.sorted { ($0.name, $0.id ?? "") < ($1.name, $1.id ?? "") }
    }

    var body: some View {
        List {
            if !ThemeGate.allowsWallpaper {
                Section {
                    PlusEntryRow()
                } footer: {
                    Text(L("Theme có nhãn Plus và ảnh nền thuộc VietTelex Plus. Hệ thống, Tối OLED, Tương phản cao và Xám trung tính luôn miễn phí."))
                }
            }
            ForEach(ThemePicker.sections, id: \.title) { section in
                Section {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(section.themes, id: \.self) { builtinCard($0) }
                    }
                    .padding(.vertical, 6)
                } header: { Text(L(section.title)) }
            }
            Section {
                if !customs.isEmpty {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(customs, id: \.id) { customCard($0) }
                    }
                    .padding(.vertical, 6)
                }
                if ThemeGate.allowsCustom {
                    // PasteButton (iOS 16+): hệ thống chỉ trao clipboard khi người dùng bấm — không hỏi "Cho
                    // phép dán", không đọc ngầm. Nhận chuỗi rồi XEM TRƯỚC (chưa ghi gì).
                    HStack {
                        PasteButton(payloadType: String.self) { items in
                            let text = items.first ?? ""
                            DispatchQueue.main.async {
                                if text.isEmpty { toast = L("Clipboard không có văn bản.") } else { pasteText = PasteText(text: text) }
                            }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        Spacer()
                    }
                } else {
                    Button { paste() } label: {
                        HStack(spacing: 6) {
                            Label(L("Dán giao diện"), systemImage: "doc.on.clipboard")
                            plusBadge
                        }
                    }
                }
            } header: { Text(L("Giao diện của bạn")) } footer: {
                Text(L("Dán JSON giao diện đã chép (Plus). Chỉ đọc clipboard khi bạn bấm, xem trước rồi mới thêm."))
            }
            assetStatusSection
        }
        // Chừa chỗ thanh tab nổi — không che "Dán giao diện" / chú thích cuối trang.
        .bottomBarScrollMargin()
        .navigationTitle(L("Chọn giao diện"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlus) { PlusView(model: PlusShared.model) }
        .sheet(item: $editing) { e in
            ThemeJSONEditorView(title: e.title, text: e.text) { text in
                let r = ThemeJSONActions.save(text, to: e.target, settings: &settings, store: &store)
                if r.ok { persist(); offerAssets(for: e.target) }
                return r.issues
            }
        }
        .sheet(item: $pasteText) { p in
            ThemePastePreview(text: p.text) { spec in
                switch ThemeJSONActions.commitPaste(spec, store: &store) {
                case .failure(let e): return e
                case .success(let id):
                    if let s = store[id], let next = ThemePicker.select(custom: s, in: settings) { settings = next; applyExtras() }
                    persist()
                    offerAssets(for: .custom(id))
                    return nil
                }
            }
        }
        .alert(L("Xoá giao diện này?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L("Xoá"), role: .destructive) {
                if let id = confirmDelete { ThemeJSONActions.delete(id, settings: &settings, store: &store); persist() }
                confirmDelete = nil
            }
            Button(L("Huỷ"), role: .cancel) { confirmDelete = nil }
        }
        .alert(L("Tải tệp giao diện?"), isPresented: assets.binding("picker")) {
            Button(L("Tải")) { if let r = assets.pending { assets.accept(r) } }
            Button(L("Để sau"), role: .cancel) { assets.pending = nil }
        } message: { Text(assets.pending?.prompt ?? "") }
        .onAppear { ThemeAssetCenter.collectGarbage(pickerDefaults) }
        .overlay(alignment: .bottom) {
            if soundHint && toast == nil { soundHintBar }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.footnote).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.thinMaterial))
                    .padding(.bottom, 100)   // trên thanh tab nổi
                    .task { try? await Task.sleep(nanoseconds: 1_600_000_000); self.toast = nil }
            }
        }
    }

    private func persist() {
        CustomThemeStore.save(store, pickerDefaults)
        onChange()
        // Dọn tệp không theme nào còn dùng (sau lưu / xoá / dán) — sau onChange (bản vá đã ghi).
        ThemeAssetCenter.collectGarbage(pickerDefaults)
    }

    /// Tệp tải về của theme (theme tự tạo hoặc bản vá theme có sẵn).
    private func assetSpec(_ t: ThemeEditTarget) -> ThemeAssetSpec {
        switch t {
        case .builtin(let b): return settings.effectiveStyle(for: b).assets
        case .custom(let id): return store[id].map { settings.effectiveStyle(id: id, typography: $0.typography).assets } ?? .init()
        }
    }

    /// Có tệp chưa tải ⇒ HỎI (không tải ngay).
    private func offerAssets(for t: ThemeEditTarget) { assets.offer(assetSpec(t)) }

    /// Trạng thái tệp tải về của theme đang chọn: đang tải / lỗi / cảnh báo / còn thiếu (nút tải).
    @ViewBuilder private var assetStatusSection: some View {
        let t: ThemeEditTarget = settings.custom.flatMap { $0.id }.map { .custom($0) } ?? .builtin(settings.theme)
        let spec = assetSpec(t)
        if !spec.isEmpty {
            let errs = assets.errors(for: spec)
            let warns = assets.storedWarnings(spec)
            let missing = assets.missing(spec)
            Section {
                if assets.busy { HStack { ProgressView(); Text(L("Đang tải tệp giao diện…")) } }
                ForEach(Array(errs.enumerated()), id: \.offset) { _, e in
                    Label(ThemeAssetURL.host(e.0) + ": " + e.1.message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red).font(.footnote)
                }
                ForEach(Array(Set(warns.map(\.rawValue)).sorted()), id: \.self) { w in
                    Label(ThemeAssetWarning(rawValue: w)?.message ?? w, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.footnote)
                }
                if !missing.isEmpty, !assets.busy {
                    Button { offerAssets(for: t) } label: {
                        Label(L("Tải %@ tệp còn thiếu", missing.count), systemImage: "arrow.down.circle")
                    }
                } else if missing.isEmpty, errs.isEmpty {
                    Label(L("Đã có đủ tệp của giao diện này."), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.footnote)
                }
            } header: { Text(L("Tệp của giao diện")) } footer: {
                Text(L("Phông / ảnh chỉ tải khi bạn đồng ý, lưu trên máy. Thiếu tệp thì bàn phím dùng màu và phông mặc định."))
            }
        }
    }

    /// Chưa có Plus: "Dán giao diện" mở màn Plus (có Plus thì là PasteButton của hệ thống).
    private func paste() { showPlus = true }

    private func copy(_ t: ThemeEditTarget) {
        guard let text = ThemeJSONActions.copyText(t, settings: settings, store: store) else { return }
        UIPasteboard.general.string = text
        toast = L("Đã chép JSON giao diện.")
    }

    private func edit(_ t: ThemeEditTarget, title: String) {
        guard ThemeGate.allowsCustom else { showPlus = true; return }
        guard let text = ThemeJSONActions.copyText(t, settings: settings, store: store) else { return }
        editing = Editing(target: t, title: title, text: text)
    }

    @ViewBuilder private func menu(_ t: ThemeEditTarget, title: String) -> some View {
        Menu {
            Button { copy(t) } label: { Label(L("Chép JSON"), systemImage: "doc.on.doc") }
            Button { edit(t, title: title) } label: {
                Label(ThemeGate.allowsCustom ? L("Sửa") : L("Sửa") + " · Plus", systemImage: "curlybraces")
            }
            switch t {
            case .builtin(let b):
                if settings.keyStyles[b.rawValue] != nil {
                    Button(role: .destructive) {
                        guard ThemeGate.allowsAdvanced else { showPlus = true; return }
                        ThemeJSONActions.reset(b, settings: &settings); onChange()
                    } label: { Label(L("Đặt lại mặc định"), systemImage: "arrow.uturn.backward") }
                }
            case .custom(let id):
                Button(role: .destructive) {
                    guard ThemeGate.allowsCustom else { showPlus = true; return }
                    confirmDelete = id
                } label: { Label(L("Xoá"), systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.body).foregroundStyle(.secondary)
                .frame(width: 28, height: 24).contentShape(Rectangle())
        }
        .accessibilityLabel(L("Tuỳ chọn giao diện %@", title))
    }

    private func builtinCard(_ t: KeyboardTheme) -> some View {
        let selected = settings.custom == nil && settings.theme == t
        let locked = !ThemeGate.allows(t)
        return cardBody(palette: settings.cardPalette(for: t, systemDark: scheme == .dark), style: settings.effectiveStyle(for: t),
                        title: t.title, selected: selected, locked: locked, showPlus: t.isPlus && locked,
                        menu: menu(.builtin(t), title: t.title)) {
            switch ThemePicker.tap(t, in: settings) {
            case .select(let next): settings = next; onChange(); applyExtras()
            case .openPlus: showPlus = true
            }
        }
    }

    private func customCard(_ c: ThemeSpec) -> some View {
        let id = c.id ?? ""
        let selected = settings.custom?.id == id
        let locked = !ThemeGate.allowsCustom
        return cardBody(palette: settings.cardPalette(custom: c, systemDark: scheme == .dark),
                        style: settings.effectiveStyle(id: id, typography: c.typography),
                        title: c.name, selected: selected, locked: locked, showPlus: locked,
                        menu: menu(.custom(id), title: c.name)) {
            if let next = ThemePicker.select(custom: c, in: settings) {
                settings = next; onChange(); applyExtras(); offerAssets(for: .custom(id))
            }
            else { showPlus = true }
        }
    }

    private func cardBody<M: View>(palette: KeyboardPalette, style: KeyStyle, title: String, selected: Bool, locked: Bool,
                                   showPlus: Bool, menu: M, tap: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: tap) {
                // Thẻ phản ánh tuỳ chỉnh riêng của theme đó (rẻ: vài phép màu, không ảnh).
                ThemePreview(palette: palette, wallpaper: nil, dim: 0, large: false, keyStyle: style)
                    .frame(height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, Color.accentColor).font(.title3).padding(4)
                        }
                    }
                    .opacity(locked ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title + (selected ? L(", đang chọn") : "") + (locked ? " · Plus" : ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
            HStack(spacing: 4) {
                Text(title).font(.footnote).lineLimit(1)
                if showPlus { plusBadge }
                Spacer(minLength: 0)
                menu
            }
            .foregroundStyle(.primary)
        }
    }

    /// Âm / hiệu ứng đi kèm theme vừa chọn (chỉ lúc chọn — ThemeExtras). Không bật âm thanh phím.
    private func applyExtras() {
        soundHint = ThemeExtras.applyOnSelect(settings.effectiveKeyStyle, to: pickerDefaults).soundHint
    }

    private var soundHintBar: some View {
        HStack(spacing: 10) {
            Text(ThemeExtras.hintText).font(.footnote).fixedSize(horizontal: false, vertical: true)
            Button(L("Bật")) {
                pickerDefaults?.set(true, forKey: ThemeExtras.soundOnKey)
                soundHint = false
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))
        .padding(.horizontal, 16)
        .padding(.bottom, 100)   // trên thanh tab nổi
        .task { try? await Task.sleep(nanoseconds: 6_000_000_000); soundHint = false }
    }

    private var plusBadge: some View {
        Text("Plus").font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.85)))
            .foregroundStyle(.white)
    }
}
