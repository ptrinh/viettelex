// "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt): danh sách kiểu, chạm là chọn + nghe thử một nét vuốt mẫu
// (KeySoundSynth.swipePreviewSamples — cùng vòng lặp + vỏ âm lượng với bàn phím) ở âm lượng Âm thanh phím. Kiểu Plus
// chưa có Plus: nhãn Plus, chạm mở VietTelex Plus. Lưu App Group `swipeSound` — bàn phím đọc lần hiện kế.
// Android: SwipeSoundPage.kt.
import SwiftUI

private let soundDefaults = UserDefaults(suiteName: AppFlavor.appGroup)

struct SwipeSoundPickerView: View {
    @AppStorage(SwipeSoundStyle.key, store: soundDefaults) private var raw = SwipeSoundStyle.defaultValue.rawValue
    @AppStorage("keySoundVolume", store: soundDefaults) private var keySoundVolume = 50
    @State private var showPlus = false

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
                Text(L("Tiếng khẽ khi ngón đang vuốt một từ, như bút lướt trên giấy: to hơn khi vuốt nhanh, im khi ngón dừng. Tắt: không phát gì. Chổi lông, Phấn bảng và Bút dạ thuộc VietTelex Plus."))
                    + Text(" ") + Text(L("Theo âm lượng của Âm thanh phím; im khi gạt im lặng. Cần Toàn quyền Truy cập; tự về Bút chì khi bật Chế độ nguồn điện thấp."))
            }
        }
        .bottomBarScrollMargin()
        .navigationTitle(L("Âm thanh nét vuốt"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlus) { PlusView(model: PlusShared.model) }
    }

    private func tap(_ s: SwipeSoundStyle, locked: Bool) {
        if locked { showPlus = true; return }
        raw = s.rawValue
        KeyFeedbackPreview.shared.playSwipe(s, volume: max(keySoundVolume, 20))
    }
}
