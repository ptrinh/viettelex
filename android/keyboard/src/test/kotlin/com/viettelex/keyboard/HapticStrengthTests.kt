package com.viettelex.keyboard

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Độ mạnh rung 10…100 % → biên độ / độ dài nhịp (giống iOS HapticTests). */
class HapticStrengthTests {
    @Test fun clampRange() {
        assertEquals(10, HapticStrength.clamp(0)); assertEquals(10, HapticStrength.clamp(-5))
        assertEquals(100, HapticStrength.clamp(250)); assertEquals(45, HapticStrength.clamp(45))
    }

    @Test fun amplitudeMapping() {
        assertEquals(26, HapticStrength.amplitude(10))
        assertEquals(115, HapticStrength.amplitude(45))
        assertEquals(255, HapticStrength.amplitude(100))
        assertEquals(255, HapticStrength.amplitude(999))
        assertEquals(26, HapticStrength.amplitude(1))
        assertEquals(7L, HapticStrength.amplitudeDurationMs(10))
        assertEquals(10L, HapticStrength.amplitudeDurationMs(45))
        assertEquals(16L, HapticStrength.amplitudeDurationMs(100))
    }

    @Test fun mappingsMonotonic() {
        assertEquals(5L, HapticStrength.durationOnlyMs(10))
        assertEquals(30L, HapticStrength.durationOnlyMs(100))
        assertEquals(5L, HapticStrength.durationOnlyMs(0))
        val durs = (10..100 step 5).map { HapticStrength.durationOnlyMs(it) }
        assertTrue(durs.zipWithNext().all { (a, b) -> a <= b })
        val amps = (10..100 step 5).map { HapticStrength.amplitude(it) }
        assertTrue(amps.zipWithNext().all { (a, b) -> a < b })
    }

    /** Pin: ưu tiên primitive TICK (45 % = tick nhẹ), rồi one-shot ngắn có biên độ, predefined, one-shot theo độ dài. */
    @Test fun planPrefersCheapestSystemEffect() {
        val p45 = HapticStrength.plan(45, 33, primitivesSupported = true, amplitudeControl = true)
        assertTrue(p45 is HapticStrength.Plan.Primitive && p45.tick)
        assertEquals(0.708f, (p45 as HapticStrength.Plan.Primitive).scale, 0.01f)
        val p10 = HapticStrength.plan(10, 33, true, true) as HapticStrength.Plan.Primitive
        assertTrue(p10.tick); assertEquals(0.3f, p10.scale, 1e-4f)
        val p100 = HapticStrength.plan(100, 33, true, true) as HapticStrength.Plan.Primitive
        assertTrue(!p100.tick); assertEquals(1f, p100.scale, 1e-4f)
        // scale tăng đều trong mỗi dải
        val ticks = (10..70 step 5).map { HapticStrength.primitiveScale(it).second }
        assertTrue(ticks.zipWithNext().all { (a, b) -> a < b })
        // primitive có mà API < 30 ⇒ không dùng
        assertEquals(HapticStrength.Plan.OneShot(10, 115), HapticStrength.plan(45, 29, true, true))
        assertEquals(HapticStrength.Plan.OneShot(10, 115), HapticStrength.plan(45, 33, false, true))
        assertEquals(HapticStrength.Plan.OneShot(15, -1), HapticStrength.plan(45, 28, false, false))
    }

    /** Hồi quy 29/10/2026: máy không điều chỉnh biên độ (API 29+) từng dùng predefined 3 nấc ⇒
     *  10…55 % CÙNG một EFFECT_TICK, kéo thanh trượt không đổi gì. Nay theo độ dài, tăng dần. */
    @Test fun noAmplitudeControlStillScalesWithSlider() {
        for (sdk in listOf(28, 29, 33)) {
            val plans = (10..100 step 5).map { HapticStrength.plan(it, sdk, false, false) }
            assertTrue(plans.all { it is HapticStrength.Plan.OneShot && it.amplitude == -1 })
            val ms = plans.map { (it as HapticStrength.Plan.OneShot).ms }
            assertTrue(ms.zipWithNext().all { (a, b) -> a <= b })
            assertTrue(ms.first() < ms.last())
            assertTrue(HapticStrength.plan(10, sdk, false, false) != HapticStrength.plan(45, sdk, false, false))
        }
    }

    @Test fun settingsLoadDefaultAndClamp() {
        assertEquals(30, HapticStrength.DEFAULT)
        assertEquals(30, KeyboardSettings.load { null }.hapticStrength)
        assertEquals(45, KeyboardSettings.load { if (it == Keys.HAPTIC_STRENGTH) 45 else null }.hapticStrength)
        assertEquals(70, KeyboardSettings.load { if (it == Keys.HAPTIC_STRENGTH) 70 else null }.hapticStrength)
        assertEquals(100, KeyboardSettings.load { if (it == Keys.HAPTIC_STRENGTH) 300 else null }.hapticStrength)
        assertEquals(10, KeyboardSettings.load { if (it == Keys.HAPTIC_STRENGTH) 3 else null }.hapticStrength)
        assertEquals(30, KeyboardSettings.load { if (it == Keys.HAPTIC_STRENGTH) "x" else null }.hapticStrength)
    }

    @Test fun backupSpecAndSnapshot() {
        val kind = BackupSettings.byKey[Keys.HAPTIC_STRENGTH]!!.kind as SettingKind.IntRange
        assertEquals(30, kind.default); assertEquals(10..100, kind.range)
        val prefs = mapOf<String, Any?>(Keys.HAPTIC_STRENGTH to 250)
        assertEquals(100, BackupPrefs.snapshot({ prefs[it] }, emptyList(), null).settings!![Keys.HAPTIC_STRENGTH])
        assertEquals(30, BackupPrefs.snapshot({ null }, emptyList(), null).settings!![Keys.HAPTIC_STRENGTH])
    }
}
