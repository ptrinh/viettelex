package com.viettelex.android.ime

import com.viettelex.android.ime.TrackpadGesture.Axis
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackpadTest {
    /** Kéo từ (0,0) theo các điểm, mỗi điểm cách [dtMs]; trả mọi bước phát ra. */
    private fun drag(points: List<Pair<Float, Float>>, dtMs: Long): List<TrackpadGesture.Step> {
        val g = TrackpadGesture()
        g.begin(0f, 0f, 0)
        var t = 0L
        return points.mapNotNull { (x, y) -> t += dtMs; g.move(x, y, t) }
    }

    @Test fun slowHorizontalIsExactPerCharacter() {
        // 3 dp mỗi 50 ms = 60 dp/s: 90 dp ⇒ đúng 10 ký tự, từng bước 1.
        val steps = drag((1..30).map { it * 3f to 0f }, 50)
        assertEquals(10, steps.sumOf { it.count })
        steps.forEach { assertEquals(Axis.H, it.axis); assertEquals(1, it.count) }
    }

    @Test fun fastHorizontalAccelerates() {
        // 30 dp mỗi 16 ms ≈ 1875 dp/s ⇒ ×5.
        val steps = drag((1..6).map { it * 30f to 0f }, 16)
        assertEquals(Axis.H, steps.last().axis)
        assertEquals(20, steps.last().count)            // 4 ô (dư 30+33+36 cộng dồn) × 5
        assertTrue(steps.sumOf { it.count } > 180 / 9)
    }

    @Test fun leftIsNegative() {
        val steps = drag((1..10).map { -it * 3f to 0f }, 50)
        assertEquals(-3, steps.sumOf { it.count })
    }

    @Test fun slightlyDiagonalHorizontalNeverChangesLine() {
        // Kéo ngang 300 dp, trôi xuống 60 dp (> 2 dòng) — vẫn không bước dọc nào.
        val steps = drag((1..100).map { it * 3f to it * 0.6f }, 30)
        steps.forEach { assertEquals(Axis.H, it.axis) }
        assertEquals(300 / 9, steps.sumOf { it.count })
    }

    @Test fun verticalDragMovesLinesDespiteJitter() {
        // 4 dp mỗi 60 ms ≈ 67 dp/s xuống, rung ngang ±2 dp: 96 dp ⇒ 4 dòng.
        val steps = drag((1..24).map { (if (it % 2 == 0) 2f else -2f) to it * 4f }, 60)
        assertEquals(listOf(Axis.V), steps.map { it.axis }.distinct())
        assertEquals(4, steps.sumOf { it.count })
    }

    @Test fun upIsNegativeAndFastVerticalAccelerates() {
        val slow = drag((1..6).map { 0f to -it * 4f }, 60)
        assertEquals(-1, slow.sumOf { it.count })
        val fast = drag((1..4).map { 0f to it * 30f }, 16)   // ~1875 dp/s ⇒ ×3
        assertEquals(Axis.V, fast.last().axis)
        assertEquals(6, fast.last().count)                    // 2 dòng (dư cộng dồn) × 3
    }

    private fun List<TrackpadGesture.Step>.sum(axis: Axis) = filter { it.axis == axis }.sumOf { it.count }

    /**
     * Hồi quy "chỉ đi được mỗi 1 dòng": kéo dọc lệch ngang ~17° — bản khoá trục cũ ra
     * bước ngang trước (dx đủ 9 dp sau ~22 dp dọc) rồi xoá dy ⇒ không bao giờ đổi dòng.
     */
    @Test fun mostlyVerticalWithDriftChangesLinesOnly() {
        val steps = drag((1..30).map { it * 1.2f to it * 4f }, 50)
        assertEquals(120 / 24, steps.sum(Axis.V))
        assertEquals(0, steps.sum(Axis.H))
    }

    @Test fun diagonalDragMovesBothAxes() {
        // 45°, 3 dp / 30 ms mỗi trục (không tăng tốc): 300 dp ⇒ ~33 ký tự + ~12 dòng lên.
        val steps = drag((1..100).map { it * 3f to -it * 3f }, 30)
        assertTrue(steps.sum(Axis.H) in 32..33)
        assertTrue(steps.sum(Axis.V) in -12..-11)
    }

    @Test fun turningFromHorizontalToVerticalInOneDrag() {
        val pts = (1..30).map { it * 3f to 0f } + (1..24).map { 90f to it * 4f }
        val steps = drag(pts, 50)
        assertEquals(10, steps.sum(Axis.H))
        assertTrue(steps.sum(Axis.V) in 3..4)
        val firstV = steps.indexOfFirst { it.axis == Axis.V }
        assertTrue(steps.drop(firstV).all { it.axis == Axis.V })
        // Dọc rồi quay ngang: vài dp đầu còn mang hướng dọc (bỏ), sau đó 9 dp = 1 ký tự.
        val g = TrackpadGesture()
        g.begin(0f, 0f, 0)
        assertEquals(Axis.V, g.move(0f, 30f, 100)!!.axis)
        assertNull(g.move(4f, 30f, 200))
        assertNull(g.move(8f, 30f, 300))
        assertNull(g.move(12f, 30f, 400))
        assertEquals(TrackpadGesture.Step(Axis.H, 1), g.move(16f, 30f, 500))
    }

    @Test fun accelerateCurve() {
        assertEquals(3, TrackpadGesture.accelerate(3, 100.0, 300.0, 1500.0, 5.0))
        assertEquals(-2, TrackpadGesture.accelerate(-2, 300.0, 300.0, 1500.0, 5.0))
        assertEquals(3, TrackpadGesture.accelerate(1, 900.0, 300.0, 1500.0, 5.0))   // ×3 giữa đường
        assertEquals(-5, TrackpadGesture.accelerate(-1, 9999.0, 300.0, 1500.0, 5.0))
        assertEquals(0, TrackpadGesture.accelerate(0, 9999.0, 300.0, 1500.0, 5.0))
    }

    // --- VerticalMove.offset ---

    @Test fun offsetKeepsColumnAndClampsToShortLine() {
        assertEquals(-7, VerticalMove.offset("abcdef\nxyz", "", -1))      // cột 3 ⇒ "abc|def"
        assertEquals(-5, VerticalMove.offset("ab\nwxyz", "", -1))         // "ab" ngắn ⇒ cuối
        assertEquals(5, VerticalMove.offset("ab", "cd\nwxyz", 1))         // cột 2 ⇒ "wx|yz"
        assertEquals(3, VerticalMove.offset("abcd", "\nxy", 1))           // cuối dòng "xy"
    }

    @Test fun offsetGraphemeColumns() {
        // Cột theo grapheme: "😀é" = 2 cột (😀 = 2 UTF-16, é tổ hợp = 2 UTF-16).
        val before = "a😀bc\n😀é"
        // Dòng trên cột 2 = sau "a😀" (3 UTF-16) ⇒ vị trí 3; hiện tại ở cuối (len 10).
        assertEquals(3 - before.length, VerticalMove.offset(before, "", -1))
        // Xuống: cột 2 trên dòng "x👨‍👩‍👧y" ⇒ sau ZWJ family trọn vẹn.
        val family = "👨‍👩‍👧"
        assertEquals(1 + 1 + family.length, VerticalMove.offset("😀é", "\nx${family}y", 1))
    }

    @Test fun offsetBoundariesAndMultipleLines() {
        assertNull(VerticalMove.offset("abc", "def", -1))                 // dòng đầu
        assertNull(VerticalMove.offset("abc", "def", 1))                  // dòng cuối
        assertEquals(-6, VerticalMove.offset("a\nbc\nde", "", -5))         // chỉ 2 dòng ⇒ "a" (ngắn ⇒ cuối)
        assertEquals(4, VerticalMove.offset("", "a\nb\nc", 2))            // cột 0 dòng thứ 3
        assertEquals(-4, VerticalMove.offset("ab\r\ncd", "", -1))         // \r\n là một ngắt
    }
}
