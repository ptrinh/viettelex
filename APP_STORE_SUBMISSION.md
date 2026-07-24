# Hướng dẫn submit VietTelex lên App Store

Tài liệu này ghi lại toàn bộ quy trình đưa bàn phím **VietTelex** (app chứa + keyboard extension) lên App Store, kèm các điểm đặc thù của **custom keyboard** mà Apple soi kỹ khi review.

## 0. Thông số project hiện tại

| Mục | Giá trị |
|---|---|
| App bundle ID | `com.viettelex.ios` |
| Keyboard extension bundle ID | `com.viettelex.ios.keyboard` |
| App Group | `group.com.viettelex` |
| Team ID | `84T567KMYD` |
| Marketing version | `1.0.0` |
| Build number | `1` |
| Deployment target | iOS 16.0 |
| Device family | iPhone + iPad (`1,2`) |
| Tên hiển thị app | VietTelex |
| Tên bàn phím | Tiếng Việt (VietTelex) |
| RequestsOpenAccess (Full Access) | **true** |

> ⚠️ **Full Access = true** là điểm khiến review khắt khe hơn (cần privacy policy + giải trình rõ). Xem mục 3 và 8.

---

## 1. Điều kiện tiên quyết

- [x] **Apple Developer Program** đang hoạt động (đã có — team `84T567KMYD`, chính là tài khoản đang ký bản Release lên iPhone).
- [ ] Quyền **Admin** hoặc **App Manager** trên [App Store Connect](https://appstoreconnect.apple.com).
- [ ] Xcode bản mới (đang dùng Xcode 26) đã đăng nhập Apple ID: *Xcode → Settings → Accounts*.
- [ ] Đã đọc [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — đặc biệt mục **2.5.14** (keyboard) và **5.1** (privacy).

---

## 2. Chuẩn bị nội dung & tài nguyên (làm trước, tốn thời gian nhất)

### 2.1 App icon
- Cần icon **1024×1024 px**, PNG, không alpha, không bo góc (Apple tự bo).
- Kiểm tra `App/Assets.xcassets/AppIcon` đã có đủ các size. Thiếu size nào Xcode sẽ báo khi archive.

### 2.2 Screenshots (bắt buộc, đúng kích thước)
Vì app hỗ trợ **cả iPhone lẫn iPad**, phải nộp screenshot cho cả hai. Nếu muốn nhẹ gánh, cân nhắc **chỉ hỗ trợ iPhone** (đổi `TARGETED_DEVICE_FAMILY = 1` trong project) để khỏi phải làm ảnh iPad.

Kích thước tối thiểu cần (App Store Connect yêu cầu ít nhất 1 bộ mỗi loại device):
- **iPhone 6.9"** (iPhone 16 Pro Max / 15 Pro Max): 1290×2796.
- **iPhone 6.5"** (nếu còn hỗ trợ máy cũ): 1242×2688 — hiện thường 6.9" là đủ.
- **iPad 13"** (nếu hỗ trợ iPad): 2064×2752.

Cách chụp nhanh bằng simulator:
```bash
xcrun simctl boot "iPhone 16 Pro Max"
# mở app, bật bàn phím, rồi:
xcrun simctl io booted screenshot ~/Desktop/vt-6.9-01.png
```
Nên có 3–5 ảnh: màn onboarding, bàn phím đang gõ tiếng Việt, thanh gợi ý, mẫu câu, settings.

### 2.3 Metadata (chuẩn bị sẵn text)
- **Tên app** (30 ký tự): ví dụ `VietTelex – Bàn phím Việt`.
- **Subtitle** (30 ký tự): ví dụ `Gõ Telex nhanh & gọn`.
- **Keywords** (100 ký tự, phẩy ngăn cách): `telex,tiếng việt,bàn phím,gõ tiếng việt,vietnamese,keyboard,vni,gõ dấu`.
- **Mô tả** (Description): nêu tính năng — Telex/gợi ý/mẫu câu/emoji — và **cam kết không thu thập dữ liệu**.
- **Promotional text** (170 ký tự, đổi được không cần review lại).
- **Support URL** (bắt buộc): 1 trang web bất kỳ có thông tin liên hệ.
- **Marketing URL** (tuỳ chọn).
- **Category**: `Utilities` (chính) — xem mục 4.5 để set trong project.

### 2.4 Privacy Policy URL (BẮT BUỘC với keyboard Full Access)
Nội dung đã soạn sẵn:
- Nguồn: [`PRIVACY_POLICY.md`](PRIVACY_POLICY.md) (song ngữ Việt–Anh).
- Trang HTML sẵn sàng host: [`docs/privacy.html`](docs/privacy.html).

**URL công khai dự kiến: `https://viettelex.com/privacy-policy`** (App Store **bắt buộc HTTPS** — không dùng `http://`).

Việc cần làm:
1. Deploy `docs/privacy.html` lên `https://viettelex.com/privacy-policy` (VD: Cloudflare Pages/Vercel, hoặc trỏ path đó tới file này).
2. **Điền email liên hệ** vào chỗ `[ĐIỀN EMAIL LIÊN HỆ CỦA BẠN]` trong cả 2 file trước khi deploy.
3. Dùng đúng URL này ở mục **App Privacy → Privacy Policy URL** trên App Store Connect.

---

## 3. Điểm đặc thù CUSTOM KEYBOARD (đọc kỹ, đây là nơi hay bị reject)

1. **App chứa phải có chức năng riêng** (Guideline 2.5.14 / 4.2): app không được chỉ là "bật bàn phím". VietTelex đã có onboarding + ô thử gõ + tab Tính năng + tab Mẫu câu + Giới thiệu → **đạt**.

2. **Full Access (`RequestsOpenAccess = true`)**:
   - Phải khai báo và giải trình trong **App Privacy** + **Review Notes**.
   - Nếu app **không thực sự cần** Full Access khi review, cân nhắc đổi `RequestsOpenAccess = false` để qua review dễ hơn (nhưng sẽ mất: rung phím, mẫu câu động, ghi App Group từ extension). Quyết định trước khi nộp.
   - Nếu giữ `true`: bàn phím **vẫn phải hoạt động cơ bản khi CHƯA cấp Full Access** (gõ được chữ). VietTelex đã đảm bảo điều này.

3. **App Privacy = "Data Not Collected"**: khai đúng sự thật. Nếu mẫu câu động fetch URL do user tự thêm, nêu rõ đó là hành động do user chủ động, không phải app thu thập.

4. **Không có cơ chế thu thập bàn phím ẩn**: đảm bảo không có analytics/log nội dung gõ. (Đã rà — không có.)

---

## 4. Cấu hình project trước khi archive

### 4.1 Chọn scheme & cấu hình Release
Archive luôn dùng cấu hình **Release**.

### 4.2 Tăng version / build number
- Lần nộp đầu: `MARKETING_VERSION = 1.0.0`, `CURRENT_PROJECT_VERSION = 1` (đang đúng).
- **Mỗi lần upload lại** (kể cả TestFlight): build number phải **tăng** (2, 3, …) trong khi version có thể giữ.
- ⚠️ **App và keyboard extension phải CÙNG** marketing version và build number.

### 4.3 Signing
- Mỗi target (App + Keyboard) → tab **Signing & Capabilities**:
  - Bỏ *Automatically manage signing* nếu muốn kiểm soát, hoặc để tự động.
  - **Cần provisioning profile loại Distribution (App Store)** cho cả 2 bundle ID. Xcode tự tạo khi archive nếu bật automatic signing.
- Kiểm tra App Group `group.com.viettelex` bật ở **cả 2** target.

### 4.4 Mã hoá (tránh bị hỏi mỗi lần upload)
Thêm vào `App/Info.plist` (app dùng HTTPS chuẩn → được miễn khai báo xuất khẩu mã hoá):
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

### 4.5 App Category
Chưa set trong project. Set trong Xcode: target **VietTelexApp → General → App Category → Utilities**. (Hoặc thêm `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities"`.)

### 4.6 Quyết định iPad
Nếu **không** làm screenshot iPad: đổi trong project `TARGETED_DEVICE_FAMILY = "1"` (chỉ iPhone) cho cả 2 target, để App Store không đòi ảnh iPad.

---

## 5. Tạo App record trên App Store Connect

1. Vào [App Store Connect](https://appstoreconnect.apple.com) → **Apps → +** → **New App**.
2. Điền:
   - Platform: **iOS**.
   - Name: tên app (mục 2.3).
   - Primary language: **Vietnamese**.
   - Bundle ID: chọn `com.viettelex.ios` (nếu chưa thấy, tạo App ID ở [Certificates, IDs & Profiles](https://developer.apple.com/account/resources/identifiers/list) trước — App ID cho app; extension thường tự nhận).
   - SKU: chuỗi tuỳ ý, ví dụ `viettelex-ios-001`.
3. Sau khi tạo, điền phần **App Information**, **Pricing** (Free), **App Privacy** (Data Not Collected + Privacy Policy URL).

---

## 6. Archive & Upload

### Cách A — Xcode GUI (khuyến nghị lần đầu)
1. Chọn destination **Any iOS Device (arm64)** (không phải simulator).
2. **Product → Archive**.
3. Archive xong mở **Organizer** → chọn archive → **Distribute App** → **App Store Connect** → **Upload**.
4. Chọn các option mặc định (tự quản signing) → Upload. Chờ vài phút xử lý.

### Cách B — Dòng lệnh (nếu muốn tự động)
```bash
# 1. Archive
xcodebuild -project VietTelex-iOS.xcodeproj \
  -scheme VietTelexApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/VietTelex.xcarchive \
  archive

# 2. Export IPA (cần file ExportOptions.plist — xem bên dưới)
xcodebuild -exportArchive \
  -archivePath build/VietTelex.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export

# 3. Upload lên App Store Connect (cần app-specific password hoặc API key)
xcrun altool --upload-app -f build/export/VietTelexApp.ipa \
  -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
# hoặc:
xcrun notarytool ... # KHÔNG dùng cho App Store; dùng altool/Transporter
```

`ExportOptions.plist` mẫu:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store</string>
    <key>teamID</key><string>84T567KMYD</string>
    <key>uploadSymbols</key><true/>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
```

> API key tạo tại App Store Connect → Users and Access → **Integrations / Keys**. Tải file `.p8` (chỉ tải được 1 lần), lưu KEY_ID và ISSUER_ID.

---

## 7. TestFlight (nên làm trước khi submit review)

1. Sau khi build lên App Store Connect, vào tab **TestFlight** của app.
2. Chờ build hết trạng thái "Processing".
3. Điền **Test Information** (export compliance nếu hỏi → No, vì đã set `ITSAppUsesNonExemptEncryption=false`).
4. Cài qua app **TestFlight** trên iPhone, kiểm tra lại **trên thiết bị thật với build phân phối** (khác với bản dev):
   - Bật bàn phím trong Cài đặt, cấp Full Access, gõ thử.
   - Test số/email/url/search input types.
   - Test mẫu câu, emoji, gợi ý.

---

## 8. Submit for Review

1. Vào tab **Distribution / App Store** của version 1.0.0.
2. Gắn **build** vừa upload.
3. Điền đủ: screenshots, mô tả, keywords, support URL, **privacy policy URL**.
4. **App Review Information → Notes** — ghi hướng dẫn cho reviewer (tiếng Anh), ví dụ:

   ```
   VietTelex is a Vietnamese Telex keyboard.

   To test:
   1. Open the VietTelex app once (onboarding + settings).
   2. Settings → General → Keyboard → Keyboards → Add New Keyboard → Tiếng Việt (VietTelex).
   3. (Optional) Enable "Allow Full Access" to test haptics and dynamic snippets.
   4. In any text field, tap the globe key to switch to VietTelex and type,
      e.g. "vieejt" -> "việt".

   Privacy: the keyboard does NOT collect, store, or transmit any typed data.
   Full Access is optional and used only for key haptics and user-created
   dynamic snippets (https:// templates the user adds themselves).
   ```

5. **Version Release**: chọn *Manually release* để chủ động thời điểm phát hành.
6. Bấm **Add for Review → Submit**.

---

## 9. Các lý do reject thường gặp với keyboard (phòng trước)

| Lý do | Cách tránh |
|---|---|
| App chứa không có chức năng riêng | Đã có onboarding/settings/mẫu câu ✅ |
| Full Access không giải trình | Ghi rõ trong Review Notes + Privacy Policy ✅ |
| Bàn phím không chạy khi chưa cấp Full Access | Đã đảm bảo gõ được không cần Full Access ✅ |
| App Privacy khai sai | Khai "Data Not Collected" đúng sự thật ✅ |
| Thiếu privacy policy URL | Chuẩn bị URL công khai (mục 2.4) |
| Screenshot sai kích thước / thiếu iPad | Làm đúng bộ hoặc bỏ hỗ trợ iPad (mục 4.6) |
| Crash khi review | Test kỹ qua TestFlight trước |

---

## 10. Checklist cuối trước khi bấm Submit

- [ ] Icon 1024 + đủ size trong Assets
- [ ] Screenshots đúng kích thước (iPhone [+ iPad nếu hỗ trợ])
- [ ] `ITSAppUsesNonExemptEncryption = false` trong App Info.plist
- [ ] App Category = Utilities
- [ ] Version/build khớp giữa App và Keyboard; build number đã tăng
- [ ] Distribution signing OK cho cả 2 bundle ID
- [ ] App Group bật ở cả 2 target
- [ ] Privacy Policy URL + Support URL sẵn sàng
- [ ] App Privacy = Data Not Collected
- [ ] Review Notes có hướng dẫn bật bàn phím + giải trình Full Access
- [ ] Đã test bản TestFlight trên máy thật
- [ ] Quyết định giữ hay bỏ `RequestsOpenAccess`

---

## Ghi chú
- Lần đầu review keyboard thường **1–3 ngày**, đôi khi lâu hơn do bị soi kỹ.
- Nếu bị reject, đọc kỹ lý do trong Resolution Center, sửa và **Reply** thẳng ở đó (không cần tạo version mới nếu chỉ là metadata/notes).
- Sau khi được duyệt, vì đã chọn *Manually release*, vào bấm **Release This Version** để lên store.
