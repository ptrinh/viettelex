#!/usr/bin/env python3
"""gen-enlexicon.py — sinh enlexicon.bin: từ điển tiếng Anh có tần suất cho GÕ VUỐT
(vuốt ra từ tiếng Anh xen trong câu tiếng Việt). Chỉ python3 stdlib.

Nguồn (xem docs/DATA-SOURCES.md — giấy phép + ghi công):
  1. Google Books Ngram Corpus v3 (20200217), sách 2010–2019, danh sách đã làm sạch
     của orgtre/google-books-ngram-frequency: 1grams_english.csv +
     1grams_english-fiction.csv (10.000 từ mỗi file). CC BY 3.0.
  2. Bổ sung từ phổ biến KHÔNG có trong sách (google, facebook, website…):
     IlyaSemenov/wikipedia-word-frequency, enwiki-2023-04-13.txt. MIT.
  3. Từ mượn/tên app hay chen trong câu Việt (wifi, login, zalo, shopee…): bảng
     neutralLoanwords + words của TelexCore/EnglishContextWords.swift (dữ liệu của
     repo), luôn có mặt; tần suất lấy từ Wikipedia (không có thì mức thấp mặc định).
  4. SUPPLEMENT bên dưới (từ công nghệ / AI / tài chính): như (3), nằm ngoài TARGET.
Cả hai được ghim theo commit (URL bên dưới) để tái tạo y hệt.

Lọc: chỉ chữ thường a–z, ≥ 2 chữ; bỏ từ nhạy cảm/tục (SensitiveWords.swift của repo
+ danh sách tiếng Anh bên dưới). Phần bổ sung từ Wikipedia thêm điều kiện: ≥ 3 chữ,
KHÔNG trùng dạng không dấu của âm tiết Việt (tran, nguyen, van, le… là tên riêng
tiếng Việt, không phải từ tiếng Anh), không phải số La Mã.

Tần suất 1 byte, CÙNG THANG với vnlexicon.bin (gen-vnlexicon.py: 255·ln(count)/ln(max)
trên OpenSubtitles vi, tổng ≈ 26,4 triệu token, max 711.535): tỉ lệ token r của từ tiếng
Anh quy về số lần "như thể" trong corpus Việt = r·N_VI rồi áp cùng công thức. Hai từ
điển nhờ vậy chấm λ·tần suất trên một thang (điểm ngôn ngữ do decoder cộng riêng).

enlexicon.bin (little-endian):
  0 "VTE1" | 4 count u32 | 8.. count × [len u8][freq u8][len byte ASCII], sort theo từ.

Usage:
  python3 Scripts/gen-enlexicon.py --download <raw_dir>     # tải dữ liệu thô (không commit)
  python3 Scripts/gen-enlexicon.py <raw_dir>                # sinh 2 file .bin
"""
import csv, math, os, re, struct, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = [os.path.join(ROOT, "iOS/Keyboard/Resources/enlexicon.bin"),
       os.path.join(ROOT, "android/app/src/main/assets/enlexicon.bin")]

GB = "https://raw.githubusercontent.com/orgtre/google-books-ngram-frequency/6a72a4d96a2c36717479e9e9bf4e24260b3dbdae/ngrams/"
WIKI = "https://raw.githubusercontent.com/IlyaSemenov/wikipedia-word-frequency/798ea9062d6e5aed1fa87deeeda1cd99d5b37903/results/"
FILES = {"1grams_english.csv": GB, "1grams_english-fiction.csv": GB, "enwiki-2023-04-13.txt": WIKI}

