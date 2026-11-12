// SwipeSound — phát "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt). Song sinh android .../ime/SwipeSoundPlayer.kt.
// Phần thuần (kiểu, cổng Plus, đo tốc độ, vỏ âm lượng, dò phím, cao độ sáo): Shared/SwipeSoundStyles.swift; mẫu: KeySoundSynth.
//
// - Tắt (mặc định) / âm lượng phím 0 % / thiếu Toàn quyền Truy cập ⇒ controller không bật (KeyboardView.swipeSound = nil):
//   không engine, không buffer; đường vuốt chỉ đọc một optional.
// - Bật: AVAudioEngine RIÊNG (không đụng engine âm phím) + MỘT AVAudioSourceNode 22,05 kHz đọc vòng lặp dựng sẵn
//   (~88–123 KB Float32). Âm lượng tính TỪNG MẪU trong render (SwipeSoundEnvelope — không "rè" khi đổi âm lượng).
// - Main KHÔNG BAO GIỜ chờ: begin/move/end chỉ ghi vài số Double vào khối điều khiển dùng chung (render đọc — số 64-bit
//   căn hàng, ghi/đọc nguyên tử trên arm64; lệch một khung render không nghe ra). Dựng/khởi động/dừng engine trên `queue`.
//   Mỗi điểm vuốt: SwipeSoundMeter.move (vài phép tính) + 2 lần ghi — không cấp phát, không khoá, không XPC.
// - Session .ambient + mixWithOthers: không ngắt nhạc, im khi gạt im lặng (như âm phím). Âm lượng = thanh Âm thanh phím.
// - PIN: nghỉ `idleTimeout` (8 s) không vuốt ⇒ engine.pause() + nhả session (giữ buffer). Cú vuốt kế khởi động lại NỀN —
//   tiếng vào khi engine sẵn sàng (tiếng mở dần nên trễ vài chục ms không nghe ra).
// - Ẩn bàn phím ⇒ shutdown (nhả engine + buffer). Cảnh báo bộ nhớ ⇒ nhả nếu không đang vuốt (cú vuốt kế dựng lại lười).
// - Roi vụt / Tia sét / Plasma / Đũa phép / Sóng biển / Mèo kêu / Chim hót: tiếng nhấc tay (KeySoundSynth.swipeLiftSamples)
//   trộn trong CÙNG render — main chỉ ghi độ to (SwipeSoundFx.liftGain của tốc độ 80 ms cuối) + tăng bộ đếm; huỷ ⇒ không
//   kêu. Đũa phép / Chim hót: lớp dày × âm lượng².
// - Nốt nhạc theo phím: mỗi điểm SwipeKeyTracker.feed (O(1), không cấp phát) — vào phím mới ⇒ main ghi (bậc, độ to) vào
//   vòng 8 sự kiện trong khối điều khiển + tăng bộ đếm; render gảy nốt dựng sẵn (14 nốt × 0,6 s ≈ 0,74 MB, nhạc cụ theo Âm
//   thanh phím) trên pool 6 giọng xoay vòng (giọng thứ 7 thay giọng cũ nhất). Không vỏ âm lượng — nốt ngân hết tự nhiên.
// - Sáo trúc: main ghi tốc độ đọc đích (SwipeSoundFx.fluteRate theo vị trí ngang); render trượt về đích τ40 ms và đọc vòng
//   lặp ở vị trí lẻ (nội suy tuyến tính); tắt dần 250 ms khi nhấc tay.
// - Âm của bạn: vòng lặp đọc từ App Group (SwipeSoundCustom) lúc dựng engine; vắng/hỏng ⇒ Bút chì.
import AVFoundation
import QuartzCore

final class SwipeSound {
    /// Chỉ dựng khi kiểu khác Tắt (main). Tắt từ đầu ⇒ không bao giờ tạo (cả queue lẫn khối điều khiển).
    nonisolated(unsafe) private static var instance: SwipeSound?
    static var shared: SwipeSound {
        if let i = instance { return i }
        let i = SwipeSound(); instance = i; return i
    }
    /// Bản đã dựng (nil = chưa từng bật) — ẩn bàn phím / cảnh báo bộ nhớ không tạo mới.
    static var existing: SwipeSound? { instance }

