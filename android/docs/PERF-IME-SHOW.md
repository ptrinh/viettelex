# Thời gian hiện bàn phím Android — đo, ngân sách, cách giữ không chậm đi

Mục tiêu: khung hình đầu có phím xuất hiện càng sớm càng tốt (mở lạnh lẫn mở ấm), gõ không ghi lại
lưới phím. Phần hệ thống giữ (bind IME, hoạt ảnh trượt lên ~200–285 ms) không tối ưu được — chỉ phần
từ `IME.onCreate` / `onStartInputView` tới lượt vẽ đầu là của mình.

Hai lớp bảo vệ:

1. **Ngân sách việc (tất định, chạy trong unit test mặc định)** — `app/src/test/.../ImeRenderBudgetTest.kt`
   chạy `VietTelexIME` thật trên Robolectric và ĐẾM việc: số cây view, số lần dựng theme / bố cục,
   asset văn bản giải trên main, lưới phím có bị làm bẩn khi gõ / khi badge chạy không, byte cấp phát
   mỗi lượt vẽ / mỗi lần chạm. Không đo giờ ⇒ không chập chờn.
2. **Thời gian thật (thủ công, emulator / máy thật)** — module `:benchmark` (Macrobenchmark) đọc mốc
   Perfetto `VT.*` của IME và `Host.*` của app chủ `:perfhost`. Không nằm trong `./gradlew test`.

## Đối chiếu khuyến nghị (báo cáo "Giảm thời gian hiện bàn phím", 11/2026)

| # | Khuyến nghị | Trạng thái | Ở đâu |
|---|---|---|---|
| 1 | `Application`/ContentProvider gần rỗng | **Làm** — không có Application; `InitializationProvider` (emoji2, lifecycle, profileinstaller) dời sang process `:settings` | `AndroidManifest.xml` |
| 2 | Làm nóng nền, `onCreateInputView` không chờ từ điển | Đã có phần lớn (model học nạp io, asset mmap, clipboard/TelexKeyPrior trên worker); **làm thêm**: seed người dùng mới parse trên io | `UserLangModel.seedIfEmpty` |
| 3 | Mở ấm gần như không làm gì | Đã có (giữ cây view, theme chỉ dựng khi prefs/uiMode đổi); **sửa**: mở lạnh không dựng theme 2 lần, giao diện EN không dựng cây view 2 lần | `VietTelexIME.createInputView` |
| 4 | `android:configChanges` trên `<input-method>` | **Bỏ qua** — ImeTheme giữ `landscape/tablet` lúc dựng; tự xử lý xoay/đổi cỡ cần rà lại cả theme + insets, rủi ro sai bố cục | — |
| 5 | Cache bố cục nhiều tầng, nhãn đo sẵn | Đã có cache theo plane + offset nhãn tính sẵn; **làm thêm**: LRU 4 chữ ký × plane | `KeyboardView.layoutCache` |
| 6 | Baseline/Startup Profile + ProfileInstaller | **Làm** — `baseline-prof.txt` sinh từ đường hiện/gõ; nâng profileinstaller 1.3.1 → 1.4.1 (bản cũ không cài profile trên API 34+) | `app/src/main/baseline-prof.txt`, `ImeBaselineProfile` |
| 7 | Lưới phím tĩnh tách khỏi trạng thái nhấn | Đã có cho phím chữ (overlay balloon); **làm thêm**: lưới trong RenderNode, nội dung phím cách là lớp động | `KeyboardView.gridNode` |
| 8 | Không cấp phát trong onDraw/chạm | Đã đạt (0 B mỗi lượt vẽ; ~1,5 KB mỗi phím gồm cả engine) — nay có test chặn | `ImeRenderBudgetTest` |
| 9 | Balloon/popup dựng sẵn, tái dùng | Đã có (một BalloonView vẽ mọi popup) | `BalloonView` |
| 10 | Icon/drawable ngoài main, hình đơn giản | Đã có (Path dựng một lần, vẽ Canvas); ảnh nền người dùng vẫn giải đồng bộ lúc đo kích thước — **bỏ qua** (đổi sang nền sẽ lóe nền màu trước ảnh) | `ImeIcons`, `ImeRootView.loadWallpaperFor` |
| 11 | Không Compose trên đường khung đầu | Đã có (IME không dùng Compose; app cài đặt process riêng) | — |
| 12 | StrictMode bản debug | **Làm** — log đọc/ghi đĩa trên main | `VietTelexIME.createService` |

