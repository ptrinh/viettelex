#!/usr/bin/env python3
"""gen-english-frequency.py — sinh TelexCore/Sources/TelexCore/EnglishFrequency.swift.

Hai bảng tĩnh cho quyết định Anh/Việt ở RANH GIỚI TỪ (không bao giờ trên đường phím):

1. WORDS — từ tiếng Anh (phím thô, chữ thường) + hai điểm tần suất 0–255 TRÊN CÙNG THANG LOG:
     en = tần suất enlexicon.bin, vn = tần suất vnlexicon.bin của âm tiết mà Telex (cấu hình mặc định
     của app, từ đứng một mình) gõ ra từ chính các phím đó (0 = phím không gõ ra âm tiết Việt hợp lệ).
     Hai file chung thang 255·ln(c)/ln(max) quy về cùng corpus tham chiếu (gen-enlexicon.py docstring;
     enlexicon cao hơn "đúng thang" ~5 byte — ngưỡng chỉnh trên eval nên đã tính cả độ lệch đó).
     1 byte ≈ 0,051 nat ⇒ gấp 10 lần ≈ 45 byte.
   Hai loại dòng:
     • TRÙNG (vn > 0): engine hiện GIỮ chữ Việt khi từ đứng một mình ("his"→hí, "last"→lát, "car"→cả).
       Dùng cho luật tần suất (TelexEngine.englishByFrequency).
     • MẠNH (vn = 0, en ≥ STRONG_MIN, ≥ 3 chữ): từ Anh thường gặp mà không đọc ra âm tiết Việt ("very",
       "fast") — một mình nó đủ chốt mạch tiếng Anh cho sửa ngược (RetroEnglish).
2. PAIRS — "phímAnh>khoáTelexÂmTiếtSau": cặp âm tiết Việt (đọc Việt của từ TRÙNG, âm tiết theo sau) hay
   đi liền nhau trong tiếng Việt (vnlm.bin: PMI hai âm tiết ≥ PAIR_PMI, mỗi từ tối đa PAIR_TOP cặp), BỎ
   cặp mà từ sau cũng là từ theo sau tiếng Anh phổ biến của từ đầu (Scripts/english-next.tsv). Dùng để
   LẬT LẠI từ đã đổi sang tiếng Anh khi từ kế tiếp cho thấy câu là tiếng Việt ("His hửng" → "hí hửng").
   Khoá âm tiết sau = phím Telex chữ thường, thanh ở cuối (như CommonSyllables: "hửng" → "huwngr").

Nguồn / giấy phép: enlexicon.bin (Google Books Ngram CC BY 3.0 + wikipedia-word-frequency MIT),
vnlexicon.bin + vnlm.bin (CC BY-SA 4.0, ghi công ở docs/DATA-SOURCES.md mục vnlm.bin), english-next.tsv
(Tatoeba CC BY 2.0 FR). Bảng sinh ra chỉ chứa số liệu thống kê suy ra (như CommonSyllables.swift) —
xem docs/DATA-SOURCES.md mục "EnglishFrequency.swift".

Chạy (cần swift; ~10 giây):  python3 Scripts/gen-english-frequency.py
  rồi  python3 android/telexcore/scripts/gen-wordlists.py && python3 windows/engine/tools/gen_tables.py
"""
import importlib.util, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ENLEX = os.path.join(ROOT, "iOS", "Keyboard", "Resources", "enlexicon.bin")
VNLEX = os.path.join(ROOT, "iOS", "Keyboard", "Resources", "vnlexicon.bin")
VNLM = os.path.join(ROOT, "iOS", "Keyboard", "Resources", "vnlm.bin")
ENEXT = os.path.join(HERE, "english-next.tsv")
OUT = os.path.join(ROOT, "TelexCore", "Sources", "TelexCore", "EnglishFrequency.swift")

STRONG_MIN = 150      # tần suất Anh tối thiểu của từ MẠNH
COLLIDE_MIN = 60      # tần suất Anh tối thiểu của từ TRÙNG được ghi (dưới mức này luật không bao giờ bật)
PAIR_MARGIN = 20      # chỉ sinh cặp cho từ TRÙNG có en − vn ≥ mức này (luật có thể bật với nó)
PAIR_PMI = 24         # PMI tối thiểu (i8, 16 = 1 nat) ⇒ 1,5 nat ≈ gấp 4,5 lần ngẫu nhiên
PAIR_TOP = 32         # tối đa số cặp / từ


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def load_en(path):
    import struct
    b = open(path, "rb").read()
    assert b[:4] == b"VTE1"
    n, = struct.unpack_from("<I", b, 4)
    p, out = 8, {}
    for _ in range(n):
        l, f = b[p], b[p + 1]
        out[b[p + 2:p + 2 + l].decode()] = f
        p += 2 + l
    return out


