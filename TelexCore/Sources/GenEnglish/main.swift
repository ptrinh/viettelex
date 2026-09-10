// gen-english — sinh bảng TỐI GIẢN các từ tiếng Anh va chạm Telex.
//
// Nguyên liệu: danh sách tiếng Anh xếp theo tần suất (google-10000-english).
// Một từ vào bảng khi VÀ CHỈ KHI hôm nay engine (cài đặt mặc định) cho ra
// kết quả KHÁC raw ở boundary — tức đúng tập từ đang bị gõ sai ("his"→hí,
// "off"→of, "class"→clas). Từ nào validator đã restore đúng thì không cần.
//
// PROTECT LIST — từ tiếng Việt mà chuỗi phím raw TRÙNG từ tiếng Anh và
// KHÔNG có cách gõ thay thế (sẽ=sex, ơn=own, tên=teen…): tiếng Việt thắng,
// loại khỏi bảng. Người gõ tiếng Anh chấp nhận miss các từ này.
//
// Chạy:  swift run gen-english <wordlist.txt> <maxWords> ../Sources/TelexCore/EnglishCollisions.swift
import Foundation
import TelexCore

/// Từ Việt phổ biến bị trùng phím với English — không bao giờ steal.
/// (raw English → từ Việt bị mất nếu restore)
let protected: Set<String> = [
    "á",    // as
    "cả",   // car
    "sẽ",   // sex
    "bên",  // been
    "ơn",   // own   (cảm ơn — ơ chỉ gõ được bằng ow)
    "tên",  // teen
    "tô",   // too
    "ít",   // its
    "lơ",   // low   (làm lơ)
    "nơ",   // now
    "hơ",   // how
    "tê",   // tee
    "rôm",  // room  (rôm rả)
    "bõ",   // box   (bõ công)
    "ải",   // air
    "bả",   // bar
    "bể",   // beer
    "bú",   // bus
    "lê",   // lee   (quả lê, họ Lê)
    "mã",   // max   (mã số)
    "môn",  // moon  (môn học)
    "rơ",   // row   (chơi rơ)
    "đi",   // did   (user 2026-07-22: free-marking did→đi thắng English "did")
    "thêm", // theme (cùng đợt: theme→thêm)
    // Đợt audit 2026-07-23 (user báo thus→thus): raw tiếng Anh trùng ĐÚNG cách
    // gõ telex chuẩn của từ Việt phổ biến → tiếng Việt thắng.
    "thú",  // thus
    "quên", // queen
    "sóng", // songs
    "chả",  // char
    "chải", // chair
    "hải",  // hair  (tên riêng Hải, hải sản)
    "lén",  // lens
    "hít",  // hits  (hít thở)
    "sét",  // sets  (sấm sét)
    "tít",  // tits  (xa tít)
    "bốt",  // boots (giày bốt)
    "lót",  // lots, lost (lót đường)
    // Chính sách 2026-07-23 (user): collision THẬT — chính tả tiếng Anh trùng
    // đúng thứ tự telex chuẩn của một TỪ VIỆT THẬT — thì tiếng Việt luôn thắng,
    // kể cả với từ tiếng Anh cực phổ biến (this, his, is, of...).
    "hí",   // his
    "thí",  // this  (thí dụ, thí nghiệm)
    "há",   // has   (há miệng)
    "í",    // is    (í ới)
    "ì",    // if    (ì ạch)
    "ò",    // of    (ò ó o)
    "ú",    // us    (mập ú, ú òa)
    "lé",   // les   (mắt lé)
    "gá",   // gas   (gá lắp)
    "nỏ",   // nor   (cái nỏ)
    "dáy",  // days  (dơ dáy)
    "mĩ",   // mix   (mĩ thuật — biến thể của mỹ)
    "típ",  // tips  (tiền típ)
    "trê",  // tree  (cá trê)
    "rún",  // runs  (rún — phương ngữ Nam)
    "ươn",  // won   (cá ươn)
    "sên",  // seen  (ốc sên)
    "sỉ",   // sir   (mua sỉ)
    "sĩ",   // six   (bác sĩ)
    "tã",   // tax
    "úp",   // ups   (úp mở)
    "rẽ",   // res   (rẽ trái)
    // Đợt corpus-from-suite 2026-07-26 (minLen 5): từ Anh ≥5 chữ trùng đúng telex
    // của một từ Việt phổ biến.
    "ướt",  // worst (ướt át)
    "lẩu",  // laura (nồi lẩu)
    "lít",  // list  (lít nước — phiên âm mượn litre; 2026-09-10)
]

