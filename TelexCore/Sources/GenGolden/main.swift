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
//   C contextualEnglish, e englishWordRestore OFF, P collisionPrefersVietnamese,
//   E eagerEnglishRestore; "-" = none.
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
        case "E": e.eagerEnglishRestore = true
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
    case "E": e.eagerEnglishRestore.toggle()
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
// Eager English restore (18/10/2026): the shipped configs with E. Kept as EXTRA lines
// (not by changing iosDefault) so the golden diff shows exactly the new behaviour.
let iosEager = "AFSLCtE"
let macEager = "AFLCPtE"
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
    for cfg in [iosEager, macEager] { run(cfg, w + " ") }
    run(macEager, w + "<<<" + " ")
}

// Sentences from test literals (spaces kept) under context-sensitive configs.
for s in testLiterals where s.contains(" ") {
    for cfg in [iosDefault, "AC", "ACL", "A", "ACP", "AFC"] { run(cfg, s + " ") }
}

// Vietnamese syllables.
for k in syllableKeys { for cfg in [iosDefault, "A", "ALM"] { run(cfg, k + " ") } }
for k in syllableKeysMid { run(iosDefault, k + " ") }
for k in syllableKeys { run(macEager, k + " ") }
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
// Run state machine (11/10/2026): content word = candidate, function word / 2 English
// words open the run, "been" predecessor gate, contraction tails neutral, reopen.
for s in ["suggestion been treen ", "file leen ", "commit leen github ", "review beenf ",
          "fix bug is ", "github repo is ", "deploy app is ", "deploy app script is ",
          "push xong merge is ", "it has been ", "I have been there ", "he been ",
          "it has email been ", "I ve been ", "you re is ", "ve is ", "position is ",
          "the position is ", "it has bee ^n ", "fix bu ^g is ", "It Has Been "] {
    for cfg in ["AC", "ACP", "AFLCP", iosDefault] { run(cfg, s) }
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

// Teencode "Dạa" (18/10/2026): tone + extra `a` at the boundary, teencode on vs off ('t').
for w in ["daja", "Daja", "DAJA", "mafa", "hara", "dasa", "quaja", "daa", "maa", "dajau", "dajaa",
          "asa", "sara", "para", "baja", "dajsa", "dafja", "duaja", "ngaxa", "giaja"] {
    for cfg in ["", "t", "A", "At", "AL", "ALt", "AFL", "AFLt", "AFSLC", "AFSLCt", "AV"] {
        run(cfg, w + " ")
    }
    run("AL", w + "%")
    run("AL", w + " ^")
    run("AL", w + " <")
    run("AL", w + "<" + "a ")
    run("ALC", "the " + w + " is ")
}

// Eager English restore fuzz: own PRNG (the stream above stays byte-identical), live
// spell-check + E always on at start, mid-word flips may include E.
var rngE = XorShift(s: 0xE16E_2026_1018_0001)
let flagLettersE = Array("AFMLStQBVCePE")
let englishPool = englishLists + suiteInputs.filter(isKeyWord)
for n in 0..<8000 {
    var flags = "LE"
    for f in flagLetters where f != "L" && rngE.chance(f == "A" ? 90 : (f == "V" || f == "B" ? 8 : 30)) { flags.append(f) }
    var ops = ""
    // Half the cases start from a real English/suite word (prefix), then fuzz.
    if rngE.chance(50), !englishPool.isEmpty {
        let w = englishPool[rngE.int(englishPool.count)]
        ops += String(w.prefix(1 + rngE.int(max(1, w.count))))
    }
    let len = n % 50 == 0 ? 20 + rngE.int(15) : 1 + rngE.int(12)
    for _ in 0..<len {
        let r = rngE.int(1000)
        var c: Character
        if r < 520 { c = heavy[rngE.int(heavy.count)] }
        else if r < 760 { c = light[rngE.int(light.count)] }
        else if r < 820 { c = Character(light[rngE.int(light.count)].uppercased()) }
        else if r < 900 { c = "<" }
        else if r < 940 { c = " " }
        else if r < 955 { c = "^" }
        else if r < 965 { c = "%" }
        else if r < 980 { ops.append("`"); c = flagLettersE[rngE.int(flagLettersE.count)] }
        else { c = "." }
        ops.append(c)
    }
    run(flags, ops + " ")
}

// Initials suffix (issue #138, 30/10/2026): Title-case syllable + uppercase run
// ("PhuwowngTH" → PhươngTH), with ⌫ across the split, lowercase after the run,
// mid-word flips and reopen. Own PRNG so the streams above stay byte-identical.
var rngI = XorShift(s: 0x1381_2026_1030_0001)
let capsPool = Array("ABCDHKLMNPQSTVXJFRWDDGY")
for n in 0..<6000 {
    let k = syllableKeys[rngI.int(syllableKeys.count)]
    var ops = k.prefix(1).uppercased() + k.dropFirst()
    for _ in 0..<(1 + rngI.int(5)) { ops.append(capsPool[rngI.int(capsPool.count)]) }
    let tail = rngI.int(10)
    if tail == 0 { ops += "<" } else if tail == 1 { ops += "<<" } else if tail == 2 { ops += "a" }
    else if tail == 3 { ops += "<" + String(capsPool[rngI.int(capsPool.count)]) }
    else if tail == 4 { ops += " ^" + String(capsPool[rngI.int(capsPool.count)]) }
    else if tail == 5 { ops.append("`"); ops.append(flagLetters[rngI.int(flagLetters.count)]) }
    let cfgs = [iosDefault, "A", "", "AL", "AFL", "ALV", "AFSLCtP", iosEager, macEager]
    run(cfgs[n % cfgs.count], ops + " ")
}
for w in ["PhuwowngTH", "KieenTV", "HungfNV", "LinhPTT", "KieenSV", "NguyeenXJ", "DDinhNV",
          "TraanfTH", "HungfNVJ", "AsJSON", "HasID", "MySQL", "NodeJS", "iOS", "macOS", "PhD"] {
    for cfg in ["", "A", "AL", "ALE", "AFL", iosDefault, macEager] {
        run(cfg, w + " "); run(cfg, w + "<" + " "); run(cfg, w + "<<" + " ")
        run(cfg, w + " ^"); run(cfg, w + "a "); run(cfg, w + "%")
    }
}
for w in ["Phu7o7ngTH", "Hu2ngNV", "Tu1NV"] { for cfg in ["AV", "AVL"] { run(cfg, w + " "); run(cfg, w + "< ") } }

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
