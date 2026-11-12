// TextToolRunner — áp TextTools lên ô gõ qua proxy (tách khỏi TextTools.swift: phần
// biến đổi thuần được bản macOS biên dịch chung theo đường dẫn, phần proxy thì không).
import Foundation

// MARK: luồng thay chữ trên proxy (UITextDocumentProxy qua TextProxyLike)

enum TextToolRunner {
    enum Outcome: Equatable {
        case applied(TextTools.Undo)
        /// Biến đổi không đổi gì → không động vào ô.
        case unchanged
        /// Không có chữ để áp (không chọn, trước con trỏ trống).
        case noSource
        /// Context lệch / ô NFD → không xoá mù.
        case failsafe
    }

    static func apply(_ tool: TextTool, proxy: TextProxyLike, selectedText: String?) -> Outcome {
        guard let src = TextTools.source(selected: selectedText, before: proxy.contextBeforeInput) else {
            return .noSource
        }
        return replace(src, with: TextTools.apply(tool, src.text), proxy: proxy)
    }

    /// Nút "Thêm dấu" (thẻ Công cụ của ☰, Plus .sentenceDiacritics): vùng chọn nếu có chữ, không
    /// thì đoạn không dấu cuối trước con trỏ (AddTones.segment — như chip tự hiện). AddTones chạy
    /// trên máy (không mạng); độ dài giữ nguyên, chữ đã có dấu giữ nguyên. Song sinh Android
    /// TextToolRunner.addTones.
    static func addTones(proxy: TextProxyLike, selectedText: String?, personal: AddTones.Personal?) -> Outcome {
        guard let src = addTonesSource(selected: selectedText, before: proxy.contextBeforeInput) else { return .noSource }
        return replace(src, with: AddTones.restore(src.text, personal: personal).text, proxy: proxy)
    }

    static func addTonesSource(selected: String?, before: String?) -> TextTools.Source? {
        if let sel = selected, sel.contains(where: \.isLetter) { return TextTools.Source(text: sel, isSelection: true) }
        guard let b = before, !b.isEmpty else { return nil }
        let seg = AddTones.segment(b)
        return seg.contains(where: \.isLetter) ? TextTools.Source(text: seg, isSelection: false) : nil
    }

    /// Thay `src` bằng `result` trong ô. `strict` (dùng sau khi CHỜ, vd bản dịch xong
    /// muộn): ô có thể đã đổi trong lúc chờ ⇒ vùng chọn phải còn y nguyên (`currentSelection`)
    /// hoặc chữ trước con trỏ phải còn kết thúc bằng `src.text`, không thì không động vào ô.
    static func replace(_ src: TextTools.Source, with result: String, proxy: TextProxyLike,
                        strict: Bool = false, currentSelection: String? = nil) -> Outcome {
        // == của String là tương đương chuẩn: NFD → NFC mà chữ không đổi cũng coi là không đổi.
        guard result != src.text else { return .unchanged }
        if src.isSelection {
            if strict, currentSelection.map({ $0.unicodeScalars.elementsEqual(src.text.unicodeScalars) }) != true {
                return .failsafe
            }
            proxy.insertText(result)               // insertText thay vùng chọn
        } else {
            guard TextTools.isNFC(src.text) else { return .failsafe }
            if strict {
                guard currentSelection?.isEmpty ?? true,
                      let ctx = proxy.contextBeforeInput,
                      ctx.unicodeScalars.reversed().starts(with: src.text.unicodeScalars.reversed()) else {
                    return .failsafe
                }
            } else {
                guard CompositionSync.canDelete(src.text.count, expected: src.text,
                                                context: { proxy.contextBeforeInput }) else {
                    return .failsafe
                }
            }
            for _ in 0..<src.text.count { proxy.deleteBackward() }
            proxy.insertText(result)
        }
        return .applied(TextTools.Undo(original: src.text, result: result))
    }

    /// Hoàn tác một lần: chỉ khi ngay trước con trỏ ĐÚNG là chữ vừa thay (so từng scalar;
    /// context nil = không biết → không xoá).
    static func undo(_ u: TextTools.Undo, proxy: TextProxyLike) -> Bool {
        guard let ctx = proxy.contextBeforeInput,
              ctx.unicodeScalars.reversed().starts(with: u.result.unicodeScalars.reversed()) else {
            return false
        }
        for _ in 0..<u.result.count { proxy.deleteBackward() }
        proxy.insertText(u.original)
        return true
    }
}
