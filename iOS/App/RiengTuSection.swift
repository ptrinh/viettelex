import SwiftUI

/// Tính Năng → "Riêng tư & sao lưu" (phần đầu; SaoLuuSection theo sau): Lịch sử clipboard + Chế độ ẩn danh. Bàn phím đọc
/// cùng key qua App Group (ClipboardFeature.historyKey / incognitoKey).
struct RiengTuSection: View {
    @AppStorage("clipboardHistory", store: UserDefaults(suiteName: AppFlavor.appGroup))
    private var clipboardHistory = false
    @AppStorage("incognitoMode", store: UserDefaults(suiteName: AppFlavor.appGroup))
    private var incognitoMode = false
    /// "Giữ lịch sử clipboard": "1h" (mặc định) / "24h" / "7d" — bàn phím đọc khi hiện
    /// (Keyboard/ClipboardHistory.swift `ClipboardTTL`; cùng khoá + id Android).
    @AppStorage("clipboardTTL", store: UserDefaults(suiteName: AppFlavor.appGroup))
    private var clipboardTTL = "1h"

    var body: some View {
        Section {
            toggle(L("Lịch sử clipboard"),
                   L(SettingCaption.clipboardHistory),
                   isOn: $clipboardHistory)
            if clipboardHistory {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Giữ lịch sử clipboard"))
                        Text(L(SettingCaption.clipboardTTL)).font(.footnote).foregroundStyle(.secondary)
                    }
                    Picker(L("Giữ lịch sử clipboard"), selection: Binding(
                        get: { ["1h", "24h", "7d"].contains(clipboardTTL) ? clipboardTTL : "1h" },
                        set: { clipboardTTL = $0 })) {
                        Text(L("1 giờ")).tag("1h")
                        Text(L("24 giờ")).tag("24h")
                        Text(L("7 ngày")).tag("7d")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                FullAccessNotice(reason: L("Lịch sử clipboard"))
            }
        } header: { Text("Clipboard") } footer: {
            VStack(alignment: .leading, spacing: 6) {
                // Hai giới hạn của iOS (06/11/2026: trước là một hàng riêng dài + đoạn ghi chú dài).
                if clipboardHistory {
                    Text(L(SettingCaption.clipboardPasteAllowIos))
                    Text(Self.iosLimitNote)
                }
                Text(L(SettingCaption.clipboardOffClears))
            }
        }
        Section {
            toggle(L("Chế độ ẩn danh"),
                   L(SettingCaption.incognitoIos),
                   isOn: $incognitoMode)
        } header: { Text(L("Riêng tư")) }
    }

    /// Giới hạn iOS (bàn phím chỉ đọc clipboard khi đang hiện) — nói rõ để không tưởng là lỗi.
    static var iosLimitNote: String {
        L(SettingCaption.clipboardIosLimit)
    }

    private func toggle(_ title: String, _ caption: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .tint(.green)
    }
}
