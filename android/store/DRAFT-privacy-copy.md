# NHÁP — câu chữ Store nhấn mạnh riêng tư (chưa đăng)

Trạng thái: nháp để duyệt. KHÔNG dán lên Play Console trước khi bản build không có quyền
`INTERNET` được phát hành (Play hiển thị danh sách quyền theo APK/AAB đang chạy).

Kiểm chứng trước khi dùng:
- `aapt2 dump permissions app-release.aab/apk` chỉ còn `android.permission.VIBRATE`
  (+ `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` nội bộ do AndroidX tự thêm, không phải quyền người dùng thấy).
- "Không tự thay từ": sửa chạm trượt chỉ là GỢI Ý trên thanh gợi ý, phải chạm mới áp dụng;
  "Tự khôi phục từ tiếng Anh" chỉ trả lại đúng các phím bạn đã gõ. Nếu sau này thêm
  autocorrect tự động thì phải sửa câu này.

## Tiếng Việt

**Mô tả ngắn (≤ 80 ký tự)** — chọn 1:
- `Bàn phím Telex riêng tư: không có quyền Internet, không tự thay từ bạn gõ.` (74)
- `Gõ Telex nhanh, không quyền Internet — chữ bạn gõ không bao giờ rời máy.` (72)

**Đoạn đầu mô tả đầy đủ:**

> 🔒 Không có quyền Internet. VietTelex không xin quyền truy cập mạng — về mặt kỹ thuật,
> bàn phím không thể gửi bất cứ thứ gì bạn gõ ra khỏi điện thoại. Bạn có thể tự kiểm tra
> trong mục "Quyền" của ứng dụng trên Google Play hoặc trong Cài đặt → Ứng dụng.
>
> ✋ Không bao giờ tự thay từ bạn gõ. VietTelex chỉ đặt dấu theo đúng phím Telex bạn bấm.
> Gợi ý sửa lỗi chỉ hiện trên thanh gợi ý — bạn chạm thì mới áp dụng. Gõ tiếng Anh như
> "google", "github" được giữ nguyên.

**Gạch đầu dòng (thay dòng quyền cũ):**
- `• Không có quyền Internet — chỉ xin quyền rung phím.`
- `• Không thu thập, không theo dõi, mã nguồn mở — ai cũng kiểm tra được.`
- `• Từ điển, gợi ý và tự học đều chạy trên máy.`
- `• Mẫu câu: nhập từ file YAML hoặc chia sẻ chữ từ app khác — không cần mạng.`

## English

**Short description (≤ 80 chars)** — pick one:
- `Private Vietnamese Telex keyboard: no Internet permission, never swaps words.` (77)
- `Vietnamese Telex keyboard with no Internet access — your typing stays on-device.` (80)

**Full description — opening:**

> 🔒 No Internet permission. VietTelex does not request network access, so the keyboard
> technically cannot send anything you type off your phone. Check it yourself under
> "Permissions" on the Google Play listing or in Settings → Apps.
>
> ✋ Never replaces what you type. VietTelex only applies the tone marks your Telex keys ask
> for. Typo fixes appear as suggestions on the bar — nothing changes unless you tap one.
> English words like "google" or "github" stay exactly as typed.

**Bullets:**
- `• No Internet permission — the only permission is key haptics.`
- `• No data collection, no tracking, open source — anyone can verify.`
- `• Dictionary, suggestions and learning all run on-device.`
- `• Snippets: import a YAML file or share text from any app — no network needed.`
