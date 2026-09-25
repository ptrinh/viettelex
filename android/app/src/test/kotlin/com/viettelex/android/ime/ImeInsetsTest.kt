package com.viettelex.android.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class ImeInsetsTest {
    @Test fun gestureNavAndroid15ReservesStripForImeButtons() {
        // nút ⌄/🌐 hệ thống: navigationBars = 0 ở một số bản, tappableElement = 48dp×2.625
        assertEquals(126, ImeInsets.bottomPad(36, 0, 126, 132, insetsKnown = true))
        assertEquals(126, ImeInsets.bottomPad(36, 126, 63, 132, insetsKnown = true))
    }

    @Test fun threeButtonNav() {
        assertEquals(126, ImeInsets.bottomPad(35, 126, 126, 132, insetsKnown = true))
        assertEquals(126, ImeInsets.bottomPad(30, 126, 126, 132, insetsKnown = true))
    }

    @Test fun olderAndroidNeverDoublePads() {
        // < 35: hệ thống đã đặt IME trên nav bar
        assertEquals(0, ImeInsets.bottomPad(34, 0, 0, 132, insetsKnown = false))
        assertEquals(0, ImeInsets.bottomPad(26, 0, 0, 132, insetsKnown = true))
    }

    @Test fun android15FallbackOnlyWhenInsetsNeverArrived() {
        assertEquals(132, ImeInsets.bottomPad(35, 0, 0, 132, insetsKnown = false))
        assertEquals(0, ImeInsets.bottomPad(35, 0, 0, 132, insetsKnown = true))   // immersive / không nav
        assertEquals(0, ImeInsets.bottomPad(35, -5, 0, 0, insetsKnown = false))
    }

    @Test fun totalHeight() {
        // 34 strip + 218 phím + 48 dải nút hệ thống (dp = px)
        assertEquals(300, ImeInsets.totalHeight(34, 218, 48))
        assertEquals(218, ImeInsets.totalHeight(0, 218, 0))
    }
}