    /// Không vuốt quá chừng này ⇒ tạm dừng engine (pin). Test chỉnh nhỏ lại.
    var idleTimeout: TimeInterval = 8

    /// Số sự kiện nốt giữ trong vòng của khối điều khiển (render đọc mỗi khung ~5–20 ms ⇒ dư sức).
    private static let eventRing = 8

    /// Khối điều khiển main ⇄ render: [đích âm lượng, giờ điểm cuối, số lần begin, số lần end, engine chạy (0/1),
    /// giờ hoạt động cuối, độ to tiếng nhấc tay, số lần nhấc tay có tiếng, tốc độ đọc đích (Sáo trúc), số nốt đã gảy,
    /// vòng 8 × (bậc, độ to)]. Cấp MỘT lần, không bao giờ giải phóng (singleton).
    private let ctl: UnsafeMutablePointer<Double> = {
        let p = UnsafeMutablePointer<Double>.allocate(capacity: 32)
        p.initialize(repeating: 0, count: 32)
        return p
    }()
    private enum C {
        static let target = 0, lastMove = 1, begins = 2, ends = 3, running = 4, lastActive = 5, liftGain = 6, lifts = 7
        static let rate = 8, notes = 9, events = 10
    }

    // --- chỉ main ---
    private var meter = SwipeSoundMeter()
    private var swiping = false
    /// Kiểu + âm lượng đã cấu hình (main ghi, queue đọc qua bản chép trong closure).
    private(set) var style: SwipeSoundStyle = .none
    private var volumePercent = 0
    /// Dò phím dưới ngón (Nốt nhạc theo phím, Sáo trúc) — dựng lại khi layout đổi (setLayout).
    private var tracker: SwipeKeyTracker?
    private var layoutCenters: [Float] = []
    private var layoutKeyWidth: Float = 0

