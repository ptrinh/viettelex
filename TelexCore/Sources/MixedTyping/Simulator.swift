// Simulator.swift — gõ từng phím qua TelexEngine thật, dựng lại văn bản trên màn hình.
//
// Mô phỏng đúng đường in-place của controller macOS (TelexInputController.boundary):
//   • chữ cái → engine.feed, áp TelexAction lên "màn hình";
//   • ký tự khác (cách, số, dấu câu) → nếu đang có từ: commitText(autoRestore:) rồi thay
//     `composed` trên màn hình bằng chữ chốt (auto-restore tắt cạnh ngoặc [ ] { } ( ) như app);
//     từ rỗng → engine.reset(). Sau đó (tự sửa từ phía trước BẬT) áp RetroCorrection đang chờ
//     nếu màn hình khớp `expected` — TRƯỚC khi ký tự ranh giới vào, đúng thứ tự app — rồi in
//     ký tự ranh giới và báo engine.noteBoundaryCharacter;
//   • hết câu = Enter: commit, forgetLastCommit, resetContext (không áp sửa ngược, như app).
// Chế độ tiếng Anh (người gõ tắt bộ gõ): phím đi thẳng ra màn hình, engine không thấy gì;
// bật lại ⇒ engine.reset() + resetContext() (activateServer của app làm vậy).

import Foundation
import TelexCore

public struct SimConfig: Sendable {
    public let name: String
    public let summary: String
    public var freeMarking = true, liveSpellCheck = true, teencode = false
    public var contextualEnglish = true, retroactiveEnglish = true
    public var collisionPrefersVietnamese = true, autoRestore = true, modernTone = false
    /// "Tự sửa từ phía trước" BẬT = tự áp phép sửa ngược. Tắt (mặc định app) = chỉ đề xuất
    /// cạnh con trỏ, người gõ "lười" không bấm Tab ⇒ văn bản không đổi.
    public var retroApply = false

    /// Mặc định của app macOS (AppState.init / EngineFlags, 30/10/2026).
    public static let appDefault = SimConfig(name: "default",
        summary: "mặc định app: ngữ cảnh tiếng Anh BẬT, tự sửa từ phía trước TẮT (chỉ đề xuất)")
    public static let retro: SimConfig = {
        var c = SimConfig(name: "retro", summary: "mặc định + \"Tự sửa từ phía trước\" BẬT (tự áp)")
        c.retroApply = true
        return c
    }()
    public static let noContext: SimConfig = {
        var c = SimConfig(name: "no-context", summary: "\"Quyết định theo ngữ cảnh\" TẮT (không ngữ cảnh, không sửa ngược)")
        c.contextualEnglish = false; c.retroactiveEnglish = false
        return c
    }()
    public static let all = [appDefault, retro, noContext]

    /// Nhóm `teen`: người gõ teencode bật công tắc Teencode (app mặc định tắt).
    func engine(category: String) -> TelexEngine {
        var e = TelexEngine()
        e.freeMarking = freeMarking; e.liveSpellCheck = liveSpellCheck
        e.teencode = teencode || category == "teen"
        e.contextualEnglish = contextualEnglish; e.retroactiveEnglish = retroactiveEnglish
        e.collisionPrefersVietnamese = collisionPrefersVietnamese
        e.eagerEnglishRestore = autoRestore; e.modernTone = modernTone
        return e
    }
}

@inline(__always) private func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

struct Sim {
    var engine: TelexEngine
    var screen: [Character] = []
    var vi = true
    let retroApply: Bool
    let autoRestore: Bool
    var timing = false
    var samples: [UInt64] = []            // feed / ⌫
    var boundarySamples: [UInt64] = []    // chốt ranh giới (+ sửa ngược + noteBoundaryCharacter)
    /// Chỉ cho --trace: gọi sau mỗi phím / ⌫ / ranh giới với (bước, màn hình).
    var onStep: ((String, String) -> Void)?

    init(_ cfg: SimConfig, category: String) {
        engine = cfg.engine(category: category)
        retroApply = cfg.retroApply
        autoRestore = cfg.autoRestore
    }

    private mutating func apply(_ a: TelexAction, _ c: Character?) {
        switch a {
        case .passthrough:
            if let c { screen.append(c) } else if !screen.isEmpty { screen.removeLast() }
        case let .replace(bs, insert):
            screen.removeLast(min(bs, screen.count))
            screen.append(contentsOf: insert)
        case .none:
            break
        }
    }

