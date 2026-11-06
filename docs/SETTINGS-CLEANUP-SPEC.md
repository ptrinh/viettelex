# Spec: Thu gọn cài đặt (mọi nền tảng)

Trạng thái: đã duyệt 05/11/2026, đang triển khai. Liên quan `docs/ONBOARDING-SPEC.md` (§4 nhóm
"Gõ mixed Việt/Anh").

## 0. Nguyên tắc

1. **Cấp 1 chỉ có thứ làm người dùng khác nhau.** Tính năng mới mặc định vào **Nâng cao** hoặc thành
   chip tại chỗ; chỉ lên cấp 1 khi nó làm các hồ sơ khác nhau hoặc phần lớn người dùng cần.
2. **Không bỏ công tắc tắt** của tính năng có thể làm chậm gõ (DESIGN.md: hiệu năng số 1; tắt = 0 chi
   phí). Thu gọn = đổi chỗ / gộp hiển thị, **không đổi hành vi, không đổi key lưu, không đổi mặc định**
   (sao lưu, đồng bộ iCloud, người dùng cũ giữ nguyên).
3. **Tối đa 2 tầng** (trang → Nâng cao). Mục "Nâng cao" có dòng phụ liệt kê những gì bên trong.
4. **Công tắc phụ thuộc: làm mờ + ghi lý do, không ẩn**, đặt ngay dưới công tắc cha (Android/Microsoft
   guidelines). Ngoại lệ: tuỳ chọn chỉ-Telex khi chọn VNI được làm mờ kèm "Chỉ áp dụng cho Telex".
5. **Cùng tên, cùng chỗ trên 5 nền tảng** (bảng §3). Nhãn bắt đầu bằng từ quan trọng, mô tả triệu chứng,
   không thuật ngữ kỹ thuật (preedit, surrounding, composition, hook, chip…) ở nhãn chính.
6. **Không nhắc tên bộ gõ khác** trong nhãn, chú thích, tuỳ chọn. Gặp thì viết lại theo hành vi.
7. Không lặp cài đặt hệ thống: chỉ một dòng link "Mở cài đặt … của hệ thống".
8. **Chú thích một dòng** (06/11/2026): mỗi cài đặt = tên + MỘT dòng chú thích ≤ 95 ký tự (cả vi lẫn
   en), một ví dụ, nằm ngay dưới tên trong cùng hàng (không thành hàng riêng). Dữ kiện cần thiết (quyền,
   Plus, riêng tư) viết thật ngắn. Bảng chú thích: macOS `TypingTab.C`, iOS `SettingCaption`
   (App/SettingsIndex.swift), Android `SettingCaption` (ui/SettingCaptions.kt) — iOS và Android cùng chữ;
   test độ dài ở mỗi nền tảng.

## 1. Nhóm "Gõ lẫn tiếng Anh" (trước: "Gõ mixed Việt/Anh"; đổi tên 05/11/2026, key giữ nguyên)

```
Gõ lẫn tiếng Anh                        dòng tóm tắt khi thu gọn (mobile)
  Bạn thường gõ thế nào?  Chọn một — …   (radio, đã có từ 6df365a7)
  ( ) Chủ yếu tiếng Việt
  ( ) Việt + Anh nhiều
  ( ) Chủ yếu tiếng Anh                  ← macOS: ẨN (trên Mac ≡ Việt + Anh nhiều)
  (•) Tuỳ chỉnh                          ← chỉ hiện khi lệch
  Vuốt phím cách đổi Tiếng Việt/Anh       ← mobile, ở cấp 1 (là cách chuyển ngôn ngữ)
  › Từ điển cá nhân                      ← mobile (đã có)
  › Nâng cao — "Khôi phục từ tiếng Anh, ngữ cảnh, khi trùng từ, sửa từ phía trước…"
      Tự khôi phục từ tiếng Anh
      Khi từ vừa Anh vừa Việt: Ưu tiên tiếng Việt / tiếng Anh   (radio; nơi đang có)
         chú thích có mẹo: "Gõ đúp phím dấu để giữ tiếng Anh (lisst → list)."
      Quyết định theo ngữ cảnh
        Tự sửa từ phía trước (thử nghiệm)      ← mờ + "Cần bật Quyết định theo ngữ cảnh"
        Đoán từ trùng theo tần suất (thử nghiệm) ← như trên
```

