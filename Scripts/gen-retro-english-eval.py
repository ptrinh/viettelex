#!/usr/bin/env python3
"""Sinh tập đánh giá cho "sửa ngược tiếng Anh" (TelexEngine.retroactiveEnglish).

Ghi iOS/KeyboardTests/Fixtures/retro-english-eval.txt — dùng chung cho 3 port:
  Swift  TelexCore/Tests/TelexCoreTests/RetroEnglishTests.swift (eval + ngưỡng)
  Kotlin android/telexcore/src/test/.../RetroEnglishTest.kt
  C++    windows/engine/tests/retro_tests.cpp

Mỗi dòng: <nhãn>\\t<phím gõ>\\t<mặt nạ>   (dòng '#' = chú thích)
  mặt nạ: một ký tự cho mỗi từ (dãy chữ cái liên tiếp) — e = từ tiếng Anh (đích = phím gõ
  thô), v = từ Việt (đích = bản gõ khi TẮT tính năng: tính năng không được đụng tới nó).
  en   câu tiếng Anh (Tatoeba, CC BY 2.0 FR, qua swipe-lang-sentences.txt) — toàn e
  mix  câu trộn Việt–Anh (swipe-lang-sentences.txt, loại mix; từ Anh "/e")  — e/v theo nhãn
  vi   câu Việt (bigram-heldout.txt + suggest-dev.txt, Tatoeba)          — toàn v
  chat câu chat không dấu (chat-cases.txt, cột trái)                      — toàn v
  cur+ câu Anh tự soạn có từ trùng tiếng Việt (his/car/is/of/its/this…)  — toàn e
  cur- câu Việt tự soạn có từ mượn / từ trùng sát cạnh tiếng Anh; từ Anh
       viết "/e" như mix (mặt nạ e) — mọi từ v phải giữ nguyên
Phím gõ: Telex chuẩn (â=aa ă=aw ê=ee ô=oo ơ=ow ư=uw đ=dd, phím dấu cuối từ). Ký tự không
phải chữ cái là ranh giới từ (dấu cách, dấu câu).

Chạy:  python3 Scripts/gen-retro-english-eval.py
"""
import os, re, unicodedata

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, ".."))
fx = os.path.join(root, "iOS", "KeyboardTests", "Fixtures")
out = os.path.join(fx, "retro-english-eval.txt")

TONE = {"́": "s", "̀": "f", "̉": "r", "̃": "x", "̣": "j"}
MARK = {"̂": None, "̆": "w", "̛": "w"}   # circumflex = double the vowel


def telex_word(w):
    if re.fullmatch(r"[A-Za-z]+", w):
        return w
    keys, tone = [], ""
    for ch in w:
        if ch in "đĐ":
            keys.append("DD" if ch == "Đ" else "dd")
            continue
        d = unicodedata.normalize("NFD", ch)
        base, marks = d[0], d[1:]
        k = base
        for m in marks:
            if m in TONE:
                tone = TONE[m]
            elif m == "̂":
                k = base + base.lower()
            elif m in ("̆", "̛"):
                k = base + "w"
            else:
                raise ValueError(f"mark {m!r} in {w!r}")
        if base.isupper():
            k = k.upper()
        keys.append(k)
    s = "".join(keys) + tone
    if not re.fullmatch(r"[A-Za-z]+", s):
        raise ValueError(w)
    return s


def telex_sentence(s):
    out, cur = [], ""
    for ch in s:
        if ch.isalpha():
            cur += ch
        else:
            if cur:
                out.append(telex_word(cur)); cur = ""
            out.append(ch)
    if cur:
        out.append(telex_word(cur))
    return "".join(out)


