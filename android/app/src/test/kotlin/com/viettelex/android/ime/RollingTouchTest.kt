package com.viettelex.android.ime

import com.viettelex.keyboard.KeyCommitQueue
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Hợp đồng thứ tự chốt khi gõ chồng ngón (spec §5, §13 "Gõ nhanh") — mô phỏng đúng
 * trình tự KeyboardView.down/up gọi: route bằng KeyLayout.hit, `commits.flush(k)` TRƯỚC
 * mọi hành động, phím chữ chèn lúc DOWN, space/dấu arm lúc DOWN – chốt lúc UP/CANCEL.
 */
class RollingTouchTest {
    private val keys = KeyLayout.build(LayoutConfig(Plane.LETTERS, 390f, 218f, 1f))
    private val out = StringBuilder()
    private val q = KeyCommitQueue()
    private val held = HashMap<Int, LaidKey>()

    private fun key(label: String) = keys.first { it.label == label && it.kind == KeyKind.LETTER }
    private val space get() = keys.first { it.kind == KeyKind.SPACE }
    private val comma get() = keys.first { it.kind == KeyKind.PUNCT }

    private fun down(pid: Int, k: LaidKey) {
        val hit = KeyLayout.hit(keys, Plane.LETTERS, k.centerX, k.centerY, 4f, 1f)!!
        q.flush(hit)
        held[pid] = hit
        when (hit.kind) {
            KeyKind.LETTER -> out.append(hit.label)
            KeyKind.SPACE -> q.arm(hit) { out.append(' ') }
            KeyKind.PUNCT -> q.arm(hit) { out.append(hit.insert) }
        }
    }

    private fun up(pid: Int) {
        val k = held.remove(pid)!!
        if (k.kind != KeyKind.LETTER) q.release(k)
    }

    @Test fun rollingEightFingersKeepsEveryKeyInOrder() {
        // mỗi ngón chạm xuống TRƯỚC khi ngón trước nhấc
        val word = "abcdefgh"
        down(0, key("a"))
        for (i in 1 until word.length) {
            down(i, key(word[i].toString()))
            up(i - 1)
        }
        up(word.length - 1)
        assertEquals("abcdefgh", out.toString())
    }

    @Test fun twoThumbsSpaceStillDownWhenNextLetterLands() {
        // "anh em": ngón cái phải còn đè space khi ngón trái chạm "e"
        for (c in "anh") { down(0, key(c.toString())); up(0) }
        down(1, space)
        down(0, key("e"))       // space phải chốt TRƯỚC "e"
        up(1)
        up(0)
        down(0, key("m")); up(0)
        assertEquals("anh em", out.toString())
    }

    @Test fun cancelledSpaceStillCommits() {
        down(0, key("a")); up(0)
        down(1, space)
        up(1)                   // ACTION_CANCEL đi cùng đường release
        assertEquals("a ", out.toString())
    }

    @Test fun punctuationThenSpaceOverlap() {
        down(0, key("a")); up(0)
        down(1, comma)
        down(2, space)
        up(1); up(2)
        assertEquals("a, ", out.toString())
    }

    @Test fun trackpadDisarmDropsSpace() {
        down(0, key("a")); up(0)
        down(1, space)
        q.disarm(held[1]!!)
        up(1)
        assertEquals("a", out.toString())
    }
}
