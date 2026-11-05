# Spec: Onboarding người dùng mới + mục "Gõ Việt–Anh"

Trạng thái: **nháp — chờ duyệt** · 05/11/2026
Phạm vi: iOS, Android, macOS, Windows (Linux theo sau nếu có màn cài đặt tương ứng).

## 1. Mục tiêu

- Người mới không phải tự dò qua hàng chục công tắc: trả lời 1 câu "bạn gõ thế nào" là có cấu hình hợp lý.
- Gom mọi tính năng liên quan gõ trộn Việt–Anh vào **một mục riêng**, dễ tìm, dễ hiểu.
- Không đổi gì với người dùng cũ trừ khi họ chủ động chọn.

Không mục tiêu: không thu thập/gửi lựa chọn của người dùng đi đâu (không telemetry).

## 2. Luồng onboarding (người dùng mới)

Hiện lần đầu mở app sau khi cài (sau bước bật bàn phím / cấp quyền hiện có). 2 màn, có **"Bỏ qua"** ở mọi màn; bỏ qua = giữ mặc định hiện tại ("Chủ yếu tiếng Việt").

### Màn 1 — "Bạn thường gõ thế nào?"

Ba lựa chọn dạng thẻ lớn, mỗi thẻ có 1 câu ví dụ:

| Lựa chọn | Ví dụ trên thẻ | Hồ sơ |
|---|---|---|
| **Chủ yếu tiếng Việt** | "Chiều nay mình đi cà phê nhé" | `vi` |
| **Việt + Anh nhiều** | "Chiều nay họp team, nhớ check mail nha" | `mixed` |
| **Chủ yếu tiếng Anh** | "See you at the meeting, nhớ mang laptop nhé" | `en` |

Không có màn chọn Telex/VNI: mặc định Telex, VNI chỉnh trong Cài đặt như hiện tại.

### Màn 2 — Gõ thử

Ô gõ thử + 2–3 câu mẫu theo hồ sơ đã chọn (hồ sơ `mixed` có câu trộn, ví dụ "Mai họp team lúc 9h, nhớ confirm nhé"). Bên dưới: danh sách ngắn những gì vừa bật, mỗi dòng 1 công tắc để tắt ngay. Nút **"Xong"**.

Ghi chú nền tảng:
- iOS/Android: gõ thử bằng chính bàn phím VietTelex (nếu chưa bật bàn phím thì ẩn màn này, hiện lại một lần sau khi bật).
- macOS/Windows: gắn vào màn chào/onboarding sẵn có (`windows/app/core/onboarding.*`; macOS màn chào hiện có), ô gõ thử dùng chính IME.

## 3. Hồ sơ = bộ cài đặt cụ thể (không phải "chế độ")

Chọn hồ sơ **ghi thẳng giá trị** vào từng cài đặt rồi thôi. Không lưu "chế độ" nào chi phối về sau ⇒ người dùng sửa một công tắc thì không bị ghi đè. Chỉ lưu thêm `onboardingDone` (Bool) và `onboardingProfile` ("vi" | "mixed" | "en", chỉ để hiển thị/hỗ trợ, không điều khiển hành vi).

| Cài đặt (key hiện có) | `vi` | `mixed` |
|---|---|---|
| Tự khôi phục từ tiếng Anh (`autoRestore`) | BẬT (như hiện tại) | BẬT |
| Quyết định theo ngữ cảnh (`contextualEnglish`) | mặc định hiện tại | BẬT |
| Tự sửa từ phía trước (`retroactiveEnglish`) | TẮT (chip mời) | BẬT (tự áp + chip Khôi phục) |
| Ưu tiên tiếng Việt khi trùng (`collisionPrefersVietnamese`, macOS) | BẬT | BẬT |
| Đoán theo tần suất cho từ trùng (flag mới, đang làm) | TẮT | **chỉ BẬT nếu bộ đo đạt ngưỡng ở §6**; nếu không: TẮT |
| Vuốt phím cách đổi Việt/Anh (`spaceSwipeLanguage`, iOS/Android) | TẮT | BẬT |
| Vuốt từ tiếng Anh (`swipeEnglish`, khi bật gõ vuốt) | mặc định | BẬT |

