package com.viettelex.keyboard

/**
 * Đồng bộ cài đặt + gõ tắt + mẫu câu giữa các máy (Android: Google Drive App Data — app/…/sync/
 * DriveSync.kt). Port 1:1 lõi iOS `SyncCore.swift` / `SyncMerge.swift`: LWW TỪNG MỤC.
 *
 * Mỗi mục (một setting / một gõ tắt / một mẫu câu) là một [SyncEntry] {v, t}: v = giá trị dạng chuỗi
 * (null = đã xoá — "tombstone"), t = thời điểm sửa (ms). Gộp hai bản = lấy entry thắng ([SyncMerge.wins])
 * cho từng key ⇒ giao hoán, kết hợp, luỹ đẳng: hai máy sửa HAI mục khác nhau thì giữ cả hai; cùng một
 * mục thì bản sửa sau thắng.
 *
 * Máy không tự biết "mục nào vừa sửa" (prefs ghi từ app + bàn phím) nên giữ một SỔ CÁI (ledger) =
 * bản đã gộp lần trước: lần đồng bộ sau so giá trị hiện tại với sổ, mục khác ⇒ đóng dấu t = now, mục
 * biến mất ⇒ tombstone t = now. Lần ĐẦU (sổ trống, vd máy mới): mục nào mây đã có thì mây thắng.
 *
 * THUẦN (không Android) — test: CloudSyncTests (vector khớp iOS BackupTests).
 */
data class SyncEntry(val v: String?, val t: Long)

typealias SyncDomain = Map<String, SyncEntry>

/** Ba nhóm được đồng bộ. Mẫu câu: key = câu, v = "<thứ tự 6 số>\u0001<label>" (như iOS). */
enum class SyncSection(val id: String) {
    SETTINGS("settings"), SHORTCUTS("shortcuts"), TEMPLATES("templates");
    /** Key trong file mây (trùng key KVS của iOS). */
    val cloudKey: String get() = "vt.sync.$id"
}

object SyncMerge {
    /** Tombstone cũ hơn ngần này thì bỏ (máy offline lâu hơn có thể "hồi sinh" mục đã xoá — chấp nhận). */
    const val TOMBSTONE_TTL: Long = 180L * 86_400_000

    fun stamp(current: Map<String, String>, ledger: SyncDomain?, remote: SyncDomain = emptyMap(), now: Long): SyncDomain {
        if (ledger == null) {
            return current.filterKeys { remote[it] == null }.mapValues { SyncEntry(it.value, now) }
        }
        val out = LinkedHashMap(ledger)
        for ((k, v) in current) if (ledger[k]?.v != v) out[k] = SyncEntry(v, now)
        for ((k, e) in ledger) if (e.v != null && current[k] == null) out[k] = SyncEntry(null, now)
        return out
    }

    fun merge(a: SyncDomain, b: SyncDomain): SyncDomain {
        val out = LinkedHashMap(a)
        for ((k, y) in b) { val x = out[k]; if (x == null || wins(y, x)) out[k] = y }
        return out
    }

    /** Thứ tự toàn phần để hai máy luôn chọn cùng kết quả: t lớn hơn; hoà thì tombstone thua giá trị;
     *  hai giá trị hoà thì chuỗi lớn hơn (so theo UTF-16 — giống Swift với chuỗi BMP). */
    fun wins(y: SyncEntry, x: SyncEntry): Boolean {
        if (y.t != x.t) return y.t > x.t
        val xv = x.v; val yv = y.v
        return when {
            xv == null && yv == null -> false
            xv == null -> true
            yv == null -> false
            else -> yv > xv
        }
    }

    fun live(d: SyncDomain): Map<String, String> = d.mapNotNull { (k, e) -> e.v?.let { k to it } }.toMap()

    fun pruned(d: SyncDomain, now: Long): SyncDomain = d.filter { it.value.v != null || now - it.value.t < TOMBSTONE_TTL }

    // --- mã hoá: {"key": {"v": "...", "t": 123}} (cùng iOS) ---

    fun toJson(d: SyncDomain): Map<String, Any> = d.toSortedMap().mapValues { (_, e) ->
        LinkedHashMap<String, Any>().apply { e.v?.let { put("v", it) }; put("t", e.t) }
    }

    fun fromJson(o: Any?): SyncDomain? {
        val m = o as? Map<*, *> ?: return null
        val out = LinkedHashMap<String, SyncEntry>()
        for ((k, raw) in m) {
            val x = raw as? Map<*, *> ?: continue
            val t = when (val tv = x["t"]) { is Long -> tv; is Double -> tv.toLong(); else -> continue }
            out[k as String] = SyncEntry(x["v"] as? String, t)
        }
        return out
    }

    // --- mẫu câu ⇄ domain (giữ thứ tự) ---

