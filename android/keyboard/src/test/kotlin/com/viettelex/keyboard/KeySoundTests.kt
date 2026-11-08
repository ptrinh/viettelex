package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

/** Âm thanh phím riêng (28/09/2026) — giống iOS KeySoundTests. */
class KeySoundTests {
    @Test fun settingDefaultsAndClamp() {
        val d = KeyboardSettings()
        assertFalse(d.keySound)
        assertEquals(50, d.keySoundVolume)
        assertEquals("subtle", d.keySoundStyle)
        val s = KeyboardSettings.load { when (it) { Keys.KEY_SOUND -> true; Keys.KEY_SOUND_VOLUME -> 250; Keys.KEY_SOUND_STYLE -> "wood"; else -> null } }
        assertTrue(s.keySound)
        assertEquals(100, s.keySoundVolume)
        assertEquals("wood", s.keySoundStyle)
        assertEquals(0, KeyboardSettings.load { if (it == Keys.KEY_SOUND_VOLUME) -3 else null }.keySoundVolume)
        assertEquals("subtle", KeyboardSettings.load { if (it == Keys.KEY_SOUND_STYLE) "loud" else null }.keySoundStyle)
        assertEquals("system", KeyboardSettings.load { if (it == Keys.KEY_SOUND_STYLE) "system" else null }.keySoundStyle)
        assertEquals("pop", KeyboardSettings.load { if (it == Keys.KEY_SOUND_STYLE) "pop" else null }.keySoundStyle)
    }

    /** TẮT ⇒ tiếng hệ thống; BẬT ⇒ tiếng riêng (không kèm hệ thống); Rung/Im lặng hoặc 0 % ⇒ im. */
    @Test fun routeOffSystemOnCustom() {
        assertEquals(KeySoundSynth.Route.SYSTEM, KeySoundSynth.route(false, 50, true))
        assertEquals(KeySoundSynth.Route.SYSTEM, KeySoundSynth.route(false, 50, false))
        assertEquals(KeySoundSynth.Route.CUSTOM, KeySoundSynth.route(true, 50, true))
        assertEquals(KeySoundSynth.Route.SILENT, KeySoundSynth.route(true, 50, false))
        assertEquals(KeySoundSynth.Route.SILENT, KeySoundSynth.route(true, 0, true))
        // Kiểu "Hệ thống" (19/10/2026) ⇒ như TẮT: playSoundEffect (hệ thống tự theo Rung/Im lặng).
        assertEquals(KeySoundSynth.Route.SYSTEM, KeySoundSynth.route(true, 50, true, "system"))
        assertEquals(KeySoundSynth.Route.SYSTEM, KeySoundSynth.route(true, 0, false, "system"))
        assertEquals(KeySoundSynth.Route.CUSTOM, KeySoundSynth.route(true, 50, true, "rock"))
        assertEquals(KeySoundSynth.Route.CUSTOM, KeySoundSynth.route(true, 50, true, "loud"))   // lạ ⇒ mặc định
    }

