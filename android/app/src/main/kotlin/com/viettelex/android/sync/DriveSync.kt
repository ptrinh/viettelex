package com.viettelex.android.sync

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.mutableStateOf
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import com.viettelex.android.ui.Prefs
import com.viettelex.android.ui.TemplatesStore
import com.viettelex.keyboard.BackupPrefs
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.MiniJson
import com.viettelex.keyboard.PlusFeature
import com.viettelex.keyboard.PlusGate
import com.viettelex.keyboard.ShortcutOrder
import com.viettelex.keyboard.SyncDomain
import com.viettelex.keyboard.SyncEngine
import com.viettelex.keyboard.SyncFile
import com.viettelex.keyboard.SyncLocal
import com.viettelex.keyboard.SyncMerge
import com.viettelex.keyboard.SyncSection
import com.viettelex.keyboard.tr
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors

/**
 * Đồng bộ cài đặt + gõ tắt + mẫu câu giữa các máy Android qua Google Drive App Data (thư mục ẩn của
 * app trong Drive người dùng — người dùng không thấy, app khác không đọc được). Plus ([PlusFeature.CLOUD_SYNC]),
 * mặc định TẮT. Song sinh iOS ICloudSync (cùng lõi LWW — [SyncEngine], cùng định dạng domain).
 *
 * - Quyền DUY NHẤT `drive.appdata` (Google xếp non-sensitive). OAuth client Android khớp theo package +
 *   SHA-1 (project GCP misc-projects-514718) — không nhúng client ID.
 * - Chỉ app cài đặt (process ":settings") đồng bộ: lúc mở app ([syncInBackground] ở onResume), lúc rời
 *   app (onStop), khi bật công tắc và khi bấm "Đồng bộ ngay". Bàn phím không chạm mạng.
 * - Không đồng bộ từ đã học (riêng tư + dung lượng).
 * - Trạng thái (bật, sổ cái, lần cuối) ở prefs RIÊNG [PREFS] — không nằm trong Auto Backup (chỉ viettelex.xml).
 */
object DriveSync {
    const val SCOPE = "https://www.googleapis.com/auth/drive.appdata"
    private const val PREFS = "viettelex_sync"
    private const val ENABLED = "driveSyncEnabled"
    private const val LAST = "driveLastSync"

    data class Status(val running: Boolean = false, val lastSync: Long = 0, val error: String? = null,
                      val needsConsent: Boolean = false)

    /** Trạng thái cho UI (main thread). */
    val status = mutableStateOf(Status())

    private val executor by lazy { Executors.newSingleThreadExecutor { r -> Thread(r, "vt-drive-sync").apply { isDaemon = true } } }
    private val main = Handler(Looper.getMainLooper())

    fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    fun isUnlocked() = PlusGate.isUnlocked(PlusFeature.CLOUD_SYNC)
    fun isEnabled(ctx: Context) = prefs(ctx).getBoolean(ENABLED, false) && isUnlocked()

    fun loadStatus(ctx: Context) {
        status.value = status.value.copy(lastSync = prefs(ctx).getLong(LAST, 0))
    }

