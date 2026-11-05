#!/usr/bin/env python3
"""Port the literal assertions of TelexCore's Swift XCTests into Kotlin.

Extracts single-line `XCTAssertEqual(helper("keys"...), "expected")` and
`XCTAssertTrue/False(SyllableValidator.isValid…("x"…))` assertions from the Swift
test files, maps each file's private helper to the Kotlin equivalent (same engine
flags + same terminal call), and writes SwiftPortedTests.kt — one Kotlin @Test per
Swift test function. Hand-written expectations, independent of the golden corpus.

A full regeneration must always compile: anything the mapping cannot express is SKIPPED
explicitly (never emitted half-translated) and listed on stdout, grouped by reason —
helpers with no mapping, helper arguments with no config placeholder, non-literal
arguments, multi-line / variable assertions, escapes, apostrophe boundaries. A helper
argument bound to an enclosing `for x in [true, false] {` loop is unrolled (one ported
assertion per value). `-v` also prints each skipped source line.
Then regenerate the C++ table: python3 windows/engine/tools/port_tests.py

Run:  python3 android/telexcore/scripts/port-swift-tests.py [-v]
"""
import os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, "..", "..", ".."))
tests = os.path.join(root, "TelexCore", "Tests", "TelexCoreTests")
out = os.path.join(here, "..", "src", "test", "kotlin", "com", "viettelex", "telexcore", "SwiftPortedTests.kt")

FREE = "freeMarking = true"
LIVE = "liveSpellCheck = true"

# file -> helper -> (kind, cfg statements)
# kinds: composed, commit, backspace, sentenceCtx, sentenceSplit, sentenceToggle, commitRestore
H = {
    "EngineTests.swift": {
        "compose": ("composed", []), "composeFree": ("composed", [FREE]),
        "composeModern": ("composed", ["modernTone = true"]), "composeSpell": ("composed", [LIVE]),
        "composeSimple": ("composed", ["simpleTelex = true"]),
        "composeSimpleFree": ("composed", ["simpleTelex = true", FREE]),
        "backspaceFree": ("backspace", [FREE]), "commitFree": ("commit", [FREE]),
        "commit": ("commit", []), "composeQuick": ("composed", [FREE, "quickTelex = true"]),
    },
    "VNITests.swift": {
        "vni": ("composed", ["vniMode = true"]), "telex": ("composed", []),
        "vniCommit": ("commit", ["vniMode = true", "liveSpellCheck = {spell|false}"]),
        "vniBackspace": ("backspace", ["vniMode = true"]), "telexBackspace": ("backspace", []),
    },
    "VNIHornUURetargetTests.swift": {"vni": ("composed", ["vniMode = true"])},
    "FreeMarkingRimeTests.swift": {"free": ("composed", [FREE])},
    "ToneClearRetoneTests.swift": {
        "vni": ("composed", ["vniMode = true"]),
        "telex.live": ("composed", [LIVE, "contextualEnglish = true"]),
        "telex.commit": ("commit", [LIVE, "contextualEnglish = true"]),
    },
    "ContextEnglishTests.swift": {
        "sentence": ("sentenceCtx", [LIVE, "contextualEnglish = {context}"]),
        "appDefaultSentence": ("sentenceCtx", [FREE, LIVE, "contextualEnglish = true", "collisionPrefersVietnamese = true"]),
    },
    # typed(): space AND apostrophe are boundaries — only the apostrophe-free rows port
    # (sentenceCtx splits on spaces only; see the skip below).
    "ContextEnglishLoanwordTests.swift": {
        "typed": ("sentenceCtx", [LIVE, "contextualEnglish = true", "freeMarking = {app|true}",
                                  "collisionPrefersVietnamese = {app|true}"]),
    },
    "TeencodeTests.swift": {
        # commit(): TeencodeTests' plain helper, or TeencodeToneThenATests' (teencode:, free:).
        "commit": ("commit", ["freeMarking = {free|true}", LIVE, "teencode = {teencode|true}"]),
        "screen": ("composed", [FREE, LIVE]),
        "commitSimple": ("commit", [FREE, LIVE, "simpleTelex = true"]),
        "run": ("commit", [FREE, LIVE]),
        "commitVNI": ("commit", ["vniMode = true", FREE, LIVE]),
    },
    "GonhanhLearningsTests.swift": {
        "commit": ("commit", [FREE]), "commitSimple": ("commit", ["simpleTelex = true", FREE]),
    },
    "EdgeCaseTests.swift": {"compose": ("composed", []), "commit": ("commit", [])},
    "BackspaceTests.swift": {"compose": ("composed", [])},
    "AbbreviationDoublerTests.swift": {"commit": ("commit", [FREE, LIVE])},
    "TeencodeToggleTests.swift": {
        "commit": ("sentenceToggle", [LIVE, "simpleTelex = {simple|false}", "teencode = {teencode}"]),
    },
    "TypingMatrixTests.swift": {
        "compose": ("composed", ["englishWordRestore = false"]),
        "commit": ("commit", ["englishWordRestore = false"]),
    },
    "CollisionPreferenceTests.swift": {
        "sentence": ("sentenceSplit", [LIVE, "contextualEnglish = true", "collisionPrefersVietnamese = {vietnamese}"]),
    },
    "BoundaryTests.swift": {"commitText": ("commitRestore", [])},
    "PostTonedSyllableReproTests.swift": {
        "screen": ("composed", [FREE, LIVE, "teencode = false", "contextualEnglish = true",
                                "collisionPrefersVietnamese = true"]),
        "vni": ("composed", ["vniMode = true", LIVE]),
    },
    "UpperToneBackspaceTests.swift": {
        "bs": ("backspace", [FREE, LIVE]), "bsNoSpell": ("backspace", [FREE]),
        "bsSimple": ("backspace", [LIVE, "simpleTelex = true"]), "screen": ("composed", [FREE, LIVE]),
    },
    "MarkSwapTests.swift": {
        "compose": ("composed", []), "composeFree": ("composed", [FREE]),
        "vni": ("composed", ["vniMode = true"]),
        "commitApp": ("commit", [FREE, LIVE, "teencode = false", "contextualEnglish = true",
                                 "collisionPrefersVietnamese = true"]),
    },
    "CompetitorReviewTests.swift": {
        "commitApp": ("commit", [FREE, LIVE, "teencode = false", "contextualEnglish = true",
                                 "collisionPrefersVietnamese = true"]),
    },
}

