package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyCommitQueueTests {
    private class KeyObj
    private var out = ""
    private val q = KeyCommitQueue()
    private val space = KeyObj(); private val comma = KeyObj(); private val ret = KeyObj()

    private fun letterDown(c: String) { q.flush(); out += c }

    @Test fun testRolloverKeepsPressOrder() {
        out = "anh"
        q.arm(space) { out += " " }
        letterDown("e")
        q.release(space)
        letterDown("m")
        assertEquals("anh em", out)
    }

    @Test fun testCancelledTouchStillCommits() {
        q.arm(ret) { out += "\n" }
        q.release(ret)
        assertEquals("\n", out)
    }

    @Test fun testTrackpadDisarmsSpace() {
        out = "ab"
        q.arm(space) { out += " " }
        q.disarm(space)
        q.release(space)
        assertEquals("ab", out)
    }

    @Test fun testSeveralPendingFireInPressOrderAndNotTwice() {
        q.arm(comma) { out += "," }
        q.arm(space) { out += " " }
        letterDown("x")
        q.release(comma); q.release(space)
        assertEquals(", x", out)
        assertTrue(q.isEmpty)
    }

    @Test fun testSameKeyPressedTwiceWhileHeldCommitsBoth() {
        q.arm(space) { out += "1" }
        q.flush(except = space)
        q.arm(space) { out += "2" }
        q.release(space)
        assertEquals("12", out)
    }

    @Test fun testFlushExceptTheKeyBeingPressed() {
        q.arm(space) { out += " " }
        q.flush(except = space)
        assertEquals("", out)
        q.release(space)
        assertEquals(" ", out)
    }
}
