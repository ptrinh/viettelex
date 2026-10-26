// "Bạn đồng hành" — view UIKit (khung vector CAShapeLayer). Phần thuần: KeyboardBuddy.swift.
// Android: app/.../ime/BuddyView.kt.
//
// Cây layer: step (dời ngang) → hop (nhún) → tilt (nghiêng quanh chân) → spin (lật ngang) → bộ phận (xoay
// quanh điểm xoay) → mảnh hình. Mỗi layer chỉ một keyPath hoạt ảnh ⇒ ghép không lẫn nhau. Model transform
// luôn = dáng nghỉ (đơn vị), hoạt ảnh là CỘNG DỒN (additive) ⇒ nối mượt bằng một hoạt ảnh bù (cũ − mới → 0).
// Hoạt ảnh vòng dựng sẵn theo bậc / phản ứng (cache), đổi trạng thái chỉ `add` lại; phím thường không đụng layer.
// Hiệu ứng phản ứng (tim, nước mắt, mưa, chữ bay, bong bóng chửi, "!") = pool layer dựng lười lần đầu,
// tối đa BuddyFX.maxParticles hạt, nằm trong ô (clipsToBounds).
import UIKit
import ImageIO

final class BuddyView: UIView {
    let character: BuddyCharacter
    let rig: BuddyRig
    let framing: BuddyFraming
    /// Mùa lễ (trang phục + đạo cụ lễ theo từ) — giải một lần lúc hiện bàn phím; đổi mùa ⇒ dựng view mới.
    let season: BuddySeason?
    /// Kiểu vẽ (BuddyStyle, cài đặt riêng từng nhân vật): Hoạt hình ⇒ ảnh atlas, không trang phục; Vẽ nét ⇒ khung vector.
    let artStyle: BuddyStyle
    /// Chế độ nguồn điện thấp: chỉ dáng tĩnh.
    var lowPower: Bool { didSet { if lowPower != oldValue { forceApply() } } }
    /// Chiều cao nhân vật tối đa (pt) — thanh gợi ý: cao trọn ô (chạm trần strip, tràn xuống hàng phím).
    var maxFigureHeight: CGFloat = 200 { didSet { if maxFigureHeight != oldValue { builtFor = .zero; setNeedsLayout() } } }
    /// Đồng hồ (giây) — test thay bằng giờ giả.
    var clock: () -> Double = { CACurrentMediaTime() }

    private(set) var brain = BuddyBrain()
    private(set) var shown: BuddyPhase = .asleep(zzz: false)
    /// Màu quầng + viền theo nền thanh (BuddyHalo) — đổi theme mới tính lại.
    private var tones: BuddyHalo.Colors
    private let outfit: BuddyOutfit

