<p align="center">
  <img src="assets/VietTelex-logo.png" width="128" alt="VietTelex">
</p>

<h1 align="center">VietTelex</h1>

<p align="center">
  <a href="https://github.com/ptrinh/viettelex/actions/workflows/ci.yml"><img src="https://github.com/ptrinh/viettelex/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/ptrinh/viettelex/releases/latest"><img src="https://img.shields.io/github/v/release/ptrinh/viettelex?color=c22727" alt="Release"></a>
  <a href="https://github.com/ptrinh/viettelex/releases"><img src="https://img.shields.io/github/downloads/ptrinh/viettelex/total?label=Downloads&color=4c1" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/ptrinh/viettelex?color=555" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-17233d" alt="macOS 14+">
</p>

**VietTelex** (ViệtTelex / ViếtTelex) là bộ gõ tiếng Việt **Telex** (và **VNI**) cho macOS, được xây dựng trên **InputMethodKit** của Apple để tích hợp sâu. Không gạch chân từ đang gõ, con trỏ luôn ở cuối, dấu bỏ trực tiếp vào chữ, và gõ được cả trong **Terminal** mà không phá autocomplete của shell.

Triết lý: **tối giản, nhanh, ổn định, mã nguồn mở** — cài xong là gõ, hầu như không phải chỉnh gì thêm.

> Dự án của **Phil Trịnh**, viết lại từ đầu sau gần 20 năm dùng macOS mà chưa thấy bộ gõ tiếng Việt nào thật sự *ngon, chuẩn, mượt*.

https://github.com/user-attachments/assets/b07b7321-912f-4d81-a741-bcaa9a43f07d

<p align="center"><sub>Demo gõ máy ở tốc độ ~380 WPM — dấu bung tức thì, không gạch chân, từ tiếng Anh tự khôi phục.</sub></p>

## Điểm nổi bật

- **Chuẩn IMKit** — là input method thật của hệ thống (không phải app chặn phím), nên thừa hưởng miễn phí: tự đổi kiểu gõ theo từng app, chính tả/dự đoán/viết hoa của macOS, con trỏ/undo/VoiceOver đều đúng.
- **Nhanh** — luật chính tả compile thành trie + bitmap, incremental parse, SIMD, zero-alloc: **~130 ns/phím**, gõ nhanh cỡ nào cũng mượt.
- **Gõ được ở nơi bộ gõ khác hay vỡ** — Terminal/iTerm (giữ autocomplete shell), address bar Chrome, ô Excel, Spotlight; tự học theo từng app.
- **Thông minh với English/code** — tự khôi phục `google`/`github`, nhận token camelCase (`OmS`, `JavaScript`) để không bỏ dấu nhầm, có Telex nghiêm ngặt.
- **Đúng, có số đo** — bộ regression 9.091 ca: **100%** từ tiếng Việt ra đúng dấu, **98,9%** từ tiếng Anh bị biến dạng được khôi phục. Chi tiết + phần chưa phủ: [`docs/REGRESSION.md`](docs/REGRESSION.md).
- **Nhẹ & riêng tư** — không chạy nền, không thu thập dữ liệu; chỉ gọi mạng khi bạn bấm *Kiểm tra cập nhật*.

| Menu trên thanh menu | Cửa sổ Cài đặt |
|---|---|
| ![Menu bộ gõ](assets/Menu-Bar-Screenshot.png) | ![Cửa sổ Cài đặt](assets/Settings-Screenshot.png) |

## Cài đặt

