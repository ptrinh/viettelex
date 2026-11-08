import Foundation

// "Giao diện JSON": đặc tả theme dạng JSON có phiên bản — theme có sẵn (themes/builtin-themes.json),
// theme tự tạo (dán / sửa), tuỳ chỉnh theo theme (KeyStyle.light/.dark). Android giữ Y HỆT
// (android/keyboard/.../ThemeSpec.kt): cùng luật đọc, cùng chuỗi chuẩn, cùng bảng lỗi — fixture chung
// KeyboardTests/Fixtures/theme-json-cases.txt chạy ở cả hai bên.
//
//   {"v":1, "id":"peach", "name":{"vi":"Hồng đào","en":"Peach"},
//    "light":{"bg":"#FBE3E1","key":"#FFF8F7","special":"#F1C4BF","ink":"#4A2226","accent":"#C2505A",
//             "accentInk":"#FFFFFF","border":"#4CAF6E","fn":"#A9BFA3","fnInk":"#C2255C",
//             "balloon":"#…","trail":"#99FFFFFF","deco":{"motif":"hearts","color":"#8CFF6FA3","density":100},
//             "borderFx":"rainbow", "spaceDeco":"soundhole"},
//             (deco "alt": motif thứ hai xen kẽ, vd {"motif":"pumpkin","alt":"bat",…})
//    "dark":{…} | "same", "corner":70, "fontScale":110, "font":"serif", "weight":"bold",
//    "sound":"phao", "effect":"blossom", "swipe":"stardust", "game":"mole", "keyShape":"pixel",
//    "photoFx":"spotlight", "tags":["interactive"], "buddy":{"character":"ai","size":5}}
//
// "font" chuỗi (KeyLabelFont): "default" | "rounded" | "serif" | "mono" | "condensed" — phông hệ thống — | "pixel" — phông
//   điểm ảnh NHÚNG trong app (Tiny5, fonts/Tiny5-Regular.ttf, đủ chữ Việt; nạp lười chỉ khi dùng, bỏ qua "weight").
//   Giá trị khác ⇒ lỗi badValue. Phông ngoài danh sách ⇒ dạng object tải qua URL (dưới).
// "keyShape" (tuỳ chọn, danh sách trắng ThemeExtraIds.keyShapes): dáng phím — "pixel" = góc cắt bậc thang theo khối,
//   viền khối đậm + bóng khối cứng dưới/phải, bấm = phím lún một khối (mất bóng). Vẽ bằng ảnh 9-slice tí hon dựng từ
//   bảng màu (PixelKeys) — 0 chi phí với theme khác. Không có ⇒ bo góc theo "corner" như cũ.
// "borderFx" (trong "light"/"dark", danh sách trắng ThemeSlots.borderFxValues): "rainbow" = viền phím cầu vồng (Gaming
//   RGB, chỉ xoay màu khi đang gõ) | "aurora" = viền gradient tím → lam ĐỨNG YÊN + dải cực quang tĩnh dọc mép trên
//   (theme AI, AuroraFx; vẽ một lần, 0 hoạt ảnh) | "none" (bản vá: bỏ). Motif "deco" có thêm "neural" (theme AI).
//
// "schedule" (tuỳ chọn, 2…6 mục, "from" tăng dần): bảng màu ĐỔI THEO GIỜ ĐỊA PHƯƠNG (theme "Theo giờ") —
//   "schedule":[{"from":"05:00","palette":{…như "light"…}}, {"from":"07:00","palette":{…}}, …]
// Mục có "from" lớn nhất ≤ giờ hiện tại thắng; trước mục đầu ⇒ mục CUỐI (qua nửa đêm). Có "schedule" ⇒ bỏ qua
// sáng/tối hệ thống (bầu trời là bầu trời); "light"/"dark" vẫn bắt buộc như mọi theme = bảng dự phòng khi không có
// giờ (bản xem trước tĩnh, "Chép JSON" so bản vá). Chọn giờ MỘT lần lúc bàn phím hiện (ThemeSchedule) — 0 chi phí
// mỗi phím, không hẹn giờ. Bản vá (KeyStyle) không có "schedule".
//
// "game" (tuỳ chọn, danh sách trắng ThemeExtraIds.games): trò chơi khi gõ CHẠY KHI theme này đang dùng — "mole" = Đập
// chuột (MoleGame.swift). Khác "sound"/"effect": không ghi gì lúc chọn theme, bàn phím đọc từ kiểu thực dùng.
//
// "photoFx" (tuỳ chọn, danh sách trắng ThemeExtraIds.photoFx): hiệu ứng trên ẢNH NỀN chạy KHI theme này đang dùng —
// "spotlight" = Đèn rọi (NightClub.swift): ảnh nền người dùng tối gần đen, mỗi phím bấm rọi một quầng sáng mềm (tô nhẹ
// hồng / tím / lục lam xoay vòng, lõi sáng lóa gần trắng) quanh chỗ chạm rồi tắt dần ~1,1 s, tối đa 6 quầng; gõ nhanh ⇒ to + sáng hơn. Không có
// ảnh nền ⇒ quầng sáng rọi lên hoạ tiết neon tối dựng sẵn; quả cầu disco nhỏ ở góc trên xoay + toả chấm sáng khi bấm.
// Như "game": không ghi gì lúc chọn theme, bàn phím đọc từ kiểu thực dùng (SpotlightPolicy); theme tự tạo dùng được.
//
// "tags" (tuỳ chọn, mảng chuỗi trong danh sách trắng ThemeTags.known): nhãn của theme — "interactive" = theme TƯƠNG TÁC
//   (phím/ảnh nền phản ứng khi gõ: trò chơi, đèn rọi, sóng, nốt nhạc…) ⇒ màn "Chọn giao diện" gắn chip "Tương tác" và
//   xếp nhóm riêng ngay sau theme miễn phí (ThemePicker). Không phải mảng ⇒ wrongType; phần tử không phải chuỗi ⇒
//   wrongType; nhãn lạ / lặp ⇒ badValue. Mảng rỗng = không có. Chỉ là nhãn hiển thị — không đổi cách vẽ. Theme tự tạo
//   dùng được; "Chép JSON" giữ nguyên; bản vá (KeyStyle) không có "tags".
//
// "buddy" (tuỳ chọn): bạn đồng hành ĐI KÈM theme — {"character": id BuddyCharacter trừ "off" (ThemeExtraIds.buddies),
//   "size": 1…20 (thang "Vị trí & cỡ", BuddyPlacement; 5 = cỡ gốc) tuỳ chọn}. Như "effect": CHỈ ghi MỘT lần lúc người
//   dùng chọn theme (ThemeExtras.applyBuddyOnSelect — khoá keyboardBuddy / buddySize); đổi tay sau đó thì giữ tới lần
//   chọn theme kế. Nhân vật bị khoá Plus / app không có ⇒ bỏ qua (cả cỡ). Khoá lạ ⇒ unknownKey; thiếu "character" ⇒
//   missingKey; id lạ ⇒ badValue; cỡ ngoài 1…20 ⇒ kẹp + cảnh báo clamped. Bản vá (KeyStyle) không có "buddy".
//
// "variant" (tuỳ chọn, danh sách trắng ThemeVariants.known): bảng màu THEO LỰA CHỌN CỦA NGƯỜI DÙNG ở trang Giao diện —
//   "zodiac" = Cung hoàng đạo: bảng màu theo nguyên tố của cung đã chọn (khoá `zodiacSign`, ZodiacElement.slots) + ký
//   hiệu cung mờ ở góc + chòm sao của cung cho hiệu ứng "Chòm sao". Giải MỘT lần lúc bàn phím hiện (ThemeSettings đọc
//   lựa chọn) — 0 chi phí mỗi phím. "light"/"dark" vẫn bắt buộc = bảng dự phòng (thẻ xem trước tĩnh, "Chép JSON").
//   "pride" = Tự hào: bảng màu + màu viền (aurora) + màu hiệu ứng theo lá cờ đã chọn (khoá `prideFlag`, PrideFlag).
//   Giá trị lạ ⇒ badValue; sai kiểu ⇒ wrongType. Bản vá (KeyStyle) không có "variant"; "Chép JSON" giữ nguyên.
//
// "sound" / "effect" (tuỳ chọn, id trong danh sách trắng ThemeExtraIds): âm phím / hiệu ứng bấm phím ĐI KÈM theme —
// CHỈ áp MỘT lần lúc người dùng chọn theme (ThemeExtras.applyOnSelect); không bao giờ tự bật âm thanh phím.
// "swipe" (tuỳ chọn, id SwipeTrailStyle trừ "theme"): nét vuốt của theme — KHÔNG áp lúc chọn theme; chỉ được
// dùng khi người dùng chọn "Theo giao diện" (SwipeTrailPolicy giải lúc hiện bàn phím).
//
// Tệp tải về (Plus — ThemeAssets.swift: kế hoạch / kho / dọn; App/ThemeAssetDownloader.swift: tải + xử lý):
//   "font": "serif" | {"name":"Nunito","url":"https://….ttf|otf","sha256":"…"?}
//   "background": {"url":"https://…","sha256":"…"?}      ảnh nền theme (ảnh nền tự đặt của người dùng thắng)
//   "foreground": {"url":"https://…","sha256":"…"?}      PNG/WebP trong suốt TRÊN phím, căng đúng cỡ bàn phím
//   "keys": {"default"|"special"|"space"|"return"|"shift"|"delete"|"a"…"z":
//            {"url","sha256"?,"slice":[t,l,b,r]? (9-slice, px ảnh gốc),"pressed":{"url","sha256"?}?}}
// Chỉ https, không user/cổng, host có dấu chấm; ≤ 16 ảnh khác nhau, ≤ 20 tệp. JSON chỉ là CHỈ DẪN: dán /
// đọc không bao giờ tự tải — app hỏi trước rồi mới tải; bàn phím không bao giờ dùng mạng.
//
// AN TOÀN (dữ liệu không tin được — dán từ clipboard): kiểm cỡ TRƯỚC khi đọc (16 KB), UTF-8 chặt (không
// BOM), độ sâu ≤ 8, chuỗi ≤ 200 ký tự (tên ≤ 40), chỉ số nguyên ≤ 9 chữ số, khoá lặp / khoá lạ / null /
// sai kiểu / ký tự điều khiển ⇒ LỖI (không bao giờ crash, không force-unwrap). Không có URL / ảnh / mã:
// chỉ màu, số, và vài giá trị liệt kê (motif, phông, độ đậm). Bàn phím chỉ đọc bản app đã chuẩn hoá và
// vẫn kiểm lại — hỏng thì về theme có sẵn / Hệ thống.

// MARK: - Lỗi / cảnh báo

