# VietTelex iOS (private)

Bàn phím iOS VietTelex — tách khỏi repo open-source từ 24/07/2026, không còn
open source. Engine Telex (`TelexCore`) vẫn dùng chung với repo public
[ptrinh/viettelex](https://github.com/ptrinh/viettelex) qua local path:
hai repo phải nằm cạnh nhau:

```
~/ClaudeCode/VietTelex/       # public: macOS app + TelexCore + web
~/ClaudeCode/VietTelex-ios/   # repo này
```

Build: `xcodegen generate && xcodebuild -project VietTelex-iOS.xcodeproj -scheme VietTelexApp -destination 'generic/platform=iOS Simulator' build`
Tests: scheme `VietTelexKeyboardTests`. Bộ mẫu câu mặc định: `ios-mau-cau.yml`
(bundle theo build). Blob emoji: `Scripts/blobify-emojisuggest.py`.