    // --- chỉ trên `queue` ---
    private let queue = DispatchQueue(label: "vt.swipesound", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var builtStyle: SwipeSoundStyle = .none
    private var builtInstrument: KeyInstrument = .dantranh
    private var render: RenderState?
    private var configObserver: NSObjectProtocol?
    private var idleCheckScheduled = false
    private var wantedStyle: SwipeSoundStyle = .none
    private var wantedInstrument: KeyInstrument = .dantranh
    private var wantedGain: Float = 0
    private var starting = false

    /// Trạng thái riêng của luồng render (vị trí đọc + vỏ âm lượng + giọng nốt). Giữ buffer vòng lặp, lớp dày, tiếng nhấc
    /// tay, bộ nốt. Mọi mảng cấp MỘT lần lúc dựng.
    private final class RenderState {
        let loop: UnsafeMutableBufferPointer<Float>
        let layer: UnsafeMutableBufferPointer<Float>
        let shot: UnsafeMutableBufferPointer<Float>
        /// Bộ nốt liền khối: nốt bậc k ở [k·noteLen, (k+1)·noteLen).
        let notes: UnsafeMutableBufferPointer<Float>
        let noteLen: Int, noteCount: Int
        let isNotes: Bool, pitched: Bool
        var pos = 0, lpos = 0
        /// Vị trí đọc tiếng nhấc tay (= shot.count ⇒ không phát).
        var spos: Int
        var shotGain = 0.0
        var env: SwipeSoundEnvelope
        var seenBegins = 0.0, seenEnds = 0.0, seenLifts = 0.0, seenNotes = 0.0
        /// Sáo trúc: vị trí đọc lẻ + tốc độ đọc hiện tại (trượt về đích).
        var fpos = 0.0, rate = 1.0
        let glideK = 1 - exp(-1 / (KeySoundSynth.swipeSampleRate * SwipeSoundFx.glideTau))
        /// Pool giọng nốt: bậc, vị trí đọc (≥ noteLen ⇒ rảnh), độ to.
        let vNote: UnsafeMutablePointer<Int>, vPos: UnsafeMutablePointer<Int>, vGain: UnsafeMutablePointer<Float>
        var nextVoice = 0

        init(_ samples: [Float], layer l: [Float], shot sh: [Float], lifts: Double, notes nb: [Float], noteLen nl: Int,
             notesSeen: Double, style: SwipeSoundStyle) {
            loop = Self.copy(samples); layer = Self.copy(l); shot = Self.copy(sh); notes = Self.copy(nb)
            noteLen = max(1, nl); noteCount = nb.count / max(1, nl)
            isNotes = style.isNotes; pitched = style.followsX
            spos = sh.count
            seenLifts = lifts; seenNotes = notesSeen
            env = SwipeSoundEnvelope(step: 1 / KeySoundSynth.swipeSampleRate, fade: SwipeSoundFx.release(style))
            let v = SwipeSoundFx.noteVoices
            vNote = .allocate(capacity: v); vNote.initialize(repeating: 0, count: v)
            vPos = .allocate(capacity: v); vPos.initialize(repeating: Int.max, count: v)
            vGain = .allocate(capacity: v); vGain.initialize(repeating: 0, count: v)
        }
        private static func copy(_ x: [Float]) -> UnsafeMutableBufferPointer<Float> {
            let b = UnsafeMutableBufferPointer<Float>.allocate(capacity: max(1, x.count))
            _ = b.initialize(from: x)
            return UnsafeMutableBufferPointer(rebasing: b[0..<x.count])
        }
        deinit {
            loop.baseAddress?.deallocate(); layer.baseAddress?.deallocate(); shot.baseAddress?.deallocate()
            notes.baseAddress?.deallocate()
            vNote.deallocate(); vPos.deallocate(); vGain.deallocate()
        }
    }

    // MARK: cấu hình (main, lúc hiện bàn phím) — không chờ

    /// `style` = kiểu thực phát (đã qua SwipeSoundPolicy + Full Access); Tắt ⇒ shutdown. `instrument` = nhạc cụ của Âm
    /// thanh phím (Nốt nhạc theo phím; không phải nhạc cụ ⇒ Đàn tranh).
    func configure(style s: SwipeSoundStyle, volumePercent v: Int, instrument: KeyInstrument = .dantranh) {
        style = s; volumePercent = v
        let g = KeySoundSynth.gain(forPercent: v)
        if s == .none || v <= 0 { shutdown(); return }
        queue.async { [self] in
            wantedStyle = s; wantedInstrument = instrument; wantedGain = g
            engine?.mainMixerNode.outputVolume = g
            if engine != nil, builtStyle != s || (s.isNotes && builtInstrument != instrument) { stopNow(keepWanted: true) }
        }
    }

    /// Tâm phím a…z (52 số, cùng toạ độ với begin/move) + bước phím — từ layout gõ vuốt. Trùng ⇒ không làm gì.
    func setLayout(centers: [Float], keyWidth: Float) {
        guard centers != layoutCenters || keyWidth != layoutKeyWidth else { return }
        layoutCenters = centers; layoutKeyWidth = keyWidth
        tracker = SwipeKeyTracker(centers: centers, keyWidth: keyWidth)
    }

    /// Ẩn bàn phím: dừng + nhả engine/buffer.
    func shutdown() {
        swiping = false
        style = .none
        queue.async { [self] in wantedStyle = .none; stopNow(keepWanted: false) }
    }

    /// Cảnh báo bộ nhớ: nhả buffer + engine nếu không đang vuốt (cú vuốt kế dựng lại lười).
    func releaseIfIdle() {
        guard !swiping else { return }
        queue.async { [self] in stopNow(keepWanted: true) }
    }

    // MARK: đường vuốt (main) — không cấp phát, không khoá

    /// Touch vừa thành cú vuốt (`x`, `y` pt; `t` = timestamp của touch).
    func begin(x: Double, y: Double, t: TimeInterval) {
        guard style != .none else { return }
        swiping = true
        meter.reset(x: x, y: y, t: t)
        tracker?.reset()
        let now = CACurrentMediaTime()
        ctl[C.target] = 0
        ctl[C.lastMove] = now
        ctl[C.lastActive] = now
        if style.followsX { ctl[C.rate] = fluteRate(x) }   // ghi TRƯỚC bộ đếm begin: render bắt cao độ ngay, không trượt
        ctl[C.begins] += 1
        if style.isNotes { hitKey(x: x, y: y) }
        if ctl[C.running] == 0 { queue.async { [self] in _ = startNow() } }   // nghỉ / chưa dựng: dựng nền (một lần mỗi cú vuốt)
    }

    func move(x: Double, y: Double, t: TimeInterval) {
        guard swiping else { return }
        meter.move(x: x, y: y, t: t)
        ctl[C.target] = meter.gain
        ctl[C.lastMove] = CACurrentMediaTime()
        if style.isNotes { hitKey(x: x, y: y) } else if style.followsX { ctl[C.rate] = fluteRate(x) }
    }

    /// Sáo trúc: tốc độ đọc theo vị trí ngang; chưa có layout ⇒ cao độ gốc.
    private func fluteRate(_ x: Double) -> Double {
        guard let tr = tracker else { return 1 }
        return SwipeSoundFx.fluteRate(tr.unitX(x))
    }

    /// Nốt nhạc theo phím: vào phím mới ⇒ một sự kiện (bậc, độ to theo tốc độ) — ghi ô vòng TRƯỚC, tăng bộ đếm SAU.
    private func hitKey(x: Double, y: Double) {
        guard let k = tracker?.feed(x: x, y: y), k >= 0 else { return }
        let n = ctl[C.notes]
        let i = C.events + 2 * (Int(n) % Self.eventRing)
        ctl[i] = Double(SwipeNoteMap.step(letter: k))
        ctl[i + 1] = SwipeSoundFx.noteVelocity(meter.speed)
        ctl[C.notes] = n + 1
        ctl[C.lastActive] = CACurrentMediaTime()
    }

    /// Nhấc tay (`liftAt` = timestamp của touch nhấc) / huỷ (nil): render tắt dần. Nhấc tay ở kiểu có tiếng nhấc tay ⇒ một
    /// tiếng ngắn, to theo tốc độ `liftWindow` cuối (gần như đứng yên ⇒ không kêu). Huỷ ⇒ không kêu.
    func end(liftAt t: TimeInterval? = nil) {
        guard swiping else { return }
        swiping = false
        if let t, style.hasLift {
            let g = SwipeSoundFx.liftGain(meter.recentSpeed(at: t))
            if g > 0 { ctl[C.liftGain] = g; ctl[C.lifts] += 1 }   // độ to ghi TRƯỚC bộ đếm
        }
        ctl[C.ends] += 1
        ctl[C.lastActive] = CACurrentMediaTime()
    }

    // MARK: engine (queue)

    @discardableResult
    func startNow() -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard wantedStyle != .none else { return false }
        let fresh = builtStyle == wantedStyle && (!wantedStyle.isNotes || builtInstrument == wantedInstrument)
        if let e = engine, e.isRunning, fresh { ctl[C.running] = 1; return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            if engine == nil || !fresh {
                stopNow(keepWanted: true)
                guard let fmt = AVAudioFormat(standardFormatWithSampleRate: KeySoundSynth.swipeSampleRate, channels: 1)
                else { return false }
                let w = wantedStyle, inst = wantedInstrument
                let loop = w == .custom ? SwipeSoundCustom.resolvedLoop(SwipeSoundCustom.load(SwipeSoundCustom.fileURL))
                                        : KeySoundSynth.swipeLoopSamples(w)
                let bank = w.isNotes ? KeySoundSynth.swipeNoteBank(inst).flatMap { $0 } : []
                let st = RenderState(loop, layer: KeySoundSynth.swipeLayerSamples(w), shot: KeySoundSynth.swipeLiftSamples(w),
                                     lifts: ctl[C.lifts], notes: bank, noteLen: KeySoundSynth.swipeNoteLength,
                                     notesSeen: ctl[C.notes], style: w)
                let node = Self.makeSource(fmt, st, ctl)
                let e = AVAudioEngine()
                e.attach(node)
                e.connect(node, to: e.mainMixerNode, format: fmt)
                engine = e; source = node; render = st; builtStyle = w; builtInstrument = inst
                configObserver = NotificationCenter.default.addObserver(
                    forName: .AVAudioEngineConfigurationChange, object: e, queue: nil) { [weak self] _ in
                    guard let self else { return }
                    self.queue.async { self.ctl[C.running] = 0; _ = self.startNow() }
                }
            }
            guard let e = engine else { return false }
            e.mainMixerNode.outputVolume = wantedGain
            if !e.isRunning { e.prepare(); try e.start() }
            ctl[C.running] = 1
            scheduleIdleCheck(after: idleTimeout)
            return true
        } catch {
            TouchLog.write("swipesound: không khởi động được engine \(error)")
            ctl[C.running] = 0
            return false
        }
    }

