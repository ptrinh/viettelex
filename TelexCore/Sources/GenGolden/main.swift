// gen-golden — golden corpus for the Kotlin (Android) port of TelexEngine.
//
// Runs many keystroke scripts through THIS Swift engine and writes the exact
// observable behaviour (every TelexAction, peekCommitText at each boundary, the
// simulated screen, composed/raw, previousWordEnglish) to a gzipped TSV that the
// Android `telexcore` unit test replays and must match 100%.
//
// Workflow: change the Swift engine → `swift run gen-golden` (from TelexCore/) →
// port the change to Kotlin until `./gradlew :telexcore:test` is green.
//
// Line format (tab-separated):
//   flags  ops  trace  screen  composed  raw  prevEnglish
// flags: letters; A autoRestore, F freeMarking, M modernTone, L liveSpellCheck,
//   S simpleTelex, t teencode OFF, Q quickTelex, B bracketVowels, V vniMode,
//   C contextualEnglish, e englishWordRestore OFF, P collisionPrefersVietnamese; "-" = none.
// ops: each char is fed, except  ' ' '.' ','  boundary (commitBoundary + insert char),
//   '<' backspace, '^' reopenLastCommit, '#' reset, '!' resetContext,
//   '%' commitText, '`X' toggle flag X mid-stream, and a leading '@' = seed(rest).
// trace: one token per op joined by '|': P passthrough, N none, R<bs>,<insert>;
//   boundary = <peek>=><action>; '^' = o:<word>|o~ (nil); '%' = c:<text>; toggle = t.
import Foundation
import TelexCore

// MARK: - Paths

let here = URL(fileURLWithPath: #filePath)               // …/TelexCore/Sources/GenGolden/main.swift
let telexCoreDir = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let repoRoot = telexCoreDir.deletingLastPathComponent()
let outURL = repoRoot.appendingPathComponent("android/telexcore/src/test/resources/golden.tsv")

// MARK: - Deterministic PRNG

struct XorShift {
    var s: UInt64
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ pct: Int) -> Bool { int(100) < pct }
}
var rng = XorShift(s: 0x9E37_79B9_7F4A_7C15)

// MARK: - Engine runner

func configure(_ e: inout TelexEngine, _ flags: String) -> Bool {
    var auto = false
    for c in flags {
        switch c {
        case "A": auto = true
        case "F": e.freeMarking = true
        case "M": e.modernTone = true
        case "L": e.liveSpellCheck = true
        case "S": e.simpleTelex = true
        case "t": e.teencode = false
        case "Q": e.quickTelex = true
        case "B": e.bracketVowels = true
        case "V": e.vniMode = true
        case "C": e.contextualEnglish = true
        case "e": e.englishWordRestore = false
        case "P": e.collisionPrefersVietnamese = true
        default: break
        }
    }
    return auto
}

func toggle(_ e: inout TelexEngine, _ c: Character, _ auto: inout Bool) {
    switch c {
    case "A": auto.toggle()
    case "F": e.freeMarking.toggle()
    case "M": e.modernTone.toggle()
    case "L": e.liveSpellCheck.toggle()
    case "S": e.simpleTelex.toggle()
    case "t": e.teencode.toggle()
    case "Q": e.quickTelex.toggle()
    case "B": e.bracketVowels.toggle()
    case "V": e.vniMode.toggle()
    case "C": e.contextualEnglish.toggle()
    case "e": e.englishWordRestore.toggle()
    case "P": e.collisionPrefersVietnamese.toggle()
    default: break
    }
}

func tok(_ a: TelexAction) -> String {
    switch a {
    case .passthrough: return "P"
    case .none: return "N"
    case .replace(let bs, let ins): return "R\(bs),\(ins)"
    }
}

func applyScreen(_ screen: inout [Character], _ a: TelexAction, literal: Character?) {
    switch a {
    case .passthrough:
        if let c = literal { screen.append(c) } else if !screen.isEmpty { screen.removeLast() }
    case .none:
        if literal == nil, !screen.isEmpty { screen.removeLast() }   // ⌫ .none → native delete
    case .replace(let bs, let ins):
        screen.removeLast(min(bs, screen.count))
        screen.append(contentsOf: ins)
    }
}

var lines: [String] = []
var seen = Set<String>()

