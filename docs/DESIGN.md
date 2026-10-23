# VietTelex — Design

Bộ gõ tiếng Việt cho macOS. Ưu tiên tuyệt đối: **performance** (latency, CPU, RAM) và **simplicity**.

## Phạm vi

- Kiểu gõ: **Telex** đầy đủ (mặc định): aa→â, aw→ă, dd→đ, ee→ê, oo→ô, ow→ơ, uw→ư,
  `w` đầu từ → ư, s/f/r/x/j = sắc/huyền/hỏi/ngã/nặng, z = xóa dấu. Tùy chọn
  **Simple Telex** (OFF mặc định): `w` lẻ giữ nguyên. **Bỏ dấu tự do** ON mặc định
  (dấu/mũ gõ muộn tự tìm về nguyên âm — `dauas`→dấu). Hỗ trợ teencode qua onset
  mapping (wá→quá, zô→dô, dzị→dị) và whitelist `đc`; từ tiếng Anh va chạm
  (was/wow/yes) force-restore. Không VNI, không hỗn hợp.
- **Teencode (2026-08-04)**: (1) *kéo dài* — âm tiết hợp lệ + đuôi lặp CÙNG một chữ
  ≥ 3 lần được giữ nguyên như trên màn hình (`hoonggggg`→hônggggg, `cosaaaaaaa`→
  cóaaaaaa, `ddepjpppp`→đẹppppp): live spell-check không đóng băng, dấu đặt trong
  phần âm tiết (không trôi ra đuôi), boundary không auto-restore. Đuôi lặp 2 lần
  vẫn restore (tiếng Anh nhân đôi chữ suốt: wall/eggs/apps). (2) vần mở **"ie"**
  là vần hợp lệ (`bies`→bíe, `miej`→mịe); đổi lại 12 từ Anh dạng `-ie(s)`
  (dies/ties/lies/life/chief…) commit thành tiếng Việt cho tới khi bảng
  EnglishCollisions được sinh lại.
- Bảng mã: **Unicode dựng sẵn (NFC precomposed)** duy nhất.
- Tùy chọn: Simple Telex, bỏ dấu tự do, kiểu bỏ dấu cũ/mới (hòa/hoà), kiểm tra chính tả
  khi gõ, tự khôi phục từ không hợp lệ, bảng gõ tắt.
- **Không có bật/tắt VI/EN nội bộ, không hotkey riêng**: Vietnamese bật khi VietTelex là
  input source đang chọn; chuyển input source để gõ tiếng Anh (macOS nhớ theo app).
- KHÔNG làm: nhớ theo browser tab (IME không thấy được tab), từ điển file
  (dùng phonotactic validator).

## Kiến trúc

```
VietTelex.app  (một bundle duy nhất, LSUIElement)
├── IMKServer + TelexInputController   ← process do macOS launch khi user chọn input source
│     đường IMKit: in-place insertText (mặc định) hoặc marked-text (app học được qua probe)
├── TerminalTapController              ← CGEventTap cho terminal / Chromium / Excel
│     (cần quyền Accessibility — chỉ bản Developer ID; bản sandbox tự rơi về marked-text)
├── TelexEngine        (TelexCore — pure Swift, zero-heap hot path)
├── SyllableValidator  (rule-based, không từ điển)
├── AppState           (UserDefaults, cache in-memory, học chiến lược per-app;
│     rule mặc định load từ typing-modes.yml bundle — sửa rule = sửa data, không sửa Swift)
└── SettingsWindow     (SwiftUI: Gõ phím, Công cụ & gợi ý, Gõ tắt, Ứng dụng
      (bảng cơ chế gõ), Chung (giới thiệu, cập nhật, chẩn đoán); chỉ tạo khi mở,
      đóng là giải phóng)
```

Quy tắc cứng:
1. **Một process duy nhất.** Không helper app, không XPC, không login item (input method
   được macOS tự khởi động).
2. **Không timer, không polling trên đường gõ.** Toàn bộ event-driven. Ngoài main
   có đúng MỘT thread thường trực: run loop của event tap (ngủ trong mach_msg,
   zero CPU khi idle) — để callback tap không xếp hàng sau XPC IMKit ~2ms/phím
   trên main (jitter terminal + nguy cơ macOS disable tap vì callback chậm).
   Shared state giữa hai thread đều có lock (AppState, Accessibility,
   SpotlightDetector, FrontmostApp, SyntheticKeyboard, activation). Hai ngoại lệ
   có chủ đích, đều KHÔNG chạy khi idle thuần: watchdog 3s trên main CHỈ tồn tại
   khi tap đang sống (phát hiện revoke quyền — xem lịch sử treo bàn phím), và
   auto-update check theo tuần (opt-in, throttle bằng timestamp lúc activate).
