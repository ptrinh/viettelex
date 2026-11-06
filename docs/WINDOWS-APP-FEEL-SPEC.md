# Spec: Windows — cài xong là gõ được, dùng như một app

Trạng thái: đã duyệt 06/11/2026. Liên quan `docs/ONBOARDING-SPEC.md`, `docs/WINDOWS-SPEC.md`.

## Vì sao

Phản hồi người dùng (06/11/2026): cài xong không biết phải chọn bàn phím nào trong danh sách
Win+Space; nhầm bàn phím "Vietnamese Telex" có sẵn của Windows với VietTelex; khay không có biểu
tượng nên không biết VietTelex có đang chạy không. Người dùng Windows quen mô hình **app**: chạy file
cài → khay có biểu tượng V/E → Ctrl+Shift đổi Việt/Anh, không bao giờ mở danh sách bàn phím.

Hướng: **giữ lõi TSF** (không gạch chân, gõ đúng trong trình duyệt/Word…), làm **lớp ngoài giống app**.
Không đổi mặc định sang hook bàn phím toàn hệ thống (vẫn là chế độ Dự phòng theo app).

## Yêu cầu

1. **Cài xong là gõ được.** Lần chạy đầu (sau MSI, và mỗi khi app khởi động mà VietTelex chưa có):
   thêm VietTelex vào danh sách bàn phím của người dùng, đặt làm bàn phím **mặc định** và **chọn ngay**
   cho phiên hiện tại. Không cần Win+Space. Không xoá bàn phím nào của người dùng.
2. **Khay luôn có biểu tượng** (mặc định BẬT cho người mới; người cũ giữ lựa chọn đã lưu):
   - Chữ **V** (tiếng Việt) / **E** (tiếng Anh) theo app đang dùng.
   - Bấm trái = đổi Việt/Anh. Bấm phải = menu (Cài đặt, Công cụ văn bản, Thoát…).
   - Ctrl+Shift vẫn là phím chuyển mặc định (không đổi).
3. **Khi bàn phím đang chọn không phải VietTelex** (người dùng lỡ Win+Space sang bàn phím khác):
   biểu tượng khay chuyển trạng thái "VietTelex đang tắt" (mờ/gạch); bấm trái = chọn lại VietTelex.
   Tooltip nói rõ. Không bật thông báo dồn dập (tối đa một lần mỗi phiên, hoặc không cần).
4. **Màn chào tối giản:** một trang "Đã sẵn sàng — gõ thử ở đây" (ô gõ thử đi qua VietTelex) + một
   dòng "Đổi Việt/Anh: Ctrl+Shift hoặc bấm biểu tượng V/E ở khay". Câu hỏi hồ sơ gõ lẫn tiếng Anh và
   các lựa chọn khác dùng mặc định, chỉnh sau trong Cài đặt (bỏ khỏi luồng chào, giữ trong Cài đặt).
   Chỉ khi phát hiện bộ gõ tiếng Việt khác đang chạy / bàn phím "Vietnamese Telex" của Windows trong
   danh sách thì hiện thêm một dòng + nút **Xử lý** (dùng hộp xử lý xung đột đã có). Gợi ý gỡ bàn
   phím trùng tên "Vietnamese Telex" khỏi danh sách (chỉ gỡ khỏi danh sách, thêm lại được).
5. **Thoát từ khay** (Thoát VietTelex): chọn lại bàn phím trước đó/tiếng Anh cho phiên hiện tại —
   "tắt app là tắt bộ gõ". Mở lại app = bật lại (mục 1).
6. **Tài liệu:** HDSD Windows (`docs/hdsd/index.html`, `docs/en/guide/index.html`) viết lại theo mô
   hình app: "Cài trong 3 bước" (tải → chạy file cài → thấy V ở khay, gõ thử), khung "Không gõ được?",
   nhấn rõ "VietTelex, không phải Vietnamese Telex của Windows". Bỏ mọi chỗ nhắc tên bộ gõ khác — mô tả
   bằng hành vi ("bấm rồi nhả", "gõ trực tiếp, không gạch chân"). Trang tải: một nút Windows tự chọn
   x64/arm64 theo máy (fallback hiện cả hai).

## Không đổi

Key cài đặt, giá trị đã lưu của người cũ, engine, chế độ gõ theo app. Người cũ (đã có cài đặt):
không ép bật khay, không hiện lại màn chào.

## Kiểm thử

Logic quyết định thuần (core, test chạy trên host): khi nào thêm/đặt mặc định/chọn VietTelex; trạng thái
khay (V / E / tắt) theo (bàn phím đang chọn, Việt/Anh); mặc định khay cho người mới vs người cũ; luồng
màn chào (khi nào hiện dòng Xử lý). Phần gọi Win32/TSF giữ mỏng, ghi rõ chưa thử trên máy thật.