## Mốc Perfetto (`ImeTrace`)

| Mốc | Loại | Từ → tới |
|---|---|---|
| `VT.onCreate` | đồng bộ | `IME.onCreate` |
| `VT.onCreate.data` / `.session` / `.state` / `.listeners` | đồng bộ | các khúc của `onCreate` (prefs + asset; UserLangModel + session; prefs trạng thái + clipboard; listener/receiver) |
| `VT.onCreateInputView` | đồng bộ | dựng cây view bàn phím |
| `VT.onStartInputView` | đồng bộ | cấu hình ô nhập + bàn phím |
| `VT.startInput.field` / `.kbConfigure` / `.refreshBar` | đồng bộ | các khúc của `onStartInputView` |
| `VT.showToFirstDraw` | async (cookie 1) | đầu `onStartInputView` → lượt vẽ đầu của lưới phím |
| `VT.coldToFirstDraw` | async (cookie 2) | `IME.onCreate` → lượt vẽ đầu (chỉ lần hiện đầu của service) |
| `VT.kbDraw` | đồng bộ | `KeyboardView.onDraw` |
| `VT.layoutBuild` | đồng bộ | `KeyLayout.build` (lỡ cache bố cục) |
| `VT.planeSwitch` | đồng bộ | đổi bảng phím (chữ ↔ ?123 …) |
| `VT.onKey` | đồng bộ | xử lý một phím (session + IcProxy) |
| `VT.keyToDraw` | async (cookie 3) | ACTION_DOWN → lượt vẽ kế của bất kỳ view bàn phím nào |
| `Host.imeShowToAnimStart` | async, app chủ | `show(ime())` → `WindowInsetsAnimation.onStart` (khuôn AOSP ImePerfTest) |
| `Host.imeShowToAnimEnd` | async, app chủ | `show(ime())` → `onEnd` (gồm hoạt ảnh của hệ thống) |

Chi phí khi không ghi trace: một lần đọc `Trace.isEnabled()` mỗi mốc, không cấp phát. Manifest có
`<profileable android:shell="true"/>` ⇒ đọc được trên bản release (API 29+).

## Đo bằng Macrobenchmark (một lệnh)

```sh
cd android
~/ClaudeCode/tools/cpu-gate.sh
./gradlew --max-workers=2 :app:assembleBenchmark :perfhost:assembleBenchmark :benchmark:assembleBenchmark
Scripts/ime-perf.sh [OUT_DIR] [TEST_FILTER] [ITERATIONS=10] [none|partial|full]
#   vd: Scripts/ime-perf.sh build/ime-perf/now com.viettelex.benchmark.ImeShowBenchmark#showCold 10 partial
#   APP_APK=đường/dẫn.apk Scripts/ime-perf.sh …   ⇒ đo một APK bàn phím khác (so A/B cùng máy, liền nhau)
```

Script cài 3 APK (bản đo của bàn phím = như release, R8, ký debug; app chủ; module test), chạy
`am instrument` trực tiếp (không giữ Gradle suốt ~15 phút đo — `./gradlew --stop` của phiên khác giết
cả lần đo), kéo kết quả về và in min/median/max từng mốc. Cũng chạy được qua Gradle:
`./gradlew :benchmark:connectedBenchmarkAndroidTest -Pandroid.testInstrumentationRunnerArguments.vt.iterations=10`
(lưu ý AGP gỡ app chủ sau khi chạy).

Kết quả: `OUT_DIR/com.viettelex.benchmark-benchmarkData.json` + một `.perfetto-trace` mỗi vòng (mở ở ui.perfetto.dev).

| Test | Đo |
|---|---|
| `showCold` | process IME vừa bị giết (force-stop) → chọn lại IME + `show(ime())` trong khối đo: `VT.onCreate`, `VT.onCreateInputView`, `VT.onStartInputView`, `VT.showToFirstDraw`, `Host.*` |
| `showWarm` | ẩn rồi hiện lại khi process + cây view còn sống |
| `typing` | 20 chạm phím chữ: `VT.keyToDraw` (avg), `VT.onKey` (avg), số `VT.kbDraw` (lưới vẽ lại), `FrameTimingMetric` của process IME |
| `planeSwitch` | 6 lần ?123 ↔ chữ: `VT.planeSwitch`, số `VT.layoutBuild`, `FrameTimingMetric` |

