package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #144: trang "Bạn đồng hành" dựng MỌI nhân vật cùng lúc (ô xem thử) rồi diễn một tràng phím. Phần thuần mà
 * BuddyView (Android) / BuddyView (iOS) chạm tới lúc dựng + vẽ phải không ném lỗi với mọi (nhân vật × mùa × đêm ×
 * khung × phản ứng) — test cũ chỉ phủ 4 mùa đầu.
 */
class BuddyPreviewSmokeTests {
    private fun parseAll(pieces: List<BuddyPiece>) {
        for (p in pieces) (p.shape as? Shape.Path)?.let { BuddySVG.parse(it.d) }
    }

    /** #144: BitmapFactory.Options.inSampleSize mặc định 0 — vòng cũ `max(w, h) / inSampleSize` chia cho 0 ⇒ văng. */
    @Test fun spriteSampleSizeStartsAtOneAndNeverDividesByZero() {
        assertEquals(4, BuddySprites.sampleSize(1536, 1024))   // atlas cô gái / chàng trai / gà con
        assertEquals(4, BuddySprites.sampleSize(1774, 887))    // atlas mèo
        assertEquals(1, BuddySprites.sampleSize(512, 300))
        assertEquals(1, BuddySprites.sampleSize(1, 1))
        assertEquals(2, BuddySprites.sampleSize(513, 10))
        assertNull("bounds không đọc được ⇒ vector", BuddySprites.sampleSize(0, 0))
        assertNull(BuddySprites.sampleSize(-1, 1024))
        for (w in listOf(1, 511, 512, 513, 1024, 4096, 20_000)) {
            val s = BuddySprites.sampleSize(w, w / 2 + 1)!!
            assertTrue(s >= 1 && Integer.bitCount(s) == 1)
            assertTrue("$w / $s", w / s <= BuddySprites.MAX_DECODE_EDGE)
        }
        // Mọi nhân vật có atlas phải có ảnh thật (thiếu ảnh chỉ lùi về vector, nhưng là lỗi đóng gói).
        val assets = java.io.File("../app/src/main/assets")
        if (assets.isDirectory) for (c in BuddyCharacter.entries.filter { BuddyStyle.hasAtlas(it) })
            assertTrue("thiếu ${BuddySprites.atlasAsset(c)}", java.io.File(assets, BuddySprites.atlasAsset(c)).isFile)
    }

    /** PNG IHDR: (rộng, cao). */
    private fun pngSize(f: java.io.File): Pair<Int, Int> {
        val b = f.readBytes()
        fun u32(o: Int) = ((b[o].toInt() and 0xFF) shl 24) or ((b[o + 1].toInt() and 0xFF) shl 16) or
            ((b[o + 2].toInt() and 0xFF) shl 8) or (b[o + 3].toInt() and 0xFF)
        return u32(16) to u32(20)
    }

    /**
     * Audit 10/11/2026: Bạn đồng hành nạp bản 512 px dựng sẵn — CHÍNH tệp iOS (iOS/Scripts/make-buddy-512.swift), hai
     * nền tảng cùng điểm ảnh. Bản gốc 1536 px chỉ còn cho người nhảy Night Club ([NightDancer.character]: cô gái /
     * chàng trai); bản gốc mèo + gà con không ai đọc ⇒ không đóng gói (−3,0 MB APK).
     */
    @Test fun companionShipsPrescaled512AtlasesIdenticalToIos() {
        val assets = java.io.File("../app/src/main/assets")
        if (!assets.isDirectory) return
        val ios = java.io.File("../../iOS/Keyboard/Resources/Buddies")
        for (c in BuddyCharacter.entries.filter { BuddyStyle.hasAtlas(it) }) {
            val f = java.io.File(assets, BuddySprites.atlasAsset(c))
            val (w, h) = pngSize(f)
            assertEquals("${f.name} cạnh dài", BuddySprites.MAX_DECODE_EDGE, maxOf(w, h))
            assertEquals("${f.name} ⇒ giải thẳng", 1, BuddySprites.sampleSize(w, h))
            val twin = java.io.File(ios, f.name)
            if (ios.isDirectory) assertTrue("${f.name} phải byte-y-hệt bản iOS", f.readBytes().contentEquals(twin.readBytes()))
        }
        val dancers = BuddyCharacter.entries.map { NightDancer.character(it) }.toSet()
        assertEquals(setOf(BuddyCharacter.GIRL, BuddyCharacter.BOY), dancers)
        for (c in BuddyCharacter.entries.filter { BuddyStyle.hasAtlas(it) }) {
            val full = java.io.File(assets, "buddy-${c.id}-v2.png")
            if (c in dancers) assertEquals("${full.name}: người nhảy Night Club cần bản gốc", 1536, maxOf(pngSize(full).first, pngSize(full).second))
            else assertFalse("${full.name}: không ai đọc bản gốc ⇒ không đóng gói", full.exists())
        }
    }

    @Test fun everyCharacterSeasonFramingBuildsAndAnimates() {
        val seasons = listOf<BuddySeason?>(null) + BuddySeason.entries
        for (c in BuddyCharacter.RIGGED) {
            val rig = BuddyRig.rig(c) ?: error("$c thiếu rig")
            parseAll(rig.pieces)
            BuddySVG.parse(rig.brows)
            for (f in BuddyFraming.entries) rig.viewport(f)
            for (r in BuddyReaction.entries) parseAll(BuddyProp.make(r, rig))
            for (s in seasons) for (night in listOf(false, true)) for (vector in listOf(false, true)) {
                val outfit = BuddyOutfit.make(s, c, night)
                parseAll(outfit.pieces)
                val d = BuddyDriver(rig)
                d.character = c; d.season = s; d.vectorDance = vector; d.danceSeed = 12345
                d.beginAppearance(777)
                var t = 100.0
                val pose = BuddyPose()
                fun frame() { d.update(t); d.poseAt(t, pose); d.animating(t); d.nextDeadline(t) }
                repeat(24) { d.keyPressed(t); frame(); t += 0.11 }
                while (t < 140.0) { frame(); t += 0.016 }
                for (r in BuddyReaction.entries) { d.react(r, t); repeat(120) { frame(); t += 0.016 } }
                d.cheer(t); repeat(120) { frame(); t += 0.016 }
                for (tier in 0 until BuddyTempo.TIERS) {
                    val frames = BuddySprites.dance(c, tier)
                    frames[BuddySprites.frameIndex(0.99, frames.size)]
                    BuddySprites.duration(c, tier)
                }
            }
        }
    }
}
