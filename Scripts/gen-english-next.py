#!/usr/bin/env python3
"""gen-english-next.py — bảng "từ kế tiếp" tiếng Anh phổ biến (they → are / were / have) cho ô gợi ý
sau một từ tiếng Anh (#146: không đệm top unigram the/of/and nữa; ô trống thì lấp bằng bảng này,
SAU cặp cá nhân). Chỉ python3 stdlib.

Hai bước:

  1. Đếm (cần dữ liệu thô, KHÔNG commit; chạy với -I vì đọc file tải về):
       mkdir -p <tạm> && cd <tạm> && curl -sO https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2
       python3 -I Scripts/gen-english-next.py --build <tạm>/eng_sentences.tsv.bz2
     → ghi Scripts/english-next.tsv (phần ĐẾM, có số đếm để duyệt tay).
  2. Sinh mã (không cần mạng): english-next.tsv + Scripts/english-next-overrides.tsv (CHỌN TAY) →
       python3 Scripts/gen-english-next.py           → iOS/Keyboard/EnglishNext.swift + android/…/EnglishNext.kt
       python3 Scripts/gen-english-next.py --check   → so với file đã commit; khác ⇒ exit 1

Nguồn: câu tiếng Anh của Tatoeba (https://tatoeba.org), © các thành viên Tatoeba, CC BY 2.0 FR
(https://creativecommons.org/licenses/by/2.0/fr/) — cùng nguồn/giấy phép đã dùng cho vnlm.bin và
Fixtures/swipe-lang-sentences.txt; ghi công ở docs/DATA-SOURCES.md. Bảng chỉ chứa SỐ ĐẾM cặp từ
(dữ kiện thống kê), không chứa câu nào của nguồn.

Quy tắc lọc (--build):
  - Bỏ câu trùng (so chữ thường). Tách câu tại . ! ? ; :, và mọi ký tự không phải chữ / dấu nháy /
    khoảng trắng (dấu phẩy, ngoặc, gạch nối, số…) là CHỖ NGẮT: không đếm cặp băng qua nó.
  - Token có dấu nháy (don't, I'm, Tom's) không đếm và cũng là chỗ ngắt (bàn phím không gợi dạng rút gọn).
  - Chữ thường hoá; chỉ ^[a-z]+$. Từ phải có trong enlexicon.bin (từ điển tiếng Anh của app, ≥ 2 chữ)
    — ngoại lệ "a" và "i" (enlexicon không có từ 1 chữ); "i" hiển thị là "I".
  - Tên riêng: từ mà số lần viết HOA giữa câu (không phải token đầu câu) ≥ số lần viết thường ⇒ bỏ
    (Tom, Mary, Boston, English, Monday…). "I" là ngoại lệ.
  - Từ nhạy cảm: BLOCK của gen-enlexicon.py + khối `set` của iOS/Keyboard/SensitiveWords.swift (runtime
    còn lọc SensitiveWords lần nữa).
  - Từ đầu (head): HEADS từ phổ biến nhất (theo số lần xuất hiện) có ≥ 1 từ theo sau đạt ngưỡng.
  - Từ theo sau: count(h, f) ≥ MIN_PAIR và P(f | h) ≥ MIN_PROB; lấy tối đa PER_HEAD theo số đếm.
  - Nhiễu từ chức năng: một từ theo sau thuộc NOISE (the, a, an, and, of, to) bị thay bằng ứng viên
    không thuộc NOISE xếp sau nó nếu ứng viên đó đạt ≥ NOISE_SWAP × số đếm của nó (ưu tiên từ nội dung
    khi gần ngang nhau; nếu từ chức năng vượt xa thì giữ — đó là sự thật của ngôn ngữ: "of" → "the").

Chọn tay (bước 2, Scripts/english-next-overrides.tsv): áp SAU phần đếm. Mỗi dòng "<từ đầu> TAB <≤3 từ>"
thay HẲN danh sách của từ đầu đó (hoặc thêm từ đầu mới) theo đúng thứ tự ghi; "<từ đầu> TAB -" bỏ từ đầu.
Không có số đếm (không bịa tần suất) — chỉ là thứ tự. Mục đích: tiếng Anh chat / email hằng ngày (thank →
you, good → morning…) thay cho lệch văn sách của Tatoeba (his / himself, "do that", "my father").
Mọi từ chọn tay qua cùng bộ lọc: có trong enlexicon.bin (trừ a / i), không thuộc từ nhạy cảm; sai ⇒ dừng.
"""
import bz2, collections, importlib.util, os, re, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TSV = os.path.join(ROOT, "Scripts", "english-next.tsv")
OVERRIDES = os.path.join(ROOT, "Scripts", "english-next-overrides.tsv")
OUT_SWIFT = os.path.join(ROOT, "iOS", "Keyboard", "EnglishNext.swift")
OUT_KT = os.path.join(ROOT, "android", "keyboard", "src", "main", "kotlin", "com", "viettelex", "keyboard",
                      "EnglishNext.kt")
