# VietTelex — Per-App Compatibility Checklist

Ma trận test tay theo app. Trạng thái: ☐ chưa test / ✅ pass / ❌ fail (ghi bug kèm theo).

**Chuỗi test chuẩn dùng cho mọi app** (gõ liên tục, tốc độ nhanh):
- `Tieengs Vieejt raats hay` → `Tiếng Việt rất hay` (hoa đầu câu — bắt lỗi nhân đôi "TTh")
- `ddaay laf nguwowif` → `đây là người`
- Gõ `hoas` rồi backspace 2 lần rồi gõ tiếp `uyeenf` → không vỡ dấu, không lặp chuỗi
- Gõ tắt (nếu bật): `vn ` → mở rộng đúng, không nhân đôi kiểu "Googoogle"
- Gõ 1 câu ~15 từ tốc độ tối đa → không mất/lặp ký tự nào
- **Ở BIÊN**: đầu dòng trống / đầu message / đầu ô — lớp lỗi Electron chỉ lộ ở đây

---

## ✅ Đã test pass (field-tested, mode chốt trong `typing-modes.yml`)

| App | Mode | Ghi chú |
|---|---|---|
| Terminal.app / iTerm2 | tap | shell prompt, vim/nano, TUI (Claude Code), `sudo` secure input, ✅ cả nhóm |
| Microsoft Word | inPlace | AutoCorrect bật, Palatino, Enter nhanh, comment/textbox — ✅ |
| Microsoft Excel | emptyReset | cell autocomplete ("đ"→"dđ" kinh điển), Enter/Tab nhanh, formula bar — ✅ |
| Chrome/Safari (browser) | axDetect | omnibox → chọn-ghi-đè, nội dung trang → in-place; ✅ omnibox + form thường |
| Discord | tap | Slate editor; in-place hỏng ở biên từ (test 21/07/2026) → chốt tap |
| Lark, Slack, VS Code | tap | cùng lớp Electron, in-place hỏng ở biên (field-test 21/07/2026) → chốt tap |
| Spotlight | inPlace | sạch trên macOS 26 kể cả khi có gợi ý xám |
| WhatsApp (native) | inPlace | bản native tôn trọng replacementRange; sandbox cần connection name đúng |
| Notes, Finder, TextMate | inPlace | — |

Các dấu ✅ ở bảng này là kết quả field-test trước batch ổn định hoá; chúng không
thay thế các ca hồi quy mới bên dưới. Discord web/Messenger và thao tác Terminal
qua Chrome Remote Desktop hiện cần test tay lại trên bản Release đã cài.

## ☐ Còn mở

### Chrome — các bề mặt ngoài omnibox

| # | Test case | Rủi ro | Expected |
|---|---|---|---|
| 1.1 | ☐ Google Docs | editor riêng, lỗi khác biệt | Đúng dấu, con trỏ không nhảy |
| 1.2 | ☐ Google Sheets (ô có autocomplete cột) | autocomplete ô như Excel | Đúng dấu |
| 1.3 | ☐ `<input>`/`contenteditable` theo version Chrome mới | regression composition Chromium (issue 409342979) | Đúng dấu; ghi version khi test |

### Adobe Photoshop

| # | Test case | Rủi ro | Expected |
|---|---|---|---|
| 2.1 | ☐ Text layer | text engine Adobe có thể bỏ qua replacementRange | Probe tự detect → fallback |
| 2.2 | ☐ Ô tên layer / số liệu (native field) | field native thường ổn | Đúng dấu |

### VS Code — watch item

| # | Test case | Rủi ro | Expected |
|---|---|---|---|
| 3.1 | ☐ `editor.editContext: true` (đang thành mặc định upstream) | EditContext là đường composition mới, nhiều bộ gõ hỏng | VS Code đã chốt tap nên ít rủi ro — nhưng verify khi EditContext thành default |
| 3.2 | ☐ Search/Find & Replace, integrated terminal | field khác editor chính | Đúng dấu |

### Lark — bề mặt ngoài chat

| # | Test case | Rủi ro | Expected |
|---|---|---|---|
| 4.1 | ☐ Lark Docs (block editor) | block editor can thiệp DOM mạnh | Đúng dấu, không nhảy block |
| 4.2 | ☐ Lark Sheets | autocomplete ô như Excel | Đúng dấu |

### Cross-app / hệ thống

