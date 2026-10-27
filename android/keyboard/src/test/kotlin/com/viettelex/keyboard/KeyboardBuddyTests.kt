package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.lang.management.ManagementFactory
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * "Bạn đồng hành" ([KeyboardBuddy]): máy trạng thái theo dấu giờ, bậc tốc độ, dáng, phản ứng theo từ, hoảng khi xoá
 * dồn, mùa lễ, cổng Plus, 0 khung hình khi ngủ, 500 phím không cấp phát / không rò, chi phí mỗi phím. Số tham chiếu
 * (bậc, mốc giờ, checksum bảng hình, grawlix, quỹ đạo hạt) GIỐNG HỆT iOS KeyboardBuddyTests.
 */
class KeyboardBuddyTests {
    private var savedPaywall = PlusGate.paywallEnabled

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled }

    @After fun tearDown() { PlusGate.paywallEnabled = savedPaywall; PlusGate.install({ null }, debugBuild = false) }

    // MARK: cài đặt

    @Test fun idsMatchIOSAndDefaultIsOff() {
        assertEquals(listOf("off", "girl", "boy", "cat", "chick", "shiba", "koi", "panda", "pig", "dragon", "eagle", "robot"), BuddyCharacter.IDS.toList())
        assertEquals(BuddyCharacter.ROBOT, BuddyCharacter.of("robot"))
        assertTrue(BuddyCharacter.ROBOT.isPlus)
        assertEquals(BuddyStyle.VECTOR, BuddyStyle.SPRITE.resolved(BuddyCharacter.ROBOT))
        assertEquals("keyboardBuddy", Keys.KEYBOARD_BUDDY)
        assertEquals(BuddyCharacter.OFF, BuddyCharacter.DEFAULT)
        assertEquals(BuddyCharacter.OFF, BuddyCharacter.of("lạ"))
        assertEquals(BuddyCharacter.OFF, BuddyCharacter.of(null))
        assertEquals(BuddyCharacter.CHICK, BuddyCharacter.of("chick"))
        for (c in BuddyCharacter.entries.drop(5)) assertEquals(c, BuddyCharacter.of(c.id))
        assertTrue(BackupSettings.all.any { it.key == Keys.KEYBOARD_BUDDY })
    }

    @Test fun settingsLoad() {
        assertEquals(BuddyCharacter.OFF, KeyboardSettings.load { null }.buddy)
        assertEquals(BuddyCharacter.CAT, KeyboardSettings.load { if (it == Keys.KEYBOARD_BUDDY) "cat" else null }.buddy)
    }

    /** = iOS testStyleKeysAndDefault: kiểu vẽ riêng từng nhân vật, mặc định Hoạt hình, khoá `buddyStyle.<id>`. */
    @Test fun styleKeysAndDefault() {
        assertEquals(listOf("sprite", "vector"), BuddyStyle.IDS.toList())
        assertEquals(BuddyStyle.SPRITE, BuddyStyle.DEFAULT)
        assertEquals("buddyStyle.girl", BuddyStyle.key(BuddyCharacter.GIRL))
        assertEquals("buddyStyle.chick", BuddyStyle.key(BuddyCharacter.CHICK))
        assertEquals(BuddyStyle.SPRITE, BuddyStyle.of(null))
        assertEquals(BuddyStyle.SPRITE, BuddyStyle.of("lạ"))
        assertEquals(BuddyStyle.VECTOR, BuddyStyle.of("vector"))
        assertEquals(BuddyStyle.SPRITE, KeyboardSettings.load { if (it == Keys.KEYBOARD_BUDDY) "cat" else null }.buddyStyle)
        val prefs = mapOf(Keys.KEYBOARD_BUDDY to "cat", "buddyStyle.cat" to "vector", "buddyStyle.boy" to "sprite")
        assertEquals(BuddyStyle.VECTOR, KeyboardSettings.load { prefs[it] }.buddyStyle)
        assertEquals("riêng từng nhân vật", BuddyStyle.SPRITE,
            KeyboardSettings.load { (prefs + (Keys.KEYBOARD_BUDDY to "boy"))[it] }.buddyStyle)
        assertEquals(BuddyStyle.VECTOR, BuddyStyle.SPRITE.resolved(BuddyCharacter.EAGLE))
        assertEquals(BuddyStyle.VECTOR, KeyboardSettings.load { if (it == Keys.KEYBOARD_BUDDY) "dragon" else null }.buddyStyle)
        assertTrue(BuddyStyle.hasAtlas(BuddyCharacter.CAT))
        assertFalse(BuddyStyle.hasAtlas(BuddyCharacter.KOI))
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF })
            assertTrue("sao lưu kiểu vẽ $c", BackupSettings.all.any { it.key == BuddyStyle.key(c) })
    }

    /** Hoạt hình + mùa lễ ⇒ không trang phục; Vẽ nét + mùa lễ ⇒ trang phục; ngoài mùa ⇒ không. */
    @Test fun styleSeasonResolution() {
        assertNull(BuddyStyle.SPRITE.season(BuddySeason.TET))
        assertNull(BuddyStyle.SPRITE.season(null))
        assertSame(BuddySeason.CHRISTMAS, BuddyStyle.VECTOR.season(BuddySeason.CHRISTMAS))
        assertNull(BuddyStyle.VECTOR.season(null))
        assertTrue(BuddyOutfit.make(BuddyStyle.SPRITE.season(BuddySeason.CHRISTMAS), BuddyCharacter.GIRL).pieces.isEmpty())
        assertFalse(BuddyOutfit.make(BuddyStyle.VECTOR.season(BuddySeason.CHRISTMAS), BuddyCharacter.GIRL).pieces.isEmpty())
    }

    /** = iOS testPlacementMath: cỡ 5 = khung cũ; hệ số 0,68…1,40; neo đáy-phải; to thì lớn xuống; lề dời đúng chiều. */
    @Test fun placementMath() {
        fun eq(e: BuddyRect, a: BuddyRect) { assertEquals(e.x, a.x, 1e-9); assertEquals(e.y, a.y, 1e-9); assertEquals(e.w, a.w, 1e-9); assertEquals(e.h, a.h, 1e-9) }
        assertEquals(1.0, BuddyPlacement.STANDARD.scale(4.0), 1e-9)
        assertEquals(0.68, BuddyPlacement(size = 1).scale(4.0), 1e-9)
        assertEquals(4.0, BuddyPlacement(size = 20).scale(4.0), 1e-9)
        assertEquals(Math.pow(4.0, 1.0 / 3), BuddyPlacement(size = 10).scale(4.0), 1e-9)
        assertEquals(1.0, BuddyPlacement(size = 20).scale(0.5), 1e-9)
        val base = BuddyRect(324, 0, 66, 66)
        eq(base, BuddyPlacement.STANDARD.frame(base, 34.0))
        eq(BuddyRect(345, 21, 45, 45), BuddyPlacement(size = 1).frame(base, 34.0))
        eq(BuddyRect(304, 0, 86, 86), BuddyPlacement(size = 10).frame(base, 34.0))
        eq(BuddyRect(126, 0, 264, 264), BuddyPlacement(size = 20).frame(base, 34.0, fullHeight = 264.0))
        eq(BuddyRect(314, -4, 66, 66), BuddyPlacement(padRight = 10, padTop = -4).frame(base, 34.0))
        assertEquals(334.0, BuddyPlacement(padRight = -10).frame(base, 34.0).x, 1e-9)
        assertEquals(6.0, BuddyPlacement(padTop = 3).frame(base, 34.0, unit = 2.0).y, 1e-9)
        assertEquals(34.0, BuddyPlacement.STANDARD.zoneWidth(34.0), 1e-9)
        assertEquals(48.0, BuddyPlacement(size = 10).zoneWidth(34.0), 1e-9)
        assertEquals(29.0, BuddyPlacement(size = 1, padRight = 6).zoneWidth(34.0), 1e-9)
        assertEquals(34.0, BuddyPlacement(padRight = -6).zoneWidth(34.0), 1e-9)
        assertEquals(BuddyPlacement.STANDARD, KeyboardSettings.load { null }.buddyPlacement)
        val prefs = mapOf(Keys.BUDDY_SIZE to 42, Keys.BUDDY_PAD_RIGHT to -300, Keys.BUDDY_PAD_TOP to 7)
        assertEquals(44.0, BuddyPlacement(padRight = 100).zoneWidth(34.0), 1e-9)
        assertEquals(BuddyPlacement(20, -100, 7), KeyboardSettings.load { prefs[it] }.buddyPlacement)
        assertEquals(listOf("buddySize", "buddyPadRight", "buddyPadTop"), listOf(Keys.BUDDY_SIZE, Keys.BUDDY_PAD_RIGHT, Keys.BUDDY_PAD_TOP))
        for (k in prefs.keys) assertTrue("sao lưu $k", BackupSettings.all.any { it.key == k })
    }

    @Test fun plusFallback() {
        assertEquals(BuddyCharacter.OFF, BuddyPolicy.active(BuddyCharacter.GIRL, plus = false))
        assertEquals(BuddyCharacter.GIRL, BuddyPolicy.active(BuddyCharacter.GIRL, plus = true))
        assertEquals(BuddyCharacter.OFF, BuddyPolicy.active(BuddyCharacter.OFF, plus = true))
        assertFalse(BuddyCharacter.OFF.isPlus)
        assertFalse(BuddyCharacter.CAT.isPlus)
        assertTrue(BuddyCharacter.entries.filter { it != BuddyCharacter.OFF && it != BuddyCharacter.CAT }.all { it.isPlus })
        assertTrue(BuddyGate.allows(BuddyCharacter.OFF))
        // Bật thu phí, chưa mua ⇒ khoá; mua ⇒ mở.
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)
        assertFalse(BuddyGate.allows(BuddyCharacter.CAT))
        assertEquals(BuddyCharacter.OFF, BuddyPolicy.active(BuddyCharacter.CAT, BuddyGate.allows(BuddyCharacter.CAT)))
        PlusGate.install({ if (it == Keys.PLUS_UNLOCKED) true else null }, debugBuild = false)
        assertTrue(BuddyGate.allows(BuddyCharacter.CAT))
    }

    // MARK: bậc

    @Test fun tierFunction() {
        assertEquals(listOf(0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3), (0..16).map { BuddyTempo.tier(it, 0) })
        assertEquals(3, BuddyTempo.tier(13, 3)); assertEquals(3, BuddyTempo.tier(12, 3)); assertEquals(2, BuddyTempo.tier(11, 3))
        assertEquals(2, BuddyTempo.tier(8, 2)); assertEquals(1, BuddyTempo.tier(7, 2))
        assertEquals(1, BuddyTempo.tier(4, 1)); assertEquals(0, BuddyTempo.tier(3, 1))
    }

    @Test fun tierFromInterKeyInterval() {
        fun tierAfter(dt: Double): Int { val b = BuddyBrain(); var t = 0.0; repeat(40) { b.press(t); t += dt }; return b.tier }
        assertEquals(0, tierAfter(0.5)); assertEquals(1, tierAfter(0.3)); assertEquals(2, tierAfter(0.18)); assertEquals(3, tierAfter(0.11))
    }

    // MARK: máy trạng thái

    @Test fun stateMachineTimeline() {
        val b = BuddyBrain()
        assertSame(BuddyPhase.Asleep.QUIET, b.phase(0.0))
        assertNull(b.nextDeadline(0.0))
        var t = 10.0
        b.press(t)
        assertSame(BuddyPhase.Dancing.of(0), b.phase(t))
        assertEquals(t + BuddyBrain.TAIL, b.nextDeadline(t)!!, 1e-9)
        val seen = ArrayList<Int>()
        repeat(30) {
            t += 0.11; b.press(t)
            (b.phase(t) as? BuddyPhase.Dancing)?.let { if (seen.lastOrNull() != it.tier) seen += it.tier }
        }
        assertEquals(listOf(0, 1, 2, 3), seen)
        val last = t
        assertSame(BuddyPhase.Dancing.of(3), b.phase(last + 0.59))
        assertEquals(8.6, BuddyBrain.SLEEP_AFTER, 1e-9)
        assertSame(BuddyPhase.Idle, b.phase(last + 0.61))   // hết đuôi nhảy ⇒ lắc nhẹ
        assertEquals(last + 8.6, b.nextDeadline(last + 0.61)!!, 1e-9)
        assertSame(BuddyPhase.Idle, b.phase(last + 8.59))
        assertSame(BuddyPhase.Asleep.ZZZ, b.phase(last + 8.61))
        assertEquals(last + 10.6, b.nextDeadline(last + 8.61)!!, 1e-9)
        assertSame(BuddyPhase.Asleep.QUIET, b.phase(last + 10.61))
        assertNull(b.nextDeadline(last + 10.61))
        b.press(last + 20)
        assertSame(BuddyPhase.Dancing.of(0), b.phase(last + 20))
    }

    /** = iOS testIdleSwayBeforeSleep: ngừng gõ + 5 s vẫn lắc nhẹ, + 9 s đã ngủ. */
    @Test fun idleSwayBeforeSleep() {
        val b = BuddyBrain()
        b.press(10.0)
        assertSame(BuddyPhase.Idle, b.phase(15.0))
        assertSame(BuddyPhase.Asleep.ZZZ, b.phase(19.0))
        assertSame(BuddyPhase.Awake, BuddyPolicy.visual(BuddyPhase.Idle, true))
        assertTrue(BuddyPolicy.animates(BuddyPhase.Idle))
        val s = BuddyRig.GIRL.style
        assertTrue(BuddyDance.idle(s, 0.0).isRest())
        assertEquals(BuddyDance.pose(s, 0, 0.375, move = BuddyDance.Move.HIP_SWAY), BuddyDance.idle(s, 0.375))
        assertTrue(BuddyDance.IDLE_LOOP > BuddyDance.loopLength(0))
        assertEquals(listOf(5, 6), BuddySprites.IDLE.toList())
    }

    @Test fun lowPowerStaticOnly() {
        for (p in listOf(BuddyPhase.Dancing.of(3), BuddyPhase.Idle, BuddyPhase.Cheering, BuddyPhase.Awake, BuddyPhase.React.of(BuddyReaction.LOVE)))
            assertSame(BuddyPhase.Awake, BuddyPolicy.visual(p, true))
        assertSame(BuddyPhase.Asleep.QUIET, BuddyPolicy.visual(BuddyPhase.Asleep.ZZZ, true))
        assertFalse(BuddyPolicy.animates(BuddyPhase.Awake)); assertFalse(BuddyPolicy.animates(BuddyPhase.Asleep.QUIET))
    }

    // MARK: dáng

    @Test fun danceLoopsAndEnergyRises() {
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF }) {
            val s = BuddyRig.rig(c)!!.style
            val peaks = (0..3).map { t ->
                assertEquals(BuddyDance.pose(s, t, 0.0), BuddyDance.pose(s, t, 1.0))
                (0 until 200).maxOf { -BuddyDance.pose(s, t, it / 200.0).dy }
            }
            assertEquals(peaks.sorted(), peaks)
            assertTrue((0 until 100).all { BuddyDance.pose(s, 2, it / 100.0).sx == 1.0 })
            assertTrue((0 until 100).any { BuddyDance.pose(s, 3, it / 100.0, move = BuddyDance.Move.SPIN).sx < 0 })
            assertTrue(BuddyDance.cheer(s, 0.0).isRest())
        }
        assertEquals(2.48, BuddyDance.loopLength(0), 1e-9)
        assertEquals(1.44, BuddyDance.loopLength(3), 1e-9)
    }

    /** = iOS testPoseParityNumbers. */
    @Test fun poseParityNumbers() {
        val p = BuddyDance.pose(BuddyRig.GIRL.style, 2, 0.3)
        assertEquals(-4.4966, p.dy, 1e-3); assertEquals(6.4672, p.dx, 1e-3)
        assertEquals(1.8051, p.armL, 1e-3); assertEquals(-2.1049, p.armR, 1e-3); assertEquals(0.2829, p.tail, 1e-3)
    }

    // MARK: hình

    @Test fun svgParse() {
        assertEquals(listOf(BuddySVG.Cmd.Move(1.0, 2.0), BuddySVG.Cmd.Line(4.0, 6.0), BuddySVG.Cmd.Line(9.0, 6.0),
            BuddySVG.Cmd.Line(9.0, -6.0), BuddySVG.Cmd.Quad(10.0, -5.0, 11.0, -4.0), BuddySVG.Cmd.Close),
            BuddySVG.parse("M1 2 l3 4 h5 V-6 q1 1 2 2 Z"))
        assertEquals(listOf(-8.0, 72.0, -10.0, 140.0), BuddySVG.numbers("M-8 72 L-10 140"))
        assertEquals(listOf(1.5, -2.0), BuddySVG.numbers("h1.5-2"))
    }

    /** Bảng hình giống hệt iOS (KeyboardBuddyTests.checksums). */
    @Test fun rigChecksumParity() {
        val sums = BuddyCharacter.entries.map { String.format(Locale.US, "%.4f", BuddyRig.checksum(it)) }
        assertEquals(listOf("0.0000", "29155.8356", "19939.9990", "28728.3206", "20913.1220", "15269.7078", "14816.0100", "12385.2865", "14587.2357", "12839.3196", "16368.4397", "14471.9114"), sums)
    }

    /** = iOS testMirroredFramesDoublePoses: lật gương khung có sẵn để gấp đôi dáng. */
    @Test fun mirroredFramesDoublePoses() {
        val m = BuddySprites.MIRROR
        val turn = BuddySprites.dance(BuddyCharacter.BOY, 2).toList()
        assertTrue(1 in turn && 1 + m in turn)
        for (f in 2..6) assertTrue("khung $f có bản lật", f + m in turn)
        assertTrue(BuddySprites.dance(BuddyCharacter.GIRL, 0).any { BuddySprites.isMirrored(it) })
        assertTrue(BuddySprites.CHEER.any { BuddySprites.isMirrored(it) })
        for (seq in listOf(turn, BuddySprites.dance(BuddyCharacter.BOY, 0).toList(),
                BuddySprites.CHEER.toList(), BuddySprites.REACT.toList()))
            for (f in seq) assertTrue(BuddySprites.cell(f) < 7)
        assertEquals(3, BuddySprites.cell(103)); assertFalse(BuddySprites.isMirrored(6))
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF }) {
            val d = BuddySprites.dance(c, 3).toList(); val o = BuddySprites.turnOrder(c).toList()
            assertEquals(setOf(2, 3, 4, 5, 6), o.toSet())
            val s = d.indexOf(o[0])
            assertEquals("$c vòng trái", o, d.subList(s, s + 5))
            assertEquals("$c vòng phải", o.map { it + m }, d.subList(s + 6, s + 11))
        }
        assertEquals(listOf(6, 3, 4, 2, 5), BuddySprites.turnOrder(BuddyCharacter.GIRL).toList())
        for (tier in 1..3) {
            val d = BuddySprites.dance(BuddyCharacter.CAT, tier).map { BuddySprites.cell(it) }
            val swings = d.zipWithNext().count { setOf(it.first, it.second) == setOf(5, 6) }
            assertTrue("bậc $tier lắc hông", swings >= 3)
        }
        assertEquals(BuddyDance.loopLength(2) / 10, BuddySprites.duration(BuddyCharacter.BOY, 2) / turn.size, 1e-9)
    }

    @Test fun girlUsesSameEightFramesAsBoy() {
        for (tier in 0 until BuddyTempo.TIERS) {
            assertEquals(BuddySprites.dance(BuddyCharacter.BOY, tier).size,
                BuddySprites.dance(BuddyCharacter.GIRL, tier).size)
            assertEquals(BuddySprites.duration(BuddyCharacter.BOY, tier),
                BuddySprites.duration(BuddyCharacter.GIRL, tier), 0.0)
        }
        assertEquals(4, BuddySprites.columns(BuddyCharacter.GIRL))
        assertEquals(2, BuddySprites.rows(BuddyCharacter.GIRL))
        assertEquals(0, BuddySprites.rest(BuddyCharacter.GIRL))
        assertEquals(7, BuddySprites.sleep(BuddyCharacter.GIRL))
    }

    @Test fun everyRigComplete() {
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF }) {
            val r = BuddyRig.rig(c)!!
            val required = if (c == BuddyCharacter.KOI) listOf(BuddyPart.TAIL, BuddyPart.BODY, BuddyPart.ARM_L, BuddyPart.ARM_R, BuddyPart.HEAD, BuddyPart.SLEEP)
                else listOf(BuddyPart.LEG_L, BuddyPart.LEG_R, BuddyPart.BODY, BuddyPart.ARM_L, BuddyPart.ARM_R, BuddyPart.HEAD, BuddyPart.SLEEP)
            for (p in required)
                assertTrue("$c thiếu $p", r.pieces.any { it.part == p })
            for (p in r.pieces) if (p.part != BuddyPart.SLEEP) assertNotNull("$c ${p.part}", r.pivots[p.part])
        }
        assertTrue(BuddyRig.GIRL.hasTail && BuddyRig.CAT.hasTail)
        assertFalse(BuddyRig.BOY.hasTail || BuddyRig.CHICK.hasTail)
        assertEquals(7, BuddySprites.frameIndex(0.99, 8)); assertEquals(0, BuddySprites.frameIndex(1.0, 8))
    }

    // MARK: phản ứng

    @Test fun reactionMatching() {
        for (w in listOf("yêu", "Yêu", "YÊU", "yeu", "iu", "thương", "thuong", "love", "LOVE!", "luv", "miss", "thích", "thich",
            "crush", "tim", "hun", "honey", "baby", "nhớ", "cưng", "thơm", "muah"))
            assertEquals(w, BuddyReaction.LOVE, BuddyWords.reaction(w, null))
        for (w in listOf("haha", "hahaha", "HAHAHAHA", "hahah", "hihi", "hihihi", "hehe", "kkk", "kkkkkkk", "kaka", "lol", "lmao",
            "=))", "=)))))", ":))", "😂", "hjhjhj"))
            assertEquals(w, BuddyReaction.LAUGH, BuddyWords.reaction(w, null))
        for (w in listOf("wow", "woooow", "WOW!", "ôi", "omg", "omggg", "ủa", "hả", "what", "ồ", "á"))
            assertEquals(w, BuddyReaction.SURPRISED, BuddyWords.reaction(w, null))
        assertEquals(BuddyReaction.SURPRISED, BuddyWords.reaction("ơi", "trời"))
        for (w in listOf("buồn", "buon", "khóc", "huhu", "huhuhu", "hic", "hichic", "hix", "sad", ":(", ":(((", "chán", "😭"))
            assertEquals(w, BuddyReaction.SAD, BuddyWords.reaction(w, null))
        assertEquals(BuddyReaction.SAD, BuddyWords.reaction("mỏi", "mệt"))
        for (w in listOf("nho", "nhỏ", "cung", "thom", "chan", "a", "o", "ha", "an", "anh", "bàn", "trời", "k", "kk", "hah", ""))
            assertNull(w, BuddyWords.reaction(w, null))
        assertNull(BuddyWords.reaction("a".repeat(30), null))
    }

    @Test fun greetingEmojiAndSignatures() {
        for (w in listOf("hi", "hello", "hey", "hế lô", "hê lô", "helo", "chào", "alo", "yo", "sup", "hiii", "heyyy"))
            assertEquals(w, BuddyReaction.GREET, BuddyWords.reaction(w, null))
        assertEquals(BuddyReaction.GREET, BuddyWords.reaction("chào", "xin"))
        assertEquals(BuddyReaction.GREET, BuddyWords.reaction("morning", "good"))
        assertEquals(BuddyReaction.GREET, BuddyWords.reaction("sáng", "buổi", "chào"))
        for (w in listOf("chao", "they", "hockey")) assertNull(w, BuddyWords.reaction(w, null))
        assertNull(BuddyWords.reaction("chao", "xin"))
        for (w in listOf("haha", "hihi", "hehe", "hoho", "kkkk", "=)))", ":)))"))
            assertEquals(w, BuddyReaction.LAUGH, BuddyWords.reaction(w, null))
        assertEquals(BuddyReaction.SAD, BuddyWords.reaction("huhu", null))
        val groups = listOf(
            BuddyReaction.GREET to "👋 🙋 🙋‍♀️ 🙋‍♂️ 🤗", BuddyReaction.LOVE to "❤️ ♥️ 💕 💖 💗 😍 🥰 😘 😻 💋",
            BuddyReaction.LAUGH to "😂 🤣 😆 😄 😁 😹 😅 😝 😜", BuddyReaction.SURPRISED to "😮 😲 😱 🤯 😳 ‼️ ⁉️",
            BuddyReaction.SAD to "😢 😭 😞 😔 🥺 💔 😿", BuddyReaction.ANGRY to "😡 🤬 😠 👿 💢",
            BuddyReaction.LUCKY_MONEY to "🧧 🧨", BuddyReaction.GIFT to "🎁 🎄 🎅 🤶 ⛄",
            BuddyReaction.CANDY to "🎃 🍬 🍭 👻 🦇", BuddyReaction.MOONCAKE to "🥮 🏮 🌕")
        for ((reaction, group) in groups) for (emoji in group.split(" ")) {
            assertEquals(emoji, reaction, BuddyWords.emoji(emoji))
            assertEquals(emoji, reaction, BuddyWords.reaction(emoji, null))
        }
        assertEquals(BuddyReaction.GREET, BuddyWords.emoji("👋🏽"))
        assertEquals(BuddyReaction.GREET, BuddyWords.emoji("🙋🏽‍♀️"))
        assertEquals(BuddyReaction.GREET, BuddyWords.emoji("a🙋🏽‍♀️b"))
        assertEquals(BuddyReaction.LAUGH, BuddyWords.reaction("abc😂x", null))
        assertEquals(BuddyWords.emoji("❤️"), BuddyWords.emoji("❤"))
        assertEquals(BuddySignature.FIRE, BuddySignature.cheer(BuddyCharacter.DRAGON, 1))
        assertEquals(BuddySignature.LASER, BuddySignature.cheer(BuddyCharacter.EAGLE, 1))
        assertEquals(BuddySignature.EGG, BuddySignature.cheer(BuddyCharacter.CHICK, 3))
        assertNull(BuddySignature.cheer(BuddyCharacter.CHICK, 2))
        assertEquals(BuddySignature.YARN, BuddySignature.reaction(BuddyCharacter.CAT, BuddyReaction.PANIC))
        assertEquals(BuddySignature.SNORT, BuddySignature.reaction(BuddyCharacter.PIG, BuddyReaction.ANGRY))
        assertEquals(BuddySignature.BONE, BuddySignature.word(BuddyCharacter.SHIBA, "good dog"))
        assertEquals(BuddySignature.FIRE, BuddySignature.word(BuddyCharacter.DRAGON, "🐉"))
        for ((character, emojis) in listOf(BuddyCharacter.SHIBA to "🐶 🐕 🦴", BuddyCharacter.KOI to "🐟 🎏",
            BuddyCharacter.PANDA to "🐼 🎋", BuddyCharacter.PIG to "🐷 🐖", BuddyCharacter.DRAGON to "🐉 🐲 🔥",
            BuddyCharacter.EAGLE to "🦅")) for (emoji in emojis.split(" "))
            assertTrue(BuddyWords.signatureEmoji(emoji, character))
        assertEquals(BuddySignature.BAMBOO, BuddySignature.idle(BuddyCharacter.PANDA))
        assertEquals(BuddySignature.BREAKDANCE, BuddySignature.dance(BuddyCharacter.BOY, 3, 0, 0))
    }

    /** Giận dùng ĐÚNG bảng của bộ lọc gợi ý (từ / cặp / bộ ba), không phụ thuộc công tắc lọc. */
    @Test fun angryUsesSensitiveTables() {
        val bad = SensitiveWords.set.sorted().first()
        assertEquals(BuddyReaction.ANGRY, BuddyWords.reaction(bad, null))
        assertEquals(BuddyReaction.ANGRY, BuddyWords.reaction(bad.uppercase() + "!", null))
        val pair = SensitiveWords.pairs.entries.first { it.value.isNotEmpty() }
        val w2 = pair.value.sorted().first()
        if (w2 !in SensitiveWords.set) {
            assertEquals(BuddyReaction.ANGRY, BuddyWords.reaction(w2, pair.key))
            assertNotEquals(BuddyReaction.ANGRY, BuddyWords.reaction(w2, "xyz"))
        }
        assertEquals(BuddyReaction.ANGRY, BuddyWords.reaction("wtf", null))
        assertEquals(BuddyReaction.LOVE, BuddyWords.reaction("yêu", "anh"))
    }

    @Test fun priorityOrder() {
        assertEquals(listOf(BuddyReaction.ANGRY, BuddyReaction.LOVE, BuddyReaction.LAUGH, BuddyReaction.SURPRISED, BuddyReaction.SAD),
            BuddyReaction.entries.take(5))
        for (r in BuddyReaction.entries) assertTrue(r.duration in 0.8..1.5)
    }

    @Test fun grawlixDeterministicSymbolsOnly() {
        assertEquals(BuddyWords.grawlix(7), BuddyWords.grawlix(7))
        val distinct = HashSet<String>()
        for (s in 0 until 50) {
            val g = BuddyWords.grawlix(s)
            assertEquals(4, g.length)
            assertTrue(g, g.all { it in BuddyWords.GRAWLIX_SYMBOLS })
            distinct += g
        }
        assertTrue(distinct.size > 10)
        assertEquals("%&*#", BuddyWords.grawlix(1))   // = iOS
    }

    @Test fun reactionStateMachine() {
        val b = BuddyBrain()
        b.press(-5.0)
        assertSame(BuddyPhase.Asleep.QUIET, b.phase(10.0))
        b.react(BuddyReaction.LOVE, 10.0)
        assertSame(BuddyPhase.React.of(BuddyReaction.LOVE), b.phase(10.5))
        assertEquals(11.2, b.nextDeadline(10.5)!!, 1e-9)
        assertSame(BuddyPhase.Asleep.QUIET, b.phase(11.21))
        assertNull(b.nextDeadline(11.21))
        var t = 20.0
        repeat(12) { b.press(t); t += 0.15 }
        b.react(BuddyReaction.ANGRY, t)
        assertSame(BuddyPhase.React.of(BuddyReaction.ANGRY), b.phase(t + 0.1))
        for (k in 0 until 10) b.press(t + 0.15 * (k + 1))
        assertSame(BuddyPhase.Dancing.of(b.tier), b.phase(t + 1.21))
        val s0 = b.reactSerial
        b.react(BuddyReaction.LOVE, 50.0); b.react(BuddyReaction.LOVE, 50.5)
        assertEquals(s0 + 2, b.reactSerial)
        assertSame(BuddyPhase.React.of(BuddyReaction.LOVE), b.phase(51.6))
        b.react(BuddyReaction.ANGRY, 51.65)
        assertSame(BuddyPhase.React.of(BuddyReaction.ANGRY), b.phase(51.7))
        b.react(BuddyReaction.LOVE, 51.8)
        assertSame(BuddyPhase.React.of(BuddyReaction.LOVE), b.phase(51.9))
        assertNotEquals(BuddyPhase.React.of(BuddyReaction.LOVE), b.phase(53.01))
        val c = BuddyBrain()
        c.react(BuddyReaction.SAD, 1.0)
        assertSame(BuddyPhase.React.of(BuddyReaction.SAD), c.phase(1.1))
        assertSame(BuddyPhase.Asleep.QUIET, c.phase(2.6))
        for (r in BuddyReaction.entries.filter { it != BuddyReaction.PANIC }) for (s in listOf(BuddyRig.GIRL.style, BuddyRig.CAT.style)) {
            assertTrue("$r", BuddyDance.react(r, s, 0.0).isRest())
            assertEquals(0.0, BuddyDance.react(r, s, 1.0).armL, 1e-9)
        }
        assertTrue(BuddyDance.react(BuddyReaction.LOVE, BuddyRig.GIRL.style, 0.5).armL < 0)
        assertTrue(BuddyDance.react(BuddyReaction.PANIC, BuddyRig.GIRL.style, 0.5).armL > 2)
    }

    @Test fun deletePanicCounter() {
        val b = BuddyBrain()
        var t = 5.0
        repeat(8) { b.delete(t); assertNotEquals(BuddyPhase.React.of(BuddyReaction.PANIC), b.phase(t)); t += 0.09 }
        b.delete(t)
        assertSame(BuddyPhase.React.of(BuddyReaction.PANIC), b.phase(t))
        val serial = b.reactSerial
        repeat(20) { t += 0.09; b.delete(t) }
        assertEquals(serial, b.reactSerial)
        assertSame(BuddyPhase.React.of(BuddyReaction.PANIC), b.phase(t + 0.79))
        assertNotEquals(BuddyPhase.React.of(BuddyReaction.PANIC), b.phase(t + 0.81))
        t += 5
        repeat(6) { b.delete(t); t += 0.09 }
        b.press(t); t += 0.09
        repeat(6) { b.delete(t); t += 0.09 }
        assertNotEquals(BuddyPhase.React.of(BuddyReaction.PANIC), b.phase(t - 0.09))
        t += 1
        repeat(6) { b.delete(t); t += 0.09 }
        t += 0.6
        repeat(6) { b.delete(t); t += 0.09 }
        assertNotEquals(BuddyPhase.React.of(BuddyReaction.PANIC), b.phase(t - 0.09))
    }

    @Test fun fxParticlesCappedAndConfined() {
        val rad = BuddyFX.PARTICLE_SIZE / 2
        for (re in BuddyReaction.entries) {
            assertTrue(BuddyFX.count(re) <= BuddyFX.MAX_PARTICLES)
            for ((w, h) in listOf(34.0 to 30.0, 34.0 to 40.0, 34.0 to 46.0, 120.0 to 96.0)) {
                for (i in 0 until BuddyFX.count(re)) {
                    val p = BuddyFX.particle(re, i, w, h)
                    for ((x, y) in listOf(p.x0 to p.y0, p.x1 to p.y1))
                        assertTrue("$re $w×$h #$i $p", x - rad >= 0 && x + rad <= w && y - rad >= 0 && y + rad <= h)
                }
                BuddyFX.badge(re, w, h)?.let { b -> assertTrue("$re $b", b.x >= 0 && b.y >= 0 && b.x + b.w <= w && b.maxY <= h) }
            }
        }
        assertTrue(BuddyFX.MAX_PARTICLES <= 8)
        assertTrue(BuddyFX.count(BuddyReaction.LOVE) + BuddyFX.count(BuddyReaction.PANIC) <= 8)
        val p = BuddyFX.particle(BuddyReaction.LOVE, 3, 34.0, 40.0)
        assertEquals(22.4, p.x1, 0.01); assertEquals(3.5, p.y1, 0.01)   // = iOS
    }

    // MARK: mùa lễ

    @Test fun seasonResolution() {
        assertEquals(BuddySeason.TET, BuddySeason.ofDate(2026, 2, 17))
        assertEquals(BuddySeason.TET, BuddySeason.ofDate(2026, 2, 7))
        assertNull(BuddySeason.ofDate(2026, 2, 6))
        assertEquals(BuddySeason.TET, BuddySeason.ofDate(2026, 2, 24))
        assertNull(BuddySeason.ofDate(2026, 2, 25))
        assertEquals(BuddySeason.TET, BuddySeason.ofDate(2028, 1, 16))
        assertEquals(BuddySeason.MID_AUTUMN, BuddySeason.ofDate(2026, 9, 25))
        assertEquals(BuddySeason.MID_AUTUMN, BuddySeason.ofDate(2026, 9, 20))
        assertNull(BuddySeason.ofDate(2026, 9, 19))
        assertEquals(BuddySeason.MID_AUTUMN, BuddySeason.ofDate(2028, 10, 8))
        assertEquals(BuddySeason.CHRISTMAS, BuddySeason.ofDate(2026, 12, 15))
        assertEquals(BuddySeason.CHRISTMAS, BuddySeason.ofDate(2026, 12, 26))
        assertNull(BuddySeason.ofDate(2026, 12, 27))
        assertEquals(BuddySeason.HALLOWEEN, BuddySeason.ofDate(2026, 10, 25))
        assertEquals(BuddySeason.HALLOWEEN, BuddySeason.ofDate(2026, 11, 1))
        assertNull(BuddySeason.ofDate(2026, 11, 2))
        assertNull(BuddySeason.ofDate(2026, 7, 1))
        assertEquals(10, BuddySeason.LUNAR_NEW_YEAR.size); assertEquals(10, BuddySeason.MID_AUTUMN_DAY.size)
        assertEquals(0, BuddySeason.dayNumber(1970, 1, 1)); assertEquals(20745, BuddySeason.dayNumber(2026, 10, 19))
    }

    @Test fun outfitByThemeThenDate() {
        assertEquals(BuddySeason.TET, BuddySeason.resolve("tetMai", 2026, 7, 1))
        assertEquals(BuddySeason.CHRISTMAS, BuddySeason.resolve("xmasSnow", 2026, 2, 17))
        assertEquals(BuddySeason.HALLOWEEN, BuddySeason.resolve("halloween", 2026, 7, 1))
        assertEquals(BuddySeason.MID_AUTUMN, BuddySeason.resolve("trungthu", 2026, 7, 1))
        assertEquals(BuddySeason.CHRISTMAS, BuddySeason.resolve("system", 2026, 12, 20))
        assertNull(BuddySeason.resolve("oled", 2026, 7, 1))
        // id theme trùng KeyboardTheme.
        for (id in listOf("tet", "tetMai", "xmas", "xmasSnow", "halloween", "trungthu"))
            assertTrue(id, KeyboardTheme.entries.any { it.id == id })
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF }) {
            assertTrue(BuddyOutfit.make(null, c).pieces.isEmpty())
            for (s in BuddySeason.entries.take(4)) { val o = BuddyOutfit.make(s, c); assertFalse("$c $s", o.pieces.isEmpty() && o.recolor.isEmpty()) }
        }
        assertEquals(BuddyOutfit.RED, BuddyOutfit.make(BuddySeason.TET, BuddyCharacter.GIRL).recolor[0xFFB3C7])
        assertTrue(BuddyOutfit.make(BuddySeason.MID_AUTUMN, BuddyCharacter.BOY).pieces.filter { it.part != BuddyPart.SLEEP }.all { it.part == BuddyPart.ARM_R })
    }

    // MARK: driver (logic view Android)

    @Test fun driverZeroFramesWhenAsleep() {
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF }) {
            val d = BuddyDriver(BuddyRig.rig(c)!!)
            var t = 100.0
            d.update(t)
            assertFalse("$c mới hiện: ngủ yên", d.animating(t))
            assertNull(d.poseAt(t, BuddyPose()))
            repeat(20) { t += 0.1; d.keyPressed(t) }
            assertTrue(d.update(t))
            assertTrue(d.shown is BuddyPhase.Dancing)
            assertTrue(d.animating(t))
            assertNotNull(d.poseAt(t, BuddyPose()))
            t += 1; d.update(t)
            assertSame(BuddyPhase.Idle, d.shown)
            assertTrue("$c lắc nhẹ", d.animating(t + BuddyDance.BLEND + 0.01))
            assertNotNull(d.poseAt(t, BuddyPose()))
            t += 8; d.update(t)
            assertSame(BuddyPhase.Asleep.ZZZ, d.shown)
            assertTrue(d.animating(t))
            t += 2.1; d.update(t)
            assertSame(BuddyPhase.Asleep.QUIET, d.shown)
            assertFalse("$c ngủ yên ⇒ 0 khung hình", d.animating(t))
            assertNull(d.nextDeadline(t))
        }
    }

    @Test fun driverLowPowerNeverAnimates() {
        val d = BuddyDriver(BuddyRig.GIRL, lowPower = true)
        var t = 0.0
        repeat(30) { t += 0.08; d.keyPressed(t); d.update(t); assertFalse(d.animating(t)) }
        assertSame(BuddyPhase.Awake, d.shown)
        d.wordCommitted("yêu", null, null, t); d.update(t)
        assertSame(BuddyPhase.Awake, d.shown)
        t += 9; d.update(t)
        assertSame(BuddyPhase.Asleep.QUIET, d.shown)
        assertFalse(d.animating(t))
    }

    /** Nối mượt: đổi bậc không nhảy dáng (sai khác giữa hai khung liền nhau nhỏ). */
    @Test fun driverTierChangeIsContinuous() {
        val d = BuddyDriver(BuddyRig.CAT)
        var t = 0.0
        val a = BuddyPose(); val b = BuddyPose()
        var prevTier = -1
        repeat(60) {
            t += 0.1; d.keyPressed(t)
            d.poseAt(t - 1e-4, a)
            val changed = d.update(t)
            val tier = (d.shown as? BuddyPhase.Dancing)?.tier ?: -1
            if (changed && prevTier >= 0 && tier != prevTier) {
                d.poseAt(t, b)
                assertEquals("armL liền mạch khi đổi bậc $prevTier→$tier", a.armL, b.armL, 0.05)
                assertEquals(a.dy, b.dy, 0.5)
            }
            prevTier = tier
        }
        assertEquals(3, prevTier)
    }

    @Test fun driverReactionRestartWakeReturn() {
        val d = BuddyDriver(BuddyRig.CHICK)
        var t = 50.0
        assertFalse(d.wordCommitted("bàn", null, null, t))
        assertTrue(d.wordCommitted("yêu", null, null, t))
        assertTrue(d.update(t))
        assertSame(BuddyPhase.React.of(BuddyReaction.LOVE), d.shown)
        t += 0.3
        assertTrue(d.wordCommitted("yêu", null, null, t))
        assertTrue("diễn lại từ đầu", d.update(t))
        assertEquals(t, d.phaseStart, 1e-9)
        t += 1.3; d.update(t)
        assertSame("ngủ tiếp", BuddyPhase.Asleep.QUIET, d.shown)
        assertFalse(d.animating(t))
    }

    /** 500 phím: đường phím (ghi giờ + so trạng thái) KHÔNG cấp phát; chi phí mỗi phím. */
    @Test fun burstOf500KeysNoAllocationAndCost() {
        val d = BuddyDriver(BuddyRig.BOY)
        val bean = ManagementFactory.getThreadMXBean() as com.sun.management.ThreadMXBean
        val tid = Thread.currentThread().id
        var t = 0.0
        // làm nóng (JIT, class load)
        repeat(2000) { i -> t += if (i % 50 < 40) 0.07 else 0.35; d.keyPressed(t); d.needsUpdate(t) }
        val a0 = bean.getThreadAllocatedBytes(tid)
        val n0 = System.nanoTime()
        repeat(500) { i ->
            t += if (i % 50 < 40) 0.07 else 0.35
            if (i % 9 == 0) d.deletePressed(t) else d.keyPressed(t)
            d.needsUpdate(t)
        }
        val ns = (System.nanoTime() - n0) / 500.0
        val bytes = bean.getThreadAllocatedBytes(tid) - a0
        // Lượt áp + dáng mỗi khung hình (view) — tái dùng BuddyPose, không cấp phát.
        val pose = BuddyPose()
        repeat(500) { t += 0.016; d.update(t); d.poseAt(t, pose) }
        val a1 = bean.getThreadAllocatedBytes(tid)
        val n1 = System.nanoTime()
        repeat(500) { i -> t += 0.016; if (i % 20 == 0) d.keyPressed(t); d.update(t); d.poseAt(t, pose) }
        val frameNs = (System.nanoTime() - n1) / 500.0
        val frameBytes = bean.getThreadAllocatedBytes(tid) - a1
        println(String.format(Locale.US, "BUDDY android keyPressed+needsUpdate=%.4f ms/phím (%d byte / 500 phím) | update+pose=%.4f ms/khung (%d byte / 500 khung)",
            ns / 1e6, bytes, frameNs / 1e6, frameBytes))
        assertTrue("cấp phát trên đường phím: $bytes byte", bytes < 1024)
        assertTrue("cấp phát mỗi khung: $frameBytes byte", frameBytes < 4096)
        assertTrue("chi phí mỗi phím ${ns / 1e6} ms", ns / 1e6 < 0.1)
    }

    // MARK: tương phản (Phil: chân mảnh lẫn vào nền tối)

    /** Mọi theme dựng sẵn (sáng + tối): quầng tương phản ≥ 3:1 với nền thanh. */
    @Test fun haloContrastOnEveryTheme() {
        for (t in KeyboardTheme.entries) for (dark in listOf(false, true)) {
            val raw = t.palette(dark)?.bg ?: (if (dark) BuddyHalo.SYSTEM_DARK else BuddyHalo.SYSTEM_LIGHT) or (0xFF shl 24)
            val bar = BuddyHalo.opaque(raw, dark)
            val tones = BuddyHalo.colors(bar)
            val c = BuddyHalo.contrast(tones.halo, bar)
            assertTrue("${t.id} ${if (dark) "tối" else "sáng"}: ${Integer.toHexString(tones.halo)} / ${Integer.toHexString(bar)} = $c", c >= 3)
        }
        assertEquals(BuddyHalo.LIGHT, BuddyHalo.colors(0x000000).halo)
        assertEquals(BuddyHalo.DARK, BuddyHalo.colors(0xFFFFFF).halo)
        assertEquals(0x3A2A2A, BuddyHalo.colors(0xFFFFFF).outline)
        assertEquals(0x808080, BuddyHalo.opaque(0x00808080, false).let { BuddyHalo.opaque(0xFF808080.toInt(), false) })
    }

    /** = iOS testLimbsAreFilledAndThickEnough: chi là hình tô (viền + ruột màu), ≥ 2,5 dp ở cỡ thanh ~38 dp. */
    @Test fun limbsAreFilledAndThickEnough() {
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF }) {
            val r = BuddyRig.rig(c)!!
            val pt = 38 / r.full.h
            for (part in listOf(BuddyPart.LEG_L, BuddyPart.LEG_R, BuddyPart.ARM_L, BuddyPart.ARM_R)) {
                val ps = r.pieces.filter { it.part == part }
                for (p in ps) if (p.fill == null && p.stroke === Stroke.Outline) {
                    val d = (p.shape as? Shape.Path)?.d ?: continue
                    assertTrue("$c $part: nét đậm trơn $d", ps.any { q -> (q.shape as? Shape.Path)?.d == d && q.stroke is Stroke.Color })
                }
                var thick = 0.0
                for (p in ps) {
                    if (p.fill == null) thick = max(thick, p.width)
                    else (p.shape as? Shape.Path)?.let { sh ->
                        val n = BuddySVG.numbers(sh.d)
                        val xs = n.filterIndexed { i, _ -> i % 2 == 0 }; val ys = n.filterIndexed { i, _ -> i % 2 == 1 }
                        if (ys.max() - ys.min() > 30) thick = max(thick, min(xs.max() - xs.min(), ys.max() - ys.min()) * 0.6)
                    }
                }
                assertTrue("$c $part: ${thick * pt} dp", thick * pt >= 2.5)
            }
        }
    }

    @Test fun holidayNamesWorkYearRoundAndFold() {
        val cases = listOf(
            "lì xì" to BuddyReaction.LUCKY_MONEY,
            "mừng tuổi" to BuddyReaction.LUCKY_MONEY,
            "tết" to BuddyReaction.LUCKY_MONEY,
            "năm mới" to BuddyReaction.LUCKY_MONEY,
            "chúc mừng năm mới" to BuddyReaction.LUCKY_MONEY,
            "vạn sự như ý" to BuddyReaction.LUCKY_MONEY,
            "happy new year" to BuddyReaction.LUCKY_MONEY,
            "giáng sinh" to BuddyReaction.GIFT,
            "noel" to BuddyReaction.GIFT,
            "merry christmas" to BuddyReaction.GIFT,
            "xmas" to BuddyReaction.GIFT,
            "ông già noel" to BuddyReaction.GIFT,
            "halloween" to BuddyReaction.CANDY,
            "trick or treat" to BuddyReaction.CANDY,
            "trung thu" to BuddyReaction.MOONCAKE,
            "bánh trung thu" to BuddyReaction.MOONCAKE,
            "rước đèn" to BuddyReaction.MOONCAKE,
            "đèn ông sao" to BuddyReaction.MOONCAKE,
            "chị hằng" to BuddyReaction.MOONCAKE,
        )
        for ((phrase, reaction) in cases) for (text in listOf(phrase, BuddyWords.fold(phrase).uppercase())) {
            val tokens = text.split(" ").reversed()
            assertEquals(text, reaction, BuddyWords.reaction(tokens[0] + "!", tokens.getOrNull(1), tokens.getOrNull(2), tokens.getOrNull(3)))
        }
        assertNull(BuddyWords.holiday("ý", "như", "sự"))
        assertNull(BuddyWords.holiday("christmas", null))
        assertNull(BuddyWords.holiday("noelish", null))
        assertNull(BuddyWords.holiday("", "noel"))
    }

    @Test fun holidayGenericSeasonGatesAndAccents() {
        data class Case(val phrase: String, val season: BuddySeason, val reaction: BuddyReaction, val strict: Boolean)
        val cases = listOf(
            Case("quà", BuddySeason.CHRISTMAS, BuddyReaction.GIFT, true),
            Case("kẹo", BuddySeason.HALLOWEEN, BuddyReaction.CANDY, true),
            Case("bí ngô", BuddySeason.HALLOWEEN, BuddyReaction.CANDY, false),
            Case("cuội", BuddySeason.MID_AUTUMN, BuddyReaction.MOONCAKE, true),
            Case("an khang", BuddySeason.TET, BuddyReaction.LUCKY_MONEY, false),
            Case("phát tài", BuddySeason.TET, BuddyReaction.LUCKY_MONEY, false),
        )
        for ((phrase, active, reaction, strict) in cases) {
            val tokens = phrase.split(" ").reversed(); val word = tokens[0]; val prev = tokens.getOrNull(1)
            assertNull(BuddyWords.holiday(word, prev))
            for (season in BuddySeason.entries) assertEquals(if (season == active) reaction else null, BuddyWords.holiday(word, prev, season = season))
            assertEquals(if (strict) null else reaction, BuddyWords.holiday(BuddyWords.fold(word), prev?.let(BuddyWords::fold), season = active))
        }
        assertNull(BuddyWords.reaction("qua", null, season = BuddySeason.CHRISTMAS))
        assertNull(BuddyWords.reaction("keo", null, season = BuddySeason.HALLOWEEN))
        assertEquals(BuddyReaction.GIFT, BuddyWords.reaction("noelll", null))
    }

    @Test fun accessoriesHaveSmallBudgetsAndBothPoses() {
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF }) {
            for (season in BuddySeason.entries.take(4)) {
                val outfit = BuddyOutfit.make(season, c)
                for (sleeping in listOf(false, true)) {
                    val pieces = outfit.pieces.filter { (it.part == BuddyPart.SLEEP) == sleeping }
                    assertTrue(pieces.isNotEmpty()); assertTrue(pieces.size <= 8)
                    assertTrue(pieces.all { it.width <= 3.2 })
                }
            }
            for (reaction in BuddyReaction.entries.filter { it.isHoliday }) {
                val pieces = BuddyProp.make(reaction, BuddyRig.rig(c)!!)
                assertTrue(pieces.isNotEmpty()); assertTrue(pieces.size <= 8)
                assertTrue(pieces.all { (it.part == BuddyPart.BODY || reaction == BuddyReaction.LION_DANCE && it.part == BuddyPart.HEAD) && it.width <= 3.2 })
                assertEquals(1.5, reaction.duration, 0.0); assertEquals(if (reaction == BuddyReaction.BOUQUET || reaction == BuddyReaction.ROSE) 4 else 0, BuddyFX.count(reaction))
            }
            assertTrue(BuddyProp.make(BuddyReaction.LOVE, BuddyRig.rig(c)!!).isEmpty())
        }
    }

    @Test fun namedMovesNeutralAndSelection() {
        for (c in BuddyCharacter.entries.filter { it != BuddyCharacter.OFF }) {
            val style = BuddyRig.rig(c)!!.style
            for (tier in 0..3) {
                for (move in BuddyDance.Move.entries) {
                    assertTrue(BuddyDance.pose(style, tier, 0.0, move = move).isRest())
                    assertTrue(BuddyDance.pose(style, tier, 1.0, move = move).isRest())
                    if (tier < 3 || move != BuddyDance.Move.SPIN)
                        assertTrue((0 until 48).all { BuddyDance.pose(style, tier, it/48.0, move = move).sx == 1.0 })
                }
                val pool = BuddyDance.moves(tier)
                assertEquals(if (tier == 3) 8 else if (tier == 2) 6 else 4, pool.size)
                assertEquals(tier == 3, pool.contains(BuddyDance.Move.SPIN))
                assertEquals(tier >= 2, pool.contains(BuddyDance.Move.SKIP))
                assertEquals(tier < 2, pool.contains(BuddyDance.Move.BOUNCE))
                for (seed in listOf(0, 1, 42, -7, Int.MAX_VALUE)) for (group in 0 until 100) {
                    val a = BuddyDance.move(c, tier, group * 2, seed)
                    assertTrue((if (c == BuddyCharacter.KOI || c == BuddyCharacter.EAGLE)
                        listOf(BuddyDance.Move.WAVE, BuddyDance.Move.CHICKEN, BuddyDance.Move.BOUNCE, BuddyDance.Move.CLAP, BuddyDance.Move.SKIP, BuddyDance.Move.SPIN, BuddyDance.Move.DAB, BuddyDance.Move.ROBOT, BuddyDance.Move.FAN_SHAKE, BuddyDance.Move.FLOSS)
                        else if (c == BuddyCharacter.ROBOT && tier >= 2) listOf(BuddyDance.Move.ROBOT, BuddyDance.Move.FAN_SHAKE, BuddyDance.Move.FLOSS, BuddyDance.Move.WAVE) else pool).contains(a))
                    assertEquals(a, BuddyDance.move(c, tier, group * 2 + 1, seed))
                    assertNotEquals(a, BuddyDance.move(c, tier, (group + 1) * 2, seed))
                }
            }
        }
        for (move in listOf(BuddyDance.Move.ROBOT, BuddyDance.Move.FAN_SHAKE, BuddyDance.Move.FLOSS))
            assertTrue((0 until 80).any { BuddyDance.move(BuddyCharacter.GIRL, 3, it * 2, 42) == move })
        val normalFans = (0 until 56).count { BuddyDance.move(BuddyCharacter.GIRL, 3, it * 2, 42) == BuddyDance.Move.FAN_SHAKE }
        val tetFans = (0 until 56).count { BuddyDance.move(BuddyCharacter.GIRL, 3, it * 2, 42, BuddySeason.TET) == BuddyDance.Move.FAN_SHAKE }
        assertTrue(tetFans > normalFans)
        assertEquals(listOf(BuddyDance.Move.WAVE, BuddyDance.Move.WAVE, BuddyDance.Move.FLOSS, BuddyDance.Move.FLOSS,
            BuddyDance.Move.ROBOT, BuddyDance.Move.ROBOT, BuddyDance.Move.FAN_SHAKE, BuddyDance.Move.FAN_SHAKE,
            BuddyDance.Move.ROBOT, BuddyDance.Move.ROBOT),
            (0 until 10).map { BuddyDance.move(BuddyCharacter.ROBOT, 3, it, 42) })
        assertTrue((0 until 40).count { BuddyDance.move(BuddyCharacter.ROBOT, 3, it * 2, 42) == BuddyDance.Move.ROBOT } >= 12)
        for (c in listOf(BuddyCharacter.GIRL, BuddyCharacter.ROBOT, BuddyCharacter.KOI, BuddyCharacter.EAGLE)) {
            val style = BuddyRig.rig(c)!!.style
            for (move in listOf(BuddyDance.Move.ROBOT, BuddyDance.Move.FAN_SHAKE, BuddyDance.Move.FLOSS))
                for (frame in 0 until 48) {
                    val p = BuddyDance.pose(style, 3, frame / 48.0, move = move, character = c)
                    assertTrue(kotlin.math.abs(p.dx) <= 12 && kotlin.math.abs(p.dy) <= 16)
                    assertTrue(kotlin.math.abs(p.head) <= 0.3 && kotlin.math.abs(p.armL) <= 2.1 && kotlin.math.abs(p.armR) <= 2.1)
                }
        }
    }

    @Test fun roundFiveHolidays() {
        assertEquals(BuddySeason.WOMENS_DAY, BuddySeason.ofDate(2027, 3, 8))
        assertEquals(BuddySeason.VIETNAMESE_WOMENS_DAY, BuddySeason.ofDate(2027, 10, 20))
        assertEquals(BuddySeason.VALENTINE, BuddySeason.ofDate(2027, 2, 14))
        assertEquals(BuddySeason.CHILDRENS_DAY, BuddySeason.ofDate(2027, 6, 1))
        assertEquals(BuddyReaction.TET_WISH, BuddyWords.reaction("mới", "năm", "mừng", "chúc", BuddySeason.TET))
        assertEquals(BuddyReaction.LION_DANCE, BuddyWords.reaction("🦁", null, season = BuddySeason.TET))
        assertEquals(BuddyReaction.BOUQUET, BuddyWords.reaction("💐", null, season = BuddySeason.WOMENS_DAY))
        assertEquals(BuddyReaction.BANH_CHUNG, BuddyWords.reaction("chưng", "bánh", season = BuddySeason.TET))
        assertEquals(BuddyReaction.MOON_GAZE, BuddyWords.reaction("🌕", null, season = BuddySeason.MID_AUTUMN))
        assertEquals(null, BuddyWords.reaction("🌕", null, season = null))
        assertEquals(BuddyReaction.BELL, BuddyWords.reaction("noel", null, season = BuddySeason.CHRISTMAS))
        assertEquals(BuddyReaction.BOO, BuddyWords.reaction("ma", null, season = BuddySeason.HALLOWEEN))
        assertEquals(null, BuddyWords.reaction("👻", null, season = null))
        assertEquals(null, BuddyWords.newHoliday("ma", null, null, null, null))
        assertEquals(BuddyReaction.ROSE, BuddyWords.reaction("valentine", null, season = BuddySeason.VALENTINE))
        assertTrue(BuddyHolidayClock.fireworks(2027, 2, 6, 0, 15))
        assertTrue(!BuddyHolidayClock.fireworks(2027, 2, 6, 0, 16))
        assertEquals(3, BuddyHolidayClock.countdown(12, 31, 23, 59, 57))
        assertEquals(null, BuddyHolidayClock.countdown(1, 1, 23, 59, 57))
        assertEquals(BuddySignature.BEEP, BuddySignature.cheer(BuddyCharacter.ROBOT, 0))
        for (word in listOf("🤖", "⚙️", "🔋")) assertEquals(BuddySignature.BEEP, BuddySignature.word(BuddyCharacter.ROBOT, word))
    }

    @Test fun namedMovePoseParity() {
        val expected = listOf(
            listOf(5.656854, -9.000000, -0.100000, -0.120000, 2.000000, -2.600000, 0.000000, -0.600000, 0.000000, 1.000000), // bounce p=0.375
            listOf(-5.656854, -9.000000, -0.100000, -0.120000, 2.000000, -2.600000, 0.000000, -0.600000, 0.000000, 1.000000), // bounce p=0.875
            listOf(5.656854, 0.000000, 0.127279, -0.070711, -0.450000, 0.450000, 0.000000, 0.000000, 0.000000, 1.000000), // hipSway p=0.375
            listOf(-5.656854, 0.000000, -0.127279, 0.070711, -0.450000, 0.450000, 0.000000, 0.000000, 0.000000, 1.000000), // hipSway p=0.875
            listOf(0.000000, -3.150000, 0.000000, 0.084853, 0.250000, -2.100000, 0.000000, 0.000000, 0.000000, 1.000000), // wave p=0.375
            listOf(0.000000, -3.150000, 0.000000, -0.084853, 0.250000, -2.100000, 0.000000, 0.000000, 0.000000, 1.000000), // wave p=0.875
            listOf(0.000000, -2.250000, 0.000000, 0.080000, -1.050000, 1.050000, 0.000000, 0.000000, 0.000000, 1.000000), // clap p=0.375
            listOf(0.000000, -2.250000, 0.000000, 0.080000, -1.050000, 1.050000, 0.000000, 0.000000, 0.000000, 1.000000), // clap p=0.875
            listOf(0.000000, -2.700000, -0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 1.000000), // dab p=0.375
            listOf(0.000000, -2.700000, -0.180000, 0.650000, 2.500000, 0.900000, 0.000000, 0.000000, 0.000000, 1.000000), // dab p=0.875
            listOf(3.394113, -13.500000, 0.056569, 0.000000, 0.424264, 0.424264, 0.636396, -0.000000, 0.000000, 1.000000), // skip p=0.375
            listOf(-3.394113, -13.500000, -0.056569, 0.000000, -0.424264, -0.424264, 0.000000, -0.636396, 0.000000, 1.000000), // skip p=0.875
            listOf(-5.656854, 0.000000, -0.098995, 0.084853, 0.601041, 0.601041, 0.000000, 0.000000, 0.000000, 1.000000), // flossLite p=0.375
            listOf(5.656854, 0.000000, 0.098995, -0.084853, -0.601041, -0.601041, 0.000000, 0.000000, 0.000000, 1.000000), // flossLite p=0.875
            listOf(5.656854, -9.000000, -0.100000, -0.120000, 2.000000, -2.600000, 0.000000, -0.600000, 0.000000, 1.000000), // spin p=0.375
            listOf(-5.656854, -9.000000, -0.100000, -0.120000, 2.000000, -2.600000, 0.000000, -0.600000, 0.000000, -1.000000), // spin p=0.875
            listOf(0.000000, -5.850000, 0.000000, 0.250000, 0.900000, -0.900000, 0.000000, 0.000000, 0.000000, 1.000000), // chicken p=0.375
            listOf(0.000000, -5.850000, 0.000000, 0.250000, 0.900000, -0.900000, 0.000000, 0.000000, 0.000000, 1.000000), // chicken p=0.875
        )
        for ((i, move) in BuddyDance.Move.entries.take(9).withIndex()) for ((j, phase) in listOf(0.375, 0.875).withIndex()) {
            val p = BuddyDance.pose(BuddyRig.GIRL.style, 3, phase, move = move)
            val values = listOf(p.dx, p.dy, p.rot, p.head, p.armL, p.armR, p.legL, p.legR, p.tail, p.sx)
            for ((a, b) in values.zip(expected[i * 2 + j])) assertEquals(b, a, 1e-6)
        }
    }
}