3. **Không NSStatusItem.** Dùng menu do IMK cung cấp: dòng tình trạng (quyền
   Accessibility) + Cài đặt….
4. Settings UI chỉ instantiate khi user mở; đóng là giải phóng.

## Chiến lược gõ theo app (5 đường, tự học)

| Đường | Áp dụng cho | Cơ chế |
|---|---|---|
| **In-place** (mặc định) | App Cocoa chuẩn (TextEdit, Safari, Mail…) | `insertText(_:replacementRange:)`, không gạch chân, track anchor cục bộ |
| **Marked text** | App bỏ qua replacementRange, khi KHÔNG có quyền AX | `setMarkedText`, có gạch chân tạm khi gõ |
| **Tap: backspace-retype** | Terminal, iTerm, Electron (Lark/Slack/Discord/VSCode) — cần AX | CGEventTap chặn phím, synth Backspace×N + Unicode |
| **Tap: selection-replace** | Address bar browser (qua `axDetect` per-field) — cần AX | Shift+←×N chọn rồi ghi đè — né race với inline autocomplete; D1 gộp burst thành 1 AX write (default ON) |
| **Tap: empty-reset** | Excel (cần AX) | Chèn U+202F hủy suggestion rồi Backspace-retype (Shift+← trong ô sẽ chọn ô kề) |

- Rule mặc định per-app nằm trong **`typing-modes.yml`** (repo root, bundle vào app,
  đính kèm release) — đóng góp rule = sửa plist, không sửa Swift. Mode `axDetect`
  dò theo Ô đang focus (address bar → selection, nội dung trang → in-place).
- App chưa phân loại được **probe** (2 tầng: verdict sơ bộ sync từ read-back/caret —
  honored cần xác nhận ở 2 offset khác nhau, chống caret rác hằng số kiểu Lark;
  AX ground truth async override sau). Kết quả persist (`probedApps` / `fallbackApps`).
- **Remote desktop / VM / screen-share** (`ClientPolicy.forcePassthroughBundleIDs`
  + `isRemoteDesktopURL` cho Chrome Remote Desktop trong browser):
  forward scancode thô nên IME passthrough hoàn toàn. Khi cả máy local lẫn máy
  remote đều chạy VietTelex, chỉ máy remote được gõ — local tự tắt trong canvas
  remote (tránh hai bộ gõ giành nhau, dấu nhảy loạn).
- **Secure input** (password field): kiểm tra `IsSecureEventInputEnabled()` đầu
  `handle()` — bypass sạch, không xử lý, không log.

## Hot path — `handle(_ event:client:) -> Bool`

Đường đi mỗi keystroke, budget **< 50µs, zero heap allocation** (đo thực tế:
xem [`BENCHMARKS.md`](BENCHMARKS.md)):

1. Synthetic event của chính mình / secure input / remote desktop / modifier (⌘⌃⌥)
   → passthrough, reset khi cần.
2. Map keycode/char → feed vào `TelexEngine`.
3. Engine trả về `.passthrough` / `.none` / `.replace(backspaces, insert)` — diff tối
   thiểu giữa render mới và text đang trên màn hình.
4. Word boundary (space/enter/punct/click/focus đổi): commit, chạy validator + bảng
   gõ tắt, reset buffer.

Yêu cầu engine:
- `struct TelexEngine`, buffer cố định capacity 32, **không** String
  interpolation/regex/NSString trên hot path.
- Bảng biến đổi nguyên âm + đặt thanh là `static let` lookup tables, build một lần.
- Double-key hủy dấu (aaa→aa, ss→s) + latch: từ đã hủy dấu là tiếng Anh, các phím sau
  literal.
