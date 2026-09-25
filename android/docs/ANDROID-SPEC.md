# VietTelex Android — Spec (clone 1:1 app iOS 1.1)

> Trạng thái: SPEC (25/09/2026). Nguồn sự thật: repo `VietTelex-ios` @ `75384f7`
> (iOS 1.1 build 2) + `VietTelex/TelexCore`. Mục tiêu: **hành vi, giao diện, chữ,
> mặc định y hệt iOS**. Chỗ nào nền tảng Android bắt buộc khác → ghi rõ ở §12
> "Lệch nền tảng" (không được tự ý lệch ở chỗ khác).

Mọi con số `pt` của iOS = `dp` trên Android. Mọi chuỗi UI giữ nguyên tiếng Việt như iOS.

---

## 1. Nguyên tắc (kế thừa iOS)

- **Minimal tuyệt đối**: IME không kéo thư viện nào ngoài Kotlin stdlib + AndroidX
  tối thiểu (`core`, `emoji2` cho máy cũ). Không analytics, không crash SDK, không
  quảng cáo. App settings được dùng Jetpack Compose (first-party), IME **không** dùng
  Compose (chi phí khởi động).
- Mục tiêu đo mỗi milestone: IME cold-start hiện bàn phím < 200 ms, RAM IME < 30 MB,
  0% CPU khi không gõ (không timer ở idle), APK/AAB download < 10 MB.
- **Không mạng, không thu thập dữ liệu**. Dữ liệu chỉ ở `filesDir`/SharedPreferences.
- Mỗi bug sửa phải kèm regression test (quy ước dự án).

## 2. Kiến trúc

```
VietTelex/android (cùng repo public, cạnh iOS/ và TelexCore/)
├── telexcore/        Kotlin/JVM module THUẦN (không Android) — port TelexCore
│   └── test/         chạy golden corpus chung (§3.2)
├── keyboard/         logic thuần port từ iOS Keyboard/ (không Android API):
│                     EngineBridge, KeyCommitQueue, AdjacentKeyFixer, TouchGeometry,
│                     SuggestionSupport, VNSuggest, UserLangModel, SeedData,
│                     EmojiSuggest, DisplayCase, SensitiveWords, EmojiData
├── app/              APK duy nhất:
│   ├── ime/          VietTelexIME : InputMethodService + KeyboardView (Canvas)
│   └── ui/           MainActivity (Compose) — 4 tab như iOS
└── assets/           lexicon blob, ios-mau-cau.yml, SpaceLogo, icon
```

- Package: `com.viettelex.android`. IME service label: **"Tiếng Việt (VietTelex)"**.
- Một process duy nhất ⇒ settings dùng chung qua **một** `SharedPreferences`
  `"viettelex"` (thay App Group `group.com.viettelex`). Key giữ nguyên tên iOS (§9).
- minSdk 26 (Android 8), target SDK mới nhất.

## 3. Engine TelexCore

### 3.1 Cách mang sang
**Port sang Kotlin thuần** (`telexcore`), 1:1 theo file Swift:
`TelexEngine.swift` (2.3k dòng), `SyllableValidator`, `Tables`, `EnglishCollisions`,
`EnglishContextWords`. Không mang `InPlaceProbe` (đặc sản macOS). Giữ API:

| Swift | Kotlin |
|---|---|
| `feed(ch) -> TelexAction` | `feed(ch: Char): TelexAction` |
| `backspace()` | `backspace()` |
| `commitBoundary(autoRestore:)` | `commitBoundary(autoRestore)` |
| `peekCommitText(autoRestore:)` | non-mutating, không copy toàn engine |
| `composed`, `rawKeystrokes`, `isEmpty`, `reset()`, `resetContext()` | như cũ |
| `TelexAction.replace(bs, insert) / .passthrough / .none` | sealed class |
| flags: `freeMarking simpleTelex liveSpellCheck quickTelex modernTone teencode contextualEnglish` | như cũ |

Hot path zero-alloc như Swift (mảng cố định, không `String` tạm mỗi phím).

Vì sao không dùng Swift SDK for Android: kéo theo runtime Swift + Foundation (nhiều MB)
vào IME, trái nguyên tắc minimal. Đổi lại mất "sửa một chỗ cả ba thấy" → bù bằng §3.2.

### 3.2 Golden corpus chung (bắt buộc)
- Thêm vào `VietTelex/TelexCore` một target Swift `GenGolden` xuất
  `golden/telex-vectors.jsonl`: mỗi dòng `{flags, keys, expectScreen, expectCommit}`,
  sinh từ **toàn bộ** test hiện có (EngineTests, TypingMatrix, Teencode,
  ContextEnglish, Backspace, Boundary, Reopen, ScreenSimulation, VNI…) + ~20k từ
  (từ điển VN + corpus English collision).
