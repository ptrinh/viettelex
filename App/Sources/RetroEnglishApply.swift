// RetroEnglishApply.swift — "Tự sửa từ phía trước" (THỬ NGHIỆM, mặc định TẮT; AppState
// `retroactiveEnglish`, chỉ có tác dụng khi "Quyết định theo ngữ cảnh" bật).
//
// Engine (TelexCore RetroEnglish.swift, docs/DESIGN.md "Sửa ngược tiếng Anh") quyết định
// MỘT phép sửa `RetroCorrection { backspaces, expected, insert }` khi mạch tiếng Anh đã chắc:
// "Hí cả í very fast" → "His car is very fast". File này giữ phần THUẦN của việc áp phép
// sửa đó lên màn hình macOS — chính sách (maintainer duyệt 23/10/2026):
//
//  • IMK in-place (app đã chứng minh tôn trọng replacementRange): đọc lại văn bản ngay
//    trước con trỏ (selectedRange + attributedSubstring), khớp ĐÚNG `expected` (UTF-16)
//    thì thay range đó bằng một insertText(replacementRange) — không ⌫.
//  • Tap ⌫-gõ-lại (trình duyệt / Electron): chỉ khi đọc được màn hình qua Accessibility
//    và khớp `expected`, không còn burst synthetic nào đang bay; rồi ⌫ + gõ lại bằng
//    đường phát của tap. Không xác nhận được ⇒ bỏ qua.
//  • Terminal / app mã nguồn / Spotlight / launcher (SystemAutoText.appAllowed), marked,
//    passthrough, chọn-ghi-đè, emptyReset, edge-burst: KHÔNG BAO GIỜ viết lại.
//
// ⌫ NGAY SAU lần sửa (phím thật kế tiếp) trả lại đúng văn bản cũ — chỉ khi màn hình còn
// khớp y hệt văn bản vừa chèn + ký tự ranh giới; ngược lại là ⌫ thường.
//
// Hai chế độ (`mode`, maintainer 23/10/2026): cờ engine bật theo "Quyết định theo ngữ
// cảnh"; công tắc "Tự sửa từ phía trước" chọn TỰ ÁP (bật) hay ĐỀ XUẤT (tắt) — đề xuất =
// gợi ý cạnh con trỏ (CaretHint, kind `.retro`, "His car is ⇥ Tab"), chỉ khi kênh áp được
// VÀ màn hình đang khớp; Tab áp qua đúng đường an toàn trên (đọc lại lần nữa). Gợi ý này
// thắng mọi gợi ý khác (thêm dấu / lỗi gõ / gợi ý từ). Enter không đề xuất gì.
//
// Chi phí khi tắt: không gì ở đây chạy — caller chỉ vào khi
// `engine.pendingRetroCorrection != nil` (engine không bao giờ đặt nó khi cờ tắt), cộng
// một lần gọi `noteBoundaryCharacter` mỗi ranh giới (engine thoát ngay bằng một phép thử Bool).

import Foundation
import TelexCore

/// Bản ghi để ⌫ kế tiếp hoàn tác một lần sửa đã áp.
struct RetroUndo: Equatable {
    /// Văn bản trước lần sửa + ký tự ranh giới ("í cả í very fast ").
    let previous: String
    /// Văn bản lần sửa để lại + ký tự ranh giới ("is car is very fast " …) — màn hình phải
    /// kết thúc ĐÚNG bằng chuỗi này ngay trước con trỏ thì mới hoàn tác.
    let current: String
}

enum RetroApply {
    /// Việc làm với một phép sửa engine vừa quyết định.
    enum Mode: Equatable {
        /// "Quyết định theo ngữ cảnh" tắt (engine không bao giờ quyết định).
        case none
        /// Công tắc bật: tự áp + ⌫ hoàn tác.
        case autoApply
        /// Công tắc tắt: đề xuất bằng gợi ý cạnh con trỏ (Tab áp).
        case offer
    }

    static func mode(contextualEnglish: Bool, autoApply: Bool) -> Mode {
        guard contextualEnglish else { return .none }
        return autoApply ? .autoApply : .offer
    }

    /// Cờ engine `retroactiveEnglish`: cả hai chế độ cần quyết định ⇒ theo "Quyết định theo
    /// ngữ cảnh", không theo công tắc.
    static func engineFlag(contextualEnglish: Bool) -> Bool { contextualEnglish }

    /// Kênh áp phép sửa cho phím ranh giới này.
    enum Channel: Equatable {
        /// Không viết lại (không xác nhận được / app bị loại trừ).
        case none
        /// IMK: insertText(replacementRange) sau khi đọc lại khớp.
        case imkReplace
        /// Tap: ⌫ + gõ lại sau khi AX đọc lại khớp.
        case tapRetype
    }

    /// Đường IMK. `appAllowed` = SystemAutoText.appAllowed (loại terminal, app mã nguồn,
    /// Spotlight, launcher); `replacesCommittedText` = app đã chứng minh tôn trọng
    /// replacementRange trên chữ đã chốt (học được / built-in / ghim In-place). Marked
    /// (Terminal ở IMK, app hỏng in-place) và từ đi kênh edge-burst (async) không bao giờ.
    static func imkChannel(appAllowed: Bool, marked: Bool, edge: Bool,
                           replacesCommittedText: Bool) -> Channel {
        guard appAllowed, !marked, !edge, replacesCommittedText else { return .none }
        return .imkReplace
    }

