// TextActions.swift
// Công cụ văn bản cho VÙNG CHỌN ở app bất kỳ: Thêm dấu (đoạn không dấu → có dấu) +
// HOA / thường / Hoa Đầu Từ / Hoa đầu câu / Xoá dấu. Gọi từ menu VietTelex (IMK) hoặc
// phím tắt Thêm dấu (TextActionHotkey). KHÔNG BAO GIỜ chạy theo phím gõ: không có
// observer, timer hay cache nào sống ngoài một lần bấm.
//
// Logic thuần dùng chung với iOS/Android, biên dịch theo đường dẫn (project.yml):
// TextTools.swift (fixture chung text-tools.txt) và AddTones.swift + lexicon.
//
// Dịch (macOS 26+): Apple Translation ngay trên máy, gói ngôn ngữ đã cài — xem
// TranslateAction.swift (chiều dịch dùng chung iOS: Translate.swift + TranslatePrefs.swift).
//
// Thêm dấu chạy trong PROCESS CON (`VietTelex --add-tones`, stdin → stdout): bảng
// lexicon/bigram/tiếng Anh giải mã ra ~1 MB heap dạng `static let` — nạp trong process
// IME thì sống tới hết phiên đăng nhập. Process con thoát là trả sạch RAM.
//
// Đọc vùng chọn: AX kAXSelectedText → IMK attributedSubstring → ⌘C (khôi phục clipboard).
// Thay: IMK insertText (thay đúng vùng chọn, không đụng clipboard) → ⌘V rồi trả lại
// clipboard cũ. Secure input / ô mật khẩu: không đọc, không copy, chỉ beep.

import AppKit
import Carbon.HIToolbox
import InputMethodKit

enum TextAction: String, CaseIterable {
    case addTones, upper, lower, title, sentence, stripDiacritics, translate

    /// Khoá VTLocalized (vi.lproj dịch).
    var titleKey: String {
        switch self {
        case .addTones: return "Add tones to selection"
        case .upper: return "UPPERCASE"
        case .lower: return "lowercase"
        case .title: return "Title Case"
        case .sentence: return "Sentence case"
        case .stripDiacritics: return "Remove tones"
        case .translate: return "Translate"
        }
    }

    var textTool: TextTool? {
        switch self {
        case .addTones, .translate: return nil
        case .upper: return .upper
        case .lower: return .lower
        case .title: return .title
        case .sentence: return .sentence
        case .stripDiacritics: return .stripDiacritics
        }
    }
}

// MARK: - Biến đổi (thuần, trừ Thêm dấu đi qua process con)

enum TextActionTransform {
    /// Trần độ dài vùng chọn (UTF-16) — to hơn thì không xử lý (dán nhầm cả tài liệu).
    static let maxLength = 20_000
    static let helperFlag = "--add-tones"

    /// Thêm dấu trong process hiện tại — chỉ process con và test gọi.
    static func addTonesInProcess(_ text: String) -> String {
        AddTones.restore(text.precomposedStringWithCanonicalMapping).text
    }

    /// nil = không đổi gì / không xử lý được.
    static func apply(_ action: TextAction, _ text: String, addTones: (String) -> String?) -> String? {
        guard !text.isEmpty, (text as NSString).length <= maxLength else { return nil }
        let out: String?
        if let tool = action.textTool { out = TextTools.apply(tool, text) } else { out = addTones(text) }
        guard let out, !out.isEmpty, !out.unicodeScalars.elementsEqual(text.unicodeScalars) else { return nil }
        return out
    }

    /// `main.swift` gọi đầu tiên: đang là process con thì đọc stdin, ghi kết quả, thoát.
    static func runHelperIfRequested() {
        guard CommandLine.arguments.dropFirst().first == helperFlag else { return }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let input = String(decoding: data, as: UTF8.self)
        FileHandle.standardOutput.write(Data(addTonesInProcess(input).utf8))
        exit(0)
    }

