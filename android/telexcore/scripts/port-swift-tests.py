#!/usr/bin/env python3
"""Port the literal assertions of TelexCore's Swift XCTests into Kotlin.

Extracts single-line `XCTAssertEqual(helper("keys"...), "expected")` and
`XCTAssertTrue/False(SyllableValidator.isValid…("x"…))` assertions from the Swift
test files, maps each file's private helper to the Kotlin equivalent (same engine
flags + same terminal call), and writes SwiftPortedTests.kt — one Kotlin @Test per
Swift test function. Hand-written expectations, independent of the golden corpus.

Run:  python3 android/telexcore/scripts/port-swift-tests.py
"""
import os, re

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
    "TeencodeTests.swift": {
        "commit": ("commit", [FREE, LIVE]), "screen": ("composed", [FREE, LIVE]),
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

classes = []
total = 0
for fname in sorted(os.listdir(tests)):
    if not fname.endswith(".swift"): continue
    helpers = H.get(fname, {})
    tests_in_file = {}
    order = []
    cur = None
    for line in open(os.path.join(tests, fname)):
        fm = func_re.match(line)
        if fm:
            cur = fm.group(1); continue
        if cur is None: continue
        for m in eq_re.finditer(line):
            neg, helper, keys, extra, member, expected = m.groups()
            if "\\" in keys or "\\" in expected: continue
            name = helper + (member or "")
            if name not in helpers: continue
            kind, cfg = helpers[name]
            args = {}
            for part in [p.strip() for p in extra.split(",") if p.strip()]:
                if ":" in part:
                    a, b = [x.strip() for x in part.split(":")]; args[a] = b
                else: args["_n"] = part
            c = build_cfg(cfg, args)
            if c is None: continue
            e = expr(kind, c, keys, args)
            if e is None: continue
            fn = "assertNotEquals" if neg == "NotEqual" else "assertEquals"
            if cur not in tests_in_file: tests_in_file[cur] = []; order.append(cur)
            tests_in_file[cur].append(f"        {fn}({kstr(expected)}, {e})")
        for m in val_re.finditer(line):
            tf, fn, word, _, tc = m.groups()
            if "\\" in word: continue
            call = f"SyllableValidator.{fn}({kstr(word)}" + (f", teencode = {tc}" if tc else "") + ")"
            if cur not in tests_in_file: tests_in_file[cur] = []; order.append(cur)
            tests_in_file[cur].append(f"        assert{tf}({kstr(fn + ' ' + word)}, {call})")
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