    /// Nguồn âm: vòng lặp × vỏ âm lượng từng mẫu (+ lớp dày × âm lượng², + tiếng nhấc tay); Sáo trúc đọc vòng ở tốc độ
    /// trượt; Nốt nhạc theo phím: pool giọng nốt. Chạy trên luồng render thời gian thực — không cấp phát, không khoá.
    private static func makeSource(_ fmt: AVAudioFormat, _ st: RenderState, _ ctl: UnsafeMutablePointer<Double>) -> AVAudioSourceNode {
        AVAudioSourceNode(format: fmt) { _, _, frameCount, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            if st.isNotes { SwipeSound.renderNotes(st, ctl, out, frames); return noErr }
            let begins = ctl[C.begins], ends = ctl[C.ends]
            if begins != st.seenBegins {
                st.seenBegins = begins; st.env.begin()
                if st.pitched { st.rate = ctl[C.rate] > 0 ? ctl[C.rate] : 1 }   // cú vuốt mới: bắt cao độ ngay
            }
            if ends != st.seenEnds { st.seenEnds = ends; if ends >= begins { st.env.release() } }
            let lifts = ctl[C.lifts]
            if lifts != st.seenLifts { st.seenLifts = lifts; st.spos = 0; st.shotGain = ctl[C.liftGain] }
            let target = SwipeSoundFx.target(ctl[C.target], sinceMove: CACurrentMediaTime() - ctl[C.lastMove])
            let loop = st.loop, n = loop.count, layer = st.layer, ln = layer.count, shot = st.shot, sn = shot.count
            guard n > 0 else { for i in 0..<frames { out[i] = 0 }; return noErr }
            let sg = Float(st.shotGain)
            let rt = ctl[C.rate] > 0 ? ctl[C.rate] : 1, kg = st.glideK, pitched = st.pitched, nd = Double(n)
            // bản chép cục bộ: vòng mẫu không truy cập thuộc tính lớp
            var pos = st.pos, lpos = st.lpos, spos = st.spos, env = st.env, fpos = st.fpos, rate = st.rate
            for i in 0..<frames {
                let g = env.next(target)
                var v: Float = 0
                if pitched {
                    rate += (rt - rate) * kg
                    if g > 0 {
                        let i0 = Int(fpos), fr = Float(fpos - Double(i0))
                        v = (loop[i0] * (1 - fr) + loop[i0 + 1 == n ? 0 : i0 + 1] * fr) * Float(g)
                    }
                    fpos += rate
                    if fpos >= nd { fpos -= nd }
                } else {
                    if g > 0 {
                        v = loop[pos] * Float(g)
                        if ln > 0 { v += layer[lpos] * Float(g * g) }
                    }
                    pos += 1
                    if pos == n { pos = 0 }
                    if ln > 0 { lpos += 1; if lpos == ln { lpos = 0 } }
                }
                if spos < sn { v += shot[spos] * sg; spos += 1 }
                out[i] = v
            }
            st.pos = pos; st.lpos = lpos; st.spos = spos; st.env = env; st.fpos = fpos; st.rate = rate
            return noErr
        }
    }