TARGET = 20000          # tổng số từ
WIKI_MAX_RANK = 50000   # chỉ bổ sung từ trong top-50k Wikipedia
# Thang: số của hermitdave 2018/vi_50k. vnlexicon.bin thật ra dựng từ bản 2016 (gen-vnlexicon.py
# REF_TOTAL/REF_MAX = 17.011.917 / 479.988) ⇒ từ tiếng Anh cao hơn ~5 byte so với "cùng thang" thật.
# Ngưỡng Anh/Việt (TypoFix tiếng Anh, vuốt tiếng Anh, prefersEnglish) đã chỉnh trên thang NÀY; đo
# 18/10/2026 đổi sang số 2016: DEV TypoFix tiếng Anh R 35,4 → 34,5 %, tiếng Việt P 97,3 → 96,8 % ⇒ GIỮ.
N_VI, CMAX_VI = 26438203, 711535

# Tục/xúc phạm/tình dục thô tiếng Anh — không vuốt ra (người dùng vẫn gõ chạm được).
BLOCK = set("""
fuck fucks fucked fucker fuckers fucking motherfucker shit shits shitty bullshit
bitch bitches bastard bastards asshole assholes ass arse cunt cunts cock cocks dick
dicks pussy pussies whore whores slut sluts dildo porn porno pornography penis
vagina anal anus boobs boob tits titties nipple nipples horny orgasm cum semen
rape raped rapist rapists nigger niggers nigga negro faggot faggots fag fags dyke
retard retarded retards tranny spic chink kike gook wetback cracker crackers
damn goddamn crap wanker twat bollocks prick pricks jerkoff blowjob handjob
masturbate masturbation erection ejaculation incest pedophile paedophile
""".split())

# Bổ sung từ mượn công nghệ / AI / tài chính (Phil 18/10/2026) — như từ mượn của repo: luôn có mặt, tần suất
# Wikipedia (không có ⇒ mức thấp mặc định). KHÔNG tính vào TARGET ⇒ bảng chỉ THÊM, không đẩy từ khác ra.
SUPPLEMENT = set("""
chatgpt anthropic openai grok ubuntu deadlock bool boolean llm copilot cursor kubernetes docker javascript
typescript github
crypto blockchain stablecoin defi nft staking etf ipo fintech usdt forex bullish bearish altcoin airdrop
mainnet testnet vc
cloudflare golang vpn agentic debug kotlin npm repo azure
keto detox paracetamol panadol aspirin whey
viettelex telex phil
flex cringe slay rizz simp skincare freeship livestream
""".split())
# ↑ dòng cuối: tiếng lóng / từ thương mại người Việt hay chen (Phil 04/11/2026). "azure" (Microsoft Azure): sinh
# lại đầy đủ 04/11/2026 đẩy nó ra khỏi đuôi Wikipedia (EnglishContextWords thêm ai/json/url…) — giữ ở đây.

ROMAN = set("ii iii iv vi vii viii ix xi xii xiii xiv xv xvi xvii xviii xix xx xxi".split())


def download(raw):
    os.makedirs(raw, exist_ok=True)
    for name, base in FILES.items():
        dst = os.path.join(raw, name)
        if os.path.exists(dst):
            continue
        print("tải", base + name)
        urllib.request.urlretrieve(base + name, dst)


def sensitive_from_repo():
    """Dùng lại SensitiveWords.swift (bộ lọc thanh gợi ý) — lấy các từ ASCII."""
    src = open(os.path.join(ROOT, "iOS/Keyboard/SensitiveWords.swift"), encoding="utf-8").read()
    # chỉ khối `set` (file còn bảng cặp `pairs` — "damn it", "piss off": it/off KHÔNG phải từ tục)
    body = re.search(r"static let set: Set<String> = \[(.*?)\]", src, re.S).group(1)
    return {w for w in re.findall(r'"([^"]+)"', body) if w.isascii() and w.isalpha()}


def vn_folded_forms():
    """Dạng không dấu của 7.184 âm tiết (section folded + offsets của vnlexicon.bin)."""
    b = open(os.path.join(ROOT, "iOS/Keyboard/Resources/vnlexicon.bin"), "rb").read()
    assert b[:4] == b"VNL2"
    count = struct.unpack_from("<I", b, 8)[0]
    sec = [struct.unpack_from("<II", b, 16 + i * 8) for i in range(6)]
    fb, _ = sec[0]
    ob, _ = sec[3]
    offs = struct.unpack_from("<%dI" % (count + 1), b, ob)
    return {b[fb + offs[i]:fb + offs[i + 1]].decode() for i in range(count)}