Ghi chú khi đo:
- App ĐÍCH của Macrobenchmark là chính bàn phím (`com.viettelex.android`) ⇒ `CompilationMode` áp cho IME,
  `FrameTimingMetric` là khung của process IME. `TraceSectionMetric(targetPackageOnly = false)` dùng cho
  mốc `Host.*` của app chủ. Cấu hình Perfetto bật `atrace_apps` cho cả hai gói.
- Force-stop bàn phím ĐANG CHỌN làm hệ thống tự đổi sang bàn phím khác ⇒ test chọn lại VietTelex mỗi vòng
  (`ime set`). Ở `showCold` lệnh chọn lại nằm TRONG khối đo, nên process bàn phím khởi động đúng lúc người
  dùng chạm ô (như thật) và `Host.imeShowToAnimStart` gồm cả bind.
- Emulator: chỉ so trước/sau trên CÙNG máy ảo, cùng lúc máy host rảnh (`cpu-gate.sh`). Số tuyệt đối (nhất là
  `frameDurationCpuMs` với GPU giả lập swiftshader) không đại diện máy thật.
- `planeSwitch` chạm theo toạ độ (phím ?123 góc dưới-trái) — thỉnh thoảng một vòng không bắt được khung nào
  và FrameTimingMetric báo lỗi; chạy lại test đó.

## Đo tay bằng Perfetto / atrace (không cần module benchmark)

```sh
adb shell ime set com.viettelex.android/.ime.VietTelexIME
# lạnh: giết process bàn phím (hệ thống đổi IME) rồi chọn lại ngay trước khi chạm ô
adb shell am force-stop com.viettelex.android; adb shell ime set com.viettelex.android/.ime.VietTelexIME
adb shell atrace -a com.viettelex.android -t 5 wm view gfx input am dalvik sched > ime.atrace &
# chạm vào một ô nhập trong 5 s, rồi:
grep -o 'VT\.[A-Za-z]*' ime.atrace | sort | uniq -c
```

Hoặc Perfetto UI / `record_android_trace` với `atrace_categories: wm view gfx input am dalvik` và
`atrace_apps: "com.viettelex.android"`; lọc slice `VT.%`. Cold = lần hiện đầu sau force-stop (có
`VT.onCreate`, `VT.onCreateInputView`); warm = ẩn/hiện lại (chỉ `VT.onStartInputView` + `VT.kbDraw`).
Mốc framework đi kèm: `IMS.onCreate`, `IMS.initializeInternal`, `IMS.showWindow`, `IMMS.showSoftInput`
(category `wm`), như AOSP ImePerfTest.

## Ngân sách (ImeRenderBudgetTest)

Chạy: `./gradlew --max-workers=2 :app:testDebugUnitTest --tests '*ImeRenderBudgetTest*'` (nằm sẵn trong
bộ unit test mặc định, ~6 s). Số đo hiện tại in ra stdout (`BUDGET …`). Đã kiểm ngược: áp các test này lên code trước tối ưu thì 4 test đỏ
(theme 2 lần, cây view 2 lần với giao diện tiếng Anh, 3 lần dựng bố cục, `seed.tsv` giải trên main).