struct ThemeIssue: Error, Equatable {
    enum Code: String, CaseIterable {
        case tooLarge, encoding, syntax, depth, duplicateKey, unknownKey, missingKey, wrongType,
             badColor, badNumber, tooLong, badValue, badVersion, controlChar, clamped, lowContrast,
             contrastTooLow, tooMany, bgKept, badUrl, tooManyFiles
    }
    var code: Code
    /// Vị trí ("light.key") hoặc chi tiết (khoá lặp, số ký tự).
    var path: String = ""
    var isError: Bool { code != .clamped && code != .lowContrast && code != .bgKept }

    /// Thông báo theo ngôn ngữ giao diện (L10n) — tiếng Việt + tiếng Anh.
    var message: String {
        switch code {
        case .tooLarge: return L("Quá lớn (tối đa 16 KB).")
        case .encoding: return L("Không phải văn bản UTF-8 hợp lệ.")
        case .syntax: return L("JSON sai cú pháp ở %@ (dòng:cột).", path)
        case .depth: return L("JSON lồng quá sâu.")
        case .duplicateKey: return L("Khoá bị lặp: %@", path)
        case .unknownKey: return L("Khoá không hỗ trợ: %@", path)
        case .missingKey: return L("Thiếu khoá bắt buộc: %@", path)
        case .wrongType: return L("Sai kiểu giá trị: %@", path)
        case .badColor: return L("Màu không hợp lệ ở %@ (dùng #RRGGBB hoặc #AARRGGBB).", path)
        case .badNumber: return L("Số không hợp lệ ở %@ (chỉ số nguyên).", path)
        case .tooLong: return L("Chuỗi quá dài ở %@.", path)
        case .badValue: return L("Giá trị không hỗ trợ ở %@.", path)
        case .badVersion: return L("Phiên bản định dạng không hỗ trợ (cần \"v\": 1).")
        case .controlChar: return L("Có ký tự điều khiển trong chuỗi.")
        case .clamped: return L("Đã đưa %@ về khoảng cho phép.", path)
        case .lowContrast: return L("Tương phản thấp ở %@ (nên ≥ 3:1).", path)
        case .contrastTooLow: return L("Tương phản quá thấp ở %@ (tối thiểu 2:1).", path)
        case .tooMany: return L("Đã đủ %@ giao diện tự tạo — xoá bớt trước khi dán.", path)
        case .bgKept: return L("Giao diện có sẵn này luôn có nền — đã giữ nền gốc.")
        case .badUrl: return L("Địa chỉ tệp không hợp lệ ở %@ (chỉ https://, phông .ttf/.otf).", path)
        case .tooManyFiles: return L("Quá nhiều tệp tải về (%@).", path)
        }
    }
}

// MARK: - JSON chặt

/// Cây JSON đã đọc (object giữ thứ tự để báo lỗi ổn định). Số: chỉ nguyên.
indirect enum StrictJSON: Equatable {
    case object([(String, StrictJSON)]), array([StrictJSON]), string(String), int(Int), bool(Bool), null

    static func == (a: StrictJSON, b: StrictJSON) -> Bool {
        switch (a, b) {
        case let (.object(x), .object(y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case let (.array(x), .array(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.int(x), .int(y)): return x == y
        case let (.bool(x), .bool(y)): return x == y
        case (.null, .null): return true
        default: return false
        }
    }

    struct Limits {
        var maxBytes = 16 * 1024
        var maxDepth = 8
        var maxString = 200
        var maxMembers = 64
    }
    struct Failure: Error { let issue: ThemeIssue }

    /// Đọc BYTES (UTF-8 chặt, không BOM). Cỡ kiểm TRƯỚC khi giải mã.
    static func parse(_ data: Data, limits: Limits = Limits()) -> Result<StrictJSON, ThemeIssue> {
        guard data.count <= limits.maxBytes else { return .failure(ThemeIssue(code: .tooLarge)) }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return .failure(ThemeIssue(code: .encoding, path: "BOM")) }
        guard let s = String(data: data, encoding: .utf8) else { return .failure(ThemeIssue(code: .encoding)) }
        return parseText(s, limits: limits)
    }

    /// Đọc CHUỖI (clipboard / App Group). Cỡ = số byte UTF-8, kiểm trước khi duyệt.
    static func parse(_ s: String, limits: Limits = Limits()) -> Result<StrictJSON, ThemeIssue> {
        guard s.utf8.count <= limits.maxBytes else { return .failure(ThemeIssue(code: .tooLarge)) }
        if s.unicodeScalars.first == "\u{FEFF}" { return .failure(ThemeIssue(code: .encoding, path: "BOM")) }
        return parseText(s, limits: limits)
    }

    private static func parseText(_ s: String, limits: Limits) -> Result<StrictJSON, ThemeIssue> {
        var p = Parser(scalars: Array(s.unicodeScalars), limits: limits)
        do {
            p.ws()
            let v = try p.value(depth: 1)
            p.ws()
            guard p.i == p.s.count else { throw Failure(issue: ThemeIssue(code: .syntax, path: String(p.i))) }
            return .success(v)
        } catch let f as Failure {
            // Vị trí (chỉ số ký tự) ⇒ "dòng:cột" (1-based) cho người đọc; Android y hệt.
            var issue = f.issue
            if [.syntax, .badNumber, .tooLong].contains(issue.code), let idx = Int(issue.path) {
                issue.path = Self.lineColumn(p.s, idx)
            }
            return .failure(issue)
        } catch {
            return .failure(ThemeIssue(code: .syntax))
        }
    }

    /// "dòng:cột" (1-based) của chỉ số `idx` trong dãy ký tự.
    static func lineColumn(_ s: [Unicode.Scalar], _ idx: Int) -> String {
        var line = 1, col = 1
        for c in s.prefix(max(0, min(idx, s.count))) { if c == "\n" { line += 1; col = 1 } else { col += 1 } }
        return "\(line):\(col)"
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        let limits: Limits
        var i = 0
        init(scalars: [Unicode.Scalar], limits: Limits) { s = scalars; self.limits = limits }

        func fail(_ c: ThemeIssue.Code, _ path: String = "") -> Failure { Failure(issue: ThemeIssue(code: c, path: path)) }
        var syntax: Failure { fail(.syntax, String(i)) }
        func peek() -> Unicode.Scalar? { i < s.count ? s[i] : nil }

        mutating func ws() {
            while let c = peek(), c == " " || c == "\t" || c == "\n" || c == "\r" { i += 1 }
        }
        mutating func expect(_ c: Unicode.Scalar) throws {
            guard peek() == c else { throw syntax }
            i += 1
        }

        /// `depth` = số object/array đang mở bao quanh (chỉ đếm vùng chứa; vượt ⇒ lỗi trước khi đệ quy
        /// tiếp — không tràn ngăn xếp).
        mutating func value(depth: Int) throws -> StrictJSON {
            guard let c = peek() else { throw syntax }
            if c == "{" || c == "[" { guard depth <= limits.maxDepth else { throw fail(.depth) } }
            switch c {
            case "{": return try object(depth: depth)
            case "[": return try array(depth: depth)
            case "\"": return .string(try string())
            case "t": try literal("true"); return .bool(true)
            case "f": try literal("false"); return .bool(false)
            case "n": try literal("null"); return .null
            case "-", "0"..."9": return .int(try number())
            default: throw syntax
            }
        }

        mutating func literal(_ w: String) throws {
            for ch in w.unicodeScalars { try expect(ch) }
        }

        mutating func number() throws -> Int {
            let start = i
            var neg = false
            if peek() == "-" { neg = true; i += 1 }
            var digits = 0, v = 0
            let first = i
            while let c = peek(), ("0"..."9").contains(c) {
                digits += 1
                guard digits <= 9 else { throw fail(.badNumber, String(start)) }
                v = v * 10 + Int(c.value - 48)
                i += 1
            }
            guard digits > 0 else { throw syntax }
            if digits > 1, s[first] == "0" { throw syntax }       // số 0 đứng đầu
            if let c = peek(), c == "." || c == "e" || c == "E" { throw fail(.badNumber, String(start)) }
            return neg ? -v : v
        }

        mutating func hex4() throws -> UInt32 {
            var v: UInt32 = 0
            for _ in 0..<4 {
                guard let c = peek(), let d = Self.hexDigit(c) else { throw syntax }
                v = v << 4 | d
                i += 1
            }
            return v
        }
        static func hexDigit(_ c: Unicode.Scalar) -> UInt32? {
            switch c {
            case "0"..."9": return c.value - 48
            case "a"..."f": return c.value - 87
            case "A"..."F": return c.value - 55
            default: return nil
            }
        }

        mutating func string() throws -> String {
            try expect("\"")
            var out = String.UnicodeScalarView()
            var n = 0
            while true {
                guard let c = peek() else { throw syntax }
                i += 1
                var scalar: Unicode.Scalar
                if c == "\"" { break }
                if c == "\\" {
                    guard let e = peek() else { throw syntax }
                    i += 1
                    switch e {
                    case "\"": scalar = "\""
                    case "\\": scalar = "\\"
                    case "/": scalar = "/"
                    case "b", "f", "n", "r", "t": throw fail(.controlChar)
                    case "u":
                        let u = try hex4()
                        if (0xD800...0xDBFF).contains(u) {
                            guard peek() == "\\" else { throw fail(.encoding) }
                            i += 1
                            guard peek() == "u" else { throw fail(.encoding) }
                            i += 1
                            let lo = try hex4()
                            guard (0xDC00...0xDFFF).contains(lo),
                                  let sc = Unicode.Scalar(0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)) else { throw fail(.encoding) }
                            scalar = sc
                        } else {
                            guard let sc = Unicode.Scalar(u) else { throw fail(.encoding) }   // nửa sau lẻ
                            scalar = sc
                        }
                    default: throw syntax
                    }
                } else {
                    scalar = c
                }
                if scalar.value < 0x20 || scalar.value == 0x7F { throw fail(.controlChar) }
                n += 1
                guard n <= limits.maxString else { throw fail(.tooLong, String(i)) }
                out.append(scalar)
            }
            return String(out)
        }

        mutating func object(depth: Int) throws -> StrictJSON {
            try expect("{")
            var members: [(String, StrictJSON)] = []
            var seen = Set<String>()
            ws()
            if peek() == "}" { i += 1; return .object([]) }
            while true {
                ws()
                guard peek() == "\"" else { throw syntax }
                let k = try string()
                guard seen.insert(k).inserted else { throw fail(.duplicateKey, k) }
                ws()
                try expect(":")
                ws()
                members.append((k, try value(depth: depth + 1)))
                guard members.count <= limits.maxMembers else { throw fail(.tooLarge) }
                ws()
                if peek() == "," { i += 1; continue }
                try expect("}")
                return .object(members)
            }
        }

        mutating func array(depth: Int) throws -> StrictJSON {
            try expect("[")
            var items: [StrictJSON] = []
            ws()
            if peek() == "]" { i += 1; return .array([]) }
            while true {
                ws()
                items.append(try value(depth: depth + 1))
                guard items.count <= limits.maxMembers else { throw fail(.tooLarge) }
                ws()
                if peek() == "," { i += 1; continue }
                try expect("]")
                return .array(items)
            }
        }
    }

    /// Chuỗi CHUẨN: khoá sắp xếp, không khoảng trắng; chỉ escape `"` và `\` (ký tự điều khiển đã bị
    /// từ chối lúc đọc). Android viết y hệt ⇒ so sánh / đồng bộ theo chuỗi.
    var canonical: String {
        var out = ""
        write(&out)
        return out
    }
    private func write(_ o: inout String) {
        switch self {
        case .object(let m):
            o += "{"
            for (n, (k, v)) in m.sorted(by: { $0.0 < $1.0 }).enumerated() {
                if n > 0 { o += "," }
                Self.str(k, &o); o += ":"; v.write(&o)
            }
            o += "}"
        case .array(let a):
            o += "["
            for (n, v) in a.enumerated() { if n > 0 { o += "," }; v.write(&o) }
            o += "]"
        case .string(let s): Self.str(s, &o)
        case .int(let v): o += String(v)
        case .bool(let b): o += b ? "true" : "false"
        case .null: o += "null"
        }
    }
    /// Bản dễ đọc (thụt 2, khoá sắp xếp) — "Chép JSON" và trình sửa.
    var pretty: String {
        var out = ""
        writePretty(&out, 0)
        return out
    }
    private func writePretty(_ o: inout String, _ depth: Int) {
        let pad = String(repeating: "  ", count: depth + 1), end = String(repeating: "  ", count: depth)
        switch self {
        case .object(let m) where !m.isEmpty:
            o += "{\n"
            for (n, (k, v)) in m.sorted(by: { $0.0 < $1.0 }).enumerated() {
                if n > 0 { o += ",\n" }
                o += pad; Self.str(k, &o); o += ": "; v.writePretty(&o, depth + 1)
            }
            o += "\n" + end + "}"
        case .array(let a) where !a.isEmpty:
            o += "[\n"
            for (n, v) in a.enumerated() { if n > 0 { o += ",\n" }; o += pad; v.writePretty(&o, depth + 1) }
            o += "\n" + end + "]"
        default: write(&o)
        }
    }
    private static func str(_ s: String, _ o: inout String) {
        o += "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": o += "\\\""
            case "\\": o += "\\\\"
            default:
                if c.value < 0x20 { o += String(format: "\\u%04x", c.value) } else { o.unicodeScalars.append(c) }
            }
        }
        o += "\""
    }
}

