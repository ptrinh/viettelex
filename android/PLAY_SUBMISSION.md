# Google Play — VietTelex Android

Package `com.viettelex.android` · versionName `1.1` · versionCode `1` (+1 mỗi lần upload).

## 1. Build

```bash
cd android && ./gradlew :app:bundleRelease
# → app/build/outputs/bundle/release/app-release.aab  (ký bằng upload key)
```

- Upload key: `~/keystores/viettelex.jks` (alias `viettelex`, RSA 2048, ~27 năm). Mật khẩu trong
  `android/keystore.properties` (gitignored). **Sao lưu cả 2 file** (1Password/iCloud).
- Dùng **Play App Signing** (mặc định khi upload AAB đầu tiên) — Google giữ app signing key.
- Upload key SHA-256: `BA:4B:FB:BB:30:02:73:83:F2:90:2B:20:75:91:B4:92:C8:31:20:CC:B3:3B:32:C0:7D:7B:CF:09:FF:DD:81:87`

## 2. Tạo app (Play Console → Create app)

| Mục | Giá trị |
|---|---|
| App name | VietTelex – Bàn phím Telex |
| Default language | Tiếng Việt (vi) — thêm English (en-US) |
| App or game | App |
| Free or paid | Free |

## 3. Store listing

**Short description (vi, ≤80)**: `Bàn phím Telex nhanh, gợi ý thông minh, riêng tư — không thu thập dữ liệu.`
**Short description (en, ≤80)**: `Fast, private Vietnamese Telex keyboard with smart suggestions.`

**Full description**: dùng bản iOS ở `iOS/APP_STORE_SUBMISSION.md` §11, thay 2 dòng về "Toàn quyền Truy cập" bằng:
- vi: `• Không có quyền Internet — chỉ xin quyền rung phím.`
- en: `• No Internet permission — the only permission is key haptics.`

(Nháp câu chữ nhấn mạnh riêng tư: `android/store/DRAFT-privacy-copy.md`.)

Thêm dòng hướng dẫn: `Bật: Cài đặt → Hệ thống → Bàn phím → Bàn phím trên màn hình → bật VietTelex.`

- App icon 512×512: `iOS/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` thu về 512.
- Feature graphic 1024×500: cần tạo.
- Phone screenshots: `android/store-assets/phone/*.png` (1080×2400).
- Category: Tools · Email/Website: privacy@viettelex.com / https://viettelex.com
- Privacy policy: https://viettelex.com/privacy-policy (đã có mục Android)

## 4. App content (khai báo)

- **Data safety**: *Không thu thập, không chia sẻ dữ liệu.* Không mã hoá khi truyền (không truyền gì).
  Không có tài khoản → không cần xoá tài khoản.
- **Ads**: không. **Target audience**: 13+ (tránh chương trình Families). **Content rating**: questionnaire →
  Utility, không nội dung nhạy cảm.
- **Government / financial / health**: không.
- IME: Play không có mục reviewer notes; privacy policy + mô tả đã nêu rõ không thu thập nội dung gõ.

## 5. Phát hành

1. Testing → **Internal testing** → Create release → upload `app-release.aab` → thêm tester → Roll out.
2. Tài khoản developer cá nhân tạo sau 11/2023: bắt buộc **Closed testing ≥12 tester trong 14 ngày**
   trước khi xin quyền Production.
3. Production → Create release → cùng AAB → Review → Roll out.
