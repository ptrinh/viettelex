# RAM audit — bàn phím Android (process IME)

Ngày đo: 28/09/2026 · commit gốc `6305eef` · chỉ đo + khuyến nghị, **chưa đổi hành vi**.

## Cách đo (lặp lại được)

| Công cụ | Việc |
|---|---|
| `android/Scripts/ram-audit.sh matrix OUT [APK]` | Ma trận cấu hình × trạng thái trên emulator: `dumpsys meminfo`, `/proc/pid/smaps` (vùng `base.apk` = asset mmap), `dumpsys gfxinfo` (cache HWUI/GPU), SIGQUIT → tổng byte ART đã cấp phát + số GC. Tự đặt VietTelex làm IME, trả lại IME cũ khi thoát. |
| `android/Scripts/hprof-summary.py` | Đọc heap dump (`am dumpheap -g` + `hprof-conv`): top lớp theo shallow size; `--referrers X --path` in chuỗi tham chiếu ngắn nhất tới GC root (thay LeakCanary). |
| `keyboard/.../RamFootprintTests.kt` | JVM: heap giữ lại + rác tạm lúc dựng từng cấu trúc; byte cấp phát/phím (ThreadMXBean); `VT_JFR=1` ⇒ JFR chỉ ra dòng code cấp phát. Chạy: `VT_SLOW_TESTS=1 [VT_JFR=1] ./gradlew --offline :keyboard:test --tests '*RamFootprintTests*' -i \| grep RAM` |

Máy: AVD `relaykey-m1` (sdk_gphone64_arm64, API 35, 1080×2400 @420 dpi, RAM 2.5 GB), bản **release** (R8 + shrink, ký debug key), ô "First name" của Contacts, gõ chạm thật (`input tap`) 200 phím.
Cấu hình: **default** (mặc định app) · **off** (tắt gợi ý, chọn phím thông minh, vuốt, âm/rung, …) · **all** (vuốt + FUTO + vuốt tiếng Anh, gợi ý, clipboard, âm phím, rung, mẫu câu, tự sửa, ảnh nền 810×1080 + trong suốt 30 %, Plus).

Lưu ý emulator: cột *Graphics* = 0 (emulator không có memtrack) — texture GPU (gfxinfo báo 8–11 MB) trên máy thật sẽ hiện ở Graphics; Native heap có thêm phần giả lập GL. So sánh **tương đối** giữa cấu hình là đáng tin; số tuyệt đối trên máy thật sẽ khác vài MB.

## Số đo (KB, PSS)

| Trạng thái | default PSS | Java | Native | Code | off PSS | all PSS | all Java | all Native |
|---|---|---|---|---|---|---|---|---|
| vừa hiện (process mới) | 50 085 | **16 008**¹ | 17 728 | 4 756 | 34 825 | **77 902** | **34 552**¹ | 21 484 |
| sau 200 phím | 50 660 | 6 256 | 19 732 | 7 660 | 45 577 | 63 771 | 9 936 | 23 856 |
| mở emoji (cuộn 6 trang) | 53 708 | 4 860 | 24 036 | 7 088 | 47 830 | 67 253 | 8 916 | 28 632 |
| mở clipboard | – | – | – | – | – | 67 691 | 8 528 | 29 332 |
| ẩn bàn phím | 54 541 | 4 416 | 25 260 | 7 092 | 48 926 | 67 492 | 8 528 | 29 216 |
| `send-trim-memory BACKGROUND` | 48 164 | 4 396 | 18 864 | 7 092 | 42 908 | 57 716 | 5 964 | 22 004 |
| `… COMPLETE` | 44 947 | 3 584 | 16 444 | 7 092 | 41 569 | 55 092 | 4 796 | 20 536 |
| hiện/ẩn thêm 20 lần | 57 479 | **16 016**² | 15 816 | 7 924 | 43 119 | 62 552 | 11 136 | 19 672 |