    /// Chạy process con (ĐỪNG gọi trên main — chờ tới `timeout`).
    static func addTonesViaHelper(_ text: String, timeout: TimeInterval = 5) -> String? {
        guard let exe = Bundle.main.executableURL else { return nil }
        let p = Process()
        p.executableURL = exe
        p.arguments = [helperFlag]
        // Môi trường trống: không thừa hưởng biến XCTest/DYLD của process cha.
        p.environment = [:]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        // Đọc stdout song song: kết quả lớn hơn buffer pipe thì process con không bị kẹt.
        var output = Data()
        let reader = DispatchQueue(label: "com.viettelex.addtones.read")
        let readDone = DispatchSemaphore(value: 0)
        reader.async {
            output = outPipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        inPipe.fileHandleForWriting.write(Data(text.utf8))
        try? inPipe.fileHandleForWriting.close()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return nil
        }
        _ = readDone.wait(timeout: .now() + 1)
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: output, as: UTF8.self)
    }
}

// MARK: - Đọc / thay vùng chọn

enum TextActionRunner {
    /// Một thao tác tại một thời điểm (bấm hotkey liên tục không chồng ⌘C/⌘V lên nhau).
    private static var busy = false

    /// MAIN thread. `client` = client IMK khi gọi từ menu VietTelex; nil khi từ hotkey.
    static func run(_ action: TextAction, client: IMKTextInput?) {
        guard !busy else { return }
        guard !IsSecureEventInputEnabled() else { return fail("secure input") }
        let trusted = Accessibility.isTrusted
        let focused = trusted ? focusedElement() : nil
        if let focused, isSecureField(focused) { return fail("password field") }
        busy = true
        NotificationCenter.default.post(name: .telexResetComposition, object: nil)

        // `same`: vùng chọn vẫn là chữ đã đọc? Chỉ Dịch dùng (kết quả về sau một lúc —
        // người dùng gõ tiếp / bôi đen chỗ khác thì KHÔNG ghi đè).
        if let focused, let s = axSelectedText(focused) {
            transform(action, s, client: client, clipboard: nil, same: { axSelectedText(focused) == s })
        } else if let client, let s = imkSelectedText(client) {
            transform(action, s, client: client, clipboard: nil, same: { imkSelectedText(client) == s })
        } else if trusted {
            // ⌘C: không đọc lại vùng chọn được (lại ⌘C) ⇒ chỉ chắc app + ô đang gõ chưa đổi.
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            PasteboardBridge.copySelection { s, snapshot in
                guard let s, !s.isEmpty else {
                    snapshot?.restore()
                    return fail("no selection (copy)")
                }
                transform(action, s, client: client, clipboard: snapshot, same: {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
                    switch (focused, focusedElement()) {
                    case (nil, nil): return true
                    case let (a?, b?): return CFEqual(a, b)
                    default: return false
                    }
                })
            }
        } else {
            fail("no selection, no Accessibility")
        }
    }

    private static func transform(_ action: TextAction, _ text: String, client: IMKTextInput?,
                                  clipboard: PasteboardBridge.Snapshot?, same: @escaping () -> Bool) {
        if action == .translate {
            return translate(text, client: client, clipboard: clipboard, same: same)
        }
        let finish: (String?) -> Void = { result in
            guard let result else {
                clipboard?.restore()
                return fail("\(action.rawValue): unchanged")
            }
            replace(with: result, client: client, clipboard: clipboard)
            busy = false
            DebugLog.log("text-action \(action.rawValue): \((text as NSString).length) → \((result as NSString).length) chars")
        }
        if action == .addTones {
            DispatchQueue.global(qos: .userInitiated).async {
                let r = TextActionTransform.apply(action, text) { TextActionTransform.addTonesViaHelper($0) }
                DispatchQueue.main.async { finish(r) }
            }
        } else {
            finish(TextActionTransform.apply(action, text) { _ in nil })
        }
    }

    // MARK: Dịch (bất đồng bộ — Apple Translation)

