package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.Executor

/**
 * Bàn phím hiện nhanh (PERF-IME-SHOW): người dùng mới (model trống) — seed.tsv KHÔNG được parse trên
 * main trong onStartInputView (trước đây: `seedIfEmpty` parse + áp đồng bộ, chặn khung đầu).
 * Seed parse trên io, áp trên main ở lượt sau; từ gõ chen giữa giữ đếm lớn hơn.
 */
class UserLMSeedAsyncTests {
    private class Queue : Executor, MainThread {
        val tasks = ArrayList<Runnable>()
        override fun execute(r: Runnable) { tasks += r }
        override fun post(r: Runnable) { tasks += r }
        override fun postDelayed(delayMs: Long, r: Runnable): Cancellable = Cancellable { }
        fun drain() { while (tasks.isNotEmpty()) tasks.removeAt(0).run() }
    }

    private fun model(io: Queue, main: Queue): UserLangModel {
        val f = File.createTempFile("userlm", ".bin").apply { delete(); deleteOnExit() }
        val m = UserLangModel(f, main, io)
        io.drain(); main.drain()            // nạp file (vắng) xong ⇒ isLoaded, bảng trống
        return m
    }

    @Test fun seedIsParsedOffTheCallerThreadAndAppliedLater() {
        val io = Queue(); val main = Queue()
        val m = model(io, main)
        var parsedOn: Thread? = null
        var calls = 0
        m.seedIfEmpty {
            calls++; parsedOn = Thread.currentThread()
            SeedData.Seed(mapOf("không" to 50, "được" to 40), listOf(Triple("không", "được", 7)))
        }
        assertEquals("seed chưa được parse ngay trong lời gọi (đường hiện bàn phím)", 0, calls)
        assertEquals(0, m.count("không"))
        io.drain()                           // parse trên io
        assertEquals(1, calls)
        assertEquals(0, m.count("không"))    // chưa áp: chờ main
        main.drain()
        assertEquals(50, m.count("không"))
        assertTrue(parsedOn != null)
        m.seedIfEmpty { calls++; SeedData.Seed(emptyMap(), emptyList()) }
        io.drain(); main.drain()
        assertEquals("đã có dữ liệu ⇒ không seed lại", 1, calls)
    }

    @Test fun wordsTypedWhileSeedingKeepTheirCounts() {
        val io = Queue(); val main = Queue()
        val m = model(io, main)
        m.seedIfEmpty { SeedData.Seed(mapOf("chào" to 3, "bạn" to 20), emptyList()) }
        repeat(5) { m.record("chào", null) }  // gõ trước khi seed áp
        val typed = m.count("chào")
        io.drain(); main.drain()
        assertTrue("seed không hạ đếm từ vừa gõ", m.count("chào") >= typed)
        assertEquals(20, m.count("bạn"))
    }

    @Test fun inMemoryModelStillSeedsSynchronously() {
        val m = UserLangModel()
        m.seedIfEmpty { SeedData.Seed(mapOf("ok" to 9), emptyList()) }
        assertEquals(9, m.count("ok"))
    }

    @Test fun eraseWhileSeedingDropsStaleSeedAndReseeds() {
        val io = Queue(); val main = Queue()
        val m = model(io, main)
        m.seedIfEmpty { SeedData.Seed(mapOf("cũ" to 5), emptyList()) }
        io.drain()                            // seed cũ parse xong, chưa áp
        m.reloadAfterExternalErase()          // xoá dữ liệu học ⇒ nạp lại, seed lại từ nguồn
        io.drain(); main.drain(); io.drain(); main.drain()
        assertFalse(main.tasks.isNotEmpty())
        assertEquals("seed lại sau khi xoá", 5, m.count("cũ"))
    }
}
