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
// khớp y hệt văn bản vừa chèn + ký tự ranh giới; ngược lại là ⌫ thường. (Chip gợi ý
// "Khôi phục"/đề xuất là của iOS/Android — macOS chỉ có tự áp + ⌫ hoàn tác.)
//
// Chi phí khi tắt: không gì ở đây chạy — caller chỉ vào khi
// `engine.pendingRetroCorrection != nil` (engine không bao giờ đặt nó khi cờ tắt), cộng
// một lần gọi `noteBoundaryCharacter` mỗi ranh giới (engine thoát ngay bằng một phép thử Bool).

import Foundation

/// Bản ghi để ⌫ kế tiếp hoàn tác một lần sửa đã áp.
struct RetroUndo: Equatable {
    /// Văn bản trước lần sửa + ký tự ranh giới ("í cả í very fast ").
    let previous: String
    /// Văn bản lần sửa để lại + ký tự ranh giới ("is car is very fast " …) — màn hình phải
    /// kết thúc ĐÚNG bằng chuỗi này ngay trước con trỏ thì mới hoàn tác.
    let current: String
}

enum RetroApply {
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
}