**Website:** [ptrinh.github.io/viettelex](https://ptrinh.github.io/viettelex/) · **Homebrew:** `brew install --cask ptrinh/viettelex/viettelex`

1. Tải **`VietTelex-x.y.z.pkg`** từ [Releases](https://github.com/ptrinh/viettelex/releases) (đã ký + notarized).
2. Double-click → làm theo hướng dẫn (tự cài, đăng ký bộ gõ, mở sẵn System Settings → Keyboard).
3. **Input Sources → Edit… / ＋ → Vietnamese → ViệtTelex → Add.**

| ① Input Sources → Edit… | ② ＋ → Vietnamese → ViệtTelex → Add |
|---|---|
| ![Input Sources → Edit](assets/instructions-1.png) | ![Add ViệtTelex](assets/instructions-2.png) |

Để gõ trong **Terminal, iTerm, Chrome/Edge/Brave**: bật quyền **Accessibility** cho VietTelex (Privacy & Security → Accessibility). Chuyển Việt/Anh bằng phím 🌐 hoặc ⌃Space (macOS nhớ theo từng app).

## Cách gõ

`s f r x j` = sắc huyền hỏi ngã nặng · `aa ee oo` = â ê ô · `aw ow uw` = ă ơ ư · `dd` = đ · `z` xóa dấu.
Ví dụ: `vieejt` → việt · `truowngf` → trường · `hoas` → hóa.

Tùy chọn (Simple Telex, bỏ dấu tự do, kiểu cũ/mới, kiểm tra chính tả, gõ tắt) ở menu bộ gõ → **Cài đặt…**

**Gõ kiểu VNI:** menu bộ gõ → **Cài đặt…** → tab **Tùy chỉnh** → bật **Gõ kiểu VNI**. Dấu gõ bằng số: `1-5` = sắc/huyền/hỏi/ngã/nặng, `6` = â/ê/ô, `7` = ơ/ư, `8` = ă, `9` = đ, `0` = bỏ dấu (ví dụ `Vie6t5` → Việt). Nên giữ **Kiểm tra chính tả khi gõ** bật để số như `mp3` không bị biến thành dấu.

## FAQ — câu hỏi thường gặp

<details>
<summary><strong>Cài xong gõ vẫn bị gạch chân?</strong></summary>

Do VietTelex chưa được cấp quyền Trợ năng: System Settings → Privacy & Security → **Accessibility** → tick VietTelex (đã tick mà vẫn lỗi thì bỏ tick rồi tick lại). Có thể cần khởi động lại máy một lần để quyền có tác dụng.
</details>

<details>
<summary><strong>Không thấy ViệtTelex trong Input Sources?</strong></summary>

Đăng xuất/đăng nhập lại một lần rồi thêm lại.
</details>

<details>
<summary><strong>Một app cụ thể gõ lỗi?</strong></summary>

Menu bộ gõ → **Cài đặt…** → tab **Bảng cơ chế gõ** → thêm app (có sẵn danh sách app mở gần đây) → ép tay thử lần lượt: **Tap (backspace)**, **Gõ trực tiếp**, **Marked text**. Cách nào gõ đúng thì [báo về GitHub](https://github.com/ptrinh/viettelex/issues/new/choose) để bản sau thành mặc định cho mọi người.
</details>

<details>
<summary><strong>Có hỗ trợ VNI không?</strong></summary>

Có: **Cài đặt…** → tab **Tùy chỉnh** → bật **Gõ kiểu VNI**.
</details>

<details>
<summary><strong>Ô mật khẩu không gõ được tiếng Việt?</strong></summary>

VietTelex tự tắt trong secure field — đúng hành vi bảo mật, không phải lỗi.
</details>

<details>
<summary><strong>Gõ comment trên TikTok (Safari) bị mất chữ cuối khi ấn Enter?</strong></summary>

**Bấm một dấu cách trước khi ấn Enter** là đủ chữ. Hoặc dùng Chrome cho TikTok.

Lý do: ô comment của TikTok chỉ ghi nhận từ đang gõ khi có một phím thật đi sau nó — Enter thì không đủ. Bộ gõ đã thử sáu cách xử lý hộ và không cách nào giữ được từ cuối (chi tiết trong [ghi chú kỹ thuật](docs/MACOS_IME_NOTES.md)), nên đây là giới hạn đã biết chứ không phải lỗi chưa sửa.
</details>

<details>
<summary><strong>Gỡ cài đặt thế nào cho sạch?</strong></summary>

Gỡ khỏi Input Sources chỉ tắt bộ gõ, chưa xoá app. Gỡ hẳn: xoá **`~/Library/Input Methods/VietTelex.app`** (Finder → Go → Go to Folder…) rồi đăng xuất/đăng nhập. Muốn xoá luôn cài đặt cá nhân (gõ tắt, tuỳ chỉnh): xoá thêm `~/Library/Preferences/com.viettelex.settings.plist`. Cài bằng Homebrew thì chỉ cần `brew uninstall --cask viettelex`.
</details>

<details>
<summary><strong>Phím tắt trong app chụp màn hình (Flameshot…) không ăn?</strong></summary>

Lỗi của framework Qt (Flameshot, OBS, VLC… dùng): shortcut trong overlay bị nuốt khi có **bất kỳ** bộ gõ nào đang active — bộ gõ Simple Telex có sẵn của Apple cũng dính y hệt, không riêng VietTelex ([chi tiết](https://github.com/ptrinh/viettelex/issues/54)). Khắc phục: System Settings → Keyboard → bật **"Automatically switch to a document's input source"**, rồi một lần chuyển sang ABC khi đang ở app đó — macOS sẽ tự nhớ, các app khác vẫn gõ tiếng Việt bình thường.
</details>

## Đóng góp & giấy phép

Gặp lỗi? Xem [hướng dẫn báo lỗi kèm cách lấy nhật ký gỡ lỗi](BAO-LOI.md) rồi [mở issue](https://github.com/ptrinh/viettelex/issues/new).

Build, kiến trúc, benchmark: xem [`docs/CONTRIBUTE.md`](docs/CONTRIBUTE.md) · độ chính xác: [`docs/REGRESSION.md`](docs/REGRESSION.md) · latency: [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

[MIT License](LICENSE) — © 2026 Phil Trinh. Tự do dùng/sửa/tích hợp (kể cả thương mại), miễn giữ lại thông báo bản quyền.