LIT = r'"((?:[^"\\]|\\.)*)"'
eq_re = re.compile(r'XCTAssert(Equal|NotEqual)\(\s*(\w+)\(' + LIT + r'((?:\s*,\s*\w+\s*:\s*\w+|\s*,\s*\d+)*)\s*\)(\.\w+)?\s*,\s*' + LIT + r'\s*[,)]')
val_re = re.compile(r'XCTAssert(True|False)\(\s*SyllableValidator\.(isValidSyllable|isValidPrefix)\(' + LIT + r'(\s*,\s*teencode:\s*(true|false))?\s*\)\s*[,)]')
func_re = re.compile(r'^\s*func (test\w*)\(')

def kstr(s):
    return '"' + s.replace("$", "\\$") + '"'

def build_cfg(cfg, args):
    stmts = []
    for c in cfg:
        m = re.search(r"\{(\w+)(?:\|(\w+))?\}", c)
        if m:
            v = args.get(m.group(1), m.group(2))
            if v is None: return None
            c = c[:m.start()] + v + c[m.end():]
        stmts.append(c)
    return "; ".join(stmts)

def expr(kind, cfg, keys, args):
    lam = "{ " + cfg + " }" if cfg else "{}"
    k = kstr(keys)
    if kind == "composed": return f"composeWith({k}) {lam}"
    if kind == "commit": return f"commitWith({k}) {lam}"
    if kind == "backspace": return f"backspaceWith({k}, {args.get('_n', '1')}) {lam}"
    if kind == "sentenceCtx": return f"sentenceCtx({k}) {lam}"
    if kind == "sentenceSplit": return f"sentenceSplit({k}) {lam}"
    if kind == "sentenceToggle": return f"sentenceToggle({k}) {lam}"
    if kind == "commitRestore":
        r = args.get("restore")
        return None if r is None else f"commitWith({k}, autoRestore = {r}) {lam}"
    return None

# `for flag in [true, false] {` around an assertion whose helper argument is `flag`
# (e.g. typed("…", app: app)) is unrolled: one ported assertion per value.
loop_re = re.compile(r'^\s*for (\w+) in \[\s*((?:true|false)(?:\s*,\s*(?:true|false))*)\s*\]\s*\{')
str_re = re.compile(LIT)

def brace_delta(line):
    code = str_re.sub('""', line.split("//", 1)[0])
    return code.count("{") - code.count("}")

def expansions(args, loops):
    """Concrete argument dicts: every non-literal value must name an enclosing Bool loop
    variable (unrolled); anything else is unsupported → ValueError(reason)."""
    combos = [{}]
    for a, v in args.items():
        if a == "_n" or v in ("true", "false") or v.isdigit() or v in combos[0]:
            continue
        vals = next((vs for (var, vs, _) in reversed(loops) if var == v), None)
        if vals is None:
            raise ValueError(f"argument `{a}: {v}` is neither a literal nor a Bool loop variable")
        combos = [dict(c, **{v: x}) for c in combos for x in vals]
    return [{a: c.get(v, v) for a, v in args.items()} for c in combos]

