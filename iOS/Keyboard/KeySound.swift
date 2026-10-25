// KeySound — âm phím RIÊNG của VietTelex (setting "Âm thanh phím", mặc định TẮT).
//
// TẮT ⇒ giữ nguyên hành vi cũ: UIDevice.playInputClick (theo Cài đặt → Âm thanh →
// Tiếng bấm bàn phím), không dựng engine, không tốn gì thêm.
// BẬT + kiểu "iOS" (`system`) ⇒ cũng là playInputClick: controller không bật đường riêng, engine
// KHÔNG dựng (startNow từ chối cả khi bị gọi nhầm) ⇒ 0 chi phí, không cần Full Access.
// BẬT ⇒ phát 3 tiếng (chữ / xoá / phím chức năng như stock) theo KIỂU đã chọn
// (`keySoundStyle`: 5 kiểu tổng hợp + âm tự chọn) và âm lượng thanh trượt, KHÔNG kèm
// click hệ thống (không kêu đôi).
//
// - Mẫu âm: Shared/KeySoundSynth.swift (tất định, dùng chung với app để nghe thử). Âm tự
//   chọn: WAV đã xử lý trong App Group (KeySoundCustom.fileURL) — vắng/hỏng ⇒ "Nhẹ nhàng".
// - Độ trễ: AVAudioEngine + 1 AVAudioPlayerNode/loại, buffer PCM dựng sẵn; bấm phím chỉ
//   scheduleBuffer(.interrupts) — không cấp phát, không chặn main (lock.try()).
// - Audio session .ambient (+ mixWithOthers): không ngắt nhạc đang phát, TÔN TRỌNG gạt
//   im lặng — như click bàn phím stock (iOS 17+ im khi bật chế độ im lặng).
// - Cần Toàn quyền Truy cập: không có Full Access, audio của extension không phát được ổn
//   định ⇒ controller chỉ bật đường này khi hasFullAccess, thiếu thì quay về click hệ thống.
// - PIN (Phil 28/09): engine đang chạy = phần cứng audio render liên tục (~vài mW) dù im.
//   ⇒ NGHỈ sau `idleTimeout` (8 s) không bấm: engine.pause() + nhả session. Lần bấm kế
//   tiếp khởi động lại NỀN (không chặn main); tiếng của lần bấm đó chỉ phát nếu engine
//   sẵn sàng trong `lateWindow` (40 ms), trễ hơn thì bỏ (thà im một tiếng còn hơn kêu muộn).
//   Kiểm tra nghỉ là một asyncAfter một lần (hẹn lại theo lastPlay) — không timer lặp,
//   bấm phím không hẹn gì thêm.
// - Vòng đời: engine dựng/khởi động trên queue riêng khi bàn phím hiện (setting BẬT),
//   dừng + nhả khi ẩn hoặc thiếu RAM.
// - PIANO (Phil 19/10/2026): mỗi phím một nốt (PianoMap). Kiểu này KHÔNG dùng 3 node chữ/xoá/chức
//   năng mà một pool 8 AVAudioPlayerNode (22.05 kHz) xoay vòng ⇒ nốt chồng nhau, bấm nhiều phím cùng
//   lúc thành hợp âm (giọng cùng cửa sổ 60 ms hạ 1/√n — không vỡ tiếng). Buffer mọi nốt dựng sẵn lúc
//   hiện (~1.97 MB). Pedal (Shift/Caps): pool 8 node thứ hai 11.025 kHz với bộ nốt ngân 2.5 s, dựng
//   LƯỜI lần đầu đạp pedal (~2.76 MB; trong lúc dựng nốt phát bản thường). Kiểu khác: đường 3 tiếng
//   như cũ, chỉ thêm một phép so bool.
// - ĐÀN TRANH (theme Sen Việt, 19/10/2026): CÙNG đường Piano (pool 8 giọng, pedal, bộ ngân dựng lười, damper) —
//   chỉ khác bảng nốt + bộ tổng hợp (KeyInstrument). Bộ nốt thường 1.0 s ⇒ ~2.45 MB Float32; bộ ngân ~2.76 MB như
//   Piano. Đổi Piano ⇄ Đàn tranh: dựng lại bộ nốt, giữ node (cùng định dạng 22.05 kHz), bỏ bộ ngân cũ.
// - VÒNG HỢP ÂM (10/2026): Piano / Ghi-ta có `map.progression` ⇒ mỗi hợp âm dựng MỘT lần lúc hiện (pianoExtra[4…]),
//   phím cách phát `.chord(i)` (KeyboardView giữ ChordProgression). Đàn tranh: hợp âm cách cố định như cũ.
// - GHI-TA (theme Ghi-ta): CÙNG đường Piano; nốt 1.2 s ⇒ bộ thường ~3.24 MB Float32 (25 nốt + 4 hợp âm + chủ + ⌫ +
//   pedal); bộ ngân như Piano.
import AVFoundation