    /// Lần dịch đang chờ; tăng khi xong / hết giờ ⇒ kết quả về muộn bị bỏ.
    private static var translateGen = 0
    /// Trần chờ một bản dịch (gói đã cài thường < 1 s).
    static let translateTimeout: TimeInterval = 20

    private static func translate(_ text: String, client: IMKTextInput?,
                                  clipboard: PasteboardBridge.Snapshot?, same: @escaping () -> Bool) {
        guard #available(macOS 26.0, *) else {
            clipboard?.restore()
            return fail("translate: macOS < 26")
        }
        let target = AppState.shared.translateTarget
        guard (text as NSString).length <= TextActionTransform.maxLength,
              let pair = TranslateDirection.resolve(detected: TranslateText.detect(text, target: target),
                                                    target: target) else {
            clipboard?.restore()
            return fail("translate: nothing to translate")
        }
        let core = TranslateText.splitWhitespace(text).core
        translateGen &+= 1
        let gen = translateGen
        TranslateToast.show(VTLocalized("Translating…"), client: client, sticky: true)
        // Session sống trong OnDeviceTranslator.translate (Task tách khỏi main), nhả ngay sau.
        Task.detached(priority: .userInitiated) {
            let r = await OnDeviceTranslator.translate(core, pair: pair)
            DispatchQueue.main.async {
                guard gen == translateGen else { return }      // đã hết giờ
                translateGen &+= 1
                finishTranslate(r, text, pair: pair, client: client, clipboard: clipboard, same: same)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + translateTimeout) {
            guard gen == translateGen else { return }
            translateGen &+= 1
            TranslateToast.hide()
            clipboard?.restore()
            fail("translate: timed out")
        }
    }

    private static func finishTranslate(_ r: Result<String, TranslateFailure>, _ text: String,
                                        pair: TranslateDirection.Pair, client: IMKTextInput?,
                                        clipboard: PasteboardBridge.Snapshot?, same: () -> Bool) {
        TranslateToast.hide()
        switch r {
        case .success(let out):
            let result = TranslateText.rewrap(original: text, translated: out)
            guard !TranslateText.splitWhitespace(out).core.isEmpty,
                  !result.unicodeScalars.elementsEqual(text.unicodeScalars) else {
                clipboard?.restore()
                return fail("translate: unchanged")
            }
            guard same() else {
                clipboard?.restore()
                busy = false
                return DebugLog.log("text-action translate: selection changed while waiting — not written")
            }
            replace(with: result, client: client, clipboard: clipboard)
            busy = false
            DebugLog.log("text-action translate \(pair.source)→\(pair.target): \((text as NSString).length) → \((result as NSString).length) chars")
        case .failure(let f):
            clipboard?.restore()
            busy = false
            DebugLog.log("text-action translate \(pair.source)→\(pair.target) failed: \(f)")
            switch f {
            case .notInstalled:
                TranslateToast.show(VTLocalized("Translation pack not downloaded — open VietTelex Settings → Suggestions & tools."),
                                    client: client, sticky: false) {
                    SettingsWindowController.shared.show(tab: .tools)
                }
            case .unsupported:
                TranslateToast.show(VTLocalized("This Mac can’t translate this language pair."),
                                    client: client, sticky: false)
            case .unknownLanguage, .failed:
                NSSound.beep()
            }
        }
    }

    private static func replace(with result: String, client: IMKTextInput?,
                                clipboard: PasteboardBridge.Snapshot?) {
        if let client {
            // NotFound = thay vùng chọn hiện tại (như gõ đè lên chữ đang bôi đen) —
            // đúng cả ở app bỏ qua replacementRange.
            client.insertText(result, replacementRange: NSRange(location: NSNotFound, length: 0))
            clipboard?.restore()
            NotificationCenter.default.post(name: .telexResetComposition, object: nil)
        } else {
            PasteboardBridge.paste(result, restoring: clipboard)
        }
    }

    private static func fail(_ why: String) {
        busy = false
        DebugLog.log("text-action skipped: \(why)")
        NSSound.beep()
    }