    fun templatesToDomain(items: List<TemplateItem>): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        items.forEachIndexed { i, it -> if (it.text !in out) out[it.text] = "%06d".format(i) + "\u0001" + it.label }
        return out
    }

    fun templatesFromDomain(d: Map<String, String>): List<TemplateItem> =
        d.map { (text, v) ->
            val order = v.substringBefore('\u0001')
            val label = if ('\u0001' in v) v.substringAfter('\u0001') else ""
            order to TemplateItem(label, text)
        }.sortedWith(compareBy({ it.first }, { it.second.text })).map { it.second }

    // --- setting ⇄ chuỗi (như iOS SettingValue.syncString / fromSyncString) ---

    fun settingsToDomain(s: Map<String, Any>): Map<String, String> = s.mapValues { (_, v) ->
        when (v) { is Boolean -> if (v) "true" else "false"; else -> v.toString() }
    }

    /** Parse theo spec của key; sai kiểu / key lạ ⇒ bỏ. */
    fun settingsFromDomain(d: Map<String, String>): Map<String, Any> {
        val out = LinkedHashMap<String, Any>()
        for ((k, s) in d) {
            val spec = BackupSettings.byKey[k] ?: continue
            when (val kind = spec.kind) {
                is SettingKind.Bool -> when (s) { "true" -> out[k] = true; "false" -> out[k] = false }
                is SettingKind.IntRange -> s.toIntOrNull()?.let { out[k] = it.coerceIn(kind.range) }
                is SettingKind.Choice -> if (s in kind.allowed) out[k] = s
                SettingKind.BuddyName -> out[k] = BuddyName.clean(s)
                SettingKind.StyleMap -> KeyStyleStore.normalize(s)?.let { out[k] = it }
                SettingKind.ThemeMap -> CustomThemeStore.normalize(s)?.let { out[k] = it }
            }
        }
        return out
    }
}

/** Kho trên mây theo nhóm (Drive: một file JSON giữ cả ba nhóm — [SyncFile]). */
interface SyncCloud {
    fun domain(s: SyncSection): SyncDomain?
    fun setDomain(s: SyncSection, d: SyncDomain)
}

/** Dữ liệu cục bộ của một máy: đọc giá trị hiện tại, ghi giá trị đã gộp, và sổ cái. */
interface SyncLocal {
    fun current(s: SyncSection): Map<String, String>
    fun apply(s: SyncSection, values: Map<String, String>)
    fun ledger(s: SyncSection): SyncDomain?
    fun setLedger(s: SyncSection, d: SyncDomain)
    /** true = dữ liệu mặc định chưa từng sửa (mẫu câu bundle) — lần đầu mà mây đã có dữ liệu thì không góp vào. */
    fun isUntouched(s: SyncSection): Boolean
}

object SyncEngine {
    data class Result(val pulled: List<SyncSection> = emptyList(), val pushed: List<SyncSection> = emptyList())

    /** Một lượt: đóng dấu thay đổi cục bộ → gộp với mây → ghi lại cả hai phía nếu khác. Lặp lại vô hại. */
    fun run(local: SyncLocal, cloud: SyncCloud, now: Long, sections: List<SyncSection> = SyncSection.entries): Result {
        val pulled = ArrayList<SyncSection>(); val pushed = ArrayList<SyncSection>()
        for (s in sections) {
            val cur = local.current(s)
            val remote = cloud.domain(s) ?: emptyMap()
            val ledger = local.ledger(s)
            val contrib = if (ledger == null && remote.isNotEmpty() && local.isUntouched(s)) emptyMap() else cur
            val stamped = SyncMerge.stamp(contrib, ledger, remote, now)
            val merged = SyncMerge.pruned(SyncMerge.merge(stamped, remote), now)
            val live = SyncMerge.live(merged)
            if (live != cur) { local.apply(s, live); pulled += s }
            if (merged != remote) { cloud.setDomain(s, merged); pushed += s }
            local.setLedger(s, merged)
        }
        return Result(pulled, pushed)
    }
}

/** File đồng bộ trên Drive (appDataFolder): {"format":"viettelex-sync","version":1,"vt.sync.settings":{…},…}. */
class SyncFile(private val domains: MutableMap<SyncSection, SyncDomain> = LinkedHashMap()) : SyncCloud {
    var dirty = false
        private set

    override fun domain(s: SyncSection): SyncDomain? = domains[s]
    override fun setDomain(s: SyncSection, d: SyncDomain) { domains[s] = d; dirty = true }

    fun encode(): String {
        val root = LinkedHashMap<String, Any>()
        root["format"] = FORMAT; root["version"] = VERSION
        for (s in SyncSection.entries) domains[s]?.let { root[s.cloudKey] = SyncMerge.toJson(it) }
        return MiniJson.write(root, pretty = false)
    }

    companion object {
        const val FORMAT = "viettelex-sync"
        const val VERSION = 1
        const val FILE_NAME = "viettelex-sync.json"

        /** null / rỗng ⇒ file mới (chưa có gì trên mây). File hỏng hoặc không phải của mình ⇒ ném. */
        fun decode(text: String?): SyncFile {
            if (text.isNullOrBlank()) return SyncFile()
            val root = runCatching { MiniJson.parse(text) }.getOrNull() as? Map<*, *>
                ?: throw IllegalArgumentException("sync file is not JSON")
            require(root["format"] == FORMAT) { "not a sync file" }
            val out = LinkedHashMap<SyncSection, SyncDomain>()
            for (s in SyncSection.entries) SyncMerge.fromJson(root[s.cloudKey])?.let { out[s] = it }
            return SyncFile(out)
        }
    }
}
