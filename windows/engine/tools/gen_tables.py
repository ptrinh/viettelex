#!/usr/bin/env python3
"""Generate windows/engine/src/generated_tables.hpp from the Swift sources
(single source of truth: TelexCore/Sources/TelexCore).

Emits, as constant arrays that live in .rdata (nothing is built at runtime):
  * the syllable validator's flat class tries (onset/rime, exact/folded, with and
    without the teencode entries) — same ClassTrie semantics as SyllableValidator.swift
  * the "onsets allowing standalone ư" trie (TelexEngine.swift)
  * the English word sets (EnglishCollisions / EnglishContextWords / freeze prefixes) and
    the common-syllable keys, as length-bucketed packed sorted text (WordSet,
    word_set.hpp) probed by binary search (boundary-only, allocation-free).

Run from anywhere:  python3 windows/engine/tools/gen_tables.py
"""
import os, re

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, "..", "..", ".."))
src = os.path.join(root, "TelexCore", "Sources", "TelexCore")
out = os.path.join(here, "..", "src", "generated_tables.hpp")

def read(name):
    with open(os.path.join(src, name), encoding="utf-8") as f:
        return f.read()

sv = read("SyllableValidator.swift")
te = read("TelexEngine.swift")
coll = read("EnglishCollisions.swift")
ctx = read("EnglishContextWords.swift")
frz = read("EnglishFreezePrefixes.swift")
common = read("CommonSyllables.swift")

# ---- letter classes -------------------------------------------------------------
MARKED = "âăêôơưđ"
def char_class(c):
    if "a" <= c <= "z":
        return ord(c) - ord("a")
    i = MARKED.find(c)
    return 26 + i if i >= 0 else None

FOLD = {"ă": "a", "â": "a", "ê": "e", "ô": "o", "ơ": "o", "ư": "u", "đ": "d"}
def fold(w):
    return "".join(FOLD.get(c, c) for c in w)

# ---- rule tables ----------------------------------------------------------------
def quoted_list(text, start):
    i = text.index(start)
    j = text.index("]", i)
    return re.findall(r'"([^"]*)"', text[i:j])

onsets = quoted_list(sv, "static let onsets: Set<String> = [")
m = re.search(r'static let rimes: Set<String> = \{\s*let list = """\n(.*?)"""', sv, re.S)
rimes = [w for w in re.split(r"\s+", m.group(1)) if w]
teen_onsets = re.findall(r'"([^"]*)"', re.search(r"static let teencodeOnsets: Set<String> = \[(.*?)\]", sv).group(1))
teen_rimes = re.findall(r'"([^"]*)"', re.search(r"static let teencodeRimes: Set<String> = \[(.*?)\]", sv).group(1))
standalone_u = quoted_list(te, "private static let onsetsAllowingStandaloneU = ClassTrie([")

ACUTE, GRAVE, DOT = 1, 2, 5
def tone_mask(r):
    if r == "ưk":
        return (1 << GRAVE) | (1 << ACUTE) | (1 << DOT)
    stop = r.endswith(("p", "t", "c", "ch", "k"))
    return ((1 << ACUTE) | (1 << DOT)) if stop else 0b111111

def build_trie(pairs):
    """ClassTrie(init): words with unmappable chars skipped; mask |= max(accept, 1)."""
    STRIDE = 33
    nxt = [-1] * STRIDE
    masks = [0]
    for w, accept in pairs:
        path = []
        ok = True
        for ch in w:
            c = char_class(ch)
            if c is None:
                ok = False; break
            path.append(c)
        if not ok:
            continue
        node = 0
        for c in path:
            slot = node * STRIDE + c
            if nxt[slot] < 0:
                nxt[slot] = len(masks)
                nxt.extend([-1] * STRIDE)
                masks.append(0)
            node = nxt[slot]
        masks[node] |= max(accept, 1)
    return nxt, masks

def uniq(seq):
    seen, res = set(), []
    for x in seq:
        if x not in seen:
            seen.add(x); res.append(x)
    return res

onsets_u = uniq(onsets); rimes_u = uniq(rimes)
onsets_std = [o for o in onsets_u if o not in teen_onsets]
rimes_std = [r for r in rimes_u if r not in teen_rimes]

tries = {
    "kOnsetExact": build_trie([(o, 1) for o in onsets_u]),
    "kRimeExact": build_trie([(r, tone_mask(r)) for r in rimes_u]),
    "kOnsetExactStd": build_trie([(o, 1) for o in onsets_std]),
    "kRimeExactStd": build_trie([(r, tone_mask(r)) for r in rimes_std]),
    "kOnsetFolded": build_trie([(fold(o), 1) for o in onsets_u]),
    "kRimeFolded": build_trie([(fold(r), 1) for r in rimes_u]),
    "kOnsetFoldedStd": build_trie([(fold(o), 1) for o in onsets_std]),
    "kRimeFoldedStd": build_trie([(fold(r), 1) for r in rimes_std]),
    "kStandaloneU": build_trie([(o, 1) for o in standalone_u]),
}

