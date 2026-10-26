package com.viettelex.keyboard

import java.util.Locale
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/*
 * "Bạn đồng hành" (Keyboard buddy, Plus, Phil 19/10/2026): nhân vật nhỏ ở góc phải thanh gợi ý — gõ thì
 * nhảy (gõ càng nhanh càng sung), ngừng gõ thì lắc nhẹ ~8 s rồi ngủ; phản ứng theo từ vừa chốt (giận / thả tim / cười /
 * ngạc nhiên / buồn), hoảng khi xoá dồn; trang phục mùa lễ. Phần THUẦN — song sinh iOS/Keyboard/KeyboardBuddy.swift:
 * cùng khoá [Keys.KEYBOARD_BUDDY] (`keyboardBuddy`), cùng id, cùng máy trạng thái, cùng bậc, cùng hàm dáng, cùng
 * bảng hình (test số chung [BuddyRig.checksum]).
 *
 * Luật hiệu năng: Tắt (mặc định) / chưa Plus ⇒ IME không tạo view (0 chi phí). Bật: mỗi phím chỉ ghi giờ vào vòng
 * 16 ô + đếm (không cấp phát — trạng thái là object dựng sẵn); ranh giới từ tra bảng O(1). View
 * (app/.../ime/BuddyView) chỉ vẽ khung hình khi có chuyển động; ngủ yên / đứng yên = 0 khung hình.
 * Trình tiết kiệm pin ⇒ chỉ dáng tĩnh.
 */

// MARK: cài đặt

enum class BuddyCharacter(val id: String, val viTitle: String) {
    OFF("off", "Tắt"), // l10n-key
    GIRL("girl", "Cô gái"), // l10n-key
    BOY("boy", "Chàng trai"), // l10n-key
    CAT("cat", "Mèo"), // l10n-key
    CHICK("chick", "Gà con"); // l10n-key

    val title: String get() = tr(viTitle)
    val isPlus: Boolean get() = this != OFF

    companion object {
        val DEFAULT = OFF
        val IDS: Set<String> = entries.map { it.id }.toSet()
        fun of(raw: Any?): BuddyCharacter = entries.firstOrNull { it.id == raw } ?: DEFAULT
    }
}

/**
 * Kiểu vẽ RIÊNG từng nhân vật (Phil 26/10/2026) = iOS BuddyStyle: Hoạt hình = bộ khung hình PNG vẽ sẵn ([BuddySprites],
 * mặc định) / Vẽ nét = khung vector [BuddyRig] (trang phục mùa lễ, đạo cụ lễ theo từ, thêm điệu nhảy). Lưu
 * `buddyStyle.<id nhân vật>` ([Keys.BUDDY_STYLE_PREFIX], cùng khoá + id iOS); IME đọc lần hiện kế như đổi nhân vật.
 * Chỉ nạp tài nguyên của kiểu đang chọn (Hoạt hình: ảnh atlas; Vẽ nét: không ảnh nào).
 */
enum class BuddyStyle(val id: String, val viTitle: String) {
    SPRITE("sprite", "Hoạt hình"), // l10n-key
    VECTOR("vector", "Vẽ nét"); // l10n-key

    val title: String get() = tr(viTitle)

    /** Mùa lễ có hiệu lực: Hoạt hình ⇒ không trang phục (null) kể cả đang mùa lễ. */
    fun season(s: BuddySeason?): BuddySeason? = if (this == VECTOR) s else null

    companion object {
        val DEFAULT = SPRITE
        val IDS: Set<String> = entries.map { it.id }.toSet()
        fun of(raw: Any?): BuddyStyle = entries.firstOrNull { it.id == raw } ?: DEFAULT
        fun key(c: BuddyCharacter): String = Keys.BUDDY_STYLE_PREFIX + c.id
    }
}

/**
 * "Vị trí & cỡ" (Phil 26/10/2026) = iOS BuddyPlacement — CHUNG mọi nhân vật: cỡ 1…10 (5 = cỡ gốc, mỗi nấc ±8 %),
 * lề phải / lề trên −10…+10 dp. IME đọc lúc hiện, khung tính một lần lúc layout (0 việc mỗi phím).
 */
data class BuddyPlacement(
    val size: Int = DEFAULT_SIZE,
    /** Dương = cách mép phải thêm (dời trái); âm = dời phải (có thể bị cắt ở mép). */
    val padRight: Int = 0,
    /** Dương = dời xuống; âm = dời lên. */
    val padTop: Int = 0,
) {
    /** Hệ số cỡ: 1 → 0,68×, 5 → 1×, 10 → 1,40×. */
    val scale: Double get() = 1 + (size - DEFAULT_SIZE) * 0.08

    /** Ô chừa trên strip (dp) theo cỡ + lề phải dương. [base] = ô cỡ gốc. */
    fun zoneWidth(base: Double): Double = Math.round(base * scale).toDouble() + max(0, padRight)

    /**
     * Khung vẽ từ khung cỡ gốc [f]: neo ĐÁY-PHẢI như cũ, cao × [scale], rộng ≥ [minWidth]; to hơn mà đỉnh vượt đỉnh
     * khung gốc (trần bàn phím) ⇒ lớn dần xuống phím. Lề × [unit] (Android px/dp, iOS pt = 1). = iOS frame(standard:).
     */
    fun frame(f: BuddyRect, minWidth: Double, unit: Double = 1.0): BuddyRect {
        val h = Math.round(f.h * scale).toDouble()
        val w = max(minWidth, h)
        val right = f.x + f.w - padRight * unit
        val top = max(f.y, f.maxY - h) + padTop * unit
        return BuddyRect(right - w, top, w, h)
    }

    companion object {
        const val DEFAULT_SIZE = 5
        val SIZE_RANGE = 1..10
        val PAD_RANGE = -10..10
        val STANDARD = BuddyPlacement()
        fun of(size: Any?, padRight: Any?, padTop: Any?): BuddyPlacement = BuddyPlacement(
            ((size as? Number)?.toInt() ?: DEFAULT_SIZE).coerceIn(SIZE_RANGE),
            ((padRight as? Number)?.toInt() ?: 0).coerceIn(PAD_RANGE),
            ((padTop as? Number)?.toInt() ?: 0).coerceIn(PAD_RANGE))
    }
}

/** Cổng Plus: đi cùng quyền giao diện cao cấp (như hiệu ứng khi bấm phím). */
object BuddyGate {
    val allows: Boolean get() = PlusGate.isUnlocked(PlusFeature.PREMIUM_THEMES)
    fun allows(c: BuddyCharacter): Boolean = !c.isPlus || allows
}

object BuddyPolicy {
    /** Tắt / hết Plus ⇒ [BuddyCharacter.OFF] (không tạo view). */
    fun active(setting: BuddyCharacter, plus: Boolean): BuddyCharacter =
        if (setting == BuddyCharacter.OFF || !plus) BuddyCharacter.OFF else setting

    /** Trạng thái HIỂN THỊ: tiết kiệm pin ⇒ chỉ dáng tĩnh (không nhảy / phản ứng / "z z"). */
    fun visual(p: BuddyPhase, lowPower: Boolean): BuddyPhase {
        if (!lowPower) return p
        return when (p) {
            is BuddyPhase.Asleep -> BuddyPhase.Asleep.QUIET
            else -> BuddyPhase.Awake
        }
    }

    fun animates(p: BuddyPhase): Boolean = when (p) {
        is BuddyPhase.Dancing, BuddyPhase.Idle, BuddyPhase.Cheering, is BuddyPhase.React -> true
        is BuddyPhase.Asleep -> p.zzz
        BuddyPhase.Awake -> false
    }
}

// MARK: tốc độ gõ → bậc

/** = iOS BuddyTempo: số phím trong 2 s → bậc 0…3 (ngưỡng như Lửa combo), trễ xuống 2. */
object BuddyTempo {
    const val WINDOW = 2.0
    val THRESHOLDS = intArrayOf(6, 10, 14)
    const val HYSTERESIS = 2
    const val TIERS = 4

    fun raw(n: Int, slack: Int = 0): Int { var lv = 0; for (th in THRESHOLDS) if (n >= th - slack) lv++; return lv }
    fun tier(count: Int, previous: Int): Int = max(raw(count), min(previous, raw(count, HYSTERESIS)))
}

// MARK: máy trạng thái

/** Trạng thái — object dựng sẵn (đường phím không cấp phát). */
sealed class BuddyPhase {
    class Asleep private constructor(val zzz: Boolean) : BuddyPhase() {
        override fun toString() = "Asleep(zzz=$zzz)"
        companion object { val QUIET = Asleep(false); val ZZZ = Asleep(true); fun of(z: Boolean) = if (z) ZZZ else QUIET }
    }
    /** Đứng yên — chỉ còn ở tiết kiệm pin ([BuddyPolicy.visual]). */
    object Awake : BuddyPhase() { override fun toString() = "Awake" }
    /** Vừa ngừng gõ (hết đuôi nhảy, chưa tới [BuddyBrain.SLEEP_AFTER]): lắc hông nhẹ, chậm rồi mới ngủ. */
    object Idle : BuddyPhase() { override fun toString() = "Idle" }
    class Dancing private constructor(val tier: Int) : BuddyPhase() {
        override fun toString() = "Dancing($tier)"
        companion object { private val all = Array(BuddyTempo.TIERS) { Dancing(it) }; fun of(t: Int) = all[t.coerceIn(0, BuddyTempo.TIERS - 1)] }
    }
    object Cheering : BuddyPhase() { override fun toString() = "Cheering" }
    class React private constructor(val reaction: BuddyReaction) : BuddyPhase() {
        override fun toString() = "React($reaction)"
        companion object { private val all = BuddyReaction.entries.map { React(it) }; fun of(r: BuddyReaction) = all[r.ordinal] }
    }
}

/** = iOS BuddyBrain (cùng hằng, cùng luật). */
class BuddyBrain {
    companion object {
        const val TAIL = 0.6
        /** Lắc nhẹ ([BuddyPhase.Idle]) từng này giây sau đuôi nhảy rồi mới ngủ (Phil 26/10/2026). */
        const val IDLE = 8.0
        const val SLEEP_AFTER = TAIL + IDLE
        const val ZZZ = 2.0
        const val CHEER = 0.6
        const val CAPACITY = 16
        const val PANIC_AFTER = 8
        const val DELETE_GAP = 0.5
        private const val NONE = -Double.MAX_VALUE
    }

    private val times = DoubleArray(CAPACITY) { NONE }
    private var head = 0
    var lastKey = NONE; private set
    var tier = 0; private set
    var cheerUntil = NONE; private set
    var reaction: BuddyReaction? = null; private set
    var reactUntil = NONE; private set
    /** Tăng mỗi lần BẮT ĐẦU một phản ứng — liên tiếp ⇒ diễn lại từ đầu (không chồng). */
    var reactSerial = 0; private set
    var deleteRun = 0; private set
    private var lastDelete = NONE

    fun press(t: Double) { deleteRun = 0; tap(t) }

    private fun tap(t: Double) {
        if (t - lastKey > BuddyTempo.WINDOW) resetRing()
        lastKey = t
        times[head] = t
        head = (head + 1) % CAPACITY
        tier = BuddyTempo.tier(count(t), tier)
    }

    fun cheer(t: Double) {
        if (t - lastKey > BuddyTempo.WINDOW) resetRing()
        lastKey = max(lastKey, t)
        cheerUntil = t + CHEER
    }

    /** Phản ứng theo từ — không tính là phím (đang ngủ: thức, diễn xong ngủ tiếp). Mới nhất thắng. */
    fun react(r: BuddyReaction, t: Double) {
        reaction = r
        reactUntil = t + r.duration
        reactSerial++
    }

    /** Phím ⌫ (cả lặp / xoá theo từ): quá [PANIC_AFTER] liên tiếp ⇒ hoảng tới 0,8 s sau phím cuối. */
    fun delete(t: Double) {
        if (t - lastDelete > DELETE_GAP) deleteRun = 0
        lastDelete = t
        deleteRun++
        tap(t)
        if (deleteRun <= PANIC_AFTER) return
        if (!(reaction == BuddyReaction.PANIC && t < reactUntil)) reactSerial++
        reaction = BuddyReaction.PANIC
        reactUntil = t + BuddyReaction.PANIC.duration
    }

    fun count(t: Double): Int { var n = 0; for (x in times) if (x <= t && t - x <= BuddyTempo.WINDOW) n++; return n }

    fun phase(t: Double): BuddyPhase {
        val r = reaction
        if (t < reactUntil && r != null) return BuddyPhase.React.of(r)
        if (lastKey <= NONE) return BuddyPhase.Asleep.QUIET
        if (t < cheerUntil) return BuddyPhase.Cheering
        val dt = t - lastKey
        if (dt < TAIL) return BuddyPhase.Dancing.of(tier)
        if (dt < SLEEP_AFTER) return BuddyPhase.Idle
        return BuddyPhase.Asleep.of(dt < SLEEP_AFTER + ZZZ)
    }

    /** Lúc trạng thái tự đổi (không có phím mới); null = ngủ yên, khỏi hẹn. */
    fun nextDeadline(t: Double): Double? {
        var best: Double? = if (reactUntil > t) reactUntil else null
        if (lastKey <= NONE) return best
        for (d in doubleArrayOf(cheerUntil, lastKey + TAIL, lastKey + SLEEP_AFTER, lastKey + SLEEP_AFTER + ZZZ))
            if (d > t) best = if (best == null) d else min(best, d)
        return best
    }

    private fun resetRing() { times.fill(NONE); head = 0; tier = 0 }
}

// MARK: dáng

/** Kênh chuyển động (đơn vị thiết kế + radian) — = iOS BuddyPose. Biến được (tái dùng mỗi khung hình). */
class BuddyPose(
    var dx: Double = 0.0, var dy: Double = 0.0, var rot: Double = 0.0, var sx: Double = 1.0,
    var head: Double = 0.0, var armL: Double = 0.0, var armR: Double = 0.0, var legL: Double = 0.0,
    var legR: Double = 0.0, var tail: Double = 0.0,
) {
    fun set(o: BuddyPose): BuddyPose {
        dx = o.dx; dy = o.dy; rot = o.rot; sx = o.sx; head = o.head; armL = o.armL; armR = o.armR
        legL = o.legL; legR = o.legR; tail = o.tail; return this
    }
    fun reset(): BuddyPose { dx = 0.0; dy = 0.0; rot = 0.0; sx = 1.0; head = 0.0; armL = 0.0; armR = 0.0; legL = 0.0; legR = 0.0; tail = 0.0; return this }
    fun isRest(eps: Double = 1e-9): Boolean = abs(dx) < eps && abs(dy) < eps && abs(rot) < eps && abs(sx - 1) < eps &&
        abs(head) < eps && abs(armL) < eps && abs(armR) < eps && abs(legL) < eps && abs(legR) < eps && abs(tail) < eps
    override fun equals(other: Any?): Boolean = other is BuddyPose && dx == other.dx && dy == other.dy && rot == other.rot &&
        sx == other.sx && head == other.head && armL == other.armL && armR == other.armR && legL == other.legL &&
        legR == other.legR && tail == other.tail
    override fun hashCode(): Int = (dx + dy * 3 + armL * 7).hashCode()
    override fun toString() = "Pose(dx=$dx dy=$dy rot=$rot sx=$sx head=$head armL=$armL armR=$armR legL=$legL legR=$legR tail=$tail)"
}

object BuddyDance {
    val BEATS = doubleArrayOf(0.62, 0.5, 0.42, 0.36)
    val ENERGY = doubleArrayOf(0.35, 0.6, 0.85, 1.0)
    const val BEATS_PER_LOOP = 4.0
    const val BLEND = 0.25