@MainActor func run(_ flags: String, _ ops: String) {
    let key = flags + "\t" + ops
    guard !ops.isEmpty, seen.insert(key).inserted else { return }
    var e = TelexEngine()
    var auto = configure(&e, flags)
    var trace: [String] = []
    var screen: [Character] = []
    if ops.first == "@" {
        let ok = e.seed(String(ops.dropFirst()))
        trace.append(ok ? "1" : "0")
        screen = Array(e.composed)
    } else {
        let it = Array(ops)
        var i = 0
        while i < it.count {
            let c = it[i]
            switch c {
            case " ", ".", ",":
                let peek = e.peekCommitText(autoRestore: auto)
                let a = e.commitBoundary(autoRestore: auto)
                if case .replace(let bs, let ins) = a {
                    screen.removeLast(min(bs, screen.count)); screen.append(contentsOf: ins)
                }
                screen.append(c)
                trace.append(peek + "=>" + tok(a))
            case "<":
                let a = e.backspace()
                applyScreen(&screen, a, literal: nil)
                trace.append(tok(a))
            case "^":
                if let w = e.reopenLastCommit() {
                    if !screen.isEmpty { screen.removeLast() }   // the boundary char it re-opened over
                    trace.append("o:" + w)
                } else { trace.append("o~") }
            case "#": e.reset(); trace.append("N")
            case "!": e.resetContext(); trace.append("N")
            case "%":
                let t = e.commitText(autoRestore: auto)
                trace.append("c:" + t)
            case "`":
                if i + 1 < it.count { toggle(&e, it[i + 1], &auto); i += 1 }
                trace.append("t")
            default:
                let a = e.feed(c)
                applyScreen(&screen, a, literal: c)
                trace.append(tok(a))
            }
            i += 1
        }
    }
    lines.append([flags.isEmpty ? "-" : flags, ops, trace.joined(separator: "|"), String(screen),
                  e.composed, e.rawKeystrokes, e.previousWordEnglish ? "1" : "0"].joined(separator: "\t"))
}

// MARK: - Word sources

func readText(_ rel: String) -> String {
    (try? String(contentsOf: telexCoreDir.appendingPathComponent(rel), encoding: .utf8)) ?? ""
}

/// Tokens inside every """…""" block of a Swift source section.
func literalWords(_ text: String, after marker: String, before end: String? = nil) -> [String] {
    guard let r = text.range(of: marker) else { return [] }
    var sub = text[r.upperBound...]
    if let end, let er = sub.range(of: end) { sub = sub[..<er.lowerBound] }
    var words: [String] = []
    let parts = sub.components(separatedBy: "\"\"\"")
    var idx = 1
    while idx < parts.count {
        for w in parts[idx].split(whereSeparator: { $0 == " " || $0 == "\n" }) { words.append(String(w)) }
        idx += 2
    }
    return words
}

let collisionSrc = readText("Sources/TelexCore/EnglishCollisions.swift")
let contextSrc = readText("Sources/TelexCore/EnglishContextWords.swift")
let collisionWords = literalWords(collisionSrc, after: "private static let list")
let contextWords = literalWords(contextSrc, after: "private static let wordList", before: "private static let restoreOnlyList")
let restoreOnly = literalWords(contextSrc, after: "private static let restoreOnlyList")
let neutral = literalWords(contextSrc, after: "static let neutralLoanwords", before: "static let maxLength")
let englishLists = collisionWords + contextWords + restoreOnly + neutral
precondition(collisionWords.count > 500 && contextWords.count > 300, "word list extraction failed")

// Inputs of the CSV regression suite (column 2).
var suiteInputs: [String] = []
for line in readText("Tests/TelexCoreTests/Resources/telex_test_suite.csv").split(separator: "\n").dropFirst() {
    let cols = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
    if cols.count >= 2 { suiteInputs.append(String(cols[1])) }
}

