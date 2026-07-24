#!/usr/bin/env python3
"""Chuyển EmojiSuggest.swift dạng dictionary-literal (generated bởi pipeline
research) sang dạng blob binary-search — tiết kiệm ~1MB dirty RAM và bỏ spike
build-dictionary ở phím đầu tiên.

Usage: blobify-emojisuggest.py <EmojiSuggest.dict.swift> <output.swift> <pairs.json>
- pairs.json: toàn bộ (key -> values) sau merge để harness verify đối chiếu.
- Precedence giữ nguyên semantics cũ: table[w] ?? foldedTable[w].
"""
import base64, json, re, struct, sys

src_path, out_path, pairs_path = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(src_path, encoding="utf-8").read()

def extract(name):
    m = re.search(r'let %s: \[String: \[String\]\] = \[(.*?)\n    \]' % name, src, re.S)
    if not m:
        sys.exit(f"không thấy dictionary {name}")
    body = m.group(1)
    entries = {}
    for km, vm in re.findall(r'"((?:[^"\\]|\\.)*)":\s*\[([^\]]*)\]', body):
        key = km.encode().decode("unicode_escape") if "\\" in km else km
        vals = re.findall(r'"((?:[^"\\]|\\.)*)"', vm)
        entries[key] = vals
    return entries

table = extract("table")
folded = extract("foldedTable")
merged = dict(folded)
merged.update(table)          # table thắng khi trùng khóa (?? semantics)
print(f"table={len(table)} folded={len(folded)} merged={len(merged)}")

for k, vs in merged.items():
    for v in vs:
        assert " " not in v, f"emoji chứa space: {k} -> {v!r}"

items = sorted(merged.items(), key=lambda kv: kv[0].encode("utf-8"))
key_blob = b"".join(k.encode("utf-8") for k, _ in items)
val_blob = b"".join(" ".join(vs).encode("utf-8") for _, vs in items)
key_off, val_off = [0], [0]
for k, vs in items:
    key_off.append(key_off[-1] + len(k.encode("utf-8")))
    val_off.append(val_off[-1] + len(" ".join(vs).encode("utf-8")))

def b64_u32(arr):
    return base64.b64encode(b"".join(struct.pack("<I", x) for x in arr)).decode()

def swift_str(b):
    out = []
    for ch in b.decode("utf-8"):
        if ch == "\\": out.append("\\\\")
        elif ch == '"': out.append('\\"')
        elif ch == "\n": out.append("\\n")
        else: out.append(ch)
    return "".join(out)

swift = f'''// EmojiSuggest.swift — GENERATED (blob) bởi Scripts/blobify-emojisuggest.py
// từ bảng dictionary (kid-words + CLDR vi/en + emojilib + hand-patch 💩…).
// KHÔNG sửa tay ngoài quy trình: sửa bảng dict gốc rồi chạy lại script.
// {len(items)} khóa sort theo UTF-8, binary search O(log n); giá trị là chuỗi
// emoji cách nhau bằng space, split lúc tra — không còn Dictionary ~1MB dirty
// RAM + spike build literal ở phím đầu.
import Foundation

enum EmojiSuggest {{
    static func emojis(for word: String) -> [String] {{
        guard !word.isEmpty else {{ return [] }}
        // Dictionary cũ so khóa theo canonical equivalence — NFC hoá để giữ
        // hành vi với input dạng tổ hợp (NFD).
        let w = word.precomposedStringWithCanonicalMapping.lowercased()
        let q = Array(w.utf8)
        var lo = 0, hi = count
        while lo < hi {{
            let mid = (lo + hi) / 2
            if cmp(mid, q) < 0 {{ lo = mid + 1 }} else {{ hi = mid }}
        }}
        guard lo < count, cmp(lo, q) == 0 else {{ return [] }}
        let s = Int(valOff[lo]), e = Int(valOff[lo + 1])
        return String(decoding: valBlob[s..<e], as: UTF8.self)
            .split(separator: " ").map(String.init)
    }}

    private static func cmp(_ id: Int, _ q: [UInt8]) -> Int {{
        var i = Int(keyOff[id])
        let end = Int(keyOff[id + 1])
        var j = 0
        while i < end && j < q.count {{
            if keyBlob[i] != q[j] {{ return keyBlob[i] < q[j] ? -1 : 1 }}
            i += 1; j += 1
        }}
        if i < end {{ return 1 }}         // khóa dài hơn query
        if j < q.count {{ return -1 }}    // khóa ngắn hơn query
        return 0
    }}

    private static let count = {len(items)}
    private static let keyBlob: [UInt8] = Array("{swift_str(key_blob)}".utf8)
    private static let valBlob: [UInt8] = Array("{swift_str(val_blob)}".utf8)
    private static let keyOff: [UInt32] = decodeU32("{b64_u32(key_off)}")
    private static let valOff: [UInt32] = decodeU32("{b64_u32(val_off)}")

    private static func decodeU32(_ b64: String) -> [UInt32] {{
        let data = Data(base64Encoded: b64)!
        return data.withUnsafeBytes {{ raw in
            (0..<(data.count / 4)).map {{
                UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))
            }}
        }}
    }}
}}
'''
open(out_path, "w", encoding="utf-8").write(swift)
json.dump({k: vs for k, vs in items}, open(pairs_path, "w"), ensure_ascii=False)
print(f"keyBlob={len(key_blob)}B valBlob={len(val_blob)}B → {out_path}")
