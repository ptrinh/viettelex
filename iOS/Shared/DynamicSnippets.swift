// Mẫu câu động có sẵn (tỷ giá, giá vàng) + phần thuần của đường fetch — dùng chung
// app, bàn phím và test. Bản Android: android/keyboard/.../Templates.kt (cùng hành vi).
import Foundation

enum DynamicSnippets {
    /// Bốn mẫu động có sẵn — cùng thứ tự/nội dung với cuối ios-mau-cau.yml.
    static let builtins: [(label: String, text: String)] = [
        ("💵❓", "https://viettelex.com/api/usd"),
        ("💸❓", "https://viettelex.com/api/usd-tudo"),
        ("🟡❓", "https://viettelex.com/api/vang"),
        ("🪙❓", "https://viettelex.com/api/btc"),
    ]

    /// Cờ App Group: đã chạy migration "thêm mẫu động có sẵn vào danh sách đã tự chỉnh".
    static let migrationKey = "dynamicSnippetsMigrated1"
    static let storeKey = "userTemplates"

    /// Phần thuần của migration MỘT LẦN. `raw` = App Group "userTemplates" (nil = chưa tự
    /// chỉnh ⇒ đang dùng mặc định từ YAML, đã có sẵn các mẫu này). Trả danh sách mới cần ghi,
    /// hoặc nil = không đổi danh sách. Caller luôn ghi cờ sau khi gọi (kể cả nil) để lần sau
    /// không chạy lại — người dùng xoá mẫu sau đó thì không bao giờ bị thêm lại.
    static func migrated(_ raw: [[String: String]]?, alreadyRan: Bool) -> [[String: String]]? {
        guard !alreadyRan, var list = raw else { return nil }
        let have = Set(list.compactMap { $0["text"]?.trimmingCharacters(in: .whitespacesAndNewlines) })
        var changed = false
        for b in builtins where !have.contains(b.text) {
            list.append(["label": b.label, "text": b.text])
            changed = true
        }
        return changed ? list : nil
    }

    /// Chạy migration trên UserDefaults (App Group). Rẻ khi đã chạy: một lần đọc bool.
    static func migrateIfNeeded(_ d: UserDefaults?) {
        guard let d, !d.bool(forKey: migrationKey) else { return }
        let raw = d.array(forKey: storeKey) as? [[String: String]]
        if d.object(forKey: storeKey) != nil, raw == nil {
            // Dữ liệu lạ (không phải [[String: String]]) — không đụng, cũng không đánh dấu.
            return
        }
        if let next = migrated(raw, alreadyRan: false) { d.set(next, forKey: storeKey) }
        d.set(true, forKey: migrationKey)
    }

    // MARK: fetch

    static let fetchTimeout: TimeInterval = 4
    static let maxBytes = 1000

    /// Nội dung chèn cho mẫu động: chỉ khi HTTP 200; giải mã UTF-8 tường minh trên ≤ 1000
    /// byte đầu, lùi về ranh giới ký tự (không cắt đôi "₫"/chữ có dấu thành "�"); trim.
    /// nil ⇒ caller chèn chính URL (lỗi mạng, timeout, mã ≠ 200, body rỗng).
    static func body(data: Data?, statusCode: Int?) -> String? {
        guard let data, statusCode == 200 else { return nil }
        var bytes = [UInt8](data.prefix(maxBytes))
        if data.count > maxBytes { bytes = trimToUTF8Boundary(bytes) }
        guard let s = String(bytes: bytes, encoding: .utf8) else {
            // Không phải UTF-8 hợp lệ: vẫn chèn (ký tự hỏng thành U+FFFD) thay vì im lặng.
            let t = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Bỏ chuỗi UTF-8 dở dang ở cuối (byte đầu ký tự nhiều byte mà thiếu byte tiếp theo).
    static func trimToUTF8Boundary(_ b: [UInt8]) -> [UInt8] {
        var i = b.count
        var cont = 0
        while i > 0, cont < 3, b[i - 1] & 0xC0 == 0x80 { i -= 1; cont += 1 }
        guard i > 0 else { return b }
        let lead = b[i - 1]
        let need: Int
        if lead & 0x80 == 0 { return b }               // ASCII cuối: đủ
        else if lead & 0xE0 == 0xC0 { need = 1 }
        else if lead & 0xF0 == 0xE0 { need = 2 }
        else if lead & 0xF8 == 0xF0 { need = 3 }
        else { return b }
        return cont >= need ? b : Array(b[..<(i - 1)])
    }
}