// MARK: - Màu

enum ThemeColorCode {
    /// "#RRGGBB" (đục) hoặc "#AARRGGBB" → ARGB; sai ⇒ nil.
    static func parse(_ s: String) -> UInt32? {
        let u = Array(s.utf8)
        guard (u.count == 7 || u.count == 9), u.first == UInt8(ascii: "#") else { return nil }
        var v: UInt32 = 0
        for b in u.dropFirst() {
            guard let d = StrictJSONHex.digit(b) else { return nil }
            v = v << 4 | d
        }
        return u.count == 7 ? (0xFF00_0000 | v) : v
    }
    /// Đục ⇒ "#RRGGBB", có alpha ⇒ "#AARRGGBB" — chữ hoa.
    static func format(_ v: UInt32) -> String {
        v >> 24 == 0xFF ? String(format: "#%06X", v & 0xFFFFFF) : String(format: "#%08X", v)
    }
    static func rgba(_ v: UInt32) -> RGBA { RGBA(hex: v & 0xFFFFFF, alpha: Double(v >> 24) / 255) }
    /// RGBA → ARGB (alpha cắt cụt như Android withAlpha, có dung sai làm tròn).
    static func argb(_ c: RGBA) -> UInt32 {
        func ch(_ x: Double) -> UInt32 { UInt32(max(0, min(255, (x * 255).rounded()))) }
        let a = UInt32(max(0, min(255, (c.a * 255 + 1e-6).rounded(.down))))
        return a << 24 | ch(c.r) << 16 | ch(c.g) << 8 | ch(c.b)
    }
}

private enum StrictJSONHex {
    static func digit(_ b: UInt8) -> UInt32? {
        switch b {
        case 48...57: return UInt32(b - 48)
        case 97...102: return UInt32(b - 87)
        case 65...70: return UInt32(b - 55)
        default: return nil
        }
    }
}

// MARK: - Mô hình

struct ThemeDeco: Equatable {
    /// nil = "none" (không hoạ tiết — dùng để bỏ hoạ tiết theme có sẵn).
    var motif: KeyboardDecoration.Motif?
    var color: UInt32 = 0
    /// Mật độ % (bước ngang = stepX × 100 / density), kẹp 50…200.
    var density = 100
    /// Motif thứ hai xen kẽ ("alt", tuỳ chọn) — chỉ có khi `motif` khác nil.
    var alt: KeyboardDecoration.Motif? = nil
    static let densityRange = 50...200
}

/// Màu một chế độ (sáng / tối). Theme đầy đủ bắt buộc key / special / ink / accent; bản vá (KeyStyle)
/// mọi trường tuỳ chọn. bg nil = nền trong suốt / theo hệ thống.
struct ThemeSlots: Equatable {
    var bg: UInt32?, key: UInt32?, special: UInt32?, ink: UInt32?, accent: UInt32?
    var accentInk: UInt32?, border: UInt32?, fn: UInt32?, fnInk: UInt32?, balloon: UInt32?, trail: UInt32?
    var deco: ThemeDeco?
    /// Hiệu ứng viền phím: "rainbow" (Gaming RGB — viền cầu vồng, chỉ xoay màu khi đang gõ) | "aurora" (AI — viền
    /// gradient tím → lam ĐỨNG YÊN + dải cực quang tĩnh dọc mép trên bàn phím; vẽ một lần, 0 hoạt ảnh) | "none" (bản vá: bỏ).
    var borderFx: String?
    /// Hình vẽ trên phím cách: "soundhole" (Ghi-ta — lỗ thoát âm tròn + vành hoa văn, vẽ MỘT lần vào lớp của phím cách)
    /// | "none" (bản vá: bỏ). Không có hook skin ảnh cho builtin (skin = ảnh tải về) ⇒ slot riêng tối giản.
    var spaceDeco: String?

    var isEmpty: Bool { self == ThemeSlots() }
    static let rainbow = "rainbow"
    /// Giá trị hợp lệ của "borderFx" (Android ThemeSlots.BORDER_FX y hệt).
    static let aurora = "aurora"
    static let borderFxValues: Set<String> = [rainbow, aurora, "none"]
    static let soundhole = "soundhole"
    /// Giá trị hợp lệ của "spaceDeco" (Android ThemeSlots.SPACE_DECO y hệt).
    static let spaceDecoValues: Set<String> = [soundhole, "none"]
    static let colorKeys = ["accent", "accentInk", "balloon", "bg", "border", "fn", "fnInk", "ink", "key", "special", "trail"]
    static let requiredKeys = ["key", "special", "ink", "accent"]

    subscript(color k: String) -> UInt32? {
        get {
            switch k {
            case "bg": return bg
            case "key": return key
            case "special": return special
            case "ink": return ink
            case "accent": return accent
            case "accentInk": return accentInk
            case "border": return border
            case "fn": return fn
            case "fnInk": return fnInk
            case "balloon": return balloon
            case "trail": return trail
            default: return nil
            }
        }
        set {
            switch k {
            case "bg": bg = newValue
            case "key": key = newValue
            case "special": special = newValue
            case "ink": ink = newValue
            case "accent": accent = newValue
            case "accentInk": accentInk = newValue
            case "border": border = newValue
            case "fn": fn = newValue
            case "fnInk": fnInk = newValue
            case "balloon": balloon = newValue
            case "trail": trail = newValue
            default: break
            }
        }
    }

    /// Đè `patch` lên (trường có trong patch thắng).
    func merged(with patch: ThemeSlots) -> ThemeSlots {
        var o = self
        for k in Self.colorKeys where patch[color: k] != nil { o[color: k] = patch[color: k] }
        if let d = patch.deco { o.deco = d }
        if let fx = patch.borderFx { o.borderFx = fx }
        if let sd = patch.spaceDeco { o.spaceDeco = sd }
        return o
    }

    /// Bản vá biến `base` thành `self` (trường khác nhau). Bỏ trường tuỳ chọn (viền, hoạ tiết, phím chức
    /// năng) = vá bằng giá trị tương đương (viền trong suốt, motif "none", fn = key, fnInk = ink).
    /// Bỏ nền (bg) của theme có nền không biểu diễn được ⇒ giữ nền (trả cờ `lostBg`).
    func patch(from base: ThemeSlots) -> (patch: ThemeSlots, lostBg: Bool) {
        var p = ThemeSlots()
        var lostBg = false
        for k in Self.colorKeys {
            let mine = self[color: k], theirs = base[color: k]
            guard mine != theirs else { continue }
            if let mine { p[color: k] = mine; continue }
            switch k {
            case "border": p.border = 0
            case "fn": p.fn = key ?? base.key
            case "fnInk": p.fnInk = ink ?? base.ink
            case "bg": lostBg = true
            default: break   // accentInk / balloon / trail bỏ = tự tính lại; base có ⇒ giữ base (chấp nhận)
            }
        }
        if deco != base.deco { p.deco = deco ?? ThemeDeco(motif: nil) }
        if borderFx != base.borderFx { p.borderFx = borderFx ?? "none" }
        if spaceDeco != base.spaceDeco { p.spaceDeco = spaceDeco ?? "none" }
        return (p, lostBg)
    }
}

// MARK: - Tệp tải về (mô hình — Android ThemeSpec.kt y hệt)

/// Một tệp: URL https (đã kiểm) + sha256 (64 hex chữ thường) nếu có.
struct ThemeAssetRef: Hashable {
    var url: String
    var sha256: String?
}

/// Phông tải về: tên hiển thị + tệp .ttf/.otf.
struct ThemeFontAsset: Equatable {
    var name: String
    var ref: ThemeAssetRef
}

/// Skin một phím / nhóm phím: ảnh (9-slice theo `slice` = [trên, trái, dưới, phải] px ẢNH GỐC) + ảnh khi đè.
struct ThemeKeySkin: Equatable {
    var image: ThemeAssetRef
    var slice: [Int]?
    var pressed: ThemeAssetRef?
}

/// Phần "tệp tải về" của theme (font / ảnh nền / tiền cảnh / skin phím). Nằm ở ThemeSpec lẫn KeyStyle (bản vá
/// theme có sẵn) — cùng bộ đọc (ThemeSpecParser.typography).
struct ThemeAssetSpec: Equatable {
    var font: ThemeFontAsset?
    var background: ThemeAssetRef?
    var foreground: ThemeAssetRef?
    var keys: [String: ThemeKeySkin] = [:]

