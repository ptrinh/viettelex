// Container app: onboarding + Telex settings (shared with the keyboard via the
// App Group) + a link that opens the Learn site in the browser. Deliberately
// minimal — no WebView, no third-party dependencies (docs/ios-app.md).
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct VietTelexApp: App {
    init() {
        #if DEBUG
        let g = UserDefaults(suiteName: "group.com.viettelex")
        NSLog("DBG kbFullAccess=%d kbLastSeen=%f",
              g?.bool(forKey: "kbFullAccess") ?? false ? 1 : 0,
              g?.double(forKey: "kbLastSeen") ?? -1)
        #endif
    }
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// Màu nhấn thích ứng sáng/tối — xanh đậm ở nền sáng (user: .blue vẫn nhạt),
/// xanh sáng hơn ở nền tối để chữ trắng vẫn nổi rõ.
let accentBlue = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.30, green: 0.52, blue: 1.00, alpha: 1)
        : UIColor(red: 0.02, green: 0.32, blue: 0.84, alpha: 1)
})

/// Bàn phím VietTelex đã được bật trong Cài đặt chưa — quét danh sách bàn phím
/// đang hoạt động tìm bundle id của extension.
func isKeyboardEnabled() -> Bool {
    UITextInputMode.activeInputModes.contains {
        ($0.value(forKey: "identifier") as? String)?
            .hasPrefix("com.viettelex.ios.keyboard") == true
    }
}