def repo_english_words():
    """neutralLoanwords + words (+ restoreOnly) của EnglishContextWords.swift."""
    src = open(os.path.join(ROOT, "TelexCore/Sources/TelexCore/EnglishContextWords.swift"),
               encoding="utf-8").read()
    body = re.sub(r"//[^\n]*", " ", src)
    out = set()
    for lit in re.findall(r'"""(.*?)"""', body, re.S):
        out |= set(lit.split())
    for lit in re.findall(r'"([a-z]+)"', body):
        out.add(lit)
    return out


def read_gb(path):
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    total = sum(int(r["freq"]) for r in rows) / float(rows[-1]["cumshare"])
    out = {}
    for r in rows:
        w = r["ngram"].lower()
        out[w] = out.get(w, 0) + int(r["freq"]) / total
    return out


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--download":
        download(sys.argv[2]); return
    if len(sys.argv) != 2:
        print(__doc__); sys.exit(1)
    raw = sys.argv[1]
    ok = re.compile(r"^[a-z]{2,}$")
    block = BLOCK | sensitive_from_repo()
    vn = vn_folded_forms()

    rate = {}
    for name in ("1grams_english.csv", "1grams_english-fiction.csv"):
        for w, r in read_gb(os.path.join(raw, name)).items():
            if ok.match(w) and w not in block:
                rate[w] = max(rate.get(w, 0.0), r)
    n_books = len(rate)

    repo = {w for w in repo_english_words() if ok.match(w) and w not in block and w not in rate}
    supp = {w for w in SUPPLEMENT if ok.match(w) and w not in block and w not in rate and w not in repo}
    cap = TARGET + len(supp)   # phần bổ sung nằm NGOÀI TARGET
    repo |= supp
    repo_counts = {}
    wiki = []
    total = 0
    for i, line in enumerate(open(os.path.join(raw, "enwiki-2023-04-13.txt"), encoding="utf-8")):
        parts = line.split()
        if len(parts) != 2:
            continue
        c = int(parts[1]); total += c
        if parts[0] in repo:
            repo_counts.setdefault(parts[0], c)
        if i < WIKI_MAX_RANK:
            wiki.append((parts[0], c))
    added = 0
    for w, c in wiki:
        if len(rate) + len(repo) >= cap:
            break
        if (w in rate or w in repo or len(w) < 3 or not ok.match(w) or w in block or w in vn
                or w in ROMAN):
            continue
        rate[w] = c / total
        added += 1

    extra = 0
    for w in sorted(repo):
        if w not in rate:
            # không có trong Wikipedia: mức ~ từ hạng 30k (byte ≈ 60)
            rate[w] = max(repo_counts.get(w, 0), 800) / total
            extra += 1

    def byte(r):
        c = r * N_VI
        return 1 if c <= 1 else max(1, min(255, int(255 * math.log(c) / math.log(CMAX_VI))))

    words = sorted(rate)
    blob = bytearray(b"VTE1") + struct.pack("<I", len(words))
    for w in words:
        blob += bytes([len(w), byte(rate[w])]) + w.encode("ascii")
    for p in OUT:
        with open(p, "wb") as f:
            f.write(blob)
    hist = [0] * 6
    for w in words:
        hist[min(5, byte(rate[w]) // 50)] += 1
    coll = sum(1 for w in words if w in vn)
    print(f"{len(words)} từ (sách {n_books}, Wikipedia bổ sung {added}, từ mượn của repo {extra}), trùng dạng Việt {coll}, "
          f"{len(blob)} byte; phân bố byte/50: {hist}")


if __name__ == "__main__":
    main()
