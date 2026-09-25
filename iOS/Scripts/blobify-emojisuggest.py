#!/usr/bin/env python3
"""Chuyển EmojiSuggest.swift dạng dictionary-literal (generated bởi pipeline
research) sang dạng blob binary-search — tiết kiệm ~1MB dirty RAM và bỏ spike
build-dictionary ở phím đầu tiên.

Usage: blobify-emojisuggest.py <EmojiSuggest.dict.swift> <output.swift> <pairs.json>
       blobify-emojisuggest.py --from-blob <EmojiSuggest.swift> <output.swift> <pairs.json>
- pairs.json: toàn bộ (key -> values) sau merge để harness verify đối chiếu.
- Precedence giữ nguyên semantics cũ: table[w] ?? foldedTable[w].
- --from-blob: đọc lại file blob đã generate (bảng dict gốc không nằm trong repo)
  — dùng khi chỉ đổi FORMAT output, dữ liệu giữ nguyên.

Format (25/09/2026, RAM/size diet): blob khóa/giá trị là StaticString đọc thẳng
từ __TEXT (trang sạch, không copy ra heap như Array("…".utf8) cũ); độ dài từng
khóa/giá trị lưu u8 base64 rồi prefix-sum thành offset [UInt16] (blob < 64KB) —
bảng offset trong binary 30KB → ~8KB, heap offset 23KB → 11.6KB.
"""
import base64, json, re, struct, sys

from_blob = sys.argv[1] == "--from-blob"
if from_blob: sys.argv.pop(1)
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

def from_existing_blob():
    """Đọc cả hai format blob cũ (Array+u32 base64) lẫn mới (StaticString+u8)."""
    def unesc(t): return t.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')
    def blob(name):
        m = re.search(r'static let %s(?:: \[UInt8\] = Array\(| = bytes\(StaticString\()"((?:[^"\\]|\\.)*)"' % name, src, re.S)
        if not m: sys.exit(f"không thấy {name}")
        return unesc(m.group(1)).encode("utf-8")
    def offs(name):
        m = re.search(r'static let %s: \[UInt32\] = decodeU32\("([^"]*)"\)' % name, src)
        if m:
            b = base64.b64decode(m.group(1))
            return [struct.unpack_from("<I", b, i * 4)[0] for i in range(len(b) // 4)]
        m = re.search(r'static let %s = offsets\("([^"]*)"\)' % name, src)
        if not m: sys.exit(f"không thấy {name}")
        out = [0]
        for n in base64.b64decode(m.group(1)): out.append(out[-1] + n)
        return out
    kb, vb = blob("keyBlob"), blob("valBlob")
    ko, vo = offs("keyOff"), offs("valOff")
    assert ko[-1] == len(kb) and vo[-1] == len(vb), "blob/offset lệch"
    return {kb[ko[i]:ko[i+1]].decode(): vb[vo[i]:vo[i+1]].decode().split(" ")
            for i in range(len(ko) - 1)}

if from_blob:
    merged = from_existing_blob()
    print(f"from-blob merged={len(merged)}")
else:
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
key_lens = [len(k.encode("utf-8")) for k, _ in items]
val_lens = [len(" ".join(vs).encode("utf-8")) for _, vs in items]
assert max(key_lens) < 256 and max(val_lens) < 256, "độ dài > 255: cần format rộng hơn"
assert len(key_blob) < 65536 and len(val_blob) < 65536, "blob ≥ 64KB: offset [UInt16] không đủ"

def b64_u8(arr):
    return base64.b64encode(bytes(arr)).decode()

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
// emoji cách nhau bằng space, split lúc tra. Blob là StaticString đọc thẳng từ
// __TEXT (không copy ra heap); offset [UInt16] prefix-sum từ độ dài u8.
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
        return String(decoding: UnsafeBufferPointer(rebasing: valBlob[s..<e]), as: UTF8.self)
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
    private static let keyBlob = bytes(StaticString("{swift_str(key_blob)}"))
    private static let valBlob = bytes(StaticString("{swift_str(val_blob)}"))
    private static let keyOff = offsets("{b64_u8(key_lens)}")
    private static let valOff = offsets("{b64_u8(val_lens)}")

    /// String literal bytes in place — clean __TEXT pages, no heap copy.
    private static func bytes(_ s: StaticString) -> UnsafeBufferPointer<UInt8> {{
        UnsafeBufferPointer(start: s.utf8Start, count: s.utf8CodeUnitCount)
    }}

    /// u8 lengths (base64) → prefix-sum offsets, count + 1 entries.
    private static func offsets(_ b64: String) -> [UInt16] {{
        let lens = Data(base64Encoded: b64)!
        var out = [UInt16](repeating: 0, count: lens.count + 1)
        var acc: UInt16 = 0
        for (i, n) in lens.enumerated() {{ acc &+= UInt16(n); out[i + 1] = acc }}
        return out
    }}
}}
'''
open(out_path, "w", encoding="utf-8").write(swift)
json.dump({k: vs for k, vs in items}, open(pairs_path, "w"), ensure_ascii=False)
print(f"keyBlob={len(key_blob)}B valBlob={len(val_blob)}B → {out_path}")