/// Các tab của app — floating menu kiểu iOS ở đáy (user 2026-07-24).
/// Tab Mẫu Câu chỉ hiện khi bật tính năng trong Tính Năng → Gợi ý.
enum AppTab: CaseIterable {
    case kieuGo, tinhNang, mauCau, gioiThieu
    var title: String {
        switch self {
        case .kieuGo: return "Kiểu Gõ"
        case .tinhNang: return "Tính Năng"
        case .mauCau: return "Mẫu Câu"
        case .gioiThieu: return "Giới Thiệu"
        }
    }
    var icon: String {
        switch self {
        case .kieuGo: return "keyboard"
        case .tinhNang: return "slider.horizontal.3"
        case .mauCau: return "text.quote"
        case .gioiThieu: return "info.circle"
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardEnabled = isKeyboardEnabled()
    @State private var tryItText = ""
    @State private var tab: AppTab = .kieuGo
    @State private var barCollapsed = false
    @AppStorage("templatesEnabled", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var templatesEnabled = true

    private var visibleTabs: [AppTab] {
        templatesEnabled ? AppTab.allCases
                         : AppTab.allCases.filter { $0 != .mauCau }
    }

    /// "1.0.0 · build 24/07/2026" — ngày build = mtime của binary.
    static var versionLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let exe = (Bundle.main.executableURL ?? Bundle.main.bundleURL).path
        let date = (try? FileManager.default.attributesOfItem(atPath: exe)[.modificationDate]) as? Date ?? Date()
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"
        return "\(v) · build \(f.string(from: date))"
    }

    // Bar tự chế nổi THẬT trên content (user 2026-07-24): system tab bar
    // reserve nguyên dải đáy — hai bên pill lộ nền list thành 2 khối chắn.
    // Overlay + contentMargins để content cuộn xuyên dưới capsule glass.
    var body: some View {
        NavigationStack {
            List {
                switch tab {
                case .kieuGo: kieuGoTab
                case .tinhNang: TinhNangSections()
                case .mauCau: MauCauSections()
                case .gioiThieu: gioiThieuTab
                }
            }
            .navigationTitle(tab == .kieuGo ? "VietTelex" : tab.title)
            .bottomBarScrollMargin()
            .collapseBarOnScroll($barCollapsed)
            // Ô "Thử gõ": cuộn hoặc chạm ra ngoài là đóng bàn phím.
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selected: $tab, tabs: visibleTabs, collapsed: barCollapsed)
        }
        .onChange(of: scenePhase) { phase in
            // Quay lại từ Cài đặt → cập nhật trạng thái bật bàn phím ngay.
            if phase == .active { keyboardEnabled = isKeyboardEnabled() }
        }
        .onChange(of: templatesEnabled) { on in
            if !on && tab == .mauCau { tab = .tinhNang }
        }
        // Bubble ⚙️ trên bàn phím → viettelex://maucau → nhảy thẳng tab Mẫu Câu.
        .onOpenURL { url in
            guard url.scheme == "viettelex" else { return }
            if url.host == "maucau" {
                templatesEnabled = true   // user chủ động mở từ keyboard
                tab = .mauCau
            }
        }
    }

    @ViewBuilder private var kieuGoTab: some View {
        Section {
            OnboardingCard(enabled: keyboardEnabled)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        Section {
            // KHÔNG .autocorrectionDisabled(): bàn phím coi ô autocorrection == .no là
            // ô mã/username → passthrough (literal, tắt Telex) — ô thử gõ mất tác dụng
            // (log Debug mode 25/09/2026: composing=0 mọi phím).
            TextField("Thử gõ tại đây…", text: $tryItText, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
        } header: { Text("Thử gõ") } footer: {
            Text("Bấm 🌐 dưới bàn phím để chuyển sang Tiếng Việt (VietTelex), rồi gõ thử: vieejt → việt.")
        }
        KieuGoSection()
    }

    @ViewBuilder private var gioiThieuTab: some View {
        DebugSection()
        // Logo + tên app trên đầu tab (user 2026-07-24), như About của macOS.
        Section {
            VStack(spacing: 10) {
                if let icon = vtAppIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                } else {
                    Text("⌨️").font(.system(size: 64))
                }
                Text("VietTelex").font(.title2.bold())
                Text("Bàn phím Telex tiếng Việt")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
        Section {
            Link(destination: URL(string: "https://ptrinh.github.io/viettelex/")!) {
                Label("Website", systemImage: "globe")
            }
            Link(destination: URL(string: "https://ptrinh.github.io/viettelex/learn/")!) {
                Label("Học gõ Telex", systemImage: "graduationcap")
            }
            Link(destination: URL(string: "https://github.com/ptrinh/viettelex")!) {
                Label("Mã nguồn trên GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } header: { Text("Tài nguyên") }
        Section {
            LabeledContent("Phiên bản", value: Self.versionLine)
            HStack {
                Text(verbatim: "© Phil Trinh \(String(Calendar.current.component(.year, from: Date())))")
                Spacer()
                Link("vt@trinh.uk", destination: URL(string: "mailto:vt@trinh.uk")!)
                    .foregroundStyle(accentBlue)
            }
            .font(.footnote).foregroundStyle(.secondary)
            Text("Không thu thập dữ liệu · Không theo dõi · Mã nguồn mở")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Toàn quyền Truy cập là tuỳ chọn — chỉ cần cho Rung phím và Mẫu câu động (https://); VietTelex không dùng quyền này cho bất kỳ việc gì khác.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Giới thiệu") }
    }
}

/// Thanh tab nổi Liquid Glass tự chế: capsule ôm đúng nội dung, content cuộn
/// xuyên bên dưới. iOS 26 dùng glassEffect thật (khúc xạ + interactive);
/// iOS cũ fallback material + viền specular. Pill chọn morph bằng
/// matchedGeometryEffect + spring.
struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var tabs: [AppTab] = AppTab.allCases
    /// Cuộn xuống → thu về icon-only (mô phỏng minimize của system bar);
    /// cuộn lên → bung lại đủ label.
    var collapsed = false
    @Namespace private var pillNS

    private var buttons: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { t in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selected = t
                    }
                } label: {
                    // Icon TRÊN text (user 2026-07-24): 4 tab nằm ngang mà
                    // icon+label cùng hàng thì bar dài quá bề ngang màn hình.
                    VStack(spacing: 2) {
                        Image(systemName: t.icon).font(.subheadline.weight(.medium))
                        if !collapsed {
                            Text(t.title).font(.caption2.weight(.semibold))
                                .lineLimit(1).fixedSize()
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, collapsed ? 11 : 12)
                    .padding(.vertical, collapsed ? 9 : 6)
                    .foregroundStyle(selected == t ? Color.white : Color.primary)
                    .background {
                        if selected == t {
                            Capsule()
                                .fill(accentBlue)
                                .matchedGeometryEffect(id: "pill", in: pillNS)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                buttons.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                buttons
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0.06)],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            }
        }
        .padding(.bottom, 8)
    }
}

extension View {
    /// Chừa lối cuộn cho bar nổi: hàng cuối cuộn lên được trên capsule
    /// (iOS 17+; iOS 16 chấp nhận hàng cuối lấp dưới bar một chút).
    @ViewBuilder func bottomBarScrollMargin() -> some View {
        if #available(iOS 17.0, *) {
            self.contentMargins(.bottom, 72, for: .scrollContent)
        } else {
            self
        }
    }

    /// Theo dõi hướng cuộn để thu/bung bar nổi (iOS 18+; máy cũ giữ bar full).
    /// Ngưỡng 3pt lọc rung tay; chỉ thu khi đã cuộn quá 40pt khỏi đỉnh.
    @ViewBuilder func collapseBarOnScroll(_ collapsed: Binding<Bool>) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { old, new in
                guard abs(new - old) > 3 else { return }
                let want = new > old && new > 40
                if want != collapsed.wrappedValue {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        collapsed.wrappedValue = want
                    }
                }
            }
        } else {
            self
        }
    }

    /// Nền card theo Liquid Glass (iOS 26); iOS cũ giữ material xám nhẹ.
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 18) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular,
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.quaternary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Nút hành động chính: glass prominent (iOS 26) / borderedProminent (cũ),
    /// cùng tint accentBlue.
    @ViewBuilder func prominentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(accentBlue)
        } else {
            self.buttonStyle(.borderedProminent).tint(accentBlue)
        }
    }
}