final class KeySound {
    static let shared = KeySound()

    /// Không bấm quá chừng này ⇒ tạm dừng engine (pin). Test chỉnh nhỏ lại.
    var idleTimeout: TimeInterval = 8
    /// Bấm lúc engine đang nghỉ: khởi động xong trong khoảng này thì vẫn phát tiếng đó.
    static let lateWindow: TimeInterval = 0.040

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "vt.keysound", qos: .userInteractive)
    // Toàn bộ dưới đây chỉ đụng khi giữ lock.
    private var engine: AVAudioEngine?
    private var nodes: [AVAudioPlayerNode] = []
    private var buffers: [AVAudioPCMBuffer] = []
    /// Tiếng Enter riêng của kiểu (Máy chữ: "ding" về dòng) — nil = Enter dùng tiếng phím chức năng.
    private var returnBuffer: AVAudioPCMBuffer?
    private var running = false
    private var wanted = false
    private var restarting = false
    private var pending: (kind: KeySoundKind, at: TimeInterval)?
    private var lastPlay: TimeInterval = 0
    private var idleCheckScheduled = false
    private var gain: Float = KeySoundSynth.gain(forPercent: 50)
    private var configObserver: NSObjectProtocol?
    /// Kiểu mong muốn (giá trị lưu) + khoá bộ mẫu đang dựng (kiểu + mtime file tự chọn).
    private var styleRaw = KeySoundStyle.defaultStyle.rawValue
    private var customURL: URL? = KeySoundCustom.fileURL
    private var builtKey: String?
    /// Kiểu thật sự đang phát (custom thiếu file ⇒ subtle) — log/test.
    private(set) var activeStyle: KeySoundStyle = .defaultStyle

    // --- Nhạc cụ mỗi phím một nốt (kiểu = piano / dantranh) ---
    private var pianoMode = false
    /// Nhạc cụ đang dựng (pianoMode). Bộ nốt / bộ ngân thuộc nhạc cụ này.
    private(set) var instrument: KeyInstrument = .piano
    private var pianoNodes: [AVAudioPlayerNode] = []
    private var sustainNodes: [AVAudioPlayerNode] = []
    /// Buffer theo số MIDI (0…127), nil = không có. Tra mỗi phím không cấp phát.
    private var pianoBuf = [AVAudioPCMBuffer?](repeating: nil, count: 128)
    private var sustainBuf = [AVAudioPCMBuffer?](repeating: nil, count: 128)
    /// cách, Enter, ⌫, pedal, rồi hợp âm vòng cách 0…n−1 (cách = hợp âm 0 dùng CHUNG buffer với nhạc cụ có vòng).
    private var pianoExtra: [AVAudioPCMBuffer] = []
    private var pianoPool = VoicePool(size: PianoSynth.voices)
    private var sustainPool = VoicePool(size: PianoSynth.voices)
    private var sustainReady = false
    private var sustainBuilding = false
    /// Giọng của lần phát piano gần nhất (test hợp âm); −1 = chưa.
    private(set) var lastPianoVoice = -1

    // --- "Éc" của theme Đập chuột (MoleGame): chỉ dựng khi theme bật trò chơi (setSqueakEnabled) ---
    private var squeakWanted = false
    private var squeakBuffer: AVAudioPCMBuffer?

    // MARK: cấu hình từ main — KHÔNG BAO GIỜ chờ lock
    // startNow/stopNow giữ `lock` suốt lúc dựng engine (AVAudioSession.setActive = XPC, tổng hợp bộ
    // nốt piano ~2 MB) — có thể hàng chục–hàng trăm ms trên máy cũ. Ẩn rồi hiện lại nhanh (đổi ô,
    // Danh bạ → ô tìm kiếm) ⇒ viewWillAppear gọi setStyle/setVolume/prepare/setSqueakEnabled trên
    // main và CHỜ lock ⇒ bàn phím hiện chậm (đo 25/10/2026: ~12 ms simulator chỉ riêng setSqueakEnabled).
    // Nay: lock rảnh ⇒ làm ngay (như cũ); bận (hoặc còn việc cấu hình đang xếp hàng — giữ thứ tự) ⇒
    // xếp vào queue nối tiếp, main đi tiếp.

    /// Bảo vệ `queuedConfig` — chỉ giữ vài lệnh, không bao giờ giữ qua việc chậm.
    private let configGate = NSLock()
    private var queuedConfig = 0

    /// Chạy `body` trong `lock`: ngay nếu lock rảnh và không còn cấu hình nào đang chờ, không thì
    /// xếp hàng trên `queue` (cùng thứ tự gọi). Trả true nếu đã chạy đồng bộ.
    @discardableResult
    private func configure(_ body: @escaping () -> Void) -> Bool {
        configGate.lock()
        if queuedConfig == 0, lock.try() {
            configGate.unlock()
            body()
            lock.unlock()
            return true
        }
        queuedConfig += 1
        configGate.unlock()
        queue.async { [self] in
            lock.lock(); body(); lock.unlock()
            configGate.lock(); queuedConfig -= 1; configGate.unlock()
        }
        return false
    }

    func setVolume(percent: Int) {
        let g = KeySoundSynth.gain(forPercent: percent)
        configure { [self] in
            gain = g
            engine?.mainMixerNode.outputVolume = g
        }
    }

    /// Chọn kiểu (giá trị `keySoundStyle`). Đổi ⇒ bộ mẫu dựng lại ở lần khởi động kế tiếp.
    func setStyle(_ raw: String, customURL: URL? = KeySoundCustom.fileURL) {
        configure { [self] in
            styleRaw = raw
            self.customURL = customURL
        }
    }

    /// Dựng + khởi động engine NỀN (không chặn lúc bàn phím hiện).
    func prepare() {
        configure { [self] in
            guard KeySoundStyle.needsEngine(styleRaw) else { return }   // kiểu "iOS": click hệ thống, không engine
            wanted = true
            let ready = running && builtKey == KeySoundCustom.bankKey(style: styleRaw, customURL: customURL)
            if !ready { queue.async { [self] in _ = startNow() } }
        }
    }

    /// Dừng + nhả engine/buffer (ẩn bàn phím, thiếu RAM, tắt setting).
    func shutdown() {
        configure { [self] in
            wanted = false
            if engine != nil { queue.async { [self] in stopNow() } }
        }
    }

    #if DEBUG
    /// Test: giữ `lock` như startNow đang dựng engine (đo main không bị chặn).
    func debugHoldLock(for seconds: TimeInterval) {
        queue.async { [self] in lock.lock(); Thread.sleep(forTimeInterval: seconds); lock.unlock() }
    }
    /// Test: chờ queue xong (mọi cấu hình xếp hàng đã áp).
    func debugDrain() { queue.sync {} }
    var debugStyleRaw: String { lock.lock(); defer { lock.unlock() }; return styleRaw }
    var debugGain: Float { lock.lock(); defer { lock.unlock() }; return gain }
    #endif

    /// Phát ngay (gọi ở touch-down trên main). false = engine chưa sẵn sàng (bỏ tiếng này,
    /// KHÔNG chờ — trừ khi khởi động lại kịp trong lateWindow). Không cấp phát ở đường nóng.
    @discardableResult
    func play(_ kind: KeySoundKind) -> Bool {
        guard lock.try() else { return false }   // queue đang start/stop — bỏ 1 tiếng, không chặn main
        defer { lock.unlock() }
        let now = CACurrentMediaTime()
        lastPlay = now
        guard wanted else { return false }
        guard running, let e = engine, e.isRunning else {
            // Nghỉ (pin), bị ngắt (cuộc gọi, Siri…) hoặc đổi route: dựng lại nền.
            running = false
            pending = (kind, now)
            if !restarting {
                restarting = true
                queue.async { [self] in _ = startNow() }
            }
            return false
        }
        if pianoMode { return playPianoLocked(Self.pianoEvent(for: kind), sustain: false, now: now) }
        nodes[kind.rawValue].scheduleBuffer(buffers[kind.rawValue], at: nil, options: .interrupts, completionHandler: nil)
        return true
    }

    /// Enter: kiểu có tiếng Enter riêng (Máy chữ: "ding") ⇒ phát nó trên node phím chức năng; còn lại = `play(.modifier)`.
    @discardableResult
    func playReturn() -> Bool {
        guard lock.try() else { return false }
        let ret = returnBuffer
        let ready = ret != nil && wanted && running && !pianoMode && engine?.isRunning == true
        if ready, let ret {
            defer { lock.unlock() }
            lastPlay = CACurrentMediaTime()
            nodes[KeySoundKind.modifier.rawValue].scheduleBuffer(ret, at: nil, options: .interrupts, completionHandler: nil)
            return true
        }
        lock.unlock()
        return play(.modifier)
    }

    /// Theme Đập chuột đang bật ⇒ dựng mẫu "éc" (~5.7k mẫu) cùng engine; tắt ⇒ nhả. Theme khác: không gọi.
    func setSqueakEnabled(_ on: Bool) {
        configure { [self] in
            squeakWanted = on
            if !on { squeakBuffer = nil }
            if on && engine != nil && squeakBuffer == nil {
                queue.async { [self] in lock.lock(); buildSqueakLocked(); lock.unlock() }
            }
        }
    }

    private func buildSqueakLocked() {
        guard squeakWanted, squeakBuffer == nil,
              let fmt = AVAudioFormat(standardFormatWithSampleRate: KeySoundSynth.sampleRate, channels: 1) else { return }
        squeakBuffer = Self.pcm(KeySoundSynth.squeakSamples(), fmt)
    }

    /// "Éc" khi đập trúng chuột — node phím chức năng (phím chữ vừa kêu ở node chữ, không cắt nhau). Engine chưa
    /// chạy / chưa có mẫu ⇒ bỏ (không chờ). Không cấp phát.
    @discardableResult
    func playSqueak() -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        guard wanted, running, engine?.isRunning == true, let b = squeakBuffer,
              nodes.count > KeySoundKind.modifier.rawValue else { return false }
        lastPlay = CACurrentMediaTime()
        nodes[KeySoundKind.modifier.rawValue].scheduleBuffer(b, at: nil, options: .interrupts, completionHandler: nil)
        return true
    }

    /// Đã dựng mẫu "éc" (test).
    var hasSqueak: Bool { lock.lock(); defer { lock.unlock() }; return squeakBuffer != nil }

    /// Kiểu đang dựng có tiếng Enter riêng (test).
    var hasReturnSound: Bool { lock.lock(); defer { lock.unlock() }; return returnBuffer != nil }

    /// Loại phím không mang nhãn (emoji, mẫu câu, 123, 🌐…) ⇒ sự kiện piano.
    static func pianoEvent(for kind: KeySoundKind) -> PianoEvent {
        switch kind {
        case .letter: return .note(PianoMap.fallbackBase)
        case .delete: return .delete
        case .modifier: return .note(PianoMap.modifierNote)
        }
    }

    /// Piano: phát một sự kiện (touch-down trên main). `sustain` = pedal đang xuống. Chỉ lên lịch,
    /// không cấp phát. Nhiều phím cùng khung hình ⇒ mỗi phím một giọng riêng (không gộp/bỏ).
    @discardableResult
    func playPiano(_ ev: PianoEvent, sustain: Bool) -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        let now = CACurrentMediaTime()
        lastPlay = now
        guard wanted, pianoMode else { return false }
        guard running, let e = engine, e.isRunning else {
            running = false
            if !restarting {
                restarting = true
                queue.async { [self] in _ = startNow() }
            }
            return false
        }
        return playPianoLocked(ev, sustain: sustain, now: now)
    }

    private func playPianoLocked(_ ev: PianoEvent, sustain: Bool, now: TimeInterval) -> Bool {
        var buf: AVAudioPCMBuffer?
        var useSustain = false
        switch ev {
        case .note(let m):
            guard m >= 0 && m < 128 else { return false }
            if sustain {
                if sustainReady, let b = sustainBuf[m] { buf = b; useSustain = true }
                else { kickSustainBuildLocked() }
            }
            if buf == nil { buf = pianoBuf[m] }
        case .space: buf = pianoExtra.count > 0 ? pianoExtra[0] : nil
        case .chord(let i): buf = i >= 0 && 4 + i < pianoExtra.count ? pianoExtra[4 + i] : (pianoExtra.count > 0 ? pianoExtra[0] : nil)
        case .returnKey: buf = pianoExtra.count > 1 ? pianoExtra[1] : nil
        case .delete: buf = pianoExtra.count > 2 ? pianoExtra[2] : nil
        case .pedal:
            buf = pianoExtra.count > 3 ? pianoExtra[3] : nil
            kickSustainBuildLocked()
        }
        guard let b = buf else { return false }
        let ns = useSustain ? sustainNodes : pianoNodes
        guard ns.count == PianoSynth.voices else { return false }
        let v: Int
        let scale: Float
        if useSustain {
            v = sustainPool.allocate(now: now)
            scale = VoicePool.chordScale(sustainPool.simultaneous(now: now))
            for i in 0..<ns.count where sustainPool.isRecent(i, now: now) { ns[i].volume = scale }
        } else {
            v = pianoPool.allocate(now: now)
            scale = VoicePool.chordScale(pianoPool.simultaneous(now: now))
            for i in 0..<ns.count where pianoPool.isRecent(i, now: now) { ns[i].volume = scale }
        }
        ns[v].scheduleBuffer(b, at: nil, options: .interrupts, completionHandler: nil)
        lastPianoVoice = v + (useSustain ? PianoSynth.voices : 0)
        return true
    }

    /// Số buffer âm đặc biệt đang dựng (cách, Enter, ⌫, pedal + hợp âm vòng) — test.
    var pianoExtraCount: Int { lock.lock(); defer { lock.unlock() }; return pianoExtra.count }

    /// Số giọng piano vừa bắt đầu trong cửa sổ hợp âm (test).
    var pianoSimultaneous: Int {
        lock.lock(); defer { lock.unlock() }
        return pianoPool.simultaneous(now: CACurrentMediaTime())
    }

    /// Tắt Caps (nhả pedal): nốt đang ngân tắt nhanh (~90 ms, 3 nấc âm lượng) thay vì ngân tiếp.
    func damper() {
        queue.async { [self] in
            lock.lock(); defer { lock.unlock() }
            guard pianoMode, running else { return }
            for n in sustainNodes { n.volume = min(n.volume, 0.35) }
            queue.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                for n in self.sustainNodes { n.volume = min(n.volume, 0.12) }
            }
            queue.asyncAfter(deadline: .now() + 0.09) { [weak self] in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                guard self.running, self.engine?.isRunning == true else { return }
                for n in self.sustainNodes { n.stop(); n.volume = 1; n.play() }
            }
        }
    }

    /// Bộ nốt ngân: dựng NỀN lần đầu đạp pedal (tổng hợp ngoài lock, gắn node trong lock).
    private func kickSustainBuildLocked() {
        guard pianoMode, !sustainReady, !sustainBuilding else { return }
        sustainBuilding = true
        let inst = instrument
        queue.async { [self] in
            let banks = inst.map.notes.map { ($0, inst.note($0, sustain: true)) }
            lock.lock(); defer { lock.unlock() }
            sustainBuilding = false
            guard pianoMode, instrument == inst, let e = engine,
                  let fmt = AVAudioFormat(standardFormatWithSampleRate: PianoSynth.sustainSampleRate, channels: 1) else { return }
            for (m, s) in banks { sustainBuf[m] = Self.pcm(s, fmt) }
            if sustainNodes.isEmpty {
                for _ in 0..<PianoSynth.voices {
                    let n = AVAudioPlayerNode()
                    e.attach(n); e.connect(n, to: e.mainMixerNode, format: fmt)
                    sustainNodes.append(n)
                }
            }
            if e.isRunning { for n in sustainNodes where !n.isPlaying { n.play() } }
            sustainReady = true
        }
    }

    private static func pcm(_ s: [Float], _ fmt: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s.count)),
              let ch = b.floatChannelData?[0] else { return nil }
        s.withUnsafeBufferPointer { ch.update(from: $0.baseAddress!, count: s.count) }
        b.frameLength = AVAudioFrameCount(s.count)
        return b
    }

    /// Dựng bộ nốt thường + pool giọng (trong lock, lúc khởi động engine với kiểu piano / đàn tranh).
    /// Đổi nhạc cụ: bộ ngân của nhạc cụ cũ bỏ (dựng lại lười), node giữ nguyên.
    private func buildPianoLocked(_ e: AVAudioEngine, _ inst: KeyInstrument) -> Bool {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: PianoSynth.sampleRate, channels: 1) else { return false }
        var nb = [AVAudioPCMBuffer?](repeating: nil, count: 128)
        for m in inst.map.notes { nb[m] = Self.pcm(inst.note(m), fmt) }
        // Nhạc cụ có vòng hợp âm: mỗi hợp âm một buffer; "cách" (không theo vòng) = hợp âm 0 (cùng object, không tốn thêm).
        let chords = (0..<inst.map.progression.count).compactMap { Self.pcm(inst.chord($0), fmt) }
        guard chords.count == inst.map.progression.count else { return false }
        let space = chords.first ?? Self.pcm(inst.space(), fmt)
        let rest = [inst.returnChord(), inst.delete(), inst.pedal()].compactMap { Self.pcm($0, fmt) }
        guard let space, rest.count == 3 else { return false }
        let extra = [space] + rest + chords
        if instrument != inst || !pianoMode {
            for n in sustainNodes { n.stop() }
            sustainBuf = [AVAudioPCMBuffer?](repeating: nil, count: 128)
            sustainReady = false
            sustainPool = VoicePool(size: PianoSynth.voices)
        }
        instrument = inst
        pianoBuf = nb; pianoExtra = extra
        if pianoNodes.isEmpty {
            for _ in 0..<PianoSynth.voices {
                let n = AVAudioPlayerNode()
                e.attach(n); e.connect(n, to: e.mainMixerNode, format: fmt)
                pianoNodes.append(n)
            }
        }
        pianoPool = VoicePool(size: PianoSynth.voices)
        return true
    }

    /// Rời kiểu piano: nhả buffer + gỡ node (về đúng chi phí của kiểu 3 tiếng).
    private func releasePianoLocked() {
        if let e = engine { for n in pianoNodes + sustainNodes { n.stop(); e.detach(n) } }
        pianoNodes = []; sustainNodes = []
        pianoBuf = [AVAudioPCMBuffer?](repeating: nil, count: 128)
        sustainBuf = [AVAudioPCMBuffer?](repeating: nil, count: 128)
        pianoExtra = []
        sustainReady = false
        pianoMode = false
    }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }
    /// Engine đã dựng chưa (test: kiểu "iOS" không bao giờ dựng).
    var hasEngine: Bool { lock.lock(); defer { lock.unlock() }; return engine != nil }

    /// Quyết định nghỉ (thuần — test được): true ⇒ dừng ngay; false ⇒ hẹn kiểm lại sau `recheck` giây.
    static func idleDecision(now: TimeInterval, lastPlay: TimeInterval, timeout: TimeInterval) -> (stop: Bool, recheck: TimeInterval) {
        let idle = now - lastPlay
        if idle >= timeout { return (true, 0) }
        return (false, max(0.05, timeout - idle))
    }

    /// Đồng bộ (queue nền hoặc test). true = engine chạy.
    @discardableResult
    func startNow() -> Bool {
        lock.lock(); defer { lock.unlock() }
        defer { restarting = false }
        guard wanted, KeySoundStyle.needsEngine(styleRaw) else { pending = nil; return false }
        let key = KeySoundCustom.bankKey(style: styleRaw, customURL: customURL)
        if running, engine?.isRunning == true, builtKey == key { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: KeySoundSynth.sampleRate, channels: 1)
            else { return false }
            let e = engine ?? AVAudioEngine()
            if engine == nil {
                var ns: [AVAudioPlayerNode] = []
                for _ in KeySoundKind.allCases {
                    let node = AVAudioPlayerNode()
                    e.attach(node)
                    e.connect(node, to: e.mainMixerNode, format: fmt)
                    ns.append(node)
                }
                nodes = ns; engine = e
                configObserver = NotificationCenter.default.addObserver(
                    forName: .AVAudioEngineConfigurationChange, object: e, queue: nil) { [weak self] _ in
                    // Không đụng lock ở đây (có thể đang ở trong start/stop) — dồn về queue.
                    guard let self else { return }
                    self.queue.async { _ = self.startNow() }
                }
            }
            if builtKey != key, let inst = KeyInstrument.of(styleRaw) {
                guard buildPianoLocked(e, inst) else { return false }
                buffers = []; returnBuffer = nil; builtKey = key; activeStyle = inst.style; pianoMode = true
            } else if builtKey != key {
                if pianoMode { releasePianoLocked() }
                let custom = styleRaw == KeySoundStyle.custom.rawValue ? KeySoundCustom.load(customURL) : nil
                let bank = KeySoundSynth.bank(styleRaw, custom: custom)
                var bs: [AVAudioPCMBuffer] = []
                for s in bank.samples {
                    guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s.count)),
                          let ch = b.floatChannelData?[0] else { return false }
                    s.withUnsafeBufferPointer { ch.update(from: $0.baseAddress!, count: s.count) }
                    b.frameLength = AVAudioFrameCount(s.count)
                    bs.append(b)
                }
                buffers = bs; builtKey = key; activeStyle = bank.style
                returnBuffer = KeySoundSynth.returnSamples(bank.style).flatMap { Self.pcm($0, fmt) }
                if bank.style.rawValue != styleRaw { TouchLog.write("keysound: \(styleRaw) thiếu file → \(bank.style.rawValue)") }
            }
            if squeakWanted, squeakBuffer == nil { buildSqueakLocked() }
            e.mainMixerNode.outputVolume = gain
            if !e.isRunning {
                e.prepare()
                try e.start()
            }
            for n in nodes where !n.isPlaying { n.play() }
            for n in pianoNodes + sustainNodes where !n.isPlaying { n.play() }
            running = true
            let now = CACurrentMediaTime()
            if let p = pending, now - p.at <= Self.lateWindow, !pianoMode {
                nodes[p.kind.rawValue].scheduleBuffer(buffers[p.kind.rawValue], at: nil, options: .interrupts, completionHandler: nil)
            }
            pending = nil
            lastPlay = now   // khởi động = hoạt động: đếm 8 s nghỉ từ đây
            scheduleIdleCheckLocked(after: idleTimeout)
            #if DEBUG
            NSLog("VTKB keysound start style=%@ io=%.1fms out=%.1fms", activeStyle.rawValue, session.ioBufferDuration * 1000, session.outputLatency * 1000)
            #endif
            return true
        } catch {
            TouchLog.write("keysound: không khởi động được engine \(error)")
            running = false
            pending = nil
            return false
        }
    }

    private func scheduleIdleCheckLocked(after delay: TimeInterval) {
        guard !idleCheckScheduled else { return }
        idleCheckScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.idleCheck() }
    }

    private func idleCheck() {
        lock.lock(); defer { lock.unlock() }
        idleCheckScheduled = false
        guard running, let e = engine else { return }
        let d = Self.idleDecision(now: CACurrentMediaTime(), lastPlay: lastPlay, timeout: idleTimeout)
        if !d.stop { scheduleIdleCheckLocked(after: d.recheck); return }
        // Nghỉ: giữ node/buffer (khởi động lại nhanh), dừng phần cứng + nhả session.
        running = false
        e.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #if DEBUG
        NSLog("VTKB keysound idle pause")
        #endif
    }

    func stopNow() {
        lock.lock(); defer { lock.unlock() }
        guard !wanted, engine != nil else { return }   // prepare() lại kịp ⇒ giữ engine
        running = false
        pending = nil
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        for n in nodes + pianoNodes + sustainNodes { n.stop() }
        engine?.stop()
        engine = nil; nodes = []; buffers = []; returnBuffer = nil; builtKey = nil; squeakBuffer = nil
        pianoNodes = []; sustainNodes = []; pianoExtra = []; pianoMode = false; sustainReady = false
        pianoBuf = [AVAudioPCMBuffer?](repeating: nil, count: 128)
        sustainBuf = [AVAudioPCMBuffer?](repeating: nil, count: 128)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    #if DEBUG
    /// Test: bật cờ muốn chạy mà không qua queue.
    func debugWant(_ on: Bool) { lock.lock(); wanted = on; lock.unlock() }
    /// Test: chạy kiểm tra nghỉ ngay (đồng bộ).
    func debugIdleCheck() { idleCheck() }
    /// Test: giả lập lần bấm cuối cách đây `ago` giây.
    func debugSetLastPlay(ago: TimeInterval) { lock.lock(); lastPlay = CACurrentMediaTime() - ago; lock.unlock() }
    #endif
}