# ---- English word sets ----------------------------------------------------------
freeze_min = re.search(r"static let minLength = (\d+)", frz).group(1)
freeze_max = re.search(r"static let maxLength = (\d+)", frz).group(1)
def blocks(text):
    return re.findall(r'"""\n(.*?)"""', text, re.S)
def words(block):
    return [w for w in re.split(r"[ \n]+", block.strip()) if w]
def section(text, start, end):
    i = text.index(start)
    j = text.index(end, i + len(start)) if end else len(text)
    return text[i:j]

collisions = [w for b in blocks(section(coll, "private static let list", None)) for w in words(b)]
freeze = [w for b in blocks(section(frz, "private static let data", None)) for w in words(b)]
assert freeze and freeze == sorted(freeze)
common_keys = [w for b in blocks(section(common, "private static let data", None)) for w in words(b)]
common_max = int(re.search(r"static let maxKeyLength = (\d+)", common).group(1))
assert common_keys and common_keys == sorted(common_keys)
neutral = [w for b in blocks(section(ctx, "static let neutralLoanwords", "static let maxLength")) for w in words(b)]
ctxwords = [w for b in blocks(section(ctx, "private static let wordList", "private static let restoreOnlyList")) for w in words(b)]
restore = [w for b in blocks(section(ctx, "private static let restoreOnlyList", None)) for w in words(b)]
maxlen = int(re.search(r"static let maxLength = (\d+)", ctx).group(1))
function = [w for b in blocks(section(ctx, "static let functionWords", "static let predecessorGates")) for w in words(b)]
tails = [w for b in blocks(section(ctx, "static let contractionTails", "static let runKeepers")) for w in words(b)]
keepers = [w for b in blocks(section(ctx, "static let runKeepers", "static let codeAcronyms")) for w in words(b)]
acronyms = [w for b in blocks(section(ctx, "static let codeAcronyms", "private static func parseGates")) for w in words(b)]
gates = []
for b in blocks(section(ctx, "static let predecessorGates", "static let contractionTails")):
    for line in b.split("\n"):
        if ":" not in line: continue
        gw, preds = line.split(":", 1)
        gates.append((gw.strip(), words(preds)))
assert gates and len(gates) <= 8
# Retroactive English word classes (EnglishContextWords.retroClassList; bit = index of the
# letter in RetroEnglish.classLetters).
class_letters = re.findall(r'"(\w)"', re.search(r"static let classLetters: \[Character\] = \[(.*?)\]",
                           read("RetroEnglish.swift")).group(1))
retro_bits = {}
for b in blocks(section(ctx, "static let retroClassList", "static let retroClasses")):
    for line in b.split("\n"):
        if ":" not in line: continue
        letter, ws = line.split(":", 1)
        for w in words(ws):
            retro_bits[w] = retro_bits.get(w, 0) | (1 << class_letters.index(letter.strip()))
assert retro_bits and len(class_letters) <= 8
for gw, ps in gates:
    assert re.fullmatch(r"[a-z]+", gw) and ps and all(re.fullmatch(r"[a-z]+", p) for p in ps), (gw, ps)

for name, ws in (("collisions", collisions), ("neutral", neutral), ("ctx", ctxwords), ("restore", restore),
                 ("function", function), ("tails", tails), ("keepers", keepers),
                 ("acronyms", acronyms)):
    assert ws, name
    for w in ws:
        assert re.fullmatch(r"[a-z]+", w), (name, w)

# ---- emit -----------------------------------------------------------------------
def emit_trie(f, name, trie):
    nxt, masks = trie
    f.write(f"// {len(masks)} nodes\n")
    f.write(f"alignas(64) constexpr int16_t {name}Next[{len(nxt)}] = {{\n")
    for i in range(0, len(nxt), 33):
        f.write("  " + ",".join(str(x) for x in nxt[i:i + 33]) + ",\n")
    f.write("};\n")
    f.write(f"constexpr uint8_t {name}Mask[{len(masks)}] = {{")
    f.write(",".join(str(x) for x in masks))
    f.write("};\n")
    f.write(f"constexpr ClassTrie {name}{{{name}Next, {name}Mask}};\n\n")

def emit_words(f, name, ws):
    ws = sorted(set(ws))
    f.write(f"constexpr std::string_view {name}[{len(ws)}] = {{\n")
    line = "  "
    for w in ws:
        item = f'"{w}",'
        if len(line) + len(item) > 96:
            f.write(line.rstrip() + "\n"); line = "  "
        line += item
    f.write(line.rstrip() + "\n};\n\n")