- `telexcore` Kotlin test đọc cùng file ⇒ **100% khớp** mới được merge.
- Quy trình: sửa engine Swift → chạy GenGolden → commit vector → port sang Kotlin tới
  khi xanh. Ghi quy trình vào README cả hai repo.

### 3.3 Dữ liệu tĩnh
Các file GENERATED của iOS (`VNLexicon2`, `SeedData`, `EmojiSuggest`, `EmojiData`,
`DisplayCase`, `SensitiveWords`) phải xuất từ **cùng script** (`Scripts/gen-vnlexicon.py`…)
sang định dạng Android: blob nhị phân trong `assets/` đọc bằng mmap/`ByteBuffer`
(zero cold-start như iOS), không nhúng thành Kotlin literal khổng lồ (dex bloat).

## 4. Hành vi gõ (EngineBridge — port nguyên)

Mô hình chỉnh sửa = **diff tối thiểu** như iOS: mỗi phím → `(bs, insert)` →
`deleteSurroundingTextInCodePoints(bs, 0)` + `commitText(insert, 1)`, bọc trong
`beginBatchEdit()/endBatchEdit()`. **Không** dùng composing text/underline (iOS không có).

| Tình huống | Hành vi |
|---|---|
| Phím chữ | `engine.feed`; áp diff. Chèn **ngay lúc chạm xuống** |
| Space / return / dấu câu / số / ký hiệu | boundary: `commitBoundary(autoRestore)` rồi chèn ký tự; trả từ ĐÃ CHỐT (sau auto-restore) cho model học |
| Backspace | nếu đang soạn: `engine.backspace()` áp diff; không thì xoá 1 ký tự |
| Ô mật khẩu (secure) | literal, bỏ engine |
| Ô "không autocorrect" (passthrough) | literal, bỏ engine (xem §12 về cách map) |
| Đổi ô / con trỏ bị dời từ ngoài | `reset()` + `resetContext()`, xoá lastWord/lastWord2, huỷ undo-restore |
| Settings | đọc lại **mỗi lần bàn phím hiện** (`onStartInputView`), tạo bridge mới |

Mặc định engine (khác macOS, giống iOS): `simpleTelex=ON`, `freeMarking=ON`,
`liveSpellCheck=ON`, `autoRestore=ON`, `quickTelex=OFF`, `modernTone=OFF`,
`teencode=OFF`, `contextualEnglish=ON`, `autoFixAdjacent=ON`.

`composeTrial(raw)`: engine scratch riêng cùng setting (cho AdjacentKeyFixer), gọi được
ngoài main thread.

### 4.1 Phát hiện "đổi từ ngoài" (thay textWillChange)
Android: `onUpdateSelection(oldSel…, newSel…)`. Bridge giữ **vị trí con trỏ mong đợi**
sau mỗi edit của mình; `newSelStart != expected` (hoặc có selection) ⇒ coi là đổi từ
ngoài ⇒ reset + tính lại auto-shift + gợi ý (như `textDidChange`). Bỏ qua callback
tới trong lúc `applyingEdit`.

### 4.2 Các hành vi đặc biệt (y hệt iOS)
- **Double-space → ". "**: 2 lần space cách nhau < 0.35 s VÀ
  `TypingHeuristics.doubleSpaceMakesPeriod(context, lastWasSpace)` (ký tự trước space là
  chữ/số, không phải `.!?,`/khoảng trắng) ⇒ xoá space, chèn `". "`.
- **Auto-shift**: chỉ khi ô yêu cầu viết hoa đầu câu (`CAP_SENTENCES`): context trống,
  hoặc kết thúc `" "` sau `.!?`, hoặc sau `\n`. Chỉ nâng OFF→ON, không bao giờ hạ CAPS.
  Tính **tức thì** sau space/newline/doubleSpace/backspace/moveCursor/clear.
- **Backspace-undo auto-restore**: space làm auto-restore đổi từ (vd `hí`→`his`) ⇒ nhớ
  `(raw, composed)`. Backspace ngay sau đó ⇒ slot "nguyên văn" hiện dạng có dấu; tap ⇒
  xoá raw, chèn `composed + " "`, học weight 2.
- **Giữ backspace**: lặp sau 0.5 s, mỗi 0.09 s; giữ > 1.6 s xoá 2 ký tự/nhịp; giữ > 3 s
  chuyển sang **xoá theo từ**, mỗi nhịp thứ 4 (≈2.8 từ/s) — xoá khoảng trắng đuôi rồi
  tới đầu từ.
- **Giữ space 0.4 s = trackpad**: kéo ngang 9 dp = 1 ký tự; nhả ra **không** chèn space;
  mọi phím mờ keycap (alpha 0.2) + nền phẳng. Reset engine khi con trỏ dời.
