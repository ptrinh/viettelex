// TranslateAction.swift
// Công cụ → Dịch (macOS 26+): dịch vùng chọn bằng Apple Translation NGAY TRÊN MÁY, chỉ
// với gói ngôn ngữ đã cài (TranslationSession(installedSource:target:)) — không mạng,
// không server. Chiều dịch + nhận ra tiếng Việt KHÔNG dùng NaturalLanguage: dùng chung
// iOS (iOS/Keyboard/Translate.swift, iOS/Shared/TranslatePrefs.swift — biên dịch theo
// đường dẫn, project.yml). Đọc / thay vùng chọn: TextActionRunner (TextActions.swift).
//
// Miễn phí trên macOS như các công cụ văn bản khác (iOS: Plus) — macOS không có Plus.
// macOS < 26: không có nút Dịch, không có mục trong Cài đặt; Translation.framework được
// weak-link (project.yml) nên bản build vẫn chạy trên macOS 13.
//
// Chi phí khi không dùng = 0: không session, không LanguageAvailability, không cửa sổ —
// tất cả chỉ tạo lúc bấm Dịch (hoặc lúc mở mục Công cụ văn bản trong Cài đặt) rồi thả.
// Gói dịch tải ở Cài đặt: .translationTask → prepareTranslation() (hệ thống hỏi người dùng).

import AppKit
import InputMethodKit
import SwiftUI
#if canImport(Translation)
import Translation
#endif

enum TranslateUI {
    /// Ngôn ngữ cho tên ngôn ngữ đích ("Tiếng Nhật" / "Japanese"): theo lựa chọn giao diện
    /// của VietTelex; "system" ⇒ bản địa hoá macOS đã chọn cho app.
    static var language: String {
        let l = AppState.shared.uiLanguage
        if l == "vi" || l == "en" { return l }
        return Bundle.main.preferredLocalizations.first == "vi" ? "vi" : "en"
    }

    /// Nhãn nút trong bảng Công cụ: "Dịch ↔ Tiếng Anh".
    static func toolTitle(target: String = AppState.shared.translateTarget) -> String {
        String(format: VTLocalized("Translate ↔ %@"), TranslatePrefs.displayName(target, uiLanguage: language))
    }
}

// MARK: - Ô báo nhỏ cạnh con trỏ ("Đang dịch…", thiếu gói)

/// Cùng kiểu panel với bảng Công cụ: không bao giờ thành key, app đang gõ giữ focus +
/// vùng chọn. Chỉ tồn tại khi đang hiện. MAIN thread.
enum TranslateToast {
    private static var window: NSPanel?
    private static var hideWork: DispatchWorkItem?

    /// `sticky` = hiện tới khi `hide()` (đang dịch); không thì tự tắt sau vài giây.
    /// `onClick`: bấm vào ô (vd mở Cài đặt khi thiếu gói).
    static func show(_ text: String, client: IMKTextInput?, sticky: Bool, onClick: (() -> Void)? = nil) {
        hide()
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 3
        label.preferredMaxLayoutWidth = 300
        let fit = label.fittingSize
        let size = NSSize(width: min(ceil(fit.width), 300) + 20, height: ceil(fit.height) + 12)

        let w = ToastWindow(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        w.isFloatingPanel = true
        w.becomesKeyOnlyIfNeeded = true
        w.hidesOnDeactivate = false
        w.level = .popUpMenu
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        w.ignoresMouseEvents = onClick == nil

        let fx = ToastView(frame: NSRect(origin: .zero, size: size))
        fx.material = .popover
        fx.state = .active
        fx.blendingMode = .behindWindow
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 8
        fx.layer?.masksToBounds = true
        if let onClick {
            fx.onClick = { hide(); onClick() }
        }
        label.frame = NSRect(x: 10, y: 6, width: size.width - 20, height: size.height - 12)
        fx.addSubview(label)
        fx.setAccessibilityElement(true)
        fx.setAccessibilityRole(.staticText)
        fx.setAccessibilityLabel(text)
        w.contentView = fx
        w.setFrameOrigin(TextToolsPanel.anchorOrigin(client: client, panelSize: size))
        w.orderFrontRegardless()
        window = w
        if !sticky {
            let work = DispatchWorkItem { hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
        }
    }

    static func hide() {
        hideWork?.cancel()
        hideWork = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    private final class ToastWindow: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class ToastView: NSVisualEffectView {
        var onClick: (() -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) { onClick?() }
    }
}

// MARK: - Cài đặt: ngôn ngữ đích + gói dịch (trong mục Công cụ văn bản)

/// Các dòng "Dịch sang" + trạng thái gói Việt ↔ đích + nút tải. Chỉ dựng khi mục Công cụ
/// văn bản đang mở; LanguageAvailability đọc trong .task của dòng đó (thả khi đóng Cài đặt).
@available(macOS 26.0, *)
struct TranslateSettingsRows: View {
    @EnvironmentObject var model: SettingsModel
    @State private var languages: [String] = []
    @State private var status: LanguageAvailability.Status?
    @State private var config: TranslationSession.Configuration?
    @State private var downloading = false
    @State private var failed = false

    private var target: String { TranslatePrefs.normalized(model.translateTarget) }
    private var lang: String { TranslateUI.language }

    var body: some View {
        // Danh sách ban đầu = danh sách biết trước (để Picker luôn có tag khớp), thay bằng
        // danh sách thật của máy trong .task.
        let ids = languages.isEmpty ? TranslatePrefs.pickerTargets(TranslatePrefs.knownTargets + [target], uiLanguage: lang)
                                    : languages
        Picker(selection: $model.translateTarget) {
            ForEach(ids, id: \.self) { id in
                Text(TranslatePrefs.displayName(id, uiLanguage: lang)).tag(id)
            }
        } label: {
            SettingRowLabel(title: model.loc("Translate to"), caption: model.loc(ToolsTab.C.translate))
        }
        .task {
            let found = await LanguageAvailability().supportedLanguages.map(\.minimalIdentifier)
            languages = TranslatePrefs.pickerTargets((found.isEmpty ? TranslatePrefs.knownTargets : found) + [target],
                                                     uiLanguage: lang)
            await refresh()
        }
        .onChange(of: model.translateTarget) {
            failed = false
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
        HStack {
            Text(String(format: model.loc("Vietnamese ↔ %@"), TranslatePrefs.displayName(target, uiLanguage: lang)))
            Spacer()
            statusLabel
            if status == .supported {
                Button(model.loc("Download")) { download() }
                    .disabled(downloading)
            }
        }
        if failed {
            Text(model.loc("Couldn’t download the translation pack — try again later."))
                .font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch status {
        case .installed:
            Label(model.loc("Downloaded"), systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon).foregroundStyle(.green)
        case .supported:
            if downloading { ProgressView().controlSize(.small) }
            else { Text(model.loc("Not downloaded")).foregroundStyle(.secondary) }
        case .unsupported:
            Text(model.loc("Not supported on this Mac")).foregroundStyle(.secondary)
        default:
            ProgressView().controlSize(.small)
        }
    }

    private func download() {
        failed = false
        downloading = true
        let src = Locale.Language(identifier: TranslatePrefs.vietnamese)
        let dst = Locale.Language(identifier: target)
        if config == nil {
            config = .init(source: src, target: dst)
        } else {
            config?.source = src
            config?.target = dst
            config?.invalidate()
        }
    }

    @MainActor private func refresh() async {
        status = nil
        status = await LanguageAvailability().status(from: Locale.Language(identifier: TranslatePrefs.vietnamese),
                                                     to: Locale.Language(identifier: target))
    }
}