¹ ở lần đo khác (rel2) default-shown = 29 MB Java: đỉnh do rác lúc dựng bảng *chọn phím thông minh* (xem #1). ² dựng lại bảng đó sau trim.

| Cấp phát ART (tích luỹ) | default | off | all |
|---|---|---|---|
| tới lúc bàn phím hiện | **~30 MB** | 4.2 MB | **~37 MB** |
| 200 phím | +1–2 MB (~5–7 KB/phím) | +1.5 MB | +3 MB |
| 20 lần hiện/ẩn | **+28.7 MB** (sau trim) | +2 MB | **+95 MB** (FUTO nạp lại mỗi lần hiện) |
| Số GC trong cả kịch bản | 11 | 7 | 16 |

Tham chiếu cùng emulator: **Gboard sau 200 phím = 189 MB PSS** (Java 17.7, Native 49.8, Code 60.9 MB). VietTelex nhẹ ~3–4× — hướng tối ưu là **đỉnh** và **churn**, không phải nền.

Mở app cài đặt (Compose, **cùng process**) rồi thoát: PSS IME 40.4 → **57.2 MB** (+16.7 MB) và **giữ nguyên** vì từ API 31 Back không finish activity gốc (Activities = 1 sau khi thoát), mà process IME ở oom_adj 100 nên hệ thống không bao giờ dọn.

### Heap giữ lại theo cấu trúc (JVM ≈ ART, ±15 %)

| Cấu trúc | Giữ lại | Rác lúc dựng | Khi nào sống |
|---|---|---|---|
| FutoSwipeModel (fp16 → FloatArray + scratch) | **3.4 MB** | 2.8 MB | FUTO bật; nhả lúc ẩn ⇒ nạp lại mỗi lần hiện |
| SwipeEnglish.lexicon (~25k String) | **1.4 MB** | 1.9 MB | vuốt tiếng Anh / gõ EN — `by lazy` trong object, **không bao giờ nhả** (→ 10/11/2026: 78.5 KB tại chỗ, xem cuối file) |
| UserLangModel đầy cap — bảng gọn 09/2026 (trước: HashMap lồng 1.25–1.5 MB) | **0.34 MB** | — | luôn (seed mới: <0.1 MB) |
| TelexKeyPrior (chọn phím thông minh, **mặc định BẬT**) | 0.86 MB | **31 MB** | luôn; nhả ở onTrimMemory ⇒ dựng lại |
| SwipeDecoder templates | 0.37 MB | 0.5 MB | gõ vuốt |
| VNLexicon2 offsets / SwipeLexicon.forms / Emoji strings | 0.12 / 0.11 / 0.11 MB | < 3.3 MB | luôn / vuốt / emoji |
| SyllableLM, EmojiSuggest, EmojiSearch | ~0 (mmap) | < 1 MB | — |

Asset `.bin`: **đã mmap đúng cách** (`noCompress += "bin"` + `openFd` + `FileChannel.map`) — smaps thấy vùng `base.apk` riêng từng asset, trang *sạch* (kernel thu hồi được): emoji.bin 112/256 KB resident, vnlexicon 152 KB, enlexicon 184 KB. Riêng `SwipeEnglish.parse` và `TelexKeyPrior` **copy cả enlexicon vào ByteArray** rồi dựng String. (vnlm.bin không được map trong các kịch bản gõ chạm này — chỉ khi vuốt/Thêm dấu cần.)

### Cấp phát mỗi phím (JVM, `RamFootprintTests.allocationPerKey`)

| Đường | B/phím | Nguồn chính (JFR) |
|---|---|---|
| engine + auto-shift | ~1.7 KB | `autoShiftFor` (`trim` copy chuỗi ngữ cảnh ≤256 ký tự), đọc ngữ cảnh |
| + thanh gợi ý | ~7.3 KB | **42 % `EngineBridge.composeTrial` tạo `TelexEngine()` mới mỗi lần** (~12 IntArray(32)); `VNSuggest.display` String; `VNSuggest.matches` |

5–7 KB/phím ⇒ GC trẻ ~mỗi 500–800 phím, concurrent — **không phải nguồn jank hiện tại** (máy đo 1 GC/200 phím, không có GC chặn lúc gõ). Churn lớn nằm ở dựng/nạp lại dữ liệu (#1, #3).

### Native / đồ hoạ

Native heap 16–29 MB là phần lớn nhất nhưng chủ yếu **HWUI/Skia của framework**: ~17.5 MB ngay khi view đầu tiên vẽ (cấu hình off). App ảnh hưởng qua:
- **Ảnh nền**: +3.5 MB native (bitmap 810×1080 ARGB_8888 giải nguyên ảnh dù chỉ thấy vùng center-crop ~60 %) + 3.34 MB texture GPU (gfxinfo) ⇒ ~7 MB trên máy thật.
- **Bảng emoji**: +2–4 MB (glyph cache màu Skia + atlas 8 MB GPU), **không nhả khi đóng/ẩn**.
- `send-trim-memory` giải phóng 6–8 MB (HWUI purge cache) — nhưng xem #6: IME đang chọn gần như không bao giờ nhận trim.

## Rò rỉ

Kịch bản: 15 lần hiện/ẩn, 4 lần xoay, 3 lần đổi IME (Gboard ↔ VietTelex), `am dumpheap -g`.
- Views/ViewRootImpl/AppContexts **không tăng** qua hiện/ẩn/xoay (27 view) — không rò view.
- **Đổi IME: 4 instance `VietTelexIME` sống sau GC** (mỗi cái giữ KeyboardSession + UserLangModel + view tree nếu đã hiện). `hprof-summary.py --path`:
  - `ROOT[jni-global] ClipboardManager$1 → ClipboardManager → VietTelexIME` ×2 — **lỗi của mình**: `AndroidClipboard` lấy `ClipboardManager` từ context của *service*; binder listener của manager chỉ được thả khi system_server GC proxy. Ép GC system_server (SIGUSR1) thì 2 instance này biến mất ⇒ rò *tạm* (vài giây → vài phút trên máy thật).
  - `ROOT RecordingCanvas pool → RenderNode → KeyButtonView (nav bar IME) → VietTelexIME` ×1 — rò của framework (pool RecordingCanvas giữ nav bar của service cũ), **sống lâu**.

## Khuyến nghị (ưu tiên theo lợi/rủi ro)

| # | Việc | Tiết kiệm ước tính | Rủi ro / công |
|---|---|---|---|
| 1 | **TelexKeyPrior (mặc định BẬT): sinh trie sẵn thành asset mmap** (script generator + test parity với `fromLexicon`), hoặc tối thiểu dựng không qua `Sequence<Pair<String,Int>>`/String/enlexicon copy. Bỏ `TelexKeyPrior.release()` ở onTrimMemory (nhả 0.86 MB nhưng lần hiện sau tốn 31 MB rác + ~0.2–1 s CPU). | Đỉnh Java **−12…24 MB** lúc mở bàn phím lần đầu; −0.86 MB giữ lại (mmap sạch); −31 MB cấp phát mỗi lần dựng | Thấp–TB (asset mới ~1 MB, phải regen khi lexicon đổi) |
| 2 | **Rò service qua ClipboardManager**: `ctx.applicationContext.getSystemService(ClipboardManager)` trong `AndroidClipboard`; trong `onDestroy` bỏ tham chiếu nặng (views, clipPane, session/model → nullable) để vỏ service bị giữ (framework pool) còn nhẹ. Tuỳ chọn: giữ UserLangModel/KeyboardSession ở singleton cấp process (đổi IME qua lại khỏi nạp lại file + 2 bản trong RAM). | Mỗi lần đổi IME: tránh giữ nguyên một bản service (UserLangModel 0.2–1.5 MB + view tree + session) | Thấp (1 dòng + dọn onDestroy) |
| 3 | **FUTO: thôi giải fp16 → FloatArray mỗi lần hiện.** (a) nhả theo hẹn giờ ẩn (#6) thay vì mỗi `onFinishInputView`; hoặc (b) ship weights fp32 không nén, đọc qua `FloatBuffer` mmap (0 heap, trang sạch) — đo lại tốc độ encoder. | −2.5…3.4 MB heap khi bật; −4.7 MB cấp phát mỗi lần hiện (95 MB/20 lần đo được) | (a) thấp; (b) TB (+1.27 MB APK, FloatBuffer chậm hơn FloatArray) |
| 4 | **Ảnh nền**: giải `inPreferredConfig = RGB_565` (JPEG không alpha; paint alpha vẫn chạy) hoặc `Bitmap.Config.HARDWARE` (bỏ bản CPU); cắt đúng vùng center-crop bằng `BitmapRegionDecoder` hoặc lưu sẵn ảnh đã crop theo tỉ lệ bàn phím lúc import. `WallpaperBitmap.drop()` khi ẩn lâu. **28/09/2026 trình chỉnh khung**: app nướng sẵn đúng vùng người dùng kéo/zoom (bản gốc ≤2048 chỉ ở app, `WallpaperMath.bakedSize` giữ mật độ điểm ảnh như bản cũ × zoom, trần 1080) ⇒ IME vẫn BitmapRegionDecoder + HARDWARE, khung mặc định giải đúng số điểm ảnh như trước, zoom không vượt trần cũ (`WallpaperCropTests.decodeRamNotAboveBefore`). | −1.7…3.4 MB native (+ tương đương GPU) | Thấp (565 có thể vằn trên ảnh mờ → bật dither) |
| 5 | **App cài đặt cùng process IME**: rẻ — `finish()` MainActivity ở `onStop` (không phải đổi cấu hình) để Compose/HWUI của activity được dọn; triệt để — `android:process=":settings"` (nhưng IME đang dựa `OnSharedPreferenceChangeListener` cùng process ⇒ phải đổi sang cơ chế liên process). | −10…16 MB sau khi user từng mở cài đặt/Luyện vuốt | Rẻ: thấp (mất trạng thái tab khi quay lại); tách process: cao |
| 6 | **onTrimMemory gần như chết**: API 34+ không gửi `TRIM_MEMORY_RUNNING_*`; IME đang chọn ở procState 5 / oom_adj 100 nên cũng không nhận `BACKGROUND`. Thay bằng **hẹn giờ ẩn** (vd 30–60 s sau `onFinishInputView`, huỷ khi hiện lại): nhả FUTO, SwipeEnglish.lexicon, WallpaperBitmap, emoji category strings, ClipboardPane view, templatesCache. Giữ TelexKeyPrior (#1). | 2–7 MB lúc ẩn (tuỳ tính năng) | Thấp |
| 7 | ✅ **ĐÃ LÀM 10/11/2026** — **SwipeEnglish.lexicon** (1.4 MB, không bao giờ nhả): đọc từ tại chỗ trên buffer mmap (so byte ASCII, không String) hoặc holder nhả được (#6). Xem mục 10/11/2026. | −1.4 MB khi vuốt EN / gõ EN | xong (test parity toàn bộ từ điển) |
| 8 | **Cấp phát mỗi phím**: `composeTrial` dùng lại một `TelexEngine` scratch mỗi luồng (reset thay vì `TelexEngine()`); `autoShiftFor` duyệt ngược thay vì `trim` copy. | −3 KB/phím (~−45 % trên đường gợi ý) | Thấp (có test engine) |
| 9 | ✅ **ĐÃ LÀM 09/2026** — UserLangModel: từ intern thành id (băm mở IntArray), uni IntArray, bi/tri LongArray sắp `(id shl 32 or count)`, file VTL2 chung iOS (CRC32; v1 "VTLM" chuyển một lần). Đo `UserLMCompactTests.measureHeavyUser` (2.990/5.990/2.990): heap 1.25 → **0.34 MB**, file 148 → 115 KB, nạp 2.3 → 1.3 ms, lưu 3.4 → 0.8 ms, `nextWords` 2.1 → 1.8 µs, `count` 41 → 33 ns, `trigramCount` 187 → 87 ns, `bigramCount` 84 → 117 ns (hai lần tra băm tự viết thay vì HashMap lồng — vẫn ~0.1 µs). Snapshot lưu chỉ copy mảng nguyên thuỷ. | −~1 MB + bớt churn lúc lưu | xong (property test so bản cũ) |

Không cần làm: không có Compose trong view IME (KeyboardView vẽ một canvas, EmojiPane vẽ trực tiếp — không view per emoji); không `largeHeap`; R8 minify + shrinkResources đã bật; SoundPool nhả khi ẩn, mẫu âm nhỏ; không có view leak khi xoay/hiện-ẩn. (10/11/2026: SoundPool **không** còn nhả mỗi lần ẩn — giữ qua các lần ẩn, nhả ở hẹn giờ ẩn / thiếu RAM; xem mục 10/11/2026.)

## Kinh nghiệm IME khác (đối chiếu)

- AOSP LatinIME / HeliBoard: từ điển nhị phân mmap ở native (không vào Java heap) — VietTelex đã làm tương đương với ByteBuffer mmap; bảng/phím dựng sẵn offline thay vì lúc chạy (chính là #1). Bảng emoji dựng lười.
- FlorisBoard dùng Compose cho cả UI IME — nặng hơn đáng kể; VietTelex đúng hướng khi giữ View/Canvas trong IME (và nên tách Compose của app ra, #5).
- Tài liệu Android: từ API 34 chỉ còn `TRIM_MEMORY_UI_HIDDEN`/`BACKGROUND` được gửi; bitmap pixel ở native heap từ API 26; `HARDWARE` bitmap chỉ ở GPU; `inSampleSize` chỉ lũy thừa 2 — muốn đúng cỡ thì crop/scale khi lưu.

## Đã sửa #1–6 (28/09/2026) — đo lại cùng emulator, bản release

Cùng kịch bản `ram-audit.sh matrix` (thêm trạng thái `hidden-idle` = ẩn 50 s cho hẹn giờ nhả) + `settings` + `switch`; "trước" = `fb17c37`, "sau" = nhánh sửa. KB PSS trừ khi ghi khác.

| Đo | default trước → sau | off trước → sau | all trước → sau |
|---|---|---|---|
| PSS vừa hiện (process mới) | 64 355 → **36 212** | 35 828 → 35 546 | 78 215 → **48 390** |
| Java heap vừa hiện | 30 092 → **2 752** | 2 552 → 2 564 | 34 888 → **8 612** |
| Native vừa hiện | 17 864 → 17 812 | 17 660 → 17 644 | 21 492 → **18 020** (ảnh nền) |
| PSS sau 200 phím | 48 640 → 47 720 | 45 732 → 45 298 | 61 423 → **56 090** |
| PSS sau 20 lần hiện/ẩn | 54 051 → **44 629** | 43 637 → 42 694 | 64 191 → **60 035** |
| Cấp phát ART tới lúc hiện | 31.7 MB → **5.1 MB** | 4.8 → 4.9 MB | 37.9 → **11.3 MB** |
| Cấp phát mỗi lần hiện (21 lần) | 1 365 → **98 KB** | 103 → 108 KB | 4 486 → **536 KB** |
| Số GC cả kịch bản | 10 → 8 | 8 → 8 | 17 → 10 |

- **#1** trie chọn phím thông minh: asset `keyprior.bin` (569 KB, mmap; nút đánh số BFS ⇒ không lưu edgeTo). `KeyPriorBlobTests` chốt asset byte-bằng bản dựng trong RAM + CRC dữ liệu nguồn (đổi vnlexicon/enlexicon/seed ⇒ test đỏ ⇒ `VT_REGEN_KEYPRIOR=1`). JVM: giữ 0.1 KB, rác 0 (trước 0.8 MB + 30 MB). Không nhả ở onTrimMemory nữa. iOS giữ nguyên (cùng thuật toán, cùng số). APK +570 KB.
- **#2** đổi IME ×3 (heap dump -g): vẫn 4 `VietTelexIME` (1 sống + 3 vỏ do `ImeOnBackInvokedDispatcher` của framework giữ qua jni-global tới khi system_server GC — ngoài tầm app) nhưng vỏ giờ **rỗng**: cây view 4 → 1 (thay input view + đo lại khung vì `FrameLayout.mMatchParentChildren` giữ con cũ), bảng UserLangModel bỏ (`close()` ghi nốt rồi dừng IO), HashMap 2 282 → 1 307, shallow heap 23.4 → 21.9 MB. ClipboardManager lấy từ applicationContext.
- **#3** FUTO: giữ weights qua các lần hiện. **Lỗi gốc**: onTrimMemory nhả ở `UI_HIDDEN` (tới mỗi lần ẩn) ⇒ giờ chỉ nhả khi thiếu RAM thật hoặc hẹn giờ ẩn (`ImeTrim`, có test). all: 95 → 11 MB cấp phát / 20 lần hiện. Chọn (a) thay vì fp32 mmap: không thêm 1.3 MB APK, không chậm encoder.
- **#4** ảnh nền: giải đúng vùng center-crop (`BitmapRegionDecoder`, cùng inSampleSize ⇒ cùng điểm ảnh) rồi chuyển `Bitmap.Config.HARDWARE` (ARGB_8888 ở GPU — không vằn như RGB_565, alpha paint vẫn chạy) ⇒ native −3.4 MB; canvas phần mềm bỏ qua bitmap HARDWARE.
- **#5** app cài đặt: finish ở onStop (trừ khi app vừa mở activity khác chờ kết quả / tắt màn hình — `SettingsExit`, có test). Heap dump tìm ra **rò thật**: Play Billing (hẹn giờ nối lại) → store → lambda → `MainActivity` sống thêm ~2–3 phút; PowerManager lấy từ activity cũng giữ activity. Sửa (WeakReference, `endConnection` ở onDestroy, applicationContext) ⇒ 0 instance ngay khi rời app. **Nhưng PSS vẫn +15 MB** (Dalvik heap chưa trim + malloc/HWUI giữ trang + .art/.oat Compose): process IME ở oom_adj 100 không được ART trim heap — chỉ tách process `:settings` mới trả hết (phải làm lại đồng bộ prefs, chưa làm).
- **#6** hẹn giờ ẩn 45 s (`IDLE_RELEASE_MS`): nhả FUTO, từ điển Anh (1.4 MB), template vuốt, ảnh nền, String emoji, bảng clipboard, cache mẫu câu; hiện lại ⇒ nạp lại trên luồng `vt-rewarm` ưu tiên thấp (không chen hàng đợi gợi ý; ảnh nền hiện lại sau < 1 s, đã chụp màn hình kiểm). Heap sống lúc `hidden-idle` (all) 7.5 → 3.2 MB; PSS chỉ về khi ART trim heap (trim-bg).
- `hprof-summary.py --path` bỏ cạnh `Reference.referent` (WeakHashMap$Entry…) — trước đó có thể in đường giả qua tham chiếu yếu.

## 10/11/2026 — #7 từ điển Anh tại chỗ + main thread không nạp + SoundPool giữ qua lần ẩn

**Từ điển Anh (enlexicon.bin, 20 059 từ) — đọc tại chỗ.** Định dạng file **không đổi** (iOS đọc cùng file). `SwipeEnglish.Lexicon` chỉ giữ `IntArray` vị trí từng mục; `contains`/`indexOf`/`completions` tìm nhị phân so byte ASCII ngay trên buffer mmap, String chỉ dựng cho từ trả ra; sửa chính tả (`EnglishAssist.corrections`) đọc qua một `CharSequence` dùng lại. Bảng riêng gõ vuốt (`keys`/`keyStart`/`order`/`bucketStart`/`freq`) thành `Lexicon.swipe`, dựng lười khi decoder vuốt tiếng Anh cần (vuốt tiếng Anh tắt ⇒ không dựng — có test).

Số đo JVM (`VT_SLOW_TESTS=1 … --tests '*RamFootprintTests.englishLexiconInPlace' -i | grep RAM`, 2 lần chạy cho cùng số heap; JVM ≈ ART ±15 % như trên):

| | Giữ lại | Cấp phát lúc nạp | Nạp (JVM, đã JIT) |
|---|---|---|---|
| Cũ: ~20k String + bảng vuốt | 1 435.9 KB | 1.91 MB | 0.61–1.30 ms |
| Mới: chỉ vị trí (mọi phiên có gợi ý) | **78.5 KB** | 0.08 MB | 0.08–0.17 ms |
| Mới: + bảng vuốt (chỉ khi vuốt tiếng Anh bật) | +374.5 KB | +0.66 MB | +0.29–0.52 ms |

`indexOf` (JVM): 132–141 → 187–193 ns (so byte qua ByteBuffer thay vì String.compareTo — vẫn dưới 0.2 µs). Thời gian nạp trên máy thật dài hơn JVM nhiều lần (ghi chú cũ: hàng chục ms cho bản String) — chưa đo lại trên máy.

**Parity** (`EnglishLexiconInPlaceTests`, so với bản cũ giữ nguyên văn trong test): từ + tần suất từng mục, `indexOf` cho mọi từ và ~6 biến thể mỗi từ (thêm/bớt chữ, hoa, ký tự ngoài ASCII), `completions` cho mọi tiền tố 1–3 chữ + mọi tiền tố của 1/7 từ (> 5 000 tiền tố × 2 giới hạn), `topWords`, `corrections` trên > 1 000 lỗi gõ, bảng vuốt byte-bằng, blob hỏng bị từ chối như cũ.

**Main thread không bao giờ nạp từ điển Anh.** Trước: tô nền sửa (bật cùng gợi ý) → `completeSuggestions` (main) → `AutoCorrect.isEnglish` → `SwipeEnglish.contains` ⇒ từ 3 chữ (EnglishAssist chỉ từ 4 phím nên worker chưa nạp) parse trên main, lặp lại sau mỗi lần nhả 3 phút. Giờ:
- `AutoCorrect.isEnglish` tra bảng hằng `opensEnglishRun` trước (OR thuần — cùng kết quả, có test trên 1/5 từ điển).
- Main dùng `AutoCorrect.isEnglishIfLoaded` (không nạp). **Chưa nạp ⇒ coi là từ đã biết ⇒ không sửa** — chỉ có thể bỏ lỡ một lần sửa, không bao giờ sửa nhầm từ tiếng Anh sang tiếng Việt (ô tô nền và dấu cách vẫn cùng một quyết định).
- Worker nạp trước khi main cần: `SuggestJob.compute()` khi có plan sửa; IME lúc hiện khi bật Tự sửa ở dấu cách (thanh gợi ý có thể tắt); luồng `vt-rewarm` sau nhả.
- Còn lại (không đổi): `SwipeVocab.setShortcuts` lúc hiện khi bật gõ vuốt + gõ tắt vẫn gọi `contains` trên main — giờ chỉ là dựng vị trí (0.08–0.17 ms JVM, 0.08 MB).

**Âm phím: SoundPool giữ qua các lần ẩn.** Trước: ẩn ⇒ `release()`, hiện ⇒ dựng SoundPool mới + nạp lại mọi mẫu (3–7 file; Piano / Đàn tranh / Ghi-ta ~30 file ≈ 1–1.6 MB PCM), phím đầu im tới khi nạp xong. Giờ: ẩn ⇒ `Feedback.onHidden()` dừng stream đang kêu (nốt ngân, sóng vỗ, rồi `autoPause` cho phần còn lại) và giữ mẫu; hiện lại cùng kiểu ⇒ **0 lần nạp** (`FeedbackPoolLifecycleTest`, cả kiểu thường lẫn Piano). SoundPool không xin audio focus / wake lock; hết stream active thì đường ra âm thanh về standby như khi không có pool. Nhả hẳn ở `releaseIdle()` (hẹn giờ ẩn 3 phút, `onTrimMemory` BACKGROUND+ khi đang ẩn, `onLowMemory` mới thêm), đổi kiểu âm, tắt âm.

**SwipeVocab.cache** (Vocab vuốt đã dựng — static) giờ cũng bỏ ở `releaseIdle()` cùng decoder vuốt; dựng lại y hệt (có test).

## Đợt 10/11/2026 — Bạn đồng hành, người nhảy Night Club, skin theme, hiệu ứng phím (song sinh iOS cùng ngày)

Audit đọc mã (không emulator). Số dưới đây đo bằng test Robolectric (bitmap ARGB_8888 giải thật từ asset) và APK debug đóng gói lại từ đầu; số trên máy thật (texture GPU, PSS) **chưa đo**.

| # | Vấn đề | Sửa | Đo / kiểm |
|---|---|---|---|
| 1 | CPU lúc nghỉ: koi ngủ vẽ lại mỗi 160 ms (bong bóng) vô hạn — kể cả trước phím đầu; Tết Thiếu nhi vẽ lại mỗi 80 ms cả ngày; Hoạt hình lắc nghỉ vẽ lại mỗi 50–80 ms dù khung chỉ đổi mỗi 0,8 s | `BuddyIdleMotion` (= iOS, cùng số): bong bóng koi chỉ sau phím đầu của lần hiện, 3 bong bóng × 3 nhịp × 2,4 s (tan hết sau 8,8 s); bóng bay nhún 3 nhịp × 2 s từ lúc hiện rồi đứng yên. Lắc nghỉ / cổ vũ Hoạt hình: hẹn MỘT lần vẽ ở mốc đổi khung kế (`BuddySprites.nextFrameDelay`). Nhảy / phản ứng / chữ ký vẫn từng khung | `BuddyIdleMotionTests`, `BuddyViewIdleTest`: koi chưa gõ 120 s ⇒ 0 khung đòi vẽ; sau 8,8 s ngủ ⇒ 0; bóng bay sau 6 s ⇒ 0; lắc nghỉ hẹn đúng +0,8 s |
| 2 | Người nhảy Night Club giải trọn 1536×1024 (6,3 MB) để hiện một ô; **lỗi**: hẹn giờ ẩn `dropWallpaper()` (và `onDestroy`) gọi `setPhoto(null)` ⇒ GIẢI người nhảy đúng lúc bàn phím đang ẩn | `SpotlightView.release()` (bỏ atlas + tham chiếu ảnh nền, không giải; đổi cỡ lúc ẩn cũng không giải), `resume()` trên `vt-rewarm` lúc hiện lại. Trần @2x như iOS (`NightDancer.MAX_DECODE_SCALE`); `decodePlan`: lấy mẫu rồi **thu đúng cạnh** (inDensity/inTargetDensity) — KHÔNG lấy mẫu 2 (768 px): dưới đèn rọi người nhảy hiện màu thật, ô 256 px phóng ~2,3–2,6× nhoè rõ. Cửa sổ vẽ GPU ⇒ `Bitmap.Config.HARDWARE` như ảnh nền (canvas phần mềm bỏ qua người nhảy, test dùng bản CPU) | bàn phím 780 px @3x (ô 221 dp): **6 291 456 → 4 688 736 B** (1326×884); máy @2,625 cũng 1326 px. HARDWARE bỏ thêm bản CPU ở native (chưa đo trên máy). `NightDancerViewTest`, `IdleAtlasReleaseTest.nightClubIdleReleaseDoesNotDecodeDancer` / `destroyDoesNotDecodeDancer` |
| 3 | Atlas Bạn đồng hành giải trên main trước khung đầu (mở asset hai lần, inflate cả PNG 1,3–2 MB); `LruCache` 3 MB cấp process giữ tới 2 atlas suốt đời process, kể cả khi tắt nhân vật | Giải trên luồng `vt-buddy` (ưu tiên thấp); `onCreate` giải sẵn khi đang bật Hoạt hình ⇒ khung đầu thường đã có ảnh; chưa xong ⇒ ô TRỐNG (không lóe vector rồi nhảy sang ảnh), lỗi ⇒ vector như cũ. Cache MỘT bản; tắt / Mắt AI / Vẽ nét ⇒ bỏ; hẹn giờ ẩn ⇒ view nhả + bỏ cache, `vt-rewarm` giải lại | `IdleAtlasReleaseTest.companionOffEmptiesAtlasCache` / `idleReleaseDropsCompanionAtlasAndShowReloads`, `BuddyViewIdleTest` |
| 4 | 4 atlas gốc 1,3–2,0 MB trong APK dù Bạn đồng hành không bao giờ giải trên 512 px | Đóng gói CHÍNH tệp iOS `buddy-<id>-v2-512.png` (byte-y-hệt, test chốt); bỏ bản gốc mèo + gà con (Night Club chỉ dùng cô gái / chàng trai). Nguồn chuẩn ảnh gốc: `assets/companion/` (script iOS đọc từ đó, chạy lại ra đúng byte cũ) | APK debug đóng gói lại từ đầu: **24 407 164 → 22 081 411 B (−2 325 753 B)**; asset PNG lưu không nén ⇒ bản release giảm tương đương. Atlas giữ trong RAM: cô gái 512×341 = **698 368 B** (trước 384×256 = 393 216 B do lấy mẫu 4 — +0,3 MB để cùng điểm ảnh iOS, nét hơn ở ô ~170 px), mèo 512×256 = 524 288 B; dữ liệu nén phải inflate mỗi lần giải 1,99 MB → 196 KB (cô gái) |
| 5 | Skin + phông theme tải về: `ThemeAssetLoader.dropCache()` không ai gọi ⇒ đổi sang theme không tệp vẫn giữ tới khi process chết | `ImeTheme.assets` của theme không tệp gọi `dropCache()` | `IdleAtlasReleaseTest.themeWithoutAssetsDropsSkinCache` |
| 6 | Ảnh dựng sẵn của hiệu ứng phím (dải Matrix, emoji, cá Biển, chữ theme) giữ khi ẩn | `KeyEffectView.releaseIdle()` trong hẹn giờ ẩn, `rewarm()` lúc hiện (luồng nền như lần đầu chọn kiểu) | `IdleAtlasReleaseTest.keyEffectPrerenderedBitmapsReleasedAndRebuilt` |

- **Không làm**: nhả skin theme ở hẹn giờ ẩn. `KeyboardView` / `BalloonView` giữ CHÍNH các Bitmap skin để vẽ phím ⇒ bỏ cache không trả byte nào khi cây view còn sống, mà lần dựng lại view kế (xoay máy) lại phải giải trên main; nhả thật thì lúc hiện lại phím vẽ màu theme tới khi giải xong (thấy thiếu ảnh) — trái luật "không để người dùng thấy ảnh thiếu, không chặn khung đầu".
- Nhảy Hoạt hình vẫn vẽ mỗi 50–80 ms: chữ ký nhảy đổi theo vòng điệu (không trùng mốc khung) — chỉ lắc nghỉ / cổ vũ hẹn theo mốc khung.
- Phần nhả theo view gom vào `ImeRootView.dropWallpaper()` / `reloadWallpaper()` (đã có cờ nạp lại `vt-rewarm`); `releaseIdle()` chỉ thêm một dòng bỏ cache atlas cấp process.