    /** Trang "Âm thanh gõ": "Hệ thống" đầu, "Âm của bạn" cuối, mỗi kiểu đúng một lần; chỉ "Hệ thống" không SoundPool. */
    @Test fun menuOrderAndSystemStyle() {
        assertEquals(KeySoundStyle.SYSTEM, KeySoundStyle.MENU_ORDER.first())
        assertEquals(KeySoundStyle.CUSTOM, KeySoundStyle.MENU_ORDER.last())
        assertEquals(KeySoundStyle.entries.toSet(), KeySoundStyle.MENU_ORDER.toSet())
        assertEquals(KeySoundStyle.entries.size, KeySoundStyle.MENU_ORDER.size)
        assertEquals("bật công tắc ⇒ Nhẹ nhàng", KeySoundStyle.SUBTLE, KeySoundStyle.DEFAULT)
        for (st in KeySoundStyle.entries) assertEquals("$st", st != KeySoundStyle.SYSTEM, st.usesPool)
        assertFalse(KeySoundStyle.needsPool("system"))
        assertTrue(KeySoundStyle.needsPool("water"))
        assertTrue(KeySoundStyle.needsPool(null))
        assertTrue(KeySoundStyle.needsPool("xyz"))
        assertFalse(KeySoundStyle.SYSTEM in KeySoundStyle.PRESETS)
        assertFalse(KeySoundStyle.CUSTOM in KeySoundStyle.PRESETS)
        // ordinal = seed nhiễu: kiểu cũ giữ vị trí; id + thứ tự Y HỆT iOS allCases.
        assertEquals(listOf("subtle", "wood", "mechanical", "typewriter", "bubble", "custom", "system", "rock", "pop", "water", "vintage",
            "phao", "jingle", "piano", "dantranh", "scifi", "trong", "boo", "guitar", "bop", "chip", "ai", "club", "dream", "airy"),
            KeySoundStyle.entries.map { it.id })
        for (id in listOf("system", "rock", "pop", "water", "vintage", "phao", "jingle", "piano", "dantranh", "trong", "boo", "guitar")) assertTrue(id, id in KeySoundStyle.IDS)
        for (st in KeySoundStyle.entries) assertNotNull("$st thiếu bản EN", L10nTable.EN[st.viTitle])
        assertNotNull(L10nTable.EN["Âm thanh gõ"])
    }

    /** Nghe thử khi chọn kiểu: chữ + lặng + xoá + lặng + chức năng (giống iOS testPreviewSequence). */
    @Test fun previewSequence() {
        val bank = KeySoundSynth.Kind.entries.map { KeySoundSynth.samples(KeySoundStyle.ROCK, it) }
        val gap = Math.round(0.16 * KeySoundSynth.SAMPLE_RATE).toInt()
        val seq = KeySoundSynth.previewSequence(bank)
        assertEquals(bank.sumOf { it.size } + 2 * gap, seq.size)
        assertArrayEquals(bank[0], seq.copyOfRange(0, bank[0].size), 0f)
        val d0 = bank[0].size + gap
        assertArrayEquals(bank[1], seq.copyOfRange(d0, d0 + bank[1].size), 0f)
        assertTrue(seq.copyOfRange(bank[0].size, d0).all { it == 0f })
        assertArrayEquals(bank[2], seq.copyOfRange(seq.size - bank[2].size, seq.size), 0f)
    }

    @Test fun gainCurve() {
        assertEquals(0f, KeySoundSynth.gain(0))
        assertEquals(0.25f, KeySoundSynth.gain(50), 1e-6f)
        assertEquals(1f, KeySoundSynth.gain(100))
        assertEquals(1f, KeySoundSynth.gain(300))
    }

    @Test fun samplesDeterministicNonEmptyDistinct() {
        for (st in KeySoundStyle.PRESETS) {
            val all = KeySoundSynth.Kind.entries.map { k ->
                val a = KeySoundSynth.samples(st, k)
                assertArrayEquals(a, KeySoundSynth.samples(st, k), 0f)
                assertTrue(a.size in 1001..2699)
                assertEquals(KeySoundSynth.baseRecipe(st).peak.toFloat(), a.maxOf { abs(it) }, 1e-4f)
                assertEquals(0f, a.first(), 1e-6f); assertEquals(0f, a.last(), 1e-6f)
                val e = a.sumOf { (it * it).toDouble() }
                val tail = a.copyOfRange(a.size / 2, a.size).sumOf { (it * it).toDouble() }
                assertTrue("$st/$k", tail / e < 0.08)
                a
            }
            assertFalse(all[0].contentEquals(all[1])); assertFalse(all[1].contentEquals(all[2]))
        }
        assertArrayEquals(KeySoundSynth.samples(KeySoundSynth.Kind.LETTER),
            KeySoundSynth.samples(KeySoundStyle.SUBTLE, KeySoundSynth.Kind.LETTER), 0f)
    }