classes = []
total = 0
skipped = []         # (file, test, reason, source line) — assertions in mapped files not ported
unmapped_count = {}  # file → XCTAssert lines in files without a helper mapping
for fname in sorted(os.listdir(tests)):
    if not fname.endswith(".swift"): continue
    helpers = H.get(fname, {})
    tests_in_file = {}
    order = []
    cur = None
    depth = 0
    loops = []          # (var, [values], brace depth inside the loop body)

    def add(test, stmt):
        if test not in tests_in_file: tests_in_file[test] = []; order.append(test)
        tests_in_file[test].append(stmt)

    for line in open(os.path.join(tests, fname)):
        fm = func_re.match(line)
        if fm:
            cur = fm.group(1); loops = []
        depth += brace_delta(line)
        lm = loop_re.match(line)
        if lm:
            loops.append((lm.group(1), [x.strip() for x in lm.group(2).split(",")], depth))
        if fm or cur is None or "XCTAssert" not in line:
            loops = [l for l in loops if l[2] <= depth]
            continue
        ported, reasons = 0, []
        for m in eq_re.finditer(line):
            neg, helper, keys, extra, member, expected = m.groups()
            name = helper + (member or "")
            if name not in helpers:
                reasons.append(f"helper {name}() not mapped"); continue
            if "\\" in keys or "\\" in expected:
                reasons.append("escape sequence in a literal"); continue
            kind, cfg = helpers[name]
            if kind == "sentenceCtx" and "'" in keys:
                reasons.append("apostrophe boundary (sentenceCtx splits on spaces only)"); continue
            args = {}
            for part in [p.strip() for p in extra.split(",") if p.strip()]:
                if ":" in part:
                    a, b = [x.strip() for x in part.split(":")]; args[a] = b
                else: args["_n"] = part
            known = set(re.findall(r"\{(\w+)", " ".join(cfg))) | {"_n", "restore"}
            if unknown := [a for a in args if a not in known]:
                reasons.append(f"{name}(): argument(s) {', '.join(unknown)} not mapped"); continue
            try:
                concrete = expansions(args, loops)
            except ValueError as err:
                reasons.append(str(err)); continue
            for cargs in concrete:
                c = build_cfg(cfg, cargs)
                if c is not None and re.search(r"= (?!(?:true|false)\b)", c):
                    reasons.append(f"{name}(): non-literal flag value ({c})"); continue
                e = None if c is None else expr(kind, c, keys, cargs)
                if e is None:
                    reasons.append(f"{name}(): call shape not supported"); continue
                fn = "assertNotEquals" if neg == "NotEqual" else "assertEquals"
                add(cur, f"        {fn}({kstr(expected)}, {e})"); ported += 1
        for m in val_re.finditer(line):
            tf, fn, word, _, tc = m.groups()
            if "\\" in word:
                reasons.append("escape sequence in a literal"); continue
            call = f"SyllableValidator.{fn}({kstr(word)}" + (f", teencode = {tc}" if tc else "") + ")"
            add(cur, f"        assert{tf}({kstr(fn + ' ' + word)}, {call})"); ported += 1
        if not ported and helpers:
            why = "; ".join(dict.fromkeys(reasons)) or "not a single-line literal assertion"
            skipped.append((fname[:-6], cur, why, line.strip()))
        elif not ported:
            unmapped_count[fname[:-6]] = unmapped_count.get(fname[:-6], 0) + 1
        loops = [l for l in loops if l[2] <= depth]
    if tests_in_file:
        cls = fname[:-6].replace("Tests", "") + "PortedTest"
        body = []
        for t in order:
            body.append(f"    @Test fun {t}() {{\n" + "\n".join(tests_in_file[t]) + "\n    }")
            total += len(tests_in_file[t])
        classes.append(f"/** Ported from TelexCore/Tests/TelexCoreTests/{fname}. */\nclass {cls} {{\n" + "\n\n".join(body) + "\n}\n")

with open(out, "w") as f:
    f.write("// GENERATED by android/telexcore/scripts/port-swift-tests.py from the Swift XCTests.\n")
    f.write("// DO NOT EDIT — regenerate. Helpers live in SwiftPortSupport.kt.\n")
    f.write("package com.viettelex.telexcore\n\n")
    f.write("import org.junit.Assert.assertEquals\nimport org.junit.Assert.assertFalse\n")
    f.write("import org.junit.Assert.assertNotEquals\nimport org.junit.Assert.assertTrue\nimport org.junit.Test\n\n")
    f.write("\n".join(classes))
print(f"{total} assertions in {len(classes)} classes")
if skipped:
    print(f"\nSkipped {len(skipped)} assertion lines in mapped files (-v: show each line):")
    by_reason = {}
    for f_, t, why, src in skipped:
        by_reason.setdefault(why, {}).setdefault(f"{f_}.{t}", []).append(src)
    for why, tests_ in by_reason.items():
        n = sum(len(v) for v in tests_.values())
        print(f"  [{why}] {n} lines in {len(tests_)} tests:")
        for t, srcs in tests_.items():
            print(f"    {t} ({len(srcs)})")
            if "-v" in sys.argv:
                for src in srcs: print(f"        {src[:140]}")
if unmapped_count:
    print(f"\nNot ported — no helper mapping for these files (XCTAssert lines): "
          + ", ".join(f"{f_} ({n})" for f_, n in sorted(unmapped_count.items())))
