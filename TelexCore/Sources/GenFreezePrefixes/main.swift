// gen-freeze-prefixes — sinh EnglishFreezePrefixes.swift (eager English restore).
//
// Một tiền tố vào bảng khi VÀ CHỈ KHI: gõ một từ tiếng Anh của enlexicon.bin bằng Telex
// (live spell-check bật, eager restore TẮT — tức hành vi lịch sử) thì từ bị ĐÓNG BĂNG
// đúng sau phím thứ r, màn hình lúc đó KHÁC phím thô (có dấu đang hiện: "gôg"), và
// r ≥ minLength. Tiền tố = r phím thô đầu (chữ thường). Engine tra ĐÚNG tiền tố đó ở
// khoảnh khắc đóng băng ⇒ bảng chỉ chứa những gì có thể khớp, nhỏ hơn nhiều so với
// toàn bộ tiền tố của 20k từ.
//
// Hợp các cấu hình hay gặp (bỏ dấu tự do × Telex đơn giản × teencode) — cấu hình nào
// đóng băng ở chỗ khác thì vẫn có tiền tố của nó.
//
// PROTECT: tiền tố trùng phím của tiếng Việt gõ thật / gõ sai phổ biến (xem
// EagerEnglishRestoreTests.testVietnameseTyposNeverEagerRestore) — tiếng Việt thắng.
//
// Chạy (từ TelexCore/):
//   swift run -c release gen-freeze-prefixes ../iOS/Keyboard/Resources/enlexicon.bin \
//       Sources/TelexCore/EnglishFreezePrefixes.swift
import Foundation
import TelexCore

let minLength = 4

/// Tiền tố mà tiếng Việt thắng (điền khi test an toàn VN báo trùng).
let protected: Set<String> = []

let args = CommandLine.arguments
guard args.count >= 3, let blob = FileManager.default.contents(atPath: args[1]) else {
    FileHandle.standardError.write("usage: gen-freeze-prefixes <enlexicon.bin> <out.swift>\n".data(using: .utf8)!)
    exit(1)
}

// enlexicon.bin: "VTE1" + u32 count + count × (len u8, freq u8, ascii bytes), sorted.
let bytes = [UInt8](blob)
guard bytes.count > 8, bytes[0..<4] == [0x56, 0x54, 0x45, 0x31] else {
    FileHandle.standardError.write("not an enlexicon (VTE1) file\n".data(using: .utf8)!)
    exit(1)
}
let total = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
var words: [String] = []
var p = 8
for _ in 0..<total {
    let len = Int(bytes[p]); p += 2
    words.append(String(decoding: bytes[p..<(p + len)], as: UTF8.self))
    p += len
}

struct Config { var free: Bool; var simple: Bool; var teen: Bool }
var configs: [Config] = []
for free in [true, false] { for simple in [false, true] { for teen in [false, true] {
    configs.append(Config(free: free, simple: simple, teen: teen))
} } }

var prefixes = Set<String>()
var perWord = 0
for w in words where w.count >= minLength && w.utf8.allSatisfy({ $0 >= 0x61 && $0 <= 0x7A }) {
    var hit = false
    for c in configs {
        var e = TelexEngine()
        e.liveSpellCheck = true
        e.freeMarking = c.free
        e.simpleTelex = c.simple
        e.teencode = c.teen
        // The engine decides at the freeze key, or at key `minLength` when the word
        // froze earlier ("ưin" → decided at "wind"). Record exactly that raw prefix
        // when the screen there still differs from the raw keys.
        var r = 0
        for ch in w {
            _ = e.feed(ch); r += 1
            guard let at = e.spellCheckFreezeAt else { continue }
            if r < minLength { continue }               // frozen early: wait for key 4
            // at == r − 1: froze at THIS key but kept the tone of the word shown before it
            // ("pẩ"+g, PR #133 freezeKeepsTone) — eager restore is checked first there, so
            // the prefix is still needed ("parag" → "parag", not "pẩg").
            if at == r || at == r - 1 || (at < minLength && r == minLength), e.composed != e.rawKeystrokes {
                let pre = String(w.prefix(r))
                if !protected.contains(pre) { prefixes.insert(pre); hit = true }
            }
            break
        }
    }
    if hit { perWord += 1 }
}