    /** "Không chói" đo được: trọng tâm phổ thấp (bản cũ ~7 kHz), độ to dễ chịu. */
    @Test fun presetsAreSoft() {
        for (st in KeySoundStyle.PRESETS) for (k in KeySoundSynth.Kind.entries) {
            val a = KeySoundSynth.samples(st, k)
            val c = KeySoundSynth.spectralCentroid(a)
            assertTrue("$st/$k centroid $c", c < 2500)
            if (st == KeySoundStyle.SUBTLE) assertTrue("mặc định trầm-êm: $c", c < 1000)
            val r = KeySoundSynth.rms(a)
            assertTrue("$st/$k rms $r", r > 0.05 && r < 0.30)
        }
    }

    /** Checksum chung với iOS (KeySoundTests.swift testCrossPlatformChecksums). */
    @Test fun crossPlatformChecksums() {
        val golden = mapOf(KeySoundStyle.SUBTLE to 169.1699, KeySoundStyle.WOOD to 192.4240,
            KeySoundStyle.MECHANICAL to 239.0849, KeySoundStyle.TYPEWRITER to 139.7659, KeySoundStyle.BUBBLE to 233.6785,
            KeySoundStyle.ROCK to 128.7247, KeySoundStyle.POP to 154.4214, KeySoundStyle.WATER to 246.5762, KeySoundStyle.VINTAGE to 139.9505,
            KeySoundStyle.PHAO to 61.5246, KeySoundStyle.JINGLE to 206.7064, KeySoundStyle.SCIFI to 128.7368,
            KeySoundStyle.TRONG to 229.6778, KeySoundStyle.BOO to 217.1955)
        for ((st, want) in golden) {
            val s = KeySoundSynth.samples(st, KeySoundSynth.Kind.LETTER).sumOf { abs(it).toDouble() }
            assertEquals("$st", want, s, 0.01)
        }
    }

    /** 4 kiểu thêm 19/10/2026: chốt cả xoá + phím chức năng (iOS testCrossPlatformChecksumsNewKinds). */
    @Test fun crossPlatformChecksumsNewKinds() {
        val golden = listOf(Triple(KeySoundStyle.ROCK, 125.7988, 176.4305), Triple(KeySoundStyle.POP, 153.6654, 183.0577),
            Triple(KeySoundStyle.WATER, 236.6294, 280.8465), Triple(KeySoundStyle.VINTAGE, 167.8816, 218.2744),
            Triple(KeySoundStyle.PHAO, 69.1895, 93.5815), Triple(KeySoundStyle.JINGLE, 212.6919, 254.5561),
            Triple(KeySoundStyle.SCIFI, 130.3325, 155.3449),
            Triple(KeySoundStyle.TRONG, 238.2098, 276.1584), Triple(KeySoundStyle.BOO, 217.6732, 252.6338))
        for ((st, del, mod) in golden) {
            assertEquals("$st", del, KeySoundSynth.samples(st, KeySoundSynth.Kind.DELETE).sumOf { abs(it).toDouble() }, 0.01)
            assertEquals("$st", mod, KeySoundSynth.samples(st, KeySoundSynth.Kind.MODIFIER).sumOf { abs(it).toDouble() }, 0.01)
        }
    }