    // MARK: AX / IMK

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.2)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let el = ref, CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
        let element = el as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)
        return element
    }

    private static func isSecureField(_ el: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &ref) == .success else { return false }
        return (ref as? String) == (kAXSecureTextFieldSubrole as String)
    }

    private static func axSelectedText(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &ref) == .success,
              let s = ref as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func imkSelectedText(_ client: IMKTextInput) -> String? {
        let sel = client.selectedRange()
        guard sel.location != NSNotFound, sel.length > 0,
              sel.length <= TextActionTransform.maxLength,
              let s = client.attributedSubstring(from: sel)?.string,
              (s as NSString).length == sel.length else { return nil }
        return s
    }
}

// MARK: - Clipboard (⌘C / ⌘V) — luôn trả lại nội dung cũ

enum PasteboardBridge {
    /// Toàn bộ item + mọi kiểu dữ liệu của clipboard lúc chụp.
    final class Snapshot {
        private let items: [[(NSPasteboard.PasteboardType, Data)]]
        init(_ pb: NSPasteboard = .general) {
            items = (pb.pasteboardItems ?? []).map { item in
                item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
            }
        }
        func restore(_ pb: NSPasteboard = .general) {
            pb.clearContents()
            let restored: [NSPasteboardItem] = items.map { pairs in
                let it = NSPasteboardItem()
                for (t, d) in pairs { it.setData(d, forType: t) }
                return it
            }
            if !restored.isEmpty { pb.writeObjects(restored) }
        }
    }

    /// Quy ước nspasteboard.org: trình quản lý clipboard bỏ qua nội dung tạm của mình.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func copySelection(_ completion: @escaping (String?, Snapshot?) -> Void) {
        let pb = NSPasteboard.general
        let snapshot = Snapshot(pb)
        let before = pb.changeCount
        whenModifiersReleased {
            postCommand("c")
            poll(tries: 25) {
                guard pb.changeCount != before else { return false }
                completion(pb.string(forType: .string), snapshot)
                return true
            } timeout: {
                completion(nil, nil)          // clipboard không đổi → không có gì để trả
            }
        }
    }

    static func paste(_ text: String, restoring snapshot: Snapshot?) {
        let pb = NSPasteboard.general
        let original = snapshot ?? Snapshot(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: transientType)
        let ours = pb.changeCount
        whenModifiersReleased {
            postCommand("v")
            // App đọc clipboard bất đồng bộ sau ⌘V — trả lại sớm quá thì nó dán bản cũ.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if pb.changeCount == ours { original.restore(pb) }
            }
        }
    }

    /// Hotkey (⌃⌥T…) còn đang giữ thì ⌘C gửi đi thành ⌃⌥⌘C — đợi nhả (tối đa ~1s).
    private static func whenModifiersReleased(_ body: @escaping () -> Void) {
        let mods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        poll(tries: 50) {
            guard CGEventSource.flagsState(.combinedSessionState).intersection(mods).isEmpty else { return false }
            body()
            return true
        } timeout: { body() }
    }

    private static func poll(tries: Int, _ check: @escaping () -> Bool, timeout: @escaping () -> Void) {
        if check() { return }
        guard tries > 0 else { return timeout() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { poll(tries: tries - 1, check, timeout: timeout) }
    }

    /// ⌘ + phím ra `letter` trên layout đang dùng (Dvorak: phím khác QWERTY).
    static func keyCode(for letter: Character) -> CGKeyCode {
        let fallback: CGKeyCode = letter == "c" ? CGKeyCode(kVK_ANSI_C) : CGKeyCode(kVK_ANSI_V)
        guard let ascii = letter.asciiValue,
              let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let t = KeyboardLayoutTranslator(layoutID: "live", source: src),
              let code = t.keyCode(forASCII: ascii, shift: false) else { return fallback }
        return CGKeyCode(code)
    }

    private static func postCommand(_ letter: Character) {
        let src = CGEventSource(stateID: .privateState)
        src?.userData = SyntheticKeyboard.magic       // tap/IMK nhận ra là phím của mình
        let key = keyCode(for: letter)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