- **Khi chọn VNI (06/11/2026): ẨN nhóm "Gõ lẫn tiếng Anh"** (bộ chọn hồ sơ + Nâng cao). VNI đặt dấu
  bằng phím số nên từ tiếng Anh gõ ra nguyên vẹn — đo 06/11/2026: google/the/his/pass/case1 cho cùng
  kết quả dù bật hay tắt Tự khôi phục; khi trùng từ, ngữ cảnh, tần suất, sửa từ phía trước đều chỉ-Telex.
  Thay nhóm bằng MỘT dòng: "Gõ VNI không làm đổi từ tiếng Anh nên không cần chỉnh phần này." /
  "VNI leaves English words as typed, so there is nothing to set here." Ngoại lệ có chủ đích của §0.4:
  cả nhóm vô tác dụng ⇒ ẩn gọn hơn làm mờ cả chục dòng. **Giữ nguyên hiện**: Chuyển Việt/Anh (desktop),
  Vuốt phím cách đổi Tiếng Việt/Anh (mobile), Từ điển cá nhân nếu nó còn phục vụ gợi ý/khác ngoài khôi
  phục tiếng Anh. Không đổi key/giá trị (đổi lại Telex thấy y như cũ); engine không đổi. Tìm kiếm cài
  đặt (mobile): mục bị ẩn vẫn tìm được và mở ra thấy dòng ghi chú. Onboarding: chọn VNI ⇒ bỏ qua bước
  hỏi hồ sơ gõ lẫn (nếu có).
- **"Vuốt từ tiếng Anh"** (mobile) chuyển về trang **Gõ vuốt**, ngay dưới công tắc Gõ vuốt (nó phụ
  thuộc Gõ vuốt). Bộ chọn hồ sơ vẫn đặt giá trị của nó như cũ; tìm kiếm cài đặt trỏ tới chỗ mới.
- Desktop: **"Chuyển Việt/Anh"** là nhóm riêng, ngay dưới nhóm mixed: phím chuyển (control chính) +
  Nâng cao: nhớ theo ứng dụng / app mới bắt đầu bằng… / giữ VietTelex khi hệ thống tự đổi bộ gõ /
  kiểu báo khi chuyển. macOS gom 3 chỗ hiện rải rác về đây (tab Ứng dụng chỉ giữ bảng chế độ theo app).
- Nâng cao trên desktop: macOS = `DisclosureGroup` trong Form; Windows = expander (mục bấm mở/thu,
  lồng 1 cấp); Linux = `Adw.ExpanderRow`. Mobile = dòng NavigationLink/hàng mở trang con.
- Ô tìm kiếm (mobile) phải tìm thấy mọi mục đã đổi chỗ và mở đúng trang/nhóm.

## 2. Chip tại chỗ (mobile; desktop nếu đã có hạ tầng)

- Xác minh chip **mời bật** + **hoàn tác** của "Tự sửa từ phía trước" (`RetroEnglishUI`,
  ONBOARDING-SPEC §7–8) thực sự render trên bàn phím iOS + Android; thiếu thì hoàn thiện, có test.
- "Đoán theo tần suất": chưa làm chip (chưa có spec) — ghi vào backlog, không làm đợt này.
- "Học từ hoàn tác" (hoàn tác cùng từ 2–3 lần thì thôi áp dụng): ý tưởng, cần đo — KHÔNG làm đợt này.

## 3. Thống nhất nhãn / chỗ

