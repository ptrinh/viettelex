# VietTelex iOS

Bàn phím iOS VietTelex, nằm trong repo [ptrinh/viettelex](https://github.com/ptrinh/viettelex).
Engine Telex (`TelexCore`) dùng chung với app macOS qua local path `../TelexCore`:

```
~/ClaudeCode/VietTelex/       # repo public: macOS app + TelexCore + web + iOS + android
~/ClaudeCode/VietTelex/iOS/   # app iOS (cùng repo)
```

Build: `xcodegen generate && xcodebuild -project VietTelex-iOS.xcodeproj -scheme VietTelexApp -destination 'generic/platform=iOS Simulator' build`
Tests: scheme `VietTelexKeyboardTests`. Bộ mẫu câu mặc định: `ios-mau-cau.yml`
(bundle theo build). Blob emoji: `Scripts/blobify-emojisuggest.py`.