// Every short ascii string literal in the Swift test sources (keystroke scripts).
var testLiterals: [String] = []
let testsDir = telexCoreDir.appendingPathComponent("Tests/TelexCoreTests")
let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789[]{} ")
if let files = try? FileManager.default.contentsOfDirectory(atPath: testsDir.path) {
    for f in files.sorted() where f.hasSuffix(".swift") {
        let text = (try? String(contentsOf: testsDir.appendingPathComponent(f), encoding: .utf8)) ?? ""
        for part in text.components(separatedBy: "\"").enumerated() where part.offset % 2 == 1 {
            let s = part.element
            if !s.isEmpty, s.count <= 48, s.allSatisfy({ allowed.contains($0) }) { testLiterals.append(s) }
        }
    }
}

func isKeyWord(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { allowed.contains($0) && $0 != " " } }

// MARK: - Vietnamese syllables → keystrokes

let onsets = ["", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n", "ng", "ngh",
              "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x", "z", "dz", "kr"]
let rimes = """
a ac ach ai am an ang anh ao ap at au ay ak ă ăc ăm ăn ăng ăp ăt ăk â âc âm ân âng âp ât âu ây
e ec em en eng eo ep et ê êch êm ên êng ênh êp êt êu i ich im in inh ip it iu ia ik
iê iêc iêm iên iêng iêp iêt iêu ie o oc oi om on ong op ot oa oac oach oai oam oan oang oanh oao oap oat oay
oă oăc oăm oăn oăng oăt oe oem oen oeo oet oo oong ooc ô ôc ôi ôm ôn ông ôp ôt ơ ơi ơm ơn ơp ơt
u uc ui um un ung up ut ua uâ uân uâng uât uây uê uêch uên uênh uô uôc uôi uôm uôn uông uôt uơ
uy uya uych uyn uynh uyt uyu uyên uyêt ư ưa ưc ưi ưm ưn ưng ưt ưu ưk ươ ươi ươm ươn ương ươp ươt ươu ươc
y yê yêm yên yêng yêt yêu oy
""".split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)

let telexExp: [Character: String] = ["â": "aa", "ă": "aw", "ê": "ee", "ô": "oo", "ơ": "ow", "ư": "uw", "đ": "dd"]
let vniExp: [Character: String] = ["â": "a6", "ê": "e6", "ô": "o6", "ơ": "o7", "ư": "u7", "ă": "a8", "đ": "d9"]
let telexTones = ["", "s", "f", "r", "x", "j"]
let vniTones = ["", "1", "2", "3", "4", "5"]
func expand(_ s: String, _ table: [Character: String]) -> String {
    s.map { table[$0] ?? String($0) }.joined()
}

var syllableKeys: [String] = []       // tone at end
var syllableKeysMid: [String] = []    // tone right after the first vowel
var syllableKeysLateW: [String] = []  // w marks moved to the end
var syllableVNI: [String] = []
for o in onsets {
    for r in rimes {
        let base = expand(o + r, telexExp)
        let vbase = expand(o + r, vniExp)
        for t in 0..<6 {
            syllableKeys.append(base + telexTones[t])
            syllableVNI.append(vbase + vniTones[t])
            if t > 0, let vi = base.firstIndex(where: { "aeiouy".contains($0) }) {
                var s = base
                s.insert(contentsOf: telexTones[t], at: s.index(after: vi))
                syllableKeysMid.append(s)
            }
            if base.contains("w") {
                syllableKeysLateW.append(base.replacingOccurrences(of: "w", with: "") + "w" + telexTones[t])
            }
        }
    }
}

// MARK: - Corpus

let iosDefault = "AFSLCt"
let wordConfigs = [iosDefault, "A", "", "AL", "AFL", "ASL", "AMQ", "ACP", "Ae", "AFSLt", "AB", "ALt"]

var words: [String] = []
words += englishLists
words += suiteInputs.filter(isKeyWord)
words += testLiterals.filter(isKeyWord)
var uniqWords: [String] = []
var seenWord = Set<String>()
for w in words where seenWord.insert(w).inserted { uniqWords.append(w) }

for w in uniqWords {
    for cfg in wordConfigs { run(cfg, w + " ") }
    // case variants + ⌫ from the end + reopen
    run(iosDefault, w.prefix(1).uppercased() + w.dropFirst() + " ")
    run("A", w.uppercased() + " ")
    run(iosDefault, w + "<<" + " ")
    run("AL", w + "<" + " ")
    run("A", w + " ^s ")
    run(iosDefault, w + " <" + "a ")
    run("A", w + "%")
}