    /// Nốt nhạc theo phím (luồng render): nhận sự kiện mới từ vòng (tối đa 8 gần nhất), gán giọng xoay vòng, trộn các giọng.
    private static func renderNotes(_ st: RenderState, _ ctl: UnsafeMutablePointer<Double>,
                                    _ out: UnsafeMutablePointer<Float>, _ frames: Int) {
        let cnt = ctl[C.notes]
        if cnt != st.seenNotes {
            var e = max(st.seenNotes, cnt - Double(eventRing))
            while e < cnt {
                let i = C.events + 2 * (Int(e) % eventRing)
                let step = Int(ctl[i])
                if step >= 0 && step < st.noteCount {
                    let v = st.nextVoice
                    st.nextVoice = (v + 1) % SwipeSoundFx.noteVoices
                    st.vNote[v] = step; st.vPos[v] = 0; st.vGain[v] = Float(ctl[i + 1])
                }
                e += 1
            }
            st.seenNotes = cnt
        }
        let notes = st.notes, len = st.noteLen, vn = SwipeSoundFx.noteVoices
        let vNote = st.vNote, vPos = st.vPos, vGain = st.vGain
        for i in 0..<frames {
            var v: Float = 0
            for k in 0..<vn where vPos[k] < len {
                v += notes[vNote[k] * len + vPos[k]] * vGain[k]
                vPos[k] += 1
            }
            out[i] = v
        }
    }

