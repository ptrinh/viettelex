// SwipeSound — phát "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt). Song sinh android .../ime/SwipeSoundPlayer.kt.
// Phần thuần (kiểu, cổng Plus, đo tốc độ, vỏ âm lượng): Shared/SwipeSoundStyles.swift; mẫu lặp: KeySoundSynth.swipeLoopSamples.
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

    /// Khối điều khiển main ⇄ render: [đích âm lượng, giờ điểm cuối, số lần begin, số lần end, engine chạy (0/1),
    /// giờ hoạt động cuối]. Cấp MỘT lần, không bao giờ giải phóng (singleton).
    private let ctl: UnsafeMutablePointer<Double> = {
        let p = UnsafeMutablePointer<Double>.allocate(capacity: 6)
        p.initialize(repeating: 0, count: 6)
        return p
    }()
    private enum C { static let target = 0, lastMove = 1, begins = 2, ends = 3, running = 4, lastActive = 5 }

    // --- chỉ main ---
    private var meter = SwipeSoundMeter()
    private var swiping = false
    /// Kiểu + âm lượng đã cấu hình (main ghi, queue đọc qua bản chép trong closure).
    private(set) var style: SwipeSoundStyle = .none
    private var volumePercent = 0

    // --- chỉ trên `queue` ---
    private let queue = DispatchQueue(label: "vt.swipesound", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var builtStyle: SwipeSoundStyle = .none
    private var render: RenderState?
    private var configObserver: NSObjectProtocol?
    private var idleCheckScheduled = false
    private var wantedStyle: SwipeSoundStyle = .none
    private var wantedGain: Float = 0
    private var starting = false

    /// Trạng thái riêng của luồng render (vị trí đọc vòng lặp + vỏ âm lượng). Giữ buffer vòng lặp.
    private final class RenderState {
        let loop: UnsafeMutableBufferPointer<Float>
        var pos = 0
        var env = SwipeSoundEnvelope(step: 1 / KeySoundSynth.swipeSampleRate)
        var seenBegins = 0.0, seenEnds = 0.0
        init(_ samples: [Float]) {
            loop = .allocate(capacity: samples.count)
            _ = loop.initialize(from: samples)
        }
        deinit { loop.deallocate() }
    }

    // MARK: cấu hình (main, lúc hiện bàn phím) — không chờ

    /// `style` = kiểu thực phát (đã qua SwipeSoundPolicy + Full Access); Tắt ⇒ shutdown.
    func configure(style s: SwipeSoundStyle, volumePercent v: Int) {
        style = s; volumePercent = v
        let g = KeySoundSynth.gain(forPercent: v)
        if s == .none || v <= 0 { shutdown(); return }
        queue.async { [self] in
            wantedStyle = s; wantedGain = g
            engine?.mainMixerNode.outputVolume = g
            if builtStyle != s, engine != nil { stopNow(keepWanted: true) }
        }
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
        let now = CACurrentMediaTime()
        ctl[C.target] = 0
        ctl[C.lastMove] = now
        ctl[C.lastActive] = now
        ctl[C.begins] += 1
        if ctl[C.running] == 0 { queue.async { [self] in _ = startNow() } }   // nghỉ / chưa dựng: dựng nền (một lần mỗi cú vuốt)
    }

    func move(x: Double, y: Double, t: TimeInterval) {
        guard swiping else { return }
        meter.move(x: x, y: y, t: t)
        ctl[C.target] = meter.gain
        ctl[C.lastMove] = CACurrentMediaTime()
    }

    /// Nhấc tay / huỷ: render tắt dần `fadeOut`.
    func end() {
        guard swiping else { return }
        swiping = false
        ctl[C.ends] += 1
        ctl[C.lastActive] = CACurrentMediaTime()
    }

    // MARK: engine (queue)

    @discardableResult
    func startNow() -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard wantedStyle != .none else { return false }
        if let e = engine, e.isRunning, builtStyle == wantedStyle { ctl[C.running] = 1; return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            if engine == nil || builtStyle != wantedStyle {
                stopNow(keepWanted: true)
                guard let fmt = AVAudioFormat(standardFormatWithSampleRate: KeySoundSynth.swipeSampleRate, channels: 1)
                else { return false }
                let st = RenderState(KeySoundSynth.swipeLoopSamples(wantedStyle))
                let node = Self.makeSource(fmt, st, ctl)
                let e = AVAudioEngine()
                e.attach(node)
                e.connect(node, to: e.mainMixerNode, format: fmt)
                engine = e; source = node; render = st; builtStyle = wantedStyle
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

    /// Nguồn âm: đọc vòng lặp × vỏ âm lượng từng mẫu. Chạy trên luồng render thời gian thực — không cấp phát, không khoá.
    private static func makeSource(_ fmt: AVAudioFormat, _ st: RenderState, _ ctl: UnsafeMutablePointer<Double>) -> AVAudioSourceNode {
        AVAudioSourceNode(format: fmt) { _, _, frameCount, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let begins = ctl[C.begins], ends = ctl[C.ends]
            if begins != st.seenBegins { st.seenBegins = begins; st.env.begin() }
            if ends != st.seenEnds { st.seenEnds = ends; if ends >= begins { st.env.release() } }
            let target = SwipeSoundFx.target(ctl[C.target], sinceMove: CACurrentMediaTime() - ctl[C.lastMove])
            let loop = st.loop, n = loop.count
            var pos = st.pos, env = st.env   // bản chép cục bộ: vòng mẫu không truy cập thuộc tính lớp
            for i in 0..<Int(frameCount) {
                let g = env.next(target)
                out[i] = g > 0 ? loop[pos] * Float(g) : 0
                pos += 1
                if pos == n { pos = 0 }
            }
            st.pos = pos; st.env = env
            return noErr
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
    var debugControl: (target: Double, begins: Double, ends: Double) { (ctl[C.target], ctl[C.begins], ctl[C.ends]) }
    #endif
}