def emit_wordset(f, name, ws):
    # Membership-only sets: packed by length (see word_set.hpp), ~1 byte per letter.
    ws = sorted(set(ws))
    assert ws and all(re.fullmatch(r"[a-z]+", w) for w in ws), name
    maxlen = max(len(w) for w in ws)
    by_len = [[w for w in ws if len(w) == n] for n in range(maxlen + 1)]
    assert max(len(b) for b in by_len) < 65536, name
    f.write(f"// {len(ws)} words\n")
    f.write(f"constexpr const char* const {name}Buckets[{maxlen + 1}] = {{\n")
    for n, b in enumerate(by_len):
        if not b:
            f.write('  "",\n'); continue
        per = max(1, 86 // n)
        lines = ['"' + "".join(b[i:i + per]) + '"' for i in range(0, len(b), per)]
        # One literal per bucket; a multi-line one is parenthesised (not a missing comma).
        f.write("  " + ("(" + "\n   ".join(lines) + ")" if len(lines) > 1 else lines[0]) + ",\n")
    f.write("};\n")
    f.write(f"constexpr uint16_t {name}Counts[{maxlen + 1}] = {{" + ",".join(str(len(b)) for b in by_len) + "};\n")
    f.write(f"constexpr WordSet {name}{{{maxlen}, {name}Buckets, {name}Counts}};\n\n")

assert max(len(m) for _, m in tries.values()) < 32767

with open(out, "w", encoding="utf-8") as f:
    f.write("// GENERATED by windows/engine/tools/gen_tables.py from TelexCore/Sources/TelexCore\n")
    f.write("// (SyllableValidator.swift, TelexEngine.swift, EnglishCollisions.swift,\n")
    f.write("// EnglishContextWords.swift). DO NOT EDIT — edit the Swift source and regenerate.\n")
    f.write("#pragma once\n#include <cstdint>\n#include <string_view>\n#include \"class_trie.hpp\"\n#include \"word_set.hpp\"\n\n")
    f.write("namespace vtx { namespace gen {\n\n")
    for name, trie in tries.items():
        emit_trie(f, name, trie)
    f.write(f"constexpr int kEnglishContextMaxLength = {maxlen};\n\n")
    emit_wordset(f, "kEnglishCollisions", collisions)
    emit_wordset(f, "kEnglishContextWords", ctxwords)
    emit_wordset(f, "kEnglishRestoreOnly", restore)
    emit_wordset(f, "kNeutralLoanwords", neutral)
    emit_wordset(f, "kFunctionWords", function)
    emit_wordset(f, "kContractionTails", tails)
    emit_wordset(f, "kRunKeepers", keepers)
    f.write("// Code acronyms (EnglishContextWords.codeAcronyms): an uppercase run that is not a\n")
    f.write("// name's initials (\"MaxID\" stays whole). Shape rule: also in the lite build.\n")
    emit_wordset(f, "kCodeAcronyms", acronyms)
    f.write("// Eager English restore (EnglishFreezePrefixes.swift): raw prefixes at which an English\n")
    f.write("// word freezes with marks on screen; probed once per word at the freeze moment.\n")
    f.write(f"constexpr int kFreezePrefixMinLength = {freeze_min};\n")
    f.write(f"constexpr int kFreezePrefixMaxLength = {freeze_max};\n")
    emit_wordset(f, "kEnglishFreezePrefixes", freeze)
    f.write("// Common Vietnamese syllables (CommonSyllables.swift): Telex keys, tone last (\"vieetj\").\n")
    f.write("// All-caps acronym rule + Vietnamese typo keep; boundary-only lookups.\n")
    f.write(f"constexpr int kCommonSyllableMaxKey = {common_max};\n")
    emit_wordset(f, "kCommonSyllables", common_keys)
    f.write("// Predecessor gates (EnglishContextWords.predecessorGates): kGateWords[i] restores inside\n")
    f.write("// an English run only right after one of kGatePredecessors<i>. Rule order = bit order.\n")
    for i, (_, ps) in enumerate(gates):
        emit_words(f, f"kGatePredecessors{i}", ps)
    f.write(f"constexpr int kGateCount = {len(gates)};\n")
    f.write("constexpr std::string_view kGateWords[kGateCount] = {" + ", ".join(f'"{gw}"' for gw, _ in gates) + "};\n")
    f.write("struct GatePredecessors { const std::string_view* words; int count; };\n")
    f.write("constexpr GatePredecessors kGatePredecessors[kGateCount] = {"
            + ", ".join(f"{{kGatePredecessors{i}, {len(set(ps))}}}" for i, (_, ps) in enumerate(gates)) + "};\n\n")
    f.write("// Retroactive English (EnglishContextWords.retroClassList): sorted words + class bits.\n")
    rw = sorted(retro_bits)
    emit_words(f, "kRetroClassWords", rw)
    f.write(f"constexpr uint8_t kRetroClassBits[{len(rw)}] = {{" + ",".join(str(retro_bits[w]) for w in rw) + "};\n\n")
    f.write("}} // namespace vtx::gen\n")

print(f"freeze={len(set(freeze))} onsets={len(onsets_u)} rimes={len(rimes_u)} collisions={len(set(collisions))} "
      f"ctx={len(set(ctxwords))} restore={len(set(restore))} neutral={len(set(neutral))} maxlen={maxlen} "
      f"function={len(set(function))} tails={len(set(tails))} gates={gates}")
