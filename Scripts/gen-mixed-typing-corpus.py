#!/usr/bin/env python3
"""Sinh corpus mô phỏng gõ câu trộn Việt–Anh: TelexCore/Corpus/mixed-typing.tsv.

Đọc bởi `swift run -c release mixed-eval` (TelexCore/Sources/MixedEval) và
`MixedTypingGoldenTests` — xem docs/REGRESSION.md mục "Mô phỏng gõ câu trộn".

Mỗi dòng ra:  <split>\t<nhóm>\t<câu đích>\t<mặt nạ>
  split  val | test — theo hash câu (sha1(câu) % 3 == 0 ⇒ test). TẬP TEST KHOÁ: chỉnh luật
         engine chỉ nhìn val (lệnh in diff từng từ sai chỉ cho val); test chỉ để báo số.
  mặt nạ một ký tự cho mỗi từ (dãy chữ cái liên tiếp, kể cả chữ có dấu) — e = tiếng Anh,
         v = tiếng Việt (gồm viết tắt chat không dấu "ko", "dc").

Nhóm và nguồn (giấy phép ở docs/DATA-SOURCES.md mục "mixed-typing.tsv"):
  vi       câu Việt Tatoeba (CC BY 2.0 FR) — iOS/KeyboardTests/Fixtures/bigram-heldout.txt
           (lấy 1/3 theo hash) + câu chat có dấu tự soạn (chat-cases.txt cột phải, MIT)
  en       câu Anh Tatoeba (CC BY 2.0 FR) — swipe-lang-sentences.txt loại en (lấy 1/2 theo hash)
  mix      câu trộn swipe-lang-sentences.txt loại mix (tự soạn + ghép câu Tatoeba)
  tech     chat công việc/lập trình tự soạn       — TelexCore/Corpus/mixed-typing-handwritten.txt
  collide  câu có từ Anh trùng phím âm tiết Việt   — như trên (+ câu cur± của gen-retro-english-eval.py)
  teen     chat teencode tự soạn                  — như trên

Trong file tự soạn: từ Anh có hậu tố "/e". Dòng KHÔNG có "/e" mà toàn ASCII ⇒ cả câu tiếng Anh
(nhóm collide). Chạy:  python3 Scripts/gen-mixed-typing-corpus.py
"""
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, "iOS", "KeyboardTests", "Fixtures")
CORPUS = os.path.join(ROOT, "TelexCore", "Corpus")
OUT = os.path.join(CORPUS, "mixed-typing.tsv")
HAND = os.path.join(CORPUS, "mixed-typing-handwritten.txt")

WORD = re.compile(r"[^\W\d_]+")          # dãy chữ cái (Unicode) — khớp Character.isLetter phía Swift


def h(s):
    return int(hashlib.sha1(s.encode("utf-8")).hexdigest()[:12], 16)


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip() and not l.startswith("#")]


def tagged(sent, default):
    """Câu có từ Anh "/e" → (câu sạch, mặt nạ). default: 'e' | 'v' cho từ không gắn nhãn."""
    marks = []                      # (start, end) trong câu sạch của các từ gắn /e
    clean = ""
    i = 0
    for m in re.finditer(r"([^\W\d_]+)/e\b", sent):
        clean += sent[i:m.start()]
        start = len(clean)
        clean += m.group(1)
        marks.append((start, len(clean)))
        i = m.end()
    clean += sent[i:]
    if "/e" in clean:
        raise ValueError(f"stray /e: {sent!r}")
    mask = []
    for m in WORD.finditer(clean):
        eng = any(s <= m.start() < e for s, e in marks)
        mask.append("e" if (eng or default == "e") else "v")
        if mask[-1] == "e" and not m.group(0).isascii():
            raise ValueError(f"non-ascii English word {m.group(0)!r} in {sent!r}")
    return clean, "".join(mask)


def main():
    rows = []          # (category, sentence, mask)

    # vi — Tatoeba câu giữ lại (1/3 theo hash cho gọn) + chat có dấu.
    for l in read_lines(os.path.join(FX, "bigram-heldout.txt")):
        if h("vi:" + l) % 3 == 0:
            rows.append(("vi",) + tagged(l, "v"))
    for l in read_lines(os.path.join(FX, "chat-cases.txt")):
        rows.append(("vi",) + tagged(l.split("\t")[1], "v"))

    for l in read_lines(os.path.join(FX, "swipe-lang-sentences.txt")):
        _, kind, sent = l.split("\t")
        if kind == "en":
            if h("en:" + sent) % 2 == 0:
                rows.append(("en",) + tagged(sent, "e"))
        elif kind == "mix":
            rows.append(("mix",) + tagged(sent, "v"))

    for l in read_lines(HAND):
        cat, sent = l.split("\t")
        default = "e" if (cat == "collide" and "/e" not in sent and sent.isascii()) else "v"
        rows.append((cat,) + tagged(sent, default))

    seen, out = set(), []
    for cat, sent, mask in rows:
        if (cat, sent) in seen or not mask:
            continue
        seen.add((cat, sent))
        split = "test" if h(sent) % 3 == 0 else "val"
        out.append(f"{split}\t{cat}\t{sent}\t{mask}")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("# mixed-typing v1 — sinh bởi Scripts/gen-mixed-typing-corpus.py (xem docstring). "
                "<split>\\t<nhóm>\\t<câu>\\t<mặt nạ e/v>. Câu Tatoeba: CC BY 2.0 FR, https://tatoeba.org; "
                "câu tự soạn: MIT. TẬP TEST KHOÁ — chỉ chỉnh trên val.\n")
        f.write("\n".join(out) + "\n")
    cats = {}
    for line in out:
        s, c = line.split("\t")[:2]
        cats.setdefault(c, [0, 0])[s == "test"] += 1
    for c, (v, t) in sorted(cats.items()):
        print(f"{c:8s} val={v:4d} test={t:4d}")
    print(len(out), "lines ->", OUT, f"({os.path.getsize(OUT)} bytes)")


if __name__ == "__main__":
    sys.exit(main())
