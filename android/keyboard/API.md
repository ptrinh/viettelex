# :keyboard — cách IME gọi module (package `com.viettelex.keyboard`)

Pure Kotlin/JVM: không Android API. IME (agent C) chỉ nối dây: InputConnection ⇄
`TextProxy`, Handler ⇄ `MainThread`, assets ⇄ `KeyboardData.install`. Toàn bộ quyết
định (engine, học từ, gợi ý, undo auto-restore, nút Dán, xoá theo từ, mẫu câu) nằm ở
`KeyboardSession` — port 1:1 `KeyboardViewController.swift`.

## 0. Khởi động (một lần / process, rẻ)
```kotlin
KeyboardData.install { name -> /* ByteBuffer của assets/<name> */ }
// Khuyên: mmap — app/build.gradle.kts cần `androidResources { noCompress += listOf("bin") }`
//   assets.openFd(name).use { fd -> FileInputStream(fd.fileDescriptor).channel
//       .map(READ_ONLY, fd.startOffset, fd.length) }
// Fallback: ByteBuffer.wrap(assets.open(name).readBytes())   (150 KB + 50 KB)
val main = object : MainThread {                       // Handler(Looper.getMainLooper())
    override fun post(r: Runnable) { handler.post(r) }
    override fun postDelayed(delayMs: Long, r: Runnable): Cancellable {
        handler.postDelayed(r, delayMs); return Cancellable { handler.removeCallbacks(r) } }
}
val model = UserLangModel(File(filesDir, Keys.USERLM_FILE), main)   // load nền, không chặn
val session = KeyboardSession(model, clipboard /* ClipboardSource */)   // tự seed + gắn lexicon
model.onReady = { refreshBar() }
TouchLog.configure(File(filesDir, Keys.TOUCHLOG_FILE), recordsCharacters = BuildConfig.DEBUG)
```
Lexicon/emoji/seed đọc lazy lần đầu cần. Mọi blob đọc tại chỗ (absolute get, thread-safe).

## 1. Mỗi lần bàn phím hiện (`onStartInputView`)
```kotlin
val settings = KeyboardSettings.load { key -> prefs.all[key] }  // SharedPreferences Keys.PREFS
TouchLog.enabled = settings.debugTouchLog
session.startInput(settings, FieldTraits(
    isSecure = variation is *PASSWORD*,
    passthrough = variation in URI/EMAIL/VISIBLE_PASSWORD/FILTER,   // spec §12
    capSentences = inputType has TYPE_TEXT_FLAG_CAP_SENTENCES,
    suggestionsAllowed = !isSecure && !passthrough /* && !NO_SUGGESTIONS nếu chốt */))
shift.auto = session.updateAutoShift(proxy) ?: shift.auto   // null = ô không CAP_SENTENCES
render(session.requestSuggestions(proxy))                   // bar mở đầu
```
`startInput` tạo `EngineBridge` mới (settings mới), và nếu `Keys.USERLM_RESET_AT` đổi
so với lần trước ⇒ `model.reloadAfterExternalErase()` (bỏ bảng trong RAM, không bao giờ
ghi đè lại dữ liệu cũ, seed lại). Nên gọi thêm ngay trong
`OnSharedPreferenceChangeListener` của key đó.
`onFinishInputView` ⇒ `session.finishInput()` (ghi userlm nếu có thay đổi).

## 2. TextProxy (bọc InputConnection)
```kotlin
interface TextProxy {
  fun insertText(text: String)            // commitText(text, 1)
  fun deleteCodePoints(count: Int)        // deleteSurroundingTextInCodePoints(count, 0) — diff engine
  fun deleteBackward()                    // 1 ký tự user thấy (KEYCODE_DEL / grapheme) — ⌫ thường
  val isSecure: Boolean
  fun contextBeforeInput(): String?       // getTextBeforeCursor(~256, 0)
  fun clearAll()                          // 🗑 mẫu câu: xoá sạch ô (≤ 20 000 ký tự)
}
```
Bọc mỗi lời gọi `session.*` sửa text trong `beginBatchEdit/endBatchEdit` + cờ
`applyingEdit` (bỏ qua `onUpdateSelection` do chính mình gây ra, §4.1).

## 3. Phím
```kotlin
val out = session.handle(Key.Letter('a'), proxy)   // phím chữ, đã theo shift
// Key.Text(",") số/ký hiệu/dấu câu · Key.Space · Key.DoubleSpacePeriod · Key.Newline
// Key.Backspace · Key.MoveCursor(delta) (trackpad: session reset, IME tự dời con trỏ)
// Key.ClearField (🗑)
if (out.needsAutoShift) handler.post { if (out.generation == session.generation)
    shift.auto = session.updateAutoShift(proxy) ?: shift.auto }
handler.postDelayed({ if (out.generation == session.generation) refreshBar() }, 30)
```
- Double-space: IME đo 2 space < `TypingTimings.DOUBLE_SPACE_S` (0.35 s) ⇒ gửi
  `Key.DoubleSpacePeriod` thay `Key.Space`; session tự kiểm `TypingHeuristics`.
