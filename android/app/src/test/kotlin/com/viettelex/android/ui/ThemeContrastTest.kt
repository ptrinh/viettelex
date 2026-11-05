package com.viettelex.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** #150: menu ⋯ của theme ở chế độ tối có nền sáng + chữ trắng. Menu/hộp thoại Material vẽ nền theo
 *  surfaceContainer*, chữ lấy LocalTextStyle (= label) ⇒ nền phải tương phản với label ở cả 2 chế độ. */
class ThemeContrastTest {
    private fun contrast(a: Color, b: Color): Double {
        val la = a.luminance() + 0.05; val lb = b.luminance() + 0.05
        return (maxOf(la, lb) / minOf(la, lb)).toDouble()
    }

    @Test fun menuAndDialogSurfacesContrastWithLabel() {
        for (dark in listOf(false, true)) {
            val c = vtColors(dark)
            val s = vtColorScheme(c)
            for ((name, bg) in listOf(
                "surface" to s.surface, "surfaceContainer" to s.surfaceContainer,
                "surfaceContainerHigh" to s.surfaceContainerHigh, "surfaceContainerHighest" to s.surfaceContainerHighest,
            )) {
                assertTrue("dark=$dark $name vs label: ${contrast(bg, c.label)}", contrast(bg, c.label) >= 7.0)
            }
            assertEquals(c.label, s.onSurface)
        }
    }

    @Test fun darkSchemeSurfacesAreDark() {
        val s = vtColorScheme(vtColors(true))
        assertTrue(s.surfaceContainer.luminance() < 0.2f)
        assertTrue(vtColorScheme(vtColors(false)).surfaceContainer.luminance() > 0.8f)
    }
}