ENLEX = os.path.join(ROOT, "iOS", "Keyboard", "Resources", "enlexicon.bin")

HEADS = 450        # số từ đầu tối đa
PER_HEAD = 3       # từ theo sau / từ đầu (= số ô gợi ý)
MIN_PAIR = 12      # số đếm cặp tối thiểu
MIN_PROB = 0.02    # P(f | h) tối thiểu
NOISE = {"the", "a", "an", "and", "of", "to"}
NOISE_SWAP = 0.6
SINGLE = {"a", "i"}

SOURCE_NOTE = """\
# english-next.tsv — từ kế tiếp tiếng Anh phổ biến: <từ đầu> TAB <từ theo sau>:<số đếm> …
# SINH bởi Scripts/gen-english-next.py --build (quy tắc lọc ở docstring script); sửa tay được (xoá dòng /
# từ), rồi chạy Scripts/gen-english-next.py để sinh EnglishNext.swift + EnglishNext.kt.
# Nguồn: câu tiếng Anh của Tatoeba (https://tatoeba.org), © các thành viên Tatoeba,
# CC BY 2.0 FR (https://creativecommons.org/licenses/by/2.0/fr/). Đã biến đổi: tách từ, lọc, đếm cặp từ
# liền nhau; chỉ chứa số liệu thống kê, không chứa câu nào. Ghi công: docs/DATA-SOURCES.md.
"""


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def enlexicon():
    b = open(ENLEX, "rb").read()
    assert b[:4] == b"VTE1"
    n = struct.unpack_from("<I", b, 4)[0]
    out, o = set(), 8
    for _ in range(n):
        ln = b[o]
        out.add(b[o + 2:o + 2 + ln].decode("ascii"))
        o += 2 + ln
    return out


def blocked():
    m = load_module("gen_enlexicon", os.path.join(ROOT, "Scripts", "gen-enlexicon.py"))
    return set(m.BLOCK) | m.sensitive_from_repo()


CHUNK = re.compile(r"[.!?;:…]+")
TOKEN = re.compile(r"[A-Za-z']+|[^A-Za-z'\s]")


def build(path):
    lex, block = enlexicon(), blocked()
    seen = set()
    uni = collections.Counter()
    upper_mid, lower = collections.Counter(), collections.Counter()
    pairs = collections.Counter()
    nsent = 0
    with bz2.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            s = parts[2].replace("’", "'").strip()
            key = s.lower()
            if key in seen:
                continue
            seen.add(key)
            nsent += 1
            for chunk in CHUNK.split(s):
                toks = TOKEN.findall(chunk)
                prev, first = None, True
                for t in toks:
                    if not t[0].isalpha() or "'" in t or not t.isascii():
                        prev = None; first = False if t[0].isalpha() else first
                        continue
                    low = t.lower()
                    if not first:
                        if t[0].isupper():
                            upper_mid[low] += 1
                        else:
                            lower[low] += 1
                    first = False
                    uni[low] += 1
                    if prev is not None:
                        pairs[(prev, low)] += 1
                    prev = low

    def ok(w):
        if w in block:
            return False
        if w not in lex and w not in SINGLE:
            return False
        if w != "i" and upper_mid[w] >= lower[w]:
            return False                      # tên riêng (hoặc gần như chỉ đứng đầu câu)
        return True

    by_head = collections.defaultdict(list)
    for (h, f), c in pairs.items():
        if c >= MIN_PAIR and ok(h) and ok(f):
            by_head[h].append((c, f))

    rows = []
    for h, _ in uni.most_common():
        if len(rows) >= HEADS:
            break
        if not ok(h) or h not in by_head:
            continue
        cands = sorted(by_head[h], key=lambda x: (-x[0], x[1]))
        cands = [(c, f) for c, f in cands if c / uni[h] >= MIN_PROB and f != h]
        if not cands:
            continue
        chosen, rest = [], list(cands)
        while rest and len(chosen) < PER_HEAD:
            c, f = rest.pop(0)
            if f in NOISE:
                alt = next((x for x in rest if x[1] not in NOISE and x[0] >= NOISE_SWAP * c), None)
                if alt is not None:
                    rest.remove(alt)
                    rest.insert(0, (c, f))       # từ chức năng vẫn còn cơ hội ở ô sau
                    c, f = alt
            chosen.append((c, f))
        rows.append((h, chosen))

    with open(TSV, "w", encoding="utf-8") as out:
        out.write(SOURCE_NOTE)
        out.write(f"# Bản xuất Tatoeba eng_sentences.tsv.bz2: {nsent} câu (sau khi bỏ trùng). Thứ tự dòng: tần suất từ đầu.\n")
        for h, chosen in rows:
            out.write(h + "\t" + " ".join(f"{f}:{c}" for c, f in chosen) + "\n")
    print(f"{len(rows)} từ đầu, {sum(len(c) for _, c in rows)} cặp → {TSV}")