    fun clamp(t: Int) = t.coerceIn(0, BuddyTempo.TIERS - 1)
    fun loopLength(t: Int) = BEATS[clamp(t)] * BEATS_PER_LOOP
    /** = iOS: lắc nhẹ sau khi ngừng gõ ([BuddyPhase.Idle]) — lắc hông độ sung bậc 0, một vòng chậm [IDLE_LOOP] giây. */
    const val IDLE_LOOP = 4.0
    fun idle(s: Style, p: Double, out: BuddyPose = BuddyPose()): BuddyPose = pose(s, 0, p, out, Move.HIP_SWAY)

    data class Style(val armL: Double, val armR: Double, val armAmp: Double, val alternate: Boolean,
                     val kick: Double, val bounce: Double, val step: Double)

    enum class Move { BOUNCE, HIP_SWAY, WAVE, CLAP, DAB, SKIP, FLOSS_LITE, SPIN, CHICKEN }
    private val calm = listOf(Move.BOUNCE, Move.HIP_SWAY, Move.WAVE, Move.CLAP)
    private val lively = listOf(Move.SKIP, Move.FLOSS_LITE, Move.DAB, Move.CHICKEN)
    private val energetic = lively + Move.SPIN
    fun moves(tier: Int): List<Move> = if (clamp(tier) < 2) calm else if (clamp(tier) == 2) lively else energetic
    fun move(character: BuddyCharacter, tier: Int, loopIndex: Int, seed: Int): Move {
        val pool = moves(tier); val n = pool.size
        val offset = abs(seed % 997) + character.ordinal * 17
        val group = max(0, loopIndex) / 2 % n
        return pool[(offset + group * (n - 1)) % n]
    }

    fun pose(s: Style, tier: Int, p: Double, out: BuddyPose = BuddyPose(), move: Move = Move.BOUNCE): BuddyPose {
        val pp = p - floor(p)
        out.reset()
        if (pp <= 0) return out
        val e = ENERGY[clamp(tier)]; val two = 2 * Math.PI
        val wave = sin(two * pp); val fast = sin(two * pp * 4)
        val beat = pp * 4; val bf = beat - floor(beat)
        val hop = abs(sin(Math.PI * bf))
        val gate = minOf(1.0, pp / 0.08, (1 - pp) / 0.08)
        when (move) {
            Move.BOUNCE -> {
                bounceBase(s, tier, pp, out)
                out.sx = 1.0
            }
            Move.HIP_SWAY -> {
                out.dx = s.step * e * wave
                out.rot = 0.18 * e * wave
                out.armL = -0.45 * e; out.armR = 0.45 * e
                out.head = -0.10 * e * wave
            }
            Move.WAVE -> {
                out.dy = -s.bounce * 0.35 * e * hop
                out.armR = (-2.1 + 0.4 * fast) * e
                out.armL = 0.25 * e
                out.head = 0.12 * e * wave
            }
            Move.CLAP -> {
                val hit = if (floor(beat).toInt() % 2 == 1) hop else 0.0
                out.dy = -s.bounce * 0.25 * e * hop
                out.armL = (-0.2 - 0.85 * hit) * e
                out.armR = (0.2 + 0.85 * hit) * e
                out.head = 0.08 * e * hit
            }
            Move.DAB -> {
                val hit = if (beat >= 3) hop else 0.0
                out.dy = -s.bounce * 0.3 * e * hop
                out.rot = -0.18 * e * hit
                out.head = 0.65 * e * hit
                out.armL = 2.5 * e * hit; out.armR = 0.9 * e * hit
            }
            Move.SKIP -> {
                out.dx = s.step * 0.6 * e * wave
                out.dy = -s.bounce * 1.5 * e * hop
                out.legL = 0.9 * e * max(0.0, wave)
                out.legR = -0.9 * e * max(0.0, -wave)
                out.armL = 0.6 * e * wave; out.armR = 0.6 * e * wave
                out.rot = 0.08 * e * wave
            }
            Move.FLOSS_LITE -> {
                out.dx = -s.step * e * wave
                out.rot = -0.14 * e * wave
                out.armL = 0.85 * e * wave; out.armR = 0.85 * e * wave
                out.head = 0.12 * e * wave
            }
            Move.SPIN -> {
                bounceBase(s, tier, pp, out)
            }
            Move.CHICKEN -> {
                out.dy = -s.bounce * 0.65 * e * hop
                out.armL = (0.9 + 0.55 * fast) * e
                out.armR = -(0.9 + 0.55 * fast) * e
                out.head = 0.25 * e * hop
                out.tail = 0.3 * e * fast
            }
        }
        out.dx *= gate; out.dy *= gate; out.rot *= gate; out.head *= gate
        out.armL *= gate; out.armR *= gate; out.legL *= gate; out.legR *= gate; out.tail *= gate
        return out
    }

    fun bounce(s: Style, tier: Int, p: Double): BuddyPose = pose(s, tier, p, move = Move.BOUNCE)
    fun hipSway(s: Style, tier: Int, p: Double): BuddyPose = pose(s, tier, p, move = Move.HIP_SWAY)
    fun wave(s: Style, tier: Int, p: Double): BuddyPose = pose(s, tier, p, move = Move.WAVE)
    fun clap(s: Style, tier: Int, p: Double): BuddyPose = pose(s, tier, p, move = Move.CLAP)
    fun dab(s: Style, tier: Int, p: Double): BuddyPose = pose(s, tier, p, move = Move.DAB)
    fun skip(s: Style, tier: Int, p: Double): BuddyPose = pose(s, tier, p, move = Move.SKIP)
    fun flossLite(s: Style, tier: Int, p: Double): BuddyPose = pose(s, tier, p, move = Move.FLOSS_LITE)
    fun spin(s: Style, tier: Int, p: Double): BuddyPose = pose(s, tier, p, move = Move.SPIN)
    fun chicken(s: Style, tier: Int, p: Double): BuddyPose = pose(s, tier, p, move = Move.CHICKEN)
    private fun bounceBase(s: Style, tier: Int, p: Double, out: BuddyPose = BuddyPose()): BuddyPose {
        val t = clamp(tier)
        val e = ENERGY[t]
        val pp = p - floor(p)
        val beats = pp * BEATS_PER_LOOP
        val bi = floor(beats).toInt()
        val bf = beats - bi
        val two = 2 * Math.PI
        val s2 = sin(two * pp * 2)
        out.dy = -s.bounce * e * abs(sin(Math.PI * bf))
        out.dx = s.step * e * sin(two * pp)
        out.rot = 0.1 * e * s2
        out.sx = if (t == BuddyTempo.TIERS - 1 && bi == 3) cos(two * bf) else 1.0
        out.head = 0.12 * e * s2
        out.armL = s.armL * e + s.armAmp * e * s2
        out.armR = -(s.armR * e + s.armAmp * e * sin(two * pp * 2 + (if (s.alternate) Math.PI else 0.0)))
        out.legL = s.kick * e * max(0.0, s2)
        out.legR = -s.kick * e * max(0.0, -s2)
        out.tail = 0.35 * e * sin(two * pp * 4)
        return out
    }

    fun cheer(s: Style, f: Double, out: BuddyPose = BuddyPose()): BuddyPose {
        val k = sin(Math.PI * f.coerceIn(0.0, 1.0))
        out.reset()
        out.dy = -s.bounce * 1.4 * k
        out.armL = 2.4 * k; out.armR = -2.4 * k
        out.legL = 0.4 * k; out.legR = -0.4 * k
        out.tail = 0.5 * k
        return out
    }

    /** = iOS BuddyDance.react. */
    fun react(r: BuddyReaction, s: Style, f: Double, out: BuddyPose = BuddyPose()): BuddyPose {
        val ff = f.coerceIn(0.0, 1.0)
        val pi = Math.PI
        val a = if (r == BuddyReaction.PANIC) min(1.0, ff / 0.15 + 1) else minOf(1.0, ff / 0.15, (1 - ff) / 0.15)
        out.reset()
        when (r) {
            BuddyReaction.LOVE, BuddyReaction.LUCKY_MONEY, BuddyReaction.GIFT, BuddyReaction.CANDY, BuddyReaction.MOONCAKE -> {
                out.dy = -s.bounce * 0.5 * a * abs(sin(3 * pi * ff))
                out.armL = -0.55 * a; out.armR = 0.55 * a
                out.head = 0.18 * a * sin(2 * pi * ff)
                out.tail = 0.4 * a * sin(4 * pi * ff)
            }
            BuddyReaction.ANGRY -> {
                val st = sin(6 * pi * ff)
                out.dy = -s.bounce * 0.25 * a * abs(st)
                out.legL = 0.35 * a * max(0.0, st); out.legR = -0.35 * a * max(0.0, -st)
                out.armL = 0.35 * a; out.armR = -0.35 * a
                out.head = 0.12 * a * sin(10 * pi * ff)
                out.tail = -0.4 * a
            }
            BuddyReaction.LAUGH -> {
                out.dx = 2 * a * sin(16 * pi * ff)
                out.dy = -s.bounce * 0.2 * a * abs(sin(8 * pi * ff))
                out.armL = -0.7 * a; out.armR = 0.7 * a
                out.head = 0.1 * a * sin(8 * pi * ff)
                out.tail = 0.3 * a * sin(8 * pi * ff)
            }
            BuddyReaction.SURPRISED -> {
                out.dy = if (ff < 0.4) -s.bounce * 1.6 * sin(pi * ff / 0.4) else 0.0
                out.armL = 1.3 * a; out.armR = -1.3 * a
                out.legL = 0.3 * a; out.legR = -0.3 * a
                out.tail = -0.5 * a
            }
            BuddyReaction.SAD -> {
                out.dy = s.bounce * 0.6 * a
                out.head = 0.3 * a
                out.armL = -0.35 * a; out.armR = 0.35 * a
                out.tail = 0.6 * a
            }
            BuddyReaction.PANIC -> {
                out.dx = 1.5 * a * sin(20 * pi * ff)
                out.armL = 2.6 * a; out.armR = -2.6 * a
                out.head = 0.08 * a * sin(20 * pi * ff)
                out.dy = -s.bounce * 0.15 * a * abs(sin(10 * pi * ff))
            }
        }
        return out
    }

    fun happyEyes(r: BuddyReaction) = r == BuddyReaction.LOVE || r == BuddyReaction.LAUGH || r.isHoliday
}

// MARK: phản ứng theo từ

/** Thứ tự = ƯU TIÊN khi một từ khớp nhiều bảng: giận > thả tim > cười > ngạc nhiên > buồn. = iOS BuddyReaction. */
enum class BuddyReaction(val duration: Double) {
    ANGRY(1.2), LOVE(1.2), LAUGH(1.3), SURPRISED(1.0), SAD(1.5), PANIC(0.8), LUCKY_MONEY(1.5), GIFT(1.5), CANDY(1.5), MOONCAKE(1.5);
    val isHoliday: Boolean get() = this == LUCKY_MONEY || this == GIFT || this == CANDY || this == MOONCAKE
}

/** = iOS BuddyWords: cùng bảng, cùng luật strict / gộp chữ lặp / mẫu cười-buồn. */
object BuddyWords {
    private fun e(f: String, strict: Boolean = false) = f to strict
    val LOVE = listOf(
        e("yêu"), e("iu"), e("thương"), e("nhớ", true), e("love"), e("luv"), e("lub"), e("miss"), e("cưng", true),
        e("thích"), e("crush"), e("tim"), e("hun"), e("thơm", true), e("honey"), e("baby"), e("anh yêu"), e("em yêu"),
        e("thương thương"), e("nhớ nhớ", true), e("muah"), e("chụt", true), e("xoxo"), e("darling"), e("lovely"),
    )
    val LAUGH = listOf(
        e("haha"), e("hihi"), e("hehe"), e("hoho"), e("kkk"), e("kaka"), e("keke"), e("hjhj"), e("lol"), e("lmao"),
        e("rofl"), e("=))"), e(":))"), e("😂"), e("🤣"), e("cười", true),
    )
    val SURPRISED = listOf(
        e("wow"), e("ôi", true), e("trời ơi"), e("omg"), e("ủa", true), e("hả", true), e("what"), e("wtf"),
        e("ồ", true), e("á", true), e("woa"), e("whoa"),
    )
    val SAD = listOf(
        e("buồn"), e("khóc"), e("huhu"), e("hic"), e("hix"), e("sad"), e(":("), e("chán", true), e("mệt mỏi"),
        e("😢"), e("😭"),
    )

    private class Table(e: List<Pair<String, Boolean>>) {
        val exact = e.map { it.first }.toHashSet()
        val folded = e.filter { !it.second }.map { fold(it.first) }.toHashSet()
        val squeezed = folded.map { squeeze(it) }.filter { it.length >= 3 }.toHashSet()
        fun has(k: String): Boolean {
            if (k.isEmpty()) return false
            if (k in exact) return true
            val f = fold(k)
            if (f in folded) return true
            val q = squeeze(f)
            return q.length >= 3 && q in squeezed
        }
    }
    private val tables: List<Pair<BuddyReaction, Table>> by lazy {
        listOf(BuddyReaction.LOVE to Table(LOVE), BuddyReaction.LAUGH to Table(LAUGH),
            BuddyReaction.SURPRISED to Table(SURPRISED), BuddyReaction.SAD to Table(SAD))
    }

    fun fold(s: String): String = EmojiWords.fold(s)

