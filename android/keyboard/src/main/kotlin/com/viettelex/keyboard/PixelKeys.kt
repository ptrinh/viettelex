package com.viettelex.keyboard

/**
 * Dáng phím "pixel" (theme JSON "keyShape":"pixel" — theme Pixel 8-bit): góc cắt 2 bậc theo KHỐI, viền 1 khối đậm,
 * bóng khối cứng dưới/phải (không mờ, không khử răng cưa); bấm = mặt phím lún 1 khối xuống-phải, mất bóng.
 *
 * Hình học THUẦN giống hệt iOS (iOS/Keyboard/PixelKeys.swift) — fixture chung
 * iOS/KeyboardTests/Fixtures/pixel-key-cases.txt. Android vẽ thẳng các hình chữ nhật ([write] ghi vào mảng có sẵn —
 * 0 cấp phát mỗi khung); iOS vẽ cùng hình học vào ảnh 9-slice tí hon.
 */
object PixelKeys {
    const val SHAPE = "pixel"
    /** Phím cao [CELLS] khối (mặt 15 + bóng 1) ⇒ khối = chiều cao phím / 16. */
    const val CELLS = 16
    /** [write]: dải viền + bóng (màu viền) từ [INK], tối đa [INK_MAX]; dải lõi từ [FILL], tối đa [FILL_MAX]; mỗi dải l,t,r,b. */
    const val INK = 0
    const val INK_MAX = 11
    const val FILL = INK_MAX * 4
    const val FILL_MAX = 4
    const val FLOATS = FILL + FILL_MAX * 4

    data class Rect(val l: Double, val t: Double, val r: Double, val b: Double)
    /** Hai vùng RỜI NHAU (màu trong suốt một phần không cộng dồn alpha): viền + bóng, lõi. */
    data class Layers(val ink: List<Rect>, val fill: List<Rect>)

    fun block(keyHeight: Double): Double = keyHeight / CELLS

    /** Dời nhãn / icon theo tâm MẶT phím: thường −k/2 (mặt lệch trái-trên vì bóng), lún +k/2. */
    fun labelShift(block: Double, pressed: Boolean): Double = if (pressed) block / 2 else -block / 2

    /**
     * Phím điểm ảnh trong khung (l, t, r, b), khối [k], cắt theo HÀNG khối — y hệt iOS PixelKeys.layers. Mặt (fl, ft, fr,
     * fb) = khung bớt 1 khối phải + dưới; bấm: mặt dời 1 khối xuống-phải, không bóng. Hình = mặt cắt góc 2 bậc (∪ chính
     * nó dời (k, k) = bóng); lõi = hình lõm 1 khối. Ghi vào [out] (≥ [FLOATS]) — 0 cấp phát. Trả số dải:
     * `ink = kq and 0xFF`, `fill = kq shr 8`.
     */
    fun write(out: FloatArray, l: Float, t: Float, r: Float, b: Float, k: Float, pressed: Boolean): Int {
        val d = if (pressed) k else 0f
        val fl = l + d; val ft = t + d; val fr = r - k + d; val fb = b - k + d
        var n = 0
        if (pressed) {
            n = row(out, n, ft, ft + k, fl + 2 * k, fr - 2 * k, Float.NaN, Float.NaN)
            n = row(out, n, ft + k, ft + 2 * k, fl + k, fr - k, fl + 2 * k, fr - 2 * k)
            n = row(out, n, ft + 2 * k, fb - 2 * k, fl, fr, fl + k, fr - k)
            n = row(out, n, fb - 2 * k, fb - k, fl + k, fr - k, fl + 2 * k, fr - 2 * k)
            n = row(out, n, fb - k, fb, fl + 2 * k, fr - 2 * k, Float.NaN, Float.NaN)
        } else {
            n = row(out, n, ft, ft + k, fl + 2 * k, fr - 2 * k, Float.NaN, Float.NaN)
            n = row(out, n, ft + k, ft + 2 * k, fl + k, fr - k, fl + 2 * k, fr - 2 * k)
            n = row(out, n, ft + 2 * k, ft + 3 * k, fl, fr, fl + k, fr - k)
            n = row(out, n, ft + 3 * k, fb - 2 * k, fl, fr + k, fl + k, fr - k)
            n = row(out, n, fb - 2 * k, fb - k, fl + k, fr + k, fl + 2 * k, fr - 2 * k)
            n = row(out, n, fb - k, fb, fl + 2 * k, fr, Float.NaN, Float.NaN)
            n = row(out, n, fb, fb + k, fl + 3 * k, fr - k, Float.NaN, Float.NaN)
        }
        return n
    }

    /** Một hàng: vùng hình [ul, ur) trừ lõi [xl, xr) (NaN = không lõi) ⇒ 1–2 dải viền (+ 1 dải lõi). [n] = số đã ghi. */
    private fun row(out: FloatArray, n: Int, y0: Float, y1: Float, ul: Float, ur: Float, xl: Float, xr: Float): Int {
        var ni = n and 0xFF
        var nf = n shr 8
        if (xl.isNaN()) {
            put(out, INK + 4 * ni++, ul, y0, ur, y1)
        } else {
            put(out, INK + 4 * ni++, ul, y0, xl, y1)
            put(out, INK + 4 * ni++, xr, y0, ur, y1)
            put(out, FILL + 4 * nf++, xl, y0, xr, y1)
        }
        return ni or (nf shl 8)
    }

    private fun put(out: FloatArray, i: Int, a: Float, b: Float, c: Float, e: Float) {
        out[i] = a; out[i + 1] = b; out[i + 2] = c; out[i + 3] = e
    }

    /** Như [write] nhưng trả danh sách (test / so fixture chung). */
    fun layers(l: Double, t: Double, r: Double, b: Double, block: Double, pressed: Boolean): Layers {
        val out = FloatArray(FLOATS)
        val n = write(out, l.toFloat(), t.toFloat(), r.toFloat(), b.toFloat(), block.toFloat(), pressed)
        fun rect(i: Int) = Rect(out[i].toDouble(), out[i + 1].toDouble(), out[i + 2].toDouble(), out[i + 3].toDouble())
        return Layers((0 until (n and 0xFF)).map { rect(INK + 4 * it) }, (0 until (n shr 8)).map { rect(FILL + 4 * it) })
    }
}
