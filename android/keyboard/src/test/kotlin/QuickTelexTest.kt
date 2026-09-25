import com.viettelex.keyboard.*
import kotlin.test.Test
import kotlin.test.assertEquals

/** Regression: bật Quick Telex trong app khi bàn phím đang mở (ô Thử gõ) → "ccaof" vẫn ra "ccào". */
class QuickTelexTest {
    @Test fun quickTelexCcBecomesCh() {
        val s = KeyboardSettings(); s.quickTelex = true
        assertEquals("chào", EngineBridge(s).composeTrial("ccaof"))
    }

    @Test fun applySettingsTakesEffectOnLiveBridge() {
        val b = EngineBridge(KeyboardSettings())
        val on = KeyboardSettings(); on.quickTelex = true
        b.applySettings(on)
        assertEquals("chào", b.composeTrial("ccaof"))
    }

    @Test fun engineKeysCoverQuickTelex() {
        assert(Keys.QUICK_TELEX in Keys.ENGINE_KEYS)
    }
}