// Sentences from test literals (spaces kept) under context-sensitive configs.
for s in testLiterals where s.contains(" ") {
    for cfg in [iosDefault, "AC", "ACL", "A", "ACP", "AFC"] { run(cfg, s + " ") }
}

// Vietnamese syllables.
for k in syllableKeys { for cfg in [iosDefault, "A", "ALM"] { run(cfg, k + " ") } }
for k in syllableKeysMid { run(iosDefault, k + " ") }
for k in syllableKeysLateW { for cfg in [iosDefault, "AF"] { run(cfg, k + " ") } }
for k in syllableVNI { for cfg in ["AVL", "AVFMt"] { run(cfg, k + " ") } }
for (i, k) in syllableKeys.enumerated() where i % 7 == 0 {
    run(iosDefault, k.prefix(1).uppercased() + k.dropFirst() + " ")
    run("AL", k.uppercased() + " ")
    run(iosDefault, k + "<" + " ")
}

// Seeds: whatever the default engine composes for the syllables, re-seeded.
for (i, k) in syllableKeys.enumerated() where i % 3 == 0 {
    var e = TelexEngine()
    for c in k { _ = e.feed(c) }
    let w = e.composed
    for cfg in ["", "M", "V", "Ft"] { run(cfg, "@" + w) }
    run("", "@" + w.uppercased())
}
for w in ["", "toán", "google", "hòa", "hoà", "Việt", "ĐƯỜNG", "a1", "é", "ñ", "thuở", "abcdefghijklmnopq"] {
    run("", "@" + w); run("M", "@" + w); run("V", "@" + w)
}

// Context sentences: random 2–4 word runs mixing English and Vietnamese keys.
let ctxPool = contextWords + restoreOnly + neutral + collisionWords
for _ in 0..<8000 {
    var parts: [String] = []
    for _ in 0..<(2 + rng.int(3)) {
        parts.append(rng.chance(50) ? ctxPool[rng.int(ctxPool.count)] : syllableKeys[rng.int(syllableKeys.count)])
    }
    let cfgs = [iosDefault, "AC", "ACP", "ACL", "ACSt", "AFSLCtP"]
    run(cfgs[rng.int(cfgs.count)], parts.joined(separator: " ") + " ")
}

// Random fuzz: letters (weighted toward Telex keys), case, ⌫, boundaries, reopen,
// reset, mid-word flag flips, digits/brackets, overflow-length words.
let flagLetters = Array("AFMLStQBVCeP")
let heavy = Array("aaeeoouuwwddsfrxjzinghtcmqy")
let light = Array("abcdefghijklmnopqrstuvwxyz")
for n in 0..<40000 {
    var flags = ""
    for f in flagLetters where rng.chance(f == "A" ? 80 : (f == "V" || f == "B" ? 12 : 30)) { flags.append(f) }
    var ops = ""
    let len = n % 50 == 0 ? 30 + rng.int(20) : 1 + rng.int(18)
    for _ in 0..<len {
        let r = rng.int(1000)
        var c: Character
        if r < 520 { c = heavy[rng.int(heavy.count)] }
        else if r < 760 { c = light[rng.int(light.count)] }
        else if r < 830 { c = Character(light[rng.int(light.count)].uppercased()) }
        else if r < 880 { c = "<" }
        else if r < 920 { c = " " }
        else if r < 945 { c = Character(String(rng.int(10))) }
        else if r < 960 { c = Array("[]{}")[rng.int(4)] }
        else if r < 968 { c = "^" }
        else if r < 972 { c = "#" }
        else if r < 975 { c = "!" }
        else if r < 978 { c = "%" }
        else if r < 983 { c = "."; }
        else if r < 990 { ops.append("`"); c = flagLetters[rng.int(flagLetters.count)] }
        else { c = Character(light[rng.int(light.count)].uppercased()) }
        ops.append(c)
    }
    run(flags, ops + " ")
}

// MARK: - Write (gzip)

let body = lines.joined(separator: "\n") + "\n"
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try body.write(to: outURL, atomically: true, encoding: .utf8)
let gz = Process()
gz.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
gz.arguments = ["-9", "-n", "-f", outURL.path]
try gz.run()
gz.waitUntilExit()
print("gen-golden: \(lines.count) cases → \(outURL.path).gz")