/// Rác viết tắt trong corpus web (không phải từ tiếng Anh thật) — vào bảng sẽ
/// nuốt mất cách gõ tiếng Việt (sw = sư!). Từ 2 chữ chỉ nhận whitelist.
let junk: Set<String> = ["aa", "aaa", "ar", "ee", "es", "las", "los", "der",
    "des", "mar", "os", "res", "ref", "rw", "sw", "nw", "usr", "var", "wa",
    "wi", "www", "est", "ie", "il", "ny", "ok"]
let twoLetterWhitelist: Set<String> = ["of", "if", "is", "us", "or"]

/// Từ tiếng Anh phổ biến NGOÀI top-maxWords vẫn đáng cover (chủ yếu lớp
/// double-letter bị cancel ăn mất một chữ). Đuôi 4000-10000 của corpus là
/// bãi mìn từ Việt (cos=có, gif=gì, mas=má, cow=cơ, zoo=zô…) nên KHÔNG quét
/// tự động — chỉ nhận bổ sung tay, và vẫn đi qua đủ engine-check + protect.
let extraEnglish = ["mess", "boss", "kiss", "chess", "bless", "gross",
                    "grass", "brass", "cliff", "moss", "hiss", "fuss",
                    // Đợt 2026-07-26 (suite regression): từ Anh THẬT còn miss sau khi
                    // sửa nhóm tone-cancel — chọn tay, bỏ hết viết tắt/tên riêng
                    // (ross, usps, ieee, nginx…) và các từ trùng tiếng Việt thật
                    // (worst=ướt, won=ươn, zoo=zô).
                    "bias", "boats", "busy", "buys", "charms", "doom", "dose", "err",
                    "ghost", "gore", "guns", "hose", "mask", "nose", "pairs", "pays",
                    "peers", "pens", "pins", "piss", "poems", "pose", "puts", "sass",
                    "sees", "tariff", "thongs", "tons", "trips", "troops", "turns", "wax"]

// Corpus BỔ SUNG (tuỳ chọn, arg 4 + độ dài tối thiểu ở arg 5): danh sách từ tiếng
// Anh khác — hiện dùng cột input của bucket `restore_raw` trong telex_test_suite.csv.
// CHẶN ĐỘ DÀI: từ ngắn là bãi mìn tiếng Việt (cos=có, gif=gì, pas=pá, max=mã), còn
// từ ≥6 chữ hầu như không trùng đúng chuỗi telex của một từ Việt phổ biến.
// Vẫn đi qua đủ engine-check + junk + protect như mọi từ khác.
let args = CommandLine.arguments
guard args.count >= 4,
      let content = try? String(contentsOfFile: args[1], encoding: .utf8),
      let maxWords = Int(args[2]) else {
    FileHandle.standardError.write("usage: gen-english <wordlist> <maxWords> <out.swift>\n".data(using: .utf8)!)
    exit(1)
}

func commitDefault(_ word: String) -> String {
    var e = TelexEngine()
    e.freeMarking = true          // app defaults (1.3.x)
    e.englishWordRestore = false  // đo hành vi validator-thuần, bảng không tự soi mình
    for ch in word { _ = e.feed(ch) }
    return e.commitText(autoRestore: true)
}

nonisolated(unsafe) var kept: [String] = []
nonisolated(unsafe) var excluded: [(String, String)] = []
nonisolated(unsafe) var seen = Set<String>()
@MainActor func consider(_ w: String) {
    guard !seen.contains(w) else { return }
    seen.insert(w)
    let out = commitDefault(w)
    guard out != w else { return }
    if junk.contains(w) { return }
    if w.count == 2, !twoLetterWhitelist.contains(w) { return }
    if protected.contains(out) { excluded.append((w, out)); return }
    kept.append(w)
}
var n = 0
for line in content.split(separator: "\n") {
    if n >= maxWords { break }
    let w = line.trimmingCharacters(in: .whitespaces).lowercased()
    guard w.count >= 2, w.count <= 12, w.allSatisfy({ $0.isASCII && $0.isLetter }) else { continue }
    n += 1
    consider(w)
}
for w in extraEnglish { consider(w) }
if args.count >= 6, let extra = try? String(contentsOfFile: args[4], encoding: .utf8),
   let minLen = Int(args[5]) {
    var added = 0
    for line in extra.split(separator: "\n") {
        let w = line.trimmingCharacters(in: .whitespaces).lowercased()
        guard w.count >= minLen, w.count <= 12, w.allSatisfy({ $0.isASCII && $0.isLetter }) else { continue }
        let before = kept.count
        consider(w)
        added += kept.count - before
    }
    print("extra corpus: +\(added) từ (minLen \(minLen))")
}