    var isEmpty: Bool { font == nil && background == nil && foreground == nil && keys.isEmpty }
    var hasImages: Bool { background != nil || foreground != nil || !keys.isEmpty }

    static let groupKeys = ["default", "special"]
    static let namedKeys = ["space", "return", "shift", "delete"]
    static let letterKeys = (UInt8(ascii: "a")...UInt8(ascii: "z")).map { String(UnicodeScalar($0)) }
    static let skinKeys: Set<String> = Set(groupKeys + namedKeys + letterKeys)
    static let maxImages = 16
    static let maxFiles = 20
    static let maxSlice = 1024
    static let nameMax = 40

    /// `self` thắng từng trường; skin phím: có bộ nào thì thay CẢ bộ (không trộn hai bộ skin).
    func merged(over base: ThemeAssetSpec) -> ThemeAssetSpec {
        var o = self
        if o.font == nil { o.font = base.font }
        if o.background == nil { o.background = base.background }
        if o.foreground == nil { o.foreground = base.foreground }
        if o.keys.isEmpty { o.keys = base.keys }
        return o
    }
}

/// Kiểm URL tệp (thuần, Android y hệt): https://host/đường-dẫn, ASCII in được, không khoảng trắng / `\` /
/// user@ / cổng; host chữ thường a-z 0-9 . -, có dấu chấm, không phải IP số; phông: đường dẫn kết thúc .ttf/.otf.
enum ThemeAssetURL {
    static let prefix = "https://"

    static func isValid(_ s: String, font: Bool) -> Bool {
        guard s.hasPrefix(prefix), s.utf8.count <= 200 else { return false }
        for b in s.utf8 where b <= 0x20 || b >= 0x7F || b == UInt8(ascii: "\\") || b == UInt8(ascii: "\"") { return false }
        let rest = s.utf8.dropFirst(prefix.utf8.count)
        let hostEnd = rest.firstIndex(where: { $0 == UInt8(ascii: "/") || $0 == UInt8(ascii: "?") || $0 == UInt8(ascii: "#") })
        let host = Array(rest[rest.startIndex..<(hostEnd ?? rest.endIndex)])
        guard !host.isEmpty, host.count <= 253, hostEnd != nil, s.utf8[hostEnd!] == UInt8(ascii: "/") else { return false }
        var dot = false, allNumeric = true
        for b in host {
            switch b {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "-"): allNumeric = false
            case UInt8(ascii: "0")...UInt8(ascii: "9"): break
            case UInt8(ascii: "."): dot = true
            default: return false   // chữ hoa, @, :, [ …
            }
        }
        guard dot, !allNumeric, host.first != UInt8(ascii: "."), host.last != UInt8(ascii: "."),
              host.first != UInt8(ascii: "-") else { return false }
        if font {
            let path = s.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? s
            let low = path.lowercased()
            guard low.hasSuffix(".ttf") || low.hasSuffix(".otf") else { return false }
        }
        return true
    }

    /// Tên miền (hiện trong câu hỏi trước khi tải).
    static func host(_ s: String) -> String {
        let rest = s.dropFirst(prefix.count)
        return String(rest.prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" }))
    }

    /// "64 hex" (hoa / thường) ⇒ chữ thường; sai ⇒ nil.
    static func sha256(_ s: String) -> String? {
        guard s.utf8.count == 64, s.utf8.allSatisfy({ StrictJSONHex.digit($0) != nil }) else { return nil }
        return s.lowercased()
    }
}

/// Một mục "schedule": từ phút `from` trong ngày (0…1439) dùng bảng màu `slots` (đầy đủ như "light").
struct ThemeScheduleEntry: Equatable {
    var from: Int
    var slots: ThemeSlots
}

/// Chọn bảng màu theo giờ (thuần — Android ThemeSchedule y hệt, test mốc chung).
enum ThemeSchedule {
    static let entryRange = 2...6
    static let minutesPerDay = 24 * 60