- **Shift**: bật ở **touch-down**; 2 lần < 0.3 s = CAPS. Shift ON tự tắt sau 1 chữ.
  Không bao giờ dựng lại view khi đổi shift — chỉ retitle.
- **Badge ngôn ngữ**: mỗi lần hiện, chữ "ViệtTelex" giữa phím space 0.7 s rồi fade 0.3 s
  (logo Vᴛ ẩn trong lúc đó).

## 5. Touch & độ chính xác (bài học iOS — bắt buộc)

- **Nền bàn phím đục toàn bộ** (không vùng trong suốt) — trên Android không có lỗi
  backboardd, nhưng giữ `touchableRegion` = toàn khung (`onComputeInsets`:
  `TOUCHABLE_INSETS_FRAME`/`CONTENT`) để chạm vào khe không rơi sang app.
- **Một mặt touch duy nhất** (một `View` custom), multi-pointer (`ACTION_POINTER_DOWN`).
  Không dùng Button/View con cho từng phím.
- **Nearest-key router** cho plane chữ: điểm chọn = điểm chạm dời lên
  `TouchGeometry.yOffset = 4dp`. Trong footprint phím nở (dx 3, dy 5.5) ⇒ phím đó; không
  thì phím gần nhất nếu khoảng cách ≤ 21 dp; phím chữ **thắng** vùng nở của shift/⌫.
  Touch ở strip gợi ý không bị router cướp.
- **KeyCommitQueue** (port nguyên + test): phím chữ chèn lúc DOWN; space/dấu câu/số/
  return **arm lúc DOWN, chốt lúc UP**, hoặc lúc `ACTION_CANCEL`, hoặc sớm hơn khi ngón
  khác chạm xuống (flush theo thứ tự). Trackpad ⇒ disarm. Cancel **vẫn chốt** phím chữ.
- Âm/rung phát ở touch-down (§8).

## 6. Giao diện bàn phím

Clone giao diện bàn phím **iOS** (không phải Gboard). Vẽ bằng Canvas, cache
`Path`/`Paint`, không alloc trong `onDraw`.

### 6.1 Kích thước
| Thành phần | Giá trị |
|---|---|
| Vùng phím dọc (điện thoại) | **218 dp**; ngang 162 dp |
| Tablet | 240 dp dọc / 300 dp ngang |
| Chỉnh chiều cao | `rowHeightAdjust` −10…+10 dp **mỗi hàng** (×4 cho cả bàn phím) |
| Strip gợi ý | mở **34 dp** (đệm trên `barTopPad` 4 dp + bar 20 dp + 10 dp); thu gọn 14 dp; tắt 0 |
| Plane emoji | **giữ nguyên** chiều cao strip (chỉ ẩn bar) — không đổi chiều cao khi vào emoji |
| Hàng phím | 4 hàng chia đều; khoảng cách phím 6 dp; margin hàng trên/dưới 5 dp, trái/phải 3 dp |
| Hàng đáy | margin trên 10 / dưới 0 (sát đáy như stock) |
| Phím | bo góc 5 dp; bóng phẳng 1 dp lệch xuống (đen, opacity 0.35 sáng / 0.30 tối), không blur |
| Font | chữ 23 sp regular; phím chức năng 16 sp |
| Navigation bar | cộng thêm inset nav bar/gesture bar **dưới** vùng phím (nền cùng màu bàn phím) |

### 6.2 Màu
| | Sáng | Tối |
|---|---|---|
| Phím thường | `#FFFFFF` | white 0.42 (`#6B6B6B`) |
| Phím chức năng | rgb(0.68,0.70,0.74) | white 0.26 (`#424242`) |
| Chữ/icon | đen | trắng |
| Shift ON/CAPS | nền trắng, glyph đen (cả 2 mode) | |
| Return hành động | `systemBlue` + chữ trắng semibold 16; bấm alpha 0.7 | |
| Nền bàn phím | xám nền bàn phím iOS tương ứng mode | |

Nhấn phím chức năng: đổi màu phẳng sang màu phím thường (không animation). Space
bấm ⇒ sẫm sang màu chức năng. Dark theo `Configuration.uiMode` (night), đổi giữa chừng
⇒ áp lại.

### 6.3 Plane chữ
```
q w e r t y u i o p
 a s d f g h j k l          (thụt 0.5 phím mỗi bên)
⇧  z x c v b n m  ⌫         (⇧ và ⌫ = 1.5 phím chữ; lưới 10 cột)
[123][🌐?][😊][      space  Vᴛ][,][return]
```
- Hàng đáy tỉ lệ bề ngang: `123` 0.12, emoji 0.10, `,` 0.075, return 0.14, space phần
  còn lại; tablet thêm phím ẩn bàn phím 0.07 ở cuối.