    fun squeeze(s: String): String {
        val b = StringBuilder(s.length)
        var last: Int = -1
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            if (cp != last) b.appendCodePoint(cp)
            last = cp
            i += Character.charCount(cp)
        }
        return b.toString()
    }

    fun clean(s: String): String {
        val t = s.trim().lowercase()
        val letters = t.trim { !it.isLetter() }
        return letters.ifEmpty { t }
    }

    fun isLaughPattern(f: String): Boolean {
        if (f.length >= 3 && f.all { it == 'k' }) return true
        if (f.length >= 3 && (f.startsWith("=)") || f.startsWith(":)")) && f.drop(2).all { it == ')' }) return true
        val units = setOf("ha", "he", "hi", "ho", "hj", "ka", "ke")
        if (f.length < 4) return false
        var i = 0; var n = 0
        while (i + 1 < f.length && f.substring(i, i + 2) in units) { i += 2; n++ }
        return n >= 2 && f.length - i <= 1
    }

    fun isSadPattern(f: String): Boolean {
        if (f.length >= 2 && f.startsWith(":(") && f.drop(2).all { it == '(' }) return true
        for (u in listOf("hu", "hic", "hix")) {
            if (f.length < u.length * 2 || f.length % u.length != 0) continue
            if ((f.indices step u.length).all { f.startsWith(u, it) }) return true
        }
        return false
    }

    /** Phản ứng cho từ vừa chốt — tục / cặp / bộ ba ([SensitiveWords], cùng bảng bộ lọc gợi ý) ⇒ giận, KHÔNG
     *  phụ thuộc công tắc lọc. Null = không. */
    private data class Holiday(val reaction: BuddyReaction, val season: BuddySeason, val names: Table, val generic: Table)
    private val holidays by lazy { listOf(
        Holiday(BuddyReaction.LUCKY_MONEY, BuddySeason.TET, Table(listOf(e("lì xì", false), e("mừng tuổi", false), e("tết", false), e("năm mới", false), e("chúc mừng năm mới", false), e("vạn sự như ý", false), e("happy new year", false))), Table(listOf(e("an khang", false), e("phát tài", false)))),
        Holiday(BuddyReaction.GIFT, BuddySeason.CHRISTMAS, Table(listOf(e("giáng sinh", false), e("noel", false), e("merry christmas", false), e("xmas", false), e("ông già noel", false))), Table(listOf(e("quà", true)))),
        Holiday(BuddyReaction.CANDY, BuddySeason.HALLOWEEN, Table(listOf(e("halloween", false), e("trick or treat", false))), Table(listOf(e("kẹo", true), e("bí ngô", false)))),
        Holiday(BuddyReaction.MOONCAKE, BuddySeason.MID_AUTUMN, Table(listOf(e("trung thu", false), e("bánh trung thu", false), e("rước đèn", false), e("đèn ông sao", false), e("chị hằng", false))), Table(listOf(e("cuội", true)))),
    ) }

    fun holiday(word: String, prev: String?, prev2: String? = null, prev3: String? = null,
                season: BuddySeason? = null): BuddyReaction? {
        val w = clean(word)
        if (w.isEmpty() || w.length > 24) return null
        val candidates = mutableListOf(w)
        var phrase = w
        for (previous in listOf(prev, prev2, prev3)) {
            if (previous == null || clean(previous).isEmpty()) break
            phrase = clean(previous) + " " + phrase
            candidates.add(phrase)
        }
        for (h in holidays) if (candidates.any { h.names.has(it) || (season == h.season && h.generic.has(it)) }) return h.reaction
        return null
    }

    fun reaction(word: String, prev: String?, prev2: String? = null, prev3: String? = null, season: BuddySeason? = null): BuddyReaction? {
        val w = clean(word)
        if (w.isEmpty() || w.length > 24) return null
        val p = prev?.let(::clean)?.ifEmpty { null }
        val p2 = prev2?.let(::clean)?.ifEmpty { null }
        if (w in SensitiveWords.set || SensitiveWords.isPair(p, w) || SensitiveWords.isTriple(p2, p, w)) return BuddyReaction.ANGRY
        holiday(w, p, p2, prev3, season)?.let { return it }
        val f = fold(w)
        for ((r, t) in tables) {
            if (p != null && t.has("$p $w")) return r
            if (t.has(w)) return r
            if (r == BuddyReaction.LAUGH && isLaughPattern(f)) return r
            if (r == BuddyReaction.SAD && isSadPattern(f)) return r
        }
        return null
    }

    val GRAWLIX_SYMBOLS = charArrayOf('#', '$', '%', '&', '*', '!', '@')
    fun grawlix(seed: Int, count: Int = 4): String {
        val r = FxRandom(seed)
        val b = StringBuilder()
        var last = ' '
        while (b.length < count) {
            val c = GRAWLIX_SYMBOLS[min((r.next() * GRAWLIX_SYMBOLS.size).toInt(), GRAWLIX_SYMBOLS.size - 1)]
            if (c == last) continue
            b.append(c); last = c
        }
        return b.toString()
    }
}

/** = iOS BuddyFX: hạt (≤ 8) + "biển" cố định, toạ độ px/pt trong ô nhân vật — luôn trọn trong ô. */
object BuddyFX {
    const val MAX_PARTICLES = 8
    const val PARTICLE_SIZE = 7.0
    const val PARTICLE_DURATION = 1.0
    const val HEART_COLOR = 0xFF5C8A
    const val TEAR_COLOR = 0x6EC6FF
    const val RAIN_COLOR = 0x7FA7D9
    const val CLOUD_COLOR = 0xA9B1BD
    const val ANGRY_RED = 0xFF3B30
    val PANIC_GLYPHS = listOf("a", "b", "c", "x", "?")

    class Particle(val x0: Double, val y0: Double, val x1: Double, val y1: Double, val delay: Double) {
        override fun toString() = "($x0,$y0)->($x1,$y1)+$delay"
    }

    fun count(r: BuddyReaction): Int = when (r) {
        BuddyReaction.LOVE -> 5
        BuddyReaction.LAUGH -> 4
        BuddyReaction.SAD -> 3
        BuddyReaction.PANIC -> 3
        BuddyReaction.ANGRY, BuddyReaction.SURPRISED, BuddyReaction.LUCKY_MONEY, BuddyReaction.GIFT, BuddyReaction.CANDY, BuddyReaction.MOONCAKE -> 0
    }

    fun particle(r: BuddyReaction, i: Int, w: Double, h: Double): Particle {
        val n = count(r)
        val rad = PARTICLE_SIZE / 2
        val t = if (n > 1) i.toDouble() / (n - 1) else 0.5
        val x0: Double; val y0: Double; val x1: Double; val y1: Double; val delay: Double
        when (r) {
            BuddyReaction.LOVE -> {
                x0 = w / 2 + (t - 0.5) * w * 0.3; y0 = h * 0.55
                x1 = rad + (w - 2 * rad) * (0.1 + 0.8 * t); y1 = rad + (h * 0.35) * ((i * 7) % 3) / 2.0
                delay = i * 0.08
            }
            BuddyReaction.LAUGH -> {
                val side = if (i % 2 == 0) -1.0 else 1.0
                x0 = w / 2 + side * w * 0.12; y0 = h * 0.25
                x1 = w / 2 + side * w * (0.36 + 0.06 * (i / 2)); y1 = h * (0.35 + 0.12 * (i / 2))
                delay = i * 0.15
            }
            BuddyReaction.SAD -> {
                x0 = w * (0.3 + 0.2 * i); y0 = h * 0.18; x1 = x0; y1 = h * 0.5; delay = i * 0.3
            }
            BuddyReaction.PANIC -> {
                x0 = w / 2; y0 = h * 0.6; x1 = rad + (w - 2 * rad) * t; y1 = rad + h * 0.1 * (i % 2); delay = i * 0.1
            }
            BuddyReaction.ANGRY, BuddyReaction.SURPRISED, BuddyReaction.LUCKY_MONEY, BuddyReaction.GIFT, BuddyReaction.CANDY, BuddyReaction.MOONCAKE -> { x0 = w / 2; y0 = h / 2; x1 = x0; y1 = y0; delay = 0.0 }
        }
        fun cx(x: Double) = min(max(x, rad), w - rad)
        fun cy(y: Double) = min(max(y, rad), h - rad)
        return Particle(cx(x0), cy(y0), cx(x1), cy(y1), delay)
    }

    fun badge(r: BuddyReaction, w: Double, h: Double): BuddyRect? = when (r) {
        BuddyReaction.ANGRY -> BuddyRect(0.0, 0.0, w, min(13.0, h * 0.32))
        BuddyReaction.SURPRISED -> BuddyRect(w - 9, 1.0, 8.0, min(14.0, h * 0.36))
        BuddyReaction.SAD -> BuddyRect(w * 0.18, 0.0, w * 0.64, min(10.0, h * 0.24))
        else -> null
    }

    private fun f(v: Double) = String.format(Locale.US, "%.2f", v)

    fun heartPath(cx: Double, cy: Double, k: Double): String =
        "M${f(cx)} ${f(cy + k * 0.9)} Q${f(cx - k * 1.4)} ${f(cy + k * 0.1)} ${f(cx - k * 0.8)} ${f(cy - k * 0.6)} " +
            "Q${f(cx - k * 0.3)} ${f(cy - k * 1.1)} ${f(cx)} ${f(cy - k * 0.4)} " +
            "Q${f(cx + k * 0.3)} ${f(cy - k * 1.1)} ${f(cx + k * 0.8)} ${f(cy - k * 0.6)} " +
            "Q${f(cx + k * 1.4)} ${f(cy + k * 0.1)} ${f(cx)} ${f(cy + k * 0.9)} Z"

    fun dropPath(cx: Double, cy: Double, k: Double): String =
        "M${f(cx)} ${f(cy - k)} Q${f(cx + k * 0.9)} ${f(cy + k * 0.2)} ${f(cx)} ${f(cy + k * 0.8)} " +
            "Q${f(cx - k * 0.9)} ${f(cy + k * 0.2)} ${f(cx)} ${f(cy - k)} Z"

    fun cloudPath(b: BuddyRect): String {
        val x = b.x; val y = b.y; val w = b.w; val h = b.h
        return "M${f(x + w * 0.1)} ${f(y + h)} Q${f(x - w * 0.05)} ${f(y + h * 0.5)} ${f(x + w * 0.2)} ${f(y + h * 0.45)} " +
            "Q${f(x + w * 0.3)} ${f(y)} ${f(x + w * 0.55)} ${f(y + h * 0.25)} " +
            "Q${f(x + w * 0.85)} ${f(y)} ${f(x + w * 0.85)} ${f(y + h * 0.5)} " +
            "Q${f(x + w * 1.05)} ${f(y + h * 0.6)} ${f(x + w * 0.9)} ${f(y + h)} Z"
    }
}

// MARK: hình (dữ liệu)

/** Bộ phận — thứ tự vẽ = thứ tự (sau đè trước). = iOS BuddyPart (rawValue = ordinal). */
enum class BuddyPart { TAIL, LEG_L, LEG_R, BODY, ARM_L, ARM_R, HEAD, SLEEP }

sealed class Shape {
    class Path(val d: String) : Shape()
    class Circle(val cx: Double, val cy: Double, val r: Double) : Shape() {
        constructor(cx: Number, cy: Number, r: Number) : this(cx.toDouble(), cy.toDouble(), r.toDouble())
    }
    class Ellipse(val cx: Double, val cy: Double, val rx: Double, val ry: Double) : Shape()
    class RRect(val x: Double, val y: Double, val w: Double, val h: Double, val r: Double) : Shape()
}

sealed class Stroke {
    object None : Stroke()
    /** Viền nhân vật: nâu đậm ở nền sáng, kem ở nền tối. */
    object Outline : Stroke()
    /** Nét mặt: luôn đậm. */
    object Ink : Stroke()
    class Color(val rgb: Int) : Stroke()
}

enum class Show { ALWAYS, REST, DANCE }

class BuddyPiece(
    val part: BuddyPart, val shape: Shape, val fill: Int? = null, val alpha: Double = 1.0,
    val stroke: Stroke = Stroke.Outline, val width: Double = BuddyRig.OUTLINE_WIDTH, val show: Show = Show.ALWAYS,
    /** Xoay mảnh (độ, quanh cx, cy) — chỉ dáng ngủ. */
    val turn: Triple<Double, Double, Double>? = null,
) {
    constructor(part: BuddyPart, shape: Shape, fill: Int? = null, stroke: Stroke = Stroke.Outline, width: Number) :
        this(part, shape, fill, 1.0, stroke, width.toDouble())
}

enum class BuddyFraming { BAR, FULL }

class BuddyRect(val x: Double, val y: Double, val w: Double, val h: Double) {
    constructor(x: Number, y: Number, w: Number, h: Number) : this(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble())
    val maxY: Double get() = y + h
    override fun toString() = "Rect($x,$y,$w,$h)"
}

class P2(val x: Double, val y: Double) { constructor(x: Number, y: Number) : this(x.toDouble(), y.toDouble()) }
class P3(val x: Double, val y: Double, val size: Double) {
    constructor(x: Number, y: Number, s: Number) : this(x.toDouble(), y.toDouble(), s.toDouble())
}
class P4(val x: Double, val y: Double, val rx: Double, val ry: Double) {
    constructor(x: Number, y: Number, rx: Number, ry: Number) : this(x.toDouble(), y.toDouble(), rx.toDouble(), ry.toDouble())
}

