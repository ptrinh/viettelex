package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Lõi đồng bộ Drive — vector khớp iOS BackupTests (MARK: LWW merge / mô phỏng 2 máy). */
class CloudSyncTests {
    private fun e(v: String?, t: Long) = SyncEntry(v, t)

    @Test fun mergeIsLastWriterWinsPerKey() {
        val a = mapOf("x" to e("1", 10), "y" to e("a", 50))
        val b = mapOf("x" to e("2", 20), "y" to e(null, 40), "z" to e("z", 1))
        val m = SyncMerge.merge(a, b)
        assertEquals(mapOf("x" to "2", "y" to "a", "z" to "z"), SyncMerge.live(m))
        assertEquals(m, SyncMerge.merge(b, a))              // giao hoán
        assertEquals(m, SyncMerge.merge(m, m))              // luỹ đẳng
    }

    @Test fun tieBreakDeterministic() {
        val a = mapOf("k" to e("false", 5)); val b = mapOf("k" to e("true", 5)); val c = mapOf("k" to e(null, 5))
        assertEquals(SyncMerge.merge(a, b), SyncMerge.merge(b, a))
        assertEquals(mapOf("k" to "false"), SyncMerge.live(SyncMerge.merge(a, c)))   // hoà: giá trị thắng tombstone
    }

    @Test fun stampDetectsEditsAndDeletes() {
        val ledger = mapOf("a" to e("1", 1), "b" to e("2", 1), "c" to e(null, 1))
        val st = SyncMerge.stamp(mapOf("a" to "1", "b" to "3", "d" to "4"), ledger, now = 100)
        assertEquals(e("1", 1), st["a"]); assertEquals(e("3", 100), st["b"])
        assertEquals(e("4", 100), st["d"]); assertEquals(e(null, 1), st["c"])
        assertEquals(e(null, 100), SyncMerge.stamp(emptyMap(), ledger, now = 100)["a"])
    }

    @Test fun firstSyncRemoteWins() {
        val remote = mapOf("a" to e("cloud", 5), "gone" to e(null, 5))
        val st = SyncMerge.stamp(mapOf("a" to "local", "gone" to "x", "new" to "n"), null, remote, now = 100)
        assertEquals(mapOf("a" to "cloud", "new" to "n"), SyncMerge.live(SyncMerge.merge(st, remote)))
    }

    @Test fun tombstonePruning() {
        val d = mapOf("old" to e(null, 0), "new" to e(null, SyncMerge.TOMBSTONE_TTL), "v" to e("1", 0))
        assertEquals(setOf("new", "v"), SyncMerge.pruned(d, SyncMerge.TOMBSTONE_TTL + 1).keys)
    }

    @Test fun fileCodecRoundTrip() {
        val f = SyncFile()
        val d = mapOf("a" to e("1", 1_727_000_000_000), "b" to e(null, 3), "ư\u0001" to e("", 0))
        f.setDomain(SyncSection.SHORTCUTS, d)
        val back = SyncFile.decode(f.encode())
        assertEquals(d, back.domain(SyncSection.SHORTCUTS))
        assertNull(back.domain(SyncSection.SETTINGS))
        assertTrue(f.encode().contains("\"vt.sync.shortcuts\""))      // cùng key với iCloud KVS của iOS
        assertNull(SyncFile.decode(null).domain(SyncSection.SETTINGS))
        assertTrue(runCatching { SyncFile.decode("nope") }.isFailure)
        assertTrue(runCatching { SyncFile.decode("{\"format\":\"viettelex-backup\"}") }.isFailure)
    }

    @Test fun templatesDomainKeepsOrderAndLabels() {
        val items = listOf(TemplateItem("b", "zz"), TemplateItem("", "aa"), TemplateItem("x\u0001y", "mm"))
        assertEquals(items, SyncMerge.templatesFromDomain(SyncMerge.templatesToDomain(items)))
    }