- 🌐 chỉ hiện khi `shouldOfferSwitchingToNextInputMethod()`; tap ⇒
  `switchToNextInputMethod(false)`, giữ ⇒ `showInputMethodPicker()`.
- Ô email: `,` ⇒ `@` (0.11) + `.` (0.09). Ô URL: `.` (0.075) `/` (0.075) `.com` (0.17).
- Logo Vᴛ mờ (alpha 0.16, 22 dp) mép phải space, tắt được (`showSpaceLogo`).
- Return: icon `return.left` mờ 0.16 khi là xuống dòng; nhãn `go/search/send/next/done/join`
  theo `imeOptions`; `go`/`search` hiện **mũi tên →** trắng thay chữ.

### 6.4 Plane số / ký hiệu
```
123:  1 2 3 4 5 6 7 8 9 0
      - / : ; ( ) $ & @ "
      [#+=] . , ? ! ' [⌫]
      [ABC][🌐][😊][space][,][return]
#+=:  [ ] { } # % ^ * + =
      _ \ | ~ < > € ¥ ₫ •
      [123] . , ? ! ' [⌫]
```
Ô số (`TYPE_CLASS_NUMBER/PHONE/DATETIME`) mở thẳng plane 123. Về plane chữ ⇒ shift ON
tự tắt.

### 6.5 Balloon phím
Phím chữ và phím ký tự hiện balloon kiểu iOS (bubble loe phía trên, cổ cong ôm liền
phím) lúc chạm, ẩn lúc nhấc. Hàng trên cùng được leo lên vùng strip gợi ý (headroom),
bị kẹp trong khung IME. Path cache theo hình dạng.

### 6.6 Thanh gợi ý
- Layout: `[☰ 52dp] [ "nguyên văn" | từ 1 | từ 2 hoặc ≤3 emoji ] [⌄ 52dp]`,
  divider 1 dp (ink alpha 0.18, cách trên/dưới 4 dp), chữ 17 sp, emoji 20 sp.
- ☰ (mẫu câu) và ⌄ (thu gọn) **ghim mép**, vùng chạm cao trọn strip; icon canh ở dòng
  chữ 20 dp trên cùng; ☰ alpha 0.9 khi plane mẫu câu mở, 0.45 khi không; ☰ ẩn nếu tắt
  mẫu câu.
- Slot có vùng chạm nở: trên 8, trái/phải 3, dưới phủ hết phần còn lại của strip —
  **không** lấn hàng Q–P.
- Thu gọn: animation 200 ms (chiều cao + fade + chevron xoay 180°); còn strip 14 dp với
  ☰ nổi (trái, 64×18) và ⌄ nổi (phải, 48×18). Trạng thái thu gọn lưu
  `suggestionBarCollapsed`. Khi thu gọn **ngừng toàn bộ pipeline gợi ý**.
- Bỏ qua ghi UI khi nội dung không đổi (so chữ ký).
- Tắt bar tự động ở ô mật khẩu và ô passthrough.

## 7. Gợi ý (port nguyên `docs/IOS-SUGGESTIONS.md`)

Toàn bộ thuật toán, trọng số, ngưỡng, hợp đồng seed giữ nguyên; tóm tắt:

| Trạng thái | 3 slot |
|---|---|
| Rule email: token trước con trỏ kết thúc `@` (dài > 1) | `gmail.com  yahoo.com  outlook.com` (chèn không kèm space) |
| Rule TLD: token kết thúc `.` sau chữ/số | `com  vn  net` |
| Ô trống / sau ngắt câu | top 3 từ hay dùng (`topWords`) |
| Vừa space sau một từ | 3 từ kế tiếp (trigram ⊕ bigram ⊕ seed, shrinkage) |
| Đang gõ dở | `"nguyên văn"` · ứng viên 1 · ứng viên 2 **hoặc** ≤3 emoji |

- **Slot nguyên văn** = phương án boundary SẼ KHÔNG cho ra: `predicted == composed ? raw : composed`.
- Ranking inline: `log(freq+1) + 2.5·log(personal+1) + 4·[trong nextWords ngữ cảnh] + 1.5·[cùng độ dài]`.
- Không ứng viên nào + `autoFixAdjacent` ⇒ `AdjacentKeyFixer.lexiconCorrection` lên slot 1
  (đảo 2 phím thắng; 1 thay rồi 2 thay ≤8 chữ; cắt tỉa tiền tố chết; cache theo raw).
  **Neighbor map giữ theo lưới QWERTY iOS** (hàng 2 lệch 0.5, hàng 3 lệch 1.5).
