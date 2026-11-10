# Thời gian hiện bàn phím iOS — đo, đọc số, ngân sách render

Mục tiêu: bàn phím hiện nhanh (init controller → khung đầu có phím) và mỗi phím rẻ. Tài liệu
này nói cách ĐO trên máy thật, cách ĐỌC số (lạnh / ấm), và bộ test chặn hồi quy.

Phần hệ thống KHÔNG giảm được: iOS đổi khung view bàn phím vài lần lúc hiện (0×0 → cả màn hình
→ … → chiều cao cuối, ~390 ms tới khi ổn định — Apple Forums 813579) rồi chạy hoạt ảnh trượt
lên. Phần của mình: từ lúc tiến trình / controller khởi tạo tới khung đầu có phím, cộng chi phí
mỗi phím.

## 1. Signpost trong extension

Subsystem `com.viettelex.ios.keyboard`, hai nguồn:

| Category | Loại | Tên | Ý nghĩa |
|---|---|---|---|
| `DynamicTracing` (FrameTrace) | khoảng | `appear` | init controller (hoặc viewWillAppear khi cùng controller hiện lại) → commit Core Animation của khung đầu có phím. Thông điệp mở: `cold` (controller đầu tiên của tiến trình) / `warm` / `reshow`. |
| | khoảng | `key` | controller nhận phím → commit khung có kết quả phím đó |
| | khoảng | `plane` | đổi mặt phím (ABC / 123 / #+= / emoji…) → commit |
| | mốc | `vc.init`, `viewDidLoad`, `viewWillAppear`, `viewDidAppear` | vòng đời controller |
| | mốc | `height` | mỗi lần chiều cao view gốc đổi (thông điệp `rộng x cao`) — thấy chuỗi kích thước host gửi |
| `startup` (StartupTrace) | khoảng | `installKeyboard`, `willAppear`, `fieldTraits`, `buildKeys`, `kv.rebuild`, `kv.layout`, `kv.applyAppearance`, `keySound`, `postFrame`, `warmUpData`, `suggestions`, `lexicons`… | từng bước bên trong lần hiện |
| | khoảng | `prewarm` | nạp nền SF Symbols / phông (thread nền) |

Chi phí khi KHÔNG ghi: category `DynamicTracing` tắt mặc định — mỗi lời gọi chỉ đọc cờ
`isEnabled` (không observer, không cấp phát), nên `key` nằm được trên đường mỗi phím.
"Commit" = lúc cây layer đã gửi cho render server (observer ngay sau commit CA, cùng order với
`PostFrameWork`); phần render server + màn hình + độ trễ chạm KHÔNG nằm trong số này (cần
Animation Hitches hoặc quay video 240 fps nếu muốn cả chuỗi).

## 2. Ghi trên máy thật (Release)

Luôn đo bản **Release** trên **máy thật** (Debug chậm hơn nhiều và lệch tỉ lệ giữa các bước).

**Instruments (GUI)**: Product → Profile (scheme VietTelexApp, Release) → template *Blank* → thêm
*os_signpost* (+ *Time Profiler*, *Animation Hitches* nếu cần) → Target: *All Processes* (extension
chưa chạy nên không attach trước được) → Record → mở app có ô nhập, chạm ô nhập nhiều lần (ẩn/hiện).
Lọc subsystem `com.viettelex.ios.keyboard`.

**xctrace (dòng lệnh)**:

```sh
# Liệt kê thiết bị
xcrun xctrace list devices
# Ghi 60 s mọi tiến trình (máy thật: --device <UDID>; simulator cũng được)
xcrun xctrace record --device <UDID> --instrument os_signpost --all-processes \
    --time-limit 60s --output ~/Downloads/Temp/kb-appear.trace
# Xuất bảng signpost (khoảng) ra XML
xcrun xctrace export --input ~/Downloads/Temp/kb-appear.trace \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost-interval"]' \
    > ~/Downloads/Temp/kb-intervals.xml
python3 iOS/Scripts/signpost-summary.py ~/Downloads/Temp/kb-intervals.xml
```

`iOS/Scripts/signpost-summary.py` gom các khoảng của subsystem bàn phím theo tên (+ thông điệp
mở cho `appear`): số lần, trung vị, P90, max.

Signpost category `DynamicTracing` chỉ được ghi khi bật subsystem: **luôn kèm
`--recording-options iOS/Scripts/keyboard-signposts.json`** (GUI: os_signpost → Recording
Options → Dynamic Subsystems → thêm `com.viettelex.ios.keyboard`). Thiếu nó chỉ thấy khoảng
`startup`, không thấy `appear` / `key` / `plane`.

**Simulator (ngoài tiến trình, không cần chạm tay)**: cài bản Release của VietTelexApp + app chủ
`iOS/Scripts/ram-audit/Host` (`xcodegen generate --spec iOS/Scripts/ram-audit/project.yml …`,
scheme RamHost); bật bàn phím không qua Cài đặt:

```sh
D=<SIM_UDID>
xcrun simctl spawn $D defaults write .GlobalPreferences AppleKeyboards -array \
  com.viettelex.ios.keyboard "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji"
xcrun simctl spawn $D defaults write com.apple.Preferences KeyboardLastUsed com.viettelex.ios.keyboard
```

rồi ghi như trên và `xcrun simctl launch $D com.viettelex.ramdrv.host -autocycle 12` (ẩn/hiện
12 lần, 1,5 s mỗi pha; giết tiến trình extension trước để lần đầu là lạnh). Nếu `xctrace record`
treo lúc lưu, bọc bằng `perl -e 'alarm 120; exec @ARGV' xcrun xctrace record …` và chạy lại.

**Cách tạo lần mở lạnh / ấm**

- *Lạnh* (cold): tiến trình extension chưa chạy. Trên máy: đổi sang bàn phím khác rồi chờ hệ
  thống giết extension, hoặc build-cài lại; mỗi lần cài lại = một lần lạnh. Khoảng `appear` có
  thông điệp `cold`.
- *Ấm* (warm): tiến trình còn sống, iOS tạo controller mới (đổi app chủ, ẩn/hiện bàn phím).
  Thông điệp `warm`; `reshow` = cùng controller hiện lại sau khi đã xé cây view (RAM-AUDIT.md #1).
- Báo **trung vị và P90 trên ≥ 20 lần, tách lạnh / ấm** — đừng trộn. Lần lạnh còn gồm dyld + khởi
  tạo UIKit của tiến trình trước `vc.init` (khoảng `appear` bắt đầu ở `vc.init` nên KHÔNG gồm phần
  đó; xem mốc tiến trình trong Instruments nếu cần).

**Đọc số**

- `appear` ấm là con số chính của cảm giác "chạm ô nhập là có phím". Mục tiêu (ý kiến, chưa có
  chuẩn công bố): ấm ≤ ~16 ms (một khung), lạnh ~100–150 ms trên máy tầm trung.
- Nhiều mốc `height` sau khi `appear` đã đóng = host đổi khung — không phải mình chậm, nhưng mỗi
  lần đổi chỉ được xếp lại khung (xem ngân sách size sequence bên dưới).
- `key` p95 < 16,7 ms. `plane` (từ cache) vài ms.
- Khoảng `startup` cho biết bước nào ăn thời gian trong `appear` (vd `buildKeys` lớn ⇒ dựng phím).

## 3. Số đo trên simulator (in-process, Debug)

`KeyboardStartupTests` dựng controller THẬT theo đúng thứ tự callback như iOS và in bảng từng
bước (dòng `STARTUP …`). Mỗi test chạy tiến trình riêng để "cold" lạnh thật:

```sh
cd iOS
for t in testTimeToFirstFrameDefault testTimeToFirstFrameDark testTimeToFirstFrameRich; do
  xcodebuild -project VietTelex-iOS.xcodeproj -scheme VietTelexKeyboardTests \
    -destination 'id=<SIM_UDID>' test -only-testing:VietTelexKeyboardTests/KeyboardStartupTests/$t \
    | grep '^STARTUP'
done
```

Đây là bản **Debug trên simulator** (Mac nhanh hơn A13 ~2–3×, Debug chậm hơn Release) — chỉ dùng
để so trước/sau cùng máy, không phải số người dùng thấy.

## 4. Ngân sách render (test chặn hồi quy)

`KeyboardTests/KeyboardRenderBudgetTests.swift` — **đếm việc, không đo giờ** ⇒ tất định, không
flaky khi Mac bận. Chạy trong bộ test mặc định:

```sh
cd iOS
xcodebuild -project VietTelex-iOS.xcodeproj -scheme VietTelexKeyboardTests \
  -destination 'id=<SIM_UDID>' test -only-testing:VietTelexKeyboardTests/KeyboardRenderBudgetTests
```

Mỗi test in một dòng `BUDGET …` với số đo hiện tại. Trần nằm trong `enum Budget` ở đầu file.

| Test | Đếm gì | Trần |
|---|---|---|
| `testOpenToFirstFrameBudget` | view / layer trong cây, `layoutSubviews` của KeyboardView và của mọi phím tới khung đầu (mặc định); dựng plane đúng 1 lần; gợi ý / model cá nhân chưa nạp trước khung đầu | xem `Budget.open*` |
| `testOpenRichDefersWarmupsUntilAfterFirstFrame` | như trên với theme + nhân vật + âm phím + gõ vuốt + hàng số; engine âm & template vuốt chỉ được xin SAU khung đầu; gõ ngay trước đó vẫn ra đúng chữ | `Budget.openRich*` |
| `testHostSizeSequenceBudget` | chuỗi khung host 0 → 896 → 452 → 268 → chiều cao xin: không dựng lại phím, không tạo view, trần lượt layout | `Budget.sizeSequence*` |
| `testKeypressBudget` | một phím chữ giữa từ: không view/layer mới, trần `layoutSubviews` (tới commit và sau khi thanh gợi ý cập nhật) | `Budget.keypress*` |
| `testPlaneSwitchBudget` | ABC → 123 → ABC lần hai: tráo từ cache, không dựng, không tạo view | `Budget.planeSwitchKeyLayouts` |
| `testNoOffscreenRenderingLayers` | layer đang hiện gây offscreen pass: bóng thiếu `shadowPath`, `mask`, `shouldRasterize`, bo góc + `masksToBounds` có sublayer, blur — cả cấu hình mặc định lẫn theme, kèm ô phóng to | `Budget.offscreenLayers` (0) |
| `testTemplatesPlaneNoOffscreenShadows` | như trên cho plane mẫu câu (bóng từng chip) | `Budget.offscreenLayers` (0) |

**Khi một test ngân sách đỏ**

1. Đọc dòng `BUDGET` và thông điệp lỗi: số nào vượt, ở đường nào (mở / đổi cỡ / gõ / đổi mặt phím).
2. `testKeypressBudget` đỏ vì KeyboardView layout lại: thông điệp lỗi kèm call stack từng lần
   layer của KeyboardView bị đánh dấu cần layout (`KeyboardView.debugNeedsLayoutLog`, DEBUG) —
   thường là một subview TRỰC TIẾP của KeyboardView đổi cỡ (Core Animation khi đó đánh dấu cả
   superlayer); đặt nó vào một lớp chứa riêng như ô phóng to (`balloonHost`).
3. Mặc định là **thay đổi vừa làm thêm việc vào đường nóng** — tìm và dời nó ra (lười, sau khung
   đầu qua `afterFirstFrame` / `PostFrameWork`, chỉ khi tính năng bật…).
4. Nếu việc thêm là CỐ Ý và đáng (vd tính năng mới cần thêm một view trên bàn phím): sửa đúng con
   số trong `enum Budget` = số đo mới (+ khoảng nhỏ nếu số dao động theo cấu hình), cập nhật
   bảng ở mục 5 dưới đây, và ghi lý do trong commit message. Không nâng trần "cho xanh".

**Đo giờ (phụ, bộ chậm)** — `testTimingOpenToFirstFrame`, `testTimingPlaneSwitch` dùng
`measure(metrics: [XCTClockMetric(), XCTCPUMetric()])` + trần rộng (~3× số đo). Bỏ qua trong bộ
mặc định (giờ dao động khi máy bận); chạy bằng một lệnh:

```sh
cd iOS
xcodebuild -project VietTelex-iOS.xcodeproj -scheme VietTelexKeyboardSlowTests \
  -destination 'id=<SIM_UDID>' test \
  -only-testing:VietTelexKeyboardTests/KeyboardRenderBudgetTests/testTimingOpenToFirstFrame \
  -only-testing:VietTelexKeyboardTests/KeyboardRenderBudgetTests/testTimingPlaneSwitch
```

Test chạy cấu hình Debug (cần hook `#if DEBUG` của controller); số tuyệt đối vì thế cao hơn
Release — dùng để so giữa các bản trên cùng máy.

## 5. Số đo

### 07/11/2026 — trước / sau đợt "signpost + ngân sách render"

**Đếm (KeyboardRenderBudgetTests, tất định):**

| Đường | Trước | Sau |
|---|---|---|
| Một phím chữ: lượt `layoutSubviews` của KeyboardView | 1 (ô phóng to đổi cỡ ⇒ CA đánh dấu superlayer) | **0** |
| Chuỗi khung host 0 → 896 → 452 → 268 → chiều cao xin: lượt layout phím | 195 | **174** |
| Warm-up nền (template vuốt / từ điển Anh / FUTO / vnlm, mô hình chạm, engine âm) | xin TRƯỚC khung đầu | sau commit khung đầu |
| Layer gây offscreen pass (chip mẫu câu, popup tông da emoji) | bóng thiếu `shadowPath` | **0** |
| Mở tới khung đầu (mặc định): view / layer / layout KeyboardView / layout phím | 112 / 112 / 1 / 41 | không đổi |

**Giờ, simulator iPhone 17 (iOS 27.0), bản Release, ngoài tiến trình** — app chủ
`iOS/Scripts/ram-audit/Host` (`-autocycle 12`: ẩn/hiện 12 lần, mỗi lượt chạy = 1 lạnh + 12 ấm),
`xctrace --instrument os_signpost --recording-options iOS/Scripts/keyboard-signposts.json`,
khoảng `appear`. Mac dùng chung với việc khác ⇒ nhiễu lớn, nhất là lần lạnh.

| Cấu hình | Bản | Lạnh (ms, từng lần) | Ấm trung vị / P90 (ms) |
|---|---|---|---|
| Mặc định | trước | 52 · 62 · 134 | 10,6 / 12,3 (n=36) |
| | sau | 59 · 61 · 103 | 11,1 / 23,4 (n=36; một lượt trùng lúc máy bận) |
| Gõ vuốt + EN + âm phím + theme + hàng số | trước | 50 · 99 | 10,4 / 13,2 (n=24) |
| | sau | 68 · 123 | 12,8 / 21,7 (n=24) |

Đọc: trên simulator (Mac nhiều lõi) **không thấy khác biệt có ý nghĩa** ở `appear` — đúng dự
kiến: đợt này không bớt việc trên main trước khung đầu (đã tối ưu ở các đợt trước; ấm ~10 ms ≈
một khung), mà bớt layout mỗi phím và bớt tranh CPU nền lúc mở (Mac thừa lõi nên không lộ).
Cần đo lại trên máy thật (A13: 2 lõi hiệu năng) theo mục 2.

Trong tiến trình (KeyboardStartupTests, Debug, simulator, 3 lần, máy bận): xem commit message.

## 6. Ảnh lưới phím cho khung đầu (KeySnapshot, 09/11/2026)

Lần hiện trước (yên, chưa chạm, `captureDelay` sau viewDidAppear) chụp **chỉ vùng phím**
(`rowsContainer`, nền trong suốt) + khung từng phím, ghi nền vào Caches riêng của extension
(`Caches/KeySnapshot/keysnap-<khoá>-<khung>-<w>x<h>.bgra`: BGRA thô để mmap, đuôi = khung phím).
Lần mở sau, khoá khớp chính xác ⇒ khung đầu là một CALayer chứa ảnh, phím thật dựng ngay sau commit
(PostFrameWork) rồi bỏ ảnh. Chạm khi ảnh còn hiện: `hitTest` dựng phím thật ngay rồi định tuyến như
thường (không mất chạm, hiệu ứng bấm phím chạy như cũ).

- **Khoá** (`KeyboardView.snapshotKeyParts`): build, scale, hướng, a11y, ngôn ngữ, plane, shift, loại ô,
  Return, sáng/tối, theme (id, JSON chuẩn của theme tự tạo, kiểu phím, bảng màu liệt kê tay —
  `KeySnapshot.paletteKey`), tệp theme, hàng số, một tay, phím cách, ký tự phụ, hình học hàng… KHÔNG
  dùng Mirror / in tên case enum (đo: ~17–23 ms lúc tiến trình lạnh → 0,1–0,2 ms sau khi bỏ).
- **Không dùng ảnh**: VoiceOver; plane emoji / mẫu câu / bàn số lớn; phím tự chuyển động (keyMotion,
  float); phím kính (keyShape glass); đập chuột. Viền cầu vồng / cực quang / Ảo giác, hoạ tiết giữa hàng,
  nền, đèn, bạn đồng hành, hiệu ứng là lớp riêng dựng sống — viền / hoạ tiết dùng khung phím lưu kèm.
  Theo giờ: bảng màu nằm trong khoá ⇒ giờ khác = dựng như cũ.
- **Tắt nhanh**: `KeySnapshot.compiledOn = false` (biên dịch) hoặc defaults `keySnapshotOff = true`.
  Tắt ⇒ không liệt kê thư mục, không tính khoá, không chụp. Trong XCTest mặc định TẮT (test bật riêng).
- Đo: `KeyboardStartupTests/testTimeToFirstFrameSnapshot{Default,Dark,Rich}` — chạy HAI lần
  (`-only-testing`, tiến trình riêng); lượt đầu chụp, lượt sau là "lạnh có ảnh" (dòng `snap=1`).

**Số đo 09/11/2026** — simulator iPhone 17 (iOS 27), Debug, trong tiến trình, mỗi ô trung vị 4 tiến
trình lạnh riêng (Mac dùng chung, nhiễu). "Sẵn chạm" = khung đầu + dựng phím thật sau khung đầu.

| Cấu hình | Khung đầu cũ (ms) | Khung đầu ảnh (ms) | Sẵn chạm cũ / ảnh (ms) | Footprint sau khung đầu cũ / ảnh (MB) |
|---|---|---|---|---|
| Mặc định | 47,8 | 34,1 | 47,8 / 51,7 | 18,3 / 19,5 |
| Tối | 51,3 | 34,7 | 51,3 / 52,4 | 18,3 / 19,4 |
| Theme + nhân vật + âm + hàng số | 63,1 | 50,5 | 63,1 / 68,8 | 20,8 / 20,9 |

Ấm (cùng tiến trình): khung đầu 11,7 → 7,0 (mặc định); footprint sau didAppear không đổi (ảnh nhả).
Đánh đổi: phím hiện sớm hơn ~13–17 ms, nhận chạm muộn hơn ~1–6 ms (chạm sớm hơn thì dựng ngay lúc chạm).
Cần đo lại trên máy thật (Release, mục 2).

## 7. Ảnh nền theo khung host, phím 🌐 iPad, nét vuốt (10/11/2026)

- **Ảnh nền / ảnh nền + tiền cảnh theme — mới nhất thắng** (`SizedDecodeGate`, Wallpaper.swift). Trước: mỗi
  khung tạm của host (0 → 896 → 452 → 268 → chiều cao xin) xếp một lần giải JPEG + cắt trên
  `Wallpaper.queue`; khung tạm đầu tiên đuổi luôn ảnh đã cache của lần hiện trước; ảnh cũ được gán lần
  lượt, ảnh đúng về sau cùng. Giờ: view của controller (`primesLastHeight`) KHÔNG xin giải khi chiều cao
  view ≠ chiều cao đang xin (> 1 pt) — hẹn kiểm lại sau `settleDelay` (0,2 s): cỡ đứng yên ⇒ coi là cỡ
  cuối và giải (host giữ cỡ khác vẫn có ảnh). Mỗi yêu cầu lấy vé; việc đã xếp mà vé cũ thì bỏ ngay đầu khối,
  `loadForKeyboard(stillWanted:)` không đuổi cache khi vé đã cũ; kết quả về main chỉ gán khi vé mới nhất
  VÀ cỡ lúc xin = `bounds.size` (vé mới nhất mà view đã đổi cỡ ⇒ xin lại ở cỡ hiện tại). Hiện lại cùng cỡ
  ⇒ 0 lần giải (cache). Cảnh nền / hoạ tiết / viền cầu vồng KHÔNG chặn theo khung tạm: chạy đồng bộ trên
  main và khung đầu có thể là khung tạm — chặn thì khung đầu thiếu hoạ tiết.
- **iPad dựng hai lần vì phím 🌐**: trước đây chỉ iPhone đoán phím 🌐 trước khung đầu; iPad dựng hàng đáy
  không 🌐 rồi didAppear (`needsInputModeSwitchKey` = true) dựng lại cả plane (hàng đáy đổi sau khi trượt
  lên, ảnh lưới phím không khớp). Giờ `GlobeMemory` nhớ giá trị thật lần trước (biến tĩnh + một Bool trong
  defaults riêng của extension) và `KeyLayout.preFrameGlobeGuess` dùng nó trên mọi loại máy; iPhone chưa
  nhớ vẫn đoán theo nút Home; didAppear vẫn sửa khi khác. Trong XCTest `GlobeMemory` mặc định tắt.
- **Nét vuốt**: touchesMoved đưa MỌI điểm gộp (coalesced) vào decoder và nét như trước, nhưng dựng path +
  commit nét MỘT lần mỗi lượt (`swipeMovedBatch`) — trước: mỗi điểm gộp một lần (cảm ứng 120 Hz trên màn
  60 Hz ⇒ lần đầu bỏ phí). Hạt (pháo hoa…) vẫn bắn theo từng điểm.
- Test: `OpenPathPerfTests` (chuỗi khung host ⇒ đúng 1 lần giải + 1 lần gán ở cỡ cuối; hiện lại cùng cỡ ⇒
  0 lần giải; host giữ cỡ khác vẫn có ảnh; iPad có giá trị nhớ ⇒ 0 lần dựng ở didAppear; ≤ 1 lần vẽ nét
  mỗi lượt touchesMoved, đầu vào decoder y hệt). Chưa đo giờ trên máy thật.
