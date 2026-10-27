package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Quy tắc Bạn đồng hành iOS / Android giống nhau. Chỉ viết, không chạy suite vòng này. */
class KeyboardBuddyExtrasTests {
    @Test fun clockBoundaries() {
        assertEquals(BuddyClock.Part.NIGHT, BuddyClock.part(4, 59))
        assertEquals(BuddyClock.Part.MORNING, BuddyClock.part(5, 0))
        assertEquals(BuddyClock.Part.MORNING, BuddyClock.part(8, 59))
        assertEquals(BuddyClock.Part.DAY, BuddyClock.part(9, 0))
        assertEquals(BuddyClock.Part.DAY, BuddyClock.part(22, 59))
        assertEquals(BuddyClock.Part.NIGHT, BuddyClock.part(23, 0))
        assertEquals(BuddyClock.Part.NIGHT, BuddyClock.part(0, 0))
    }

    @Test fun birthdayRulesAndTriggers() {
        assertFalse(BuddyBirthday.valid(0, 1))
        assertTrue(BuddyBirthday.valid(2, 29))
        assertTrue(BuddyBirthday.matches(2, 29, 2024, 2, 29))
        assertTrue(BuddyBirthday.matches(2, 29, 2025, 2, 28))
        assertFalse(BuddyBirthday.matches(2, 29, 2024, 2, 28))
        assertFalse(BuddyBirthday.matches(2, 29, 2100, 2, 29))
        for (word in listOf("hpbd", "hbd", "sinh nhật", "happy birthday", "🎂", "🎉", "🥳", "🎈")) {
            assertTrue(word, BuddyBirthday.trigger(word, null))
            assertEquals(word, BuddyReaction.CAKE, BuddyWords.reaction(word, null))
        }
        assertTrue(BuddyBirthday.trigger("nhật", "sinh"))
        assertTrue(BuddyBirthday.trigger("birthday", "happy"))
        assertFalse(BuddyBirthday.trigger("happy", null))
        assertEquals(8, BuddyFX.count(BuddyReaction.CAKE))
        assertEquals(3, BuddyFX.count(BuddyReaction.TICKLE))
        assertTrue(BuddyOutfit.make(null, BuddyCharacter.CAT, night = true).pieces.isNotEmpty())
        assertEquals(BuddyOutfit.make(BuddySeason.CHRISTMAS, BuddyCharacter.CAT).pieces.size,
            BuddyOutfit.make(BuddySeason.CHRISTMAS, BuddyCharacter.CAT, night = true).pieces.size)
        assertEquals(4, BuddyProp.make(BuddyReaction.CAKE, BuddyRig.CAT).size)
    }

    @Test fun namesAndBackupKeys() {
        assertEquals("Mướp", BuddyName.clean("  Mướp\n"))
        assertEquals("a".repeat(20), BuddyName.clean("a".repeat(30)))
        assertEquals("🐱".repeat(20), BuddyName.clean("🐱".repeat(21)))
        assertEquals("buddyName.cat", BuddyName.key(BuddyCharacter.CAT))
        assertEquals("Mướp chào bạn!", BuddyName.bubble("Mướp", false, 30))
        assertEquals("Mướp says hi!", BuddyName.bubble("Mướp", true, 30))
        assertEquals("Mướp sa…", BuddyName.bubble("Mướp", true, 8))
        assertNull(BuddyName.bubble("", false, 30))
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF })
            assertTrue(BackupSettings.all.any { it.key == BuddyName.key(c) })
        assertTrue(BackupSettings.all.any { it.key == BuddyBirthday.MONTH_KEY })
        assertTrue(BackupSettings.all.any { it.key == BuddyBirthday.DAY_KEY })
    }

    @Test fun tickleOnlyAtFigureInsideReservedStrip() {
        val strip = 40.0
        for (size in listOf(1, 5, 20)) for (right in listOf(-100, 0, 100)) for (top in listOf(-100, 0, 100)) {
            val placement = BuddyPlacement(size, right, top)
            val zoneWidth = placement.zoneWidth(34.0)
            val zone = BuddyRect(390.0 - zoneWidth, 0.0, zoneWidth, strip)
            val figure = placement.frame(BuddyRect(324, 0, 66, 66), zoneWidth, fullHeight = 260.0)
            val x0 = maxOf(zone.x, figure.x); val x1 = minOf(zone.x + zone.w, figure.x + figure.w)
            val y0 = maxOf(0.0, figure.y); val y1 = minOf(strip, figure.y + figure.h)
            if (x0 < x1 && y0 < y1) assertTrue(BuddyTap.tickles((x0 + x1) / 2, (y0 + y1) / 2, zone, strip, figure))
            assertFalse("phím luôn thắng: $size, $right, $top", BuddyTap.tickles(figure.x + figure.w / 2, 55.0, zone, strip, figure))
            assertFalse(BuddyTap.tickles(zone.x - 1, 10.0, zone, strip, figure))
        }
    }
}