- Emoji: thử cụm `lastWord + " " + từ`, rồi từ đang gõ, rồi raw. Emoji **không** bị lọc
  nhạy cảm. Không có emoji ⇒ đệm 2 từ.
- Luôn đủ 3 slot (đệm bằng `topWords`, loại trùng + từ đang gõ — `SuggestionFill.pad`).
- Đầu câu (auto-shift ON) ⇒ viết hoa chữ đầu gợi ý. `DisplayCase` cho proper noun.
- Chạm từ ⇒ thay từ đang gõ + space, học weight 2; chạm emoji ⇒ thay từ bằng emoji;
  chạm fragment (`.`/`@`) ⇒ chèn không space.
- Luồng: gợi ý hoãn 30 ms theo generation (phím mới huỷ lượt cũ); VNSuggest +
  AdjacentKeyFixer chạy **thread nền**, main chỉ re-rank + vẽ; kết quả chỉ áp khi còn
  hiện hành (cùng lượt, cùng bridge, cùng từ).
- `UserLangModel`: cap 3000/6000/3000, halve khi tràn, decay ×0.7/tuần lúc load, học
  chữ thuần ≤ 12 ký tự không lặp ≥3, từ ngoài lexicon cần count ≥ 3 mới được gợi ý,
  trigram chỉ khi bigram nền ≥ 2. Lưu **binary** `filesDir/userlm.bin` qua `AtomicFile`,
  coalesce 5 s sau phím cuối + khi `onFinishInputView`; load nền, gợi ý mở đầu refresh
  khi xong. Seed khi trống.
- Mẫu câu và dán **không** học vào model.

### 7.1 Nút Dán (iOS 1.1)
- Hiện **thay cả bar** (một thẻ rộng giữa ☰ và ⌄, 2 dòng: icon clipboard + "Dán" 14 sp /
  "Nội dung vừa copy" 10 sp alpha 0.55), neo sát đỉnh bar.
- Điều kiện: không đang gõ dở; ký tự trước con trỏ là khoảng trắng hoặc ô trống;
  clipboard có **text** mới (đổi trong 180 s qua, chưa dán lần này). Ảnh ⇒ **không**
  hiện. Cache kết quả 2 s. Có phím chữ ⇒ ẩn thẻ ngay.
- Chạm ⇒ `commitText(clip)`, đánh dấu đã dùng, reset engine + context.
- Android: nguồn = `ClipboardManager` + `addPrimaryClipChangedListener` (thay
  `changeCount`); đọc nội dung chỉ khi user chạm.

## 8. Âm thanh & rung
- Âm: `AudioManager.playSoundEffect(FX_KEYPRESS_*)` ở touch-down, tôn trọng cài đặt
  âm bàn phím của hệ thống.
- Rung: toggle `hapticFeedback` (mặc định TẮT) ⇒ `performHapticFeedback(KEYBOARD_TAP)`.
  Android không cần Full Access ⇒ bật là chạy.

## 9. Settings (key = iOS)

| Key | Mặc định | Tab / Nhãn | Chú thích (giữ nguyên chữ iOS) |
|---|---|---|---|
| `simpleTelex` | true | Kiểu Gõ · Telex đơn giản | Phím w đứng lẻ giữ nguyên là w, không thành ư. |
| `freeMarking` | true | Kiểu Gõ · Bỏ dấu tự do | Phím dấu đặt đâu cũng được, không cần đúng thứ tự. |
| `quickTelex` | false | Kiểu Gõ · Gõ nhanh (Quick Telex) | cc → ch, nn → ng, tt → th… |
| `modernTone` | false | Kiểu Gõ · Bỏ dấu kiểu mới | hoà, thuý thay vì hòa, thúy. |
| `contextualEnglish` | true | Kiểu Gõ · Quyết định theo ngữ cảnh | "he is" → he is… "sao í" |
| `autoFixAdjacent` | true | Kiểu Gõ · Gợi ý sửa lỗi chạm trượt | nbjeeuf → nhiều, ohims → phím, cahcs → cách… |
| `teencode` | false | Kiểu Gõ · Chính tả teencode | wá, zui zẻ, kó, bíe, thík, gòy, ừk… |
| `autoRestore` | true | Tính Năng › Chính tả · Tự khôi phục từ tiếng Anh | |
| `liveSpellCheck` | true | Tính Năng › Chính tả · Kiểm tra chính tả khi gõ | |
| `showSuggestions` | true | Tính Năng › Gợi ý · Thanh gợi ý (kéo theo học từ) | |
| `filterSensitive` | true | Tính Năng › Gợi ý · Lọc từ nhạy cảm khỏi gợi ý | |
| `templatesEnabled` | true | Tính Năng › Gợi ý · Mẫu câu (ẩn/hiện tab Mẫu Câu) | |
| nút "Xóa từ đã học" | — | Tính Năng › Gợi ý (destructive) | xoá userlm, seed lại |
| `showSpaceLogo` | true | Tính Năng › Giao diện · Hiện logo Vᴛ | |
| `hapticFeedback` | false | Tính Năng › Giao diện · Rung phím | |
| `rowHeightAdjust` | 0 | Tính Năng › Giao diện · Stepper "Chiều cao hàng phím" −10…10 | "Chuẩn" / "%+d pt mỗi hàng (%+d pt cả bàn phím)" → đổi "pt" thành "dp" |
| `userTemplates` | từ `ios-mau-cau.yml` | Tab Mẫu Câu | list `{label,text}` |
| `debugTouchLog` | false | Giới Thiệu › Gỡ lỗi | |
| `suggestionBarCollapsed`, `emojiRecents` | | nội bộ IME | |