/// Một mẫu câu: text đầy đủ + label tuỳ chọn (emoji/chữ ngắn) để bubble trên
/// bàn phím render gọn.
struct TemplateItem: Equatable, Identifiable {
    var label: String
    var text: String
    var id: String { label + "\u{1}" + text }
}

/// Tab Mẫu Câu — quản lý câu soạn sẵn cho nút ☰ trên bàn phím
/// (App Group key "userTemplates", mỗi entry ["label": …, "text": …]).
struct MauCauSections: View {
    private static let store = UserDefaults(suiteName: "group.com.viettelex")
    /// Mặc định từ ios-mau-cau.yml bundle theo build — cùng file với keyboard.
    private static let defaults: [TemplateItem] = {
        guard let url = Bundle.main.url(forResource: "ios-mau-cau", withExtension: "yml"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [TemplateItem(label: "👋", text: "Chào buổi sáng")] }
        return parseYAML(text)
    }()

    static func load() -> [TemplateItem] {
        guard let raw = store?.array(forKey: "userTemplates") as? [[String: String]] else {
            return defaults
        }
        return raw.compactMap { e in
            guard let t = e["text"], !t.isEmpty else { return nil }
            return TemplateItem(label: e["label"] ?? "", text: t)
        }
    }

    @State private var templates = MauCauSections.load()
    @State private var newLabel = ""
    @State private var newText = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var notice: String?

    private func persist() {
        Self.store?.set(templates.map { ["label": $0.label, "text": $0.text] },
                        forKey: "userTemplates")
    }

    var body: some View {
        Section {
            ForEach(templates) { t in
                HStack {
                    Text(t.label.isEmpty ? "💬" : t.label).frame(minWidth: 30)
                    Text(t.text)
                }
            }
            .onDelete { offsets in
                templates.remove(atOffsets: offsets)
                persist()
            }
            if templates.isEmpty {
                Text("Chưa có mẫu câu nào.").foregroundStyle(.secondary)
            }
        } header: { Text("Mẫu câu (\(templates.count))") } footer: {
            Text("Bấm ☰ trên bàn phím để chèn nhanh. Vuốt trái một dòng để xoá. Label (emoji/chữ ngắn) giúp bubble trên bàn phím gọn hơn.")
        }

        Section {
            HStack {
                TextField("👋", text: $newLabel)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                Divider()
                TextField("Thêm mẫu câu…", text: $newText, axis: .vertical)
                    .lineLimit(1...3)
                Button {
                    let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let l = newLabel.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, !templates.contains(where: { $0.text == t })
                    else { return }
                    templates.append(TemplateItem(label: l, text: t))
                    newLabel = ""; newText = ""
                    persist()
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
.disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: { Text("Thêm mới") } footer: {
            Text("Ô nhỏ bên trái là label (không bắt buộc).")
        }

        Section {
            FullAccessNotice(reason: "Mẫu câu động")
        } header: { Text("Mẫu câu động (https://)") } footer: {
            Text("Mẫu có nội dung bắt đầu bằng https:// sẽ fetch dữ liệu NGAY LÚC BẤM và chèn kết quả (tối đa 1000 bytes) — ví dụ IP❓ chèn địa chỉ IP hiện tại. Chưa cấp Toàn quyền thì bàn phím không có mạng, bấm sẽ chèn chính URL.")
        }

        Section {
            Button {
                showImporter = true
            } label: { Label("Import…", systemImage: "square.and.arrow.down") }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.yaml, .plainText, .text, .data]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    notice = "Không đọc được file."
                    return
                }
                let imported = Self.parseYAML(text)
                let before = templates.count
                for item in imported
                where !templates.contains(where: { $0.text == item.text }) {
                    templates.append(item)
                }
                persist()
                let added = templates.count - before
                notice = "Đã thêm \(added)/\(imported.count) mẫu"
                    + (imported.count > added ? " (trùng bị bỏ qua)." : ".")
            }
            Button {
                showExporter = true
            } label: { Label("Export ra YAML…", systemImage: "square.and.arrow.up") }
            .fileExporter(isPresented: $showExporter,
                          document: TemplatesDocument(text: Self.exportYAML(templates)),
                          contentType: .yaml,
                          defaultFilename: "viettelex-mau-cau") { result in
                if case .success = result { notice = "Đã export \(templates.count) mẫu." }
            }
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
        } footer: {
            Text("YAML phẳng, mỗi dòng “- \"👋 | Chào buổi sáng\"” (label | câu) hoặc “- \"câu\"”. Import gộp thêm, không thay thế.")
        }
    }