    private let stage = CALayer()      // khung nhân vật (cắt theo bounds view)
    private let sprite = CALayer()
    private var spriteAtlas: CGImage?
    // Keep at most 3 MiB cached; visible previews retain only their own image.
    private static let atlasCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 3_145_728
        return cache
    }()

    private static func atlas(_ character: BuddyCharacter) -> CGImage? {
        guard character != .off else { return nil }
        let name = "buddy-\(character.rawValue)-v2"
        if let image = atlasCache.object(forKey: name as NSString) { return image }
        guard let url = VTBundleResource.url(name, "png", anchor: BuddyView.self),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
        atlasCache.setObject(image, forKey: name as NSString, cost: image.bytesPerRow * image.height)
        return image
    }

    private func spriteRect(_ frame: Int) -> CGRect {
        let index = BuddySprites.cell(frame)
        let columns = BuddySprites.columns(character)
        let rows = BuddySprites.rows(character)
        return CGRect(x: Double(index % columns) / Double(columns), y: Double(index / columns) / Double(rows),
                      width: 1 / Double(columns), height: 1 / Double(rows))
    }
    private let step = CALayer(), hop = CALayer(), tilt = CALayer(), spin = CALayer()
    private var parts: [BuddyPart: CALayer] = [:]
    /// Quầng: bản sao cây bộ phận (cùng điểm xoay, cùng hoạt ảnh) nằm DƯỚI mọi bộ phận — viền sáng/tối quanh cả dáng.
    private var haloParts: [BuddyPart: CALayer] = [:]
    private var haloShapes: [(CAShapeLayer, BuddyPart, Double, Bool)] = []
    private let sleepHalo = CALayer()
    private let sleepGroup = CALayer()
    private var zLayers: [CAShapeLayer] = []
    private var restOnly: [CALayer] = [], danceOnly: [CALayer] = []
    private var shapes: [(CAShapeLayer, BuddyPiece)] = []

    private var scale: CGFloat = 1
    private var builtFor: CGSize = .zero
    private var loopEpoch = 0.0, loopLen = 1.0, cheerStart = 0.0, idleStart = 0.0
    private var danceSeed = Int.random(in: 0...1_000_000)
    private var danceLoopBase = 0
    private var danceMove = BuddyDance.Move.bounce
    private var loopCache: [Int: [(CALayer, CAAnimation)]] = [:]
    private var cheerAnims: [(CALayer, CAAnimation)]?
    private var idleAnims: [(CALayer, CAAnimation)]?
    private var timer: Timer?
    private var applyQueued = false

    // Phản ứng
    private var reactStart = 0.0
    private var shownSerial = 0
    private var reactAnims: [BuddyReaction: [(CALayer, CAAnimation)]] = [:]
    /// Trái tim ôm trước ngực (thả tim) — trong cây nhảy, đi theo người.
    private let prop = CAShapeLayer()
    private var holidayProps: [BuddyReaction: (CALayer, [(CAShapeLayer, BuddyPiece)])] = [:]
    private var wordHistory: (word: String, prev: String?, prev2: String?)?

    /// Giận: mặt đỏ + lông mày cau (trong đầu).
    private let flush = CAShapeLayer(), brows = CAShapeLayer()
    private var fxShapes: [CAShapeLayer] = []
    private var fxTexts: [CATextLayer] = []
    private var badge: CAShapeLayer?
    private var badgeText: CATextLayer?

    init(character: BuddyCharacter, bar: UInt32, lowPower: Bool, framing: BuddyFraming = .bar, season: BuddySeason? = nil,
         artStyle: BuddyStyle = .defaultValue) {
        self.character = character
        self.rig = BuddyRig.rig(character) ?? BuddyRig.cat
        self.framing = framing
        self.season = season
        self.artStyle = artStyle
        self.outfit = BuddyOutfit.make(artStyle.season(season), character)
        self.tones = BuddyHalo.colors(bar: bar)
        self.lowPower = lowPower
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = true          // không vẽ ra ngoài ô (ô đã gồm phần tràn xuống hàng phím đầu)
        // Hoạt hình: chỉ nạp ảnh atlas (không dựng cây vector); thiếu ảnh ⇒ lùi về vector. Vẽ nét: không nạp ảnh.
        if artStyle == .sprite, let atlas = Self.atlas(character) {
            spriteAtlas = atlas
            sprite.contents = atlas
            sprite.contentsRect = spriteRect(BuddySprites.sleep(character))
            sprite.magnificationFilter = .linear
            sprite.minificationFilter = .linear
            layer.addSublayer(sprite)
            prop.isHidden = true
            prop.fillColor = Self.cg(BuddyFX.heartColor)
            layer.addSublayer(prop)
            return
        }
        layer.addSublayer(stage)
        stage.addSublayer(step); step.addSublayer(hop); hop.addSublayer(tilt); tilt.addSublayer(spin)
        stage.addSublayer(sleepGroup)
        for p in BuddyPart.allCases where p != .sleep {
            let h = CALayer()
            haloParts[p] = h
            spin.addSublayer(h)
        }
        for p in BuddyPart.allCases where p != .sleep {
            let l = CALayer()
            parts[p] = l
            spin.addSublayer(l)
        }
        sleepGroup.addSublayer(sleepHalo)
        // Nhóm quầng theo (bộ phận, bề rộng nét): hình tô ⇒ nét viền + tô kín; nét đơn ⇒ nét của nó.
        var keys: [(BuddyPart, Double, Bool)] = []
        for piece in rig.pieces + outfit.pieces where piece.alpha == 1 {
            let k = Self.haloKey(piece)
            if !keys.contains(where: { $0.0 == piece.part && $0.1 == k.0 && $0.2 == k.1 }) { keys.append((piece.part, k.0, k.1)) }
        }
        for (part, w, filled) in keys {
            let l = CAShapeLayer()
            l.lineJoin = .round; l.lineCap = .round
            haloShapes.append((l, part, w, filled))
            (part == .sleep ? sleepHalo : haloParts[part])?.addSublayer(l)
        }
        for piece in rig.pieces + outfit.pieces {
            let s = CAShapeLayer()
            s.lineCap = .round; s.lineJoin = .round
            shapes.append((s, piece))
            if piece.part == .sleep { sleepGroup.addSublayer(s) } else { parts[piece.part]?.addSublayer(s) }
            switch piece.show {
            case .rest: restOnly.append(s)
            case .dance: danceOnly.append(s)
            case .always: break
            }
        }
        for l in [prop, flush, brows] { l.isHidden = true; l.lineJoin = .round; l.lineCap = .round }
        spin.insertSublayer(prop, above: parts[.body])
        parts[.head]?.addSublayer(flush)
        parts[.head]?.addSublayer(brows)
        for _ in rig.zzz {
            let z = CAShapeLayer()
            z.fillColor = nil; z.lineCap = .round; z.lineJoin = .round
            z.strokeColor = Self.cg(BuddyRig.zColor)
            zLayers.append(z)
            sleepGroup.addSublayer(z)
        }
        applyColors()
        showSleep(true)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { timer?.invalidate() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            danceSeed = Int.random(in: 0...1_000_000)
            forceApply(); schedule(clock())
        }
        else { halt(); wordHistory = nil }
    }

    // MARK: Đầu vào (đường phím)

    /// Một phím vừa gõ. Chỉ ghi giờ + so trạng thái; đổi trạng thái thì áp ở lượt runloop sau.
    func keyPressed() {
        let now = clock()
        brain.press(at: now)
        afterInput(now)
    }

    /// Phím ⌫ (cả lặp khi giữ, xoá theo từ): bộ đếm xoá dồn ⇒ hoảng.
    func deletePressed() {
        let now = clock()
        brain.delete(at: now)
        afterInput(now)
    }

    /// Chọn từ gợi ý ⇒ cổ vũ ngắn.
    func cheer() {
        let now = clock()
        brain.cheer(at: now)
        afterInput(now)
    }

    /// Ranh giới từ: từ vừa chốt ⇒ phản ứng (giận / thả tim / cười / ngạc nhiên / buồn). Tra O(1), chỉ ở ranh giới.
    func wordCommitted(_ word: String, prev: String?, prev2: String? = nil) {
        let prev3 = wordHistory.flatMap { $0.word == prev && $0.prev == prev2 ? $0.prev2 : nil }
        wordHistory = (word, prev, prev2)
        let date = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let active = season ?? BuddySeason.of(year: date.year ?? 0, month: date.month ?? 0, day: date.day ?? 0)
        guard let r = BuddyWords.reaction(word: word, prev: prev, prev2: prev2, prev3: prev3, season: active) else { return }
        react(r)
    }

    func react(_ r: BuddyReaction) {
        let now = clock()
        brain.react(r, at: now)
        afterInput(now)
    }

    @inline(__always) private func afterInput(_ now: Double) {
        let v = BuddyPolicy.visual(brain.phase(at: now), lowPower: lowPower)
        if v != shown || (isReact(v) && brain.reactSerial != shownSerial) { queueApply() }
        if timer == nil { schedule(now) }
    }

    @inline(__always) private func isReact(_ p: BuddyPhase) -> Bool {
        if case .react = p { return true }
        return false
    }

    private func queueApply() {
        guard !applyQueued else { return }
        applyQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyQueued = false
            self.tick()
        }
    }

    /// Áp trạng thái hiện tại + hẹn lần đổi kế.
    func tick() {
        let now = clock()
        apply(brain.phase(at: now), now: now)
        schedule(now)
    }

    private func schedule(_ now: Double) {
        timer?.invalidate(); timer = nil
        var deadline = brain.nextDeadline(after: now)
        if spriteAtlas == nil, case .dancing = shown {
            let index = danceLoopIndex(now)
            let boundary = loopEpoch + Double((index / 2 + 1) * 2 - danceLoopBase) * loopLen
            deadline = min(deadline ?? boundary, boundary)
        }
        guard let d = deadline else { return }
        let t = Timer(timeInterval: max(d - now, 0.01) + 0.01, repeats: false) { [weak self] _ in
            self?.timer = nil
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Ẩn bàn phím / gỡ: dừng hẹn giờ + gỡ hoạt ảnh.
    func halt() {
        timer?.invalidate(); timer = nil
        sprite.removeAllAnimations()
        removeAllAnimations()
    }

    /// Nền thanh gợi ý (RGB đục) — đổi theme / sáng-tối.
    func setBar(_ bar: UInt32) {
        let t = BuddyHalo.colors(bar: bar)
        guard t != tones else { return }
        tones = t
        applyColors()
    }

    /// Khoá nhóm quầng của một mảnh: (bề rộng nét thiết kế, có tô).
    static func haloKey(_ p: BuddyPiece) -> (Double, Bool) {
        p.fill != nil ? (BuddyRig.outlineWidth, true) : (p.width, false)
    }

    private func forceApply() {
        let now = clock()
        let p = brain.phase(at: now)
        shown = .awake == shown ? .asleep(zzz: false) : .awake   // khác ⇒ apply chạy lại
        apply(p, now: now)
    }

    // MARK: Trạng thái → layer

    func apply(_ phase: BuddyPhase, now: Double) {
        let v = BuddyPolicy.visual(phase, lowPower: lowPower)
        var moveChanged = false
        if spriteAtlas == nil, case .dancing(let tier) = v, case .dancing = shown {
            moveChanged = BuddyDance.move(character, tier: tier, loopIndex: danceLoopIndex(now), seed: danceSeed) != danceMove
        }
        guard moveChanged || v != shown || (isReact(v) && brain.reactSerial != shownSerial) else { return }
        let old = displayedPose(now)
        let prev = shown
        shown = v
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if isReact(prev) { stopFX() }
        if spriteAtlas != nil {
            applySprite(v)
            return
        }
        switch v {
        case .asleep(let zzz):
            removeRigAnimations()
            showSleep(true)
            if zzz { startZzz() } else { stopZzz() }
        case .awake:
            stopZzz()
            showSleep(false); showEyes(dance: false)
            removeRigAnimations()
            if !lowPower, let old { addBlend(from: old, to: .rest) }
        case .dancing(let t):
            stopZzz()
            showSleep(false); showEyes(dance: true)
            var p = 0.0
            if case .dancing = prev { p = loopPhase(now); danceLoopBase = danceLoopIndex(now) }
            else { danceLoopBase = 0 }
            danceMove = BuddyDance.move(character, tier: t, loopIndex: danceLoopBase, seed: danceSeed)
            loopLen = BuddyDance.loopLength(t)
            loopEpoch = now - p * loopLen
            removeRigAnimations()
            for (l, a) in loops(t, danceMove) {
                a.beginTime = loopEpoch
                l.add(a, forKey: "loop")
            }
            addBlend(from: old ?? .rest, to: BuddyDance.pose(rig.style, tier: t, p: p, move: danceMove))
        case .idle:
            stopZzz()
            showSleep(false); showEyes(dance: false)
            removeRigAnimations()
            idleStart = now
            for (l, a) in idleLoop() { l.add(a, forKey: "loop") }
            addBlend(from: old ?? .rest, to: BuddyDance.idle(rig.style, p: 0))
        case .cheering:
            stopZzz()
            showSleep(false); showEyes(dance: true)
            removeRigAnimations()
            cheerStart = now
            for (l, a) in cheerLoop() { l.add(a, forKey: "loop") }
            addBlend(from: old ?? .rest, to: .rest)
        case .react(let r):
            stopZzz()
            showSleep(false); showEyes(dance: BuddyDance.happyEyes(r))
            removeRigAnimations()
            reactStart = now
            shownSerial = brain.reactSerial
            for (l, a) in reactLoop(r) { l.add(a, forKey: "loop") }
            addBlend(from: old ?? .rest, to: BuddyDance.react(r, rig.style, f: 0))
            startFX(r)
        }
    }

    private func applySprite(_ phase: BuddyPhase) {
        sprite.removeAllAnimations()
        var frames: [Int] = []
        var duration = 1.0
        var repeats = false
        switch phase {
        case .asleep:
            sprite.contentsRect = spriteRect(BuddySprites.sleep(character))
        case .awake: sprite.contentsRect = spriteRect(BuddySprites.rest(character))
        case .dancing(let tier):
            frames = BuddySprites.dance(character, tier)
            duration = BuddySprites.duration(character, tier)
            repeats = true
        case .idle:
            frames = BuddySprites.idle; duration = BuddySprites.idleDuration; repeats = true
        case .cheering:
            frames = BuddySprites.cheer; duration = BuddyBrain.cheer
        case .react(let reaction):
            shownSerial = brain.reactSerial
            frames = BuddySprites.react; duration = reaction.duration
            startFX(reaction)
        }
        guard !frames.isEmpty else { return }
        sprite.contentsRect = spriteRect(BuddySprites.rest(character))
        let animation = CAKeyframeAnimation(keyPath: "contentsRect")
        animation.values = (frames + [repeats ? frames[0] : frames[frames.count - 1]]).map { NSValue(cgRect: spriteRect($0)) }
        animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.repeatCount = repeats ? .infinity : 0
        sprite.add(animation, forKey: "sprite")
        // Khung lật gương: scale.x = −1 quanh tâm sprite, cùng nhịp rời rạc với contentsRect.
        let seq = frames + [repeats ? frames[0] : frames[frames.count - 1]]
        guard seq.contains(where: BuddySprites.isMirrored) else { return }
        let flip = CAKeyframeAnimation(keyPath: "transform.scale.x")
        flip.values = seq.map { BuddySprites.isMirrored($0) ? -1.0 : 1.0 }
        flip.keyTimes = animation.keyTimes
        flip.calculationMode = .discrete
        flip.duration = duration
        flip.repeatCount = animation.repeatCount
        sprite.add(flip, forKey: "flip")
    }

    /// Dáng đang hiện (để nối mượt); nil = đang ngủ.
    private func displayedPose(_ now: Double) -> BuddyPose? {
        switch shown {
        case .asleep: return nil
        case .awake: return .rest
        case .dancing(let t): return BuddyDance.pose(rig.style, tier: t, p: loopPhase(now), move: danceMove)
        case .idle: return BuddyDance.idle(rig.style, p: (now - idleStart) / BuddyDance.idleLoop)
        case .cheering: return BuddyDance.cheer(rig.style, f: (now - cheerStart) / BuddyBrain.cheer)
        case .react(let r):
            let len = Self.reactLength(r)
            var f = (now - reactStart) / len
            if r == .panic { f -= f.rounded(.down) }
            return BuddyDance.react(r, rig.style, f: f)
        }
    }

    private static func reactLength(_ r: BuddyReaction) -> Double { r == .panic ? 0.5 : r.duration }

    private func danceLoopIndex(_ now: Double) -> Int {
        danceLoopBase + max(0, Int(floor((now - loopEpoch) / loopLen)))
    }

    private func loopPhase(_ now: Double) -> Double {
        let x = (now - loopEpoch) / loopLen
        return x - x.rounded(.down)
    }

    private func showSleep(_ on: Bool) {
        step.isHidden = on
        sleepGroup.isHidden = !on
    }

    private func showEyes(dance: Bool) {
        for l in restOnly { l.isHidden = dance }
        for l in danceOnly { l.isHidden = !dance }
    }

    // MARK: Hoạt ảnh

    /// Kênh → layer + keyPath + hệ số (dời: × tỉ lệ pt).
    private func channels() -> [(WritableKeyPath<BuddyPose, Double>, CALayer, String, Double)] {
        var out: [(WritableKeyPath<BuddyPose, Double>, CALayer, String, Double)] = [
            (\.dx, step, "transform.translation.x", Double(scale)),
            (\.dy, hop, "transform.translation.y", Double(scale)),
            (\.rot, tilt, "transform.rotation.z", 1),
        ]
        for (kp, part) in [(\BuddyPose.head, BuddyPart.head), (\.armL, .armL), (\.armR, .armR), (\.legL, .legL),
                           (\.legR, .legR), (\.tail, .tail)] {
            guard let l = parts[part], rig.pivots[part] != nil else { continue }
            out.append((kp, l, "transform.rotation.z", 1))
            if let h = haloParts[part] { out.append((kp, h, "transform.rotation.z", 1)) }   // quầng xoay cùng
        }
        return out
    }

    private static let samples = 48

    private func sampled(_ n: Int, _ len: Double, repeatForever: Bool, _ pose: (Double) -> BuddyPose)
        -> [(CALayer, CAAnimation)] {
        let poses = (0...n).map { pose(Double($0) / Double(n)) }
        var out: [(CALayer, CAAnimation)] = []
        for (kp, l, path, k) in channels() {
            let vals = poses.map { $0[keyPath: kp] * k }
            guard vals.contains(where: { abs($0) > 1e-4 }) else { continue }
            out.append((l, Self.keyframes(path, vals, len, repeatForever: repeatForever)))
        }
        let sx = poses.map(\.sx)
        if sx.contains(where: { abs($0 - 1) > 1e-4 }) {
            let a = Self.keyframes("transform.scale.x", sx, len, repeatForever: repeatForever)
            a.isAdditive = false
            out.append((spin, a))
        }
        return out
    }

    /// Hoạt ảnh vòng của bậc `t` (dựng một lần, cache).
    private func loops(_ t: Int, _ move: BuddyDance.Move) -> [(CALayer, CAAnimation)] {
        let key = t * BuddyDance.Move.allCases.count + move.rawValue
        if let c = loopCache[key] { return c }
        let out = sampled(Self.samples, BuddyDance.loopLength(t), repeatForever: true) {
            BuddyDance.pose(rig.style, tier: t, p: $0, move: move)
        }
        loopCache[key] = out
        return out
    }

    /// Vòng lắc nhẹ (`.idle`) — dựng một lần, cache như vòng nhảy.
    private func idleLoop() -> [(CALayer, CAAnimation)] {
        if let c = idleAnims { return c }
        let out = sampled(Self.samples, BuddyDance.idleLoop, repeatForever: true) { BuddyDance.idle(rig.style, p: $0) }
        idleAnims = out
        return out
    }

    private func cheerLoop() -> [(CALayer, CAAnimation)] {
        if let c = cheerAnims { return c }
        let out = sampled(24, BuddyBrain.cheer, repeatForever: false) { BuddyDance.cheer(rig.style, f: $0) }
        cheerAnims = out
        return out
    }

    private func reactLoop(_ r: BuddyReaction) -> [(CALayer, CAAnimation)] {
        if let c = reactAnims[r] { return c }
        let out = sampled(r == .panic ? 30 : 48, Self.reactLength(r), repeatForever: r == .panic) {
            BuddyDance.react(r, rig.style, f: $0)
        }
        reactAnims[r] = out
        return out
    }

    private static func keyframes(_ path: String, _ vals: [Double], _ dur: Double, repeatForever: Bool) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: path)
        a.values = vals
        a.duration = dur
        a.calculationMode = .linear
        a.isAdditive = true
        a.repeatCount = repeatForever ? .infinity : 1
        a.isRemovedOnCompletion = true
        return a
    }

    /// Nối mượt: hoạt ảnh bù cộng dồn (cũ − mới → 0) trong `BuddyDance.blend` giây.
    private func addBlend(from old: BuddyPose, to new: BuddyPose) {
        for (kp, l, path, k) in channels() {
            let d = (old[keyPath: kp] - new[keyPath: kp]) * k
            guard abs(d) > 1e-3 else { continue }
            let a = CABasicAnimation(keyPath: path)
            a.fromValue = d
            a.toValue = 0
            a.duration = BuddyDance.blend
            a.isAdditive = true
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            l.add(a, forKey: "blend")
        }
    }

    private func removeRigAnimations() {
        for l in [step, hop, tilt, spin] { l.removeAllAnimations() }
        for (_, l) in parts { l.removeAllAnimations() }
        for (_, l) in haloParts { l.removeAllAnimations() }
    }

    private func removeAllAnimations() {
        sprite.removeAllAnimations()
        removeRigAnimations()
        stopZzz()
        stopFX()
    }

    /// "z z Z" lần lượt hiện + bay nhẹ lên, chạy một lượt (`BuddyBrain.zzz` giây) — rồi gỡ ở mốc kế.
    private func startZzz() {
        let n = Double(zLayers.count)
        for (i, z) in zLayers.enumerated() {
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            let a = Double(i) / n, b = (Double(i) + 1) / n
            fade.values = [0, 0, 1, 1]
            fade.keyTimes = [0, NSNumber(value: a * 0.8), NSNumber(value: b * 0.8), 1]
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = 4 * scale; rise.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [fade, rise]
            g.duration = BuddyBrain.zzz
            z.add(g, forKey: "zzz")
        }
    }

    private func stopZzz() {
        for z in zLayers { z.removeAllAnimations() }
    }

    // MARK: Hiệu ứng phản ứng

    private func holidayProp(_ reaction: BuddyReaction) -> CALayer {
        if let cached = holidayProps[reaction] { return cached.0 }
        let group = CALayer()
        let shapes = BuddyProp.make(reaction, rig).map { piece -> (CAShapeLayer, BuddyPiece) in
            let l = CAShapeLayer()
            l.lineCap = .round; l.lineJoin = .round
            group.addSublayer(l)
            return (l, piece)
        }
        if spriteAtlas != nil { layer.addSublayer(group) }
        else { spin.insertSublayer(group, above: parts[.armR]) }
        holidayProps[reaction] = (group, shapes)
        layoutHolidayProps()
        return group
    }

    private func layoutHolidayProps() {
        guard !holidayProps.isEmpty else { return }
        let hp = rig.heart, vp = rig.viewport(framing)
        let s = spriteAtlas == nil ? scale : prop.bounds.width / CGFloat(hp.size * 2)
        let center = spriteAtlas == nil
            ? CGPoint(x: CGFloat(hp.x - vp.x) * s, y: CGFloat(hp.y - vp.y) * s)
            : prop.position
        for (group, shapes) in holidayProps.values {
            group.position = center
            for (l, piece) in shapes {
                l.path = Self.path(piece, origin: (hp.x, hp.y), scale: s)
                l.lineWidth = CGFloat(piece.width) * s
                l.fillColor = piece.fill.map { Self.cg($0, alpha: piece.alpha) }
                switch piece.stroke {
                case .none: l.strokeColor = nil
                case .outline: l.strokeColor = Self.cg(tones.outline)
                case .ink: l.strokeColor = Self.cg(BuddyRig.ink)
                case .color(let c): l.strokeColor = Self.cg(c)
                }
            }
        }
    }

    private func startFX(_ r: BuddyReaction) {
        let w = Double(bounds.width), h = Double(bounds.height)
        guard w > 0, h > 0 else { return }
        let dur = r.duration
        switch r {
        case .luckyMoney, .gift, .candy, .mooncake:
            let group = holidayProp(r)
            group.isHidden = false
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [0.2, 1.15, 0.95, 1.1, 1, 1.1, 0.2]
            pulse.keyTimes = [0, 0.15, 0.3, 0.45, 0.6, 0.8, 1]
            pulse.duration = dur
            group.add(pulse, forKey: "fx")
        case .love:
            prop.isHidden = false
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [0.2, 1.15, 0.95, 1.1, 1, 1.1, 0.2]
            pulse.keyTimes = [0, 0.15, 0.3, 0.45, 0.6, 0.8, 1]
            pulse.duration = dur
            prop.add(pulse, forKey: "fx")
        case .angry:
            flush.isHidden = false; brows.isHidden = false
            let blush = CAKeyframeAnimation(keyPath: "opacity")
            blush.values = [0, 1, 1, 0]
            blush.keyTimes = [0, 0.15, 0.8, 1]
            blush.duration = dur
            flush.add(blush, forKey: "fx")
            showBadge(r, w: w, h: h, text: BuddyWords.grawlix(seed: brain.reactSerial), dur: dur)
        case .surprised:
            showBadge(r, w: w, h: h, text: "!", dur: dur)
        case .sad:
            showBadge(r, w: w, h: h, text: nil, dur: dur)
        case .laugh, .panic:
            break
        }
        let n = min(BuddyFX.count(r), BuddyFX.maxParticles)
        guard n > 0 else { return }
        let k = BuddyFX.particleSize / 2
        for i in 0..<n {
            let p = BuddyFX.particle(r, i, width: w, height: h)
            let l: CALayer
            if r == .panic {
                let t = fxText(i)
                t.string = BuddyFX.panicGlyphs[i % BuddyFX.panicGlyphs.count]
                t.foregroundColor = Self.cg(tones.halo)
                l = t
            } else {
                let s = fxShape(i)
                let d = r == .love ? BuddyFX.heartPath(cx: k, cy: k, k: k * 0.85) : BuddyFX.dropPath(cx: k, cy: k, k: k * 0.8)
                s.path = Self.svg(d, origin: (0, 0), scale: 1)
                s.fillColor = Self.cg(r == .love ? BuddyFX.heartColor : r == .sad ? BuddyFX.rainColor : BuddyFX.tearColor)
                l = s
            }
            l.isHidden = false
            l.position = CGPoint(x: p.x1, y: p.y1)
            l.opacity = 0
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = CGPoint(x: p.x0, y: p.y0)
            move.toValue = CGPoint(x: p.x1, y: p.y1)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.15, 0.6, 1]
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.4; grow.toValue = 1.1
            let g = CAAnimationGroup()
            g.animations = [move, fade, grow]
            g.duration = BuddyFX.particleDuration
            g.repeatCount = r == .panic ? 30 : 1    // hoảng kéo dài tới khi thôi xoá (gỡ ở stopFX)
            g.beginTime = CACurrentMediaTime() + p.delay
            g.fillMode = .backwards
            l.add(g, forKey: "fx")
        }
    }

    /// Bong bóng chửi / "!" / mây: bật ra (0,15 s) rồi tắt dần ở cuối.
    private func showBadge(_ r: BuddyReaction, w: Double, h: Double, text: String?, dur: Double) {
        guard let rect = BuddyFX.badge(r, width: w, height: h) else { return }
        let b = badge ?? { let s = CAShapeLayer(); s.lineJoin = .round; layer.addSublayer(s); badge = s; return s }()
        let t = badgeText ?? {
            let x = CATextLayer()
            x.alignmentMode = .center
            x.contentsScale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
            x.font = "HelveticaNeue-Bold" as CFString
            layer.addSublayer(x)
            badgeText = x
            return x
        }()
        let frame = CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
        b.frame = frame
        let local = CGRect(origin: .zero, size: frame.size)
        switch r {
        case .angry:
            b.path = UIBezierPath(roundedRect: local.insetBy(dx: 0.75, dy: 0.75), cornerRadius: local.height / 2).cgPath
            b.fillColor = Self.cg(0xFFFFFF)
            b.strokeColor = Self.cg(BuddyFX.angryRed)
            b.lineWidth = 1
        case .sad:
            b.path = Self.svg(BuddyFX.cloudPath(BuddyRect(x: 0, y: 0, w: rect.w, h: rect.h)), origin: (0, 0), scale: 1)
            b.fillColor = Self.cg(BuddyFX.cloudColor)
            b.strokeColor = nil
        default:
            b.path = nil
        }
        b.isHidden = b.path == nil
        if let text {
            t.isHidden = false
            t.string = text
            t.fontSize = r == .surprised ? frame.height * 0.95 : frame.height * 0.72
            t.foregroundColor = Self.cg(BuddyFX.angryRed)
            t.frame = CGRect(x: frame.minX, y: frame.minY + (r == .surprised ? -1 : frame.height * 0.06),
                             width: frame.width, height: frame.height + 2)
        } else {
            t.isHidden = true
        }
        for l in [b, t] as [CALayer] where !l.isHidden {
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.3, 1.1, 1, 1]
            pop.keyTimes = [0, 0.12, 0.2, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.1, 0.75, 1]
            let g = CAAnimationGroup()
            g.animations = [pop, fade]
            g.duration = dur
            l.opacity = 0
            l.add(g, forKey: "fx")
        }
    }

    private func fxShape(_ i: Int) -> CAShapeLayer {
        while fxShapes.count <= i {
            let k = BuddyFX.particleSize / 2
            let s = CAShapeLayer()
            s.bounds = CGRect(x: 0, y: 0, width: 2 * k, height: 2 * k)
            s.opacity = 0
            layer.addSublayer(s)
            fxShapes.append(s)
        }
        return fxShapes[i]
    }

    private func fxText(_ i: Int) -> CATextLayer {
        while fxTexts.count <= i {
            let t = CATextLayer()
            t.bounds = CGRect(x: 0, y: 0, width: 9, height: 10)
            t.fontSize = 8
            t.font = "HelveticaNeue-Bold" as CFString
            t.alignmentMode = .center
            t.contentsScale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
            t.opacity = 0
            layer.addSublayer(t)
            fxTexts.append(t)
        }
        return fxTexts[i]
    }

    private func stopFX() {
        for (group, _) in holidayProps.values { group.removeAllAnimations(); group.isHidden = true }
        for l in [prop, flush, brows] as [CALayer] { l.removeAllAnimations(); l.isHidden = true }
        for l in fxShapes as [CALayer] + fxTexts { l.removeAllAnimations(); l.opacity = 0 }
        for l in [badge, badgeText].compactMap({ $0 }) as [CALayer] { l.removeAllAnimations(); l.opacity = 0; l.isHidden = true }
    }

    // MARK: Hình

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != builtFor, bounds.width > 0, bounds.height > 0 else { return }
        builtFor = bounds.size
        build()
    }

    /// Dựng path theo cỡ view (chỉ khi cỡ đổi). Nhân vật đứng đáy ô, giữa ngang.
    private func build() {
        if let atlas = spriteAtlas {
            let rows = BuddySprites.rows(character)
            let columns = BuddySprites.columns(character)
            let aspect = CGFloat(atlas.width) / CGFloat(atlas.height) * CGFloat(rows) / CGFloat(columns)
            // Cao trọn ô (chạm trần strip); ô ảnh rộng hơn ô nhân vật thì cắt lề trong suốt hai bên (clipsToBounds).
            let h = min(bounds.height, maxFigureHeight)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            sprite.frame = CGRect(x: (bounds.width - h * aspect) / 2, y: bounds.height - h,
                                  width: h * aspect, height: h)
            let heartSize = h * 0.18
            prop.frame = CGRect(x: bounds.midX - heartSize / 2, y: sprite.frame.minY + h * 0.45,
                                width: heartSize, height: heartSize)
            prop.path = Self.svg(BuddyFX.heartPath(cx: Double(heartSize / 2), cy: Double(heartSize / 2),
                                                 k: Double(heartSize / 2)), origin: (0, 0), scale: 1)
            layoutHolidayProps()
            CATransaction.commit()
            return
        }
        let vp = rig.viewport(framing)
        let h = min(bounds.height - 1, maxFigureHeight)
        let s = min(h / CGFloat(vp.h), bounds.width / CGFloat(vp.w))
        scale = s
        let size = CGSize(width: CGFloat(vp.w) * s, height: CGFloat(vp.h) * s)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        stage.frame = CGRect(x: (bounds.width - size.width) / 2, y: bounds.height - size.height, width: size.width,
                             height: size.height)
        let box = CGRect(origin: .zero, size: size)
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: CGFloat(x - vp.x) * s, y: CGFloat(y - vp.y) * s)
        }
        for l in [step, hop, sleepGroup] { l.frame = box }
        let feet = pt(rig.feet.x, rig.feet.y)
        for l in [tilt, spin] { pin(l, box, at: feet) }
        for (p, l) in parts {
            let v = rig.pivots[p] ?? (rig.feet.x, rig.feet.y)
            pin(l, box, at: pt(v.x, v.y))
            if let h = haloParts[p] { pin(h, box, at: pt(v.x, v.y)) }
        }
        sleepHalo.frame = box
        let sleepDy = rig.sleepOffset(framing)
        for (layer, piece) in shapes {
            layer.frame = box
            let dy = piece.part == .sleep ? sleepDy : 0
            layer.path = Self.path(piece, origin: (vp.x, vp.y - dy), scale: s)
            layer.lineWidth = CGFloat(piece.width) * s
        }
        for (z, spec) in zip(zLayers, rig.zzz) {
            z.frame = box
            z.path = Self.svg(BuddyRig.zPath(x: spec.x, y: spec.y, size: spec.size), origin: (vp.x, vp.y - sleepDy), scale: s)
            z.lineWidth = 4.5 * s
        }
        // Quầng: gộp path các mảnh cùng nhóm, nét rộng hơn viền đúng `BuddyHalo.width` pt mỗi bên.
        for (l, part, w, filled) in haloShapes {
            let m = CGMutablePath()
            let dy = part == .sleep ? sleepDy : 0
            for (_, piece) in shapes where piece.part == part && piece.alpha == 1 {
                let k = Self.haloKey(piece)
                guard k.0 == w, k.1 == filled else { continue }
                m.addPath(Self.path(piece, origin: (vp.x, vp.y - dy), scale: s))
            }
            l.frame = box
            l.path = m
            l.lineWidth = CGFloat(w) * s + CGFloat(2 * BuddyHalo.width)
        }
        let hp = rig.heart
        prop.frame = box
        prop.path = Self.svg(BuddyFX.heartPath(cx: hp.x, cy: hp.y, k: hp.size), origin: (vp.x, vp.y), scale: s)
        prop.lineWidth = CGFloat(BuddyRig.outlineWidth) * s
        let hc = pt(hp.x, hp.y)
        prop.anchorPoint = CGPoint(x: hc.x / max(box.width, 1), y: hc.y / max(box.height, 1))
        prop.position = hc
        // Giận: mặt đỏ + lông mày (toạ độ đầu — cùng khung bộ phận).
        let fc = rig.face
        flush.frame = box
        flush.path = Self.path(BuddyPiece(.head, .ellipse(fc.x, fc.y, fc.rx, fc.ry)), origin: (vp.x, vp.y), scale: s)
        brows.frame = box
        brows.path = Self.svg(rig.brows, origin: (vp.x, vp.y), scale: s)
        brows.lineWidth = 4.5 * s
        layoutHolidayProps()
        // Cỡ đổi ⇒ dời (pt) trong hoạt ảnh đổi: dựng lại.
        loopCache.removeAll(); cheerAnims = nil; reactAnims.removeAll()
        let now = clock()
        let p = shown
        shown = p == .awake ? .asleep(zzz: false) : .awake
        apply(p, now: now)
    }

    private func pin(_ l: CALayer, _ box: CGRect, at p: CGPoint) {
        l.bounds = box
        l.anchorPoint = CGPoint(x: box.width > 0 ? p.x / box.width : 0.5, y: box.height > 0 ? p.y / box.height : 0.5)
        l.position = p
    }

    private func applyColors() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let outline = Self.cg(tones.outline)
        let halo = Self.cg(tones.halo)
        for (l, _, _, filled) in haloShapes { l.strokeColor = halo; l.fillColor = filled ? halo : nil }
        layoutHolidayProps()
        prop.fillColor = Self.cg(BuddyFX.heartColor)
        prop.strokeColor = outline
        flush.fillColor = Self.cg(BuddyFX.angryRed, alpha: 0.45)
        flush.strokeColor = nil
        brows.fillColor = nil
        brows.strokeColor = Self.cg(BuddyRig.ink)
        func re(_ c: UInt32) -> UInt32 { outfit.recolor[c] ?? c }
        for (l, p) in shapes {
            l.fillColor = p.fill.map { Self.cg(re($0), alpha: p.alpha) }
            switch p.stroke {
            case .none: l.strokeColor = nil
            case .outline: l.strokeColor = outline
            case .ink: l.strokeColor = Self.cg(BuddyRig.ink)
            case .color(let c): l.strokeColor = Self.cg(re(c), alpha: p.fill == nil ? p.alpha : 1)
            }
        }
    }

    static func cg(_ rgb: UInt32, alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: CGFloat(alpha))
    }

    static func path(_ p: BuddyPiece, origin: (Double, Double), scale s: CGFloat) -> CGPath {
        let m = CGMutablePath()
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: CGFloat(x - origin.0) * s, y: CGFloat(y - origin.1) * s)
        }
        switch p.shape {
        case .path(let d):
            m.addPath(svg(d, origin: origin, scale: s))
        case .circle(let cx, let cy, let r):
            let c = pt(cx, cy), rr = CGFloat(r) * s
            m.addEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr))
        case .ellipse(let cx, let cy, let rx, let ry):
            let c = pt(cx, cy)
            m.addEllipse(in: CGRect(x: c.x - CGFloat(rx) * s, y: c.y - CGFloat(ry) * s,
                                    width: CGFloat(2 * rx) * s, height: CGFloat(2 * ry) * s))
        case .rrect(let x, let y, let w, let h, let r):
            let o = pt(x, y)
            let rr = min(CGFloat(r) * s, CGFloat(min(w, h)) * s / 2)
            m.addRoundedRect(in: CGRect(x: o.x, y: o.y, width: CGFloat(w) * s, height: CGFloat(h) * s),
                             cornerWidth: rr, cornerHeight: rr)
        }
        guard let t = p.turn else { return m }
        let c = pt(t.cx, t.cy)
        var tr = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(t.deg * .pi / 180))
            .translatedBy(x: -c.x, y: -c.y)
        return m.copy(using: &tr) ?? m
    }

    static func svg(_ d: String, origin: (Double, Double), scale s: CGFloat) -> CGPath {
        let m = CGMutablePath()
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: CGFloat(x - origin.0) * s, y: CGFloat(y - origin.1) * s)
        }
        for c in BuddySVG.parse(d) {
            switch c {
            case .move(let x, let y): m.move(to: pt(x, y))
            case .line(let x, let y): m.addLine(to: pt(x, y))
            case .quad(let cx, let cy, let x, let y): m.addQuadCurve(to: pt(x, y), control: pt(cx, cy))
            case .close: m.closeSubpath()
            }
        }
        return m
    }

    // MARK: Test / xem trước

    /// Số hoạt ảnh đang gắn trên mọi layer (0 khi ngủ yên / đứng yên).
    var runningAnimationCount: Int {
        func count(_ l: CALayer) -> Int { (l.animationKeys()?.count ?? 0) + (l.sublayers ?? []).reduce(0) { $0 + count($1) } }
        return count(layer)
    }
    var layerCount: Int {
        func count(_ l: CALayer) -> Int { 1 + (l.sublayers ?? []).reduce(0) { $0 + count($1) } }
        return count(layer)
    }
    var hasPendingTimer: Bool { timer != nil }
    /// Khung nhân vật trong view (pt).
    var figureFrame: CGRect { spriteAtlas != nil ? sprite.frame : stage.frame }
    /// Hạt hiệu ứng đã dựng (pool) + "biển" đang hiện.
    var fxParticles: [CALayer] { fxShapes as [CALayer] + fxTexts }
    var fxBadgeFrame: CGRect? { badge.flatMap { $0.isHidden && badgeText?.isHidden != false ? nil : $0.frame } }
    var fxBadgeText: String? { badgeText?.isHidden == false ? badgeText?.string as? String : nil }
    var heartPropVisible: Bool { !prop.isHidden }
    var angryFaceVisible: Bool { !flush.isHidden }
    /// Mảnh trang phục đang gắn.
    var outfitPieceCount: Int { outfit.pieces.count }

    /// Xem trước / ảnh chụp: đặt dáng TĨNH (model transform, không hoạt ảnh) — `render(in:)` vẽ đúng dáng này.
    func debugPose(_ pose: BuddyPose?, dance: Bool = true, heart: Bool = false, angry: Bool = false) {
        layoutIfNeeded()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        removeAllAnimations()
        if spriteAtlas != nil {
            sprite.contentsRect = spriteRect(pose == nil
                ? BuddySprites.sleep(character)
                : (dance ? 1 : BuddySprites.rest(character)))
            prop.isHidden = !heart
            return
        }
        prop.isHidden = !heart
        flush.isHidden = !angry; brows.isHidden = !angry
        guard let pose else { showSleep(true); for z in zLayers { z.opacity = 1 }; return }
        showSleep(false); showEyes(dance: dance)
        step.transform = CATransform3DMakeTranslation(CGFloat(pose.dx) * scale, 0, 0)
        hop.transform = CATransform3DMakeTranslation(0, CGFloat(pose.dy) * scale, 0)
        tilt.transform = CATransform3DMakeRotation(CGFloat(pose.rot), 0, 0, 1)
        spin.transform = CATransform3DMakeScale(CGFloat(pose.sx), 1, 1)
        let rot: [BuddyPart: Double] = [.head: pose.head, .armL: pose.armL, .armR: pose.armR, .legL: pose.legL,
                                        .legR: pose.legR, .tail: pose.tail]
        for (p, a) in rot {
            parts[p]?.transform = CATransform3DMakeRotation(CGFloat(a), 0, 0, 1)
            haloParts[p]?.transform = CATransform3DMakeRotation(CGFloat(a), 0, 0, 1)
        }
    }
}

extension KeyboardPalette {
    /// Nền thanh gợi ý (RGB đục) cho quầng nhân vật: nền theme (trộn lên xám bàn phím hệ thống nếu trong suốt).
    var buddyBar: UInt32 {
        let sys = RGBA(hex: isDark ? BuddyHalo.systemDark : BuddyHalo.systemLight)
        let c = background.map { $0.over(sys) } ?? sys
        func b(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return b(c.r) << 16 | b(c.g) << 8 | b(c.b)
    }
}
