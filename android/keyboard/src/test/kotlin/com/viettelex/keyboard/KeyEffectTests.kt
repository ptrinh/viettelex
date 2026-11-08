package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.lang.management.ManagementFactory
import kotlin.math.hypot

/**
 * "Hiệu ứng khi bấm phím" (Plus, 19/10/2026) — song sinh iOS KeyEffectTests: model cài đặt, cổng Plus,
 * điều kiện tự tắt, trần hạt, mô phỏng hạt không cấp phát, và số đo chi phí mỗi phím / mỗi khung hình.
 * Ràng buộc Phil: chèn chữ TRƯỚC rồi mới vẽ; tắt = 0 chi phí; ≤ ~20 hạt; > ~0,3 ms/phím là không phát hành.
 */
class KeyEffectTests {
    private var savedPaywall = PlusGate.paywallEnabled

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled }
    @After fun tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.install({ null }, debugBuild = false)
    }

    @Test fun idsMatchIosAndDefaultIsNone() {
        assertEquals(listOf("none", "heart", "bubble", "ripple", "petal", "firework", "flash", "matrix", "lightning", "emojiword", "blossom", "combo", "ink", "wave", "snow", "meteor", "lantern", "smoke", "string", "plasma", "shake", "laser", "glitch", "tone", "keyword", "letters", "sand", "sea", "tokens"), KeyEffect.entries.map { it.id })
        assertEquals("keyEffect", Keys.KEY_EFFECT)
        assertEquals(KeyEffect.NONE, KeyEffect.DEFAULT)
        assertEquals(KeyEffect.NONE, KeyEffect.of(null))
        assertEquals(KeyEffect.NONE, KeyEffect.of("sparkle"))
        assertEquals(KeyEffect.NONE, KeyEffect.of(3))
        assertEquals(KeyEffect.HEART, KeyEffect.of("heart"))
    }

    @Test fun settingsLoad() {
        assertEquals(KeyEffect.NONE, KeyboardSettings().keyEffect)
        assertEquals(KeyEffect.NONE, KeyboardSettings.load { null }.keyEffect)
        assertEquals(KeyEffect.PETAL, KeyboardSettings.load { if (it == Keys.KEY_EFFECT) "petal" else null }.keyEffect)
        assertEquals(KeyEffect.NONE, KeyboardSettings.load { if (it == Keys.KEY_EFFECT) "lol" else null }.keyEffect)
    }

    @Test fun backupSpecWhitelistsIds() {
        val spec = BackupSettings.all.first { it.key == Keys.KEY_EFFECT }
        assertEquals(SettingKind.Choice("none", setOf("none", "heart", "bubble", "ripple", "petal", "firework", "flash", "matrix", "lightning", "emojiword", "blossom", "combo", "ink", "wave", "snow", "meteor", "lantern", "smoke", "string", "plasma", "shake", "laser", "glitch", "tone", "keyword", "letters", "sand", "sea", "tokens")), spec.kind)
    }

    @Test fun titlesBilingual() {
        val en = L10nTable.EN
        for (e in KeyEffect.entries) assertTrue(e.viTitle, en.containsKey(e.viTitle))
        assertTrue(en.containsKey("Hiệu ứng khi bấm phím"))
    }

    @Test fun onlyNoneIsFree() {
        assertFalse(KeyEffect.NONE.isPlus)
        for (e in KeyEffect.entries) if (e != KeyEffect.NONE) assertTrue(e.id, e.isPlus)
    }

    @Test fun plusGate() {
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)
        assertFalse(KeyEffectGate.allows)
        assertTrue(KeyEffectGate.allows(KeyEffect.NONE))
        assertFalse(KeyEffectGate.allows(KeyEffect.HEART))
        PlusGate.install({ if (it == Keys.PLUS_UNLOCKED) true else null }, debugBuild = false)
        assertTrue(KeyEffectGate.allows(KeyEffect.HEART))
        PlusGate.paywallEnabled = false
        PlusGate.install({ null }, debugBuild = false)
        assertTrue("chưa bật thanh toán ⇒ mở hết", KeyEffectGate.allows(KeyEffect.FIREWORK))
    }

    @Test fun autoDisableConditions() {
        assertEquals(KeyEffect.HEART, KeyEffectPolicy.active(KeyEffect.HEART, plus = true, powerSave = false))
        assertEquals(KeyEffect.NONE, KeyEffectPolicy.active(KeyEffect.HEART, plus = false, powerSave = false))
        assertEquals("Trình tiết kiệm pin ⇒ tắt", KeyEffect.NONE,
            KeyEffectPolicy.active(KeyEffect.HEART, plus = true, powerSave = true))
        // Tắt hiệu ứng động của hệ thống không còn tắt hiệu ứng phím (Phil 19/10/2026).
        assertEquals(KeyEffect.NONE, KeyEffectPolicy.active(KeyEffect.NONE, plus = true, powerSave = false))
    }

    @Test fun poolCapsAndRecyclesOldest() {
        assertTrue(KeyEffectPool.CAP <= 20)
        val p = KeyEffectPool()
        val seen = HashSet<Int>()
        repeat(200) { val i = p.next(); assertTrue(i in 0 until KeyEffectPool.CAP); seen += i }
        assertEquals(KeyEffectPool.CAP, seen.size)
        val q = KeyEffectPool()
        val first = q.next()
        repeat(KeyEffectPool.CAP - 1) { q.next() }
        assertEquals("đầy ⇒ thay ô cũ nhất", first, q.next())
        assertEquals(1, KeyEffectPool(0).capacity)
    }

    /** Cùng số với iOS KeyEffectTests.testTrajectoriesDistinctAndBounded. */
    @Test fun trajectoriesDistinctAndBounded() {
        for (e in KeyEffect.PARTICLES) {
            assertTrue(e.particlesPerTap <= KeyEffectPool.CAP / 2)
            assertEquals(e.particlesPerTap * 2, e.variantCount)
            for (seed in 0 until 5) {
                val vs = (0 until e.particlesPerTap).map { e.variant(it, seed) }
                assertEquals("${e.id} seed $seed", vs.size, vs.toSet().size)
                vs.forEach { assertTrue(it in 0 until e.variantCount) }
            }
            for (v in 0 until e.variantCount) {
                val t = e.trajectory(v)
                assertTrue("${e.id} #$v", hypot(t.dx, t.dy) <= 72)
                assertTrue(t.duration > 0.2 && t.duration <= 1.2)
                assertTrue(t.scaleTo > 0)
            }
        }
        assertEquals(0, KeyEffect.NONE.particlesPerTap)
        assertTrue("tim bay lên", KeyEffect.HEART.trajectory(0).dy < 0)
        assertTrue(KeyEffect.HEART.trajectory(0).dx < 0)
        assertTrue(KeyEffect.HEART.trajectory(5).dx > 0)
        assertEquals(30.0, KeyEffect.FIREWORK.trajectory(0).dx, 1e-9)
        assertEquals(36.0, KeyEffect.FIREWORK.trajectory(3).dy, 1e-9)
    }

    @Test fun particlesFlyThenDie() {
        val sim = KeyEffectParticles()
        sim.configure(KeyEffect.HEART)
        sim.spawn(100f, 200f, 1000L)
        assertEquals(3, sim.aliveCount())
        var any = false
        for (s in 0 until sim.capacity) if (sim.sample(s, 1000L + 300, 2f)) {
            any = true
            assertTrue("đang bay lên", sim.sy < 200f)
            assertEquals(1f, sim.sAlpha, 1e-6f)
        }
        assertTrue(any)
        for (s in 0 until sim.capacity) sim.sample(s, 1000L + 2000, 2f)
        assertEquals("bay xong ⇒ tắt (không vẽ, không hẹn khung hình)", 0, sim.aliveCount())
        sim.configure(KeyEffect.NONE)
        sim.spawn(1f, 1f, 0L)
        assertEquals(0, sim.aliveCount())
    }

    /** 200 phím dồn dập: hạt sống không vượt trần, không cấp phát (spawn + sample mỗi khung hình). */
    @Test fun burstOf200KeysCappedAndAllocationFree() {
        val bean = ManagementFactory.getThreadMXBean() as com.sun.management.ThreadMXBean
        val tid = Thread.currentThread().id
        for (e in KeyEffect.PARTICLES) {
            val sim = KeyEffectParticles()
            sim.configure(e)
            // làm nóng (JIT) rồi đo cấp phát
            repeat(50) { sim.spawn(it.toFloat(), 10f, it * 16L); for (s in 0 until sim.capacity) sim.sample(s, it * 16L, 3f) }
            val a0 = bean.getThreadAllocatedBytes(tid)
            var now = 10_000L
            repeat(200) { i ->
                sim.spawn((i % 10) * 39f, 80f, now)
                // 2 khung hình 60 Hz mỗi phím (gõ ~30 phím/giây)
                repeat(2) { now += 16; for (s in 0 until sim.capacity) sim.sample(s, now, 3f) }
                assertTrue(sim.aliveCount() <= KeyEffectPool.CAP)
            }
            val bytes = bean.getThreadAllocatedBytes(tid) - a0
            assertTrue("${e.id}: cấp phát $bytes byte cho 200 phím", bytes < 1024)
        }
    }

    /**
     * Số đo JVM: chi phí main thread phần MÔ HÌNH mỗi phím (spawn) và mỗi khung hình (sample ≤ 20 hạt).
     * Phần canvas (≤ 20 drawPath vào display list) chỉ đo được trên máy — xem báo cáo.
     */
    @Test fun perKeyAndPerFrameCost() {
        val sim = KeyEffectParticles()
        for (e in KeyEffect.PARTICLES) {
            sim.configure(e)
            repeat(20_000) { sim.spawn(1f, 2f, it.toLong()); for (s in 0 until sim.capacity) sim.sample(s, it.toLong(), 3f) }
            val n = 20_000
            var t0 = System.nanoTime()
            for (i in 0 until n) sim.spawn(1f, 2f, i.toLong())
            val spawnNs = (System.nanoTime() - t0).toDouble() / n
            // khung hình với đủ 20 hạt đang bay
            for (i in 0 until 10) sim.spawn(i.toFloat(), 2f, 0L)
            t0 = System.nanoTime()
            var alive = 0
            for (i in 0 until n) for (s in 0 until sim.capacity) if (sim.sample(s, (i % 100).toLong(), 3f)) alive++
            val frameNs = (System.nanoTime() - t0).toDouble() / n
            println("KEYFX-ANDROID ${e.id} spawn/key=%.3f µs sample/frame(≤20 hạt)=%.3f µs".format(spawnNs / 1000, frameNs / 1000))
            assertTrue("${e.id} spawn ${spawnNs}ns", spawnNs < 50_000)
            assertTrue("${e.id} frame ${frameNs}ns", frameNs < 100_000)
            assertTrue(alive > 0)
        }
    }
}