    @Test fun settingsDomainValidatesBySpec() {
        val bool = BackupSettings.all.first { it.kind is SettingKind.Bool }.key
        val int = BackupSettings.all.first { it.kind is SettingKind.IntRange }
        val range = (int.kind as SettingKind.IntRange).range
        val back = SyncMerge.settingsFromDomain(mapOf(bool to "true", int.key to "999999", "unknown" to "x"))
        assertEquals(true, back[bool])
        assertEquals(range.last, back[int.key])                       // kẹp phạm vi
        assertFalse("unknown" in back)
        assertTrue(SyncMerge.settingsFromDomain(mapOf(bool to "yes")).isEmpty())
        assertEquals(mapOf(bool to "false", int.key to "3"), SyncMerge.settingsToDomain(mapOf(bool to false, int.key to 3)))
    }

    // --- mô phỏng 2 máy + một file Drive ---

    private class FakeLocal(var settings: Map<String, String> = emptyMap(), var shortcuts: Map<String, String> = emptyMap(),
                            var templates: Map<String, String> = emptyMap(), var templatesTouched: Boolean = true) : SyncLocal {
        val ledgers = HashMap<SyncSection, SyncDomain>()
        override fun current(s: SyncSection) = when (s) {
            SyncSection.SETTINGS -> settings; SyncSection.SHORTCUTS -> shortcuts; SyncSection.TEMPLATES -> templates
        }
        override fun apply(s: SyncSection, values: Map<String, String>) {
            when (s) { SyncSection.SETTINGS -> settings = values; SyncSection.SHORTCUTS -> shortcuts = values
                SyncSection.TEMPLATES -> { templates = values; templatesTouched = true } }
        }
        override fun ledger(s: SyncSection) = ledgers[s]
        override fun setLedger(s: SyncSection, d: SyncDomain) { ledgers[s] = d }
        override fun isUntouched(s: SyncSection) = s == SyncSection.TEMPLATES && !templatesTouched
    }

    /** Mỗi lượt: tải file (chuỗi) → gộp → ghi lại nếu đổi — đúng đường DriveSync. */
    private fun sync(local: FakeLocal, drive: Array<String?>, now: Long) {
        val f = SyncFile.decode(drive[0])
        SyncEngine.run(local, f, now)
        if (f.dirty) drive[0] = f.encode()
    }

    @Test fun twoDeviceSync() {
        val drive = arrayOf<String?>(null)
        val a = FakeLocal(shortcuts = mapOf("ko" to "không"), templates = mapOf("một" to "000000\u00011"))
        sync(a, drive, 1000)
        // B máy mới, mẫu câu mặc định chưa sửa: nhận của A, không đẩy mẫu mặc định lên.
        val b = FakeLocal(shortcuts = mapOf("mn" to "mọi người"), templates = mapOf("mặc định" to "000000\u0001"),
            templatesTouched = false)
        sync(b, drive, 2000)
        assertEquals(mapOf("ko" to "không", "mn" to "mọi người"), b.shortcuts)
        assertEquals(setOf("một"), b.templates.keys)
        // A kéo về gõ tắt của B.
        sync(a, drive, 3000)
        assertEquals(mapOf("ko" to "không", "mn" to "mọi người"), a.shortcuts)
        // A xoá "ko", B sửa "mn" cùng lúc ⇒ giữ cả hai thay đổi.
        a.shortcuts = mapOf("mn" to "mọi người")
        b.shortcuts = mapOf("ko" to "không", "mn" to "mọi người ơi")
        sync(a, drive, 4000); sync(b, drive, 5000); sync(a, drive, 6000)
        assertEquals(mapOf("mn" to "mọi người ơi"), a.shortcuts)
        assertEquals(a.shortcuts, b.shortcuts)
        // Không đổi gì ⇒ không ghi file.
        val before = drive[0]
        val f = SyncFile.decode(drive[0]); SyncEngine.run(a, f, 7000)
        assertFalse(f.dirty); assertEquals(before, drive[0])
    }
}
