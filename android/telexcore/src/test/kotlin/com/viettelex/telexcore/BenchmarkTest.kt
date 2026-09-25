package com.viettelex.telexcore

import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.management.ManagementFactory

/** Micro-benchmark (prints ns/keystroke) — mirrors TelexCore BenchmarkTests' corpus. */
class BenchmarkTest {
    private val vietnamese = ("Phil Trinhj (Trinhj Minh Phucs) laf mootj nhaf sangs laapj ddaa linhx vuwcj sinh ra taij " +
        "Haf Nooij, hieenj soongs taij Singapore. Anh du hocj ngaanhf Khoa hocj Mays tinhs taij " +
        "DDaij hocj Drexel (Myx), sau ddos lamf kyx suw phaanf meemf taij SIG, Zalora vaf Grab. " +
        "Hieenj anh ddoongf ddieeuf hanhf ba coong ty goomf SenPrints (SaaS thuwowng maij ddieenj " +
        "tuwr/print-on-demand), Printik (in aans taij Myx) vaf AloRide (cho thuee xe mays), " +
        "vowis beef dayf kinh nghieemj veef kyx thuaatj vaf xaay duwngj doanh nghieepj.")
        .split(' ', '(', ')', ',', '.', '/', '-').filter { it.isNotEmpty() }

    private fun feedAll(e: TelexEngine, words: List<String>): Int {
        var keys = 0
        for (w in words) {
            for (c in w) { e.feed(c); keys++ }
            e.peekCommitText(true)          // iOS suggestion bar peeks every word
            e.commitBoundary(true); keys++
        }
        return keys
    }

    private fun bench(name: String, cfg: TelexEngine.() -> Unit, words: List<String>): Double {
        val e = TelexEngine().apply(cfg)
        repeat(3000) { feedAll(e, words) }            // JIT warm-up
        val iters = 5000
        val t0 = System.nanoTime()
        var keys = 0
        repeat(iters) { keys += feedAll(e, words) }
        val ns = (System.nanoTime() - t0).toDouble() / keys
        val mx = ManagementFactory.getThreadMXBean() as? com.sun.management.ThreadMXBean
        var bytesPerKey = -1.0
        if (mx != null && mx.isThreadAllocatedMemorySupported) {
            @Suppress("DEPRECATION") val tid = Thread.currentThread().id
            val b0 = mx.getThreadAllocatedBytes(tid)
            var k = 0
            repeat(200) { k += feedAll(e, words) }
            bytesPerKey = (mx.getThreadAllocatedBytes(tid) - b0).toDouble() / k
        }
        println("BENCH %-28s %7.1f ns/keystroke  %6.1f B/keystroke".format(name, ns, bytesPerKey))
        return ns
    }

    /** Passthrough keystrokes (no transform) must not allocate at all. */
    @Test fun passthroughKeystrokesDoNotAllocate() {
        val mx = ManagementFactory.getThreadMXBean() as? com.sun.management.ThreadMXBean ?: return
        if (!mx.isThreadAllocatedMemorySupported) return
        val e = TelexEngine().apply { liveSpellCheck = true }
        fun type() { for (c in "bcnghbcnghbcngh") e.feed(c); e.reset() }
        repeat(20_000) { type() }
        @Suppress("DEPRECATION") val tid = Thread.currentThread().id
        val b0 = mx.getThreadAllocatedBytes(tid)
        repeat(10_000) { type() }
        val perKey = (mx.getThreadAllocatedBytes(tid) - b0).toDouble() / (10_000 * 15)
        println("ALLOC passthrough %.3f B/keystroke".format(perKey))
        assertTrue("passthrough allocates $perKey B/key", perKey < 1.0)
    }

    @Test fun perKeystrokeLatency() {
        val ios = bench("iOS defaults (Telex)", { freeMarking = true; simpleTelex = true; liveSpellCheck = true; contextualEnglish = true; teencode = false }, vietnamese)
        bench("engine defaults (Telex)", {}, vietnamese)
        bench("English (folded)", { liveSpellCheck = true }, vietnamese.map { w -> w.filter { it !in "sfrxj" } })
        assertTrue("avg keystroke $ios ns exceeds 50µs budget", ios < 50_000)
    }
}