let sorted = prefixes.sorted()
let maxLen = sorted.map(\.count).max() ?? minLength
var lines: [String] = []
var cur = ""
for w in sorted {
    if cur.count + w.count + 1 > 92 { lines.append(cur); cur = "" }
    cur = cur.isEmpty ? w : cur + " " + w
}
if !cur.isEmpty { lines.append(cur) }
let body = lines.map { "    " + $0 }.joined(separator: "\n")

let src = """
// EnglishFreezePrefixes.swift — SINH TỰ ĐỘNG bởi gen-freeze-prefixes, ĐỪNG SỬA TAY.
// Tiền tố phím thô (chữ thường) mà ở đó một từ tiếng Anh của enlexicon.bin bị live
// spell-check ĐÓNG BĂNG khi đang hiện dấu ("goog" → "gôg"). Eager English restore
// (TelexEngine.eagerEnglishRestore) tra bảng ĐÚNG MỘT LẦN mỗi từ, ở khoảnh khắc đóng
// băng — không bao giờ trên đường nóng mỗi phím.
// \(sorted.count) tiền tố từ \(perWord) từ, dài \(minLength)…\(maxLen).
// Regenerate (từ TelexCore/):
//   swift run -c release gen-freeze-prefixes ../iOS/Keyboard/Resources/enlexicon.bin \\
//       Sources/TelexCore/EnglishFreezePrefixes.swift
enum EnglishFreezePrefixes {
    static let minLength = \(minLength)
    static let maxLength = \(maxLen)
    static let count = \(sorted.count)

    /// Sorted, separated by space/newline. A StaticString lives in the binary's
    /// read-only data: zero heap, nothing built at launch; binary search in place.
    private static let data: StaticString = \"\"\"
\(body)
    \"\"\"

    /// True if `raw[0..<n]` (ascii letters, any case) is in the table. Allocation-free.
    static func contains(_ raw: UnsafeBufferPointer<UInt8>, count n: Int) -> Bool {
        guard n >= minLength, n <= maxLength, n <= raw.count else { return false }
        return data.withUTF8Buffer { buf -> Bool in
            @inline(__always) func isSep(_ b: UInt8) -> Bool { b == 0x20 || b == 0x0A }
            var lo = 0, hi = buf.count
            while lo < hi {
                var s = (lo + hi) / 2
                while s > lo, !isSep(buf[s - 1]) { s -= 1 }
                if isSep(buf[s]) {               // landed on a separator run: skip it
                    var t = s
                    while t < hi, isSep(buf[t]) { t += 1 }
                    if t >= hi { hi = s; continue }
                    s = t
                }
                var e = s
                while e < buf.count, !isSep(buf[e]) { e += 1 }
                // Compare token buf[s..<e] with lowercased raw[0..<n].
                var cmp = 0
                var i = 0
                while i < n, s + i < e {
                    var k = raw[i]
                    if k >= 0x41, k <= 0x5A { k |= 0x20 }
                    let b = buf[s + i]
                    if b != k { cmp = b < k ? -1 : 1; break }
                    i += 1
                }
                if cmp == 0 {
                    let tl = e - s
                    if tl == n { return true }
                    cmp = tl < n ? -1 : 1
                }
                if cmp < 0 { lo = e } else { hi = s }
            }
            return false
        }
    }
}

"""
try! src.write(toFile: args[2], atomically: true, encoding: .utf8)
print("\(sorted.count) prefixes from \(perWord) words (of \(words.count)); max len \(maxLen); \(sorted.reduce(0) { $0 + $1.count + 1 }) bytes")