    mutating func key(_ c: Character) {
        guard vi else { screen.append(c); return }
        if timing {
            let t0 = nowNs(); let a = engine.feed(c); samples.append(nowNs() &- t0); apply(a, c)
        } else {
            apply(engine.feed(c), c)
        }
        onStep?("'\(c)'", text)
    }

    mutating func backspace() {
        guard vi else { if !screen.isEmpty { screen.removeLast() }; return }
        if timing {
            let t0 = nowNs(); let a = engine.backspace(); samples.append(nowNs() &- t0); apply(a, nil)
        } else {
            apply(engine.backspace(), nil)
        }
        onStep?("⌫", text)
    }

    /// Ký tự ranh giới (nil = Enter cuối câu).
    mutating func boundary(_ ch: Character?) {
        guard vi else { if let ch { screen.append(ch) }; return }
        let t0 = timing ? nowNs() : 0
        if engine.isEmpty {
            engine.reset()
        } else {
            let onScreen = engine.composed.unicodeScalars.count
            let suppress = ch.map { "[]{}()".contains($0) } ?? false
            let committed = engine.commitText(autoRestore: autoRestore && !suppress)
            screen.removeLast(min(onScreen, screen.count))
            screen.append(contentsOf: committed)
        }
        if let ch {
            if retroApply, let c = engine.pendingRetroCorrection {
                let exp = Array(c.expected)
                if screen.count >= exp.count, Array(screen.suffix(exp.count)) == exp {
                    _ = engine.takeRetroCorrection()
                    screen.removeLast(exp.count)
                    screen.append(contentsOf: c.insert)
                }
            }
            screen.append(ch)
            engine.noteBoundaryCharacter(ch)
        } else {
            engine.forgetLastCommit()
            engine.resetContext()
        }
        if timing { boundarySamples.append(nowNs() &- t0) }
        onStep?(ch.map { "ranh '\($0)'" } ?? "Enter", text)
    }

    /// Bật/tắt bộ gõ giữa hai từ.
    mutating func toggle() {
        if vi { vi = false } else { vi = true; engine.reset(); engine.resetContext() }
    }

    /// Gõ một từ theo kế hoạch (chế độ Anh: gõ thẳng phím dự định, lỗi gõ sửa nguyên văn
    /// nên bỏ qua).
    mutating func typeWord(_ p: WordPlan) {
        guard vi, let t = p.typo else { for c in p.intended { key(c) }; return }
        let start = screen.count
        // Người gõ nhìn màn hình: bản đúng sau j phím dự định trông thế nào.
        var probe = engine
        var renders: [[Character]] = [[]]
        for c in p.intended { _ = probe.feed(c); renders.append(Array(probe.composed)) }
        for c in t.typed { key(c) }
        // Lỗi có thể chưa hiện ngay ("meer"+"t" trông y "meet" = mêt — r bị nuốt làm dấu rồi
        // rơi): người gõ so màn hình với bản đúng sau MỖI phím và sửa ở lần lệch đầu tiên.
        // Sửa đúng MỘT lần — sau đó lệch nữa là do engine, chính thứ đang đo.
        var pos = t.consumed
        while Array(screen[min(start, screen.count)...]) == renders[pos] {
            guard pos < p.intended.count else { return }
            key(p.intended[pos]); pos += 1
        }
        var resume = 0, guardN = 0
        while screen.count > start, !engine.isEmpty, guardN < 40 {
            backspace(); guardN += 1
            let cur = Array(screen[min(start, screen.count)...])
            if let j = (0...t.resumeMax).reversed().first(where: { renders[$0] == cur }) { resume = j; break }
        }
        for c in p.intended[resume...] { key(c) }
    }

    /// Gõ từ i và khoảng sau nó (Enter nếu là từ cuối).
    mutating func typeWordAndGap(_ s: MixedSentence, _ plans: [WordPlan], _ i: Int) {
        typeWord(plans[i])
        for ch in s.gaps[i + 1] { boundary(ch) }
        if i == s.words.count - 1 { boundary(nil) }
    }

    var text: String { String(screen) }
}

/// Kết quả một câu.
struct SentenceResult {
    var output: String
    var correct: [Bool]           // theo từ đích
    var outWords: [String?]       // từ ra tương ứng (nil = lệch số từ)
    var toggles = 0
}