| Key | Nhãn chung (vi) | Ghi chú |
|---|---|---|
| `freeMarking` | Bỏ dấu tự do | macOS đang "Đặt dấu tự do" |
| `modernOrthography` | Bỏ dấu kiểu mới (oà, uý) | |
| `reEditWord` | Sửa dấu từ đã gõ | macOS chưa có UI: thêm vào Nâng cao kiểu gõ nếu key đọc được runtime, không thì ghi "luôn bật" trong docs |
| `numberChips` | Gợi ý số tiền | bỏ chữ "chip" |
| `autoRestore` | Tự khôi phục từ tiếng Anh | chú thích có ví dụ (google, github…) |
| teencode | ở **Nâng cao kiểu gõ** mọi nền tảng | Windows đang ở Chính tả |
| sửa chạm trượt (mobile) | gom chung một chỗ: trang Chính tả & sửa lỗi | Android đang ở Kiểu Gõ |
| Linux "Học từ bạn gõ" | ngay dưới "Gợi ý từ", mờ + lý do khi Gợi ý từ tắt | |
| Windows chọn VNI | 5 công tắc chỉ-Telex mờ + "Chỉ áp dụng cho Telex" | |
| `simpleTelex` mặc định | GIỮ NGUYÊN (mobile bật, desktop tắt) — ghi lý do vào DESIGN.md | đổi mặc định = đổi hành vi người dùng cũ |

Nâng cao kiểu gõ (mọi nền tảng, tên "Nâng cao"): Telex đơn giản, Bỏ dấu tự do, Gõ nhanh (Quick Telex →
nhãn "Gõ tắt phụ âm nhanh (cc→ch, gg→gi…)" hoặc giữ tên + chú thích), Bỏ dấu kiểu mới, Teencode,
phím ngoặc… — những mục chỉ-Telex làm mờ khi VNI.

## 4. Cấp 1

**Mobile (iOS + Android, giống hệt nhau)** — giữ 4 tab:
- Tab Kiểu Gõ: Kiểu gõ Telex/VNI · Gõ lẫn tiếng Anh · Tự viết hoa đầu câu (nếu đang ở tab này) ·
  › Nâng cao kiểu gõ.
- Tab Tính Năng: gộp "Chính tả & sửa lỗi" + "Gợi ý & từ điển" → **"Sửa lỗi & gợi ý"** (các mục sửa
  chạm trượt giữ công tắc riêng, xếp liền nhau); "Phím & cử chỉ" tách **"Phản hồi khi chạm"** (rung, âm
  thanh, phóng to phím) thành trang con; gộp 2 trang nhỏ quyền riêng tư + sao lưu → **"Riêng tư & sao
  lưu"**; Debug log chuyển từ Giới Thiệu về **"Nâng cao / Gỡ lỗi"** (cuối danh sách).
- Ba cách thêm dấu (chip, công cụ, phím tắt) dùng chung tên **"Thêm dấu"**.

**Desktop (macOS / Windows / Linux, cùng 5 tab/trang)**:
`Gõ phím` (Kiểu gõ + Nâng cao · Gõ lẫn tiếng Anh · Chuyển Việt/Anh · Chính tả) ·
`Gợi ý & công cụ` · `Gõ tắt` · `Ứng dụng` · `Chung` (ngôn ngữ, biểu tượng, đồng bộ, cập nhật,
Nâng cao/Gỡ lỗi).
- macOS: mục "Viết hoa, gợi ý chữ…" (lặp cài đặt hệ thống) → một dòng link cuối trang.
- Windows: trang Kiểu gõ 21 mục tách theo trên; Game, Giao diện vào expander thu gọn.
- Linux: trang "Tuỳ chỉnh" (tên chung chung) → "Gợi ý & công cụ" + "Ứng dụng"; thuật ngữ
  preedit/surrounding → nhãn theo triệu chứng ("Hiện gạch chân chữ đang gõ", …), để trong Nâng cao.

## 5. Kiểm thử

Mỗi nền tảng: test hiện có xanh; test mới cho (a) bộ chọn hồ sơ vẫn áp đúng key sau khi mục đổi chỗ,
(b) tìm kiếm cài đặt mobile trỏ đúng chỗ mới, (c) không còn chuỗi nhắc bộ gõ khác (test quét chuỗi),
(d) nhãn bảng §3 khớp (test chuỗi vi). Không đổi key ⇒ test sao lưu/khôi phục phải xanh nguyên.
