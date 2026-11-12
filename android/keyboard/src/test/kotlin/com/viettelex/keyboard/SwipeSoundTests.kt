package com.viettelex.keyboard

import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin
import org.junit.After
import org.junit.Before
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * "Âm thanh nét vuốt" ([SwipeSoundStyle]) — model/id/cổng Plus/chính sách, đường cong tốc độ → âm lượng, vỏ âm lượng
 * (tắt dần 100 ms), mẫu lặp tất định + checksum (= iOS SwipeSoundTests, cùng số tham chiếu), chỗ nối vòng liền mạch.
 */
class SwipeSoundTests {
    private var savedPaywall = PlusGate.paywallEnabled

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled }
    @After fun tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.install({ null }, debugBuild = false)
    }

    private fun plus(on: Boolean) {
        PlusGate.paywallEnabled = true
        PlusGate.install({ if (on && it == Keys.PLUS_UNLOCKED) true else null }, debugBuild = false)
    }

    @Test fun idsTitlesAndDefaults() {
        assertEquals(listOf("none", "pencil", "brush", "chalk", "marker", "whip", "lightning", "plasma", "wand", "custom"),
            SwipeSoundStyle.entries.map { it.id })
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.DEFAULT)
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.of(null))
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.of("loud"))
        assertEquals(SwipeSoundStyle.CHALK, SwipeSoundStyle.of("chalk"))
        assertEquals("swipeSound", Keys.SWIPE_SOUND)
        assertEquals(listOf(false, false, true, true, true, true, true, true, true, true), SwipeSoundStyle.entries.map { it.isPlus })
        assertEquals(listOf("Tắt", "Bút chì", "Chổi lông", "Phấn bảng", "Bút dạ", "Roi vụt", "Tia sét", "Plasma", "Đũa phép", "Âm của bạn"),
            SwipeSoundStyle.entries.map { it.viTitle })
        assertEquals(listOf(SwipeSoundStyle.WHIP, SwipeSoundStyle.LIGHTNING, SwipeSoundStyle.PLASMA, SwipeSoundStyle.WAND),
            SwipeSoundStyle.entries.filter { it.hasLift })
        assertEquals(8, SwipeSoundStyle.SYNTHESIZED.size)
        assertFalse(SwipeSoundStyle.CUSTOM in SwipeSoundStyle.SYNTHESIZED)
        assertEquals(SwipeSoundStyle.WAND, SwipeSoundStyle.of("wand"))
        assertEquals(SwipeSoundStyle.CUSTOM, SwipeSoundStyle.of("custom"))
        for (s in SwipeSoundStyle.entries) assertTrue(L10nTable.EN.containsKey(s.viTitle), s.viTitle)
    }

    @Test fun settingsLoadAndBackupSpec() {
        assertEquals(SwipeSoundStyle.NONE, KeyboardSettings().swipeSound)
        assertEquals(SwipeSoundStyle.NONE, KeyboardSettings.load { null }.swipeSound)
        assertEquals(SwipeSoundStyle.BRUSH, KeyboardSettings.load { if (it == Keys.SWIPE_SOUND) "brush" else null }.swipeSound)
        val spec = BackupSettings.all.first { it.key == Keys.SWIPE_SOUND }
        assertEquals(SettingKind.Choice("none", setOf("none", "pencil", "brush", "chalk", "marker", "whip", "lightning", "plasma",
            "wand", "custom")), spec.kind)
    }

    @Test fun plusGateAndPolicy() {
        // Hiện ở dòng cài đặt: kiểu Plus khi chưa có Plus ⇒ Bút chì (giá trị lưu giữ nguyên).
        assertEquals(SwipeSoundStyle.PENCIL, SwipeSoundStyle.displayed("marker", plus = false))
        assertEquals(SwipeSoundStyle.MARKER, SwipeSoundStyle.displayed("marker", plus = true))
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.displayed("none", plus = false))
        val p = SwipeSoundPolicy
        assertEquals(SwipeSoundStyle.NONE, p.active(SwipeSoundStyle.NONE, plus = true, powerSave = false, volumePercent = 50))
        assertEquals(SwipeSoundStyle.NONE, p.active(SwipeSoundStyle.PENCIL, true, false, 0), "âm lượng 0 ⇒ không dựng gì")
        assertEquals(SwipeSoundStyle.PENCIL, p.active(SwipeSoundStyle.PENCIL, plus = false, powerSave = true, volumePercent = 50))
        assertEquals(SwipeSoundStyle.PENCIL, p.active(SwipeSoundStyle.BRUSH, plus = false, powerSave = false, volumePercent = 50))
        assertEquals(SwipeSoundStyle.PENCIL, p.active(SwipeSoundStyle.CHALK, plus = true, powerSave = true, volumePercent = 50))
        assertEquals(SwipeSoundStyle.MARKER, p.active(SwipeSoundStyle.MARKER, plus = true, powerSave = false, volumePercent = 1))
        for (s in listOf(SwipeSoundStyle.WHIP, SwipeSoundStyle.LIGHTNING, SwipeSoundStyle.PLASMA, SwipeSoundStyle.WAND, SwipeSoundStyle.CUSTOM)) {
            assertEquals(SwipeSoundStyle.PENCIL, p.active(s, plus = false, powerSave = false, volumePercent = 50), "${s.id} cần Plus")
            assertEquals(s, p.active(s, plus = true, powerSave = false, volumePercent = 50))
            assertEquals(SwipeSoundStyle.PENCIL, SwipeSoundStyle.displayed(s.id, plus = false))
        }
        // Cổng = cổng Hiệu ứng nét vuốt.
        plus(false)
        assertFalse(SwipeSoundGate.allows); assertTrue(SwipeSoundGate.allows(SwipeSoundStyle.PENCIL))
        assertFalse(SwipeSoundGate.allows(SwipeSoundStyle.CHALK))
        assertFalse(SwipeSoundGate.allows(SwipeSoundStyle.WHIP)); assertFalse(SwipeSoundGate.allows(SwipeSoundStyle.CUSTOM))
        plus(true)
        assertEquals(SwipeTrailGate.allows, SwipeSoundGate.allows); assertTrue(SwipeSoundGate.allows(SwipeSoundStyle.CHALK))
    }

    @Test fun speedToVolume() {
        val f = SwipeSoundFx
        assertEquals(0.0, f.speedGain(0.0), 0.0)
        assertEquals(0.0, f.speedGain(f.SPEED_MIN), 0.0, "đứng yên / rê chậm ⇒ im")
        assertEquals(0.5, f.speedGain(f.SPEED_MIN + 0.25 * (f.SPEED_FULL - f.SPEED_MIN)), 1e-12)
        assertEquals(1.0, f.speedGain(f.SPEED_FULL), 1e-12)
        assertEquals(1.0, f.speedGain(9000.0), 0.0, "trần 1")
        assertEquals(0.576361, f.speedGain(525.0), 1e-6)   // số tham chiếu chung iOS
        var last = -1.0
        for (v in 0..2000 step 50) { val g = f.speedGain(v.toDouble()); assertTrue(g >= last); last = g }   // đơn điệu
        assertEquals(0.7, f.target(0.7, 0.05), 0.0)
        assertEquals(0.0, f.target(0.7, f.HOLD + 0.001), 0.0, "ngón dừng quá HOLD ⇒ im")
        assertEquals(0.632121, f.smooth(0.0, 1.0, f.SPEED_TAU), 1e-6)
        assertEquals(f.smooth(0.0, 1.0, f.MAX_DT), f.smooth(0.0, 1.0, 5.0), 0.0, "dt kẹp MAX_DT")
    }

    @Test fun meterFollowsFingerSpeed() {
        val m = SwipeSoundMeter()
        m.reset(0.0, 0.0, 0.0)
        // 600 pt/s đều trong 0,5 s (120 Hz) ⇒ hội tụ ~600.
        var t = 0.0; var x = 0.0
        repeat(60) { t += 1.0 / 120; x += 5.0; m.move(x, 0.0, t) }
        assertEquals(600.0, m.speed, 1.0)
        assertEquals(SwipeSoundFx.speedGain(m.speed), m.gain, 0.0)
        // Điểm gộp trùng giờ: bỏ qua (không chia cho 0), quãng đường tính vào điểm sau.
        val before = m.speed
        m.move(x + 50, 0.0, t)
        assertEquals(before, m.speed, 0.0)
        m.move(x + 10, 0.0, t + 1.0 / 60)
        assertEquals(before, m.speed, 1.0)   // 10 pt / (1/60 s) = 600 pt/s
        m.reset(0.0, 0.0, 1.0)
        assertEquals(0.0, m.speed, 0.0)
    }

    @Test fun envelopeRampsAndFadesOutIn100ms() {
        val sr = KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble()
        val e = SwipeSoundEnvelope(1 / sr)
        repeat((0.2 * sr).toInt()) { e.next(0.8) }
        assertEquals(0.8, e.gain, 2e-3, "tiến về đích")
        e.release()
        var n = 0
        while (!e.finished) { e.next(1.0); n++; assertTrue(n < sr) }   // đích bị bỏ qua khi đang tắt dần
        assertEquals(SwipeSoundFx.FADE_OUT * sr, n.toDouble(), 2.0, "tắt dần ~FADE_OUT")
        assertEquals(0.0, e.gain, 0.0)
        // Vuốt lại: begin() bỏ tắt dần, mở từ 0.
        e.begin(); e.next(1.0); assertTrue(e.gain > 0 && e.gain < 0.01)
        // Android: nhịp 25 ms ⇒ 4 nhịp là im.
        val a = SwipeSoundEnvelope(SwipeSoundFx.TICK)
        repeat(20) { a.next(0.5) }
        a.release()
        var k = 0
        while (!a.finished) { a.next(0.5); k++ }
        assertEquals(4, k, "FADE_OUT / TICK")
        // Đích 0 (ngón dừng) ⇒ nhỏ dần theo RAMP_TAU, không tắt hẳn đột ngột.
        val b = SwipeSoundEnvelope(1 / sr)
        repeat((0.2 * sr).toInt()) { b.next(1.0) }
        repeat((SwipeSoundFx.RAMP_TAU * sr).toInt()) { b.next(0.0) }
        assertEquals(0.367879, b.gain, 2e-3)
    }

    @Test fun loopsAreDeterministicSoftAndSeamless() {
        val sr = KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble()
        assertEquals(0, KeySoundSynth.swipeLoopSamples(SwipeSoundStyle.NONE).size)
        assertEquals(0, KeySoundSynth.swipePreviewSamples(SwipeSoundStyle.NONE).size)
        assertTrue(KeySoundSynth.swipeLoopSamples(SwipeSoundStyle.CUSTOM).contentEquals(KeySoundSynth.swipeLoopSamples(SwipeSoundStyle.PENCIL)),
            "Âm của bạn: dự phòng Bút chì")
        val sums = ArrayList<String>()
        for (s in SwipeSoundStyle.SYNTHESIZED) {
            val x = KeySoundSynth.swipeLoopSamples(s)
            assertTrue(x.contentEquals(KeySoundSynth.swipeLoopSamples(s)), "tất định ${s.id}")
            assertEquals((KeySoundSynth.swipeLoopSeconds(s) * sr).roundToInt(), x.size)
            assertTrue(x.size in (0.8 * sr).toInt()..(1.5 * sr).toInt())
            val peak = x.maxOf { abs(it) }.toDouble()
            assertEquals(KeySoundSynth.swipePeak(s), peak, 1e-6)
            assertTrue(peak <= 0.34 + 1e-6, "nhỏ: ${s.id}")
            val r = KeySoundSynth.rms(x)
            assertTrue(r in 0.02..0.12, "êm, không câm: ${s.id} rms=$r")
            // Chỗ nối vòng (mẫu cuối → mẫu đầu) không phải bước nhảy lớn nhất của chính tiếng đó ⇒ không "tách".
            var maxStep = 0.0
            for (i in 1 until x.size) maxStep = maxOf(maxStep, abs(x[i] - x[i - 1]).toDouble())
            val seam = abs(x[0] - x[x.size - 1]).toDouble()
            assertTrue(seam <= maxStep * 0.9, "nối vòng ${s.id}: $seam vs $maxStep")
            // Năng lượng đều quanh chỗ nối: 20 ms cuối ≈ 20 ms đầu (không hụt/dội âm lượng).
            val w = (0.02 * sr).toInt()
            val head = KeySoundSynth.rms(x.copyOfRange(0, w)); val tail = KeySoundSynth.rms(x.copyOfRange(x.size - w, x.size))
            assertTrue(head / tail in 0.4..2.5, "vỏ quanh chỗ nối ${s.id}: $head / $tail")
            val sum = x.sumOf { abs(it).toDouble() }
            sums += "${s.id}=" + "%.4f".format(sum)
            println("SWIPE-SOUND-GOLDEN ${s.id}=" + "%.4f".format(sum))
        }
        for (s in SwipeSoundStyle.SYNTHESIZED) {
            val sum = KeySoundSynth.swipeLoopSamples(s).sumOf { abs(it).toDouble() }
            assertEquals(GOLDEN.getValue(s), sum, 0.01, "checksum chung iOS: ${s.id}")
        }
        // Âm sắc: Bút chì sáng nhất, Chổi lông trầm nhất (trọng tâm phổ, khung 2048 mẫu).
        fun centroid(s: SwipeSoundStyle) = KeySoundSynth.spectralCentroid(KeySoundSynth.swipeLoopSamples(s).copyOfRange(4000, 6048), sr)
        val c = SwipeSoundStyle.SYNTHESIZED.associateWith { centroid(it) }
        println("SWIPE-SOUND-CENTROID $c")
        assertTrue(c.getValue(SwipeSoundStyle.BRUSH) < 2600, "chổi lông trầm-trung")
        assertTrue(c.getValue(SwipeSoundStyle.PENCIL) > c.getValue(SwipeSoundStyle.MARKER))
        assertTrue(c.getValue(SwipeSoundStyle.PENCIL) > c.getValue(SwipeSoundStyle.BRUSH))
        assertTrue(c.getValue(SwipeSoundStyle.CHALK) > c.getValue(SwipeSoundStyle.BRUSH))
        assertTrue(c.getValue(SwipeSoundStyle.WHIP) > c.getValue(SwipeSoundStyle.BRUSH) + 1000, "roi vụt sáng/gió hơn chổi lông")
        assertTrue(c.getValue(SwipeSoundStyle.PLASMA) < c.getValue(SwipeSoundStyle.WHIP), "plasma ù trầm")
    }

    @Test fun layerAndLiftSamples() {
        val sr = KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble()
        for (s in SwipeSoundStyle.entries) if (s != SwipeSoundStyle.WAND) assertEquals(0, KeySoundSynth.swipeLayerSamples(s).size, s.id)
        val layer = KeySoundSynth.swipeLayerSamples(SwipeSoundStyle.WAND)
        assertTrue(layer.contentEquals(KeySoundSynth.swipeLayerSamples(SwipeSoundStyle.WAND)))
        assertEquals(KeySoundSynth.swipeLoopSamples(SwipeSoundStyle.WAND).size, layer.size)
        assertEquals(KeySoundSynth.SWIPE_LAYER_PEAK, layer.maxOf { abs(it) }.toDouble(), 1e-6)
        val lsum = layer.sumOf { abs(it).toDouble() }
        println("SWIPE-LAYER-GOLDEN wand=" + "%.4f".format(lsum))
        assertEquals(LAYER_GOLDEN, lsum, 0.01)
        for (s in SwipeSoundStyle.entries) if (!s.hasLift) assertEquals(0, KeySoundSynth.swipeLiftSamples(s).size, s.id)
        for (s in SwipeSoundStyle.entries.filter { it.hasLift }) {
            val x = KeySoundSynth.swipeLiftSamples(s)
            assertTrue(x.contentEquals(KeySoundSynth.swipeLiftSamples(s)), "tất định ${s.id}")
            assertTrue(x.size in (0.12 * sr).toInt()..(0.35 * sr).toInt(), "ngắn: ${s.id} ${x.size}")
            val peak = x.maxOf { abs(it) }.toDouble()
            assertTrue(peak <= 0.55 + 1e-6 && peak > 0.3, "đỉnh ${s.id}: $peak")
            assertTrue(abs(x[x.size - 1]) < 1e-3, "đóng mềm ${s.id}")
            val sum = x.sumOf { abs(it).toDouble() }
            println("SWIPE-LIFT-GOLDEN ${s.id}=" + "%.4f".format(sum))
            assertEquals(LIFT_GOLDEN.getValue(s), sum, 0.01, "checksum chung iOS: ${s.id}")
        }
        // Roi vụt: "chát" — đỉnh trong 10 ms đầu, đuôi nhiễu ngắn, dài 120–200 ms.
        val crack = KeySoundSynth.swipeLiftSamples(SwipeSoundStyle.WHIP)
        assertTrue(crack.size in (0.12 * sr).toInt()..(0.2 * sr).toInt())
        val iPeak = crack.indices.maxByOrNull { abs(crack[it]) } ?: 0
        assertTrue(iPeak < (0.01 * sr).toInt(), "đỉnh ở đầu")
        val w = (0.02 * sr).toInt(); val tail = (0.05 * sr).toInt()
        assertTrue(KeySoundSynth.rms(crack.copyOfRange(0, w)) > 5 * KeySoundSynth.rms(crack.copyOfRange(crack.size - tail, crack.size)))
        val zw = KeySoundSynth.swipeLiftSamples(SwipeSoundStyle.PLASMA); val h = zw.size / 2
        assertTrue(KeySoundSynth.spectralCentroid(zw.copyOfRange(h, zw.size), sr) > KeySoundSynth.spectralCentroid(zw.copyOfRange(0, h), sr),
            "plasma víu đi lên")
    }

    @Test fun liftGainFollowsLastWindowSpeed() {
        val f = SwipeSoundFx
        assertEquals(0.0, f.liftGain(0.0), 0.0)
        assertEquals(0.0, f.liftGain(f.LIFT_MIN), 0.0, "gần như đứng yên ⇒ không kêu")
        assertEquals(1.0, f.liftGain(f.SPEED_FULL), 1e-12)
        assertEquals(1.0, f.liftGain(9000.0), 0.0)
        assertEquals(0.527046, f.liftGain(525.0), 1e-6)   // số tham chiếu chung iOS
        val m = SwipeSoundMeter()
        m.reset(0.0, 0.0, 0.0)
        var t = 0.0; var x = 0.0
        repeat(60) { t += 1.0 / 120; x += 8.0; m.move(x, 0.0, t) }   // 960 dp/s
        assertEquals(960.0, m.recentSpeed(t), 960 * 0.15, "nhấc ngay: ~tốc độ 80 ms cuối")
        assertEquals(0.0, m.recentSpeed(t + 0.1), 0.0, "dừng 100 ms rồi mới nhấc ⇒ 0")
        repeat(12) { t += 1.0 / 120; x += 0.5; m.move(x, 0.0, t) }
        assertTrue(m.recentSpeed(t) < 100)
        assertEquals(0.0, f.liftGain(m.recentSpeed(t)), 0.0)
        val n = SwipeSoundMeter()
        n.reset(0.0, 0.0, 0.0)
        var tt = 0.0
        for (i in 1..120) { tt = i / 240.0; n.move(i * 5.0, 0.0, tt) }   // 1200 dp/s, vòng đệm đầy
        assertEquals(1200.0, n.recentSpeed(tt), 1200 * 0.1)
        n.reset(0.0, 0.0, tt)
        assertEquals(0.0, n.recentSpeed(tt), 0.0)
    }

    private fun sine(seconds: Double, rate: Double, freq: Double = 440.0, amp: Float = 0.9f, lead: Double = 0.0): FloatArray =
        FloatArray(((seconds + lead) * rate).toInt()) { i ->
            val t = i / rate - lead
            if (t < 0) 0f else amp * sin(2 * PI * freq * t).toFloat()
        }

    @Test fun customProcessTrimsNormalisesAndLoopsSeamlessly() {
        val sr = KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble()
        val long = SwipeSoundCustom.process(sine(5.0, 44_100.0, lead = 0.3), 44_100.0)
        assertTrue(long.truncated)
        assertEquals((SwipeSoundCustom.MAX_DURATION * sr).toInt(), long.samples.size, "đúng 3 s")
        assertEquals(SwipeSoundCustom.TARGET_PEAK.toDouble(), long.samples.maxOf { abs(it) }.toDouble(), 1e-4)
        assertEquals(KeySoundSynth.swipePeak(SwipeSoundStyle.PENCIL), SwipeSoundCustom.TARGET_PEAK.toDouble(), 1e-6)
        assertTrue(KeySoundSynth.rms(long.samples.copyOfRange(0, (0.05 * sr).toInt())) > 0.1, "lặng đầu đã bỏ")
        for (r in listOf(long.samples, SwipeSoundCustom.process(sine(1.5, 48_000.0, freq = 523.0), 48_000.0).samples)) {
            var maxStep = 0f
            for (i in 1 until r.size) maxStep = maxOf(maxStep, abs(r[i] - r[i - 1]))
            assertTrue(abs(r[0] - r[r.size - 1]) <= maxStep * 1.05f, "nối vòng không tách")
        }
        val mid = SwipeSoundCustom.process(sine(1.5, sr), sr)
        assertFalse(mid.truncated)
        assertTrue(abs((1.5 * sr).toInt() - (KeySoundSynth.SWIPE_CROSSFADE * sr).roundToInt() - mid.samples.size) <= 2)
        val short = SwipeSoundCustom.process(sine(0.1, sr), sr)
        assertTrue(short.samples.size >= (SwipeSoundCustom.MIN_LOOP * sr).toInt())
        assertTrue(short.samples.size <= (SwipeSoundCustom.MAX_DURATION * sr).toInt())
        assertFailsWith<SwipeSoundCustom.Failure> { SwipeSoundCustom.process(FloatArray(0), sr) }
        assertFailsWith<SwipeSoundCustom.Failure> { SwipeSoundCustom.process(FloatArray(5000), sr) }
    }

    @Test fun customLoadFallback() {
        val dir = java.nio.file.Files.createTempDirectory("ss").toFile()
        try {
            val f = File(dir, SwipeSoundCustom.FILE_NAME)
            assertNull(SwipeSoundCustom.load(null))
            assertNull(SwipeSoundCustom.load(f), "vắng")
            assertTrue(SwipeSoundCustom.resolvedLoop(SwipeSoundCustom.load(f)).contentEquals(KeySoundSynth.swipeLoopSamples(SwipeSoundStyle.PENCIL)))
            f.writeText("not a wav")
            assertNull(SwipeSoundCustom.load(f), "hỏng")
            val sr = KeySoundSynth.SWIPE_SAMPLE_RATE
            f.writeBytes(KeySoundSynth.wav(sine(4.0, sr.toDouble()), sr))
            assertNull(SwipeSoundCustom.load(f), "quá dài ⇒ không tin")
            val loop = SwipeSoundCustom.process(sine(4.0, 48_000.0, lead = 0.25), 48_000.0).samples
            f.writeBytes(KeySoundSynth.wav(loop, sr))
            val back = SwipeSoundCustom.load(f)!!
            assertEquals(loop.size, back.size)
            assertEquals(SwipeSoundCustom.TARGET_PEAK.toDouble(), back.maxOf { abs(it) }.toDouble(), 2e-3)
            assertTrue(SwipeSoundCustom.resolvedLoop(back).contentEquals(back))
            assertEquals((KeySoundSynth.SWIPE_PREVIEW * sr).roundToInt(), KeySoundSynth.swipePreview(back).size)
        } finally { dir.deleteRecursively() }
    }

    @Test fun previewFollowsDemoSwipeAndFadesOut() {
        val sr = KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble()
        assertEquals(0.0, KeySoundSynth.swipeDemoSpeed(0.0), 0.0)
        assertEquals(0.0, KeySoundSynth.swipeDemoSpeed(KeySoundSynth.SWIPE_PREVIEW_LIFT), 0.0)
        assertEquals(675.0, KeySoundSynth.swipeDemoSpeed(KeySoundSynth.SWIPE_PREVIEW_LIFT / 2), 1e-9)   // giữa nét: chậm lại ở phím
        for (s in SwipeSoundStyle.SYNTHESIZED) {
            val p = KeySoundSynth.swipePreviewSamples(s)
            val shot = KeySoundSynth.swipeLiftSamples(s)
            val liftAt = (KeySoundSynth.SWIPE_PREVIEW_LIFT * sr).roundToInt()
            assertEquals(maxOf((KeySoundSynth.SWIPE_PREVIEW * sr).toInt(), liftAt + shot.size), p.size)
            assertTrue(p.contentEquals(KeySoundSynth.swipePreviewSamples(s)))
            val lift = (KeySoundSynth.SWIPE_PREVIEW_LIFT * sr).toInt()
            val fadeEnd = lift + (SwipeSoundFx.FADE_OUT * sr).toInt() + 2
            for (i in fadeEnd until p.size) {
                val k = i - liftAt
                val want = if (k < shot.size) (shot[k].toDouble() * SwipeSoundFx.PREVIEW_LIFT_GAIN).toFloat() else 0f
                assertEquals(want.toDouble(), p[i].toDouble(), 0.0, "sau tắt dần chỉ còn tiếng nhấc tay (${s.id})")
            }
            assertTrue(abs(p[0]) < 1e-3, "mở từ 0")
            val cap = KeySoundSynth.swipePeak(s) + (if (s == SwipeSoundStyle.WAND) KeySoundSynth.SWIPE_LAYER_PEAK else 0.0) +
                (shot.maxOfOrNull { abs(it) }?.toDouble() ?: 0.0) * SwipeSoundFx.PREVIEW_LIFT_GAIN
            assertTrue(p.maxOf { abs(it) } <= cap + 1e-6)
            val sum = p.sumOf { abs(it).toDouble() }
            println("SWIPE-PREVIEW-GOLDEN ${s.id}=" + "%.4f".format(sum))
            assertEquals(PREVIEW_GOLDEN.getValue(s), sum, 0.01)
        }
    }

    private companion object {
        val GOLDEN = mapOf(
            SwipeSoundStyle.PENCIL to 1060.9227,
            SwipeSoundStyle.BRUSH to 1786.0301,
            SwipeSoundStyle.CHALK to 932.4742,
            SwipeSoundStyle.MARKER to 1379.6404,
            SwipeSoundStyle.WHIP to 1272.6721,
            SwipeSoundStyle.LIGHTNING to 878.1293,
            SwipeSoundStyle.PLASMA to 1586.8690,
            SwipeSoundStyle.WAND to 1352.8294,
        )
        val PREVIEW_GOLDEN = mapOf(
            SwipeSoundStyle.PENCIL to 593.6883,
            SwipeSoundStyle.BRUSH to 842.1863,
            SwipeSoundStyle.CHALK to 364.0651,
            SwipeSoundStyle.MARKER to 786.1841,
            SwipeSoundStyle.WHIP to 786.1677,
            SwipeSoundStyle.LIGHTNING to 579.4536,
            SwipeSoundStyle.PLASMA to 1061.6143,
            SwipeSoundStyle.WAND to 1066.6231,
        )
        val LIFT_GOLDEN = mapOf(
            SwipeSoundStyle.WHIP to 94.7710,
            SwipeSoundStyle.LIGHTNING to 239.0145,
            SwipeSoundStyle.PLASMA to 434.8444,
            SwipeSoundStyle.WAND to 581.7851,
        )
        const val LAYER_GOLDEN = 906.3455
    }
}