/** Bộ khung một nhân vật — toàn bộ là dữ liệu (đơn vị thiết kế, y xuống). = iOS BuddyRig. */
class BuddyRig(
    val pieces: List<BuddyPiece>,
    val pivots: Map<BuddyPart, P2>,
    val full: BuddyRect,
    val barBottom: Double?,
    val feet: P2,
    val sleepBottom: Double,
    val zzz: List<P3>,
    val style: BuddyDance.Style,
    val heart: P3 = P3(0, 46, 11),
    val face: P4 = P4(0, -6, 24, 18),
    val brows: String = "M-16 -25 L-6 -21 M16 -25 L6 -21",
    val hat: P3 = P3(0, -42, 34),
    val sleepHat: P3 = P3(-34, -2, 26),
    val neck: P2 = P2(0, 18),
    val hand: P2 = P2(23, 64),
) {
    constructor(pieces: List<BuddyPiece>, pivots: Map<BuddyPart, P2>, full: BuddyRect, barBottom: Double?, feet: P2,
                sleepBottom: Int, zzz: List<P3>, style: BuddyDance.Style, heart: P3 = P3(0, 46, 11),
                face: P4 = P4(0, -6, 24, 18), brows: String = "M-16 -25 L-6 -21 M16 -25 L6 -21",
                hat: P3 = P3(0, -42, 34), sleepHat: P3 = P3(-34, -2, 26), neck: P2 = P2(0, 18), hand: P2 = P2(23, 64)) :
        this(pieces, pivots, full, barBottom, feet, sleepBottom.toDouble(), zzz, style, heart, face, brows, hat, sleepHat, neck, hand)

    val hasTail: Boolean get() = pieces.any { it.part == BuddyPart.TAIL }

    fun viewport(f: BuddyFraming): BuddyRect {
        val b = barBottom
        if (f != BuddyFraming.BAR || b == null) return full
        return BuddyRect(full.x, full.y, full.w, b - full.y)
    }

    fun sleepOffset(f: BuddyFraming): Double = viewport(f).maxY - 4 - sleepBottom

    companion object {
        const val OUTLINE_WIDTH = 6.0
        const val Z_COLOR = 0x8AA6E8
        const val OUTLINE_LIGHT = 0x3A2A2A
        const val OUTLINE_DARK = 0x4A3A38
        const val INK = 0x3A2A2A
        private const val ink = INK

        fun zPath(x: Double, y: Double, size: Double): String {
            fun n(v: Double) = if (v == floor(v)) v.toLong().toString() + ".0" else v.toString()
            return "M${n(x)} ${n(y)} h${n(size)} l${n(-size)} ${n(size)} h${n(size)}"
        }

        fun rig(c: BuddyCharacter): BuddyRig? = when (c) {
            BuddyCharacter.OFF -> null
            BuddyCharacter.GIRL -> GIRL
            BuddyCharacter.BOY -> BOY
            BuddyCharacter.CAT -> CAT
            BuddyCharacter.CHICK -> CHICK
        }

        /** = iOS BuddyRig.checksum (cùng công thức) — sửa hình một bên mà quên bên kia thì test đỏ. */
        fun checksum(c: BuddyCharacter): Double {
            val r = rig(c) ?: return 0.0
            var s = 0.0
            for (p in r.pieces) {
                s += p.part.ordinal + p.width + p.alpha + (p.fill ?: 0) / 65536.0
                s += when (val k = p.stroke) {
                    Stroke.None -> 1.0
                    Stroke.Outline -> 2.0
                    Stroke.Ink -> 3.0
                    is Stroke.Color -> 4 + k.rgb / 65536.0
                }
                s += when (p.show) { Show.ALWAYS -> 0.0; Show.REST -> 5.0; Show.DANCE -> 7.0 }
                p.turn?.let { s += it.first + it.second + it.third }
                s += when (val sh = p.shape) {
                    is Shape.Path -> BuddySVG.numbers(sh.d).sum()
                    is Shape.Circle -> sh.cx + sh.cy + sh.r
                    is Shape.Ellipse -> sh.cx + sh.cy + sh.rx + sh.ry
                    is Shape.RRect -> sh.x + sh.y + sh.w + sh.h + sh.r
                }
            }
            for (part in BuddyPart.entries) r.pivots[part]?.let { s += it.x * 3 + it.y * 5 }
            s += r.full.x + r.full.y + r.full.w + r.full.h + (r.barBottom ?: 0.0) + r.feet.x + r.feet.y + r.sleepBottom
            for (z in r.zzz) s += z.x + z.y + z.size
            s += r.heart.x + r.heart.y * 2 + r.heart.size * 3
            s += r.face.x + r.face.y + r.face.rx + r.face.ry + BuddySVG.numbers(r.brows).sum()
            s += r.hat.x + r.hat.y + r.hat.size + r.sleepHat.x + r.sleepHat.y + r.sleepHat.size
            s += r.neck.x + r.neck.y + r.hand.x * 2 + r.hand.y * 2
            return s
        }

        private fun P(part: BuddyPart, d: String, fill: Int? = null, alpha: Double = 1.0, stroke: Stroke = Stroke.Outline,
                      width: Number = OUTLINE_WIDTH, show: Show = Show.ALWAYS, turn: Triple<Double, Double, Double>? = null) =
            BuddyPiece(part, Shape.Path(d), fill, alpha, stroke, width.toDouble(), show, turn)
        private fun C(part: BuddyPart, cx: Number, cy: Number, r: Number, fill: Int, stroke: Stroke = Stroke.Outline,
                      alpha: Double = 1.0, show: Show = Show.ALWAYS) =
            BuddyPiece(part, Shape.Circle(cx.toDouble(), cy.toDouble(), r.toDouble()), fill, alpha, stroke, OUTLINE_WIDTH, show)
        private fun E(part: BuddyPart, cx: Number, cy: Number, rx: Number, ry: Number, fill: Int,
                      stroke: Stroke = Stroke.Outline, alpha: Double = 1.0) =
            BuddyPiece(part, Shape.Ellipse(cx.toDouble(), cy.toDouble(), rx.toDouble(), ry.toDouble()), fill, alpha, stroke)
        private fun R(part: BuddyPart, x: Number, y: Number, w: Number, h: Number, r: Number, fill: Int) =
            BuddyPiece(part, Shape.RRect(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble(), r.toDouble()), fill)
        private fun L(part: BuddyPart, d: String, stroke: Stroke, w: Number, show: Show = Show.ALWAYS) =
            BuddyPiece(part, Shape.Path(d), null, 1.0, stroke, w.toDouble(), show)
        private fun limb(part: BuddyPart, d: String, color: Int, w: Number): List<BuddyPiece> =
            listOf(L(part, d, Stroke.Outline, w.toDouble() + 5), L(part, d, Stroke.Color(color), w))

        // Pink-haired cat girl: hoodie, pleated skirt and soft flowing locks.
        val GIRL: BuddyRig = run {
            val p = listOf(
                P(BuddyPart.TAIL, "M14 63 Q44 71 49 49 Q53 34 44 29 Q38 27 37 33 Q47 42 39 53 Q31 61 15 56 Z", fill = 0xE996B2, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.TAIL, "M43 34 Q48 43 43 50", stroke = Stroke.Color(0xFFD4E2), width = 3),
                P(BuddyPart.LEG_L, "M -2 72 Q -8 68 -14 73 L -16 102 L -15 137 Q -10 143 -5 137 L -4 105 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_L, "M -4 109 Q -10 112 -16 109 L -15 137 Q -10 143 -5 137 Z", fill = 0xFFF7F4, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_L, "M -5 134 Q -10 131 -16 135 L -19 140 Q -21 146 -13 146 L -4 145 Q 0 142 -5 134 Z", fill = 0xFF6F91, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_L, "M -6 139 L -14 139", stroke = Stroke.Color(0xFFF7F4), width = 2.5),
                P(BuddyPart.LEG_R, "M 2 72 Q 8 68 14 73 L 16 102 L 15 137 Q 10 143 5 137 L 4 105 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_R, "M 4 109 Q 10 112 16 109 L 15 137 Q 10 143 5 137 Z", fill = 0xFFF7F4, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_R, "M 5 134 Q 10 131 16 135 L 19 140 Q 21 146 13 146 L 4 145 Q 0 142 5 134 Z", fill = 0xFF6F91, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_R, "M 6 139 L 14 139", stroke = Stroke.Color(0xFFF7F4), width = 2.5),
                P(BuddyPart.BODY, "M-17 59 L-26 79 Q0 88 26 79 L17 59 Z", fill = 0xFFF7F4, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.BODY, "M-13 68 L-16 79 M-4 70 L-5 81 M5 70 L6 81 M14 68 L17 79", stroke = Stroke.Color(0xD9CADA), width = 1.8),
                P(BuddyPart.BODY, "M-16 22 Q0 14 16 22 Q23 41 22 62 Q25 69 18 72 Q0 78 -22 70 Q-21 44 -16 22 Z", fill = 0xFFB3C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.BODY, "M14 25 Q18 46 13 60 Q1 66 -20 62 L-22 70 Q0 78 18 72 Q25 69 22 62 Q23 42 14 25 Z", fill = 0xDF8EAB, stroke = Stroke.None, width = 0),
                P(BuddyPart.BODY, "M-10 26 Q0 35 10 26 M-8 34 L-9 43 M8 34 L9 43 M-9 55 Q0 61 9 55", stroke = Stroke.Color(0xFFF0F4), width = 2),
                P(BuddyPart.ARM_L, "M -10 25 Q -18 22 -22 32 Q -28 45 -29 57 Q -27 65 -19 62 Q -15 50 -9 36 Z", fill = 0xFFB3C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_L, "M -21 37 Q -29 49 -29 57 Q -27 65 -19 62 L -18 56 Q -25 57 -21 37 Z", fill = 0xDF8EAB, stroke = Stroke.None, width = 0),
                P(BuddyPart.ARM_L, "M -19 60 Q -24 57 -28 61 Q -32 67 -26 70 Q -20 72 -18 67 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_R, "M 10 25 Q 18 22 22 32 Q 28 45 29 57 Q 27 65 19 62 Q 15 50 9 36 Z", fill = 0xFFB3C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_R, "M 21 37 Q 29 49 29 57 Q 27 65 19 62 L 18 56 Q 25 57 21 37 Z", fill = 0xDF8EAB, stroke = Stroke.None, width = 0),
                P(BuddyPart.ARM_R, "M 19 60 Q 24 57 28 61 Q 32 67 26 70 Q 20 72 18 67 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-31 -28 Q-45 6 -40 43 L-46 54 Q-29 54 -22 35 L-24 8 Z M31 -28 Q45 6 40 43 L46 54 Q29 54 22 35 L24 8 Z", fill = 0xE996B2, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-33 -36 Q-39 -55 -31 -72 Q-20 -70 -10 -51 M10 -51 Q23 -71 32 -73 Q39 -54 34 -35 Z", fill = 0xFFF7F4, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-29 -62 L-26 -43 L-17 -50 Z M28 -63 L18 -50 L29 -43 Z", fill = 0xE996B2, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-36 -20 Q-38 -53 0 -54 Q38 -53 36 -20 L34 -4 Q28 19 0 20 Q-28 19 -34 -4 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-33 -7 Q-21 17 5 15 Q24 15 34 -4 Q28 19 0 20 Q-28 19 -33 -7 Z", fill = 0xF4BEAB, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-36 -10 Q-45 -45 -19 -53 Q4 -65 25 -49 Q43 -40 35 -8 L27 -18 L22 -36 Q14 -22 0 -20 L5 -35 Q-6 -22 -22 -23 L-27 -9 L-30 32 Q-39 19 -36 -10 Z", fill = 0xF3ACC4, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-29 -38 Q-15 -53 2 -49 Q-14 -42 -22 -32 Z M11 -49 Q27 -48 30 -31 Q22 -42 11 -44 Z", fill = 0xFFD6E3, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-34 4 Q-35 26 -39 39 M32 0 Q38 25 34 40", stroke = Stroke.Color(0xFFD6E3), width = 2),
                P(BuddyPart.HEAD, "M-18 -9 Q-18 -16 -13 -16 Q-8 -16 -8 -9 Q-8 -2 -13 -2 Q-18 -2 -18 -9 Z M8 -9 Q8 -16 13 -16 Q18 -16 18 -9 Q18 -2 13 -2 Q8 -2 8 -9 Z", fill = 0x75445D, stroke = Stroke.Ink, width = 1.6, show = Show.REST),
                P(BuddyPart.HEAD, "M-14 -4 h2 M12 -4 h2", stroke = Stroke.Color(0xDFA284), width = 1.8, show = Show.REST),
                P(BuddyPart.HEAD, "M-15.7 -12 Q-15.7 -14.5 -13.5 -14.5 Q-11.3 -14.5 -11.3 -12 Q-11.3 -9.5 -13.5 -9.5 Q-15.7 -9.5 -15.7 -12 Z M10.3 -12 Q10.3 -14.5 12.5 -14.5 Q14.7 -14.5 14.7 -12 Q14.7 -9.5 12.5 -9.5 Q10.3 -9.5 10.3 -12 Z", fill = 0xFFFFFF, stroke = Stroke.None, width = 0, show = Show.REST),
                P(BuddyPart.HEAD, "M-18 -9 q5 -7 10 0 M8 -9 q5 -7 10 0", stroke = Stroke.Ink, width = 3, show = Show.DANCE),
                E(BuddyPart.HEAD, -24, 3, 6, 3, fill = 0xF3A0AC, stroke = Stroke.None),
                E(BuddyPart.HEAD, 24, 3, 6, 3, fill = 0xF3A0AC, stroke = Stroke.None),
                P(BuddyPart.HEAD, "M-6 5 Q0 8 6 5 Q4 15 0 14 Q-4 15 -6 5 Z", fill = 0xA94C60, stroke = Stroke.Ink, width = 1.6),
                P(BuddyPart.HEAD, "M-2 11 Q0 10 2 11", stroke = Stroke.Color(0xFFB3C7), width = 2.4),
                P(BuddyPart.SLEEP, "M-12 28 Q18 14 46 26 Q65 31 67 47 Q54 59 15 57 L-14 50 Z", fill = 0xFFB3C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M12 47 Q41 53 61 39 L67 47 Q54 59 15 57 L-14 50 Z", fill = 0xDF8EAB, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M56 37 Q69 34 77 40 L78 49 Q68 53 58 48 Z", fill = 0xFFF7F4, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M73 39 Q83 36 84 44 Q84 51 76 51 L72 48 Z", fill = 0xFF6F91, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-60 12 Q-63 -10 -35 -13 Q-7 -13 -5 15 Q4 24 16 39 Q8 56 -24 55 L-57 45 Z", fill = 0xE996B2, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-60 8 Q-69 -11 -63 -23 Q-50 -21 -42 -8 M-28 -8 Q-21 -31 -15 -30 Q-6 -15 -8 5 Z", fill = 0xFFF7F4, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-60 -14 L-56 0 L-48 -6 Z M-18 -21 L-24 -7 L-14 -4 Z", fill = 0xF3ACC4, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M-63 22 Q-64 -5 -34 -6 Q-5 -5 -5 23 Q-8 49 -34 51 Q-61 49 -63 22 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-62 23 Q-68 -5 -42 -12 Q-12 -18 -5 12 L-8 24 Q-17 8 -24 9 L-30 16 L-31 5 Q-43 17 -54 13 Z", fill = 0xF3ACC4, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-56 3 Q-45 -7 -32 -6", stroke = Stroke.Color(0xFFD6E3), width = 3),
                P(BuddyPart.SLEEP, "M-51 27 Q-46 33 -40 27 M-29 27 Q-24 33 -18 27", stroke = Stroke.Ink, width = 2.5),
                P(BuddyPart.SLEEP, "M-37 39 Q-33 42 -29 38", stroke = Stroke.Ink, width = 1.8),
                E(BuddyPart.SLEEP, -52, 37, 5, 3, fill = 0xF3A0AC, stroke = Stroke.None),
                E(BuddyPart.SLEEP, -16, 37, 5, 3, fill = 0xF3A0AC, stroke = Stroke.None),
                P(BuddyPart.SLEEP, "M-22 44 Q-8 37 3 44 Q6 50 -2 53 L-22 53 Q-28 49 -22 44 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M54 53 Q81 57 83 42 Q81 37 85 35 Q93 34 93 44 Q93 72 55 69 L29 66 Q25 60 31 59 Z", fill = 0xF3ACC4, stroke = Stroke.Outline, width = 3.2),
            )
            BuddyRig(
                pieces = p,
                pivots = mapOf(BuddyPart.TAIL to P2(14, 66), BuddyPart.LEG_L to P2(-8, 72), BuddyPart.LEG_R to P2(8, 72), BuddyPart.BODY to P2(0, 72), BuddyPart.ARM_L to P2(-12, 30), BuddyPart.ARM_R to P2(12, 30), BuddyPart.HEAD to P2(0, 18)),
                full = BuddyRect(-96, -84, 196, 234), barBottom = null, feet = P2(0, 146), sleepBottom = 72,
                zzz = listOf(P3(0, -30, 12), P3(16, -46, 15), P3(36, -64, 19)),
                style = BuddyDance.Style(armL = 2.3, armR = 2.3, armAmp = 0.3, alternate = true, kick = 0.6, bounce = 9.0, step = 8.0),
                face = P4(0, -2, 28, 19), brows = "M-20 -20 L-8 -17 M20 -20 L8 -17",
                hat = P3(0, -49, 26), sleepHat = P3(-34, -10, 26), neck = P2(0, 22), hand = P2(24, 66))
        }

        // Tousled-haired boy: navy vest, ivory tee and denim sneakers.
        val BOY: BuddyRig = run {
            val p = listOf(
                P(BuddyPart.LEG_L, "M -2 68 L -17 65 Q -21 91 -20 108 L -23 132 Q -16 139 -9 132 L -5 106 Z", fill = 0x83ACCA, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_L, "M -14 70 L -17 65 Q -21 91 -20 108 L -23 132 L -17 134 L -13 105 Z", fill = 0x5F88AB, stroke = Stroke.None, width = 0),
                P(BuddyPart.LEG_L, "M -9 130 Q -17 126 -23 131 L -29 137 Q -32 143 -24 144 L -8 143 Q -4 139 -9 130 Z", fill = 0xFFF9F3, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_L, "M -11 135 L -20 135 M -9 141 L -26 141", stroke = Stroke.Color(0xB8C6D7), width = 1.7),
                P(BuddyPart.LEG_R, "M 2 68 L 17 65 Q 21 91 20 108 L 23 132 Q 16 139 9 132 L 5 106 Z", fill = 0x83ACCA, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_R, "M 14 70 L 17 65 Q 21 91 20 108 L 23 132 L 17 134 L 13 105 Z", fill = 0x5F88AB, stroke = Stroke.None, width = 0),
                P(BuddyPart.LEG_R, "M 9 130 Q 17 126 23 131 L 29 137 Q 32 143 24 144 L 8 143 Q 4 139 9 130 Z", fill = 0xFFF9F3, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_R, "M 11 135 L 20 135 M 9 141 L 26 141", stroke = Stroke.Color(0xB8C6D7), width = 1.7),
                P(BuddyPart.BODY, "M-18 20 Q0 14 18 20 L23 69 Q0 76 -23 69 Z", fill = 0xFFF9F3, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.BODY, "M8 32 Q10 52 19 62 L23 69 Q0 76 -23 69 L-21 64 Q2 70 8 59 Z", fill = 0xDFE6EE, stroke = Stroke.None, width = 0),
                P(BuddyPart.BODY, "M-19 20 L-9 18 Q-12 38 -9 57 L-10 73 L-26 73 L-22 36 Z M9 18 L19 20 L22 36 L26 73 L10 73 L9 57 Q12 38 9 18 Z", fill = 0x304563, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.BODY, "M-18 28 L-19 59 M18 28 L19 59", stroke = Stroke.Color(0x536B8C), width = 2),
                P(BuddyPart.BODY, "M-7 23 Q0 28 7 23", stroke = Stroke.Color(0xB8C6D7), width = 2),
                P(BuddyPart.ARM_L, "M -14 28 Q -20 23 -25 31 L -32 53 Q -36 63 -29 67 Q -22 69 -20 60 L -15 45 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_L, "M -14 23 Q -21 19 -26 27 L -30 39 Q -24 45 -16 40 L -11 31 Z", fill = 0xFFF9F3, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_L, "M -24 45 Q -30 56 -27 61", stroke = Stroke.Color(0xF0BCA3), width = 2),
                P(BuddyPart.ARM_R, "M 14 28 Q 20 23 25 31 L 32 53 Q 36 63 29 67 Q 22 69 20 60 L 15 45 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_R, "M 14 23 Q 21 19 26 27 L 30 39 Q 24 45 16 40 L 11 31 Z", fill = 0xFFF9F3, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_R, "M 24 45 Q 30 56 27 61", stroke = Stroke.Color(0xF0BCA3), width = 2),
                P(BuddyPart.HEAD, "M-32 -16 Q-45 -21 -42 -7 Q-40 2 -31 2 M32 -16 Q45 -21 42 -7 Q40 2 31 2 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-36 -24 Q-35 -53 0 -53 Q36 -53 36 -24 L33 -2 Q26 19 0 20 Q-26 19 -33 -2 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-33 -3 Q-20 15 6 14 Q22 13 33 -2 Q26 19 0 20 Q-26 19 -33 -3 Z", fill = 0xF0BCA3, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-34 -5 L-40 -22 L-37 -33 L-43 -34 Q-35 -51 -19 -53 L-24 -60 Q-7 -62 3 -57 Q18 -64 28 -52 Q42 -45 39 -27 L35 -8 L28 -17 L25 -35 Q14 -24 5 -25 L9 -38 Q-3 -23 -16 -22 L-12 -33 L-27 -22 L-29 -7 Z", fill = 0x303141, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-31 -37 Q-18 -52 -4 -48 Q-16 -43 -22 -33 Z M6 -49 Q22 -56 30 -39 Q18 -46 6 -43 Z", fill = 0x4C5066, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-20 -20 Q-14 -23 -8 -20 M8 -20 Q14 -23 20 -20", stroke = Stroke.Ink, width = 1.8),
                P(BuddyPart.HEAD, "M-17.8 -8 Q-17.8 -14.8 -13 -14.8 Q-8.2 -14.8 -8.2 -8 Q-8.2 -1.2 -13 -1.2 Q-17.8 -1.2 -17.8 -8 Z M8.2 -8 Q8.2 -14.8 13 -14.8 Q17.8 -14.8 17.8 -8 Q17.8 -1.2 13 -1.2 Q8.2 -1.2 8.2 -8 Z", fill = 0x4B485C, stroke = Stroke.Ink, width = 1.6, show = Show.REST),
                P(BuddyPart.HEAD, "M-14 -3.2 h2 M12 -3.2 h2", stroke = Stroke.Color(0xDFA284), width = 1.8, show = Show.REST),
                P(BuddyPart.HEAD, "M-15.7 -11 Q-15.7 -13.5 -13.5 -13.5 Q-11.3 -13.5 -11.3 -11 Q-11.3 -8.5 -13.5 -8.5 Q-15.7 -8.5 -15.7 -11 Z M10.3 -11 Q10.3 -13.5 12.5 -13.5 Q14.7 -13.5 14.7 -11 Q14.7 -8.5 12.5 -8.5 Q10.3 -8.5 10.3 -11 Z", fill = 0xFFFFFF, stroke = Stroke.None, width = 0, show = Show.REST),
                P(BuddyPart.HEAD, "M-18 -8 q5 -7 10 0 M8 -8 q5 -7 10 0", stroke = Stroke.Ink, width = 3, show = Show.DANCE),
                E(BuddyPart.HEAD, -24, 4, 6, 3, fill = 0xF2B1A7, stroke = Stroke.None),
                E(BuddyPart.HEAD, 24, 4, 6, 3, fill = 0xF2B1A7, stroke = Stroke.None),
                P(BuddyPart.HEAD, "M-8 5 Q0 9 8 5 Q6 16 0 16 Q-6 16 -8 5 Z", fill = 0xA7525B, stroke = Stroke.Ink, width = 1.8),
                P(BuddyPart.HEAD, "M-5 7 Q0 9 5 7 L4 10 L-4 10 Z", fill = 0xFFF9F3, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M-10 27 Q14 15 41 25 L61 35 L59 50 Q35 58 -8 53 Z", fill = 0x304563, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M26 29 Q49 25 68 38 L70 48 Q54 58 30 49 Z", fill = 0x83ACCA, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M40 36 Q52 44 61 43", stroke = Stroke.Color(0x5F88AB), width = 3),
                P(BuddyPart.SLEEP, "M66 38 Q76 33 81 42 Q84 49 76 51 L67 49 Z", fill = 0xFFF9F3, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-64 21 Q-64 -8 -34 -8 Q-4 -8 -4 22 Q-7 48 -34 51 Q-60 48 -64 21 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-61 32 Q-36 54 -7 31 Q-10 49 -34 51 Q-55 48 -61 32 Z", fill = 0xF0BCA3, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M-62 24 L-68 9 L-65 -3 L-69 -7 Q-54 -18 -41 -14 Q-18 -24 -7 -8 Q2 3 -5 21 L-13 11 L-17 2 Q-28 15 -40 13 L-35 3 Q-48 15 -58 11 Z", fill = 0x303141, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-57 -2 Q-42 -13 -28 -9 L-42 1 Z", fill = 0x4C5066, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M-51 26 Q-46 32 -40 26 M-29 26 Q-24 32 -18 26", stroke = Stroke.Ink, width = 2.5),
                E(BuddyPart.SLEEP, -51, 36, 5, 3, fill = 0xF2B1A7, stroke = Stroke.None),
                E(BuddyPart.SLEEP, -17, 36, 5, 3, fill = 0xF2B1A7, stroke = Stroke.None),
                P(BuddyPart.SLEEP, "M-37 38 Q-33 42 -29 38", stroke = Stroke.Ink, width = 1.8),
                P(BuddyPart.SLEEP, "M-22 44 Q-9 38 2 44 Q6 50 -3 53 L-22 53 Q-28 49 -22 44 Z", fill = 0xFFE0C7, stroke = Stroke.Outline, width = 3.2),
            )
            BuddyRig(
                pieces = p,
                pivots = mapOf(BuddyPart.LEG_L to P2(-9, 68), BuddyPart.LEG_R to P2(9, 68), BuddyPart.BODY to P2(0, 70), BuddyPart.ARM_L to P2(-18, 26), BuddyPart.ARM_R to P2(18, 26), BuddyPart.HEAD to P2(0, 16)),
                full = BuddyRect(-92, -76, 184, 226), barBottom = null, feet = P2(0, 142), sleepBottom = 57,
                zzz = listOf(P3(0, -30, 12), P3(16, -46, 15), P3(36, -64, 19)),
                style = BuddyDance.Style(armL = -1.3, armR = 2.3, armAmp = 0.2, alternate = false, kick = 0.3, bounce = 8.0, step = 10.0),
                face = P4(0, -2, 28, 19), brows = "M-20 -20 L-8 -17 M20 -20 L8 -17",
                hat = P3(2, -48, 26), sleepHat = P3(-34, -12, 26), neck = P2(0, 22), hand = P2(27, 60))
        }

        // Round tabby: cream cheeks, tiny paw pads and a striped tail.
        val CAT: BuddyRig = run {
            val p = listOf(
                P(BuddyPart.TAIL, "M18 75 Q45 82 47 61 Q44 39 54 30 Q60 24 64 30 Q68 36 61 43 Q58 48 61 61 Q64 94 20 88 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.TAIL, "M48 43 Q46 35 54 30 Q60 24 64 30 Q68 36 61 43 L57 48 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                P(BuddyPart.TAIL, "M50 55 L60 53 M46 73 L56 78", stroke = Stroke.Color(0xDC8736), width = 5),
                P(BuddyPart.LEG_L, "M -7 85 Q -14 80 -21 87 L -24 103 Q -29 115 -17 116 L -8 115 Q -2 112 -5 103 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_L, "M -5 103 Q -14 108 -24 103 Q -29 115 -17 116 L -8 115 Q -2 112 -5 103 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                P(BuddyPart.LEG_L, "M -10 109 L -10 113 M -16 110 L -16 114", stroke = Stroke.Color(0xD4AE8D), width = 1.4),
                P(BuddyPart.LEG_R, "M 7 85 Q 14 80 21 87 L 24 103 Q 29 115 17 116 L 8 115 Q 2 112 5 103 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_R, "M 5 103 Q 14 108 24 103 Q 29 115 17 116 L 8 115 Q 2 112 5 103 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                P(BuddyPart.LEG_R, "M 10 109 L 10 113 M 16 110 L 16 114", stroke = Stroke.Color(0xD4AE8D), width = 1.4),
                P(BuddyPart.BODY, "M-20 28 Q-32 42 -30 70 Q-32 101 0 102 Q32 101 30 70 Q32 42 20 28 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.BODY, "M21 42 Q39 94 10 101 L-5 101 Q25 88 21 42 Z", fill = 0xEA9B41, stroke = Stroke.None, width = 0),
                P(BuddyPart.BODY, "M0 43 Q-20 44 -20 71 Q-22 93 0 94 Q22 93 20 71 Q20 44 0 43 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                P(BuddyPart.BODY, "M-29 61 L-24 64 M-29 77 L-24 79 M29 61 L24 64 M29 77 L24 79", stroke = Stroke.Color(0xDC8736), width = 3),
                P(BuddyPart.ARM_L, "M -18 48 Q -24 43 -29 49 L -39 70 Q -43 80 -34 85 Q -25 87 -23 76 L -17 59 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_L, "M -24 73 Q -31 68 -39 73 Q -43 80 -34 85 Q -25 87 -24 73 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                E(BuddyPart.ARM_L, -31, 78, 3.5, 3.5, fill = 0xF4A0A1, stroke = Stroke.None),
                P(BuddyPart.ARM_R, "M 18 48 Q 24 43 29 49 L 39 70 Q 43 80 34 85 Q 25 87 23 76 L 17 59 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_R, "M 24 73 Q 31 68 39 73 Q 43 80 34 85 Q 25 87 24 73 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                E(BuddyPart.ARM_R, 31, 78, 3.5, 3.5, fill = 0xF4A0A1, stroke = Stroke.None),
                P(BuddyPart.HEAD, "M-40 -17 Q-44 -39 -34 -57 Q-26 -59 -10 -39 L10 -39 Q26 -59 34 -57 Q44 -39 40 -17 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-35 -46 Q-38 -32 -31 -25 L-18 -36 Z M35 -46 Q38 -32 31 -25 L18 -36 Z", fill = 0xF4A0A1, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-38 -21 Q-28 -39 0 -39 Q28 -39 38 -21 L43 -8 L39 -7 L46 2 L41 4 Q47 17 32 29 Q17 40 0 40 Q-17 40 -32 29 Q-47 17 -41 4 L-46 2 L-39 -7 L-43 -8 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-40 9 Q-25 -3 -12 6 Q0 -2 12 6 Q25 -3 40 9 Q41 27 18 35 Q0 43 -18 35 Q-41 27 -40 9 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-14 -36 L-10 -21 Q-6 -20 -7 -35 Z M-3 -39 L-2 -22 Q1 -17 4 -38 Z M11 -36 L7 -22 Q11 -20 16 -34 Z", fill = 0xDC8736, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-22.5 -4 Q-22.5 -11 -17 -11 Q-11.5 -11 -11.5 -4 Q-11.5 3 -17 3 Q-22.5 3 -22.5 -4 Z M11.5 -4 Q11.5 -11 17 -11 Q22.5 -11 22.5 -4 Q22.5 3 17 3 Q11.5 3 11.5 -4 Z", fill = 0x654532, stroke = Stroke.Ink, width = 1.6, show = Show.REST),
                P(BuddyPart.HEAD, "M-18 1 h2 M16 1 h2", stroke = Stroke.Color(0xDFA284), width = 1.8, show = Show.REST),
                P(BuddyPart.HEAD, "M-19.7 -7 Q-19.7 -9.5 -17.5 -9.5 Q-15.3 -9.5 -15.3 -7 Q-15.3 -4.5 -17.5 -4.5 Q-19.7 -4.5 -19.7 -7 Z M14.3 -7 Q14.3 -9.5 16.5 -9.5 Q18.7 -9.5 18.7 -7 Q18.7 -4.5 16.5 -4.5 Q14.3 -4.5 14.3 -7 Z", fill = 0xFFFFFF, stroke = Stroke.None, width = 0, show = Show.REST),
                P(BuddyPart.HEAD, "M-22 -4 q5 -7 10 0 M12 -4 q5 -7 10 0", stroke = Stroke.Ink, width = 3, show = Show.DANCE),
                E(BuddyPart.HEAD, -29, 14, 6, 3, fill = 0xF4B09A, stroke = Stroke.None),
                E(BuddyPart.HEAD, 29, 14, 6, 3, fill = 0xF4B09A, stroke = Stroke.None),
                P(BuddyPart.HEAD, "M-4 8 Q0 6 4 8 Q3 12 0 13 Q-3 12 -4 8 Z", fill = 0xE7878B, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-7 17 Q0 21 7 17 Q5 29 0 29 Q-5 29 -7 17 Z", fill = 0xA65350, stroke = Stroke.Ink, width = 1.8),
                P(BuddyPart.HEAD, "M-3 25 Q0 23 3 25", stroke = Stroke.Color(0xF4A0A1), width = 3),
                P(BuddyPart.HEAD, "M0 13 L0 17 Q-4 21 -8 16 M0 17 Q4 21 8 16 M-32 11 L-44 8 M-32 18 L-44 20 M32 11 L44 8 M32 18 L44 20", stroke = Stroke.Ink, width = 1.8),
                P(BuddyPart.SLEEP, "M-20 32 Q-3 9 29 16 Q62 19 64 45 Q64 65 28 65 L-22 58 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M26 23 Q45 29 43 54 Q29 64 3 57 Q10 42 26 23 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M13 18 L10 27 M28 19 L24 30 M44 24 L39 34", stroke = Stroke.Color(0xDC8736), width = 4),
                P(BuddyPart.SLEEP, "M-61 12 Q-68 -7 -61 -15 Q-49 -13 -40 0 L-26 0 Q-15 -14 -7 -13 L-10 16 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-59 -7 L-55 9 L-45 3 Z M-13 -5 L-25 5 L-14 11 Z", fill = 0xF4A0A1, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M-65 25 Q-65 -2 -34 -3 Q-3 -2 -3 25 Q-6 54 -34 55 Q-62 54 -65 25 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-63 32 Q-48 21 -34 30 Q-20 21 -5 32 Q-10 53 -34 55 Q-58 53 -63 32 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M-42 1 L-40 11 M-32 0 L-32 10 M-22 2 L-24 11", stroke = Stroke.Color(0xDC8736), width = 3),
                P(BuddyPart.SLEEP, "M-54 26 Q-48 33 -41 26 M-28 26 Q-21 33 -15 26", stroke = Stroke.Ink, width = 2.5),
                P(BuddyPart.SLEEP, "M-38 34 Q-34 31 -30 34 L-34 38 Z", fill = 0xE7878B, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M-34 38 Q-38 43 -42 39 M-34 38 Q-30 43 -26 39", stroke = Stroke.Ink, width = 1.6),
                E(BuddyPart.SLEEP, -54, 37, 5, 3, fill = 0xF4B09A, stroke = Stroke.None),
                E(BuddyPart.SLEEP, -14, 37, 5, 3, fill = 0xF4B09A, stroke = Stroke.None),
                P(BuddyPart.SLEEP, "M56 45 Q64 40 67 48 Q72 66 44 67 Q13 70 -6 60 Q-12 55 -7 51 Q-3 47 5 51 Q35 62 54 56 Q60 53 56 45 Z", fill = 0xFFB957, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M12 54 Q7 64 -3 62 Q-13 58 -7 51 Q-3 47 5 51 Z", fill = 0xFFF0D5, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M28 59 L26 66 M43 60 L43 67", stroke = Stroke.Color(0xDC8736), width = 4),
            )
            BuddyRig(
                pieces = p,
                pivots = mapOf(BuddyPart.TAIL to P2(18, 80), BuddyPart.LEG_L to P2(-14, 88), BuddyPart.LEG_R to P2(14, 88), BuddyPart.BODY to P2(0, 96), BuddyPart.ARM_L to P2(-22, 52), BuddyPart.ARM_R to P2(22, 52), BuddyPart.HEAD to P2(0, 32)),
                full = BuddyRect(-80, -66, 160, 188), barBottom = null, feet = P2(0, 116), sleepBottom = 68,
                zzz = listOf(P3(0, -30, 12), P3(16, -46, 15), P3(36, -64, 19)),
                style = BuddyDance.Style(armL = 1.2, armR = 1.2, armAmp = 0.6, alternate = true, kick = 0.2, bounce = 10.0, step = 8.0),
                heart = P3(0, 68, 13), face = P4(0, 10, 33, 22), brows = "M-24 -17 L-11 -13 M24 -17 L11 -13",
                hat = P3(0, -36, 24), sleepHat = P3(-34, -2, 28), neck = P2(0, 40), hand = P2(31, 78))
        }

        // Butter-yellow chick: swept crest, downy belly and scalloped wings.
        val CHICK: BuddyRig = run {
            val p = listOf(
                P(BuddyPart.LEG_L, "M -8 85 L -17 85 L -17 101 Q -27 102 -26 108 Q -23 113 -17 109 Q -11 115 -7 109 Q 0 111 0 106 Q -1 102 -8 101 Z", fill = 0xF6A13A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_L, "M -11 102 L -11 108 M -17 103 L -19 107", stroke = Stroke.Color(0xD78129), width = 1.5),
                P(BuddyPart.LEG_R, "M 8 85 L 17 85 L 17 101 Q 27 102 26 108 Q 23 113 17 109 Q 11 115 7 109 Q 0 111 0 106 Q 1 102 8 101 Z", fill = 0xF6A13A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.LEG_R, "M 11 102 L 11 108 M 17 103 L 19 107", stroke = Stroke.Color(0xD78129), width = 1.5),
                P(BuddyPart.BODY, "M-27 31 Q-42 50 -36 74 Q-30 96 0 96 Q30 96 36 74 Q42 50 27 31 Z", fill = 0xFFE17A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.BODY, "M28 47 Q44 84 14 94 Q-2 100 -22 89 Q24 93 28 47 Z", fill = 0xF5C35D, stroke = Stroke.None, width = 0),
                P(BuddyPart.BODY, "M0 48 Q-22 48 -23 70 Q-23 89 0 90 Q23 89 23 70 Q22 48 0 48 Z", fill = 0xFFF1BE, stroke = Stroke.None, width = 0),
                P(BuddyPart.ARM_L, "M -30 47 Q -39 44 -48 53 Q -61 64 -54 68 L -49 67 Q -59 77 -49 78 L -45 76 Q -50 87 -40 84 Q -29 79 -25 59 Z", fill = 0xFFE17A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_L, "M -35 64 Q -40 71 -46 72 M -34 72 Q -38 78 -41 79", stroke = Stroke.Color(0xF0BC55), width = 2),
                P(BuddyPart.ARM_R, "M 30 47 Q 39 44 48 53 Q 61 64 54 68 L 49 67 Q 59 77 49 78 L 45 76 Q 50 87 40 84 Q 29 79 25 59 Z", fill = 0xFFE17A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.ARM_R, "M 35 64 Q 40 71 46 72 M 34 72 Q 38 78 41 79", stroke = Stroke.Color(0xF0BC55), width = 2),
                P(BuddyPart.HEAD, "M-39 -6 Q-38 -34 -8 -39 Q-19 -49 -11 -53 Q-5 -53 -4 -44 Q-3 -61 13 -61 Q24 -59 14 -49 L7 -41 Q24 -52 28 -44 Q30 -38 18 -34 Q40 -25 40 -3 L43 6 L39 8 Q38 35 0 39 Q-38 35 -39 8 L-43 6 Z", fill = 0xFFE17A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.HEAD, "M-33 14 Q-13 38 14 29 Q31 25 38 13 Q35 37 0 39 Q-28 36 -33 14 Z", fill = 0xF5C35D, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-27 -20 Q-18 -34 -4 -33 Q-17 -25 -20 -15 Z M0 -47 Q4 -57 13 -56 L7 -50 Z", fill = 0xFFF1AE, stroke = Stroke.None, width = 0),
                P(BuddyPart.HEAD, "M-23 -15 Q-18 -19 -13 -16 M13 -16 Q18 -19 23 -15", stroke = Stroke.Color(0xC49139), width = 1.8),
                P(BuddyPart.HEAD, "M-21 0 Q-21 -6.5 -16 -6.5 Q-11 -6.5 -11 0 Q-11 6.5 -16 6.5 Q-21 6.5 -21 0 Z M11 0 Q11 -6.5 16 -6.5 Q21 -6.5 21 0 Q21 6.5 16 6.5 Q11 6.5 11 0 Z", fill = 0x6A482B, stroke = Stroke.Ink, width = 1.6, show = Show.REST),
                P(BuddyPart.HEAD, "M-17 4.5 h2 M15 4.5 h2", stroke = Stroke.Color(0xDFA284), width = 1.8, show = Show.REST),
                P(BuddyPart.HEAD, "M-18.7 -3 Q-18.7 -5.5 -16.5 -5.5 Q-14.3 -5.5 -14.3 -3 Q-14.3 -0.5 -16.5 -0.5 Q-18.7 -0.5 -18.7 -3 Z M13.3 -3 Q13.3 -5.5 15.5 -5.5 Q17.7 -5.5 17.7 -3 Q17.7 -0.5 15.5 -0.5 Q13.3 -0.5 13.3 -3 Z", fill = 0xFFFFFF, stroke = Stroke.None, width = 0, show = Show.REST),
                P(BuddyPart.HEAD, "M-21 0 q5 -7 10 0 M11 0 q5 -7 10 0", stroke = Stroke.Ink, width = 3, show = Show.DANCE),
                E(BuddyPart.HEAD, -27, 14, 6, 3, fill = 0xF5AF71, stroke = Stroke.None),
                E(BuddyPart.HEAD, 27, 14, 6, 3, fill = 0xF5AF71, stroke = Stroke.None),
                P(BuddyPart.HEAD, "M-8 14 Q0 10 8 14 Q6 27 0 27 Q-6 27 -8 14 Z", fill = 0xC46A36, stroke = Stroke.Ink, width = 1.8),
                P(BuddyPart.HEAD, "M-10 12 Q-4 4 0 5 Q4 4 10 12 Q0 19 -10 12 Z", fill = 0xF6A13A, stroke = Stroke.Ink, width = 1.8),
                P(BuddyPart.HEAD, "M-2 23 L2 23", stroke = Stroke.Color(0xF5AF71), width = 2.5),
                P(BuddyPart.SLEEP, "M-21 28 Q6 9 33 21 Q56 31 53 51 Q50 69 10 68 Q-23 67 -31 49 Z", fill = 0xFFE17A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M10 48 Q28 42 45 52 Q35 66 10 65 Q-9 65 -18 56 Z", fill = 0xFFF1BE, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M41 60 Q47 57 53 62 L57 66 Q49 70 42 66 Z", fill = 0xF6A13A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M13 31 Q32 25 42 38 Q48 48 41 48 L36 46 Q41 54 33 53 Q20 50 13 31 Z", fill = 0xFFE17A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M24 37 Q29 43 34 44", stroke = Stroke.Color(0xF0BC55), width = 2),
                P(BuddyPart.SLEEP, "M-59 24 Q-59 3 -39 -1 Q-48 -10 -42 -14 Q-36 -16 -31 -6 Q-27 -23 -17 -18 Q-11 -13 -24 -4 Q-1 1 0 24 Q-1 52 -30 55 Q-59 52 -59 24 Z", fill = 0xFFE17A, stroke = Stroke.Outline, width = 3.2),
                P(BuddyPart.SLEEP, "M-56 35 Q-32 55 -3 34 Q-8 52 -30 55 Q-50 52 -56 35 Z", fill = 0xF5C35D, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M-49 10 Q-42 2 -33 4 L-43 14 Z", fill = 0xFFF1AE, stroke = Stroke.None, width = 0),
                P(BuddyPart.SLEEP, "M-49 25 Q-43 32 -37 25 M-25 25 Q-19 32 -13 25", stroke = Stroke.Ink, width = 2.5),
                P(BuddyPart.SLEEP, "M-57 32 Q-68 33 -68 38 Q-62 43 -55 40 Z", fill = 0xF6A13A, stroke = Stroke.Ink, width = 1.8),
                E(BuddyPart.SLEEP, -47, 37, 5, 3, fill = 0xF5AF71, stroke = Stroke.None),
                E(BuddyPart.SLEEP, -12, 37, 5, 3, fill = 0xF5AF71, stroke = Stroke.None),
            )
            BuddyRig(
                pieces = p,
                pivots = mapOf(BuddyPart.LEG_L to P2(-12, 86), BuddyPart.LEG_R to P2(12, 86), BuddyPart.BODY to P2(0, 94), BuddyPart.ARM_L to P2(-32, 50), BuddyPart.ARM_R to P2(32, 50), BuddyPart.HEAD to P2(0, 34)),
                full = BuddyRect(-80, -66, 160, 188), barBottom = null, feet = P2(0, 110), sleepBottom = 68,
                zzz = listOf(P3(0, -34, 12), P3(16, -50, 15), P3(36, -68, 19)),
                style = BuddyDance.Style(armL = 1.0, armR = 1.0, armAmp = 0.7, alternate = false, kick = 0.3, bounce = 12.0, step = 8.0),
                heart = P3(0, 66, 13), face = P4(0, 10, 30, 21), brows = "M-23 -15 L-11 -11 M23 -15 L11 -11",
                hat = P3(0, -36, 24), sleepHat = P3(-30, 0, 26), neck = P2(0, 39), hand = P2(43, 79))
        }
    }
}

/**
 * Quầng sáng / tối quanh CẢ dáng (vẽ dưới mọi bộ phận) + màu viền nét — theo nền thanh gợi ý, chọn MỘT lần lúc đổi
 * theme: bên nào tương phản WCAG cao hơn. = iOS BuddyHalo (cùng số).
 */
object BuddyHalo {
    const val LIGHT = 0xF4F4F4
    const val DARK = 0x3A2A2A
    /** Bề rộng quầng (dp) ngoài nét viền. */
    const val WIDTH = 1.75
    const val SYSTEM_LIGHT = 0xD1D3D9
    const val SYSTEM_DARK = 0x2C2C2E

    fun luminance(c: Int): Double {
        fun ch(v: Int): Double { val x = (v and 0xFF) / 255.0; return if (x <= 0.03928) x / 12.92 else Math.pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(c shr 16) + 0.7152 * ch(c shr 8) + 0.0722 * ch(c)
    }
    fun contrast(a: Int, b: Int): Double {
        val x = luminance(a); val y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    data class Colors(val halo: Int, val outline: Int, val darkBar: Boolean)

    /** Màu quầng + viền cho nền thanh [bar] (RGB đục). */
    fun colors(bar: Int): Colors {
        val darkBar = contrast(LIGHT, bar) >= contrast(DARK, bar)
        return Colors(if (darkBar) LIGHT else DARK, if (darkBar) BuddyRig.OUTLINE_DARK else BuddyRig.OUTLINE_LIGHT, darkBar)
    }

    /** Nền thanh (ARGB, có thể trong suốt) trộn lên xám bàn phím hệ thống ⇒ RGB đục. */
    fun opaque(argb: Int, dark: Boolean): Int {
        val a = ((argb ushr 24) and 0xFF) / 255.0
        val sys = if (dark) SYSTEM_DARK else SYSTEM_LIGHT
        fun ch(sh: Int): Int = Math.round(((argb shr sh) and 0xFF) * a + ((sys shr sh) and 0xFF) * (1 - a)).toInt()
        return (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
    }

    /** Khoá nhóm quầng của một mảnh: (bề rộng nét thiết kế, có tô). */
    fun key(p: BuddyPiece): Pair<Double, Boolean> = if (p.fill != null) BuddyRig.OUTLINE_WIDTH to true else p.width to false
}

/** Nghệ thuật: khung vector (mặc định) hoặc bộ khung hình vẽ sẵn (hoạ sĩ — chưa có). = iOS BuddyArt. */
sealed class BuddyArt {
    class Rig(val rig: BuddyRig) : BuddyArt()
    class Sprites(val sprites: BuddySprites) : BuddyArt()
}

/** Bộ khung hình (tên ảnh) — mỗi bậc nhảy một chuỗi khung chạy hết trong một vòng. */
class BuddySprites(val sleep: String, val rest: String, val dance: List<List<String>>, val cheer: List<String>) {
    companion object {
        /** Khung lật gương = ô + MIRROR (nhấc chân trái ↔ chân phải) — = iOS BuddySprites.mirror. */
        const val MIRROR = 100
        fun cell(frame: Int) = frame % MIRROR
        fun isMirrored(frame: Int) = frame >= MIRROR
        private val GENTLE = intArrayOf(0, 1, 0, 1 + MIRROR)
        /** Lắc hông: qua lại giữa khung 5 và 6 (ảnh thứ 6 / 7) vài lần. */
        private val SWAY = intArrayOf(0, 1, 0, 1 + MIRROR, 5, 6, 5, 6)
        /** = iOS turnOrder: thứ tự ảnh khi xoay trọn vòng; cô gái vẽ khác thứ tự. */
        fun turnOrder(c: BuddyCharacter): IntArray =
            if (c == BuddyCharacter.GIRL) intArrayOf(6, 3, 4, 2, 5) else intArrayOf(2, 3, 4, 5, 6)
        /** Bậc cao: nhảy, xoay trọn vòng trái, rồi trọn vòng phải (bản lật gương), rồi lắc hông. */
        private val TURNS = BuddyCharacter.entries.associateWith { c ->
            val o = turnOrder(c)
            intArrayOf(0, 1, 0, 1 + MIRROR) + o + intArrayOf(0) + o.map { it + MIRROR }.toIntArray() +
                intArrayOf(0, 5, 6, 5, 6, 0)
        }
        val CHEER = intArrayOf(0, 1, 6, 1 + MIRROR, 0)
        val REACT = intArrayOf(0, 1, 6, 6 + MIRROR)
        /** Lắc nhẹ sau khi ngừng gõ ([BuddyPhase.Idle]): qua lại khung 5 ↔ 6, chậm. */
        val IDLE = intArrayOf(5, 6)
        const val IDLE_DURATION = 1.6
        fun columns(c: BuddyCharacter) = 4
        fun rows(c: BuddyCharacter) = 2
        fun rest(c: BuddyCharacter) = 0
        fun sleep(c: BuddyCharacter) = 7
        fun dance(c: BuddyCharacter, tier: Int): IntArray = if (tier >= 2) TURNS.getValue(c) else if (tier == 1) SWAY else GENTLE
        /** Vòng dài theo số khung (nhịp mỗi khung như bộ cũ: 10 khung bậc cao, 4 khung bậc thấp). */
        fun duration(c: BuddyCharacter, tier: Int) =
            BuddyDance.loopLength(tier) * dance(c, tier).size / (if (tier >= 2) 10.0 else 4.0)


        fun frameIndex(p: Double, count: Int): Int {
            if (count <= 0) return 0
            val pp = p - floor(p)
            return min((pp * count).toInt(), count - 1)
        }
    }
}

// MARK: trang phục theo mùa lễ

/** = iOS BuddySeason: theme lễ thắng, không thì cửa sổ ngày (âm lịch tra bảng nhúng 2026–2035, không mạng). */
enum class BuddySeason {
    TET, CHRISTMAS, HALLOWEEN, MID_AUTUMN;

    companion object {
        fun ofTheme(themeId: String?): BuddySeason? = when (themeId) {
            "tet", "tetMai" -> TET
            "xmas", "xmasSnow" -> CHRISTMAS
            "halloween" -> HALLOWEEN
            "trungthu" -> MID_AUTUMN
            else -> null
        }

        /** Mùng 1 Tết — LƯU Ý: bảng nhúng theo lịch âm VN, cần đối chiếu nguồn chính thức trước khi phát hành. */
        val LUNAR_NEW_YEAR: Map<Int, Pair<Int, Int>> = mapOf(
            2026 to (2 to 17), 2027 to (2 to 6), 2028 to (1 to 26), 2029 to (2 to 13), 2030 to (2 to 3),
            2031 to (1 to 23), 2032 to (2 to 11), 2033 to (1 to 31), 2034 to (2 to 19), 2035 to (2 to 8),
        )
        /** Rằm tháng Tám. */
        val MID_AUTUMN_DAY: Map<Int, Pair<Int, Int>> = mapOf(
            2026 to (9 to 25), 2027 to (9 to 15), 2028 to (10 to 3), 2029 to (9 to 22), 2030 to (9 to 12),
            2031 to (10 to 1), 2032 to (9 to 19), 2033 to (9 to 8), 2034 to (9 to 27), 2035 to (9 to 16),
        )

        fun dayNumber(y: Int, m: Int, d: Int): Int {
            val a = (14 - m) / 12
            val yy = y + 4800 - a
            val mm = m + 12 * a - 3
            val jdn = d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045
            return jdn - 2_440_588
        }

        fun ofDate(y: Int, m: Int, d: Int): BuddySeason? {
            val today = dayNumber(y, m, d)
            for (yy in intArrayOf(y, y + 1)) {
                val t = LUNAR_NEW_YEAR[yy] ?: continue
                val n = dayNumber(yy, t.first, t.second)
                if (today >= n - 10 && today <= n + 7) return TET
            }
            if (m == 12 && d in 15..26) return CHRISTMAS
            if ((m == 10 && d >= 25) || (m == 11 && d == 1)) return HALLOWEEN
            MID_AUTUMN_DAY[y]?.let { t -> if (abs(today - dayNumber(y, t.first, t.second)) <= 5) return MID_AUTUMN }
            return null
        }

        fun resolve(themeId: String?, y: Int, m: Int, d: Int): BuddySeason? = ofTheme(themeId) ?: ofDate(y, m, d)
    }
}

/** = iOS BuddyOutfit: mảnh thêm + đổi màu. */
object BuddyAccessory {
    val santa: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-17 0 Q-17 -16 -5 -22 Q10 -29 19 -14 Q11 -18 9 -8 L15 0 Z"), 0xDE5263, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M2 -22 Q10 -25 19 -14 Q11 -18 9 -8 L15 0 L4 0 Q8 -12 2 -22 Z"), 0xB93650, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-11 -10 Q-10 -17 -5 -18"), null, 1.0, Stroke.Color(0xFFB1BB), 2.0),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-16 -4 L15 -4 Q20 -4 20 1 Q20 6 15 6 L-16 6 Q-21 6 -21 1 Q-21 -4 -16 -4 Z"), 0xFFF7ED, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-17 2 Q0 5 17 1 L17 4 L-17 4 Z"), 0xE4D8D5, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M16 -18 Q23 -21 25 -14 Q27 -7 20 -6 Q13 -6 13 -12 Q12 -16 16 -18 Z"), 0xFFF7ED, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M20 -16 L22 -14"), null, 1.0, Stroke.Color(0xFFFFFF), 2.0),
    ) }
    val witch: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-22 0 Q0 -8 22 0 Q27 4 18 7 Q0 11 -20 6 Q-27 3 -22 0 Z"), 0x695185, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-15 0 Q-12 -14 -6 -23 Q-2 -31 12 -24 Q5 -25 4 -18 L14 0 Z"), 0x8C72AF, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-1 -25 Q4 -28 12 -24 Q5 -25 4 -18 L14 0 L5 0 Q0 -13 -1 -25 Z"), 0x695185, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-12 -6 L11 -6 L13 0 L-15 0 Z"), 0xF5A65B, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-3 -7 L4 -7 L4 0 L-3 0 Z"), 0xF8D77B, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-7 -16 L-5 -20"), null, 1.0, Stroke.Color(0xC9AFE3), 2.0),
    ) }
    val pumpkin: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-2 -19 L-3 -28 Q1 -31 4 -27 L3 -18 Z"), 0x799656, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M3 -24 Q13 -32 15 -23 Q8 -19 3 -24 Z"), 0xA9C879, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M0 -21 Q-15 -26 -18 -13 Q-22 1 -10 4 Q0 7 12 3 Q23 -1 18 -14 Q14 -25 0 -21 Z"), 0xF5A65B, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M9 -20 Q18 -18 18 -9 Q20 3 9 4 Q15 -9 9 -20 Z"), 0xD97B46, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-7 -17 Q-11 -14 -11 -10"), null, 1.0, Stroke.Color(0xFFDA91), 2.5),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-9 -7 Q-6 -13 -3 -7 Z M3 -7 Q6 -13 9 -7 Z M-7 -2 Q0 4 7 -2 Q0 0 -7 -2 Z"), 0x563D3C, 1.0, Stroke.None, 3.2),
    ) }
    val khanDong: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-18 0 L-18 -8 Q-17 -20 0 -20 Q17 -20 18 -8 L18 0 Q0 7 -18 0 Z"), 0xDE5263, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M8 -18 Q17 -16 18 -8 L18 0 Q0 7 -18 0 L-18 -4 Q9 2 8 -18 Z"), 0xB93650, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-14 -9 Q0 -16 14 -9 M-14 -3 Q0 -9 14 -3"), null, 1.0, Stroke.Color(0xF8D77B), 2.0),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-10 -13 L-6 -15"), null, 1.0, Stroke.Color(0xFFABB6), 2.0),
    ) }
    val bow: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M0 0 Q-18 -17 -19 -6 L-19 6 Q-18 17 0 0 Q18 -17 19 -6 L19 6 Q18 17 0 0 Z"), 0xDE5263, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-18 7 L-3 0 L-7 7 Q-18 15 -18 7 Z M18 7 L3 0 L7 7 Q18 15 18 7 Z"), 0xB93650, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-12 -5 L-8 -3 M8 -3 L12 -5"), null, 1.0, Stroke.Color(0xFFB1BB), 2.0),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-4 -4 Q0 -7 4 -4 L4 4 Q0 7 -4 4 Z"), 0xF8D77B, 1.0, Stroke.Outline, 3.2),
    ) }
    val pattern: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M0 4 Q9 9 0 14 Q-9 9 0 4 Z M-7 20 Q0 14 5 23 Q-4 29 -7 20 Z M7 31 Q14 36 7 41 Q0 36 7 31 Z"), 0xF8D77B, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M0 9 L0 28 Q0 33 7 36"), null, 1.0, Stroke.Color(0xF8D77B), 1.5),
    ) }
    val lantern: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M0 0 L13 -8 L18 1"), null, 1.0, Stroke.Color(0x8B6655), 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M18 -2 Q37 -2 37 17 Q37 36 18 36 Q-1 36 -1 17 Q-1 -2 18 -2 Z"), 0xF8D77B, 0.16, Stroke.None, 0.0),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M18 0 L22 10 L33 11 L25 19 L28 30 L18 24 L8 30 L11 19 L3 11 L14 10 Z"), 0xDE5263, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M18 4 L21 13 L29 13 L23 18 L25 26 L18 21 L11 26 L13 18 L7 13 L15 13 Z"), 0xF8D77B, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M18 9 L20 15 L18 20 L16 15 Z"), 0xFFF0B3, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M18 25 L18 36 M14 34 L14 38 M22 34 L22 38"), null, 1.0, Stroke.Color(0xF5A65B), 2.0),
    ) }
    val luckyMoney: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-11 -8 L-10 -20 L10 -20 L11 -8 Z"), 0xA9C879, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-6 -16 L5 -16"), null, 1.0, Stroke.Color(0xE7EFC7), 2.0),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-14 -11 Q0 -8 14 -11 L14 15 Q0 20 -14 15 Z"), 0xDE5263, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M8 -10 L14 -11 L14 15 Q0 20 -14 15 L-14 11 Q8 16 8 -10 Z"), 0xB93650, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-14 -11 L0 -1 L14 -11"), null, 1.0, Stroke.Color(0xF8D77B), 2.0),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M0 1 L6 7 L0 13 L-6 7 Z"), 0xF8D77B, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M19 -15 L19 -7 M15 -11 L23 -11"), null, 1.0, Stroke.Color(0xF8D77B), 2.0),
    ) }
    val gift: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-15 -6 L15 -6 L15 15 Q0 19 -15 15 Z"), 0x83B9A4, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M8 -6 L15 -6 L15 15 Q0 19 -15 15 L-15 11 L8 11 Z"), 0x5B9686, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-16 -12 L16 -12 L16 -4 L-16 -4 Z"), 0xA9D5BF, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-3 -12 L3 -12 L3 16 L-3 16 Z"), 0xF8D77B, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M0 -12 Q-17 -12 -10 -21 Q-4 -25 0 -12 Q4 -25 10 -21 Q17 -12 0 -12 Z"), 0xDE5263, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-10 -8 L-6 -8"), null, 1.0, Stroke.Color(0xE6F4DC), 2.0),
    ) }
    val candy: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-11 -7 Q-13 -27 0 -27 Q13 -27 11 -7"), null, 1.0, Stroke.Color(0x8C72AF), 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-12 -12 L-16 -19 L-8 -21 L-5 -12 M5 -12 L7 -23 L15 -20 L13 -10"), 0xF8D77B, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-16 -10 Q0 -5 16 -10 L14 11 Q0 21 -14 11 Z"), 0xF5A65B, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M9 -8 L16 -10 L14 11 Q0 21 -14 11 L-13 7 Q7 15 9 -8 Z"), 0xD97B46, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-10 -1 L-5 -6 L-2 -1 Z M2 -1 L5 -6 L10 -1 Z M-7 5 Q0 13 7 5 Q0 8 -7 5 Z"), 0x563D3C, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-11 -7 L-7 -6"), null, 1.0, Stroke.Color(0xFFDA91), 2.0),
    ) }
    val mooncake: List<BuddyPiece> by lazy { listOf(
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-15 -9 Q-20 -5 -16 0 Q-20 5 -14 8 Q-15 15 -8 15 Q-4 20 1 16 Q6 20 10 15 Q17 15 16 8 Q22 4 17 -1 Q20 -7 14 -10 Q13 -16 6 -15 Q0 -20 -6 -15 Q-13 -17 -15 -9 Z"), 0xD99450, 1.0, Stroke.Outline, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-14 5 Q0 16 16 5 L16 9 Q17 15 10 15 Q6 20 1 16 Q-4 20 -8 15 Q-15 15 -14 8 Z"), 0xB97245, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-12 -7 Q0 -17 12 -7 L12 5 Q0 14 -12 5 Z"), 0xF5C778, 1.0, Stroke.None, 3.2),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M0 -9 Q8 -9 5 -3 Q12 1 5 5 Q0 12 -5 5 Q-12 1 -5 -3 Q-8 -9 0 -9 Z"), null, 1.0, Stroke.Color(0xB97245), 2.0),
        BuddyPiece(BuddyPart.BODY, Shape.Path("M-8 -9 L-4 -10"), null, 1.0, Stroke.Color(0xFFE6A8), 2.0),
    ) }

    fun place(art: List<BuddyPiece>, part: BuddyPart, x: Double, y: Double, size: Double): List<BuddyPiece> {
        val k = size / 32
        fun f(v: Double) = String.format(Locale.US, "%.2f", v)
        return art.map { p ->
            val d = (p.shape as Shape.Path).d
            val path = BuddySVG.parse(d).joinToString(" ") { cmd -> when (cmd) {
                is BuddySVG.Cmd.Move -> "M${f(x + cmd.x * k)} ${f(y + cmd.y * k)}"
                is BuddySVG.Cmd.Line -> "L${f(x + cmd.x * k)} ${f(y + cmd.y * k)}"
                is BuddySVG.Cmd.Quad -> "Q${f(x + cmd.cx * k)} ${f(y + cmd.cy * k)} ${f(x + cmd.x * k)} ${f(y + cmd.y * k)}"
                BuddySVG.Cmd.Close -> "Z"
            } }
            BuddyPiece(part, Shape.Path(path), p.fill, p.alpha, p.stroke, p.width)
        }
    }
}

