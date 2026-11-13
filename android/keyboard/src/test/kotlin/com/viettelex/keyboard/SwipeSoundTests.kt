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
 * Đợt 2 (Nốt nhạc theo phím, Sáo trúc, Sóng biển, Mèo kêu, Chim hót): bảng phím → nốt + dò phím (lõi, mỗi phím một nốt),
 * cao độ sáo, lịch tiếng hót, bộ nốt / vòng / lớp / tiếng nhấc tay / bản nghe thử tất định + checksum chung iOS.
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
        assertEquals(listOf("none", "pencil", "brush", "chalk", "marker", "whip", "lightning", "plasma", "wand", "notes", "flute",
            "waves", "cat", "birds", "custom"), SwipeSoundStyle.entries.map { it.id })
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.DEFAULT)
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.of(null))
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.of("loud"))
        assertEquals(SwipeSoundStyle.CHALK, SwipeSoundStyle.of("chalk"))
        assertEquals("swipeSound", Keys.SWIPE_SOUND)
        assertEquals(listOf(false, false) + List(13) { true }, SwipeSoundStyle.entries.map { it.isPlus })
        assertEquals(listOf("Tắt", "Bút chì", "Chổi lông", "Phấn bảng", "Bút dạ", "Roi vụt", "Tia sét", "Plasma", "Đũa phép",
            "Nốt nhạc theo phím", "Sáo trúc", "Sóng biển", "Mèo kêu", "Chim hót", "Âm của bạn"), SwipeSoundStyle.entries.map { it.viTitle })
        assertEquals(listOf(SwipeSoundStyle.WHIP, SwipeSoundStyle.LIGHTNING, SwipeSoundStyle.PLASMA, SwipeSoundStyle.WAND,
            SwipeSoundStyle.WAVES, SwipeSoundStyle.CAT, SwipeSoundStyle.BIRDS), SwipeSoundStyle.entries.filter { it.hasLift })
        assertEquals(12, SwipeSoundStyle.SYNTHESIZED.size)
        assertFalse(SwipeSoundStyle.CUSTOM in SwipeSoundStyle.SYNTHESIZED)
        assertFalse(SwipeSoundStyle.NOTES in SwipeSoundStyle.SYNTHESIZED, "Nốt nhạc theo phím không có vòng lặp")
        assertEquals(listOf(SwipeSoundStyle.NOTES), SwipeSoundStyle.entries.filter { it.isNotes })
        assertEquals(listOf(SwipeSoundStyle.FLUTE), SwipeSoundStyle.entries.filter { it.followsX })
        assertEquals(listOf(SwipeSoundStyle.NOTES, SwipeSoundStyle.FLUTE), SwipeSoundStyle.entries.filter { it.needsLayout })
        assertEquals("Key melody", L10nTable.EN["Nốt nhạc theo phím"])
        assertEquals("Vietnamese flute", L10nTable.EN["Sáo trúc"])
        assertEquals(SwipeSoundStyle.BIRDS, SwipeSoundStyle.of("birds"))
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
            "wand", "notes", "flute", "waves", "cat", "birds", "custom")), spec.kind)
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
        for (s in listOf(SwipeSoundStyle.WHIP, SwipeSoundStyle.LIGHTNING, SwipeSoundStyle.PLASMA, SwipeSoundStyle.WAND, SwipeSoundStyle.NOTES,
                SwipeSoundStyle.FLUTE, SwipeSoundStyle.WAVES, SwipeSoundStyle.CAT, SwipeSoundStyle.BIRDS, SwipeSoundStyle.CUSTOM)) {
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
        // Sáo trúc: tắt dần chậm hơn (FLUTE_RELEASE 250 ms; nhịp 25 ms ⇒ 10 nhịp).
        assertEquals(SwipeSoundFx.FLUTE_RELEASE, SwipeSoundFx.release(SwipeSoundStyle.FLUTE), 0.0)
        assertEquals(SwipeSoundFx.FADE_OUT, SwipeSoundFx.release(SwipeSoundStyle.PENCIL), 0.0)
        val f = SwipeSoundEnvelope(1 / sr, SwipeSoundFx.release(SwipeSoundStyle.FLUTE))
        repeat((0.2 * sr).toInt()) { f.next(0.8) }
        f.release()
        var m = 0
        while (!f.finished) { f.next(1.0); m++; assertTrue(m < sr) }
        assertEquals(SwipeSoundFx.FLUTE_RELEASE * sr, m.toDouble(), 2.0)
        val ft = SwipeSoundEnvelope(SwipeSoundFx.TICK, SwipeSoundFx.FLUTE_RELEASE)
        repeat(20) { ft.next(0.5) }
        ft.release()
        var q = 0
        while (!ft.finished) { ft.next(0.5); q++ }
        assertTrue(q in 10..11, "FLUTE_RELEASE / TICK: $q")   // 0,025/0,25 không chẵn nhị phân
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
        assertTrue(c.getValue(SwipeSoundStyle.CAT) < 2000, "mèo rừ trầm")
        assertTrue(c.getValue(SwipeSoundStyle.CAT) < c.getValue(SwipeSoundStyle.WAVES))
        assertTrue(c.getValue(SwipeSoundStyle.WAVES) < c.getValue(SwipeSoundStyle.WHIP), "sóng trầm hơn roi vụt")
    }

    @Test fun layerAndLiftSamples() {
        val sr = KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble()
        val layered = listOf(SwipeSoundStyle.WAND, SwipeSoundStyle.BIRDS)
        for (s in SwipeSoundStyle.entries) if (s !in layered) assertEquals(0, KeySoundSynth.swipeLayerSamples(s).size, s.id)
        for (s in layered) {
            val layer = KeySoundSynth.swipeLayerSamples(s)
            assertTrue(layer.contentEquals(KeySoundSynth.swipeLayerSamples(s)))
            assertEquals(KeySoundSynth.swipeLoopSamples(s).size, layer.size)
            assertEquals(KeySoundSynth.SWIPE_LAYER_PEAK, layer.maxOf { abs(it) }.toDouble(), 1e-6)
            val lsum = layer.sumOf { abs(it).toDouble() }
            println("SWIPE-LAYER-GOLDEN ${s.id}=" + "%.4f".format(lsum))
            assertEquals(LAYER_GOLDEN.getValue(s), lsum, 0.01)
        }
        for (s in SwipeSoundStyle.entries) if (!s.hasLift) assertEquals(0, KeySoundSynth.swipeLiftSamples(s).size, s.id)
        for (s in SwipeSoundStyle.entries.filter { it.hasLift }) {
            val x = KeySoundSynth.swipeLiftSamples(s)
            assertTrue(x.contentEquals(KeySoundSynth.swipeLiftSamples(s)), "tất định ${s.id}")
            val maxLen = if (s == SwipeSoundStyle.WAVES || s == SwipeSoundStyle.CAT || s == SwipeSoundStyle.BIRDS) 0.6 else 0.35
            assertTrue(x.size in (0.12 * sr).toInt()..(maxLen * sr).toInt(), "ngắn: ${s.id} ${x.size}")
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
        // Sóng biển: đúng đoạn sóng vỡ + rút của theme Biển (dùng lại surfSamples), mở mềm.
        val settle = KeySoundSynth.swipeLiftSamples(SwipeSoundStyle.WAVES)
        assertEquals(KeySoundSynth.surfSamples().size - (KeySoundSynth.SWIPE_SETTLE_FROM * sr).roundToInt(), settle.size)
        assertTrue(abs(settle[0]) < 1e-3, "mở mềm")
        // Mèo kêu: "meo" có thân — 20 ms đầu nhỏ hơn hẳn giữa tiếng.
        val meow = KeySoundSynth.swipeLiftSamples(SwipeSoundStyle.CAT); val mh = meow.size / 2; val w20 = (0.02 * sr).toInt()
        assertTrue(KeySoundSynth.rms(meow.copyOfRange(0, w20)) < 0.5 * KeySoundSynth.rms(meow.copyOfRange(mh - w20, mh + w20)))
        // Chim hót: láy cao (trọng tâm phổ > 3 kHz).
        val trill = KeySoundSynth.swipeLiftSamples(SwipeSoundStyle.BIRDS)
        assertTrue(KeySoundSynth.spectralCentroid(trill.copyOfRange(0, 2048), sr) > 3000)
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
        for (s in SwipeSoundStyle.SYNTHESIZED.filter { it != SwipeSoundStyle.FLUTE }) {
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
            val cap = KeySoundSynth.swipePeak(s) +
                (if (s == SwipeSoundStyle.WAND || s == SwipeSoundStyle.BIRDS) KeySoundSynth.SWIPE_LAYER_PEAK else 0.0) +
                (shot.maxOfOrNull { abs(it) }?.toDouble() ?: 0.0) * SwipeSoundFx.PREVIEW_LIFT_GAIN
            assertTrue(p.maxOf { abs(it) } <= cap + 1e-6)
            val sum = p.sumOf { abs(it).toDouble() }
            println("SWIPE-PREVIEW-GOLDEN ${s.id}=" + "%.4f".format(sum))
            assertEquals(PREVIEW_GOLDEN.getValue(s), sum, 0.01)
        }
    }

    // --- Nốt nhạc theo phím, Sáo trúc, Chim hót ---

    @Test fun noteMapStepsAndMidi() {
        assertEquals(listOf(2, 4, 2, 4, 6, 5, 6, 7, 11, 8, 9, 10, 6, 5, 12, 13, 4, 7, 3, 8, 10, 3, 5, 1, 9, 0), SwipeNoteMap.LETTER_STEPS.toList())
        for (row in SwipeNoteMap.ROWS) {   // trong hàng: trái → phải tăng đúng một bậc
            val st = row.map { SwipeNoteMap.step(it - 'a') }
            assertEquals((st[0] until st[0] + st.size).toList(), st)
        }
        assertEquals((0 until SwipeNoteMap.STEPS).toSet(), SwipeNoteMap.LETTER_STEPS.toSet())
        assertEquals(listOf(55, 57, 60, 62, 64, 67, 69, 72, 74, 76, 79, 81, 84, 86),
            (0 until 14).map { SwipeNoteMap.midi(it, NoteMap.DANTRANH.scale) })
        assertEquals(listOf(55, 57, 59, 62, 64, 67, 69, 71, 74, 76, 79, 81, 83, 86),
            (0 until 14).map { SwipeNoteMap.midi(it, NoteMap.PIANO.scale) })
        assertEquals(SwipeSoundFx.NOTE_FLOOR, SwipeSoundFx.noteVelocity(0.0), 0.0, "vuốt chậm vẫn nghe")
        assertEquals(1.0, SwipeSoundFx.noteVelocity(SwipeSoundFx.SPEED_FULL), 1e-12)
        assertEquals(0.4 + 0.6 * 0.576361, SwipeSoundFx.noteVelocity(525.0), 1e-6)
    }

    @Test fun keyTrackerCoreAndDedup() {
        val c = SwipeKeyTracker.qwertyCenters(36f, 54f)
        val tr = SwipeKeyTracker.of(c, 36f)!!
        assertNull(SwipeKeyTracker.of(c, 0f))
        assertNull(SwipeKeyTracker.of(FloatArray(52) { Float.POSITIVE_INFINITY }, 36f))
        assertEquals(54.0, tr.rowHeight, 0.0); assertEquals(0.0, tr.minX, 0.0); assertEquals(360.0, tr.maxX, 0.0)
        fun at(ch: Char) = c[2 * (ch - 'a')].toDouble() to c[2 * (ch - 'a') + 1].toDouble()
        for (k in 0 until 26) assertEquals(k, tr.key(c[2 * k].toDouble(), c[2 * k + 1].toDouble()))
        val (gx, gy) = at('g')
        assertEquals(6, tr.key(gx + 0.34 * 36, gy), "trong lõi")
        assertEquals(-1, tr.key(gx + 0.36 * 36, gy), "ngoài lõi (ranh giới)")
        assertEquals(-1, tr.key(gx, gy + 0.36 * 54))
        assertEquals(-1, tr.key(gx, 4 * 54.0), "hàng cách")
        assertEquals(-1, tr.key(-100.0, gy))
        assertEquals(6, tr.feed(gx, gy))
        assertEquals(-1, tr.feed(gx + 5, gy), "cùng phím ⇒ một nốt")
        val hx = at('h').first
        var hits = 0
        for (i in 0 until 20) if (tr.feed((gx + hx) / 2 + (if (i % 2 == 0) -2 else 2), gy) >= 0) hits++
        assertEquals(0, hits, "rung ở ranh giới g|h không gảy")
        assertEquals(7, tr.feed(hx, gy))
        assertEquals(6, tr.feed(gx, gy), "quay lại g sau h ⇒ gảy lại")
        tr.reset()
        assertEquals(6, tr.feed(gx, gy), "cú vuốt mới")
        assertEquals(0.0, tr.unitX(-50.0), 0.0); assertEquals(0.5, tr.unitX(180.0), 0.0); assertEquals(1.0, tr.unitX(999.0), 0.0)
        // Nét mẫu "viet".
        val d = KeySoundSynth.swipeDemoPath()
        assertEquals(103, d.xs.size)
        val t2 = SwipeKeyTracker.of(d.centers, d.keyWidth)!!
        val word = StringBuilder()
        for (i in d.xs.indices) { val k = t2.feed(d.xs[i], d.ys[i]); if (k >= 0) word.append('a' + k) }
        assertEquals("vhiuytrert", word.toString())
        // Giai điệu của nét: bậc từng nốt (v h i u y t r e r t).
        assertEquals(listOf(3, 7, 11, 10, 9, 8, 7, 6, 7, 8), word.map { SwipeNoteMap.step(it - 'a') })
    }

    @Test fun flutePitchMapping() {
        val f = SwipeSoundFx
        assertEquals(64, f.nearestPentatonic(65.0)); assertEquals(67, f.nearestPentatonic(66.0))
        assertEquals(74, f.nearestPentatonic(74.4)); assertEquals(84, f.nearestPentatonic(83.0))
        assertEquals(64.3, f.fluteMidi(0.0), 1e-9)
        assertEquals(74.0, f.fluteMidi(0.5), 1e-9)
        assertEquals(83.7, f.fluteMidi(1.0), 1e-9)
        assertEquals(f.fluteMidi(0.0), f.fluteMidi(-3.0), 0.0); assertEquals(f.fluteMidi(1.0), f.fluteMidi(9.0), 0.0)
        assertEquals(1.0, f.fluteRate(0.5), 1e-12)
        assertEquals(0.755673, f.fluteRate(0.25), 1e-6)   // số tham chiếu chung iOS
        assertEquals(1.503509, f.fluteRate(0.9), 1e-6)
        var last = 0.0
        for (i in 0..200) {
            val r = f.fluteRate(i / 200.0)
            assertTrue(r >= last && r >= 0.5 && r <= 2.0, "rate $r")
            last = r
        }
        assertTrue(f.fluteRate(1.0) / f.fluteRate(0.0) > Math.pow(2.0, 1.5) * 0.95, "~1,5 quãng tám")
    }

    @Test fun birdChirpSchedule() {
        val l = KeySoundSynth.swipeLoopSeconds(SwipeSoundStyle.BIRDS); val m = KeySoundSynth.BIRD_MARGIN
        val sparse = KeySoundSynth.birdChirps(KeySoundSynth.BIRD_SEED, l, 0.18, 0.30)
        val dense = KeySoundSynth.birdChirps(KeySoundSynth.BIRD_LAYER_SEED, l, 0.04, 0.10)
        assertEquals(sparse, KeySoundSynth.birdChirps(KeySoundSynth.BIRD_SEED, l, 0.18, 0.30))
        assertEquals(6, sparse.size); assertEquals(9, dense.size)   // số tham chiếu chung iOS
        for (list in listOf(sparse, dense)) {
            var phrase = 0
            var prevEnd = -1.0
            for ((i, c) in list.withIndex()) {
                assertTrue(c.start >= m && c.start + c.duration <= l - m + 1e-9)
                assertTrue(c.duration in 0.035..0.07)
                assertTrue(maxOf(c.f0, c.f1) in 2600.0..(4200 * 1.15 * 1.5))
                assertTrue(c.amp in 0.6..1.0)
                assertTrue(c.start > prevEnd, "không chồng nhau")
                prevEnd = c.start + c.duration
                val same = i > 0 && list[i - 1].duration == c.duration && c.start - (list[i - 1].start + c.duration) < 0.056
                phrase = if (same) phrase + 1 else 1
                assertTrue(phrase <= 4)
                if (i + 1 == list.size || !(list[i + 1].duration == c.duration && list[i + 1].start - prevEnd < 0.056))
                    assertTrue(phrase >= 2, "câu ít nhất 2 tiếng")
            }
        }
    }

    @Test fun noteBankAndPitchedPreviews() {
        val sr = KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble()
        assertEquals(0, KeySoundSynth.swipeLoopSamples(SwipeSoundStyle.NOTES).size)
        assertEquals((0.6 * sr).toInt(), KeySoundSynth.swipeNoteLength)
        for (inst in KeyInstrument.entries) {
            val bank = KeySoundSynth.swipeNoteBank(inst)
            assertEquals(14, bank.size)
            var sum = 0.0
            for (x in bank) {
                assertEquals(KeySoundSynth.swipeNoteLength, x.size)
                assertEquals(KeySoundSynth.SWIPE_NOTE_PEAK, x.maxOf { abs(it) }.toDouble(), 1e-6)
                assertTrue(abs(x[x.size - 1]) < 1e-4, "đóng mềm")
                sum += x.sumOf { abs(it).toDouble() }
            }
            println("SWIPE-NOTES-GOLDEN ${inst.name}=" + "%.4f".format(sum))
            assertEquals(NOTE_BANK_GOLDEN.getValue(inst), sum, 0.02, "checksum chung iOS: $inst")
            val p = KeySoundSynth.swipePreviewSamples(SwipeSoundStyle.NOTES, inst)
            assertTrue(p.contentEquals(KeySoundSynth.swipeNotesPreview(inst)))
            assertEquals((0.825 * sr).roundToInt() + KeySoundSynth.swipeNoteLength, p.size)   // nốt cuối (t) ở 0,825 s
            assertTrue(p.maxOf { abs(it) } < 0.5f)
            val ps = p.sumOf { abs(it).toDouble() }
            println("SWIPE-NOTES-PREVIEW-GOLDEN ${inst.name}=" + "%.4f".format(ps))
            assertEquals(NOTES_PREVIEW_GOLDEN.getValue(inst), ps, 0.02)
        }
        val f = KeySoundSynth.swipePreviewSamples(SwipeSoundStyle.FLUTE)
        assertTrue(f.contentEquals(KeySoundSynth.swipeFlutePreview()))
        val lift = (KeySoundSynth.SWIPE_PREVIEW_LIFT * sr).roundToInt()
        assertEquals(maxOf(sr.toInt(), lift + (SwipeSoundFx.FLUTE_RELEASE * sr).roundToInt() + 2), f.size)
        assertTrue(abs(f[0]) < 1e-3, "mở từ 0")
        assertEquals(0.0, abs(f[f.size - 1]).toDouble(), 0.0, "tắt dần hết sau FLUTE_RELEASE")
        assertTrue(f.maxOf { abs(it) } <= KeySoundSynth.swipePeak(SwipeSoundStyle.FLUTE) + 1e-6)
        val fs = f.sumOf { abs(it).toDouble() }
        println("SWIPE-FLUTE-PREVIEW-GOLDEN " + "%.4f".format(fs))
        assertEquals(FLUTE_PREVIEW_GOLDEN, fs, 0.01)
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
            SwipeSoundStyle.FLUTE to 1946.4318,
            SwipeSoundStyle.WAVES to 1681.5173,
            SwipeSoundStyle.CAT to 475.8167,
            SwipeSoundStyle.BIRDS to 424.2226,
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
            SwipeSoundStyle.WAVES to 1376.3931,
            SwipeSoundStyle.CAT to 1441.8459,
            SwipeSoundStyle.BIRDS to 561.5857,
        )
        val LIFT_GOLDEN = mapOf(
            SwipeSoundStyle.WHIP to 94.7710,
            SwipeSoundStyle.LIGHTNING to 239.0145,
            SwipeSoundStyle.PLASMA to 434.8444,
            SwipeSoundStyle.WAND to 581.7851,
            SwipeSoundStyle.WAVES to 715.3403,
            SwipeSoundStyle.CAT to 1502.8527,
            SwipeSoundStyle.BIRDS to 363.6219,
        )
        val LAYER_GOLDEN = mapOf(SwipeSoundStyle.WAND to 906.3455, SwipeSoundStyle.BIRDS to 344.4035)
        /** Tổng |mẫu| của cả 14 nốt + bản nghe thử "viet" theo nhạc cụ (Nốt nhạc theo phím). */
        val NOTE_BANK_GOLDEN = mapOf(KeyInstrument.DANTRANH to 5414.3445, KeyInstrument.PIANO to 6428.3102, KeyInstrument.GUITAR to 5343.4127)
        val NOTES_PREVIEW_GOLDEN = mapOf(KeyInstrument.DANTRANH to 1564.3575, KeyInstrument.PIANO to 1777.4152,
            KeyInstrument.GUITAR to 1390.8450)
        const val FLUTE_PREVIEW_GOLDEN = 924.0326
    }
}
