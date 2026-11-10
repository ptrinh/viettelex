# RAM audit — bàn phím iOS (28/09/2026)

Mục tiêu: biết extension `VietTelexKeyboard` tốn RAM vào đâu, có rò rỉ không, và sửa gì trước.
Trần jetsam của keyboard extension ~48–66 MB tuỳ máy/iOS (vượt ⇒ bị giết không log, iOS quay về
bàn phím trước — user thấy "bàn phím trắng / tự đổi bàn phím").

> Số đo trên simulator iPhone 17 (iOS 27.0), bản Release (`-Osize`), commit 6305eef. Simulator
> cộng thêm ~14 MB cố định (dyld_sim, `__DATA` framework hệ thống, page table) nên số tuyệt đối
> cao hơn máy thật vài MB; **phần tăng** giữa các trạng thái và rò rỉ thì như nhau. Dao động giữa
> hai lượt chạy ±5 MB (máy có tải song song).

## Đã sửa (28/09/2026) — trước / sau

Cùng simulator iPhone 17 (iOS 27.0) riêng, bản Release, `ram-audit.sh` (XCUITest) + `leak-cycle.sh`
(không AX). Trước = main 1380a38, sau = nhánh sửa. MB phys_footprint.

| Trạng thái | default trước | default sau | all trước | all sau |
|---|---|---|---|---|
| Vừa hiện | 25 | 24 | 36 | **30** |
| Sau 200 phím | 32 | 31 | 39 | 39 |
| Đang mở emoji | 57 | **51** | 70 | **65** |
| Rời emoji về chữ | 49 | 49 | 61 | 61 |
| Sau 10 vòng ẩn/hiện | 63 | **50** | 76 | **62** |
| Sau 30 vòng ẩn/hiện | 94 | **53** | 103 | **63** |
| Đỉnh | 94 | 55 | 105 | 69 |
| `leak-cycle.sh 30` (không AX): vòng 0 → 30 | 18 → 57, 31 `KeyboardView` sống | 16 → 20, 1 `KeyboardView` | — | 22 → 29 |

