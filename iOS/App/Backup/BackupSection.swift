// Tính Năng → "Riêng tư & sao lưu", nhóm "Sao lưu & đồng bộ": xuất/nhập file một tệp (JSON, đọc được trên
// Android) + công tắc đồng bộ iCloud (mặc định tắt).
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SaoLuuSection: View {
    @ObservedObject private var sync = ICloudSync.shared
    @AppStorage(ICloudSync.enabledKey, store: UserDefaults(suiteName: BackupStore.appGroupID))
    private var syncEnabled = false
    @AppStorage("backupIncludeLearned", store: UserDefaults(suiteName: BackupStore.appGroupID))
    private var includeLearned = false
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDoc = BackupDocument(data: Data())
    @State private var notice: String?
    /// Sau khôi phục: tệp giao diện (phông / ảnh) KHÔNG nằm trong file sao lưu — hỏi tải lại.
    @ObservedObject private var assetCenter = ThemeAssetCenter.shared

    private static var fileName: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "viettelex-sao-luu-\(f.string(from: Date()))"
    }

    var body: some View {
        Section {
            if ICloudSync.isUnlocked() {
                Toggle(isOn: Binding(get: { syncEnabled },
                                     set: { syncEnabled = $0; sync.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Đồng bộ iCloud"))
                        Text(syncCaption).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            settingToggle(L("Kèm từ đã học khi xuất file"),
                          L("Từ bàn phím đã học (tần suất gõ) — riêng tư, chỉ bật khi file do chính bạn giữ."),
                          isOn: $includeLearned)
            Button {
                let p = BackupStore.appGroup.snapshot(includeLearned: includeLearned)
                exportDoc = BackupDocument(data: BackupCodec.encode(p))
                showExporter = true
            } label: { Label(L("Xuất file sao lưu…"), systemImage: "square.and.arrow.up") }
            .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                          defaultFilename: Self.fileName) { result in
                if case .success = result { notice = L("Đã xuất file sao lưu.") }
            }
            Button {
                showImporter = true
            } label: { Label(L("Nhập file sao lưu…"), systemImage: "square.and.arrow.down") }
            .alert(L("Tải tệp giao diện?"), isPresented: assetCenter.binding("restore")) {
                Button(L("Tải")) { if let r = assetCenter.pending { assetCenter.accept(r) } }
                Button(L("Để sau"), role: .cancel) { assetCenter.pending = nil }
            } message: { Text(assetCenter.pending?.prompt ?? "") }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText, .data]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { notice = L("Không đọc được file."); return }
                do {
                    notice = BackupStore.appGroup.apply(try BackupCodec.decode(data))
                    sync.syncNow()
                    assetCenter.offerAfterRestore(UserDefaults(suiteName: BackupStore.appGroupID))
                } catch let e as BackupError {
                    notice = e.message
                } catch { notice = L("Không đọc được file.") }
            }
            if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text(L("Sao lưu & đồng bộ")) } footer: {
            Text(L("File gồm cài đặt, gõ tắt, mẫu câu (và từ đã học nếu chọn) — mở được trên iPhone, iPad và Android. Nhập: cài đặt theo file, gõ tắt và mẫu câu được gộp thêm."))
        }
    }

    private var syncCaption: String {
        guard syncEnabled else {
            return L("Cài đặt, gõ tắt, mẫu câu giống nhau trên mọi máy cùng tài khoản iCloud. Không đồng bộ từ đã học.")
        }
        if !sync.iCloudAvailable { return L("Máy chưa đăng nhập iCloud — sẽ đồng bộ khi đăng nhập.") }
        guard let d = sync.lastSync else { return L("Đang chờ đồng bộ…") }
        let f = DateFormatter(); f.dateFormat = "HH:mm dd/MM"
        return L("Đồng bộ lần cuối %@.", f.string(from: d))
    }
}