Footer các section: "Cài đặt áp dụng ngay lần mở bàn phím kế tiếp."

## 10. Plane emoji & mẫu câu

### 10.1 Emoji
- Lưới lớn **cuộn ngang, column-major, 5 hàng**, liên tục qua category; tiêu đề section
  nhỏ xám (dải 14 dp) trên cột đầu mỗi category, không tràn sang section kế.
- Hàng dưới: `[ABC] [9 icon category] [⌫]`; icon category đang xem có highlight tròn;
  chạm icon cuộn tới section, giữ highlight icon vừa chạm khi section cuối không cuộn
  tới mép được.
- Category (tên hiển thị): THƯỜNG DÙNG · MẶT CƯỜI & NGƯỜI · ĐỘNG VẬT & THIÊN NHIÊN ·
  ĐỒ ĂN & ĐỒ UỐNG · HOẠT ĐỘNG · DU LỊCH & ĐỊA ĐIỂM · ĐỒ VẬT · BIỂU TƯỢNG · CỜ. Dữ liệu =
  `EmojiData` (cờ 🇻🇳 đầu tiên).
- Recents tối đa 30, section 🕐 xuất hiện ngay lần dùng đầu trong phiên.
- Giữ emoji có tông da ⇒ popup 6 biến thể (gốc + 5 tông, áp cho mọi base trong ZWJ).
- ⌫ giữ = lặp như bàn phím chữ. Dùng `emoji2` để hiển thị trên máy cũ.

### 10.2 Mẫu câu (☰)
- Plane: bubble chips dạng tag cloud, cuộn dọc; có label ⇒ chỉ hiện label, không thì
  text cắt "…"; bubble ⚙️ cuối cùng mở app tab Mẫu Câu (`viettelex://maucau`).
- Hàng đáy: `[ABC] [🗑 xoá sạch ô] [space] [,] [return]` — hàng đáy cao đúng 1 hàng phím.
- Chạm chip ⇒ về plane chữ, xoá từ đang soạn, chèn nguyên văn, reset engine, không học.
- Mẫu bắt đầu `https://` = **mẫu động**: fetch lúc chạm (timeout 4 s), chèn body đã trim
  (≤ 1000 byte); lỗi ⇒ chèn chính URL. Android cần quyền `INTERNET` (§12).
- 🗑: xoá toàn bộ nội dung ô (dời con trỏ về cuối rồi xoá lùi, có giới hạn an toàn
  20 000 ký tự).

## 11. App settings (MainActivity, Compose)

Cấu trúc **y hệt** iOS: một danh sách kiểu grouped (inset) + **thanh tab nổi dạng viên
thuốc** ở đáy (icon trên chữ; thu về icon-only khi cuộn xuống > 40 dp, bung lại khi cuộn
lên; pill chọn trượt bằng spring; màu nhấn `accentBlue` sáng rgb(0.02,0.32,0.84) /
tối rgb(0.30,0.52,1.00)). Ẩn thanh tab khi bàn phím đang hiện. Toggle màu xanh lá
hệ thống. Nền card: surface mờ + viền nhẹ (tương đương fallback iOS < 26).

Tab: **Kiểu Gõ** (⌨) · **Tính Năng** · **Mẫu Câu** (chỉ khi `templatesEnabled`) ·
**Giới Thiệu**. Tiêu đề: tab Kiểu Gõ hiện "VietTelex", tab khác hiện tên tab.

### 11.1 Kiểu Gõ
1. **OnboardingCard**:
   - Chưa bật: icon 64, "Bật bàn phím VietTelex", checklist 2 bước, hướng dẫn đường dẫn
     Cài đặt (viết lại theo Android, §12), nút chính "Mở Cài đặt"
     (`Settings.ACTION_INPUT_METHOD_SETTINGS`).
   - Đã bật nhưng chưa chọn làm bàn phím hiện tại: thêm nút "Chọn VietTelex"
     (`showInputMethodPicker()`).
   - Đã bật: dòng tick xanh "Bàn phím đã bật" / "Thử gõ ngay bên dưới." (thu gọn).
   - Phát hiện: `enabledInputMethodList` chứa service; làm mới mỗi `onResume`.
   - Khối "Để dán nhanh từ thanh gợi ý" của iOS **bỏ** (Android không có prompt dán).