| Test | Kiểm | Trần | Hiện tại |
|---|---|---|---|
| `coldOpenBuildsOneTreeOneThemeOneLayout` | mở lạnh: `onCreateInputView`, ImeTheme, `KeyLayout.build`, số view | 1 / 1 / 1 / ≤ `Budget.VIEWS` = 6 | 1 / 1 / 1 / 5 (trước: theme dựng 2 lần) |
| `coldOpenWithEnglishUiBuildsTreeOnce` | giao diện tiếng Anh: cây view + theme dựng một lần | 1 / 1 | 1 / 1 (trước: cây view dựng 2 lần) |
| `coldOpenDecodesNoTextAssetOnMain` | không `KeyboardData.text()` trên main trước khung đầu | 0 | 0 (trước: `seed.tsv`) |
| `warmReopenRebuildsNothing` | ẩn rồi hiện: giữ cây view, 0 theme, 0 bố cục | 0 / 0 / 0 | 0 / 0 / 0 |
| `alternatingFieldsServeLayoutsFromCache` | chat ↔ tìm kiếm lần 2: 0 bố cục, 0 cây view | 0 / 0 | 0 / 0 (trước: 3 lần dựng bố cục) |
| `planeSwitchBuildsEachPlaneOnce` | 3 vòng chữ ↔ ?123: dựng ?123 một lần | 1 | 1 |
| `letterKeypressDoesNotDirtyKeyGrid` | gõ "nhanh" + auto-shift + gợi ý: `KeyboardView` không bẩn | sạch | sạch |
| `spaceBadgeAnimationKeepsGridClean` | badge "ViệtTelex": view vẽ lại nhưng lưới tĩnh không ghi lại | sạch | sạch (trước: ghi lại cả lưới ~20 khung mỗi lần hiện) |
| `shiftChangeDirtiesGrid` | đối chứng: shift đổi ⇒ lưới PHẢI ghi lại | bẩn | bẩn |
| `keyGridRedrawAllocatesNothing` | byte cấp phát mỗi lượt vẽ lưới (trừ chi phí `View.draw`) | `Budget.DRAW_ALLOC_BYTES` = 0 | ≤ 0 |
| `letterKeypressAllocationBudget` | byte cấp phát một lần chạm-nhả phím chữ (đường chạm + session + IcProxy) | `Budget.KEYPRESS_ALLOC_BYTES` = 3 000 | 1 560 |

Liên quan: `keyboard/.../UserLMSeedAsyncTests.kt` (seed người dùng mới parse trên io, không chặn
`onStartInputView`).

**Quy trình nâng ngân sách** (khi một test đỏ):
1. Đọc thông báo — nó nói việc gì vượt trần.
2. Vô tình (đa số) ⇒ sửa code: dời việc ra sau khung đầu, sang worker, hoặc dùng cache.
3. Cố ý (tính năng mới thật sự cần) ⇒ nâng hằng số trong `ImeRenderBudgetTest.Budget` (hoặc số kỳ vọng
   trong test) TRONG CÙNG commit, ghi lý do vào commit message và cập nhật bảng trên. Kèm số đo
   Macrobenchmark trước/sau nếu thay đổi đụng đường hiện bàn phím.

## Baseline Profile

`benchmark/.../ImeBaselineProfile.kt` sinh profile cho đường hiện + gõ + đổi bảng phím:

```sh
./gradlew --max-workers=2 :app:assembleBenchmarkProfile :perfhost:assembleBenchmark :benchmark:assembleBenchmark
adb install -r app/build/outputs/apk/benchmarkProfile/app-benchmarkProfile.apk   # KHÔNG R8: luật mang tên gốc
adb install -r perfhost/build/outputs/apk/benchmark/perfhost-benchmark.apk
adb install -r -t benchmark/build/outputs/apk/benchmark/benchmark-benchmark.apk
adb shell am instrument -w -e class com.viettelex.benchmark.ImeBaselineProfile -e vt.genProfile 1 \
  -e androidx.benchmark.suppressErrors EMULATOR \
  -e additionalTestOutputDir /sdcard/Android/media/com.viettelex.benchmark/additional_test_output \
  com.viettelex.benchmark/androidx.test.runner.AndroidJUnitRunner
adb pull /sdcard/Android/media/com.viettelex.benchmark/additional_test_output/ImeBaselineProfile_generate-startup-prof.txt \
  app/src/main/baseline-prof.txt
```

Sinh lại khi đường hiện / gõ đổi nhiều (lớp mới, đổi tên): luật cũ không gây hại, chỉ bớt tác dụng.
Cần API 33+ (emulator google_apis được, không cần root).

AGP đóng profile vào APK/AAB; Play dùng nó khi cài; bản APK ngoài Play được ProfileInstaller cài
(chạy trong process `:settings` lúc mở app cài đặt lần đầu). So hiệu quả: `showCold` với
`vt.compilation=none` và `vt.compilation=partial`.

## Kết quả

Emulator `vt_perf` (AVD API 35 google_apis arm64, 1080×2400 @420 dpi, 4 nhân, GPU swiftshader), máy host
Apple Silicon dùng chung với phiên khác. **Số emulator — chỉ so tương đối.** 10 vòng mỗi test,
`CompilationMode.None` (mới cài, chưa biên dịch trước), median (min–max), ms. "Trước" = code gốc + cùng
mốc đo (bản đo dựng riêng, chỉ bỏ các tối ưu), đo liền trước "Sau" trên cùng máy ảo (07/11/2026).

