#!/usr/bin/env python3
"""gen-common-syllables.py — sinh TelexCore/Sources/TelexCore/CommonSyllables.swift.

Bảng âm tiết tiếng Việt THƯỜNG GẶP (có dấu), dùng cho luật "viết tắt toàn chữ HOA"
(TelexEngine.isRareAllCapsAcronym): "NAS" gõ ra "NÁ" — âm tiết hợp lệ nhưng HIẾM ⇒ là
viết tắt, khôi phục phím thô; "VIỆT", "ĐÀ NẴNG", "CÓ" — thường gặp ⇒ giữ tiếng Việt.

Nguồn: tần suất 0–255 của iOS/Keyboard/Resources/vnlexicon.bin (xem docs/DATA-SOURCES.md
mục vnlexicon.bin; chỉ đọc số tần suất, không thêm nguồn mới). Một âm tiết vào bảng khi:
  * có ít nhất một dấu (chữ ASCII trần không bao giờ là kết quả biến đổi), và
  * tần suất ≥ SHORT_MIN nếu ≤ 3 chữ cái, ≥ LONG_MIN nếu ≥ 4 chữ cái (âm tiết dài
    hiếm khi trùng một từ viết tắt, nên chỉ âm tiết thật sự hiếm mới bị coi là viết tắt).

Khoá = phím Telex chữ thường, dấu thanh ở CUỐI (â→aa, ă→aw, ơ→ow, ư→uw, đ→dd, thanh
s f r x j): "việt" → "vieetj", "hòa"/"hoà" → "hoaf" — không phụ thuộc kiểu đặt dấu.
Engine dựng đúng khoá đó từ chữ đã render (base + mark) + thanh.

Chạy:  python3 Scripts/gen-common-syllables.py
(Kotlin/C++ port đọc lại file Swift này qua android/telexcore/scripts/gen-wordlists.py
và windows/engine/tools/gen_tables.py.)
"""
import os, struct, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LEX = os.path.join(ROOT, "iOS", "Keyboard", "Resources", "vnlexicon.bin")
OUT = os.path.join(ROOT, "TelexCore", "Sources", "TelexCore", "CommonSyllables.swift")

SHORT_MIN = 100
LONG_MIN = 20

TONE_KEY = {"́": "s", "̀": "f", "̉": "r", "̃": "x", "̣": "j"}


def load(path):
    data = open(path, "rb").read()
    assert data[:4] == b"VNL2"
    _ver, count, nsec = struct.unpack_from("<III", data, 4)
    secs = [struct.unpack_from("<II", data, 16 + 8 * i) for i in range(nsec)]
    _folded, display, _attr, _offs, doffs, freqs = [data[o:o + n] for o, n in secs]
    doff = struct.unpack_from("<%dI" % (count + 1), doffs)
    best = {}
    for i in range(count):
        d = display[doff[i]:doff[i + 1]].decode("utf-8")
        best[d] = max(best.get(d, 0), freqs[i])
    return best


def telex_key(word):
    """NFC syllable → Telex keys (tone last), or None if not a plain Vietnamese syllable."""
    out, tone, letters = [], "", 0
    for ch in unicodedata.normalize("NFC", word.lower()):
        if ch == "đ":
            out.append("dd"); letters += 1; continue
        d = unicodedata.normalize("NFD", ch)
        base = d[0]
        if not ("a" <= base <= "z"):
            return None, 0
        mark = ""
        for c in d[1:]:
            if c in TONE_KEY:
                if tone:
                    return None, 0
                tone = TONE_KEY[c]
            elif c == "̂":
                mark = base
            elif c in ("̛", "̆"):
                mark = "w"
            else:
                return None, 0
        out.append(base + mark)
        letters += 1
    return "".join(out) + tone, letters


def main():
    freq = load(LEX)
    keys = set()
    for w, f in freq.items():
        if all(ord(c) < 128 for c in w):
            continue
        k, n = telex_key(w)
        if not k:
            continue
        if f >= (SHORT_MIN if n <= 3 else LONG_MIN):
            keys.add(k)
    keys = sorted(keys)
    lines, cur = [], ""
    for k in keys:
        if len(cur) + len(k) + 1 > 92:
            lines.append(cur); cur = ""
        cur = (cur + " " + k) if cur else k
    if cur:
        lines.append(cur)
    body = "\n".join("    " + l for l in lines)
    maxlen = max(len(k) for k in keys)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(f"""// CommonSyllables.swift — SINH TỰ ĐỘNG bởi Scripts/gen-common-syllables.py, ĐỪNG SỬA TAY.
// Âm tiết tiếng Việt THƯỜNG GẶP (có dấu), khoá = phím Telex chữ thường, thanh ở cuối
// ("vieetj", "hoaf"). Dùng cho luật viết tắt toàn chữ HOA (TelexEngine.isRareAllCapsAcronym):
// âm tiết hợp lệ mà KHÔNG có trong bảng ⇒ hiếm ⇒ "NAS" là viết tắt, không phải "NÁ".
// Ngưỡng tần suất vnlexicon.bin: ≥ {SHORT_MIN} (≤ 3 chữ cái), ≥ {LONG_MIN} (≥ 4 chữ cái).
// {len(keys)} khoá. Chỉ tra ở ranh giới của từ TOÀN CHỮ HOA — không bao giờ trên đường phím.
enum CommonSyllables {{
    static let maxKeyLength = {maxlen}
    static let count = {len(keys)}

    /// Sorted, separated by space/newline. StaticString: read-only data, zero heap.
    private static let data: StaticString = \"\"\"
{body}
    \"\"\"

    /// True if `key[0..<n]` (lowercase ascii Telex keys) is in the table. Allocation-free.
    static func contains(_ key: UnsafeMutableBufferPointer<UInt8>, count n: Int) -> Bool {{
        guard n >= 1, n <= maxKeyLength else {{ return false }}
        return data.withUTF8Buffer {{ buf -> Bool in
            @inline(__always) func isSep(_ b: UInt8) -> Bool {{ b == 0x20 || b == 0x0A }}
            var lo = 0, hi = buf.count
            while lo < hi {{
                var s = (lo + hi) / 2
                while s > lo, !isSep(buf[s - 1]) {{ s -= 1 }}
                if isSep(buf[s]) {{
                    var t = s
                    while t < hi, isSep(buf[t]) {{ t += 1 }}
                    if t >= hi {{ hi = s; continue }}
                    s = t
                }}
                var e = s
                while e < buf.count, !isSep(buf[e]) {{ e += 1 }}
                var cmp = 0
                var i = 0
                while i < n, s + i < e {{
                    let k = key[i]
                    let b = buf[s + i]
                    if b != k {{ cmp = b < k ? -1 : 1; break }}
                    i += 1
                }}
                if cmp == 0 {{
                    let tl = e - s
                    if tl == n {{ return true }}
                    cmp = tl < n ? -1 : 1
                }}
                if cmp < 0 {{ lo = e }} else {{ hi = s }}
            }}
            return false
        }}
    }}
}}
""")
    print(f"{len(keys)} keys → {OUT}")


if __name__ == "__main__":
    main()