2. **Thử gõ**: ô nhiều dòng (1–4), không tự viết hoa, **không** tắt suggestions (để bàn
   phím không vào passthrough). Footer: "Bấm 🌐 … rồi gõ thử: vieejt → việt." (đổi 🌐
   thành hướng dẫn chọn bàn phím Android nếu cần).
3. Các toggle Kiểu gõ (§9).

### 11.2 Tính Năng — 3 section Chính tả / Gợi ý / Giao diện (§9).

### 11.3 Mẫu Câu
Danh sách (label | text, vuốt để xoá), "Thêm mới" (ô label 44 dp + ô câu + nút ＋, chặn
trùng), section "Mẫu câu động (https://)", **Import…** / **Export ra YAML…** (SAF
`OpenDocument`/`CreateDocument`, tên `viettelex-mau-cau.yaml`), thông báo
"Đã thêm x/y mẫu (trùng bị bỏ qua)." Định dạng YAML phẳng giống hệt
(`- "label | câu"` hoặc `- "câu"`, `\"` escape). Mặc định = `ios-mau-cau.yml` (dùng chung
file, copy vào assets lúc build).

### 11.4 Giới Thiệu
- **Gỡ lỗi**: "Debug mode — ghi log chạm phím" + khi bật: "Hiện log (tự copy vào
  clipboard)" (80 dòng cuối, monospace) và "Xoá log". Log `filesDir/touchlog.txt`, cap
  300 KB giữ nửa mới; **bản Release không ghi ký tự gõ**.
- Logo 88 dp + "VietTelex" + "Bàn phím Telex tiếng Việt".
- Tài nguyên: Website `https://ptrinh.github.io/viettelex/`, Học gõ Telex `…/learn/`,
  Mã nguồn GitHub (mở trình duyệt, không WebView).
- Phiên bản "x.y · build dd/MM/yyyy", "© Phil Trinh <năm>", mailto `vt@trinh.uk`,
  "Không thu thập dữ liệu · Không theo dõi · Mã nguồn mở". Dòng Full Access của iOS ⇒
  thay bằng giải thích cảnh báo hệ thống của Android (§12).
- Deep link `viettelex://maucau` ⇒ bật `templatesEnabled`, nhảy tab Mẫu Câu.

## 12. Lệch nền tảng (đã chốt cách map)

| iOS | Android | Ghi chú |
|---|---|---|
| Keyboard extension + app chứa, App Group | 1 APK, IME service + Activity, 1 SharedPreferences | Hết cảnh "không Full Access thì không ghi được App Group" |
| Full Access (rung, mẫu động, dán, log) | Không có khái niệm. Rung: không cần quyền. Mạng: `INTERNET` trong manifest (chỉ dùng cho mẫu động do user tạo). Clipboard: IME đang focus đọc được | Bỏ `FullAccessNotice`, `kbFullAccess`, `kbLastSeen`, `pasteNoPrompt` |
| Prompt "Allow Paste" | Android 12+ hiện toast hệ thống "VietTelex đã dán từ bộ nhớ đệm" | chấp nhận |
| `textDocumentProxy` insert/delete | `InputConnection` + batch edit, `deleteSurroundingTextInCodePoints` | §4 |
| `textWillChange/DidChange` | `onUpdateSelection` + expected cursor | §4.1 |
| `keyboardType` | `EditorInfo.inputType` class/variation | §6.3–6.4 |
| `returnKeyType` | `imeOptions & IME_MASK_ACTION`; `IME_FLAG_NO_ENTER_ACTION` hoặc ô multiline ⇒ xuống dòng; hành động ⇒ `performEditorAction` | |
| `autocapitalizationType == .sentences` | `inputType & TYPE_TEXT_FLAG_CAP_SENTENCES` | |
| `isSecureTextEntry` | variation `PASSWORD / WEB_PASSWORD / NUMBER_PASSWORD / VISIBLE_PASSWORD` | ⇒ literal |
| `autocorrectionType == .no` ⇒ passthrough | **Đề xuất**: passthrough khi variation `URI`, `EMAIL_ADDRESS`, `VISIBLE_PASSWORD`, `FILTER`; `TYPE_TEXT_FLAG_NO_SUGGESTIONS` chỉ ẩn bar, **không** passthrough | Nhiều app chat Android đặt NO_SUGGESTIONS — map thẳng sẽ tắt Telex ở đó. Phải test ma trận §13 rồi chốt |
| `keyboardAppearance` | theo night mode hệ thống | |
| Globe / `handleInputModeList` | `switchToNextInputMethod` / `showInputMethodPicker` | |
| Mở app từ extension (cần Full Access) | `startActivity(FLAG_ACTIVITY_NEW_TASK)` từ IME | luôn chạy |
| Liquid Glass | surface bán trong + viền, không blur | |
| Home indicator / chrome host vẽ | inset nav bar do IME tự đệm | `barTopPad` 4 dp giữ để giống hình |
| Cảnh báo | Android hiện cảnh báo hệ thống khi bật IME bên thứ ba ("có thể thu thập mọi văn bản bạn nhập") | Onboarding thêm 1 dòng trấn an: "Cảnh báo này hiện với mọi bàn phím bên thứ ba — VietTelex chạy hoàn toàn trên máy, không gửi gì đi." |
| Cài đặt → Chung → Bàn phím → Thêm bàn phím mới… | Cài đặt → Hệ thống → Ngôn ngữ & nhập liệu → Bàn phím trên màn hình → Quản lý → bật VietTelex | chữ onboarding viết lại cho Android |