class BuddyOutfit(val pieces: List<BuddyPiece> = emptyList(), val recolor: Map<Int, Int> = emptyMap()) {
    companion object {
        const val RED = 0xDE5263
        const val GOLD = 0xF8D77B
        const val WHITE = 0xFFF7ED
        fun make(s: BuddySeason?, c: BuddyCharacter): BuddyOutfit {
            val r = BuddyRig.rig(c) ?: return BuddyOutfit()
            if (s == null) return BuddyOutfit()
            val h = r.hat; val sh = r.sleepHat
            val sn = P2(sh.x + sh.size * 1.15, sh.y + sh.size * 1.8)
            return when (s) {
                BuddySeason.TET -> when (c) {
                    BuddyCharacter.GIRL -> BuddyOutfit(
                        BuddyAccessory.place(BuddyAccessory.pattern, BuddyPart.BODY, r.neck.x, r.neck.y + 10, h.size) +
                        BuddyAccessory.place(BuddyAccessory.pattern, BuddyPart.SLEEP, sh.x + sh.size * 2.4, sh.y + sh.size * 1.4, sh.size * 0.6),
                        mapOf(0xFFB3C7 to RED, 0xDF8EAB to 0xB93650, 0xFF6F91 to GOLD, 0xFFF0F4 to GOLD))
                    BuddyCharacter.BOY -> BuddyOutfit(khanDong(BuddyPart.HEAD, h) + khanDong(BuddyPart.SLEEP, sh),
                        mapOf(0x304563 to RED, 0x536B8C to 0xF18B95))
                    else -> BuddyOutfit(bow(BuddyPart.HEAD, r.neck) + bow(BuddyPart.SLEEP, sn))
                }
                BuddySeason.CHRISTMAS -> BuddyOutfit(santa(BuddyPart.HEAD, h) + santa(BuddyPart.SLEEP, sh))
                BuddySeason.HALLOWEEN -> BuddyOutfit(if (c == BuddyCharacter.GIRL) witch(BuddyPart.HEAD, h) + witch(BuddyPart.SLEEP, sh)
                    else pumpkin(BuddyPart.HEAD, h) + pumpkin(BuddyPart.SLEEP, sh))
                BuddySeason.MID_AUTUMN -> {
                    val x = sh.x + sh.size * (if (c == BuddyCharacter.CHICK) 2.3 else 0.9)
                    val y = sh.y + sh.size * (if (c == BuddyCharacter.CHICK) 1.6 else 2.1)
                    BuddyOutfit(lantern(r.hand) + BuddyAccessory.place(BuddyAccessory.lantern, BuddyPart.SLEEP, x, y, 24.0).map {
                        BuddyPiece(BuddyPart.SLEEP, it.shape, it.fill, it.alpha, it.stroke, it.width, turn = Triple(-70.0, x, y))
                    })
                }
            }
        }
        fun santa(part: BuddyPart, a: P3) = BuddyAccessory.place(BuddyAccessory.santa, part, a.x, a.y, a.size)
        fun witch(part: BuddyPart, a: P3) = BuddyAccessory.place(BuddyAccessory.witch, part, a.x, a.y, a.size)
        fun pumpkin(part: BuddyPart, a: P3) = BuddyAccessory.place(BuddyAccessory.pumpkin, part, a.x, a.y, a.size)
        fun khanDong(part: BuddyPart, a: P3) = BuddyAccessory.place(BuddyAccessory.khanDong, part, a.x, a.y, a.size)
        fun bow(part: BuddyPart, a: P2) = BuddyAccessory.place(BuddyAccessory.bow, part, a.x, a.y, 22.0)
        fun lantern(hnd: P2) = BuddyAccessory.place(BuddyAccessory.lantern, BuddyPart.ARM_R, hnd.x, hnd.y, 24.0)
    }
}