    private fun request() = AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(SCOPE))).build()

    /**
     * Xin quyền. [onConsent] = Google cần người dùng chọn tài khoản / đồng ý (UI mở PendingIntent rồi gọi
     * [handleConsentResult]); [onToken] = đã có quyền.
     */
    fun authorize(ctx: Context, onToken: (String) -> Unit, onConsent: (PendingIntent) -> Unit) {
        Identity.getAuthorizationClient(ctx).authorize(request())
            .addOnSuccessListener { r -> handle(r, onToken, onConsent) }
            .addOnFailureListener { fail(tr("Không xin được quyền Google Drive.")) }
    }

    fun handleConsentResult(ctx: Context, data: Intent?, onToken: (String) -> Unit) {
        val r = runCatching { Identity.getAuthorizationClient(ctx).getAuthorizationResultFromIntent(data) }.getOrNull()
        val t = r?.accessToken
        if (t == null) fail(tr("Chưa cấp quyền Google Drive.")) else onToken(t)
    }

    private fun handle(r: AuthorizationResult, onToken: (String) -> Unit, onConsent: (PendingIntent) -> Unit) {
        val t = r.accessToken
        when {
            r.hasResolution() -> r.pendingIntent?.let(onConsent) ?: fail(tr("Chưa cấp quyền Google Drive."))
            t != null -> onToken(t)
            else -> fail(tr("Chưa cấp quyền Google Drive."))
        }
    }

    fun setEnabled(ctx: Context, on: Boolean) {
        prefs(ctx).edit().putBoolean(ENABLED, on).apply()
        if (!on) status.value = status.value.copy(error = null, needsConsent = false)
    }

    /** Không có giao diện xin quyền: chỉ chạy khi đã cấp quyền trước đó; cần chọn lại tài khoản ⇒ báo ở UI. */
    fun syncInBackground(ctx: Context) {
        if (!isEnabled(ctx) || status.value.running) return
        val app = ctx.applicationContext
        authorize(app, onToken = { run(app, it) },
            onConsent = { status.value = status.value.copy(needsConsent = true, error = tr("Cần đăng nhập lại Google để đồng bộ.")) })
    }

    /** Một lượt đồng bộ (luồng nền): tải file → gộp → ghi prefs / ghi file nếu đổi. */
    fun run(ctx: Context, token: String) {
        val app = ctx.applicationContext
        if (status.value.running) return
        status.value = status.value.copy(running = true, error = null, needsConsent = false)
        executor.execute {
            val err: String? = try {
                val api = DriveApi(token)
                val id = api.findId()
                val file = SyncFile.decode(id?.let(api::download))
                SyncEngine.run(AndroidSyncLocal(app), file, System.currentTimeMillis())
                if (file.dirty) { if (id == null) api.create(file.encode()) else api.update(id, file.encode()) }
                prefs(app).edit().putLong(LAST, System.currentTimeMillis()).apply()
                null
            } catch (e: DriveApi.HttpError) {
                if (e.code == 401) runCatching {
                    Identity.getAuthorizationClient(app).clearToken(ClearTokenRequest.builder().setToken(token).build())
                }
                if (e.code == 401) tr("Phiên Google hết hạn — thử lại.") else tr("Google Drive báo lỗi %d.", e.code)
            } catch (e: IOException) {
                tr("Không kết nối được Google Drive.")
            } catch (e: IllegalArgumentException) {
                tr("Dữ liệu đồng bộ trên Drive bị hỏng.")
            }
            main.post {
                status.value = Status(running = false, lastSync = prefs(app).getLong(LAST, 0), error = err)
                if (err == null) com.viettelex.android.ui.PrefRefresh.dispatch(app, null)
            }
        }
    }

    private fun fail(msg: String) { status.value = status.value.copy(running = false, error = msg) }
}

/** Nối [SyncEngine] với SharedPreferences [Keys.PREFS] (chung với bàn phím) + sổ cái ở prefs riêng. */
class AndroidSyncLocal(private val ctx: Context) : SyncLocal {
    private val sp = Prefs.of(ctx)
    private val ledgers = DriveSync.prefs(ctx)

    override fun current(s: SyncSection): Map<String, String> {
        val all = sp.all
        return when (s) {
            SyncSection.SETTINGS -> SyncMerge.settingsToDomain(BackupPrefs.settings { all[it] })
            SyncSection.SHORTCUTS -> BackupPrefs.shortcutsFromPref(all[BackupPrefs.SHORTCUTS_KEY])
            SyncSection.TEMPLATES -> SyncMerge.templatesToDomain(TemplatesStore.load(ctx))
        }
    }