    /// "HH:MM" (đúng 5 ký tự, 00…23 : 00…59) ⇒ phút trong ngày; sai ⇒ nil.
    static func parseTime(_ s: String) -> Int? {
        let u = Array(s.utf8)
        guard u.count == 5, u[2] == UInt8(ascii: ":") else { return nil }
        var d: [Int] = []
        for i in [0, 1, 3, 4] {
            guard u[i] >= 0x30, u[i] <= 0x39 else { return nil }
            d.append(Int(u[i]) - 0x30)
        }
        let h = d[0] * 10 + d[1], m = d[2] * 10 + d[3]
        guard h < 24, m < 60 else { return nil }
        return h * 60 + m
    }
    static func format(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    /// Chỉ số mục đang hiệu lực ở phút `minute` (kẹp vào ngày): mục có `from` lớn nhất ≤ phút; trước mục đầu ⇒ mục
    /// cuối (đêm qua nửa đêm). `froms` tăng dần (bộ đọc đã kiểm), rỗng ⇒ nil.
    static func index(_ froms: [Int], minute: Int) -> Int? {
        guard !froms.isEmpty else { return nil }
        let m = ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
        var best = froms.count - 1
        for (i, f) in froms.enumerated() where f <= m { best = i }
        return best
    }

    /// Phút trong ngày theo giờ địa phương (lịch máy) — gọi MỘT lần mỗi lần hiện bàn phím, chỉ khi theme có lịch.
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

struct ThemeSpec: Equatable {
    static let version = 1
    static let maxName = 40
    var id: String?
    var nameVi: String
    var nameEn: String?
    var light: ThemeSlots
    /// nil = "same" (giống sáng).
    var dark: ThemeSlots?
    var corner: Int?
    var fontScale: Int?
    var font: KeyLabelFont?
    var weight: KeyLabelWeight?
    /// Tệp tải về (phông / ảnh nền / tiền cảnh / skin phím). Có `assets.font` ⇒ `font` = nil.
    var assets = ThemeAssetSpec()
    /// Âm phím / hiệu ứng bấm phím đi kèm (id ThemeExtraIds) — chỉ áp lúc chọn theme.
    var sound: String?
    var effect: String?
    /// Nét vuốt của theme (id ThemeExtraIds.swipes) — chỉ dùng khi cài đặt nét vuốt = "Theo giao diện".
    var swipe: String?
    /// Trò chơi khi gõ ("mole") — chạy khi theme đang dùng (ThemeExtraIds.games).
    var game: String?
    /// Dáng phím ("pixel") — ThemeExtraIds.keyShapes.
    var keyShape: String?
    /// Hiệu ứng trên ảnh nền ("spotlight" — Đèn rọi) — chạy khi theme đang dùng (ThemeExtraIds.photoFx).
    var photoFx: String? = nil
    /// Bảng màu theo giờ (ThemeSchedule); nil = theo sáng/tối hệ thống như mọi theme.
    var schedule: [ThemeScheduleEntry]? = nil
    /// Nhãn ("interactive" — ThemeTags.known), thứ tự như trong JSON; nil = không có (mảng rỗng cũng là nil).
    var tags: [String]? = nil
    /// Bạn đồng hành đi kèm (ghi một lần lúc chọn theme — ThemeExtras.applyBuddyOnSelect); nil = không đổi.
    var buddy: ThemeBuddy? = nil
    /// Bảng màu theo lựa chọn người dùng ("zodiac" — ThemeVariants.known); nil = theo "light"/"dark" như mọi theme.
    var variant: String? = nil
    /// Theme tương tác (nhãn "interactive") — chip "Tương tác" + nhóm riêng trong màn chọn giao diện.
    var isInteractive: Bool { tags?.contains(ThemeTags.interactive) ?? false }

    func slots(dark d: Bool) -> ThemeSlots { d ? (dark ?? light) : light }
    /// Bảng màu ở phút `minute` trong ngày: có lịch ⇒ mục đang hiệu lực (bỏ qua sáng/tối); không lịch / `minute` nil
    /// ⇒ như `slots(dark:)`.
    func slots(dark d: Bool, minute: Int?) -> ThemeSlots {
        guard let sc = schedule, let m = minute, let i = ThemeSchedule.index(sc.map(\.from), minute: m) else { return slots(dark: d) }
        return sc[i].slots
    }
    /// Chỉ số mục lịch đang hiệu lực (nil = không có lịch).
    func scheduleIndex(minute: Int) -> Int? { schedule.flatMap { ThemeSchedule.index($0.map(\.from), minute: minute) } }
    var name: String { L10n.isEnglish ? (nameEn ?? nameVi) : nameVi }

    /// Kiểu chữ / bo góc / tệp tải về mặc định của theme (KeyStyle không đặt thì dùng cái này).
    var typography: KeyStyle {
        var k = KeyStyle(corner: corner, fontScale: fontScale, font: font ?? .standard, weight: weight ?? .regular)
        k.assets = assets
        k.sound = sound
        k.effect = effect
        k.swipe = swipe
        k.game = game
        k.keyShape = keyShape
        k.photoFx = photoFx
        return k
    }
}

/// "buddy" của theme JSON: nhân vật (id BuddyCharacter, không "off") + cỡ tuỳ chọn (BuddyPlacement.sizeRange).
struct ThemeBuddy: Equatable {
    var character: String
    var size: Int? = nil
}

/// "variant" của theme JSON — bảng màu theo lựa chọn của người dùng (Android ThemeVariants y hệt, fixture chung chốt).
struct ThemeVariantChoice: Equatable {
    var zodiac: ZodiacSign = .defaultValue
    var pride: PrideFlag = .defaultValue

    static func load(_ d: UserDefaults?) -> ThemeVariantChoice {
        var c = ThemeVariantChoice()
        c.zodiac = ZodiacSign.load(d)
        c.pride = PrideFlag.load(d)
        return c
    }
    /// Chưa từng chọn ⇒ không tạo khoá (máy giữ mặc định); đã có khoá ⇒ ghi.
    func save(_ d: UserDefaults?) {
        guard let d else { return }
        if zodiac != .defaultValue || d.object(forKey: ZodiacSign.key) != nil { d.set(zodiac.rawValue, forKey: ZodiacSign.key) }
        if pride != .defaultValue || d.object(forKey: PrideFlag.key) != nil { d.set(pride.rawValue, forKey: PrideFlag.key) }
    }
}

enum ThemeVariants {
    static let zodiac = "zodiac"
    static let pride = "pride"
    static let known: Set<String> = [zodiac, pride]

    /// Bảng màu của biến thể theo lựa chọn; nil = biến thể lạ (không xảy ra với spec đã kiểm).
    static func slots(_ v: String, _ c: ThemeVariantChoice) -> ThemeSlots? {
        switch v {
        case zodiac: return c.zodiac.element.slots
        case pride: return c.pride.slots
        default: return nil
        }
    }

    /// Palette đã giải của biến thể (gồm ký hiệu góc). nil ⇒ dùng light/dark.
    static func palette(_ v: String, _ c: ThemeVariantChoice) -> KeyboardPalette? {
        guard let s = slots(v, c) else { return nil }
        var p = ThemeSpec.palette(s)
        if v == zodiac { p.cornerGlyph = c.zodiac.glyph }
        if v == pride { p.auroraColors = c.pride.stripes }
        return p
    }
}

/// Nhãn theme ("tags") — danh sách trắng; Android ThemeTags y hệt (fixture chung chốt).
enum ThemeTags {
    static let interactive = "interactive"
    static let known: Set<String> = [interactive]
}

/// Danh sách trắng id "sound" / "effect" của theme JSON = đúng danh sách kiểu âm dựng sẵn / hiệu ứng của app
/// (KeySoundStyle.presetIDs, KeyEffect) — Android ThemeExtraIds y hệt (fixture chung chốt).
enum ThemeExtraIds {
    static let sounds: Set<String> = Set(KeySoundStyle.presetIDs)
    static let effects: Set<String> = Set(KeyEffect.allCases.map(\.rawValue))
    /// "swipe": kiểu nét vuốt cụ thể (không có "theme" — theme không trỏ về chính nó).
    static let swipes: Set<String> = Set(SwipeTrailStyle.themeIds)
    /// "game": trò chơi khi gõ (Android ThemeExtraIds.GAMES y hệt).
    static let games: Set<String> = [MoleGame.themeGame]
    /// "keyShape": dáng phím (Android ThemeExtraIds.KEY_SHAPES y hệt).
    static let keyShapes: Set<String> = [PixelKeys.shape]
    /// "photoFx": hiệu ứng trên ảnh nền (Android ThemeExtraIds.PHOTO_FX y hệt).
    static let spotlight = "spotlight"
    static let photoFx: Set<String> = [spotlight]
    /// "buddy.character": mọi nhân vật trừ "off" (Android ThemeExtraIds.BUDDIES y hệt).
    static let buddies: Set<String> = Set(BuddyCharacter.allCases.filter { $0 != .off }.map(\.rawValue))
}

// MARK: - Đọc / kiểm

enum ThemeSpecParser {
    struct Outcome {
        var spec: ThemeSpec?
        var issues: [ThemeIssue]
        var errors: [ThemeIssue] { issues.filter(\.isError) }
    }

    private struct Ctx {
        var issues: [ThemeIssue] = []
        mutating func err(_ c: ThemeIssue.Code, _ p: String) { issues.append(ThemeIssue(code: c, path: p)) }
        var failed: Bool { issues.contains(where: \.isError) }
    }

    static let assetKeys: Set<String> = ["background", "foreground", "keys"]
    static let rootKeys: Set<String> = Set(["v", "id", "name", "light", "dark", "corner", "fontScale", "font", "weight",
                                            "sound", "effect", "swipe", "game", "keyShape", "schedule", "photoFx",
                                            "tags", "buddy", "variant"])
        .union(assetKeys)
    static let slotKeys: Set<String> = Set(ThemeSlots.colorKeys + ["deco", "borderFx", "spaceDeco"])

    /// Đọc theme ĐẦY ĐỦ từ văn bản (dán / trình sửa). Cảnh báo tương phản kèm theo.
    static func parse(_ text: String) -> Outcome {
        switch StrictJSON.parse(text) {
        case .failure(let e): return Outcome(spec: nil, issues: [e])
        case .success(let j): return spec(from: j, contrast: true)
        }
    }
    static func parse(_ data: Data) -> Outcome {
        switch StrictJSON.parse(data) {
        case .failure(let e): return Outcome(spec: nil, issues: [e])
        case .success(let j): return spec(from: j, contrast: true)
        }
    }

    static func spec(from j: StrictJSON, contrast: Bool) -> Outcome {
        var c = Ctx()
        guard case .object(let m) = j else { return Outcome(spec: nil, issues: [ThemeIssue(code: .wrongType, path: "$")]) }
        let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
        for (k, _) in m where !rootKeys.contains(k) { c.err(.unknownKey, k) }
        switch d["v"] {
        case .int(1)?: break
        case nil: c.err(.missingKey, "v")
        case .int?: c.err(.badVersion, "v")
        default: c.err(.wrongType, "v")
        }
        var id: String?
        if let v = d["id"] {
            if case .string(let s) = v {
                if KeyStyleStore.validId(s) { id = s } else { c.err(.badValue, "id") }
            } else { c.err(.wrongType, "id") }
        }
        var vi = "", en: String?
        switch d["name"] {
        case nil: c.err(.missingKey, "name")
        case .object(let nm)?:
            for (k, _) in nm where k != "vi" && k != "en" { c.err(.unknownKey, "name." + k) }
            let nd = Dictionary(nm, uniquingKeysWith: { a, _ in a })
            vi = name(nd["vi"], "name.vi", required: true, &c) ?? ""
            en = name(nd["en"], "name.en", required: false, &c)
        default: c.err(.wrongType, "name")
        }
        var light = ThemeSlots()
        switch d["light"] {
        case nil: c.err(.missingKey, "light")
        case let v?: light = slots(v, "light", full: true, &c)
        }
        var dark: ThemeSlots?
        switch d["dark"] {
        case nil, .string("same")?: dark = nil
        case .string?: c.err(.badValue, "dark")
        case let v?: dark = slots(v, "dark", full: true, &c)
        }
        var typo = KeyStyle()
        typography(d, &typo, &c)
        var schedule: [ThemeScheduleEntry]?
        if let v = d["schedule"] { schedule = Self.schedule(v, &c) }
        var tags: [String]?
        if let v = d["tags"] { tags = Self.tags(v, &c) }
        var buddy: ThemeBuddy?
        if let v = d["buddy"] { buddy = Self.buddy(v, &c) }
        var variant: String?
        switch d["variant"] {
        case nil: break
        case .string(let s)?: if ThemeVariants.known.contains(s) { variant = s } else { c.err(.badValue, "variant") }
        default: c.err(.wrongType, "variant")
        }
        guard !c.failed else { return Outcome(spec: nil, issues: c.issues) }
        var spec = ThemeSpec(id: id, nameVi: vi, nameEn: en, light: light, dark: dark == light ? nil : dark)
        spec.corner = typo.corner
        spec.fontScale = typo.fontScale
        if d["font"] != nil { spec.font = typo.font }
        if d["weight"] != nil { spec.weight = typo.weight }
        spec.assets = typo.assets
        if spec.assets.font != nil { spec.font = nil }
        spec.sound = typo.sound
        spec.effect = typo.effect
        spec.swipe = typo.swipe
        spec.game = typo.game
        spec.keyShape = typo.keyShape
        spec.photoFx = typo.photoFx
        spec.schedule = schedule
        spec.tags = tags
        spec.buddy = buddy
        spec.variant = variant
        if contrast { c.issues += contrastIssues(spec) }
        return Outcome(spec: c.failed ? nil : spec, issues: c.issues)
    }

    /// "tags": mảng nhãn trong ThemeTags.known, không lặp; rỗng ⇒ nil.
    private static func tags(_ v: StrictJSON, _ c: inout Ctx) -> [String]? {
        guard case .array(let a) = v else { c.err(.wrongType, "tags"); return nil }
        var out: [String] = []
        for (i, e) in a.enumerated() {
            let p = "tags[\(i)]"
            guard case .string(let t) = e else { c.err(.wrongType, p); continue }
            guard ThemeTags.known.contains(t), !out.contains(t) else { c.err(.badValue, p); continue }
            out.append(t)
        }
        return out.isEmpty ? nil : out
    }

    /// "buddy": {"character": id (ThemeExtraIds.buddies), "size": 1…20 (kẹp + clamped)?}.
    private static func buddy(_ v: StrictJSON, _ c: inout Ctx) -> ThemeBuddy? {
        guard case .object(let m) = v else { c.err(.wrongType, "buddy"); return nil }
        for (k, _) in m where k != "character" && k != "size" { c.err(.unknownKey, "buddy." + k) }
        let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
        var out: ThemeBuddy?
        switch d["character"] {
        case nil: c.err(.missingKey, "buddy.character")
        case .string(let id)?:
            if ThemeExtraIds.buddies.contains(id) { out = ThemeBuddy(character: id) } else { c.err(.badValue, "buddy.character") }
        default: c.err(.wrongType, "buddy.character")
        }
        switch d["size"] {
        case nil: break
        case .int(let n)?:
            let r = BuddyPlacement.sizeRange
            if !r.contains(n) { c.err(.clamped, "buddy.size") }
            out?.size = min(max(n, r.lowerBound), r.upperBound)
        default: c.err(.wrongType, "buddy.size")
        }
        return out
    }

    /// "schedule": mảng 2…6 {"from":"HH:MM","palette":{màu đầy đủ}}, "from" tăng dần.
    private static func schedule(_ v: StrictJSON, _ c: inout Ctx) -> [ThemeScheduleEntry]? {
        guard case .array(let a) = v else { c.err(.wrongType, "schedule"); return nil }
        guard ThemeSchedule.entryRange.contains(a.count) else { c.err(.badValue, "schedule"); return nil }
        var out: [ThemeScheduleEntry] = []
        for (i, e) in a.enumerated() {
            let p = "schedule[\(i)]"
            guard case .object(let m) = e else { c.err(.wrongType, p); continue }
            for (k, _) in m where k != "from" && k != "palette" { c.err(.unknownKey, p + "." + k) }
            let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
            var from: Int?
            switch d["from"] {
            case nil: c.err(.missingKey, p + ".from")
            case .string(let t)?:
                if let f = ThemeSchedule.parseTime(t) { from = f } else { c.err(.badValue, p + ".from") }
            default: c.err(.wrongType, p + ".from")
            }
            if let f = from, let last = out.last?.from, f <= last { c.err(.badValue, p + ".from"); from = nil }
            guard let pv = d["palette"] else { c.err(.missingKey, p + ".palette"); continue }
            let sl = Self.slots(pv, p + ".palette", full: true, &c)
            if let f = from { out.append(ThemeScheduleEntry(from: f, slots: sl)) }
        }
        return out.count == a.count ? out : nil
    }

    private static func name(_ v: StrictJSON?, _ p: String, required: Bool, _ c: inout Ctx) -> String? {
        guard let v else { if required { c.err(.missingKey, p) }; return nil }
        guard case .string(let s) = v else { c.err(.wrongType, p); return nil }
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { c.err(.badValue, p); return nil }
        if t.unicodeScalars.count > ThemeSpec.maxName { c.err(.tooLong, p); return nil }
        return t
    }

    /// Màu một chế độ. `full` = theme đầy đủ (bắt buộc key/special/ink/accent).
    static func slots(_ v: StrictJSON, _ p: String, full: Bool) -> (ThemeSlots, [ThemeIssue]) {
        var c = Ctx()
        let s = slots(v, p, full: full, &c)
        return (s, c.issues)
    }

    private static func slots(_ v: StrictJSON, _ p: String, full: Bool, _ c: inout Ctx) -> ThemeSlots {
        guard case .object(let m) = v else { c.err(.wrongType, p); return ThemeSlots() }
        var s = ThemeSlots()
        for (k, val) in m {
            let path = p + "." + k
            if k == "deco" { s.deco = deco(val, path, &c); continue }
            if k == "borderFx" {
                guard case .string(let fx) = val else { c.err(.wrongType, path); continue }
                guard ThemeSlots.borderFxValues.contains(fx) else { c.err(.badValue, path); continue }
                s.borderFx = fx
                continue
            }
            if k == "spaceDeco" {
                guard case .string(let sd) = val else { c.err(.wrongType, path); continue }
                guard ThemeSlots.spaceDecoValues.contains(sd) else { c.err(.badValue, path); continue }
                s.spaceDeco = sd
                continue
            }
            guard slotKeys.contains(k) else { c.err(.unknownKey, path); continue }
            guard case .string(let str) = val else { c.err(.wrongType, path); continue }
            guard let col = ThemeColorCode.parse(str) else { c.err(.badColor, path); continue }
            s[color: k] = col
        }
        if full {
            for k in ThemeSlots.requiredKeys where s[color: k] == nil && !m.contains(where: { $0.0 == k }) {
                c.err(.missingKey, p + "." + k)
            }
        }
        return s
    }

    private static func deco(_ v: StrictJSON, _ p: String, _ c: inout Ctx) -> ThemeDeco? {
        guard case .object(let m) = v else { c.err(.wrongType, p); return nil }
        let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
        for (k, _) in m where !["motif", "alt", "color", "density"].contains(k) { c.err(.unknownKey, p + "." + k) }
        var out = ThemeDeco(motif: nil)
        switch d["motif"] {
        case .string("none")?: out.motif = nil
        case .string(let s)?:
            guard let mo = KeyboardDecoration.Motif(rawValue: s) else { c.err(.badValue, p + ".motif"); return nil }
            out.motif = mo
        case nil: c.err(.missingKey, p + ".motif"); return nil
        default: c.err(.wrongType, p + ".motif"); return nil
        }
        if out.motif != nil {
            switch d["color"] {
            case .string(let s)?:
                guard let col = ThemeColorCode.parse(s) else { c.err(.badColor, p + ".color"); return nil }
                out.color = col
            case nil: c.err(.missingKey, p + ".color"); return nil
            default: c.err(.wrongType, p + ".color"); return nil
            }
        } else if d["color"] != nil {
            if case .string(let s)? = d["color"], ThemeColorCode.parse(s) != nil {} else { c.err(.badColor, p + ".color") }
        }
        // "alt": motif thứ hai xen kẽ (không "none"; bỏ qua khi motif = "none").
        switch d["alt"] {
        case nil: break
        case .string(let s)?:
            guard let mo = KeyboardDecoration.Motif(rawValue: s) else { c.err(.badValue, p + ".alt"); return nil }
            if out.motif != nil { out.alt = mo }
        default: c.err(.wrongType, p + ".alt"); return nil
        }
        switch d["density"] {
        case nil: break
        case .int(let n)?:
            let r = ThemeDeco.densityRange
            if !r.contains(n) { c.err(.clamped, p + ".density") }
            out.density = min(max(n, r.lowerBound), r.upperBound)
        default: c.err(.wrongType, p + ".density")
        }
        return out
    }

    /// corner / fontScale / font / weight (theme đầy đủ lẫn bản vá).
    private static func typography(_ d: [String: StrictJSON], _ s: inout KeyStyle, _ c: inout Ctx) {
        switch d["corner"] {
        case nil: break
        case .int(let n)?:
            if !(0...100).contains(n) { c.err(.clamped, "corner") }
            s.corner = min(max(n, 0), 100)
        default: c.err(.wrongType, "corner")
        }
        switch d["fontScale"] {
        case nil: break
        case .int(let n)?:
            if !(KeyStyle.fontScaleMin...KeyStyle.fontScaleMax).contains(n) { c.err(.clamped, "fontScale") }
            s.fontScale = min(max(n, KeyStyle.fontScaleMin), KeyStyle.fontScaleMax)
        default: c.err(.wrongType, "fontScale")
        }
        switch d["font"] {
        case nil: break
        case .string(let f)?: if let v = KeyLabelFont(rawValue: f) { s.font = v } else { c.err(.badValue, "font") }
        case .object(let m)?:
            if let fa = fontAsset(m, &c) { s.assets.font = fa; s.font = .standard }
        default: c.err(.wrongType, "font")
        }
        if let v = d["background"] { s.assets.background = assetRef(v, "background", font: false, &c) }
        if let v = d["foreground"] { s.assets.foreground = assetRef(v, "foreground", font: false, &c) }
        if let v = d["keys"] { s.assets.keys = keySkins(v, &c) }
        for i in assetLimitIssues(s.assets) { c.issues.append(i) }
        switch d["weight"] {
        case nil: break
        case .string(let f)?: if let v = KeyLabelWeight(rawValue: f) { s.weight = v } else { c.err(.badValue, "weight") }
        default: c.err(.wrongType, "weight")
        }
        func pick(_ k: String, _ allowed: Set<String>) -> String? {
            switch d[k] {
            case nil: return nil
            case .string(let v)?: if allowed.contains(v) { return v }; c.err(.badValue, k); return nil
            default: c.err(.wrongType, k); return nil
            }
        }
        s.sound = pick("sound", ThemeExtraIds.sounds)
        s.effect = pick("effect", ThemeExtraIds.effects)
        s.swipe = pick("swipe", ThemeExtraIds.swipes)
        s.game = pick("game", ThemeExtraIds.games)
        s.keyShape = pick("keyShape", ThemeExtraIds.keyShapes)
        s.photoFx = pick("photoFx", ThemeExtraIds.photoFx)
    }

    // MARK: tệp tải về

    /// {"url","sha256"?} (+ khoá thêm cho phông / skin). Sai ⇒ lỗi + nil.
    private static func assetRef(_ v: StrictJSON, _ p: String, font: Bool, extra: Set<String> = [],
                                 _ c: inout Ctx) -> ThemeAssetRef? {
        guard case .object(let m) = v else { c.err(.wrongType, p); return nil }
        for (k, _) in m where k != "url" && k != "sha256" && !extra.contains(k) { c.err(.unknownKey, p + "." + k) }
        let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
        var ok = true
        var ref = ThemeAssetRef(url: "")
        switch d["url"] {
        case nil: c.err(.missingKey, p + ".url"); ok = false
        case .string(let u)?:
            if ThemeAssetURL.isValid(u, font: font) { ref.url = u } else { c.err(.badUrl, p + ".url"); ok = false }
        default: c.err(.wrongType, p + ".url"); ok = false
        }
        switch d["sha256"] {
        case nil: break
        case .string(let h)?:
            if let x = ThemeAssetURL.sha256(h) { ref.sha256 = x } else { c.err(.badValue, p + ".sha256"); ok = false }
        default: c.err(.wrongType, p + ".sha256"); ok = false
        }
        return ok ? ref : nil
    }

    private static func fontAsset(_ m: [(String, StrictJSON)], _ c: inout Ctx) -> ThemeFontAsset? {
        let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
        let n = name(d["name"], "font.name", required: true, &c)
        guard let ref = assetRef(.object(m), "font", font: true, extra: ["name"], &c), let n else { return nil }
        return ThemeFontAsset(name: n, ref: ref)
    }

    private static func keySkins(_ v: StrictJSON, _ c: inout Ctx) -> [String: ThemeKeySkin] {
        guard case .object(let m) = v else { c.err(.wrongType, "keys"); return [:] }
        var out: [String: ThemeKeySkin] = [:]
        for (k, val) in m {
            let p = "keys." + k
            guard ThemeAssetSpec.skinKeys.contains(k) else { c.err(.unknownKey, p); continue }
            guard case .object(let im) = val else { c.err(.wrongType, p); continue }
            let d = Dictionary(im, uniquingKeysWith: { a, _ in a })
            guard let ref = assetRef(val, p, font: false, extra: ["slice", "pressed"], &c) else { continue }
            var skin = ThemeKeySkin(image: ref)
            var ok = true
            switch d["slice"] {
            case nil: break
            case .array(let a)?:
                var ins: [Int] = []
                for x in a {
                    if case .int(let n) = x { ins.append(n) } else { c.err(.wrongType, p + ".slice"); ok = false; break }
                }
                if ok {
                    if ins.count == 4, ins.allSatisfy({ (0...ThemeAssetSpec.maxSlice).contains($0) }) { skin.slice = ins }
                    else { c.err(.badValue, p + ".slice"); ok = false }
                }
            default: c.err(.wrongType, p + ".slice"); ok = false
            }
            if let pv = d["pressed"] {
                if let pr = assetRef(pv, p + ".pressed", font: false, &c) { skin.pressed = pr } else { ok = false }
            }
            if ok { out[k] = skin }
        }
        return out
    }

    /// ≤ 16 ảnh khác nhau (theo URL), ≤ 20 tệp (ảnh + phông).
    static func assetLimitIssues(_ a: ThemeAssetSpec) -> [ThemeIssue] {
        let images = ThemeAssetPlan.imageURLs(a)
        let files = images.count + (a.font == nil ? 0 : 1)
        var out: [ThemeIssue] = []
        if images.count > ThemeAssetSpec.maxImages {
            out.append(ThemeIssue(code: .tooManyFiles, path: "\(images.count) > \(ThemeAssetSpec.maxImages)"))
        } else if files > ThemeAssetSpec.maxFiles {
            out.append(ThemeIssue(code: .tooManyFiles, path: "\(files) > \(ThemeAssetSpec.maxFiles)"))
        }
        return out
    }

    /// Bản vá theo theme (KeyStyleStore): label / fill / accent (#RRGGBB, áp cả sáng lẫn tối), kiểu chữ,
    /// light / dark (vá từng chế độ). Khoá lạ / sai ⇒ nil (cả mục bị bỏ).
    static func override(from j: StrictJSON) -> KeyStyle? {
        guard case .object(let m) = j else { return nil }
        var c = Ctx()
        let allowed: Set<String> = Set(["label", "fill", "accent", "corner", "fontScale", "font", "weight", "light", "dark",
                                        "sound", "effect", "swipe", "game", "keyShape", "photoFx"])
            .union(assetKeys)
        for (k, _) in m where !allowed.contains(k) { c.err(.unknownKey, k) }
        let d = Dictionary(m, uniquingKeysWith: { a, _ in a })
        var st = KeyStyle()
        func rgb(_ k: String) -> UInt32? {
            guard let v = d[k] else { return nil }
            guard case .string(let s) = v, let col = ThemeColorCode.parse(s), col >> 24 == 0xFF else {
                c.err(.badColor, k); return nil
            }
            return col & 0xFFFFFF
        }
        st.labelColor = rgb("label")
        st.fillColor = rgb("fill")
        st.accentColor = rgb("accent")
        typography(d, &st, &c)
        if let l = d["light"] { st.light = slots(l, "light", full: false, &c) }
        if let k = d["dark"] { st.dark = slots(k, "dark", full: false, &c) }
        return c.failed ? nil : st
    }

    // MARK: tương phản

    /// Chữ/phím, chữ/phím chức năng, chữ/nhấn mỗi chế độ: < 2:1 lỗi, < 3:1 cảnh báo.
    static func contrastIssues(_ spec: ThemeSpec) -> [ThemeIssue] {
        var out: [ThemeIssue] = []
        var modes: [(String, ThemeSlots, Bool)] = [("light", spec.light, false)]
        if let d = spec.dark { modes.append(("dark", d, true)) }
        // Bảng theo giờ: kiểm trên backdrop theo độ sáng chữ của chính nó.
        for (i, e) in (spec.schedule ?? []).enumerated() {
            modes.append(("schedule[\(i)]", e.slots, ThemeSpec.palette(e.slots).isDark))
        }
        for (name, slots, dark) in modes {
            let p = ThemeSpec.palette(slots)
            let sys = KeyboardTransparency.systemBackdrop(dark: dark)
            let behind = p.background?.over(sys) ?? sys
            let pairs: [(String, RGBA, RGBA)] = [
                ("ink/key", p.ink, p.keyFill.over(behind)),
                ("fnInk/fn", p.fnInk, p.fnFill.over(behind)),
                ("accentInk/accent", p.accentInk, p.accent.over(behind)),
            ]
            for (what, fg, bg) in pairs {
                let r = RGBA.contrast(fg.over(bg), bg)
                if r < 2 { out.append(ThemeIssue(code: .contrastTooLow, path: "\(name) \(what)")) }
                else if r < 3 { out.append(ThemeIssue(code: .lowContrast, path: "\(name) \(what)")) }
            }
        }
        return out
    }
}

// MARK: - Ghi chuẩn

extension ThemeSpec {
    var json: StrictJSON {
        var m: [(String, StrictJSON)] = [("v", .int(Self.version))]
        if let id { m.append(("id", .string(id))) }
        var nm: [(String, StrictJSON)] = [("vi", .string(nameVi))]
        if let nameEn { nm.append(("en", .string(nameEn))) }
        m.append(("name", .object(nm)))
        m.append(("light", Self.json(light)))
        m.append(("dark", dark.map(Self.json) ?? .string("same")))
        if let corner { m.append(("corner", .int(corner))) }
        if let fontScale { m.append(("fontScale", .int(fontScale))) }
        if let fa = assets.font { m.append(("font", Self.json(fa))) }
        else if let font { m.append(("font", .string(font.rawValue))) }
        if let weight { m.append(("weight", .string(weight.rawValue))) }
        Self.appendImages(assets, to: &m)
        if let sound { m.append(("sound", .string(sound))) }
        if let effect { m.append(("effect", .string(effect))) }
        if let swipe { m.append(("swipe", .string(swipe))) }
        if let game { m.append(("game", .string(game))) }
        if let keyShape { m.append(("keyShape", .string(keyShape))) }
        if let photoFx { m.append(("photoFx", .string(photoFx))) }
        if let tags { m.append(("tags", .array(tags.map { .string($0) }))) }
        if let buddy {
            var b: [(String, StrictJSON)] = [("character", .string(buddy.character))]
            if let n = buddy.size { b.append(("size", .int(n))) }
            m.append(("buddy", .object(b)))
        }
        if let variant { m.append(("variant", .string(variant))) }
        if let schedule {
            m.append(("schedule", .array(schedule.map {
                .object([("from", .string(ThemeSchedule.format($0.from))), ("palette", Self.json($0.slots))])
            })))
        }
        return .object(m)
    }

    static func json(_ r: ThemeAssetRef, extra: [(String, StrictJSON)] = []) -> StrictJSON {
        var m: [(String, StrictJSON)] = [("url", .string(r.url))]
        if let h = r.sha256 { m.append(("sha256", .string(h))) }
        return .object(m + extra)
    }
    static func json(_ f: ThemeFontAsset) -> StrictJSON { json(f.ref, extra: [("name", .string(f.name))]) }
    static func json(_ k: ThemeKeySkin) -> StrictJSON {
        var extra: [(String, StrictJSON)] = []
        if let s = k.slice { extra.append(("slice", .array(s.map { .int($0) }))) }
        if let p = k.pressed { extra.append(("pressed", json(p))) }
        return json(k.image, extra: extra)
    }
    /// background / foreground / keys (font ghi riêng — chung khoá với phông hệ thống).
    static func appendImages(_ a: ThemeAssetSpec, to m: inout [(String, StrictJSON)]) {
        if let b = a.background { m.append(("background", json(b))) }
        if let f = a.foreground { m.append(("foreground", json(f))) }
        if !a.keys.isEmpty { m.append(("keys", .object(a.keys.map { ($0.key, json($0.value)) }))) }
    }
    /// Chuỗi chuẩn (trùng Android từng ký tự).
    var canonical: String { json.canonical }

    static func json(_ s: ThemeSlots) -> StrictJSON {
        var m: [(String, StrictJSON)] = []
        for k in ThemeSlots.colorKeys { if let v = s[color: k] { m.append((k, .string(ThemeColorCode.format(v)))) } }
        if let d = s.deco {
            var dm: [(String, StrictJSON)] = [("motif", .string(d.motif?.rawValue ?? "none"))]
            if d.motif != nil {
                if let a = d.alt { dm.append(("alt", .string(a.rawValue))) }
                dm.append(("color", .string(ThemeColorCode.format(d.color))))
                if d.density != 100 { dm.append(("density", .int(d.density))) }
            }
            m.append(("deco", .object(dm)))
        }
        if let fx = s.borderFx { m.append(("borderFx", .string(fx))) }
        if let sd = s.spaceDeco { m.append(("spaceDeco", .string(sd))) }
        return .object(m)
    }
}

// MARK: - Spec ⇄ palette

extension ThemeSpec {
    /// Chữ trên nền nhấn tự tính: trắng nếu đọc được (≥ 3:1), không thì đen/trắng tương phản hơn.
    static func autoAccentInk(_ accent: RGBA) -> RGBA { KeyboardTransparency.readable(.white, on: accent) }

    /// Palette một chế độ (trước ảnh nền / độ trong suốt). Mặc định: balloon = key, trail = nhấn 60%,
    /// accentInk tự tính. Thiếu màu bắt buộc (không xảy ra với spec đã kiểm) ⇒ xám an toàn.
    func palette(dark d: Bool) -> KeyboardPalette {
        Self.palette(slots(dark: d))
    }
    /// Palette lúc `date`: theme có lịch ⇒ bảng của giờ địa phương đó (đọc lịch máy MỘT lần); không lịch ⇒
    /// `palette(dark:)` — không đụng tới lịch/đồng hồ.
    func palette(dark d: Bool, at date: Date, choice: ThemeVariantChoice) -> KeyboardPalette {
        if let v = variant, let p = ThemeVariants.palette(v, choice) { return p }
        return palette(dark: d, at: date)
    }
    func palette(dark d: Bool, at date: Date) -> KeyboardPalette {
        guard schedule != nil else { return palette(dark: d) }
        return Self.palette(slots(dark: d, minute: ThemeSchedule.minuteOfDay(date)))
    }

    static func palette(_ s: ThemeSlots) -> KeyboardPalette {
        let c = ThemeColorCode.rgba
        let key = c(s.key ?? 0xFFFF_FFFF), ink = c(s.ink ?? 0xFF00_0000)
        let accent = c(s.accent ?? 0xFF00_7AFF)
        var p = KeyboardPalette(background: s.bg.map(c), keyFill: key, specialFill: c(s.special ?? 0xFFCCCCCC), ink: ink,
                                trail: s.trail.map(c) ?? accent.alpha(0.6), barInk: ink,
                                balloon: s.balloon.map(c) ?? key, accent: accent,
                                accentInk: s.accentInk.map(c) ?? autoAccentInk(accent),
                                keyBorder: s.border.map(c), isDark: ink.luminance > 0.5)
        p.functionFill = s.fn.map(c)
        p.functionInk = s.fnInk.map(c)
        // Nền đục mà chữ theme không đọc được trên nền (Piano: phím ngà chữ đen trên thân đàn đen) ⇒ thanh gợi ý /
        // bảng emoji theo tông NỀN (chữ đen/trắng đọc được), phím vẫn theo `ink`. Theme khác: không đổi gì.
        if let bg = s.bg.map(c) {
            let solid = RGBA(r: bg.r, g: bg.g, b: bg.b)
            if RGBA.contrast(ink, solid) < KeyboardTransparency.minLabelContrast {
                p.barInk = KeyboardTransparency.readable(ink, on: solid)
                p.surfaceDark = solid.luminance < 0.18
            }
        }
        if let dc = s.deco, let m = dc.motif {
            p.decoration = KeyboardDecoration(motif: m, color: c(dc.color), density: dc.density, alt: dc.alt)
        }
        p.rainbowBorder = s.borderFx == ThemeSlots.rainbow
        p.auroraBorder = s.borderFx == ThemeSlots.aurora
        p.spaceSoundhole = s.spaceDeco == ThemeSlots.soundhole
        return p
    }

    /// Ngược lại: palette (đã giải) → màu một chế độ; bỏ trường bằng mặc định tự tính.
    static func slots(from p: KeyboardPalette) -> ThemeSlots {
        let a = ThemeColorCode.argb
        var s = ThemeSlots()
        s.bg = p.background.map(a)
        s.key = a(p.keyFill); s.special = a(p.specialFill); s.ink = a(p.ink); s.accent = a(p.accent)
        if a(p.accentInk) != a(autoAccentInk(p.accent)) { s.accentInk = a(p.accentInk) }
        s.border = p.keyBorder.map(a)
        s.fn = p.functionFill.map(a)
        s.fnInk = p.functionInk.map(a)
        if a(p.balloon) != a(p.keyFill) { s.balloon = a(p.balloon) }
        if a(p.trail) != a(p.accent.alpha(0.6)) { s.trail = a(p.trail) }
        if let d = p.decoration { s.deco = ThemeDeco(motif: d.motif, color: a(d.color), density: d.density, alt: d.alt) }
        if p.rainbowBorder { s.borderFx = ThemeSlots.rainbow }
        if p.auroraBorder { s.borderFx = ThemeSlots.aurora }
        if p.spaceSoundhole { s.spaceDeco = ThemeSlots.soundhole }
        return s
    }

    /// Theme đầy đủ từ palette sáng/tối đã giải + kiểu chữ ("Chép JSON").
    static func export(id: String?, nameVi: String, nameEn: String?, light: KeyboardPalette, dark: KeyboardPalette,
                       style: KeyStyle) -> ThemeSpec {
        let l = slots(from: light), d = slots(from: dark)
        var s = ThemeSpec(id: id, nameVi: nameVi, nameEn: nameEn, light: l, dark: d == l ? nil : d)
        s.corner = style.corner
        s.fontScale = style.fontScale
        if style.font != .standard { s.font = style.font }
        if style.weight != .regular { s.weight = style.weight }
        s.assets = style.assets
        if s.assets.font != nil { s.font = nil }
        s.sound = style.sound
        s.effect = style.effect
        s.swipe = style.swipe
        s.game = style.game
        s.keyShape = style.keyShape
        s.photoFx = style.photoFx
        return s
    }
}

// MARK: - Theme có sẵn

enum BuiltinThemes {
    /// Đọc MỘT lần (static let — lười, an toàn luồng). Hỏng (không xảy ra — test khoá) ⇒ rỗng ⇒ theme
    /// đó vẽ như Hệ thống.
    static let specs: [String: ThemeSpec] = parse(BuiltinThemesData.json)

    static func parse(_ text: String) -> [String: ThemeSpec] {
        var lim = StrictJSON.Limits()
        lim.maxBytes = 64 * 1024
        guard case .success(.object(let root)) = StrictJSON.parse(text, limits: lim),
              let themes = root.first(where: { $0.0 == "themes" })?.1, case .array(let arr) = themes else { return [:] }
        var out: [String: ThemeSpec] = [:]
        for t in arr {
            if let s = ThemeSpecParser.spec(from: t, contrast: false).spec, let id = s.id { out[id] = s }
        }
        return out
    }
}

// MARK: - Theme tự tạo

/// Theme tự tạo / dán (Plus): App Group `customThemes` = chuỗi chuẩn {"id": spec, …} (sao lưu + iCloud);
/// `activeThemeSpec` = chuỗi chuẩn của theme ĐANG CHỌN (chỉ bàn phím đọc — không phải đọc cả kho).
enum CustomThemeStore {
    static let key = "customThemes"
    static let activeKey = "activeThemeSpec"
    static let maxThemes = 50
    static let maxBytes = 16 * 1024
    /// Cả kho: 50 theme × ≤ 16 KB.
    static let maxStoreBytes = maxThemes * maxBytes + 1024

    static func parse(_ raw: String?) -> [String: ThemeSpec] {
        guard let raw, !raw.isEmpty else { return [:] }
        var lim = StrictJSON.Limits()
        lim.maxBytes = maxStoreBytes
        lim.maxDepth = 9
        guard case .success(.object(let m)) = StrictJSON.parse(raw, limits: lim) else { return [:] }
        var out: [String: ThemeSpec] = [:]
        for (id, v) in m where KeyStyleStore.validId(id) && KeyboardTheme(rawValue: id) == nil && out.count < maxThemes {
            guard var s = ThemeSpecParser.spec(from: v, contrast: false).spec else { continue }
            s.id = id
            out[id] = s
        }
        return out
    }

    static func serialize(_ m: [String: ThemeSpec]) -> String {
        StrictJSON.object(m.map { id, s in var t = s; t.id = id; return (id, t.json) }).canonical
    }

    static func normalize(_ raw: String) -> String? {
        var lim = StrictJSON.Limits()
        lim.maxBytes = maxStoreBytes
        lim.maxDepth = 9
        guard case .success(.object) = StrictJSON.parse(raw, limits: lim) else { return nil }
        return serialize(parse(raw))
    }

    static func load(_ d: UserDefaults?) -> [String: ThemeSpec] { parse(d?.string(forKey: key)) }
    static func save(_ m: [String: ThemeSpec], _ d: UserDefaults?) { d?.set(serialize(m), forKey: key) }

    /// Id không trùng theme có sẵn / theme tự tạo: giữ `want` nếu trống, không thì "-2", "-3"… (Android y hệt).
    static func uniqueId(_ want: String?, taken: Set<String>) -> String {
        let base = String((want.flatMap { KeyStyleStore.validId($0) ? $0 : nil } ?? "custom").prefix(36))
        func free(_ s: String) -> Bool { !taken.contains(s) && KeyboardTheme(rawValue: s) == nil }
        if free(base) { return base }
        var n = 2
        while !free("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// Thêm theme (dán). Đủ 50 ⇒ lỗi `tooMany`.
    static func add(_ spec: ThemeSpec, to m: [String: ThemeSpec]) -> Result<(id: String, store: [String: ThemeSpec]), ThemeIssue> {
        guard m.count < maxThemes else { return .failure(ThemeIssue(code: .tooMany, path: String(maxThemes))) }
        let id = uniqueId(spec.id, taken: Set(m.keys))
        var s = spec
        s.id = id
        var out = m
        out[id] = s
        return .success((id, out))
    }

    /// Bàn phím: theme đang chọn (đã chuẩn hoá bởi app) — kiểm lại; hỏng ⇒ nil (về Hệ thống). Nhớ chuỗi
    /// lần trước ⇒ cùng chuỗi không đọc lại.
    static func active(_ raw: String?, id: String) -> ThemeSpec? {
        guard let raw else { return nil }
        if let c = cache, c.raw == raw { return c.spec?.id == id ? c.spec : nil }
        var spec = ThemeSpecParser.parse(raw).spec
        if spec?.id == nil { spec?.id = id }
        cache = (raw, spec)
        #if DEBUG
        if spec == nil { NSLog("VTTheme: activeThemeSpec hỏng — về Hệ thống") }
        #endif
        return spec?.id == id ? spec : nil
    }
    nonisolated(unsafe) private static var cache: (raw: String, spec: ThemeSpec?)?
}

// MARK: - Hành động thẻ "Chọn giao diện" (thuần — app gọi, test được; Android ThemeJsonActions y hệt)

enum ThemeEditTarget: Equatable {
    case builtin(KeyboardTheme)
    case custom(String)
}

enum ThemeJSONActions {
    /// "Chép JSON" (miễn phí): theme thực thấy gồm tuỳ chỉnh, dạng dễ đọc.
    static func copyText(_ t: ThemeEditTarget, settings s: ThemeSettings, store: [String: ThemeSpec]) -> String? {
        switch t {
        case .builtin(let b): return s.exportSpec(for: b).json.pretty
        case .custom(let id): return store[id].map { s.exportSpec(custom: $0).json.pretty }
        }
    }

    /// Lưu văn bản đã sửa. Theme có sẵn ⇒ bản vá (KeyStyle) so với theme gốc; theme tự tạo ⇒ thay đặc tả
    /// (giữ id), bỏ tuỳ chỉnh rời. Lỗi ⇒ không đổi gì, trả danh sách lỗi. Thành công ⇒ cảnh báo (nếu có).
    static func save(_ text: String, to t: ThemeEditTarget, settings s: inout ThemeSettings,
                     store: inout [String: ThemeSpec]) -> (ok: Bool, issues: [ThemeIssue]) {
        let out = ThemeSpecParser.parse(text)
        guard let spec = out.spec else { return (false, out.issues) }
        var warnings = out.issues
        switch t {
        case .builtin(let b):
            let bl = b.spec?.light ?? ThemeSpec.slots(from: b.palette(systemDark: false))
            let bd = b.spec?.slots(dark: true) ?? ThemeSpec.slots(from: b.palette(systemDark: true))
            let r = KeyStyle.fromEdited(spec, baseLight: bl, baseDark: bd)
            var st = r.style
            // Kiểu chữ trùng mặc định theme ⇒ không lưu (theme đổi mặc định về sau vẫn theo).
            if st.corner == b.spec?.corner { st.corner = nil }
            if st.fontScale == b.spec?.fontScale { st.fontScale = nil }
            if let f = b.spec?.font, st.font == f { st.font = .standard }
            if let w = b.spec?.weight, st.weight == w { st.weight = .regular }
            if st.sound == b.spec?.sound { st.sound = nil }
            if st.effect == b.spec?.effect { st.effect = nil }
            if st.swipe == b.spec?.swipe { st.swipe = nil }
            if st.game == b.spec?.game { st.game = nil }
            if st.keyShape == b.spec?.keyShape { st.keyShape = nil }
            if st.photoFx == b.spec?.photoFx { st.photoFx = nil }
            s.setStyle(st, for: b)
            if r.lostBg { warnings.append(ThemeIssue(code: .bgKept, path: "bg")) }
        case .custom(let id):
            guard store[id] != nil else { return (false, [ThemeIssue(code: .missingKey, path: id)]) }
            var n = spec
            n.id = id
            store[id] = n
            s.keyStyles[id] = nil
            if s.custom?.id == id { s.custom = n }
        }
        return (true, warnings)
    }

    /// "Đặt lại mặc định" (theme có sẵn): bỏ mọi tuỳ chỉnh của theme đó.
    static func reset(_ b: KeyboardTheme, settings s: inout ThemeSettings) { s.setStyle(KeyStyle(), for: b) }

    /// "Xoá" (theme tự tạo): bỏ khỏi kho + tuỳ chỉnh; đang chọn ⇒ về Hệ thống.
    static func delete(_ id: String, settings s: inout ThemeSettings, store: inout [String: ThemeSpec]) {
        store[id] = nil
        s.keyStyles[id] = nil
        if s.custom?.id == id { s.select(.system) }
    }

    /// "Dán giao diện": CHỈ khi người dùng bấm (không tự đọc clipboard). Trả kết quả kiểm để XEM TRƯỚC;
    /// `commitPaste` mới ghi.
    static func preview(_ text: String) -> ThemeSpecParser.Outcome { ThemeSpecParser.parse(text) }

    static func commitPaste(_ spec: ThemeSpec, store: inout [String: ThemeSpec]) -> Result<String, ThemeIssue> {
        switch CustomThemeStore.add(spec, to: store) {
        case .failure(let e): return .failure(e)
        case .success(let r): store = r.store; return .success(r.id)
        }
    }
}

extension ThemeSettings {
    /// App (khởi động): theme tự tạo đang chọn đồng bộ lại với kho (sửa / xoá trên máy khác qua iCloud);
    /// mất khỏi kho ⇒ về Hệ thống. Không chọn theme tự tạo ⇒ không làm gì.
    static func refreshCustom(_ d: UserDefaults?) {
        guard let d, let raw = d.string(forKey: themeKey), KeyboardTheme(rawValue: raw) == nil,
              raw != KeyStyleStore.removedPureWhite else { return }
        var s = load(d)
        let fresh = CustomThemeStore.load(d)[raw]
        guard fresh != s.custom else { return }
        if let fresh { s.select(custom: fresh) } else { s.select(.system) }
        s.save(d)
    }
}