## 13. Kiểm thử

- **Unit (JVM)** port toàn bộ test iOS: `EngineBridgeTests`, `FeatureRegressionTests`,
  `KeyCommitQueueTests`, `AdjacentKeyFixerTests`, SuggestionSupport, TouchGeometry, YAML
  parse/export, UserLangModel (shrinkage, trigram gating, ngưỡng từ lạ, decay, seed ≤ 50).
  Lưu ý: 2 test iOS đang fail sẵn (`testAutoRestoreAndCollisions` "of"/"off",
  `testRestorePairForUndo`) — chốt kỳ vọng đúng theo engine hiện tại trước khi port.
- **Golden corpus** §3.2: 100% khớp.
- **Instrumented**: mock `InputConnection` ghi lại chuỗi màn hình ⇒ so với golden.
- **Ma trận field thật**: Messenger, Zalo, Telegram, WhatsApp, Gmail, Chrome (ô địa chỉ +
  form web), Google Docs, Notes/Keep, Samsung Notes, ô mật khẩu, ô số/điện thoại/email/URL,
  Termux (TUI). Kiểm: không mất dấu, không nhân đôi ký tự, backspace đúng, auto-restore.
- **Gõ nhanh**: kịch bản "abcdefgh" lăn ngón, 2 ngón cái "anh em" — không rớt, đúng thứ tự.
- Thiết bị: Pixel (gesture nav + 3-button), Samsung One UI, 1 máy Android 8–9, 1 tablet.
- Đo & ghi bảng: cold-start, RAM, độ trễ phím (touch-down → commitText), APK size.

## 14. Phát hành

- Google Play, AAB ký bằng Play App Signing; R8 + resource shrink.
- Data safety: **không thu thập, không chia sẻ**. Privacy policy = bản iOS chỉnh chữ
  "iOS/Full Access" ⇒ Android (host cùng `ptrinh.github.io/viettelex`).
- Store listing: tên "VietTelex — Bàn phím Telex", ảnh chụp theo bộ `store-assets` iOS.
- Version khởi đầu `1.1` (khớp tính năng iOS 1.1), versionCode 1.

## 15. Milestones

| M | Nội dung | Ước lượng |
|---|---|---|
| A0 | Repo, module, GenGolden bên Swift, port TelexCore Kotlin tới 100% golden | 3–4 ngày |
| A1 | IME tối thiểu: plane chữ + shift + ⌫ + space/return, diff-edit, router + commit queue | 2 ngày |
| A2 | Đủ bàn phím: plane số/ký hiệu, input kind, return action, balloon, trackpad, ⌫ giữ, double-space, auto-shift, dark, tablet, nav inset | 3 ngày |
| A3 | Gợi ý đủ 6 tầng + AdjacentKeyFixer + Dán + mẫu câu + emoji plane | 4–5 ngày |
| A4 | App settings Compose 4 tab + onboarding + import/export + debug log | 2–3 ngày |
| A5 | Ma trận field, đo hiệu năng, sửa lệch, Play internal testing → production | ~1 tuần |

## 16. Quyết định còn mở
1. Map passthrough cho `TYPE_TEXT_FLAG_NO_SUGGESTIONS` (§12) — đề xuất: chỉ ẩn bar.
2. Giao diện phím: clone iOS (mặc định của spec) hay theo Material/Gboard cho quen tay
   người dùng Android? Spec này theo yêu cầu "giống hệt iOS".
3. Repo Android public (như macOS) hay private (như iOS)?