object BuddyProp {
    fun make(reaction: BuddyReaction, r: BuddyRig): List<BuddyPiece> {
        val art = when (reaction) {
            BuddyReaction.LUCKY_MONEY -> BuddyAccessory.luckyMoney
            BuddyReaction.GIFT -> BuddyAccessory.gift
            BuddyReaction.CANDY -> BuddyAccessory.candy
            BuddyReaction.MOONCAKE -> BuddyAccessory.mooncake
            else -> return emptyList()
        }
        return BuddyAccessory.place(art, BuddyPart.BODY, r.heart.x, r.heart.y, r.heart.size * 2)
    }
}

// MARK: đường SVG rút gọn

/** M/m L/l H/h V/v Q/q Z/z — = iOS BuddySVG. */
object BuddySVG {
    sealed class Cmd {
        data class Move(val x: Double, val y: Double) : Cmd()
        data class Line(val x: Double, val y: Double) : Cmd()
        data class Quad(val cx: Double, val cy: Double, val x: Double, val y: Double) : Cmd()
        object Close : Cmd() { override fun toString() = "Close" }
    }

    fun numbers(s: String): List<Double> {
        val out = ArrayList<Double>()
        val cur = StringBuilder()
        fun flush() { cur.toString().toDoubleOrNull()?.let { out.add(it) }; cur.setLength(0) }
        for (ch in s) {
            when {
                ch.isDigit() || ch == '.' -> cur.append(ch)
                ch == '-' -> { flush(); cur.append('-') }
                else -> flush()
            }
        }
        flush()
        return out
    }