Hồ sơ `en` = như `mixed`, thêm: ngôn ngữ khởi đầu của bàn phím là **Tiếng Anh** (iOS/Android: `keyboardLanguage = en`, vuốt phím cách để gõ tiếng Việt; macOS/Windows: khởi đầu ở chế độ tiếng Anh nếu nền tảng có chế độ này, không thì như `mixed`). Bảng §3 áp cho `en` y như cột `mixed`.

Mọi tính năng còn "thử nghiệm" chỉ được đưa vào hồ sơ `mixed` khi đã qua bộ đo; không hỏi người dùng "có bật tính năng thử nghiệm không".

## 4. Mục cài đặt mới "Gõ Việt–Anh"

Một trang riêng, cùng cấp với Kiểu gõ / Chính tả / Gợi ý / Gõ vuốt…, cùng tên và thứ tự trên mọi nền tảng.

Đầu trang: bộ chọn nhanh **"Chủ yếu tiếng Việt / Việt + Anh nhiều / Chủ yếu tiếng Anh"** — bấm = áp bộ cài đặt ở §3 (có xác nhận nếu sẽ đổi công tắc người dùng đã tự chỉnh). Không có trạng thái "đang ở hồ sơ nào"; nếu cài đặt khớp đúng một hồ sơ thì tô hồ sơ đó, không khớp thì hiện "Tuỳ chỉnh".

Nhóm công tắc (chuyển từ các trang cũ sang, trang cũ giữ một dòng liên kết "Đã chuyển sang Gõ Việt–Anh" trong 1–2 bản):

1. **Nhận diện tiếng Anh**
   - Tự khôi phục từ tiếng Anh
   - Quyết định theo ngữ cảnh
   - Tự sửa từ phía trước (chỉ hiện khi bật ngữ cảnh)
   - Đoán theo tần suất cho từ trùng (nhãn "Thử nghiệm" tới khi chốt)
   - (macOS) Ưu tiên tiếng Việt khi từ trùng
2. **Chuyển ngôn ngữ**
   - Vuốt phím cách đổi Việt/Anh (iOS/Android)
   - Phím tắt đổi ngôn ngữ (macOS/Windows — nếu có)
3. **Gợi ý & gõ vuốt tiếng Anh**
   - Vuốt từ tiếng Anh
   - (liên kết tới Từ điển cá nhân để thêm từ tiếng Anh riêng)

Ô tìm kiếm cài đặt (FeatureSearch) trỏ các mục trên về trang mới. Sao lưu/khôi phục: key không đổi ⇒ không cần đổi định dạng backup.

## 5. Người dùng cũ

- Không chạy onboarding. `onboardingDone` được đặt `true` khi phát hiện đã có cài đặt cũ (bản nâng cấp).
- Hiện **một lần** thẻ nhỏ trong app: "Bạn hay gõ trộn Anh/Việt? Xem mục Gõ Việt–Anh mới" → mở trang §4. Đóng là không hiện lại.
- Không đổi bất kỳ giá trị nào của người dùng cũ.

## 6. Ngưỡng để đưa tính năng thử nghiệm vào hồ sơ `mixed`

Dùng bộ đo trộn Việt–Anh (đang xây cùng việc cải thiện nhận diện tiếng Anh):
- Văn bản thuần tiếng Việt / chat tiếng Việt (gồm láy: hí hí, hì hì; từ hiếm: nơ, bú, lát): tỉ lệ từ sai **không tăng** so với tắt.
- Câu tiếng Anh và câu trộn: tỉ lệ từ sai **giảm rõ** (mục tiêu ≥ 30% tương đối).
- Không tăng chi phí gõ khi tắt (perf test hiện có).

Đạt cả ba ⇒ bật trong `mixed`; không đạt ⇒ chỉ để công tắc trong trang §4.

## 7. Vuốt phím cách khi đang gõ dở một từ (iOS, Android)

Hiện tại: vuốt phím cách chỉ đổi ngôn ngữ cho các từ **sau**.

Mới: nếu đang có một từ **đang soạn** (chưa có dấu cách/dấu câu chốt), vuốt đổi ngôn ngữ thì **chuyển luôn từ đó** sang ngôn ngữ đích, rồi ngôn ngữ đích áp tiếp cho các từ sau.