enum Scorer {
    /// Đúng/sai từng từ đích. Cùng số từ ⇒ so cặp; lệch ⇒ gióng LCS.
    static func score(_ target: [String], _ outText: String) -> ([Bool], [String?]) {
        let out = MixedCorpus.words(of: outText)
        let tk = target.map(MixedCorpus.canon), ok = out.map(MixedCorpus.canon)
        if out.count == target.count {
            return (zip(tk, ok).map { $0 == $1 }, out.map { Optional($0) })
        }
        let n = tk.count, m = ok.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = tk[i] == ok[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var correct = [Bool](repeating: false, count: n), outs = [String?](repeating: nil, count: n)
        var i = 0, j = 0
        while i < n, j < m {
            if tk[i] == ok[j] { correct[i] = true; outs[i] = out[j]; i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 } else { j += 1 }
        }
        return (correct, outs)
    }

    static func wordCorrect(_ s: MixedSentence, _ i: Int, _ screen: [Character]) -> Bool {
        let out = MixedCorpus.words(of: String(screen))
        return i < out.count && MixedCorpus.canon(out[i]) == MixedCorpus.canon(s.words[i])
    }
}

public enum Runner {
    /// Người gõ "lười": không bao giờ bật/tắt bộ gõ.
    static func lazy(_ s: MixedSentence, _ plans: [WordPlan], _ cfg: SimConfig,
                     timing: Bool, samples: inout [UInt64], boundarySamples: inout [UInt64]) -> SentenceResult {
        var sim = Sim(cfg, category: s.category)
        sim.timing = timing
        if timing { sim.samples.reserveCapacity(128) }
        for ch in s.gaps[0] { sim.boundary(ch) }
        for i in s.words.indices { sim.typeWordAndGap(s, plans, i) }
        if timing { samples.append(contentsOf: sim.samples); boundarySamples.append(contentsOf: sim.boundarySamples) }
        let (c, o) = Scorer.score(s.words, sim.text)
        return SentenceResult(output: sim.text, correct: c, outWords: o)
    }

    /// Người gõ "lý tưởng": trước mỗi từ, nếu gõ tiếp ở chế độ hiện tại từ đó sẽ RA SAI thì
    /// bật/tắt bộ gõ (đếm một lần) — chỉ khi chế độ kia ra đúng. "Ra sai" xét lúc chốt từ; khi
    /// tự sửa từ phía trước bật, xét sau tối đa `lookahead` từ gõ tiếp (phép sửa ngược có thể
    /// chữa — hoặc làm hỏng — từ đó muộn hơn).
    static func ideal(_ s: MixedSentence, _ plans: [WordPlan], _ cfg: SimConfig) -> SentenceResult {
        let lookahead = cfg.retroApply ? 5 : 0
        var sim = Sim(cfg, category: s.category)
        for ch in s.gaps[0] { sim.boundary(ch) }
        var toggles = 0
        let ok = { (st: Sim, i: Int) -> Bool in
            var t = st
            for k in i...min(i + lookahead, s.words.count - 1) { t.typeWordAndGap(s, plans, k) }
            return Scorer.wordCorrect(s, i, t.screen)
        }
        for i in s.words.indices {
            if !ok(sim, i) {
                var other = sim; other.toggle()
                if ok(other, i) { sim = other; toggles += 1 }
            }
            sim.typeWordAndGap(s, plans, i)
        }
        let (c, o) = Scorer.score(s.words, sim.text)
        return SentenceResult(output: sim.text, correct: c, outWords: o, toggles: toggles)
    }
}

extension Runner {
    /// Vết gõ từng phím của một câu (người gõ lười) — để soi một lỗi: phím, lệnh engine, màn hình.
    public static func trace(_ s: MixedSentence, _ cfg: SimConfig, options: TypistOptions = TypistOptions()) -> [String] {
        let plans = Typist.plan(s, options)
        var log: [String] = []
        for (w, p) in zip(s.words, plans) {
            var line = "\(w): phím \"\(String(p.intended))\""
            if let t = p.typo { line += " — lỗi gõ \(t.kind): gõ \"\(String(t.typed))\", sửa về ≤\(t.resumeMax) phím" }
            log.append(line)
        }
        var sim = Sim(cfg, category: s.category)
        sim.onStep = { what, text in log.append("  \(what.padding(toLength: 10, withPad: " ", startingAt: 0)) │\(text)│") }
        for ch in s.gaps[0] { sim.boundary(ch) }
        for i in s.words.indices { sim.typeWordAndGap(s, plans, i) }
        return log
    }
}