- Backspace xóa nguyên ký tự hiển thị cuối (không chỉ pop một phím raw), re-render.
- Backspace ngay sau ranh giới **mở lại từ vừa chốt** (issue #40): boundary nhớ đúng
  chuỗi phím nó vừa commit (chỉ khi màn hình đang hiển thị `composed` — không
  auto-restore, không overflow, không gõ tắt), ⌫ xóa ký tự ranh giới thì replay lại
  chuỗi đó nên `tháy` ␣ ⌫ `a` → `thấy` thay vì `tháya`. Snapshot chết ngay khi có
  bất kỳ input nào khác, và chỉ được dùng sau khi **đọc lại text trên màn hình**
  (IMKit: `attributedSubstring`; tap: AX) đúng bằng từ đó.

Quy tắc ổn định đã rút ra khi implement (chi tiết trong `MACOS_IME_NOTES.md`):
- Mọi edit đi qua **một kênh có thứ tự duy nhất** (không trộn passthrough hệ thống với
  insertText của mình — race khi gõ nhanh làm "được"→"đựoc").
- Không gọi `selectedRange()` sau mỗi insert (caret stale khi gõ nhanh) — track anchor
  cục bộ, chỉ đọc một lần ở phím đầu của từ.
- Tap callback phải O(1); event synth phải đóng dấu timestamp tăng nghiêm ngặt để
  window server không đảo thứ tự.

## SyllableValidator (thay từ điển)

Âm tiết tiếng Việt đóng theo luật → validate bằng phonotactics, không cần file:
- Parse: onset (∅, b, c, ch, d, đ, g/gh, gi, h, kh, l, m, n, ng/ngh, nh, p, ph, qu, r,
  s, t, th, tr, v, x) + rime (bảng ~180 vần hợp lệ hard-code) + tone.
- Ràng buộc: coda p/t/c/ch chỉ đi với sắc/nặng.
- `isValidSyllable` dùng ở ranh giới từ cho auto-restore; `isValidPrefix` (fold nguyên
  âm về gốc để chấp nhận trạng thái Telex trung gian) dùng cho live spell-check.
- Chi phí: O(độ dài từ), zero RAM ngoài static tables.
- Hạn chế cố hữu (chấp nhận): từ tiếng Anh trùng âm tiết Việt hợp lệ (`test`→tét,
  `list`→lít) không khôi phục được — cần từ điển/tần suất, ngoài phạm vi.

## Sửa ngược tiếng Anh (`retroactiveEnglish`, THỬ NGHIỆM, mặc định TẮT)

Gõ trộn: từ có phím gõ trùng tiếng Việt bị ghép thành tiếng Việt vì lúc gõ chưa có gì nói
câu là tiếng Anh ("His car is" → "Hí cả í"). Khi mạch tiếng Anh đã CHẮC (hai từ liền nhau
được chốt là tiếng Anh, từ thứ hai vừa chốt), engine đề xuất MỘT phép sửa đưa các từ ngay
trước mạch về phím gõ thô: "Hí cả í very fast" → "His car is very fast".

**Phụ thuộc "Quyết định theo ngữ cảnh" (`contextualEnglish`)**: cờ chỉ có tác dụng khi
`contextualEnglish` bật (và không ở VNI) — `retroactiveEnglishActive`. UI chỉ hiện công tắc
khi cài đặt kia đang bật. Tắt = không đổi hành vi, chi phí một phép thử Bool mỗi lần chốt
từ; golden không đổi.

Quyết định (thuần, `RetroEnglish.plan` — Swift `TelexCore/Sources/TelexCore/RetroEnglish.swift`,
Kotlin `android/telexcore/.../RetroEnglish.kt`, C++ `TelexEngine::retroPlan`):
1. Kích hoạt: từ vừa chốt VÀ từ trước nó đều là tiếng Anh (bộ phân loại ngữ cảnh gọi là
   English + màn hình là ascii), cách nhau chỉ bằng dấu cách.
2. Cửa sổ: tối đa 3 từ liền trước mạch, chỉ gồm *ứng viên* (chốt có dấu Việt, phím thô nằm
   trong `EnglishCollisions` ∪ `EnglishContextWords.words` ∪ `runKeepers` ∪ was/wow/yes/queue)
   hoặc từ đã là tiếng Anh; dừng ở từ Việt khác, từ mượn trung tính, dấu câu, xuống dòng,
   hơn 2 dấu cách, hay bất kỳ sửa đổi nào engine không thấy. Bỏ `restoreOnly` (ừ/á/ok… là
   tiểu từ chat).
3. Đoạn viết lại phải có *điểm neo* (`EnglishContextWords.retroClassList`, 6 lớp + cờ X):
   bắt đầu bằng đại từ chủ ngữ / hạn định / giới từ / liên từ ("His…", "of course", "as far
   as"); hoặc trợ động từ đầu cụm + đại từ chủ ngữ (câu hỏi đảo: "Did you", "Is this");
   hoặc một từ đã là tiếng Anh khi mọi từ viết lại là trợ động từ không mang cờ X
   ("winter í coming" → is; "merge đi this PR" giữ "đi").
4. Cặp kề nhau phải hợp lý (P→B|mở, D→mở, R→D|P|O|mở, còn lại tự do); cổng tiền tố
   (`predecessorGates`: "been" chỉ sau have/has/had/'ve) áp dụng.
5. Giữa câu sau một từ Việt, cần ≥ 2 từ viết lại ("cái này á the best" giữ "á").

API cho integrator (giống nhau ở 3 port; đơn vị = ký tự UTF-16, mọi ký tự liên quan đều BMP):

| | Swift (`TelexEngine`) | Kotlin (`TelexEngine`) | C++ (`vtx::TelexEngine`) | C ABI Windows | C ABI Linux |
|---|---|---|---|---|---|
| Cờ | `retroactiveEnglish` | `retroactiveEnglish` | `retroactiveEnglish` | `VTX_RETRO_ENGLISH` (1u<<12) | `VT_FLAG_RETRO_ENGLISH` (12) |
| Đang hiệu lực | `retroactiveEnglishActive` | `retroactiveEnglishActive` | `retroactiveEnglishActive()` | — | — |
| Báo ký tự ranh giới | `noteBoundaryCharacter(_:)` | `noteBoundaryCharacter(ch)` | `noteBoundaryCharacter(ch)` | `vtx_note_boundary` | `vt_note_boundary` |
| Lấy phép sửa | `takeRetroCorrection() -> RetroCorrection?` | `takeRetroCorrection(): RetroCorrection?` | `takeRetroCorrection(out) -> bool` | `vtx_take_retro_correction` | `vt_take_retro` |
| Xem không lấy | `pendingRetroCorrection` | `pendingRetroCorrection` | `pendingRetroCorrection(out)` | — | — |

`RetroCorrection { backspaces, expected, insert, words }` — áp như `TelexAction.replace`:
xoá `backspaces` ký tự ngay trước con trỏ (đúng bằng `expected`), chèn `insert`. Tiền tố
không đổi đã bỏ ("Hí"→"His" chỉ xoá từ "í").

Luồng tích hợp (mỗi ranh giới từ):
1. `commitBoundary`/`commitText` như cũ, áp action của từ hiện tại.
2. Chèn ký tự ranh giới như cũ rồi gọi `noteBoundaryCharacter(ch)` — BẮT BUỘC cho mọi ký tự
   ranh giới; thiếu báo cáo = hai từ không liền nhau = không bao giờ sửa (an toàn).
3. `takeRetroCorrection()` (trước hay sau bước 2 đều được — phép sửa luôn tính từ con trỏ
   hiện tại, ký tự ranh giới đã báo được nối vào cả `expected` lẫn `insert`). Nếu đọc được
   văn bản trước con trỏ (AX, `getTextBeforeCursor`, `ITfRange`), so với `expected`, lệch thì
   bỏ qua. Lấy phép sửa = cam kết áp nó (lịch sử ghi các từ đó là tiếng Anh).
4. Phép sửa hết hạn ở lệnh engine kế tiếp (phím mới, ⌫, reset…).

macOS (`App/Sources/RetroEnglishApply.swift`, cài đặt "Tự sửa từ phía trước", chỉ hiện khi
"Quyết định theo ngữ cảnh" bật; tắt = cờ engine tắt): lấy phép sửa ngay sau commit, TRƯỚC
khi ký tự ranh giới tới app, rồi báo ký tự ranh giới. IMK in-place (app đã chứng minh tôn
trọng replacementRange): đọc lại `expected` trước con trỏ, khớp UTF-16 thì một
`insertText(replacementRange)`. Tap ⌫-gõ-lại: chỉ khi AX đọc lại khớp và không còn burst
đang bay. Terminal/app mã nguồn/marked/passthrough/chọn-ghi-đè/edge: không bao giờ. ⌫ ngay
sau đó trả lại đúng văn bản cũ nếu màn hình còn khớp. (Chip đề xuất / "Khôi phục" là của
iOS/Android.)

Desktop (Windows TIP `windows/ime/core/retro_english.h`, Linux `linux/common/include/viettelex/retro_english.h`):
cờ engine bật khi "Quyết định theo ngữ cảnh" bật (tắt = không có gì). Phép sửa chỉ dùng ở ranh
giới gõ được (dấu cách, dấu câu; Enter/Tab chỉ cắt mạch) và khi văn bản trước con trỏ kiểm chứng
được. Công tắc "Tự sửa từ phía trước" BẬT: tự áp, ⌫ ngay sau đó khôi phục chữ cũ. TẮT: MỜI bằng
gợi ý cạnh con trỏ sẵn có của nền tảng ("His car is", Tab áp — đọc lại văn bản trước khi thay;
phím khác ẩn gợi ý); gợi ý này thắng mọi gợi ý khác cùng phím. Lấy phép sửa TRƯỚC khi báo ký tự
ranh giới, vì app chèn ký tự đó sau phím này; phép sửa được mời kèm ký tự ranh giới vào cả phần
thay lẫn phần chèn. Lấy mà không áp (mời, lệch) thì cắt mạch.

Lịch sử từ (6 từ gần nhất) bị xoá bởi `reset()`, `resetContext()`, `forgetLastCommit()`,
`seed`, `reopenLastCommit`, ⌫ khi buffer rỗng, ranh giới không phải dấu cách, từ tràn
buffer, và khi cờ/`contextualEnglish` tắt. Mọi thao tác engine không thấy (di chuyển con
trỏ, xoá vào chữ đã chốt, dán, undo, gõ tắt) phải đi qua các lệnh đó như hiện nay.

Đo (fixture chung `iOS/KeyboardTests/Fixtures/retro-english-eval.txt`, sinh bởi
`Scripts/gen-retro-english-eval.py`: 1.200 câu Anh + 573 câu trộn + 3.834 câu Việt Tatoeba +
52 câu chat + 72 câu tự soạn; cấu hình mặc định app): precision 1.000 (253 từ sửa đúng,
0 sai), recall 253/467 = 54% số từ Anh mà engine gõ sai khi TẮT; 0 từ Việt bị đổi. Test
có ngưỡng ở cả 3 port (`RetroEnglishTests`, `RetroEnglishTest`, `vtx_tests retro`).
Giới hạn đã biết: chỉ nhìn LÙI — từ trùng đứng SAU mạch hoặc mạch chỉ 1 từ không được sửa
("His car is here now" ở cấu hình mặc định không có từ nào chốt là tiếng Anh: here→hể vì
`collisionPrefersVietnamese`, now→nơ); "Ít people know…" ở ĐẦU câu sẽ thành "Its".

## State & Settings

- `UserDefaults` (suite riêng): autoRestore, freeMarking, modernOrthography,
  liveSpellCheck, simpleTelex, shortcuts `[String: String]`, fallbackApps, probedApps.
- Cache in-memory load một lần; hot path chỉ đọc cache, không đọc disk.
- Bảng gõ tắt chỉ tra ở word boundary.

## Performance budgets (phải đo, không ước)

| Metric | Target | Thực tế | Cách đo |
|---|---|---|---|
| Keystroke latency (engine) | < 50µs p99 | **0.27µs** (xem BENCHMARKS.md) | unit benchmark (XCTest measure, release) |
| RSS sau 1h dùng | < 20MB | chưa đo | Activity Monitor / `footprint` |
| CPU idle | 0.0% | không timer nào tồn tại | Instruments |
| Cold start (chọn input source → gõ được) | < 300ms | chưa đo | log timestamp |

## Privacy

- Zero network trên đường gõ (chỉ gọi mạng khi user bấm *Kiểm tra cập nhật* — GitHub Releases API, xem `Updater.swift`). Zero log keystroke. Không Analytics SDK.
- `PrivacyInfo.xcprivacy` khai báo zero data collection / zero tracking.
- Store description: "Không thu thập bất kỳ dữ liệu nào."

## Ngoài phạm vi (đã quyết định không làm)

- Phím ngoặc `[`→ơ `]`→ư, quick consonants (f→ph, w→qu, g→ng), `oo` literal cho từ mượn
  (xoong, boong), macro auto-caps, tự viết hoa đầu câu.
- VNI (phím 6/7/8/9), Quick Telex (cc=ch, gg=gi), smart switch EN/VI, Dvorak,
  Windows/Linux.

## Testing

1. **Engine unit tests** (`TelexCore/Tests`) — golden table: biến đổi cơ bản, hủy dấu,
   lan horn ươ, ràng buộc coda-tone, w-lẻ, auto-restore từ hiếm hợp lệ, free-marking,
   modern orthography, live spell-check (corpus 40+ từ), Simple Telex.
2. **Validator tests**: đủ bảng vần, coda-tone constraints.
3. **Benchmark test** cho latency budget — kết quả ghi vào `BENCHMARKS.md`.
4. **App-target tests** (`AppTests/`, chạy qua `xcodebuild test`): ma trận routing
   per-app × quyền AX, import plist idempotent, Updater (network stub), DebugLog.
   TelexCore ~99% line coverage; phần IMK/tap plumbing loại trừ có chủ đích.
5. Manual checklist per-app: `checklist.md`.
