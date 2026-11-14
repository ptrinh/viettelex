// Dịch trên máy (Plus) — chọn ngôn ngữ đích + tải gói dịch Apple cho cặp Việt ↔ đích.
// Bàn phím không tải gói được (TranslationSession(installedSource:) không xin tải) nên
// việc tải nằm ở app: .translationTask → prepareTranslation() để hệ thống hỏi người dùng.
// Lối vào: màn Plus (dòng "Dịch trên máy") và viettelex://dich từ chip báo thiếu gói.
import SwiftUI
#if canImport(Translation)
import Translation
#endif

@available(iOS 26.0, *)
struct TranslateSettingsView: View {
    @AppStorage(TranslatePrefs.targetKey, store: UserDefaults(suiteName: PlusConfig.appGroup))
    private var storedTarget = TranslatePrefs.defaultTarget
    @AppStorage(TranslatePrefs.aiKey, store: UserDefaults(suiteName: PlusConfig.appGroup))
    private var useAI = false
    @State private var aiAvailable = false
    @State private var languages: [String] = []
    @State private var status: LanguageAvailability.Status?
    @State private var config: TranslationSession.Configuration?
    @State private var downloading = false
    @State private var failed = false

    private var target: String { TranslatePrefs.normalized(storedTarget) }

    var body: some View {
        List {
            Section {
                Picker(L("Dịch sang"), selection: $storedTarget) {
                    ForEach(languages, id: \.self) { id in
                        Text(TranslatePrefs.displayName(id)).tag(id)
                    }
                }
                .pickerStyle(.navigationLink)
            } footer: {
                Text(L("Chip “Dịch ↔ …” dịch chữ sang ngôn ngữ này; chữ vốn đã là ngôn ngữ này thì dịch về tiếng Việt."))
            }

            Section {
                HStack {
                    Text(L("Tiếng Việt ↔ %@", TranslatePrefs.displayName(target)))
                    Spacer()
                    statusLabel
                }
                if status == .supported {
                    Button {
                        failed = false
                        downloading = true
                        if config == nil {
                            config = .init(source: Locale.Language(identifier: TranslatePrefs.vietnamese),
                                           target: Locale.Language(identifier: target))
                        } else {
                            config?.source = Locale.Language(identifier: TranslatePrefs.vietnamese)
                            config?.target = Locale.Language(identifier: target)
                            config?.invalidate()
                        }
                    } label: {
                        HStack {
                            Text(L("Tải gói dịch"))
                            if downloading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(downloading)
                }
                if failed {
                    Text(L("Chưa tải được gói dịch — thử lại sau.")).font(.footnote).foregroundStyle(.red)
                }
            } header: { Text(L("Gói dịch")) } footer: {
                Text(L("Gói dịch của Apple tải một lần, sau đó dịch hoàn toàn trên máy — chữ bạn gõ không gửi đi đâu. Xoá gói: Cài đặt → Ứng dụng → Dịch thuật."))
            }

            // Chỉ hiện khi máy có Apple Intelligence dùng được (hoặc đã bật trước đó — để tắt được).
            if aiAvailable || useAI {
                Section {
                    Toggle(L("Dịch bằng Apple Intelligence (thử nghiệm)"), isOn: $useAI)
                } footer: {
                    Text(L("Dịch tự nhiên hơn, hiểu ngữ cảnh và thành ngữ nhưng chậm hơn; lỗi hoặc quá lâu thì dùng Apple Translation. Vẫn chạy hoàn toàn trên máy."))
                }
            }
        }
        .navigationTitle(L("Dịch trên máy"))
        .task {
            let ids = await LanguageAvailability().supportedLanguages.map(\.minimalIdentifier)
            languages = TranslatePrefs.pickerTargets((ids.isEmpty ? TranslatePrefs.knownTargets : ids) + [target])
            aiAvailable = AIAvailability.isAvailable
            await refresh()
        }
        .onChange(of: storedTarget) {
            Task { await refresh() }
        }
        .translationTask(config) { session in
            var ok = true
            do { try await session.prepareTranslation() } catch { ok = false }
            await MainActor.run {
                downloading = false
                failed = !ok
            }
            await refresh()
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch status {
        case .installed:
            Label(L("Đã tải"), systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon).foregroundStyle(.green)
        case .supported:
            Text(L("Chưa tải")).foregroundStyle(.secondary)
        case .unsupported:
            Text(L("Máy không hỗ trợ")).foregroundStyle(.secondary)
        default:
            ProgressView()
        }
    }

    @MainActor private func refresh() async {
        status = nil
        let s = await LanguageAvailability().status(from: Locale.Language(identifier: TranslatePrefs.vietnamese),
                                                    to: Locale.Language(identifier: target))
        status = s
    }
}