    /// Flat YAML: `- "label | text"` hoặc `- text`; bỏ comment/dòng trống.
    static func parseYAML(_ text: String) -> [TemplateItem] {
        text.split(separator: "\n").compactMap { line in
            var s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, !s.hasPrefix("#"), s.hasPrefix("- ") else { return nil }
            s = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
                s = String(s.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
            }
            guard !s.isEmpty else { return nil }
            if let r = s.range(of: " | ") {
                let label = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                let body = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                return body.isEmpty ? nil : TemplateItem(label: label, text: body)
            }
            return TemplateItem(label: "", text: s)
        }
    }

    static func exportYAML(_ items: [TemplateItem]) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "\\\"") }
        return "# VietTelex — mẫu câu (\(items.count))\n"
            + items.map {
                $0.label.isEmpty ? "- \"\(esc($0.text))\""
                                 : "- \"\(esc($0.label)) | \(esc($0.text))\""
            }.joined(separator: "\n") + "\n"
    }
}

/// FileDocument tối giản cho export YAML.
struct TemplatesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.yaml, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Icon app từ asset catalog (AppIcon) — đọc tên file icon từ Info.plist.
/// Dùng chung cho OnboardingCard và header tab Giới Thiệu.
let vtAppIcon: UIImage? = {
    guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
          let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
          let files = primary["CFBundleIconFiles"] as? [String],
          let name = files.last else { return nil }
    return UIImage(named: name)
}()

struct OnboardingCard: View {
    let enabled: Bool

    @ViewBuilder private var hero: some View {
        if let icon = vtAppIcon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Text("⌨️").font(.system(size: 52))
        }
    }

    /// Một dòng checklist: xong = tick xanh, chưa = số thứ tự.
    private func step(_ n: Int, _ title: String, done: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle.fill")
                .foregroundStyle(done ? Color.green : Color.secondary)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if enabled {
                // Đã bật — thu gọn, chỉ xác nhận + nhắc thử gõ.
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2).foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bàn phím đã bật").font(.headline)
                        Text("Thử gõ ngay bên dưới.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                hero
                Text("Bật bàn phím VietTelex").font(.title3.bold())
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Bật bàn phím trong Cài đặt", done: enabled)
                    step(2, "Thử gõ ngay bên dưới", done: false)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cài đặt → Cài đặt chung → Bàn phím → Bàn phím")
                        Text("Thêm bàn phím mới… → Tiếng Việt (VietTelex)")
                        Text("Khi gõ, bấm 🌐 để chuyển sang VietTelex")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.leading, 30)
                }
                .font(.subheadline)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Mở Cài đặt").font(.headline).frame(maxWidth: .infinity)
                }
                .prominentGlassButton()
            }
        }
        .padding(enabled ? 14 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.vertical, 6)
    }
}

/// Cảnh báo + nút mở Settings cho các tính năng cần Toàn quyền Truy cập
/// (Rung phím, Mẫu câu động https://) — dùng chung.
struct FullAccessNotice: View {
    var reason: String
    // Cờ do keyboard extension ghi vào App Group mỗi lần hiện (kbFullAccess) —
    // app chứa không tự hỏi được iOS về Full Access của extension.
    @State private var state = FullAccessNotice.check()