    /** Pháo (Tết) NHỎ hơn: đỉnh + RMS dưới "Gõ gỗ" cả 3 loại phím; Chuông không to hơn (iOS testPhaoQuietJingleModerate). */
    @Test fun phaoQuietJingleModerate() {
        for (k in KeySoundSynth.Kind.entries) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k)
            val phao = KeySoundSynth.samples(KeySoundStyle.PHAO, k)
            val bell = KeySoundSynth.samples(KeySoundStyle.JINGLE, k)
            assertTrue("$k", KeySoundSynth.rms(phao) < KeySoundSynth.rms(wood))
            assertTrue("$k", phao.maxOf { abs(it) } < wood.maxOf { abs(it) })
            assertTrue("$k", KeySoundSynth.rms(bell) <= KeySoundSynth.rms(wood))
            assertTrue("$k", bell.maxOf { abs(it) } <= wood.maxOf { abs(it) })
        }
        assertFalse(KeySoundSynth.samples(KeySoundStyle.PHAO, KeySoundSynth.Kind.LETTER)
            .contentEquals(KeySoundSynth.samples(KeySoundStyle.PHAO, KeySoundSynth.Kind.DELETE)))
    }

    /**
     * Bộ đủ món (theme Vũ trụ / Máy chữ cổ): "Bíp sci-fi" NHỎ (đỉnh + RMS < Gõ gỗ cả 3 loại phím); Enter của Máy chữ =
     * tiếng phím + "ding" (RMS + đỉnh ≤ Gõ gỗ, không chói); kiểu khác không có Enter riêng (iOS testScifiQuietAndTypewriterDing).
     */
    @Test fun scifiQuietAndTypewriterDing() {
        for (k in KeySoundSynth.Kind.entries) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k)
            val sci = KeySoundSynth.samples(KeySoundStyle.SCIFI, k)
            assertTrue("$k", KeySoundSynth.rms(sci) < KeySoundSynth.rms(wood))
            assertTrue("$k", sci.maxOf { abs(it) } < wood.maxOf { abs(it) })
        }
        val ding = KeySoundSynth.returnSamples(KeySoundStyle.TYPEWRITER)!!
        val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, KeySoundSynth.Kind.MODIFIER)
        assertTrue(KeySoundSynth.rms(ding) <= KeySoundSynth.rms(wood))
        assertTrue(ding.maxOf { abs(it) } <= wood.maxOf { abs(it) })
        assertEquals(Math.round(0.28 * KeySoundSynth.SAMPLE_RATE).toInt(), ding.size)
        assertEquals(0f, ding.first(), 1e-6f); assertEquals(0f, ding.last(), 1e-6f)
        assertTrue("ding không chói", KeySoundSynth.spectralCentroid(ding.copyOfRange(0, 4096)) < 2500)
        assertEquals(1168.1703, ding.sumOf { abs(it).toDouble() }, 0.01)
        assertArrayEquals(ding, KeySoundSynth.returnSamples(KeySoundStyle.TYPEWRITER), 0f)
        for (st in KeySoundStyle.entries) if (st != KeySoundStyle.TYPEWRITER) assertNull("$st", KeySoundSynth.returnSamples(st))
    }

    /** Trống lân / Ma quái KHÔNG to hơn "Gõ gỗ" (đỉnh + RMS), trầm êm, ≤ 62 ms (iOS testTrongBooQuietAndShort). */
    @Test fun trongBooQuiet() {
        for (k in KeySoundSynth.Kind.entries) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k)
            for (st in listOf(KeySoundStyle.TRONG, KeySoundStyle.BOO)) {
                val a = KeySoundSynth.samples(st, k)
                assertTrue("$st/$k", KeySoundSynth.rms(a) < KeySoundSynth.rms(wood))
                assertTrue("$st/$k", a.maxOf { abs(it) } < wood.maxOf { abs(it) })
                assertTrue("$st/$k", a.size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.062)
                assertTrue("$st/$k", KeySoundSynth.spectralCentroid(a) < if (st == KeySoundStyle.TRONG) 400.0 else 800.0)
            }
        }
        assertEquals("Lion drum", L10nTable.EN["Trống lân"]); assertEquals("Spooky", L10nTable.EN["Ma quái"])
    }

    /** "Bíp 8-bit" (theme Pixel 8-bit): không to hơn Gõ gỗ, ≤ 55 ms, sáng (sóng vuông); checksum chung iOS testChipBlipQuietShortAndShared. */
    /** "Nhịp club" (theme Neon Night Club): chữ = hi-hat, xoá / chức năng = kick; checksum chung iOS testClubBeatQuietAndShared. */
    @Test fun clubBeat() {
        for (k in KeySoundSynth.Kind.entries) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k); val a = KeySoundSynth.samples(KeySoundStyle.CLUB, k)
            assertTrue("$k", KeySoundSynth.rms(a) < KeySoundSynth.rms(wood))
            assertTrue("$k", a.maxOf { abs(it) } < wood.maxOf { abs(it) })
            assertTrue("$k", a.size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.061)
        }
        val hat = KeySoundSynth.samples(KeySoundStyle.CLUB, KeySoundSynth.Kind.LETTER)
        val kick = KeySoundSynth.samples(KeySoundStyle.CLUB, KeySoundSynth.Kind.DELETE)
        assertTrue(KeySoundSynth.spectralCentroid(hat) > 3 * KeySoundSynth.spectralCentroid(kick))
        assertTrue(KeySoundSynth.spectralCentroid(kick) < 600)
        assertEquals(0x636C7562 xor 0x85EBCA6B.toInt(), KeySoundSynth.seed(KeySoundStyle.CLUB, KeySoundSynth.Kind.LETTER))
        val golden = listOf(47.9893, 207.6961, 231.8860)
        for ((i, k) in KeySoundSynth.Kind.entries.withIndex())
            assertEquals("$k", golden[i], KeySoundSynth.samples(KeySoundStyle.CLUB, k).sumOf { abs(it).toDouble() }, 0.01)
        assertEquals("Club beat", L10nTable.EN["Nhịp club"])
        assertTrue(KeySoundStyle.CLUB in KeySoundStyle.PRESETS)
    }

    @Test fun chipBlip() {
        for (k in KeySoundSynth.Kind.entries) {
            val wood = KeySoundSynth.samples(KeySoundStyle.WOOD, k); val a = KeySoundSynth.samples(KeySoundStyle.CHIP, k)
            assertTrue("$k", KeySoundSynth.rms(a) < KeySoundSynth.rms(wood))
            assertTrue("$k", a.maxOf { abs(it) } < wood.maxOf { abs(it) })
            assertTrue("$k", a.size.toDouble() / KeySoundSynth.SAMPLE_RATE < 0.056)
            assertTrue("$k sóng vuông sáng", KeySoundSynth.spectralCentroid(a) > 1000.0)
        }
        val golden = listOf(214.9587, 213.1522, 237.6303)
        for ((i, k) in KeySoundSynth.Kind.entries.withIndex())
            assertEquals("$k", golden[i], KeySoundSynth.samples(KeySoundStyle.CHIP, k).sumOf { abs(it).toDouble() }, 0.01)
        assertEquals("8-bit blip", L10nTable.EN["Bíp 8-bit"])
        assertTrue(KeySoundStyle.CHIP in KeySoundStyle.PRESETS)
    }

    /** Danh sách id DUY NHẤT cho "sound" của theme JSON (trùng iOS presetIDs); "theme" (đã bỏ) ⇒ mặc định. */
    @Test fun presetIdsForThemeJson() {
        assertEquals(listOf("subtle", "wood", "mechanical", "typewriter", "bubble", "rock", "pop", "water", "vintage",
            "phao", "jingle", "scifi", "trong", "boo", "bop", "chip", "ai", "club", "dream", "airy", "piano", "dantranh", "guitar"), KeySoundStyle.PRESET_IDS)
        for (bad in listOf("system", "custom", "theme")) assertFalse(bad, bad in KeySoundStyle.PRESET_IDS)
        assertEquals(KeySoundStyle.SUBTLE, KeySoundStyle.resolve("theme", true))
        assertEquals("subtle", KeyboardSettings.load { if (it == Keys.KEY_SOUND_STYLE) "theme" else null }.keySoundStyle)
        assertEquals("piano", KeyboardSettings.load { if (it == Keys.KEY_SOUND_STYLE) "piano" else null }.keySoundStyle)
    }

    @Test fun styleResolveAndBankFallback() {
        assertEquals(KeySoundStyle.SUBTLE, KeySoundStyle.resolve(null, true))
        assertEquals(KeySoundStyle.SUBTLE, KeySoundStyle.resolve("xyz", true))
        assertEquals(KeySoundStyle.WOOD, KeySoundStyle.resolve("wood", false))
        assertEquals(KeySoundStyle.SUBTLE, KeySoundStyle.resolve("custom", false))
        assertEquals(KeySoundStyle.CUSTOM, KeySoundStyle.resolve("custom", true))
        assertEquals(KeySoundStyle.SYSTEM, KeySoundStyle.resolve("system", false))
        assertEquals(KeySoundStyle.VINTAGE, KeySoundStyle.resolve("vintage", false))
        val miss = KeySoundSynth.bank("custom", null)
        assertEquals(KeySoundStyle.SUBTLE, miss.first)
        assertArrayEquals(KeySoundSynth.samples(KeySoundStyle.SUBTLE, KeySoundSynth.Kind.LETTER), miss.second[0], 0f)
        val c = floatArrayOf(0f, 0.5f, -0.5f, 0f)
        val hit = KeySoundSynth.bank("custom", c)
        assertEquals(KeySoundStyle.CUSTOM, hit.first)
        assertArrayEquals(c, hit.second[0], 0f)
        val dir = Files.createTempDirectory("ks").toFile()
        try {
            val f = java.io.File(dir, KeySoundCustom.FILE_NAME)
            assertNull(KeySoundCustom.load(f))
            f.writeText("not a wav")
            assertNull(KeySoundCustom.load(f))
            assertEquals("custom", KeySoundCustom.bankKey("custom", java.io.File(dir, "none")))
            assertEquals("wood", KeySoundCustom.bankKey("wood", f))
        } finally { dir.deleteRecursively() }
    }

    @Test fun wavHeaderAndRoundTrip() {
        val w = KeySoundSynth.wav(KeySoundSynth.Kind.LETTER)
        assertEquals("RIFF", String(w, 0, 4)); assertEquals("WAVE", String(w, 8, 4)); assertEquals("data", String(w, 36, 4))
        assertEquals(44 + KeySoundSynth.samples(KeySoundSynth.Kind.LETTER).size * 2, w.size)
        assertArrayEquals(w, KeySoundSynth.wav(KeySoundSynth.Kind.LETTER))
        val s = KeySoundSynth.samples(KeySoundStyle.WOOD, KeySoundSynth.Kind.DELETE)
        val (back, rate) = KeySoundSynth.parseWav(KeySoundSynth.wav(s))!!
        assertEquals(44_100.0, rate, 0.0)
        assertEquals(s.size, back.size)
        for (i in s.indices) assertEquals(s[i], back[i], 1f / 16_000)
        assertNull(KeySoundSynth.parseWav(byteArrayOf(1, 2, 3)))
    }

    /** WAV thử: stereo 16-bit ở [rate], lặng [lead] s rồi sine [tone] s biên độ [amp]. */
    private fun testWav(rate: Int, lead: Double, tone: Double, amp: Double, freq: Double = 440.0): ByteArray {
        val n = ((lead + tone) * rate).toInt()
        val data = n * 4
        val b = ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(2).putInt(rate).putInt(rate * 4).putShort(4).putShort(16)
        b.put("data".toByteArray()).putInt(data)
        for (i in 0 until n) {
            val t = i.toDouble() / rate - lead
            val v = if (t < 0) 0.0 else amp * sin(2 * PI * freq * t)
            val sv = (v.coerceIn(-1.0, 1.0) * 32767).toInt().toShort()
            b.putShort(sv); b.putShort(sv)
        }
        return b.array()
    }

    /** Đường nhập từ file thử (giải mã WAV → process): bỏ lặng, cắt ≤ 300 ms, đỉnh/RMS an toàn. */
    @Test fun customImportTrimsCapsNormalizes() {
        val (mono, rate) = KeySoundSynth.parseWav(testWav(48_000, 0.25, 0.8, 1.0))!!
        val r = KeySoundCustom.process(mono, rate)
        assertTrue(r.truncated)
        val dur = r.samples.size / 44_100.0
        assertTrue("dur $dur", dur <= 0.3 + 1e-3 && dur > 0.29)
        assertTrue(r.samples.maxOf { abs(it) } <= KeySoundCustom.TARGET_PEAK + 1e-3)
        assertTrue(KeySoundSynth.rms(r.samples) <= KeySoundCustom.MAX_RMS + 1e-3)
        assertTrue(r.samples.copyOfRange(0, 220).maxOf { abs(it) } > 0.05f)   // lặng đầu đã bỏ
        assertEquals(0f, r.samples.last(), 1e-3f)
        // Ghi + đọc lại như IME.
        val dir = Files.createTempDirectory("ks").toFile()
        try {
            val f = java.io.File(dir, KeySoundCustom.FILE_NAME)
            f.writeBytes(KeySoundSynth.wav(r.samples))
            val loaded = KeySoundCustom.load(f)
            assertNotNull(loaded)
            assertEquals(r.samples.size, loaded!!.size)
            assertEquals(KeySoundStyle.CUSTOM, KeySoundSynth.bank("custom", loaded).first)
            assertTrue(KeySoundCustom.bankKey("custom", f).startsWith("custom@"))
        } finally { dir.deleteRecursively() }
    }

    @Test fun customImportShortQuietIsBoostedAndSilentRejected() {
        val (mono, rate) = KeySoundSynth.parseWav(testWav(22_050, 0.02, 0.03, 0.05, 300.0))!!
        val r = KeySoundCustom.process(mono, rate)
        assertFalse(r.truncated)
        assertTrue(r.samples.size < 0.06 * 44_100)
        val peak = r.samples.maxOf { abs(it) }
        assertTrue("peak $peak", peak > 0.25f && peak <= KeySoundCustom.TARGET_PEAK + 1e-3f)
        assertEquals(KeySoundCustom.MAX_RMS, KeySoundSynth.rms(r.samples), 0.01)
        val silent = KeySoundSynth.parseWav(testWav(44_100, 0.5, 0.0, 0.0))!!
        assertTrue(runCatching { KeySoundCustom.process(silent.first, silent.second) }.exceptionOrNull() is KeySoundCustom.Failure)
        assertTrue(runCatching { KeySoundCustom.process(FloatArray(0), 44_100.0) }.exceptionOrNull() is KeySoundCustom.Failure)
        assertEquals(44_100, KeySoundCustom.resample(FloatArray(48_000) { 0.5f }, 48_000.0, 44_100.0).size)
    }

    @Test fun previewThrottle() {
        val t = PreviewThrottle(120)
        assertTrue(t.shouldFire(50, 0, false))
        assertFalse(t.shouldFire(55, 50, false))    // quá sớm
        assertTrue(t.shouldFire(55, 130, false))
        assertFalse(t.shouldFire(55, 300, false))   // cùng giá trị khi kéo
        assertFalse(t.shouldFire(55, 200, true))    // vừa phát đúng giá trị này
        assertTrue(t.shouldFire(60, 210, true))     // thả ở giá trị mới ⇒ luôn phát
        assertTrue(t.shouldFire(60, 500, true))     // thả sau lâu ⇒ phát lại
    }

    @Test fun backupRoundTripAndClamp() {
        val snap = BackupPrefs.snapshot({ when (it) { Keys.KEY_SOUND -> true; Keys.KEY_SOUND_VOLUME -> 35; Keys.KEY_SOUND_STYLE -> "bubble"; else -> null } }, emptyList(), null)
        assertEquals(true, snap.settings!![Keys.KEY_SOUND]); assertEquals(35, snap.settings!![Keys.KEY_SOUND_VOLUME])
        assertEquals("bubble", snap.settings!![Keys.KEY_SOUND_STYLE])
        val back = BackupCodec.decode(BackupCodec.encode(snap))
        assertEquals(true, back.settings!![Keys.KEY_SOUND]); assertEquals(35, back.settings!![Keys.KEY_SOUND_VOLUME])
        assertEquals("bubble", back.settings!![Keys.KEY_SOUND_STYLE])
        val raw = """{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"ios","settings":{"keySoundVolume":250,"keySoundStyle":"loud"}}"""
        val dec = BackupCodec.decode(raw).settings!!
        assertEquals(100, dec[Keys.KEY_SOUND_VOLUME])
        assertNull(dec[Keys.KEY_SOUND_STYLE])
        // mặc định khi pref vắng
        val def = BackupPrefs.settings { null }
        assertEquals(false, def[Keys.KEY_SOUND]); assertEquals(50, def[Keys.KEY_SOUND_VOLUME])
        assertEquals("subtle", def[Keys.KEY_SOUND_STYLE])
    }
}