1. **Rò rỉ cây view (#1) — gốc là UIKit, không phải code mình.** `ViewTreeLeakTests` tái hiện
   với `UIInputView` RỖNG (không phím, không stack view, style `.keyboard` hay `.default` như
   nhau): UIKit iOS 26+/27 không bao giờ nhả `UIInputView` — vòng `UIInputView` ⇄
   `_UIInputViewContent` (associated object, `leaks --traceTree` gốc ở
   `objc::AssociationsManager`). Trait `_UICornerProvider` / `NSISEngine` chỉ là thêm đường tới
   cùng cái vỏ đó. Không tránh được bằng bỏ UIStackView / cornerRadius / trait. Sửa:
   `viewDidDisappear` → `KeyboardView.tearDown()` (dừng timer/display link, bỏ planeCache,
   bảng emoji, ảnh nền, gỡ đệ quy mọi subview + constraint) + gỡ 4 constraint cạnh
   KeyboardView↔view gốc (removeFromSuperview KHÔNG gỡ chúng khỏi mảng constraint của
   UIInputView — chính chúng giữ KeyboardView cũ khi cùng controller hiện lại) + gỡ subview
   view gốc; `viewWillAppear` thấy đã xé ⇒ `installKeyboard()` dựng KeyboardView mới rồi áp
   cấu hình như controller mới. Mỗi vòng còn rò phần vỏ của UIKit (~80 KB: UIInputView,
   `_UIInputViewContent`, NSISEngine, trait storage, xpc_connection — heapdiff) thay vì ~1,8 MB.
   Độ trễ (in-process, Debug): hiện lại cùng controller 10,7 ms ≈ mở controller mới 14,5 ms;
   xé khi ẩn 1,1 ms; đường controller mới (thường gặp) không đổi.
2. **Emoji**: `isPrefetchingEnabled = false`, ô bỏ `adjustsFontSizeToFitWidth` ⇒ lúc mở −6 MB
   (CA 8,1 → 5,0 MB). `EmojiData.categories` giờ `[UInt16]` id (33 KB) — nhưng **1,8 MB đo
   trước đây KHÔNG phải mảng String** (chuỗi emoji ≤15 byte nằm inline) mà là font Apple Color
   Emoji CoreText nạp lần đầu khi kiểm glyph — lưới vẽ emoji cũng cần font đó nên không bớt được.
   Rời lưới / tearDown / cảnh báo bộ nhớ ⇒ `EmojiData.dropCaches()`. Cache glyph CoreText (~8,5
   KB/emoji) vẫn không xả được ⇒ "rời emoji" không đổi.
3. **Cảnh báo bộ nhớ**: thêm `planeCache.removeAll()` (plane không hiện), `EmojiData.dropCaches()`,
   `Wallpaper.dropCache()` (cache tĩnh; view đang hiện vẫn giữ ảnh). Simulator không bắn được
   cảnh báo cho process khác ⇒ kiểm bằng `RamFixTests.testMemoryWarningDropsCaches`.
4. **Ảnh nền**: giải ở tối đa @2x (`Wallpaper.decodeScale`) rồi **cắt đúng phần hiện**
   (`aspectFillCrop`, aspect-fill giữa, không bao giờ phóng to vào bitmap): ảnh dọc 810×1080 trên
   bàn phím iPhone 3,5 → 1,9 MB; ảnh chụp màn hình dọc 497×1080 2,1 → 0,7 MB. Ảnh chụp màn so
   trước/sau: sai khác trung bình 0,24/255 mỗi kênh (mắt không thấy — nguồn ≤1080 px nên @2x
   gần như không mất chi tiết).
   **Trình chỉnh khung (28/09/2026)**: người dùng kéo/zoom ảnh dưới khung đúng tỉ lệ bàn phím dọc;
   app giữ bản gốc ≤2048 px (container riêng, không App Group, không sao lưu) + khung chuẩn hoá
   (`wallpaperCrop` trong App Group) và **nướng sẵn đúng vùng cắt** (≤1080, đã mờ) vào
   `wallpaper.jpg` — ImageIO không giải được một vùng, nên cắt ở app để extension chỉ giải phần
   hiện. Bàn phím không đổi đường giải; ngang = dải giữa của khung dọc (cắt giữa file đã nướng).
   Test `WallpaperCropTests.testDecodeRamNotAboveBefore`: đỉnh giải + bitmap giữ ≤ đường cũ.

Test: `ViewTreeLeakTests` (cây cũ chết qua controller mới / cùng controller, trạng thái sau hiện
lại, heap/vòng < 30 KB, độ trễ), `RamFixTests` (emoji id, dropCaches, lưới, cảnh báo bộ nhớ, cắt
ảnh nền), `RamBreakdownTests` leak-cycles (bỏ XCTExpectFailure; 3 vòng làm ấm rồi đo).

## Framework nạp lúc khởi động + đợt 14/10/2026

**Framework link vào bàn phím** (`otool -L` binary appex, Release iphoneos). Trước khi gỡ, đã
tính bao đóng phụ thuộc của UIKit + Foundation trên runtime simulator iOS 26.5 (`otool -L` đệ
quy trong RuntimeRoot, 538 image): **AVFAudio, AVFoundation, Accelerate, AudioToolbox, CoreImage,
CoreText, ImageIO đều đã nằm trong bao đóng của UIKit** ⇒ bỏ link trực tiếp không bớt image nào
được nạp (không làm: thay AVAudioEngine bằng `AudioServicesPlaySystemSound` mất âm lượng/kiểu âm;
thay vDSP bằng vòng lặp chậm hơn mà không lợi gì; CoreImage chỉ được libswiftCoreImage weak kéo).
Chỉ hai cái là THÊM:

| Framework | Image thêm ngoài bao đóng UIKit | Xử lý |
|---|---|---|
| Translation (weak) | **34** (AppIntents, Speech, ContextKit, ToolKit, LinkServices, StatusKit…) | **Gỡ khỏi bàn phím** — phần gọi Apple Translation tách thành `VTTranslate.framework` (iOS/VTTranslate/) nhúng ở app chủ, bàn phím `dlopen` lần đầu bấm chip Dịch (`TranslateLoader`, Keyboard/Translate.swift). Extension không được có thư mục Frameworks riêng (ITMS-90206) nên framework nằm ở `VietTelex.app/Frameworks/`; dlopen file trong bundle đã ký là hợp lệ App Store. |
| CoreHaptics | 1 (chính nó) | Giữ — chỉ một image, không kéo theo gì. |

Trước → sau (link của binary bàn phím): bỏ `Translation.framework (weak)`; còn lại y nguyên
(Foundation, UIKit, AVFAudio, Accelerate, AudioToolbox, CoreFoundation, CoreGraphics, CoreHaptics,
CoreText, ImageIO, QuartzCore + overlay libswift*). **Cần máy thật**: đo footprint "vừa hiện" trước/
sau (ước vài trăm KB `__DATA` dirty của 34 image) và bấm chip Dịch một lần (dlopen từ appex trên
thiết bị đã ký).

**Bảng emoji (51–65 MB khi mở)**: Khi bàn phím ẩn, `tearDown()` đã gỡ toàn bộ cây view (gồm lưới
emoji) và `EmojiData.dropCaches()` — phần còn lại là cache glyph Apple Color Emoji của CoreText,
không API công khai nào xả được (§4). Tự thoát process khi ẩn — không làm (hệ thống có thể đang
hiện lại bàn phím, rủi ro "bàn phím trắng"). **Sửa (14/10/2026, maintainer duyệt): app chủ vẽ sẵn
emoji thành atlas ảnh, bàn phím vẽ bitmap — §4b.**

Đường phím nóng (14/10/2026): `manualCompletions` dùng chỉ mục fold sẵn + tìm nhị phân (trước fold
cả danh sách từ thêm tay mỗi phím); hoãn gợi ý 30 ms dùng lại MỘT `DispatchSourceTimer`
(`MainDebouncer`) thay vì `asyncAfter` mỗi phím; khoá "bar không đổi" là struct Equatable thay vì
chuỗi ghép; `TouchLog.write` nhận `@autoclosure` (Debug mode tắt ⇒ không dựng chuỗi). Test:
`PerfSizeUXFixTests`.

Dung lượng: app iOS không chép `vnlexicon.bin` + `enlexicon.bin` nữa (−334 KB, đọc bản trong
`PlugIns/VietTelexKeyboard.appex` — `VTBundleResource`); VTTranslate.framework +72 KB; TelexCore
(package) giờ -Osize ở Release iOS (Xcode không truyền `SWIFT_OPTIMIZATION_LEVEL` của project xuống
package; `__TEXT` 106 → 89 KB). `icon-1024.png`: không tối ưu — actool giải PNG rồi nén lại lzfse
ARGB trong Assets.car (559 KB) nên nén PNG nguồn không đổi dung lượng bản phát hành.

## Kết luận nhanh (audit gốc, trước khi sửa)

1. **Rò rỉ nghiêm trọng: mỗi lần ẩn/hiện bàn phím giữ lại NGUYÊN cây view cũ** (~1,8 MB/lần,
   không bao giờ nhả). 30 lần ẩn/hiện: 25 → **107 MB**. Trên máy thật extension sẽ bị jetsam
   sau khoảng 15–20 lần ẩn/hiện trong cùng app — rất có thể là nguồn "bàn phím tự văng".
   Nguyên mẫu "xé cây view khi `viewDidDisappear`": 30 vòng chỉ còn 16 → 20 MB. (§3)
2. **Bảng emoji**: mỗi emoji KHÁC NHAU từng vẽ để lại ~8,5 KB trong cache glyph của CoreText,
   vĩnh viễn trong process (cảnh báo bộ nhớ, nhả font đều không nhả). Mở + lướt 6 trang:
   +22 MB (lúc mở) / +16 MB (sau khi rời). Lướt hết ~3.800 emoji trong process test: +108 MB. (§4)
3. **Model cá nhân (UserLangModel)** — ĐÃ SỬA 09/2026 (bảng gọn intern id + file nhị phân VTL2):
   tại trần 3.000/6.000/3.000 còn ~0,3 MB (trước ~0,7–1,0 MB). Con số "+13 MB / ~1 KB/mục" cũ
   phần lớn là DispatchWorkItem lưu-sau-5s mà mỗi record hẹn (24.000 record dồn trong <5 s) —
   hiện vật của phép đo, không phải bảng. (§5)
4. Dữ liệu mmap (`vnlm.bin`, `vnlexicon.bin`, `emoji.bin`, `futoswipe.bin`, `enlexicon.bin`) đúng
   thiết kế: **~0 dirty** (trang sạch 12–31 MB, jetsam không tính). FUTO (2,5 MB) nhả đúng khi ẩn.

## 1. Số đo process extension thật (MB phys_footprint)

`iOS/Scripts/ram-audit/ram-audit.sh <default|all|off>` — driver XCUITest đi qua các trạng thái,
host lấy `footprint` / `vmmap --summary` / `heap -s` của process extension ở mỗi mốc.

| Trạng thái | default | all (bật hết¹) | off (tắt hết) |
|---|---|---|---|
| Vừa hiện | 25 | 30 | 24 |
| Sau 200 phím | 26–33 | 40 | 29 |
| Đang mở emoji (lướt 6 trang) | 48–55 | 67 | 50 |
| Rời emoji về chữ | 41–51 | 57 | 44 |
| Panel clipboard | — | 58 | — |
| Sau 50 lần vuốt | 51 | 59 | 44 |
| Xoay ngang / dọc lại | 51 / 52 | 61 / 61 | 44 / 44 |
| Sau cảnh báo bộ nhớ² | không đổi | không đổi | không đổi |
| Sau 10 vòng ẩn/hiện | 69 | 72 | 57 |
| Sau 30 vòng ẩn/hiện | **107** | — | — |
| Đỉnh (peak) trước vòng ẩn/hiện | 61 | 71 | 52 |

¹ gợi ý + vuốt + FUTO + emoji gợi ý + clipboard + âm phím (mechanical) + rung + theme peach +
ảnh nền + trong suốt 30 % + hàng số + chip số/toán + teencode. Full Access bật, Plus mở.
² Simulator không có cách CLI tin cậy để bắn memory warning cho process khác (Simulator ghi file
`SIMULATOR_MEMORY_WARNINGS`, chỉ bắn được lần đầu tạo file) — số "sau cảnh báo" ở đây là không
nhận được cảnh báo. Đo trong process test (gọi thẳng `didReceiveMemoryWarning` + notification):
UIKit tự nhả **13–16 MB** footprint (cache CA/ảnh), heap của mình không giảm (§6).

Cơ cấu lúc vừa hiện (default, 25 MB): malloc 10 MB · `__DATA` framework hệ thống 10,4 MB (cố định)
· dyld + page table 3,4 MB · CoreAnimation 1 MB. Mặc định vs tắt hết chỉ khác ~1 MB lúc hiện.

## 2. Top thành phần (đo tách từng phần — `RamBreakdownTests`)

`RamBreakdownTests/testComponentBreakdown` (bộ chậm) nạp từng thành phần trong process test và in
phần tăng. Sắp theo mức ảnh hưởng thực tế:

| # | Thành phần | RAM | Nhả được? |
|---|---|---|---|
| 1 | **Cây view cũ bị giữ mỗi lần hiện** | +1,8 MB / lần hiện, không giới hạn | ✗ (rò rỉ) |
| 2 | **Cache glyph emoji màu (CoreText)** | ~8,5 KB / emoji khác nhau (mọi cỡ chữ) — 6 trang ≈ 15 MB, hết bảng ≈ 32 MB | ✗ suốt đời process |
| 3 | Backing store CA của bảng emoji (ô UILabel) | +8 MB khi đang mở | ✓ khi rời |
| 4 | Framework hệ thống (`__DATA` dirty, dyld, page table) | ~14 MB (sim) | ✗ cố định |
| 5 | UserLangModel (model cá nhân) | ~0,3 MB tại trần (bảng gọn 09/2026; trước ~0,7–1,0 MB) | ✓ khi bỏ controller |
| 6 | Ấm máy khi gõ (cache glyph chữ, layout, gợi ý) | +1 … +8 MB trong 200 phím đầu | một lần |
| 7 | Âm phím riêng (AVAudioEngine + HAL) | +3–4 MB footprint | ✓ shutdown khi ẩn |
| 8 | Ảnh nền (810×1080 @3x) | bitmap 3,4 MB, đỉnh giải mã +7 MB | ✓ |
| 9 | FUTO Swipe model | 2,5 MB | ✓ nhả khi ẩn / memory warning |
| 10 | `EmojiData.categories` (mảng ~3.800 String) | 1,8 MB heap | ✗ static suốt đời |
| 11 | planeCache (số + ký hiệu) | 1,4–2,6 MB | chỉ khi đổi chữ ký |
| 12 | TelexKeyPrior (trie smartTouch) | ~1 MB heap | ✗ static |
| 13 | enlexicon parse / SwipeDecoder template | 0,7 / 0,36 MB | template nhả khi `swipe = nil` |
| — | vnlm / vnlexicon / emoji.bin / futoswipe.bin (mmap) | ~0 dirty | trang sạch |

## 3. Rò rỉ #1 — cây view cũ sống mãi

Tái hiện: `iOS/Scripts/ram-audit/leak-cycle.sh 30` (app chủ tự đổi first responder mỗi 1,5 s,
KHÔNG qua XCUITest ⇒ không có runtime Accessibility giữ view):

| vòng ẩn/hiện | 0 | 10 | 20 | 30 |
|---|---|---|---|---|
| hiện tại: footprint (MB) / số `KeyboardView` sống | 8 / 1 | 46 / 16 | 71 / 31 | 72 / 31 |
| nguyên mẫu xé cây view khi ẩn | 16 / 1 | 19 / 1 | 20 / 1 | — |

(Trong process test cũng thấy: 20 lần dựng/đóng controller +17 MB.)

- `KeyboardViewController` được giải phóng đúng (heap chỉ còn 1–2 instance); **view** của nó
  (`UIInputView` → `KeyboardView` → ~40 `KeyButton`, label, constraint, gesture) thì không.
- `leaks --traceTree` cho đường giữ: `KeyButton` đang sống → `_cachedTraitCollection` →
  `_UICustomTraitStorage` → `_UICornerProvider.id` → `UIStackView` của bàn phím CŨ →
  `_layoutEngine` → toàn bộ cây cũ, và cây cũ lại giữ cây cũ hơn (chuỗi). Tức là trait "corner
  provider" (cơ chế góc bo đồng tâm iOS 26+) của UIKit được tái dùng giữa các lần dựng và kéo theo
  hierarchy cũ. `leaks` thường báo 0 "leak" vì mọi thứ vẫn reachable.
- Nguyên mẫu đã thử (KHÔNG commit): trong `viewDidDisappear` gỡ đệ quy mọi subview của `view`.
  Cắt được chuỗi (còn lại cùng lắm vài KB stack view + engine).

**ĐÃ SỬA 28/09/2026** (xem đầu file — gốc là UIKit giữ `UIInputView`, kể cả khi rỗng).
**Sửa đề xuất** (ưu tiên 1, tiết kiệm ~1,8 MB × số lần hiện, rủi ro trung bình):
`viewDidDisappear` → `keyboard.tearDown()` (nhả planeCache, emoji plane, panel clipboard, gỡ
subview đệ quy, `keyboard = nil`); `viewWillAppear` → nếu đã xé thì dựng lại `KeyboardView` (tách
phần dựng trong `viewDidLoad` ra hàm). Phải test: hiện → ẩn → hiện CÙNG controller (đổi app nhanh,
đổi ô nhập), xoay, iPad nổi, một tay, mẫu câu. Test hồi quy: `RamBreakdownTests` phần leak-cycles
(đang `XCTExpectFailure`, bỏ dòng đó khi sửa xong) + `leak-cycle.sh`. Nên gửi Feedback cho Apple
(trait `_UICornerProvider` giữ view mạnh).

## 4. Bảng emoji

- `testEmojiGlyphCache`: vẽ emoji bằng CoreText, mỗi emoji MỚI +8–10 KB heap ở MỌI cỡ (20/24/26/32/40
  pt như nhau); vẽ lại emoji cũ +0; `didReceiveMemoryWarning` +0; tự tạo `CTFont` rồi nhả cũng +0
  ⇒ cache glyph toàn process, không API nào xả. Đây là chi phí thuê font Apple Color Emoji —
  không tránh được bằng cỡ chữ.
- Ngoài cache glyph, lướt toàn bộ bảng trong process test tốn thêm ~15 KB/emoji (heap +92 MB tổng)
  — chưa tách được (nghi: layout text của UILabel với `adjustsFontSizeToFitWidth`, layout
  attributes của 3.800 item).
- Backing store CA ~8 MB khi mở — nhả khi rời (bảng emoji không vào planeCache ✓).

Đề xuất (ưu tiên 2):
- Bỏ `adjustsFontSizeToFitWidth` ở `EmojiCell` (đặt cỡ cố định theo metrics); tắt
  `collection.isPrefetchingEnabled` để không dựng/vẽ cột ngoài màn hình. Đo lại bằng
  `testComponentBreakdown` (bước "emoji scroll all sections"). Rủi ro thấp.
- `EmojiData.categories` giữ id `[UInt16]` thay vì `[String]`; ô tự đọc chuỗi từ blob mmap
  (`EmojiData.emoji(id)`) — −1,7 MB, rủi ro thấp.
- Cache glyph không xả được ⇒ giữ "khoảng trống" bằng cách sửa #1 và giảm các khoản khác; nhảy
  theo nhóm (thanh category) thay vì lướt liên tục đã giới hạn số emoji vẽ.

## 4b. Atlas emoji vẽ sẵn (14/10/2026)

Bàn phím KHÔNG vẽ chữ emoji ở lưới / Recents / kết quả tìm / popup tông da nữa khi có atlas hợp lệ —
mọi cache glyph CoreText chuyển sang app chủ (không có trần jetsam chặt).

- **App** (`App/EmojiAtlasBuilder.swift`): lúc mở app (init + `scenePhase == .active`) kiểm manifest;
  thiếu/cũ ⇒ dựng nền (QoS utility, không chặn UI): 8 category đúng thứ tự lưới (chỉ emoji máy vẽ
  được) + nhóm `tones` (biến thể tông da của popup; Recents/tìm kiếm chỉ chứa emoji thuộc hai tập
  này). Vẽ bằng CoreText ở **cỡ glyph lớn nhất lưới dùng** (iPhone 34 pt, iPad 52 pt — test khoá với
  `EmojiGridMetrics`) × scale màn hình, ô vuông `ceil(cỡ × scale)` px (102 px trên @3x), căn giữa theo
  bbox ảnh glyph. Trang 8 × 4 ô PNG (816 × 408 px).
- **Lưu** (`Shared/EmojiAtlas.swift`) trong App Group `EmojiAtlas/`: mỗi bản dựng một thư mục
  `b<uuid>/` (manifest.json + index.bin + trang), con trỏ `current` ghi nguyên tử SAU CÙNG, bản cũ
  xoá sau ⇒ bàn phím đang giữ bản cũ chỉ thấy trang biến mất (ô đó vẽ chữ), không bao giờ ảnh lệch.
  `isExcludedFromBackup`. Manifest: format, **build iOS** (`operatingSystemVersionString` — cập nhật
  iOS đổi font emoji), scale, cỡ chữ, **hash FNV-1a của section EMOJ trong emoji.bin** (chỉ tập chuỗi
  emoji; khoá tìm SKEY đổi không cần dựng lại). Khoá index = **chuỗi emoji** (không phải id).
  `index.bin` mmap, tra nhị phân theo byte UTF-8 — 0 heap.
- **Bàn phím**: `EmojiPlane` / `EmojiSearchBar` mở atlas lúc dựng (chỉ khi vào bảng emoji — đường
  gõ không đổi, không mở emoji ⇒ 0 chi phí). Ô = `UIImageView` với BẢN SAO riêng của ô (crop trang
  → bitmap 102² px ≈ 41 KB), không giữ cả trang ⇒ Recents rải 30 trang cũng chỉ 30 ô. Trang giải mã
  bằng ImageIO (`ShouldCacheImmediately`), LRU 4 trang + giải mã trước trang kề ở nền. Rời bảng
  emoji / ô tìm / cảnh báo bộ nhớ ⇒ `EmojiData.dropCaches()` → `EmojiAtlasStore.release()`. Atlas
  hợp lệ cũng thay việc kiểm glyph: app đã kiểm trên CHÍNH bản iOS này ⇒ emoji mới hơn mức tin cậy
  mà không có trong atlas = không vẽ được (khỏi nạp font Apple Color Emoji ~1,8 MB chỉ để kiểm).
- **Rơi về chữ** từng ô: chưa mở app lần nào, manifest cũ (vừa cập nhật iOS, chưa mở app), emoji
  thiếu trong atlas, trang bị xoá. VoiceOver: ô là một phần tử, nhãn = chuỗi emoji (VoiceOver đọc
  tên emoji; emoji.bin không có trường tên CLDR riêng — tên tts lẫn trong SKEY).
- **Định dạng**: PNG (đo simulator iPhone 17, @3x): 3.714 ảnh (emoji lưới + biến thể tông da), 120 trang,
  **38,5 MB đĩa**, dựng 4,1 s, giải mã 7,1 ms/trang. HEIC q0,9 (alpha): 14,6 MB, dựng 8,4 s, giải mã
  9,1 ms/trang, alpha nén mất mát. Chọn PNG (giải mã rẻ nhất qua ImageIO, không lệ thuộc bộ giải
  HEVC trong extension, alpha không viền); đổi sang HEIC = một dòng (`EmojiAtlasBuilder.Format`).
- **App** giữ cache glyph của mọi emoji đã vẽ (~3.700 × vài chục KB) tới khi bị hệ thống thu hồi —
  chấp nhận được (app không có trần extension).

Đo (simulator iPhone 17, iOS 27.0, Debug, phys_footprint, `EmojiAtlasTests` bộ chậm, mỗi biến thể
một process riêng vì cache glyph không xả):

| `EmojiPlane` thật trong cửa sổ (402 × 290) | chữ (trước) | atlas (sau) |
|---|---|---|
| Mở bảng | +11,0 MB | **+4,8 MB** |
| Lướt HẾT mọi category | +228,6 MB | **+7,8 MB** |
| Rời bảng | +211,7 MB (không nhả) | **+7,8 MB** |

| Vẽ trực tiếp (không UIKit) | |
|---|---|
| Chữ, 266 emoji "objects" @34 pt | heap +2,1 MB = 8,3 KB/emoji, không nhả |
| Atlas, 559 emoji "smileys", cửa sổ 60 ô sống + LRU trang | đỉnh +3,5–4,9 MB, sau khi nhả +0,7 MB (heap +0,04 MB); 0,2–0,3 ms/emoji |

Con số "lướt hết" bằng chữ (+228 MB) lớn hơn nhiều so với 8,5 KB/emoji cache glyph đo bằng heap ở
§4: phần lớn nằm NGOÀI malloc (ảnh sbix đã giải mã ở cỡ @3x mà CoreText/CoreUI giữ) — chỉ thấy
qua phys_footprint. **Cần máy thật**: `ram-audit.sh` (mốc "Đang mở emoji" / "Rời emoji") sau khi mở
app chủ một lần; kiểm nét ảnh @3x (iPhone) và @2x (iPad 52 pt), căn giữa so với stock, giật khi
lướt (giải mã trang trên main lúc trang kề chưa kịp giải mã nền), app dựng lại sau cập nhật iOS.

## 4c. Trie chọn phím thông minh dựng sẵn (09/11/2026)

`TelexKeyPrior` (chọn phím thông minh, mặc định BẬT) trước đây dựng trie trong RAM mỗi process
(`fromLexicon`: vnlexicon + parse enlexicon ra String + seed). Giờ đọc `keyprior.bin` — CHÍNH tệp
Android (`android/app/src/main/assets`, sinh bằng `KeyPriorBlobTests` Kotlin) chép vào
`Keyboard/Resources/`, mmap qua `NSData(.alwaysMapped)`, `KeyTrie.mapped` đọc tại chỗ (nút BFS).
Thiếu / hỏng / tham số khác ⇒ dựng như cũ. `KeyPriorBlobTests` (iOS): bản chép trùng byte bản
Android, duyệt đủ 63.341 nút khớp bản dựng trong RAM (63.340 trọng số trùng bit, 1 lệch sai số
cộng float), prior từng phím khớp, blob hỏng bị từ chối.

| `testRamAssetVsLexicon` (simulator iPhone 17, Debug) | dựng từ lexicon (cũ) | asset mmap (mới) |
|---|---|---|
| Heap giữ lại khi trie sống | +959,8 KB | +0,6 KB |
| Thời gian (luồng nền, sau khung đầu) | 960 ms | 0,31 ms |

Đổi dữ liệu nguồn (vnlexicon / enlexicon / seed / TelexSpell): sinh lại bên Android rồi chép tệp
sang iOS — test iOS đỏ nếu hai bản lệch.

## 4d. Âm nhạc cụ + cảnh báo bộ nhớ (10/11/2026)

**Bộ nốt ngân (Piano / Đàn tranh / Ghi-ta, pedal Shift/Caps).** Trước: dựng lười bằng cách tổng hợp CẢ 25 nốt ra
`[Float]` rồi mới chép từng nốt sang `AVAudioPCMBuffer` ⇒ hai bản cả bộ cùng sống; bộ dựng xong giữ tới `shutdown()`
(nghỉ 8 s giữ nguyên, cảnh báo bộ nhớ lúc đang hiện không nhả gì). Sau (`KeySound.sustainPCMBank`): mỗi nốt tổng hợp →
chép vào PCM → `[Float]` nhả ngay (đỉnh = bộ PCM + một nốt). Nghỉ 8 s (`idleCheck`) và cảnh báo bộ nhớ
(`releaseSustainBank`, cả khi đang hiện) nhả bộ ngân — node giữ nguyên, nốt đang ngân không bị cắt (node tự giữ buffer
đã lên lịch tới khi phát xong). Pedal lần sau dựng lại nền; nốt ngân trong lúc đó phát bản thường. Lượt dựng đang chạy
lúc bị nhả thì bỏ kết quả (bộ đếm thế hệ). Đường phím vẫn chỉ `lock.try()`.

| `KeySoundTests.testSustainBankBuildPeakIsOneBank` (simulator iPhone 17, iOS 27, Debug, heap malloc) | cũ | mới |
|---|---|---|
| Đỉnh heap khi dựng bộ ngân (Piano / Đàn tranh / Ghi-ta, bộ 2,63 MB) | 5,37 MB | 2,63–2,64 MB |
| Giữ khi bàn phím đang hiện, đã nghỉ ≥ 8 s hoặc sau cảnh báo bộ nhớ | 2,63 MB | 0 |

**Cảnh báo bộ nhớ — cache thêm từ giữa 10/2026** (`KeyboardViewController.purgeStaticCaches`). Ẩn ⇒ bỏ hết; đang
hiện ⇒ chỉ bỏ thứ không trên màn hình (không bao giờ làm trống thứ đang nhìn), mọi thứ nạp lại lười:

| Cache | Ẩn | Đang hiện |
|---|---|---|
| `ThemeAssetLoader.cache` (skin/phông theme tải về — một mục = theme đang dùng) | bỏ | giữ |
| `BuddyView.atlasCache` (≤ 3 MiB) | bỏ hết | giữ atlas nhân vật đang hiện, bỏ phần còn lại |
| Atlas người nhảy Night Club (giữ trong `SpotlightView`, không phải cache tĩnh) | thả nếu view ngoài cửa sổ (thường đã thả cùng `tearDown`); gắn lại cửa sổ ⇒ giải lại | giữ |
| `SwipeVocab.cache` (2 chế độ lọc) | bỏ cả hai | giữ chế độ đang dùng, bỏ chế độ kia |
| Bộ nốt ngân nhạc cụ | (engine đã `shutdown`) | bỏ |

Đo `RamFixTests.testMemoryWarningHiddenDropsLateCaches` (cùng simulator, Debug; nạp tệp theme RỖNG — không ảnh, atlas
mèo + gà con, từ vựng vuốt cả hai chế độ, rồi bỏ khi ẩn): heap **−0,13 MB**, phys_footprint đo được **±0,00 MB**. Phần
lớn là từ vựng vuốt; atlas Bạn đồng hành (ảnh ImageIO ≤ 512 px) không hiện rõ trong heap malloc lẫn footprint của
process test — chưa tách được con số riêng. Skin/phông theme thật (ngân sách skin ≤ 4 MB — `ThemeAssetTests.testHeavyThemeOnRealKeyboard`) không đo trong
lượt này vì cần theme tải về; bỏ chúng chỉ xảy ra khi ẩn.

**Chưa đo được**: `ram-audit.sh` không có mốc nhạc cụ + pedal, và simulator không bắn được cảnh báo bộ nhớ cho process
extension (§1 chú thích ²) ⇒ chưa có số footprint process thật cho đợt này; số trên là heap trong process test.
Cần máy thật: theme có nhạc cụ, đạp pedal, nghỉ 8 s, đo footprint trước/sau.

## 5. UserLangModel

**Đã làm (09/2026)** — `UserLMTables` trong Keyboard/UserLangModel.swift: từ intern thành id
`Int32` (`words` + `[String: Int32]`), uni = `[UInt32]` theo id, bi = `ContiguousArray<UInt64>` sắp
`(next id<<32 | count)` theo prev id, tri = `[UInt64: Int32]` ((p2<<32|p1) → slot) + mảng như bi;
compact id khi prune/decay/xoá từ. File `userlm.bin` VTL2 (little-endian, CRC32, chung layout
Android) thay binary plist; plist cũ chuyển một lần (xoá chỉ sau khi bản mới ghi xong + đọc lại
khớp). Ngữ nghĩa y hệt: `UserLMCompactTests` so từng đầu ra với `LegacyUserLangModel` (bản cũ
giữ nguyên trong test) qua chuỗi thao tác ngẫu nhiên có chạm trần/decay/retract/xoá.

Đo `UserLMCompactTests.testMeasureHeavyUser` (simulator, `SWIFT_OPTIMIZATION_LEVEL=-O`; RAM = phần
heap nhả ra khi bỏ model):

| | cũ (dict lồng) | mới (bảng gọn) |
|---|---|---|
| RAM, nạp từ file tại trần (2.990 / 5.990 / 2.990) | 1,04 MB | 0,31 MB |
| RAM, phiên học dồn 40.000 từ (2.365 / 5.095 / 679) | 0,69 MB | 0,33 MB |
| File | 207 KB (plist) | 115 KB |
| Nạp (đọc + dựng bảng) | 12,4 ms | 1,0 ms |
| Lưu (encode + ghi atomic) | 5,0 ms | 0,6 ms |
| `nextWords` (đường gợi ý) | 22,6 µs | 3,5 µs |
| `count(of:)` / `bigramCount` / `trigramCount` | 0,80 / 1,33 / 1,00 µs | 0,11 / 0,26 / 0,35 µs |

Ghi chú đo: bản cũ nạp từ plist là NSDictionary bridge (tra chậm qua ObjC); số "+13 MB" trước
đây lẫn cả chục MB block DispatchWorkItem đã huỷ nhưng chờ tới hạn 5 s (mỗi record hẹn một lần lưu)
— máy thật gõ ~3 từ/s chỉ có vài block sống cùng lúc.

## 6. Các khoản nhỏ hơn (ưu tiên 4+)

| Việc | Tiết kiệm ước | Rủi ro |
|---|---|---|
| Ảnh nền giải ở @2x thay @3x (nền đã mờ/phủ tối, mắt không thấy) | −1,9 MB giữ, đỉnh giải mã −3 MB | thấp |
| `didReceiveMemoryWarning`: thêm `planeCache.removeAll()`, bỏ `EmojiData` cache, `Wallpaper.dropCache()` khi không hiện, template vuốt khi ẩn | 2–4 MB khi bị ép | thấp |
| Âm phím: đã shutdown khi ẩn ✓; nếu cần nhẹ hơn nữa: `AudioServicesPlaySystemSound` với file dựng sẵn thay AVAudioEngine | −2–3 MB khi bật | trung bình (độ trễ/âm lượng) |
| Link yếu + nạp lười AVFAudio/AudioToolbox/CoreHaptics (đang link cứng, nạp lúc khởi động dù tắt) | ~0: 14/10/2026 kiểm — AVFAudio/AudioToolbox đã trong bao đóng UIKit, CoreHaptics chỉ +1 image (xem "Framework nạp lúc khởi động") | — |
| FUTO giữ fp16, đổi fp32 theo lớp khi chạy | −1,25 MB khi bật | trung bình (CPU) |

Đã đúng (không cần làm): mmap `.alwaysMapped` cho mọi blob; ảnh nền giải bằng ImageIO thumbnail
đúng cỡ (`kCGImageSourceThumbnailMaxPixelSize`) và nhả ảnh cũ trước khi giải ảnh mới; bảng emoji
không cache; FUTO nhả khi ẩn/memory warning; AVAudioEngine tắt khi ẩn; `CADisplayLink` trackpad dùng
proxy weak; closure `onKey`… đều `[weak self]`; `leaks` không thấy chu trình nào của code mình
(469 "leak" ≈ 25 KB đều là nội bộ UIKit `_UIViewServiceLegacyClientSession`).

## 7. Thực hành tốt đã đối chiếu

- WWDC18 *iOS Memory Deep Dive* / WWDC21 *Detect and diagnose memory issues*: footprint = dirty +
  compressed; ảnh giải = rộng × cao × 4 bất kể file nén; downsample bằng ImageIO; `vmmap --summary`,
  `footprint`, `leaks --traceTree`, memory graph.
- Extension: nhả khi `viewDidDisappear` / memory warning; không giữ cache static lớn; mmap dữ liệu
  chỉ đọc; `autoreleasepool` trong vòng lặp dựng nhiều object; tránh view/layer thừa (một plane chữ
  ~40 `KeyButton` + label là ổn — chi phí chính không nằm ở số view mà ở việc cả cây bị giữ).
- Cộng đồng bàn phím (KeyboardKit, bài "three hard constraints of an iOS keyboard extension"):
  trần ~48–60 MB, jetsam không để lại crash log ⇒ phải tự đo footprint theo trạng thái như file này.

## 8. Công cụ

| Công cụ | Dùng |
|---|---|
| `iOS/Scripts/ram-audit/ram-audit.sh <default\|all\|off> [out] [udid] [cycles]` | Driver XCUITest (`Driver/`, app chủ `Host/`, `project.yml` sinh bằng xcodegen) + mẫu footprint/vmmap/heap mỗi mốc, in bảng (`summarize.py`). ~8 phút/cấu hình. |
| `iOS/Scripts/ram-audit/leak-cycle.sh [cycles]` | Ẩn/hiện không qua XCUITest, in footprint + số `KeyboardView` sống. |
| `iOS/Scripts/ram-audit/heapdiff.py a.heap b.heap` | Lớp tăng nhiều nhất giữa hai mốc. |
| `EmojiAtlasTests` (bộ chậm: `testPlaneScrollMemoryText` / `testPlaneScrollMemoryAtlas` — chạy MỖI cái một lệnh, `testMemoryTextVsAtlas`, `testFullAtlasDiskSize`) | RAM chữ vs atlas, dung lượng + thời gian dựng atlas PNG/HEIC. `TEST_RUNNER_VT_SLOW_TESTS=1 xcodebuild -scheme VietTelexKeyboardTests -only-testing:VietTelexKeyboardTests/EmojiAtlasTests/<test> test` |
| `RamBreakdownTests` (bộ chậm, scheme `VietTelexKeyboardSlowTests`) | Tách RAM từng thành phần + leak-cycles + cache glyph emoji. `TEST_RUNNER_VT_SLOW_TESTS=1 xcodebuild -scheme VietTelexKeyboardTests -only-testing:VietTelexKeyboardTests/RamBreakdownTests test` |

Lưu ý khi đo: (1) `pgrep` phải lấy đúng process extension của đúng simulator (script đã lọc theo
UDID); (2) XCUITest bật Accessibility ⇒ `_AXObjectCacheHelper` cũng giữ view — kiểm rò rỉ bằng
`leak-cycle.sh`; (3) `MallocStackLogging` qua `launchctl setenv` làm cả simulator chậm tới mức driver
hỏng — gỡ bằng `launchctl unsetenv`.