| # | Test case | Expected |
|---|---|---|
| 5.1 | ☐ Password field (Safari, Chrome, System Settings) — secure input | Bypass sạch, không log, không treo |
| 5.2 | ☐ Click chuột giữa từ đang gõ / Cmd+Tab giữa từ | Buffer reset/commit sạch |
| 5.3 | ☐ Key repeat + gõ >120 wpm | Không mất/lặp ký tự |
| 5.4 | ☐ Raycast/Alfred | Field đặc biệt, hay bị bỏ quên |
| 5.5 | ☐ Save dialog / rename trong Finder | Đúng dấu |
| 5.6 | ☐ Stress 500 phím/s (`swift Scripts/stress-typing.swift`) vào TextEdit/terminal/Chrome | Text ra khớp 100% — lớp bug chỉ lộ khi gõ nhanh |
| 5.7 | ☐ RDP/Windows App: focus session rồi rời sang app khác | Passthrough trong RDP; app kia gõ bình thường |
| 5.8 | ☐ Chrome Remote Desktop (`remotedesktop.google.com`): cả 2 máy cài VietTelex | Máy local passthrough (không Backspace+retype); máy remote gõ dấu bình thường, con trỏ không nhảy |
| 5.9 | ☐ Discord web trong Chrome, gõ từ cuối đang compose rồi Return | Gửi đúng một lần, giữ đủ từ cuối, không chèn dòng trống; Shift+Enter xuống dòng |
| 5.10 | ☐ Messenger web trong Chrome, gõ câu tiếng Việt rồi Return | Gửi ngay một lần, không cần Enter lần hai; Shift+Enter xuống dòng |
| 5.11 | ☐ Chrome chat/textarea khi Accessibility tắt | Plain Return theo hành vi của app; Shift+Enter tạo đúng một newline; không làm rơi từ cuối |
| 5.12 | ☐ Warp: gõ một từ đang compose rồi Tab, ←/→ và ↑/↓ | Completion/history/caret hoạt động; dấu không lặp hoặc chèn vào vị trí cũ |
| 5.13 | ☐ Accessibility đã bật: chuyển app/input source nhiều lần | Không lặp hộp nhắc/cửa sổ cài đặt; status khớp với bản Release đang chạy |
| 5.14 | ☐ Bản Xcode Debug và app Release cùng có mặt trên đĩa | TIS mode + IMK connection của Debug khác Release; chỉ Release là input source người dùng chọn |
| 5.15 | ☐ Codex desktop prompt khi VietTelex ở marked fallback | Plain Return gửi prompt một lần; Shift+Return xuống dòng; câu tiếng Việt giữ đủ dấu |

Ghi chú 23/09/2026: 5.9, 5.10, 5.12 và 5.14 pass trên Release 1.7.8 đã cài **sau khi
dọn process Debug thừa** (xem MACOS_IME_NOTES "Bản Debug thừa CHIẾM IMK connection"),
phím giả lập qua HID tap, Accessibility đã bật. Chưa chạy lại trên bản có patch Plain
Return vì máy test không có cert Developer ID; 5.8 và 5.15 chưa test.

---

## Hàm ý thiết kế đã rút ra (đối chiếu DESIGN.md)

1. **`insertText(replacementRange:)` né được lớp lỗi lớn nhất** ("dđ" trong omnibox/Excel — race giữa backspace và inline autocomplete), nhưng phải test theo version Chromium.
2. **Fallback tap-mode là bắt buộc**: Terminal/TUI và app bỏ qua replacementRange. Probe read-back tự phát hiện, không bắt user cấu hình.

### Terminal/TUI regression tự động

Issue #33 có lỗi dấu cuối từ không ổn định trong Claude/Kiro CLI ở tốc độ gõ
bình thường. Chạy reader ở terminal thứ nhất:

```bash
python3 Scripts/pty-reader.py /tmp/viettelex-terminal.log \
  --corpus Scripts/terminal-regression-cases.json --repeats 10
```

Ở terminal thứ hai, chạy poster rồi focus lại terminal reader trong 3 giây:

```bash
swift Scripts/stress-typing.swift \
  --corpus Scripts/terminal-regression-cases.json --rate 7 --repeats 10
```

Reader tự áp dụng byte Backspace/DEL và decode UTF-8 để dựng text mà TUI thật
nhận được, sau đó so sánh từng dòng. Kết quả phải là `30/30 passed`. Chạy lại
với `--rate 500` để giữ stress coverage cũ. Corpus gồm baseline và hai chuỗi
tái hiện từ issue #33; thêm case mới vào JSON, không hardcode thêm trong script.
3. **Electron hỏng Ở BIÊN TỪ** dù giữa dòng trông ổn — mọi test in-place cho app Electron phải gõ đầu-dòng/đầu-message trước khi kết luận.
4. **Secure input**: check `IsSecureEventInputEnabled`, bypass sạch.
5. **VS Code EditContext** là chiến trường mới — theo dõi khi nó thành default upstream (hiện VietTelex đi tap nên không blocker).