def readings():
    tc = os.path.join(ROOT, "TelexCore")
    subprocess.run(["swift", "build", "-c", "release", "--product", "gen-english-frequency"],
                   cwd=tc, check=True, stdout=subprocess.DEVNULL)
    r = subprocess.run([os.path.join(tc, ".build", "release", "gen-english-frequency"), ENLEX],
                       check=True, capture_output=True, text=True)
    for line in r.stdout.splitlines():
        w, composed, committed, valid = line.split("\t")
        yield w, composed, committed, valid == "1"


def english_next():
    nxt = {}
    for line in open(ENEXT, encoding="utf-8"):
        if line.startswith("#") or "\t" not in line:
            continue
        a, rest = line.rstrip("\n").split("\t", 1)
        nxt[a] = {x.split(":")[0] for x in rest.split()}
    return nxt


def wrap(tokens, width=92):
    lines, cur = [], ""
    for t in tokens:
        if len(cur) + len(t) + 1 > width:
            lines.append(cur); cur = ""
        cur = (cur + " " + t) if cur else t
    if cur:
        lines.append(cur)
    return "\n".join("    " + l for l in lines)


def main():
    gcs = module("gcs", os.path.join(HERE, "gen-common-syllables.py"))
    lm = module("lm", os.path.join(HERE, "gen-syllable-lm.py"))
    en = load_en(ENLEX)
    vfreq = {}
    for d, f in gcs.load(VNLEX).items():
        k, _ = gcs.telex_key(d)
        if k:
            vfreq[k] = max(vfreq.get(k, 0), f)
    words, collide = {}, {}
    for w, composed, committed, valid in readings():
        f = en.get(w, 0)
        if committed != w and valid:
            k, _ = gcs.telex_key(composed)
            if not k or f < COLLIDE_MIN:
                continue
            v = max(1, vfreq.get(k, 1))
            words[w] = (f, v)
            collide[w] = composed.lower()
        elif committed == w and not valid and f >= STRONG_MIN and len(w) >= 3:
            words[w] = (f, 0)

    # PAIRS từ vnlm.bin
    lex, _ = lm.load_lexicon(VNLEX)
    ids = {}
    for i, d in enumerate(lex):
        ids.setdefault(d, []).append(i)
    v3 = lm.V3(open(VNLM, "rb").read())
    nxt = english_next()
    pairs = set()
    for w, syl in collide.items():
        f, v = words[w]
        if f - v < PAIR_MARGIN:
            continue
        cand = {}
        for p in ids.get(syl, []):
            for j, c in v3.bi_scan(p):
                s = v3.q2(j) + v3.i8("adj", c)
                k, _ = gcs.telex_key(lex[c])
                if not k or s < PAIR_PMI or k in nxt.get(w, ()):
                    continue
                cand[k] = max(cand.get(k, -999), s)
        for k, s in sorted(cand.items(), key=lambda kv: (-kv[1], kv[0]))[:PAIR_TOP]:
            pairs.add(f"{w}>{k}")

    toks = [f"{w}={f:02x}{v:02x}" for w, (f, v) in sorted(words.items())]
    ptoks = sorted(pairs)
    n_coll = sum(1 for f, v in words.values() if v > 0)
    maxw = max(len(w) for w in words)
    maxp = max(len(p) for p in ptoks)
    src = f"""// EnglishFrequency.swift — SINH TỰ ĐỘNG bởi Scripts/gen-english-frequency.py, ĐỪNG SỬA TAY.
// Tần suất tiếng Anh (enlexicon.bin) và tiếng Việt (vnlexicon.bin, âm tiết Telex gõ ra từ cùng phím) trên
// CÙNG thang log 0–255 (gấp 10 lần ≈ 45 byte) + cặp âm tiết Việt hay đi liền (vnlm.bin). Số liệu thống kê
// suy ra từ dữ liệu CC BY-SA 4.0 / CC BY 3.0 / CC BY 2.0 FR — ghi công: docs/DATA-SOURCES.md mục
// "EnglishFrequency.swift". Chỉ tra ở RANH GIỚI từ (luật tần suất, lật lại, từ Anh mạnh của sửa ngược).
// {len(toks)} từ ({n_coll} trùng âm tiết Việt, {len(toks) - n_coll} từ mạnh en ≥ {STRONG_MIN}), {len(ptoks)} cặp.
enum EnglishFrequency {{
    static let strongMin: UInt8 = {STRONG_MIN}
    static let maxWordLength = {maxw}
    static let maxPairLength = {maxp}
    static let wordCount = {len(toks)}
    static let pairCount = {len(ptoks)}

    /// "từ=EEVV" (EE = tần suất Anh, VV = tần suất Việt, hex), sắp theo từ. StaticString: dữ liệu chỉ
    /// đọc trong binary, không heap, không dựng gì lúc chạy.
    private static let words: StaticString = \"\"\"
{wrap(toks)}
    \"\"\"

    /// "từAnh>khoáTelexÂmTiếtSau", sắp xếp.
    private static let pairs: StaticString = \"\"\"
{wrap(ptoks)}
    \"\"\"

    /// (en, vn) của từ `key[0..<n]` (chữ thường a–z), nil nếu không có. Không cấp phát.
    static func scores(_ key: UnsafeBufferPointer<UInt8>, count n: Int) -> (en: UInt8, vn: UInt8)? {{
        guard n >= 1, n <= maxWordLength else {{ return nil }}
        return words.withUTF8Buffer {{ buf in
            guard let s = find(buf, key, n, sep: 0x3D) else {{ return nil }}
            return (hex(buf, s + n + 1), hex(buf, s + n + 3))
        }}
    }}

    /// Cặp `key[0..<n]` (đã gồm dấu ">") có trong bảng PAIRS. Không cấp phát.
    static func hasPair(_ key: UnsafeBufferPointer<UInt8>, count n: Int) -> Bool {{
        guard n >= 3, n <= maxPairLength else {{ return false }}
        return pairs.withUTF8Buffer {{ buf in find(buf, key, n, sep: 0) != nil }}
    }}

    @inline(__always) private static func nib(_ b: UInt8) -> UInt8 {{ b <= 0x39 ? b &- 0x30 : b &- 0x57 }}
    @inline(__always) private static func hex(_ buf: UnsafeBufferPointer<UInt8>, _ i: Int) -> UInt8 {{
        nib(buf[i]) << 4 | nib(buf[i + 1])
    }}

    /// Tìm nhị phân token có phần đầu (tới `sep`, hoặc cả token khi sep = 0) đúng bằng key[0..<n].
    /// Trả về vị trí đầu token.
    private static func find(_ buf: UnsafeBufferPointer<UInt8>, _ key: UnsafeBufferPointer<UInt8>,
                             _ n: Int, sep: UInt8) -> Int? {{
        @inline(__always) func isSpace(_ b: UInt8) -> Bool {{ b == 0x20 || b == 0x0A }}
        var lo = 0, hi = buf.count
        while lo < hi {{
            var s = (lo + hi) / 2
            while s > lo, !isSpace(buf[s - 1]) {{ s -= 1 }}
            if isSpace(buf[s]) {{
                var t = s
                while t < hi, isSpace(buf[t]) {{ t += 1 }}
                if t >= hi {{ hi = s; continue }}
                s = t
            }}
            var e = s
            while e < buf.count, !isSpace(buf[e]) {{ e += 1 }}
            var k = e
            if sep != 0 {{ k = s; while k < e, buf[k] != sep {{ k += 1 }} }}
            var cmp = 0, i = 0
            while i < n, s + i < k {{
                let a = buf[s + i], b = key[i]
                if a != b {{ cmp = a < b ? -1 : 1; break }}
                i += 1
            }}
            if cmp == 0 {{
                let tl = k - s
                if tl == n {{ return s }}
                cmp = tl < n ? -1 : 1
            }}
            if cmp < 0 {{ lo = e }} else {{ hi = s }}
        }}
        return nil
    }}
}}
"""
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(src)
    print(f"{len(toks)} từ ({n_coll} trùng), {len(ptoks)} cặp -> {OUT} ({os.path.getsize(OUT)} bytes)")


if __name__ == "__main__":
    sys.exit(main())