def row(label, sent, default):
    """sent: câu gốc, từ Anh có thể mang "/e". Trả về dòng fixture."""
    keys, mask = [], []
    for tok in sent.split(" "):
        eng = tok.endswith("/e") or default == "e"
        tok = tok[:-2] if tok.endswith("/e") else tok
        keys.append(telex_sentence(tok))
        mask.append(("e" if eng else "v") * len(re.findall(r"[^\W\d_]+", tok)))
    return f"{label}\t{' '.join(keys)}\t{''.join(mask)}"


def read_lines(name):
    with open(os.path.join(fx, name), encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip() and not l.startswith("#")]


CUR_POS = """
His car is very fast
His car is in the garage
my car is here now
This list is very long
its time to go home
of course not
Of course I will
As far as I know
If you want to come with us
Or we can go there tomorrow
His box is on the table
His six cats are cute
the max value is ten
His test results are good
Its last page is missing
His best friend is here
This test is very hard
Is this the right way
His list of books is long
This car is not mine
Its roof is red
her car is not here
His cost is too high
This town is very small
His past is a mystery
Her list is on the desk
This box is too heavy
His room is very clean
Its main door is open
This rest area is closed
""".strip().split("\n")

CUR_NEG = """
Mai cả team/e họp
Gửi file/e cho cả nhà
cả team/e meeting/e
cái này á the/e best/e
check/e cả deploy/e build/e
Mình biết ít people/e like/e this/e
làm cả review/e code/e
hôm nay họp cả buổi with/e the/e team/e
em sẽ check/e the/e logs/e
anh ấy bảo ò the/e end/e
có cả the/e best/e of/e both/e
mã code/e is/e wrong/e
thí sinh this/e year/e
ít khi go/e to/e the/e gym/e
sao í the/e deadline/e is/e today/e
đẹp á the/e best/e
cái áo này mã số is/e wrong/e
nhà mình có sĩ quan is/e here/e
cả nhà đi Đà Lạt for/e the/e weekend/e
gửi cho em lít nước is/e enough/e
ok/e cả nhóm join/e the/e call/e nhé
mai họp cả ngày with/e the/e client/e
bạn có biết ò the/e song/e không
mình thích cả the/e beatles/e and/e queen/e
tối nay xem cả game/e of/e thrones/e
bé thích ăn bánh sinh nhật with/e the/e kids/e
nó í, the/e boss/e is/e angry/e
mua cả set/e of/e tools/e
có tét không, the/e test/e is/e hard/e
chị ấy bảo hí the/e show/e is/e fun/e
mình mất cả buổi to/e fix/e this/e bug/e
cả lớp is/e waiting/e
merge/e đi this/e PR/e is/e ready/e
push/e code/e bên this/e repo/e nhé
check/e đi the/e logs/e are/e here/e
commit/e bên this/e branch/e is/e fine/e
test/e thế này the/e build/e is/e green/e
Đi đâu đó, the/e weather/e is/e nice/e
Thế the/e deadline/e is/e when/e
Như thế is/e fine/e
deploy/e đi it/e is/e ready/e
fix/e bug/e đi you/e know/e
""".strip().split("\n")


def main():
    lines = ["# retro-english-eval v1 — sinh bởi Scripts/gen-retro-english-eval.py; xem docstring. "
             "Câu en/vi: Tatoeba (CC BY 2.0 FR, https://tatoeba.org)."]
    for s in CUR_POS:
        lines.append(row("cur+", s, "e"))
    for s in CUR_NEG:
        lines.append(row("cur-", s, "v"))
    for l in read_lines("swipe-lang-sentences.txt"):
        _, kind, sent = l.split("\t")
        if kind in ("en", "mix"):
            lines.append(row(kind, sent, "e" if kind == "en" else "v"))
    for name in ("bigram-heldout.txt", "suggest-dev.txt"):
        for l in read_lines(name):
            lines.append(row("vi", l, "v"))
    for l in read_lines("chat-cases.txt"):
        lines.append(row("chat", l.split("\t")[0], "v"))
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(len(lines) - 1, "lines ->", out)


if __name__ == "__main__":
    main()
