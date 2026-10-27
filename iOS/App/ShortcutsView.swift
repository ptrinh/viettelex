// Gõ tắt — quản lý bảng (tắt → đầy đủ) trong app chứa. Lưu App Group key "shortcuts"
// ([String: String], giống macOS AppState.shortcuts); bàn phím đọc lúc hiện. Nhập/xuất
// YAML phẳng CÙNG định dạng macOS (ShortcutFile) — một file dùng chung Mac/iPhone/Android.
import SwiftUI
import UniformTypeIdentifiers

enum ShortcutStore {
    static let store = UserDefaults(suiteName: AppFlavor.appGroup)
    static func load() -> [String: String] {
        (store?.dictionary(forKey: ShortcutFile.storeKey) as? [String: String]) ?? [:]
    }
    static func save(_ t: [String: String]) { store?.set(t, forKey: ShortcutFile.storeKey) }

    /// Mốc thêm/sửa từng khoá (ShortcutOrder) — thứ tự "mới nhất trước" của danh sách.
    static func loadTimes() -> [String: Int64] { ShortcutOrder.times(from: store) }
    static func saveTimes(_ t: [String: Int64]) { ShortcutOrder.setTimes(t, in: store) }
}

/// Dòng trong Tính Năng: bật/tắt + mở trang quản lý.
struct ShortcutsSection: View {
    @AppStorage(ShortcutFile.enabledKey, store: UserDefaults(suiteName: AppFlavor.appGroup))
    private var enabled = true
    @State private var count = ShortcutStore.load().count
    @AppStorage(SystemTextReplacement.enabledKey, store: UserDefaults(suiteName: AppFlavor.appGroup))
    private var useSystem = true
    @State private var systemSnapshot = SystemTextReplacement.readSnapshot(ShortcutStore.store)

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Gõ tắt"))
                    Text(L("Gõ chữ tắt rồi dấu cách/dấu câu để bung: ko → không, Ko → Không, KO → KHÔNG. ⌫ ngay sau đó trả lại chữ đã gõ."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                ShortcutsView()
            } label: {
                LabeledContent(L("Bảng gõ tắt"), value: count == 0 ? L("Trống") : L("%@ mục", count))
            }
            if enabled {
                Toggle(isOn: $useSystem) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Dùng Thay thế văn bản của iOS"))
                        Text(L("Bung cả các mục trong Cài đặt → Cài đặt chung → Bàn phím → Thay thế văn bản. Chỉ đọc — sửa trong Cài đặt iOS; trùng chữ tắt thì bảng của VietTelex thắng."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
                if useSystem { systemStatus }
            }
        } header: { Text(L("Gõ tắt")) }
        .onAppear {
            count = ShortcutStore.load().count
            systemSnapshot = SystemTextReplacement.readSnapshot(ShortcutStore.store)
        }
    }
}

extension ShortcutsSection {
    /// App không đọc được UILexicon — bàn phím ghi snapshot (cần Toàn quyền truy cập).
    @ViewBuilder fileprivate var systemStatus: some View {
        if let snap = systemSnapshot {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Đang dùng %@ mục từ Thay thế văn bản của iOS", snap.count))
                if !snap.sample.isEmpty {
                    Text(snap.sample.joined(separator: ", ") + (snap.count > snap.sample.count ? ", …" : ""))
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        } else {
            Text(L("Số mục hiện ở đây sau khi mở bàn phím VietTelex (cần Toàn quyền truy cập để báo về app)."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct ShortcutsView: View {
    @State private var table = ShortcutStore.load()
    @State private var times = ShortcutStore.loadTimes()
    /// Mục vừa thêm/sửa: cuộn tới + tô nền một lúc.
    @State private var highlight: String?
    @State private var query = ""
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var editingKey: String?
    @State private var editKey = ""
    @State private var editValue = ""
    @State private var notice: String?
    @State private var showImporter = false
    @State private var showExporter = false

    private var rows: [(key: String, value: String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ShortcutOrder.sorted(table.keys, times: times).compactMap { k in
            let v = table[k]!
            guard q.isEmpty || k.lowercased().contains(q) || v.lowercased().contains(q) else { return nil }
            return (k, v)
        }
    }

    /// Ghi bảng + mốc thêm/sửa (khoá mới hoặc đổi nội dung ⇒ lên đầu danh sách).
    private func persist() {
        let old = ShortcutStore.load()
        times = ShortcutOrder.updated(times, from: old, to: table, now: ShortcutOrder.nowMs())
        ShortcutStore.save(table)
        ShortcutStore.saveTimes(times)
    }

    private func add() {
        let k = newKey.trimmingCharacters(in: .whitespaces)
        let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ShortcutTable.isValidKey(k) else { notice = L("Chữ tắt không được chứa khoảng trắng."); return }
        guard !v.isEmpty else { return }
        if table[k] != nil { notice = L("“%@” đã có — chạm dòng đó để sửa.", k); return }
        table[k] = v
        newKey = ""; newValue = ""; notice = nil; query = ""
        persist()
        highlight = k
    }

    private func commitEdit() {
        guard let old = editingKey else { return }
        let k = editKey.trimmingCharacters(in: .whitespaces)
        let v = editValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ShortcutTable.isValidKey(k), !v.isEmpty else { notice = L("Chữ tắt không được chứa khoảng trắng."); return }
        if k != old, table[k] != nil { notice = L("“%@” đã có.", k); return }
        table.removeValue(forKey: old)
        table[k] = v
        editingKey = nil; notice = nil
        persist()
        highlight = k
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section {
                TextField(L("Tìm chữ tắt hoặc nội dung…"), text: $query)
                    .textInputAutocapitalization(.never)
                ForEach(rows, id: \.key) { row in
                    if editingKey == row.key {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(L("Chữ tắt"), text: $editKey)
                                .textInputAutocapitalization(.never)
                            TextField(L("Nội dung"), text: $editValue, axis: .vertical)
                                .lineLimit(1...6)
                            HStack {
                                Button(L("Lưu")) { commitEdit() }
                                    .buttonStyle(.borderless)
                                Spacer()
                                Button(L("Huỷ")) { editingKey = nil }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            editKey = row.key; editValue = row.value; editingKey = row.key
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.key).font(.body.monospaced()).foregroundStyle(.primary)
                                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                                Text(row.value).foregroundStyle(.primary).lineLimit(3)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .listRowBackground(highlight == row.key ? Color.accentColor.opacity(0.18) : nil)
                    }
                }
                .onDelete { offsets in
                    let current = rows
                    for i in offsets { table.removeValue(forKey: current[i].key) }
                    persist()
                }
                if table.isEmpty {
                    Text(L("Chưa có gõ tắt nào. Thêm bên dưới, hoặc bấm “Thêm bộ gợi ý”."))
                        .foregroundStyle(.secondary)
                } else if rows.isEmpty {
                    Text(L("Không tìm thấy.")).foregroundStyle(.secondary)
                }
            } header: { Text(L("Bảng gõ tắt (%@)", table.count)) } footer: {
                Text(L("Mới thêm hoặc vừa sửa ở đầu danh sách. Chạm một dòng để sửa, vuốt trái để xoá."))
            }

            Section {
                TextField(L("Chữ tắt (vd: ko, cty, ->)"), text: $newKey)
                    .textInputAutocapitalization(.never)
                TextField(L("Nội dung đầy đủ (được nhiều dòng)"), text: $newValue, axis: .vertical)
                    .lineLimit(1...6)
                Button { add() } label: { Label(L("Thêm"), systemImage: "plus.circle.fill") }
                    .buttonStyle(.borderless)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty
                              || newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let notice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text(L("Thêm mới")) } footer: {
                Text(L("Bung khi gõ dấu cách, Enter hoặc dấu câu ngay sau chữ tắt. Viết chữ tắt thường để tự theo hoa/thường khi gõ. Chữ tắt có ký hiệu hoặc số (->, k2) bung khi gõ dấu cách. Không bung khi dính liền sau số hoặc / # @ (5h, /h3), trong ô mật khẩu, email, URL."))
            }

            Section {
                Button {
                    let missing = ShortcutFile.suggested.filter { table[$0.key] == nil }
                    table.merge(missing) { cur, _ in cur }
                    persist()
                    notice = missing.isEmpty ? L("Bộ gợi ý đã có đủ.") : L("Đã thêm %@ gõ tắt gợi ý.", missing.count)
                } label: { Label(L("Thêm bộ gợi ý"), systemImage: "sparkles") }
                Button { showImporter = true } label: {
                    Label(L("Nhập từ file…"), systemImage: "square.and.arrow.down")
                }
                .fileImporter(isPresented: $showImporter,
                              allowedContentTypes: [.yaml, .json, .plainText, .text, .data]) { result in
                    guard case .success(let url) = result else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                        notice = L("Không đọc được file.")
                        return
                    }
                    let imported = ShortcutFile.parse(text)
                    guard !imported.isEmpty else { notice = L("File không có gõ tắt nào."); return }
                    let r = ShortcutFile.merge(table, imported)
                    table = r.table
                    persist()
                    notice = L("Đã nhập %@ mục: %@ mới, %@ ghi đè.", imported.count, r.added, r.replaced)
                }
                Button { showExporter = true } label: {
                    Label(L("Xuất ra YAML…"), systemImage: "square.and.arrow.up")
                }
                .disabled(table.isEmpty)
                .fileExporter(isPresented: $showExporter,
                              document: TemplatesDocument(text: ShortcutFile.exportYAML(table)),
                              contentType: .yaml,
                              defaultFilename: "viettelex-go-tat") { result in
                    if case .success = result { notice = L("Đã xuất %@ gõ tắt.", table.count) }
                }
            } footer: {
                Text(L("Bộ gợi ý: %@. File YAML “chữ tắt: nội dung” dùng chung với VietTelex trên Mac và Android; nhập sẽ gộp (mục trùng lấy theo file).", ShortcutFile.suggested.keys.sorted().joined(separator: ", ")))
            }
        }
        .navigationTitle(L("Gõ tắt"))
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: highlight) { key in
            guard let key else { return }
            withAnimation { proxy.scrollTo(key, anchor: .center) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if highlight == key { withAnimation { highlight = nil } }
            }
        }
        }
    }
}