| Mốc | Trước | Sau |
|---|---|---|
| cold `VT.onCreate` | 7.4 (4.8–13.0) | 7.3 (5.3–14.5) |
| cold `VT.onCreateInputView` | 4.5 (3.7–9.2) | 4.0 (3.6–8.6) |
| cold `VT.onStartInputView` | **21.5** (4.3–28.9) | **8.8** (5.1–29.0) |
| cold `VT.showToFirstDraw` (onStartInputView → phím vẽ) | **58.7** (43.5–96.9) | **41.8** (35.0–65.9) |
| cold `Host.imeShowToAnimStart` (gồm bind + process mới) | 137 (114–197) | 132 (111–149) |
| cold `Host.imeShowToAnimEnd` | 454 (431–514) | 449 (428–466) |
| warm `VT.onStartInputView` | 10.1 (6.4–2111*) | 12.9 (8.3–24.7) |
| warm `VT.showToFirstDraw` | 24.1 (15.3–3143*) | 22.2 (15.2–37.0) |
| warm `Host.imeShowToAnimStart` | 63.0 (44.7–3769*) | 49.8 (44.8–50.5) |
| gõ: `VT.kbDraw` (lưới vẽ lại khi gõ chữ) | 0 | 0 |
| gõ: `VT.onKey` avg | 0.09 | 0.15 |
| gõ: `frameDurationCpuMs` P50 / P90 / P99 (process IME) | 8.4 / 18.6 / 48.8 | 6.3 / 11.7 / 13.9 |
| gõ: `frameOverrunMs` P90 / P99 | 10.6 / 34.0 | 0.4 / 1.9 |

\* một vòng bị máy host chen (GC/IO), không phải hồi quy.

Đọc: phần cải thiện rõ là `onStartInputView` lúc mở lạnh (bỏ dựng ImeTheme lần hai) kéo theo
`showToFirstDraw` ~−17 ms; khung hình khi gõ đều hơn (badge mờ dần + nhãn phím cách không còn ghi lại
cả lưới phím mỗi khung). `onCreate` gần như không đổi trong mốc của mình — phần provider androidx.startup
bỏ đi nằm TRƯỚC `IME.onCreate` (lúc process khởi động), lẫn vào `Host.imeShowToAnimStart` và nhiễu của
emulator. `keyToDraw` (~13–16 ms) chủ yếu là chờ vsync kế, không phải việc của bàn phím. Hoạt ảnh trượt
lên của hệ thống (`imeShowToAnimEnd − imeShowToAnimStart` ≈ 315 ms) không đổi được.

Lần đo đầu (trước khi có A/B) máy host tải 15–27 nên số cold khi đó gấp 3–10 lần (onCreate 125 ms,
showToFirstDraw 500 ms) — luôn chạy `cpu-gate.sh` và so A/B liền nhau.

### Baseline Profile (cùng APK, `vt.compilation=none` vs `partial`, 10 vòng, median ms)

| Mốc | none | partial (profile) |
|---|---|---|
| cold `VT.onCreate` | 10.6 | 5.1 |
| cold `VT.onCreateInputView` | 4.6 | 3.0 |
| cold `VT.onStartInputView` | 10.6 | 19.2 |
| cold `VT.showToFirstDraw` | 46.6 | 54.6 |
| cold `Host.imeShowToAnimStart` / `AnimEnd` | 124.5 / 441.7 | 121.9 / 438.6 |
| gõ `frameDurationCpuMs` P90 | 11.8 | 11.8 |

Trên emulator kết quả **chưa kết luận được**: `onCreate`/`onCreateInputView` nhanh hơn rõ, `onStartInputView`
lại chậm hơn (khoảng min–max chồng nhau, emulator dịch ARM trên máy dùng chung), tổng tới lúc hoạt ảnh bắt
đầu gần như bằng nhau. Cần đo lại trên máy thật trước khi kết luận. Việc chắc chắn có ích là nâng
profileinstaller lên 1.4.1: bản 1.3.1 kéo theo trước đây từ chối cài profile trên API 34+, nên APK ngoài Play
trên Android 14+ chưa bao giờ được biên dịch trước (kể cả profile của thư viện).
