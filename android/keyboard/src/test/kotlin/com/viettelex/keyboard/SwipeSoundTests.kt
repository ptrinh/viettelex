package com.viettelex.keyboard

import kotlin.math.abs
import kotlin.math.roundToInt
import org.junit.After
import org.junit.Before
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
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
        assertEquals(listOf("none", "pencil", "brush", "chalk", "marker"), SwipeSoundStyle.entries.map { it.id })
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.DEFAULT)
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.of(null))
        assertEquals(SwipeSoundStyle.NONE, SwipeSoundStyle.of("loud"))
        assertEquals(SwipeSoundStyle.CHALK, SwipeSoundStyle.of("chalk"))
        assertEquals("swipeSound", Keys.SWIPE_SOUND)
        assertEquals(listOf(false, false, true, true, true), SwipeSoundStyle.entries.map { it.isPlus })
        assertEquals(listOf("Tắt", "Bút chì", "Chổi lông", "Phấn bảng", "Bút dạ"), SwipeSoundStyle.entries.map { it.viTitle })
        for (s in SwipeSoundStyle.entries) assertTrue(L10nTable.EN.containsKey(s.viTitle), s.viTitle)
    }

    @Test fun settingsLoadAndBackupSpec() {
        assertEquals(SwipeSoundStyle.NONE, KeyboardSettings().swipeSound)
        assertEquals(SwipeSoundStyle.NONE, KeyboardSettings.load { null }.swipeSound)
        assertEquals(SwipeSoundStyle.BRUSH, KeyboardSettings.load { if (it == Keys.SWIPE_SOUND) "brush" else null }.swipeSound)
        val spec = BackupSettings.all.first { it.key == Keys.SWIPE_SOUND }
        assertEquals(SettingKind.Choice("none", setOf("none", "pencil", "brush", "chalk", "marker")), spec.kind)
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
        // Cổng = cổng Hiệu ứng nét vuốt.
        plus(false)
        assertFalse(SwipeSoundGate.allows); assertTrue(SwipeSoundGate.allows(SwipeSoundStyle.PENCIL))
        assertFalse(SwipeSoundGate.allows(SwipeSoundStyle.CHALK))
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
        val sums = ArrayList<String>()
        for (s in SwipeSoundStyle.entries.drop(1)) {
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
        for (s in SwipeSoundStyle.entries.drop(1)) {
            val sum = KeySoundSynth.swipeLoopSamples(s).sumOf { abs(it).toDouble() }
            assertEquals(GOLDEN.getValue(s), sum, 0.01, "checksum chung iOS: ${s.id}")
        }
        // Âm sắc: Bút chì sáng nhất, Chổi lông trầm nhất (trọng tâm phổ, khung 2048 mẫu).
        fun centroid(s: SwipeSoundStyle) = KeySoundSynth.spectralCentroid(KeySoundSynth.swipeLoopSamples(s).copyOfRange(4000, 6048), sr)
        val c = SwipeSoundStyle.entries.drop(1).associateWith { centroid(it) }
        println("SWIPE-SOUND-CENTROID $c")
        assertTrue(c.getValue(SwipeSoundStyle.BRUSH) < 2600, "chổi lông trầm-trung")
        assertTrue(c.getValue(SwipeSoundStyle.PENCIL) > c.getValue(SwipeSoundStyle.MARKER))
        assertTrue(c.getValue(SwipeSoundStyle.PENCIL) > c.getValue(SwipeSoundStyle.BRUSH))
        assertTrue(c.getValue(SwipeSoundStyle.CHALK) > c.getValue(SwipeSoundStyle.BRUSH))
    }

    @Test fun previewFollowsDemoSwipeAndFadesOut() {
        val sr = KeySoundSynth.SWIPE_SAMPLE_RATE.toDouble()
        assertEquals(0.0, KeySoundSynth.swipeDemoSpeed(0.0), 0.0)
        assertEquals(0.0, KeySoundSynth.swipeDemoSpeed(KeySoundSynth.SWIPE_PREVIEW_LIFT), 0.0)
        assertEquals(675.0, KeySoundSynth.swipeDemoSpeed(KeySoundSynth.SWIPE_PREVIEW_LIFT / 2), 1e-9)   // giữa nét: chậm lại ở phím
        for (s in SwipeSoundStyle.entries.drop(1)) {
            val p = KeySoundSynth.swipePreviewSamples(s)
            assertEquals((KeySoundSynth.SWIPE_PREVIEW * sr).toInt(), p.size)
            assertTrue(p.contentEquals(KeySoundSynth.swipePreviewSamples(s)))
            val lift = (KeySoundSynth.SWIPE_PREVIEW_LIFT * sr).toInt()
            val fadeEnd = lift + (SwipeSoundFx.FADE_OUT * sr).toInt() + 2
            for (i in fadeEnd until p.size) assertEquals(0.0, abs(p[i]).toDouble(), 0.0, "im sau khi tắt dần (${s.id})")
            assertTrue(abs(p[0]) < 1e-3, "mở từ 0")
            assertTrue(p.maxOf { abs(it) } <= KeySoundSynth.swipePeak(s) + 1e-6)
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
        )
        val PREVIEW_GOLDEN = mapOf(
            SwipeSoundStyle.PENCIL to 593.6883,
            SwipeSoundStyle.BRUSH to 842.1863,
            SwipeSoundStyle.CHALK to 364.0651,
            SwipeSoundStyle.MARKER to 786.1841,
        )
    }
}