// MONOTONE: giữ lại mọi từ đã có trong bảng đang ship. `consider` chỉ nhận từ mà
// engine HÔM NAY còn gõ sai với CÀI ĐẶT MẶC ĐỊNH — nhưng một từ được luật mới cứu
// ở mặc định (nhóm tone-cancel 2026-07-26: office/message/current) có thể vẫn cần
// bảng khi người dùng tắt free marking / bật Simple Telex. Rẻ (~vài KB) nên không
// prune; chỉ protect-list mới gỡ được một từ khỏi bảng.
// (Đọc thẳng file output cũ — bảng là `internal` trong TelexCore.)
var inherited = Set<String>()
let keptSet = Set(kept)
/// Rút các từ ra khỏi file output cũ. Nhận CẢ HAI định dạng: bảng literal-mỗi-từ
/// (`"access", "across",` — định dạng cũ, giữ để đọc được file đang ship) và bảng
/// MỘT literal nhiều dòng (định dạng mới). Với định dạng mới chỉ đọc các dòng NẰM
/// TRONG khối `= """ … """` nên token trong code (`var`, `set`…) không lọt vào bảng.
func previousWords(_ text: String) -> [String] {
    func ok(_ s: Substring) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isLowercase && $0.isLetter }
    }
    var out: [String] = []
    var inLiteral = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if inLiteral {
            if t == "\"\"\"" { inLiteral = false; continue }
            for tok in t.split(whereSeparator: { $0 == " " }) where ok(tok) { out.append(String(tok)) }
        } else if t.hasSuffix("= \"\"\"") {
            inLiteral = true
        } else {
            for m in line.split(separator: "\"") where ok(m) { out.append(String(m)) }
        }
    }
    return out
}
if let prev = try? String(contentsOfFile: args[3], encoding: .utf8) {
    for w in previousWords(prev) {
        // KHÔNG dùng `seen` ở đây: `consider` đã nạp cả corpus vào `seen` (kể cả
        // các từ nó loại vì engine hôm nay gõ đúng) — đó chính là những từ cần
        // thừa hưởng. Chỉ chặn trùng lặp trong `kept` và protect-list.
        guard w.count >= 2, !inherited.contains(w), !keptSet.contains(w) else { continue }
        inherited.insert(w)
        let out = commitDefault(w)
        if protected.contains(out) { excluded.append((w, out)); continue }
        kept.append(w)
    }
}
kept.sort()

var src = """
// EnglishCollisions.swift — SINH TỰ ĐỘNG bởi gen-english, ĐỪNG SỬA TAY.
// Từ tiếng Anh phổ biến (top-\(maxWords)) mà Telex mặc định biến thành âm tiết
// Việt hợp lệ (validator không cứu được) — force-restore ở word boundary.
// Bảng là HỢP của lần sinh này với bảng đang ship (xem gen-english: monotone).
// Đã loại các từ mà tiếng Việt thắng (sẽ=sex, ơn=own… — xem gen-english).
// Regenerate:  swift run gen-english google-10000-english.txt \(maxWords) \
//              Sources/TelexCore/EnglishCollisions.swift
enum EnglishCollisions {
    /// Sorted ascii, lowercase. ~\(kept.count) từ, tra Set ở boundary (không trên hot path).
    /// Lưu thành MỘT literal (cách nhau bởi space/newline) rồi split lazily ở lần tra
    /// đầu tiên: 1 string literal thay vì \(kept.count) phần tử literal → nhỏ hơn hàng
    /// chục KB __TEXT/__DATA. Cùng kiểu với SyllableValidator.rimes.
    static let words: Set<String> = {
        var set = Set<String>(minimumCapacity: \(kept.count))
        for token in list.split(whereSeparator: { $0 == " " || $0 == "\\n" }) {
            set.insert(String(token))
        }
        return set
    }()

    private static let list = \"\"\"

"""
for chunk in stride(from: 0, to: kept.count, by: 8) {
    src += "    " + kept[chunk..<min(chunk + 8, kept.count)].joined(separator: " ") + "\n"
}
src += """
    \"\"\"
}
"""
try! src.write(toFile: args[3], atomically: true, encoding: .utf8)
print("scanned \(n)  kept \(kept.count)  protected-out \(excluded.count)")
for (w, o) in excluded { print("  VN wins: \(w) → \(o)") }
