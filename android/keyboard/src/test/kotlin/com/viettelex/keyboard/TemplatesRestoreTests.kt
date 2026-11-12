package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/** "Hoàn tác" sau khi vuốt xoá mẫu câu (báo lỗi 13/11/2026: vuốt nhầm là mất). */
class TemplatesRestoreTests {
    private val r6 = TemplateItem("R6", "Cảm ơn anh")
    private val r7 = TemplateItem("R7", "Em gọi lại sau")
    private val r8 = TemplateItem("R8", "Đã nhận")

    @Test fun restoresAtSamePositionWithLabel() {
        val before = listOf(r6, r7, r8)
        val after = before - r7
        assertEquals(before, Templates.restore(after, 1, r7))
        assertEquals(before, Templates.restore(before - r6, 0, r6))
        assertEquals(before, Templates.restore(before - r8, 2, r8))
    }

    @Test fun clampsIndexWhenListShrank() {
        assertEquals(listOf(r6, r8), Templates.restore(listOf(r6), 5, r8))
        assertEquals(listOf(r8), Templates.restore(emptyList(), 2, r8))
    }

    @Test fun noDuplicateWhenTextAlreadyBack() {
        val cur = listOf(r6, TemplateItem("", r7.text))
        assertSame(cur, Templates.restore(cur, 1, r7))
    }
}