def parse():
    table = {}
    for n, line in enumerate(open(TSV, encoding="utf-8"), 1):
        if not line.strip() or line.startswith("#"):
            continue
        head, _, rest = line.rstrip("\n").partition("\t")
        assert re.fullmatch(r"[a-z]+", head) and head not in table, f"dòng {n}: {head!r}"
        fs = [x.split(":")[0] for x in rest.split()]
        assert fs and all(re.fullmatch(r"[a-z]+", f) for f in fs), f"dòng {n}"
        table[head] = fs
    lex, block = enlexicon(), blocked()
    valid = lambda w: (w in lex or w in SINGLE) and w not in block
    seen = set()
    for n, line in enumerate(open(OVERRIDES, encoding="utf-8"), 1):
        line = line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        head, _, rest = line.partition("\t")
        fs = rest.split()
        assert re.fullmatch(r"[a-z]+", head) and head not in seen, f"overrides dòng {n}: {head!r}"
        seen.add(head)
        if fs == ["-"]:
            assert head in table, f"overrides dòng {n}: {head!r} không có trong bảng"
            del table[head]
            continue
        assert 1 <= len(fs) <= PER_HEAD and len(set(fs)) == len(fs), f"overrides dòng {n}"
        for w in [head] + fs:
            assert re.fullmatch(r"[a-z]+", w) and valid(w), f"overrides dòng {n}: {w!r} không qua bộ lọc"
        table[head] = fs
    return sorted((h, ["I" if f == "i" else f for f in fs]) for h, fs in table.items())


HEAD = ("GENERATED by Scripts/gen-english-next.py from Scripts/english-next.tsv\n"
        "// + Scripts/english-next-overrides.tsv (chọn tay) — do not edit.")
ATTR = ("Data: Tatoeba English sentences (https://tatoeba.org), (c) Tatoeba contributors, CC BY 2.0 FR —\n"
        "// pair counts only, no sentences. Attribution: docs/DATA-SOURCES.md.")


Q = '"' * 3   # dấu mở/đóng chuỗi nhiều dòng của Swift / Kotlin


def raw_lines(table):
    """Một dòng / từ đầu: "head<TAB>f1 f2 f3". Một hằng chuỗi (không mảng literal): Swift / Kotlin sinh
    mã khởi tạo cho TỪNG phần tử của mảng literal (~140 KB .o Debug cho 900 phần tử) — chuỗi chỉ là
    dữ liệu, tách lười ở lần tra đầu tiên (~450 dòng, vài chục µs)."""
    return [h + "\t" + " ".join(fs) for h, fs in table]