    fun parse(s: String): List<Cmd> {
        val out = ArrayList<Cmd>()
        var x = 0.0; var y = 0.0; var sx = 0.0; var sy = 0.0
        fun emit(cmd: Char, nums: List<Double>) {
            val rel = cmd.isLowerCase()
            var i = 0
            fun take(n: Int): List<Double>? = if (i + n <= nums.size) nums.subList(i, i + n).also { i += n } else null
            when (cmd.uppercaseChar()) {
                'Z' -> { out.add(Cmd.Close); x = sx; y = sy }
                'M' -> {
                    var first = true
                    while (true) {
                        val v = take(2) ?: break
                        x = if (rel) x + v[0] else v[0]; y = if (rel) y + v[1] else v[1]
                        if (first) { out.add(Cmd.Move(x, y)); sx = x; sy = y; first = false } else out.add(Cmd.Line(x, y))
                    }
                }
                'L' -> while (true) { val v = take(2) ?: break; x = if (rel) x + v[0] else v[0]; y = if (rel) y + v[1] else v[1]; out.add(Cmd.Line(x, y)) }
                'H' -> while (true) { val v = take(1) ?: break; x = if (rel) x + v[0] else v[0]; out.add(Cmd.Line(x, y)) }
                'V' -> while (true) { val v = take(1) ?: break; y = if (rel) y + v[0] else v[0]; out.add(Cmd.Line(x, y)) }
                'Q' -> while (true) {
                    val v = take(4) ?: break
                    val cx = if (rel) x + v[0] else v[0]; val cy = if (rel) y + v[1] else v[1]
                    x = if (rel) x + v[2] else v[2]; y = if (rel) y + v[3] else v[3]
                    out.add(Cmd.Quad(cx, cy, x, y))
                }
            }
        }
        var cmd = 'M'
        val token = StringBuilder()
        var started = false
        for (ch in s) {
            if (ch in "MmLlHhVvQqZz") {
                if (started) emit(cmd, numbers(token.toString()))
                cmd = ch; token.setLength(0); started = true
            } else token.append(ch)
        }
        if (started) emit(cmd, numbers(token.toString()))
        return out
    }
}