    private func scheduleIdleCheck(after delay: TimeInterval) {
        guard !idleCheckScheduled else { return }
        idleCheckScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.idleCheck() }
    }

    private func idleCheck() {
        idleCheckScheduled = false
        guard let e = engine, e.isRunning else { return }
        let swipingNow = ctl[C.begins] > ctl[C.ends]
        let d = KeySound.idleDecision(now: CACurrentMediaTime(), lastPlay: ctl[C.lastActive], timeout: idleTimeout)
        if swipingNow || !d.stop { scheduleIdleCheck(after: swipingNow ? idleTimeout : d.recheck); return }
        ctl[C.running] = 0
        e.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Dừng + nhả engine/buffer. `keepWanted` = vẫn bật (dựng lại lười ở cú vuốt kế).
    private func stopNow(keepWanted: Bool) {
        if !keepWanted { wantedStyle = .none }
        ctl[C.running] = 0
        guard let e = engine else { return }
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        e.stop()                       // đồng bộ: render không còn chạy ⇒ nhả buffer an toàn
        if let s = source { e.detach(s) }
        engine = nil; source = nil; render = nil; builtStyle = .none
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    #if DEBUG
    /// Test: chờ queue xong.
    func debugDrain() { queue.sync {} }
    var debugHasEngine: Bool { queue.sync { engine != nil } }
    var debugHasBuffer: Bool { queue.sync { render != nil } }
    var debugBuiltStyle: SwipeSoundStyle { queue.sync { builtStyle } }
    var debugIsSwiping: Bool { swiping }
    var debugHasLayout: Bool { tracker != nil }
    var debugControl: (target: Double, begins: Double, ends: Double) { (ctl[C.target], ctl[C.begins], ctl[C.ends]) }
    var debugLift: (gain: Double, count: Double) { (ctl[C.liftGain], ctl[C.lifts]) }
    var debugRate: Double { ctl[C.rate] }
    /// Số nốt đã gảy + (bậc, độ to) của nốt gần nhất.
    var debugNotes: (count: Double, step: Int, gain: Double) {
        let n = ctl[C.notes]
        guard n > 0 else { return (0, -1, 0) }
        let i = C.events + 2 * (Int(n - 1) % Self.eventRing)
        return (n, Int(ctl[i]), ctl[i + 1])
    }
    #endif
}
