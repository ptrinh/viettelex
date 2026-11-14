// Ảnh chụp trạng thái ô nhập cho log gỡ lỗi + cảnh báo bất thường — hàm THUẦN (app + bàn phím).
// Bối cảnh (15/11/2026): Messenger không vẽ chữ dù bàn phím ghi vào ô bình thường (ctx tăng,
// sfx=1) — log cũ không phân biệt được lỗi app chủ hay bàn phím. CHỈ độ dài / cờ / 4 ký tự đầu
// ID ô (UUID ngẫu nhiên mỗi ô) — KHÔNG BAO GIỜ nội dung chữ.
import Foundation

enum TouchLogAlerts {
    static let mark = "⚠︎"

    struct Probe: Equatable {
        /// 4 ký tự đầu documentIdentifier ("?" = đọc lỗi).
        var doc: String
        var ctxLen: Int        // -1 = nil
        var afterLen: Int      // -1 = nil
        var hasText: Bool
        var selLen: Int
    }

    static func describe(_ p: Probe) -> String {
        "doc=\(p.doc) ctx=\(p.ctxLen) after=\(p.afterLen) hasText=\(p.hasText ? 1 : 0) sel=\(p.selLen)"
    }

    /// Bất thường CHẮC CHẮN (không đoán): `hostEvents` = số lần app báo textDidChange /
    /// selectionDidChange… kể từ ảnh chụp trước.
    static func anomalies(prev: Probe?, now: Probe, hostEvents: Int) -> [String] {
        var out: [String] = []
        if now.ctxLen > 0 || now.afterLen > 0, !now.hasText {
            out.append("ô có chữ (ctx=\(now.ctxLen) after=\(now.afterLen)) mà hasText=0")
        }
        if let p = prev, p.doc != "?", now.doc != "?", p.doc != now.doc, hostEvents == 0 {
            out.append("ô đổi \(p.doc)→\(now.doc) mà app không báo")
        }
        return out
    }

    /// Khi copy log: các dòng cảnh báo lên đầu (tester hay chỉ dán được phần cuối).
    static func alertsFirst(_ log: String) -> String {
        let alerts = log.split(separator: "\n").filter { $0.contains(mark) }
        guard !alerts.isEmpty else { return log }
        return "=== Cảnh báo (\(alerts.count)) ===\n" + alerts.suffix(50).joined(separator: "\n")
            + "\n=== Log đầy đủ ===\n" + log
    }
}