// MARK: bộ điều khiển (thuần) cho view Android

/**
 * Máy trạng thái + dáng đang hiện tại từng thời điểm cho [app/.../ime/BuddyView]: view gọi [keyPressed] / [deletePressed]
 * / [wordCommitted] (ghi giờ, không cấp phát), [update] mỗi khung hình hoặc ở mốc hẹn, rồi [poseAt] để vẽ.
 * [animating] = còn cần khung hình kế không (ngủ yên / đứng yên = false ⇒ view thôi vẽ). Nối mượt giữa trạng thái
 * = bù (cũ − mới) giảm dần trong [BuddyDance.BLEND] giây — y như hoạt ảnh bù cộng dồn của iOS.
 */
class BuddyDriver(val rig: BuddyRig, var lowPower: Boolean = false) {
    val brain = BuddyBrain()
    var season: BuddySeason? = null
    private var lastWord: String? = null
    private var lastPrev: String? = null
    private var lastPrev2: String? = null
    var shown: BuddyPhase = BuddyPhase.Asleep.QUIET; private set
    var phaseStart = 0.0; private set
    var shownSerial = 0; private set
    var character: BuddyCharacter = when (rig) {
        BuddyRig.GIRL -> BuddyCharacter.GIRL; BuddyRig.BOY -> BuddyCharacter.BOY
        BuddyRig.CHICK -> BuddyCharacter.CHICK; else -> BuddyCharacter.CAT
    }
    var danceSeed: Int = 0
    var vectorDance: Boolean = true
    private var danceLoopBase = 0
    private var danceMove = BuddyDance.Move.BOUNCE
    private var nextMoveAt = Double.POSITIVE_INFINITY
    private val loopCache = mutableMapOf<Int, List<BuddyPose>>()
    private var loopEpoch = 0.0
    private var loopLen = 1.0
    private val blendDelta = BuddyPose()
    private var blendStart = -1e9
    private val tmp = BuddyPose()
    private val tmp2 = BuddyPose()

    fun beginAppearance(seed: Int) {
        danceSeed = seed
        nextMoveAt = Double.NEGATIVE_INFINITY
    }

    fun keyPressed(t: Double) { brain.press(t) }
    fun deletePressed(t: Double) { brain.delete(t) }
    fun cheer(t: Double) { brain.cheer(t) }
    fun react(r: BuddyReaction, t: Double) { brain.react(r, t) }
    /** Ranh giới từ: tra bảng O(1); true = có phản ứng. */
    fun wordCommitted(word: String, prev: String?, prev2: String?, t: Double): Boolean {
        val prev3 = if (lastWord == prev && lastPrev == prev2) lastPrev2 else null
        lastWord = word; lastPrev = prev; lastPrev2 = prev2
        val r = BuddyWords.reaction(word, prev, prev2, prev3, season) ?: return false
        brain.react(r, t)
        return true
    }

    /** Trạng thái hiển thị tại [t] có khác đang hiện không (gọi trên đường phím — không cấp phát). */
    fun needsUpdate(t: Double): Boolean {
        val v = BuddyPolicy.visual(brain.phase(t), lowPower)
        // The key path only compares a deadline; selection/sampling happens in update/onDraw.
        val moveChanged = vectorDance && v is BuddyPhase.Dancing && shown is BuddyPhase.Dancing && t >= nextMoveAt
        return moveChanged || v !== shown || (v is BuddyPhase.React && brain.reactSerial != shownSerial)
    }

    /** Áp trạng thái tại [t]; true = vừa đổi. */
    fun update(t: Double): Boolean {
        if (!needsUpdate(t)) return false
        val v = BuddyPolicy.visual(brain.phase(t), lowPower)
        val old = displayed(t, tmp2)
        val prev = shown
        shown = v
        phaseStart = t
        val target: BuddyPose? = when (v) {
            is BuddyPhase.Asleep -> null
            BuddyPhase.Awake -> tmp.reset()
            BuddyPhase.Idle -> if (vectorDance) idlePose(0.0, tmp) else tmp.reset()
            is BuddyPhase.Dancing -> {
                val p = if (prev is BuddyPhase.Dancing) loopPhase(t) else 0.0
                danceLoopBase = if (prev is BuddyPhase.Dancing) danceLoopIndex(t) else 0
                danceMove = BuddyDance.move(character, v.tier, danceLoopBase, danceSeed)
                loopLen = BuddyDance.loopLength(v.tier)
                loopEpoch = t - p * loopLen
                nextMoveAt = loopEpoch + ((danceLoopBase / 2 + 1) * 2 - danceLoopBase) * loopLen
                if (vectorDance) dancePose(v.tier, p, tmp) else tmp.reset()
            }
            BuddyPhase.Cheering -> tmp.reset()
            is BuddyPhase.React -> { shownSerial = brain.reactSerial; BuddyDance.react(v.reaction, rig.style, 0.0, tmp) }
        }
        if (target == null || lowPower) { blendStart = -1e9; blendDelta.reset() }
        else {
            val o = old ?: tmp2.reset()
            blendDelta.dx = o.dx - target.dx; blendDelta.dy = o.dy - target.dy; blendDelta.rot = o.rot - target.rot
            blendDelta.head = o.head - target.head; blendDelta.armL = o.armL - target.armL; blendDelta.armR = o.armR - target.armR
            blendDelta.legL = o.legL - target.legL; blendDelta.legR = o.legR - target.legR; blendDelta.tail = o.tail - target.tail
            blendDelta.sx = 0.0
            blendStart = t
        }
        return true
    }

    private fun danceLoopIndex(t: Double) = danceLoopBase + max(0, floor((t - loopEpoch) / loopLen).toInt())

    private fun dancePose(tier: Int, p: Double, out: BuddyPose): BuddyPose {
        val key = tier * BuddyDance.Move.entries.size + danceMove.ordinal
        val frames = loopCache.getOrPut(key) {
            (0..48).map { BuddyDance.pose(rig.style, tier, it / 48.0, move = danceMove) }
        }
        return sample(frames, p, out)
    }

    /** Vòng lắc nhẹ ([BuddyPhase.Idle]) — dựng một lần lúc cần, cache như vòng nhảy. */
    private var idleFrames: List<BuddyPose>? = null
    private fun idlePose(p: Double, out: BuddyPose): BuddyPose {
        val frames = idleFrames ?: (0..48).map { BuddyDance.idle(rig.style, it / 48.0) }.also { idleFrames = it }
        return sample(frames, p - floor(p), out)
    }

    private fun sample(frames: List<BuddyPose>, p: Double, out: BuddyPose): BuddyPose {
        val x = (p * 48).coerceIn(0.0, 48.0); val i = min(47, x.toInt()); val f = x - i
        val a = frames[i]; val b = frames[i + 1]
        out.dx = a.dx + (b.dx - a.dx) * f; out.dy = a.dy + (b.dy - a.dy) * f
        out.rot = a.rot + (b.rot - a.rot) * f; out.sx = a.sx + (b.sx - a.sx) * f
        out.head = a.head + (b.head - a.head) * f
        out.armL = a.armL + (b.armL - a.armL) * f; out.armR = a.armR + (b.armR - a.armR) * f
        out.legL = a.legL + (b.legL - a.legL) * f; out.legR = a.legR + (b.legR - a.legR) * f
        out.tail = a.tail + (b.tail - a.tail) * f
        return out
    }

    private fun loopPhase(t: Double): Double { val x = (t - loopEpoch) / loopLen; return x - floor(x) }

    /** Độ dài vòng phản ứng (hoảng: lặp 0,5 s). */
    fun reactLength(r: BuddyReaction) = if (r == BuddyReaction.PANIC) 0.5 else r.duration

    private fun displayed(t: Double, out: BuddyPose): BuddyPose? = when (val s = shown) {
        is BuddyPhase.Asleep -> null
        BuddyPhase.Awake -> out.reset()
        BuddyPhase.Idle -> if (vectorDance) idlePose((t - phaseStart) / BuddyDance.IDLE_LOOP, out) else out.reset()
        is BuddyPhase.Dancing -> if (vectorDance) dancePose(s.tier, loopPhase(t), out) else out.reset()
        BuddyPhase.Cheering -> BuddyDance.cheer(rig.style, (t - phaseStart) / BuddyBrain.CHEER, out)
        is BuddyPhase.React -> {
            var f = (t - phaseStart) / reactLength(s.reaction)
            if (s.reaction == BuddyReaction.PANIC) f -= floor(f)
            BuddyDance.react(s.reaction, rig.style, f, out)
        }
    }

    /** Dáng vẽ tại [t] (ghi vào [out]); null = đang ngủ (vẽ nhóm ngủ). */
    fun poseAt(t: Double, out: BuddyPose): BuddyPose? {
        val p = displayed(t, out) ?: return null
        val k = (t - blendStart) / BuddyDance.BLEND
        if (k in 0.0..1.0) {
            val e = 1 - (1 - (1 - k) * (1 - k))   // easeOut: còn lại (1−k)²
            p.dx += blendDelta.dx * e; p.dy += blendDelta.dy * e; p.rot += blendDelta.rot * e
            p.head += blendDelta.head * e; p.armL += blendDelta.armL * e; p.armR += blendDelta.armR * e
            p.legL += blendDelta.legL * e; p.legR += blendDelta.legR * e; p.tail += blendDelta.tail * e
        }
        return p
    }

    /** Còn cần vẽ khung kế tại [t] không — ngủ yên / đứng yên (hết nối) = false. */
    fun animating(t: Double): Boolean {
        if (lowPower) return false
        return when (val s = shown) {
            is BuddyPhase.Asleep -> s.zzz
            BuddyPhase.Awake -> t - blendStart < BuddyDance.BLEND
            else -> true
        }
    }

    /** Mốc tự đổi kế (để hẹn một lần gọi [update]); null = ngủ yên. */
    fun nextDeadline(t: Double): Double? {
        val deadline = brain.nextDeadline(t)
        return if (vectorDance && shown is BuddyPhase.Dancing) min(deadline ?: nextMoveAt, nextMoveAt) else deadline
    }
}