def swift(table):
    body = "\n".join(raw_lines(table))
    return f"""// EnglishNext.swift — {HEAD}
// {ATTR}
// Từ kế tiếp tiếng Anh phổ biến ({len(table)} từ đầu, {sum(len(f) for _, f in table)} cặp) — CHỈ lấp ô trống của "từ kế
// tiếp" sau một từ tiếng Anh, sau cặp cá nhân (#146). Song sinh android EnglishNext.kt.
enum EnglishNext {{
    /// "từ đầu<TAB>từ theo sau…" mỗi dòng; từ đầu chữ thường, đã sắp (so byte); từ theo sau thường gặp nhất trước.
    private static let raw = {Q}
{body}
{Q}
    private static let table: (heads: [String], followers: [String]) = {{
        var h: [String] = [], f: [String] = []
        for line in raw.split(separator: "\\n") {{
            let parts = line.split(separator: "\\t", maxSplits: 1)
            h.append(String(parts[0])); f.append(String(parts[1]))
        }}
        return (h, f)
    }}()
    /// Từ đầu (tìm nhị phân) — nạp lười ở lần dùng đầu tiên.
    static var heads: [String] {{ table.heads }}
    /// Từ theo sau của `heads[i]`, cách nhau dấu cách.
    static var followers: [String] {{ table.followers }}

    /// Từ kế tiếp phổ biến sau `prev` (không phân biệt hoa/thường); không có ⇒ [].
    static func next(after prev: String) -> [String] {{
        let p = prev.lowercased(), hs = table.heads
        var lo = 0, hi = hs.count - 1
        while lo <= hi {{
            let mid = (lo + hi) / 2, h = hs[mid]
            if h == p {{ return table.followers[mid].split(separator: " ").map(String.init) }}
            if h < p {{ lo = mid + 1 }} else {{ hi = mid - 1 }}
        }}
        return []
    }}
}}
"""


def kotlin(table):
    body = "\n".join(raw_lines(table))
    return f"""// EnglishNext.kt — {HEAD}
// {ATTR}
// Song sinh iOS/Keyboard/EnglishNext.swift. Từ kế tiếp tiếng Anh phổ biến ({len(table)} từ đầu,
// {sum(len(f) for _, f in table)} cặp) — CHỈ lấp ô trống của "từ kế tiếp" sau một từ tiếng Anh, sau cặp cá nhân (#146).
package com.viettelex.keyboard

object EnglishNext {{
    /** "từ đầu<TAB>từ theo sau…" mỗi dòng; từ đầu chữ thường, đã sắp; từ theo sau thường gặp nhất trước. */
    private const val RAW = {Q}{body}{Q}

    private class Table(@JvmField val heads: Array<String>, @JvmField val followers: Array<String>)

    /** Tách lười ở lần tra đầu tiên (object khởi tạo khi chạm lần đầu; by lazy an toàn đa luồng). */
    private val table by lazy {{
        val lines = RAW.split('\\n')
        Table(Array(lines.size) {{ lines[it].substringBefore('\t') }}, Array(lines.size) {{ lines[it].substringAfter('\t') }})
    }}

    /** Từ đầu, chữ thường, đã sắp — tìm nhị phân. */
    val heads: Array<String> get() = table.heads

    /** Từ theo sau của heads[i], cách nhau dấu cách, thường gặp nhất trước. */
    val followers: Array<String> get() = table.followers

    /** Từ kế tiếp phổ biến sau [prev] (không phân biệt hoa/thường); không có ⇒ rỗng. */
    fun next(prev: String): List<String> {{
        val t = table
        val i = t.heads.binarySearch(prev.lowercase())
        return if (i >= 0) t.followers[i].split(' ') else emptyList()
    }}
}}
"""


def main():
    if "--build" in sys.argv:
        build(sys.argv[sys.argv.index("--build") + 1])
        return
    table = parse()
    assert [h for h, _ in table] == sorted(h for h, _ in table)
    outs = {OUT_SWIFT: swift(table), OUT_KT: kotlin(table)}
    if "--check" in sys.argv:
        bad = [p for p, s in outs.items() if not os.path.exists(p) or open(p, encoding="utf-8").read() != s]
        if bad:
            print("EnglishNext tables are stale: run Scripts/gen-english-next.py\n  " + "\n  ".join(bad),
                  file=sys.stderr)
            sys.exit(1)
        print(f"EnglishNext OK ({len(table)} từ đầu)")
        return
    for p, s in outs.items():
        with open(p, "w", encoding="utf-8") as f:
            f.write(s)
    print(f"{len(table)} từ đầu, {sum(len(f) for _, f in table)} cặp → {len(outs)} file")


if __name__ == "__main__":
    main()
