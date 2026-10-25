# Báo lỗi VietTelex

Gửi issue tại **https://github.com/ptrinh/viettelex/issues/new/choose** → chọn **🐞 Báo lỗi**. Trước khi báo: cập nhật bản mới nhất (tab **Giới thiệu** → *Kiểm tra cập nhật*) và thử lại.

Gõ trong Terminal/iTerm/Chrome bị gạch chân hoặc không ra dấu → kiểm tra quyền trước: **Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng** (macOS 26 trở về trước) / **Điều khiển thiết bị và truy cập dữ liệu** (macOS 27) → bật VietTelex. Đã bật mà vẫn báo thiếu quyền: chọn VietTelex, bấm − để xoá rồi bấm + thêm lại.

## Mẫu issue

Form sẽ hỏi đúng những field dưới đây — xem trước cho nhanh. Phiên bản, macOS, chế độ gõ… đã nằm sẵn trong nhật ký:

```markdown
**App / website bị lỗi:** Chrome — docs.google.com
**Gõ chuỗi phím:** `theme ` (ghi đúng phím bấm, không phải chữ mong muốn)
**Mong đợi:** thêm — **Thực tế:** themee
**Nhật ký gỡ lỗi:** (dán nội dung vào đây, hoặc kéo-thả file)
```

Lỗi hiển thị (chữ nhảy, bôi đen, mất chữ…) → kèm video quay màn hình (⌘⇧5) càng tốt.

## Lấy nhật ký gỡ lỗi

Nhật ký chỉ ghi sự kiện của bộ gõ, **không ghi nội dung bạn gõ**.

1. Menu **Ｖ** → **Cài đặt…** → tab **Chung**.
2. Mục **Chẩn đoán** (cuối trang) → bật **Ghi nhật ký gỡ lỗi** → bấm **Xoá**.
3. Tái hiện lỗi trong app bị lỗi, rồi quay lại bấm **Chép nhật ký gỡ lỗi** ngay và dán thẳng vào issue (log chỉ giữ 2000 dòng gần nhất). Cần file thì bấm **Lưu nhật ký gỡ lỗi…**.

<img src="assets/debug-log-1.png" alt="Bật Mở tính năng nâng cao" width="440"> <img src="assets/debug-log-2.png" alt="Ghi nhật ký gỡ lỗi" width="440">