    /// Đường tap. Chỉ chế độ ⌫-gõ-lại (omnibox chọn-ghi-đè / ô autocomplete emptyReset
    /// tự viết lại chữ dưới tay mình), và chỉ khi không còn burst synthetic nào đang bay
    /// (đọc AX lúc đó mới phản ánh đúng màn hình). Việc xác nhận AX làm sau, ở caller.
    static func tapChannel(appAllowed: Bool, emitMode: TapEmit, queueDrained: Bool) -> Channel {
        guard appAllowed, emitMode == .backspace, queueDrained else { return .none }
        return .tapRetype
    }

    /// Range UTF-16 của `text` nằm NGAY trước con trỏ nếu màn hình chứa đúng `text` ở đó
    /// (so UTF-16 chính xác: `==` của Swift coi NFD == NFC nên một ô NFD sẽ "khớp" mà độ
    /// dài range lệch). nil = không đọc được / có vùng chọn / lệch ⇒ không viết lại.
    static func verifiedRange(_ text: String, caret: Int?, selectionLength: Int = 0,
                              read: (NSRange) -> String?) -> NSRange? {
        let len = text.utf16.count
        guard len > 0, let caret, selectionLength == 0, caret >= len else { return nil }
        let range = NSRange(location: caret - len, length: len)
        guard let screen = read(range), screen.utf16.elementsEqual(text.utf16) else { return nil }
        return range
    }

    /// Bản ghi hoàn tác cho lần sửa vừa áp, nil khi ranh giới không phải MỘT ký tự in được
    /// trên cùng dòng (Enter có thể đã gửi tin, Tab dời focus — không hứa hoàn tác).
    static func undo(expected: String, insert: String, boundary: String?) -> RetroUndo? {
        guard let b = boundary, b.count == 1, let c = b.first, !c.isNewline, c != "\t",
              !expected.isEmpty, expected != insert else { return nil }
        return RetroUndo(previous: expected + b, current: insert + b)
    }

    /// ⌫ ngay sau lần sửa: range cần thay bằng `undo.previous`, hoặc nil (⌫ thường) khi
    /// màn hình không còn kết thúc đúng bằng `undo.current`.
    static func revertRange(_ undo: RetroUndo, caret: Int?, selectionLength: Int = 0,
                            read: (NSRange) -> String?) -> NSRange? {
        verifiedRange(undo.current, caret: caret, selectionLength: selectionLength, read: read)
    }

    /// Ký tự ranh giới cần báo cho engine (`noteBoundaryCharacter`): đúng MỘT ký tự mà phím
    /// để lại sau từ. nil = phím không chèn gì đoán được — không báo (engine coi hai từ
    /// không liền nhau, an toàn).
    static func boundaryCharacter(_ inserted: String?) -> Character? {
        guard let s = inserted, s.count == 1 else { return nil }
        return s.first
    }

    // MARK: Đề xuất (công tắc tắt)

    /// Gợi ý cho phép sửa `expected` → `insert` (đã xác nhận trên màn hình TRƯỚC ranh giới) sau ký tự ranh giới
    /// `boundary`: thay `expected + b` bằng `insert + b`. nil khi ranh giới không phải MỘT
    /// ký tự in được trên cùng dòng (Enter gửi tin / Tab dời focus ⇒ không đề xuất).
    /// `display` điền sau, khi đọc được màn hình (`offerDisplay`).
    static func offer(expected: String, insert: String, boundary: String?) -> CaretSuggestion? {
        guard let b = boundary, b.count == 1, let ch = b.first, !ch.isNewline, ch != "\t",
              !expected.isEmpty, expected != insert else { return nil }
        return CaretSuggestion(kind: .retro, display: "", replace: expected + b, insert: insert + b)
    }

    /// Ký tự đọc thêm trước `replace` để dựng chữ hiển thị (phần đầu từ bị cắt bởi LCP).
    static let displayLookback = 24

    /// Chữ hiện trong ô: các từ ĐƯỢC SỬA, đủ từ — "Hí cả í very fast " (replace
    /// "í cả í very fast ", insert "is car is very fast ") ⇒ "His car is". `before` = văn bản
    /// ngay trước con trỏ; phải kết thúc ĐÚNG (UTF-16) bằng `replace`, không thì nil (màn
    /// hình đã khác ⇒ không đề xuất).
    static func offerDisplay(before: String, replace: String, insert: String) -> String? {
        let b = Array(before.utf16), r = Array(replace.utf16)
        guard !r.isEmpty, b.count >= r.count, Array(b[(b.count - r.count)...]) == r else { return nil }
        // Đầu từ đứng trước phần bị thay (LCP đã cắt "H" của "His").
        let prefixUnits = Array(b[..<(b.count - r.count)])
        let prefixText = String(decoding: prefixUnits, as: UTF16.self)
        let head = String(prefixText.reversed().prefix { $0.isLetter }.reversed())
        // Bỏ đuôi chung (" very fast ") rồi kéo tới hết từ đang dở trong `insert`.
        let rs = Array(replace.unicodeScalars), ins = Array(insert.unicodeScalars)
        var k = 0
        while k < rs.count, k < ins.count, rs[rs.count - 1 - k] == ins[ins.count - 1 - k] { k += 1 }
        var end = ins.count - k
        while end < ins.count, !CharacterSet.whitespacesAndNewlines.contains(ins[end]) { end += 1 }
        var core = String.UnicodeScalarView()
        core.append(contentsOf: ins[..<end])
        let text = (head + String(core)).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
