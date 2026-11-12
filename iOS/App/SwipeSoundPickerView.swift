// "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt): danh sách kiểu, chạm là chọn + nghe thử một nét vuốt mẫu
// (KeySoundSynth.swipePreviewSamples — cùng vòng lặp + vỏ âm lượng + tiếng nhấc tay với bàn phím) ở âm lượng Âm thanh phím.
// Kiểu Plus chưa có Plus: nhãn Plus, chạm mở VietTelex Plus. Lưu App Group `swipeSound` — bàn phím đọc lần hiện kế.
// "Âm của bạn": chọn file (Files) → SwipeSoundImport (như âm phím tự chọn) + nghe thử + xoá. Android: SwipeSoundPage.kt.
import SwiftUI
import UniformTypeIdentifiers

private let soundDefaults = UserDefaults(suiteName: AppFlavor.appGroup)

struct SwipeSoundPickerView: View {
    @AppStorage(SwipeSoundStyle.key, store: soundDefaults) private var raw = SwipeSoundStyle.defaultValue.rawValue
    @AppStorage("keySoundVolume", store: soundDefaults) private var keySoundVolume = 50
    @State private var showPlus = false
    @State private var importing = false
    @State private var styleBeforeImport: String?
    @State private var customDuration: Double?
    @State private var importMessage: String?

    var body: some View {
        let current = SwipeSoundStyle.displayed(raw)
        List {
            if !SwipeSoundGate.allows {
                Section { PlusEntryRow() }
            }
            Section {
                ForEach(SwipeSoundStyle.allCases, id: \.self) { s in
                    let locked = !SwipeSoundGate.allows(s)
                    Button { tap(s, locked: locked) } label: {
                        HStack(spacing: 6) {
                            Text(s.title).foregroundStyle(locked ? Color.secondary : Color.primary)
                            if locked { SwipeTrailPlusBadge() }
                            Spacer()
                            if current == s { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.title + (current == s ? L(", đang chọn") : "") + (locked ? " · Plus" : ""))
                    .accessibilityAddTraits(current == s ? .isSelected : [])
                }
            } header: {
                Text(L("Chạm một kiểu để chọn và nghe thử."))
            } footer: {
                Text(L("Tiếng khẽ khi ngón đang vuốt một từ: to hơn khi vuốt nhanh, im khi ngón dừng. Nốt nhạc theo phím: mỗi phím ngón đi qua gảy một nốt, mỗi từ thành một giai điệu nhỏ (nhạc cụ theo Âm thanh phím nếu là Piano, Đàn tranh hay Ghi-ta mộc, không thì Đàn tranh). Sáo trúc: cao độ theo vị trí ngón. Roi vụt, Tia sét, Plasma, Đũa phép, Sóng biển, Mèo kêu và Chim hót thêm một tiếng ngắn lúc nhấc tay. Tắt: không phát gì. Bút chì miễn phí, các kiểu còn lại thuộc VietTelex Plus."))
                    + Text(" ") + Text(L("Theo âm lượng của Âm thanh phím; im khi gạt im lặng. Cần Toàn quyền Truy cập; tự về Bút chì khi bật Chế độ nguồn điện thấp."))
            }
            if SwipeSoundGate.allows && (current == .custom || customDuration != nil) {
                Section { customRow }
            }
        }
        .bottomBarScrollMargin()
        .navigationTitle(L("Âm thanh nét vuốt"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlus) { PlusView(model: PlusShared.model) }
        .onAppear { customDuration = SwipeSoundImport.storedDuration() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { handleImport($0) }
        .alert(L("Âm của bạn"), isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button(L("OK"), role: .cancel) { importMessage = nil }
        } message: { Text(importMessage ?? "") }
    }

    /// Hàng "Âm của bạn": độ dài + chọn file + nghe thử + xoá (như Âm thanh gõ → Âm của bạn).
    private var customRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let d = customDuration {
                Text(L("Âm của bạn: %@ giây", String(format: "%.2f", d))).font(.subheadline)
            } else {
                Text(L("Chưa có âm — chọn một file âm thanh (m4a, mp3, wav, caf, aiff); dùng tối đa 3 giây đầu làm vòng lặp."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button(customDuration == nil ? L("Chọn âm thanh…") : L("Chọn âm khác…")) {
                    styleBeforeImport = raw; importing = true
                }
                if customDuration != nil {
                    Button(L("Nghe thử")) { KeyFeedbackPreview.shared.playSwipe(.custom, volume: max(keySoundVolume, 20)) }
                    Button(L("Xoá"), role: .destructive) {
                        SwipeSoundImport.remove()
                        customDuration = nil
                        if raw == SwipeSoundStyle.custom.rawValue { raw = SwipeSoundStyle.fallback.rawValue }
                    }
                }
            }
            .buttonStyle(.borderless)
            Text(L("Bỏ lặng đầu/cuối, nối đuôi vào đầu cho liền, chỉnh độ to như các kiểu khác. File chỉ trên máy này (không tải lên, không sao lưu); thiếu file ⇒ phát Bút chì."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func tap(_ s: SwipeSoundStyle, locked: Bool) {
        if locked { showPlus = true; return }
        if s == .custom && customDuration == nil {
            styleBeforeImport = raw
            raw = s.rawValue
            importing = true
            return
        }
        raw = s.rawValue
        KeyFeedbackPreview.shared.playSwipe(s, volume: max(keySoundVolume, 20))
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let o = try SwipeSoundImport.importFile(url)
                customDuration = o.duration
                raw = SwipeSoundStyle.custom.rawValue
                if o.truncated { importMessage = L("Âm dài hơn 3 giây nên chỉ dùng 3 giây đầu.") }
                KeyFeedbackPreview.shared.playSwipe(.custom, volume: max(keySoundVolume, 20))
            } catch {
                importMessage = error.localizedDescription
                revertAfterFailedImport()
            }
        case .failure:
            revertAfterFailedImport()
        }
        styleBeforeImport = nil
    }

    /// Huỷ/lỗi khi đang chọn "Âm của bạn" mà chưa có file ⇒ quay lại kiểu trước.
    private func revertAfterFailedImport() {
        if customDuration == nil, raw == SwipeSoundStyle.custom.rawValue {
            raw = styleBeforeImport ?? SwipeSoundStyle.defaultValue.rawValue
        }
    }
}
