package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Dáng phím "pixel" (theme Pixel 8-bit): hình học CHUNG iOS qua iOS/KeyboardTests/Fixtures/pixel-key-cases.txt
 * (iOS PixelKeysTests.testSharedGeometryWithAndroid), vùng rời nhau, đường vẽ không cấp phát.
 */
class PixelKeysTests {
    private fun fixture(): File =
        listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/pixel-key-cases.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures/pixel-key-cases.txt")

    private fun rects(s: String): List<PixelKeys.Rect> = if (s == "-") emptyList() else s.split(";").map { r ->
        val v = r.split(",").map { it.toDouble() }
        PixelKeys.Rect(v[0], v[1], v[2], v[3])
    }

    private fun assertRects(msg: String, want: List<PixelKeys.Rect>, got: List<PixelKeys.Rect>) {
        assertEquals(msg, want.size, got.size)
        for ((a, b) in want.zip(got)) {
            for ((p, q) in listOf(a.l to b.l, a.t to b.t, a.r to b.r, a.b to b.b)) assertEquals(msg, p, q, 1e-6)
        }
    }

    @Test fun sharedGeometryWithIOS() {
        var n = 0
        for (line in fixture().readLines()) {
            if (line.isEmpty() || line.startsWith("#")) continue
            val c = line.split("\t")
            when (c[0]) {
                "KEY" -> {
                    val f = c[1].split(" ").map { it.toDouble() }
                    val ly = PixelKeys.layers(f[0], f[1], f[2], f[3], c[2].toDouble(), c[3] == "1")
                    assertRects("$line viền+bóng", rects(c[4]), ly.ink)
                    assertRects("$line lõi", rects(c[5]), ly.fill)
                }
                "BLOCK" -> assertEquals(line, c[2].toDouble(), PixelKeys.block(c[1].toDouble()), 1e-4)
                "SHIFT" -> assertEquals(line, c[3].toDouble(), PixelKeys.labelShift(c[1].toDouble(), c[2] == "1"), 1e-6)
                else -> error("dòng lạ: $line")
            }
            n++
        }
        assertTrue(n >= 16)
    }

    /** Vùng viền+bóng và lõi RỜI NHAU (màu trong suốt một phần không cộng dồn alpha), lấp đúng hình phím 16×16. */
    @Test fun regionsAreDisjointAndCoverTheShape() {
        for (pressed in listOf(false, true)) {
            val ly = PixelKeys.layers(0.0, 0.0, 16.0, 16.0, 1.0, pressed)
            val grid = Array(16) { IntArray(16) }
            for (r in ly.ink + ly.fill) for (y in r.t.toInt() until r.b.toInt()) for (x in r.l.toInt() until r.r.toInt()) grid[y][x]++
            assertTrue(grid.all { row -> row.all { it <= 1 } })
            // Thường: hàng 0 có viền cột 2…12, góc trên-trái trống, bóng hàng 15; lún: hàng 0 / cột 0 trống.
            if (!pressed) {
                assertEquals(0, grid[0][1]); assertEquals(1, grid[0][2]); assertEquals(1, grid[15][6]); assertEquals(0, grid[15][15])
            } else {
                assertTrue((0 until 16).all { grid[0][it] == 0 && grid[it][0] == 0 })
            }
        }
    }

    @Test fun writeIsAllocationFreeShape() {
        val out = FloatArray(PixelKeys.FLOATS)
        val n = PixelKeys.write(out, 0f, 0f, 60f, 48f, 3f, false)
        assertEquals(11, n and 0xFF); assertEquals(4, n shr 8)
        val p = PixelKeys.write(out, 0f, 0f, 60f, 48f, 3f, true)
        assertEquals(8, p and 0xFF); assertEquals(3, p shr 8)
    }
}