- Giữ ⌫ > 3 s ⇒ `session.deleteWordBackward(proxy)` mỗi nhịp thứ 4.
- Con trỏ dời từ ngoài (`onUpdateSelection` ≠ expected, không `applyingEdit`) ⇒
  `session.externalSelectionChange()` rồi `updateAutoShift` + `refreshBar()`.
- Thứ tự chạm: `KeyCommitQueue` (arm lúc DOWN / flush khi ngón khác DOWN / release
  lúc UP hoặc CANCEL / disarm khi vào trackpad). Phím chữ: `queue.flush()` rồi handle.

## 4. Gợi ý (off-main)
```kotlin
fun refreshBar() = when (val plan = session.requestSuggestions(proxy)) {
    is SuggestionPlan.Ready -> bar.show(plan.set)          // plan.set == null ⇒ không vẽ gì
    is SuggestionPlan.Background -> bgExecutor.execute {
        val r = plan.job.compute()                          // VNSuggest + AdjacentKeyFixer
        handler.post { session.completeSuggestions(plan.job, r)?.let(bar::show) } }
}                                                            // null ⇒ lượt cũ, bỏ
```
`SuggestionSet` = `literal`, `word`, `word2`, `emojis`, `nextWords`, `paste`,
`signature()` (so để bỏ vẽ lại). Bar thu gọn: `session.barCollapsed = true` (pipeline
ngừng; IME lưu `Keys.SUGGESTION_BAR_COLLAPSED`). Bar tắt/ô cấm: `session.suggestionsActive`.
Chạm slot: `session.acceptSuggestion(item, proxy)` — item là đúng chuỗi hiển thị
(literal / từ / emoji / `gmail.com` / `SuggestionSet.PASTE_TOKEN`). Sau đó
IME gọi `updateAutoShift` + `refreshBar()` + phát click (hàm trả Unit).
`session.suggestionsNow(proxy)` = bản đồng bộ (test/debug).

## 5. Nút Dán
`ClipboardSource`: `changeCount` (IME tăng trong `addPrimaryClipChangedListener`),
`hasText()` (chỉ đọc ClipDescription), `readText()` (chỉ gọi khi user chạm).
Session tự áp điều kiện (không gõ dở, trước con trỏ là trắng/ô trống, đổi trong 180 s,
chưa dán, cache 2 s). Bàn phím vừa hiện hẳn: `session.invalidatePasteCache()` rồi refresh.

## 6. Chạm → phím (TouchGeometry / KeyRouter)
```kotlin
val p = TouchGeometry.keySelectionPoint(KPoint(x, y), density)   // dời lên 4 dp
val idx = KeyRouter.nearestLetter(p, letterRects, rowsTop)  // null ⇒ không phải phím chữ
KeyRouter.letterCoreContains(p, letterRects, rowsTop)       // phím chữ thắng vùng nở ⇧/⌫
KeyRouter.expandedContains(rect, p)                          // hit nở dx 3 dp, dy 5.5 dp
```
Tất cả tính bằng **dp** (truyền rect theo dp, hoặc dùng overload có `density`).

## 7. Mẫu câu, emoji, settings
- Mẫu câu: sau fetch gọi `session.insertTemplate(...)` rồi updateAutoShift + refreshBar.
- `Templates.load(json = prefs.getString(Keys.USER_TEMPLATES), defaultsYaml = { assets ios-mau-cau.yml })`,
  `Templates.parseYAML/exportYAML/toJson/fromJson/merge` (thông báo import y iOS).
- Chạm chip: nếu `Templates.isDynamic(text)` IME fetch (timeout 4 s) rồi
  `session.insertTemplate(Templates.bodyFromResponse(bytes) ?: text, proxy)`.
- `EmojiData.categories` (lazy từ `emojidata.tsv`), `EmojiData.displayName(name)`,
  `EmojiData.toneVariants(e)`, `EmojiRecents.noteUsed(list, e)` + `encode/decode`
  (pref `Keys.EMOJI_RECENTS`).
- `Keys` = mọi key SharedPreferences + tên file (`userlm.bin`, `touchlog.txt`) dùng chung
  C/D. `KeyboardSettings` giữ mặc định iOS.
- `TouchLog.*` ghi `filesDir/touchlog.txt` (cap 300 KB giữ nửa mới); ký tự chỉ ghi khi
  `recordsCharacters = true` (chỉ debug build). `TouchLog.tail(80)`, `TouchLog.clear()`.