    /// granted: hasFullAccess extension báo về lần chạy gần nhất.
    /// kbSeen: bàn phím đã chạy bản có heartbeat ít nhất một lần chưa —
    /// chưa chạy thì cờ granted không có ý nghĩa.
    static func check() -> (granted: Bool, kbSeen: Bool) {
        guard let g = UserDefaults(suiteName: "group.com.viettelex") else {
            return (false, false)
        }
        return (g.bool(forKey: "kbFullAccess"),
                g.double(forKey: "kbLastSeen") > 0)
    }

    var body: some View {
        Group {
            if state.granted {
                Label {
                    Text("Đã cấp Toàn quyền Truy cập.")
                        .font(.footnote).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                notice
                if !state.kbSeen {
                    Text("Nếu đã bật rồi: mở bàn phím VietTelex một lần (gõ ở app bất kỳ) để app nhận trạng thái quyền.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        // Refresh khi view hiện lại (đổi tab) và khi quay lại từ
        // Settings/bàn phím — cờ chỉ đổi ngoài app.
        .onAppear { state = Self.check() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            state = Self.check()
        }
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("\(reason) cần Toàn quyền Truy cập. Bật trong Cài đặt → Bàn phím → Cho phép Toàn quyền Truy cập. VietTelex không thu thập dữ liệu.")
                    .font(.footnote).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Mở Cài đặt để cấp Toàn quyền")
                    .font(.subheadline.weight(.medium))
            }
            // .borderless bắt buộc: Button nằm chung row trong List mà không
            // set style thì List nuốt tap (row nhiều phần tử tương tác).
            .buttonStyle(.borderless)
            .tint(accentBlue)
        }
    }
}

/// Toggle kèm chú giải nhỏ bên dưới tiêu đề — dùng chung cho 2 tab settings.
private func settingToggle(_ title: String, _ caption: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(caption).font(.footnote).foregroundStyle(.secondary)
        }
    }
    .tint(.green)   // giữ màu toggle hệ thống — .tint(accentBlue) ở TabView lan xuống
}

/// Tab Kiểu Gõ — các tuỳ chọn Telex core (EngineBridge đọc cùng key qua App Group).
struct KieuGoSection: View {
    @AppStorage("freeMarking", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var freeMarking = true
    @AppStorage("simpleTelex", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var simpleTelex = true
    @AppStorage("quickTelex", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var quickTelex = false
    @AppStorage("modernTone", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var modernTone = false
    @AppStorage("teencode", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var teencode = false

    var body: some View {
        Section {
            settingToggle("Telex đơn giản", "Phím w đứng lẻ giữ nguyên là w, không thành ư.", isOn: $simpleTelex)
            settingToggle("Bỏ dấu tự do", "Phím dấu đặt đâu cũng được, không cần đúng thứ tự.", isOn: $freeMarking)
            settingToggle("Gõ nhanh (Quick Telex)", "Phụ âm đôi đầu từ thành phụ âm ghép: cc → ch, nn → ng, tt → th…", isOn: $quickTelex)
            settingToggle("Bỏ dấu kiểu mới", "hoà, thuý thay vì hòa, thúy.", isOn: $modernTone)
            settingToggle("Chính tả teencode", "Chấp nhận cách viết khi chat: w/z/k thay cho qu/d/c (wá, zui zẻ, kó) và bíe, thík, gòy, ừk. Tắt = chỉ chính tả chuẩn, từ tiếng Anh như was, war, zoo giữ nguyên.", isOn: $teencode)
        } header: { Text("Kiểu gõ") } footer: {
            Text("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp.")
        }
    }
}

/// Tab Tính Năng — Chính tả, Gợi ý, Giao diện.
struct TinhNangSections: View {
    @AppStorage("liveSpellCheck", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var liveSpellCheck = true
    @AppStorage("autoRestore", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var autoRestore = true
    @AppStorage("showSpaceLogo", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var showSpaceLogo = true
    @AppStorage("showSuggestions", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var showSuggestions = true
    @AppStorage("filterSensitive", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var filterSensitive = true
    @AppStorage("templatesEnabled", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var templatesEnabled = true
    @AppStorage("rowHeightAdjust", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var rowHeightAdjust = 0
    @AppStorage("hapticFeedback", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var hapticFeedback = false

    var body: some View {
        Section {
            settingToggle("Tự khôi phục từ tiếng Anh", "Từ không phải tiếng Việt tự trả về như đã gõ (google, github…).", isOn: $autoRestore)
            settingToggle("Kiểm tra chính tả khi gõ", "Ngừng bỏ dấu ngay khi từ không thể là tiếng Việt.", isOn: $liveSpellCheck)
        } header: { Text("Chính tả") }

        Section {
            // Thanh gợi ý bật = tự học từ hay dùng (learnWords đi theo, không
            // còn toggle riêng — quyết định 2026-07-24)
            settingToggle("Thanh gợi ý", "Gợi ý từ + emoji, tự học từ bạn hay dùng (chỉ trên máy).", isOn: $showSuggestions)
            settingToggle("Lọc từ nhạy cảm khỏi gợi ý", "Không chủ động gợi ý từ tục — gõ tay và học vẫn bình thường.", isOn: $filterSensitive)
            settingToggle("Mẫu câu", "Nút ☰ trên bàn phím chèn nhanh câu soạn sẵn — quản lý ở tab Mẫu Câu.", isOn: $templatesEnabled)
            Button("Xóa từ đã học", role: .destructive) {
                if let dir = FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: "group.com.viettelex") {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("userlm.plist"))
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("userlm.json"))
                }
            }
        } header: { Text("Gợi ý") }

        Section {
            settingToggle("Hiện logo Vᴛ", "Logo mờ ở góc phải phím space.", isOn: $showSpaceLogo)
            settingToggle("Rung phím", "Rung nhẹ mỗi lần chạm phím.", isOn: $hapticFeedback)
            if hapticFeedback {
                FullAccessNotice(reason: "Rung phím")
            }
            Stepper(value: $rowHeightAdjust, in: -10...10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chiều cao hàng phím")
                    Text(rowHeightAdjust == 0
                         ? "Chuẩn"
                         : String(format: "%+d pt mỗi hàng (%+d pt cả bàn phím)",
                                  rowHeightAdjust, rowHeightAdjust * 4))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: { Text("Giao diện") } footer: {
            Text("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp.")
        }
    }
}

/// Debug mode (25/09/2026): lấy log "gõ nhanh rớt chữ" không cần cáp/Console.
/// Bàn phím ghi touchlog.txt vào App Group (cần Full Access). Log hiện NGAY trong
/// section qua một Toggle — Button mở sheet / present UIKit đều "không hiện ra gì"
/// trên máy user (25/09/2026); Toggle trong cùng Form thì chạy chắc chắn.
struct DebugSection: View {
    @AppStorage("debugTouchLog", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var debugTouchLog = false
    @AppStorage("deferBottomEdge", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var deferBottomEdge = true
    @State private var showLog = false
    @State private var logText = ""
    @State private var clearLog = false

    static var logURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.viettelex")?
            .appendingPathComponent("touchlog.txt")
    }
    private func reload() {
        logText = Self.logURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    var body: some View {
        Section {
            settingToggle("Debug mode — ghi log chạm phím",
                          "Ghi thời điểm chạm, độ trễ, phím nào VÀ CẢ KÝ TỰ BẠN GÕ vào log trong app (chỉ nằm trên máy này, tự xoá được). Đừng gõ mật khẩu khi đang bật. Cần \"Cho phép Toàn quyền\" cho bàn phím. Tắt + Xoá log khi xong.",
                          isOn: $debugTouchLog)
            if debugTouchLog {
                settingToggle("Hoãn cử chỉ hệ thống ở mép dưới",
                              "Thử nghiệm A/B cho lỗi rớt phím: gõ nhanh với BẬT rồi TẮT, so log. Ẩn bàn phím rồi mở lại sau khi đổi.",
                              isOn: $deferBottomEdge)
                settingToggle("Hiện log (tự copy vào clipboard)",
                              "Bật để xem log bên dưới và copy toàn bộ — tắt rồi bật lại để tải log mới.",
                              isOn: $showLog)
                settingToggle("Xoá log", "Bật để xoá log cũ trước khi thử lại.", isOn: $clearLog)
                if showLog {
                    Text(logText.isEmpty
                         ? "Chưa có log. Bật \"Cho phép Toàn quyền\" cho bàn phím VietTelex (Cài đặt → Chung → Bàn phím → Bàn phím → VietTelex), rồi gõ thử."
                         : "\(logText.split(separator: "\n").count) dòng — đã copy vào clipboard.\n\n" + logText.split(separator: "\n").suffix(80).joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } header: { Text("Gỡ lỗi") }
        .onChange(of: showLog) { on in
            guard on else { return }
            reload()
            if !logText.isEmpty { UIPasteboard.general.string = logText }
        }
        .onChange(of: clearLog) { on in
            guard on else { return }
            if let u = Self.logURL { try? FileManager.default.removeItem(at: u) }
            logText = ""
            clearLog = false
        }
    }
}