| Đang hiện | Vuốt sang | Kết quả | Cách tính |
|---|---|---|---|
| `Hí` (phím `His`) | EN | `His` | thay bằng phím gốc đã gõ |
| `His` (phím `His`, đang EN) | VI | `Hí` | chạy lại phím gốc qua Telex/VNI |
| `vẻy` (phím `very`) | EN | `very` | phím gốc |
| `Hí` → vuốt EN → vuốt VI | — | `Hí` | khứ hồi trả đúng như ban đầu |

Quy tắc:
- Chỉ áp cho **từ đang soạn**; từ đã chốt (đã có dấu cách) không đổi. Không có từ đang soạn ⇒ hành vi như cũ.
- Giữ hoa/thường theo phím gốc (`His` → `Hí`, `HIS` → `HÍ`).
- Bộ nhớ phím gốc của từ đang soạn đã có trong engine (dùng cho khôi phục tiếng Anh) ⇒ không thêm dữ liệu.
- Ghi bằng đường thay thế chữ đang soạn hiện có (marked text / composing region), không xoá-chèn ký tự ngoài từ.
- Ngôn ngữ EN đang bật: không áp Telex cho phím tiếp theo của từ (giữ nguyên hành vi EN hiện tại); nếu từ đang soạn có tiền tố đã đóng băng tiếng Anh thì vuốt VI vẫn chạy lại toàn bộ phím gốc qua Telex.
- Hoàn tác: vuốt ngược lại = trở về như trước (bảng trên); không thêm chip.
- Phản hồi: rung nhẹ + hoạt ảnh nhãn ngôn ngữ như hiện tại.
- macOS/Windows: phím tắt đổi ngôn ngữ (nếu có) áp cùng quy tắc cho từ đang soạn — cân nhắc làm cùng đợt cho đồng bộ.

Test cần có (cả iOS và Android, hàm thuần trong lõi): bảng trên; từ có dấu mũ/móc (`dduwowcj` ⇒ `được` ⇄ `dduwowcj`); VNI (`hi1` ⇄ `hí`); từ rỗng; sau dấu cách không đổi; đổi khi đang ở bảng số/emoji ⇒ không áp.

## 8. Tô nền gợi ý sửa khi gõ sai (iOS, Android)

Khi từ đang soạn **không hợp lệ** (không phải âm tiết Việt, không phải từ trong từ điển tiếng Anh/cá nhân) và có ứng viên sửa đủ chắc (cùng ngưỡng AutoCorrect đang dùng):
- Ô 1: từ đang gõ trong ngoặc kép (`"Anhh"`). Chạm = giữ nguyên + ghi vào danh sách từ đã hoàn tác tự sửa (đã có) để không sửa lại.
- Ô giữa: ứng viên tốt nhất, **tô nền** (pill) — ô sẽ được dùng nếu bấm dấu cách.
- Ô còn lại: ứng viên kế.
- Bật "Tự sửa từ gõ sai": dấu cách thay bằng đúng ô tô nền (không bao giờ khác ô đã hiện). Tắt: chỉ tô nền làm gợi ý, dấu cách không sửa.
- Từ hợp lệ: thanh gợi ý như hiện tại (không ngoặc kép, không tô nền).
- Chi phí: ứng viên đã được tính cho thanh gợi ý ⇒ chỉ thêm phần vẽ; không chạy thêm gì khi tắt thanh gợi ý.
- Test: "Anhh" ⇒ ["\"Anhh\"", **Anh**, …]; từ hợp lệ không tô; dấu cách khi bật AutoCorrect áp đúng ô tô; chạm ô ngoặc kép ⇒ không sửa lần sau.

## 9. Thứ tự làm

1. §7 (vuốt phím cách đổi từ đang soạn) và §8 (tô nền gợi ý sửa) — độc lập, nhỏ.
2. §4 trang "Gõ Việt–Anh" + di chuyển công tắc + tìm kiếm.
3. §2/§3 onboarding + hồ sơ; §5 thẻ cho người dùng cũ.
4. Sau khi có kết quả bộ đo (§6): quyết định flag tần suất có vào hồ sơ `mixed` không.

## 10. Đã chốt (05/11/2026)

- Không có màn chọn Telex/VNI trong onboarding.
- Có lựa chọn thứ ba "Chủ yếu tiếng Anh" (hồ sơ `en`).
- Phím tắt đổi ngôn ngữ trên macOS/Windows: nhóm "Chuyển ngôn ngữ" chỉ hiện mục nào nền tảng đó có; kiểm tra lúc làm.