    override fun apply(s: SyncSection, values: Map<String, String>) {
        when (s) {
            SyncSection.SETTINGS -> {
                val e = sp.edit()
                for ((k, v) in SyncMerge.settingsFromDomain(values)) when (v) {
                    is Boolean -> e.putBoolean(k, v)
                    is Int -> e.putInt(k, v)
                    is String -> e.putString(k, v)
                }
                e.apply()
            }
            SyncSection.SHORTCUTS -> {
                val all = sp.all
                val old = BackupPrefs.shortcutsFromPref(all[BackupPrefs.SHORTCUTS_KEY])
                // Mục kéo về (mới / đổi nội dung) lên đầu danh sách; mục bị xoá bỏ mốc — như iOS.
                val times = ShortcutOrder.updated(ShortcutOrder.fromPref(all[Keys.SHORTCUTS_ADDED]), old, values,
                    System.currentTimeMillis())
                sp.edit().putString(BackupPrefs.SHORTCUTS_KEY, BackupPrefs.shortcutsToPref(values))
                    .putString(Keys.SHORTCUTS_ADDED, ShortcutOrder.toPref(times)).apply()
            }
            SyncSection.TEMPLATES -> TemplatesStore.save(ctx, SyncMerge.templatesFromDomain(values))
        }
    }

    override fun ledger(s: SyncSection): SyncDomain? =
        ledgers.getString(key(s), null)?.let { runCatching { SyncMerge.fromJson(MiniJson.parse(it)) }.getOrNull() }

    // Tắt đồng bộ KHÔNG xoá sổ: bật lại thì thay đổi lúc tắt được đóng dấu như sửa mới (như iOS).
    override fun setLedger(s: SyncSection, d: SyncDomain) {
        ledgers.edit().putString(key(s), MiniJson.write(SyncMerge.toJson(d), pretty = false)).apply()
    }

    override fun isUntouched(s: SyncSection) = s == SyncSection.TEMPLATES && !sp.contains(Keys.USER_TEMPLATES)

    private fun key(s: SyncSection) = "ledger.${s.id}"
}

/** Drive REST v3 tối giản (HttpURLConnection) — chỉ thư mục appDataFolder, một file [SyncFile.FILE_NAME]. */
class DriveApi(private val token: String) {
    class HttpError(val code: Int) : IOException("HTTP $code")

    fun findId(): String? {
        val q = URLEncoder.encode("name='${SyncFile.FILE_NAME}' and trashed=false", "UTF-8")
        val body = call("GET", "$API/files?spaces=appDataFolder&fields=files(id)&pageSize=1&q=$q")
        val files = (MiniJson.parse(body) as? Map<*, *>)?.get("files") as? List<*>
        return (files?.firstOrNull() as? Map<*, *>)?.get("id") as? String
    }

    fun download(id: String): String = call("GET", "$API/files/$id?alt=media")

    fun create(content: String) {
        val boundary = "vt" + System.nanoTime()
        val meta = MiniJson.write(mapOf("name" to SyncFile.FILE_NAME, "parents" to listOf("appDataFolder")), pretty = false)
        val body = "--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n" +
            "--$boundary\r\nContent-Type: application/json\r\n\r\n$content\r\n--$boundary--"
        call("POST", "$UPLOAD/files?uploadType=multipart", body, "multipart/related; boundary=$boundary")
    }

    /** HttpURLConnection không có PATCH ⇒ POST + X-HTTP-Method-Override (Google API hỗ trợ). */
    fun update(id: String, content: String) {
        call("POST", "$UPLOAD/files/$id?uploadType=media", content, "application/json", override = "PATCH")
    }

    private fun call(method: String, url: String, body: String? = null, type: String? = null, override: String? = null): String {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.requestMethod = method
            c.connectTimeout = 15_000; c.readTimeout = 20_000
            c.setRequestProperty("Authorization", "Bearer $token")
            override?.let { c.setRequestProperty("X-HTTP-Method-Override", it) }
            if (body != null) {
                c.doOutput = true
                c.setRequestProperty("Content-Type", type ?: "application/json")
                c.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
            val code = c.responseCode
            if (code !in 200..299) throw HttpError(code)
            return c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
        } finally {
            c.disconnect()
        }
    }

    private companion object {
        const val API = "https://www.googleapis.com/drive/v3"
        const val UPLOAD = "https://www.googleapis.com/upload/drive/v3"
    }
}
