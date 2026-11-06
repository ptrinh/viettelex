# Spec: Onboarding người dùng mới + mục "Gõ mixed Việt/Anh"

Trạng thái: **đã duyệt, đã triển khai** (iOS, Android, macOS, Windows, Linux — xem §11–§12) · 05/11/2026
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
| Đoán theo tần suất cho từ trùng (`englishByFrequency`) | TẮT | BẬT (đã chốt 05/11/2026: bộ đo đạt — sai 1.96% so với 2.85%, tiếng Việt 0% sai) |
| Vuốt phím cách đổi Việt/Anh (`spaceSwipeLanguage`, iOS/Android) | TẮT | BẬT |
| Vuốt từ tiếng Anh (`swipeEnglish`, khi bật gõ vuốt) | mặc định | BẬT |

Hồ sơ `en` = như `mixed`, thêm: ngôn ngữ khởi đầu của bàn phím là **Tiếng Anh** (iOS/Android: `keyboardLanguage = en`, vuốt phím cách để gõ tiếng Việt; macOS/Windows: khởi đầu ở chế độ tiếng Anh nếu nền tảng có chế độ này, không thì như `mixed`). Bảng §3 áp cho `en` y như cột `mixed`.

Mọi tính năng còn "thử nghiệm" chỉ được đưa vào hồ sơ `mixed` khi đã qua bộ đo; không hỏi người dùng "có bật tính năng thử nghiệm không".

## 4. Nhóm cài đặt "Gõ mixed Việt/Anh"

**Đã làm (iOS + Android, 05/11/2026)** — theo yêu cầu Phil: không phải trang riêng mà là **một nhóm thu gọn được nằm trong tab Kiểu Gõ, ngay dưới mục Kiểu gõ**, cùng tên + thứ tự trên mọi nền tảng.

- Dòng tiêu đề "Gõ mixed Việt/Anh" (icon quả địa cầu + tóm tắt công tắc đang bật + mũi tên). Chạm = mở/thu gọn.
- **Mặc định thu gọn.** Trạng thái mở/thu gọn chỉ nhớ **trong phiên chạy app** (không lưu): mở lại app là thu gọn.
- Vì vẫn ở cùng tab nên **không** có dòng "Đã chuyển sang …" ở chỗ cũ.
- Ô tìm cài đặt (FeatureSearch, tab Tính Năng) khớp một mục trong nhóm ⇒ chuyển sang tab Kiểu Gõ, mở nhóm, cuộn tới dòng đó và tô sáng ~1,6 s. Mục con đang ẩn (xem dưới) ⇒ cuộn tới công tắc cha "Quyết định theo ngữ cảnh". Tìm "Gõ mixed" / "mixed" ra chính nhóm.
- Key lưu không đổi ⇒ hành vi và sao lưu/khôi phục giữ nguyên.
- Mã: iOS `Shared/MixedTypingUI.swift` (danh mục, thuần, có test) + `App/MixedTypingSection.swift`; Android `ui/MixedTyping.kt`.

Nhóm công tắc (chuyển từ chỗ cũ sang):

1. **Nhận diện tiếng Anh**
   - Tự khôi phục từ tiếng Anh (`autoRestore`) — trước ở Tính Năng → Chính tả & sửa lỗi
   - Quyết định theo ngữ cảnh (`contextualEnglish`) — trước ở mục Kiểu gõ
   - Tự sửa từ phía trước (`retroactiveEnglish`, chỉ hiện khi bật ngữ cảnh và không VNI) — trước ở mục Kiểu gõ
   - Đoán từ trùng theo tần suất (`englishByFrequency`, nhãn "Thử nghiệm", cùng điều kiện hiện như trên) — trước ở mục Kiểu gõ
   - (macOS) Ưu tiên tiếng Việt khi từ trùng — khi làm macOS
2. **Chuyển ngôn ngữ**
   - Vuốt phím cách đổi Tiếng Việt / Tiếng Anh (`spaceSwipeLanguage`, iOS/Android) — trước ở Tính Năng → Phím & cử chỉ
   - Phím tắt đổi ngôn ngữ (macOS/Windows — nếu có)
3. **Gợi ý & gõ vuốt tiếng Anh**
   - Vuốt từ tiếng Anh (`swipeEnglish`) — trước ở Tính Năng → Gõ vuốt (chỉ hiện khi bật Gõ vuốt); nay luôn hiện, mờ + ghi chú "Cần bật Gõ vuốt" khi Gõ vuốt tắt
   - Liên kết Từ điển cá nhân (vẫn còn ở Gợi ý & từ điển)

Các mục khác của mục Kiểu gõ (Telex/VNI, Telex đơn giản, Bỏ dấu tự do, Gõ nhanh, Bỏ dấu kiểu mới, Tự động viết hoa, Chính tả teencode; Android thêm Gợi ý sửa lỗi chạm trượt) không phải gõ trộn ⇒ giữ nguyên.

**Bộ chọn nhanh** (đã làm trên iOS/Android; desktop macOS/Windows/Linux 05/11/2026, xem §11): **"Chủ yếu tiếng Việt / Việt + Anh nhiều / Chủ yếu tiếng Anh"** ở đầu nhóm (bấm = áp bộ cài đặt ở §3, có xác nhận nếu sẽ đổi công tắc người dùng đã tự chỉnh; cài đặt khớp đúng một hồ sơ thì tô hồ sơ đó, không khớp thì "Tuỳ chỉnh").

## 5. Người dùng cũ

- Không chạy onboarding. `onboardingDone` được đặt `true` khi phát hiện đã có cài đặt cũ (bản nâng cấp).
- Hiện **một lần** thẻ nhỏ trong app: "Bạn hay gõ trộn Anh/Việt? Xem nhóm Gõ mixed Việt/Anh mới" → mở tab Kiểu Gõ, mở sẵn nhóm §4. Đóng là không hiện lại.
- Không đổi bất kỳ giá trị nào của người dùng cũ.

## 6. Ngưỡng để đưa tính năng thử nghiệm vào hồ sơ `mixed`

Dùng bộ đo trộn Việt–Anh (đang xây cùng việc cải thiện nhận diện tiếng Anh):
- Văn bản thuần tiếng Việt / chat tiếng Việt (gồm láy: hí hí, hì hì; từ hiếm: nơ, bú, lát): tỉ lệ từ sai **không tăng** so với tắt.
- Câu tiếng Anh và câu trộn: tỉ lệ từ sai **giảm rõ** (mục tiêu ≥ 30% tương đối).
- Không tăng chi phí gõ khi tắt (perf test hiện có).

Đạt cả ba ⇒ bật trong `mixed`; không đạt ⇒ chỉ để công tắc trong nhóm §4.

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
- Từ vuốt (gõ vuốt) còn mở: **không chuyển** — đó là từ từ điển, phím gốc trong engine là phím tổng hợp chứ không phải phím người dùng gõ; vuốt phím cách chốt nguyên từ đó rồi đổi ngôn ngữ như cũ.
- Chữ trước con trỏ không khớp từ đang soạn / ô email / ô mật khẩu / phím engine không nhận ⇒ không chuyển, hành vi như cũ (chốt rồi đổi).
- Đã làm (iOS + Android): `EngineBridge.convertComposing(toEnglish:)` (+ iOS `flickLanguage`, Android `KeyboardSession.toggleLanguage(convertWord)`); bảng chữ mới áp (`KeyboardView.spaceFlickConvertsWord` / `Plane.LETTERS`). Mặc định tự khôi phục + kiểm tra chính tả bật thì `very` đã hiện `very` giữa từ (vuốt EN không đổi chữ); `vẻy` chỉ thấy khi tắt hai công tắc đó.
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
- Đã làm (iOS + Android, `CorrectionHintTests` hai nền tảng):
  - **Một quyết định chung**: `AutoCorrect` tách `plan` (phần thuần: từ có gõ sai không + ứng viên — chạy nền cùng thanh gợi ý, chỉ khi từ không khớp gì) và `decide` (điểm chạm + từ đã biết). Controller (`correctionDecision`) / `KeyboardSession` nhớ kết quả theo (phím thô, điểm chạm); dấu cách (`autoCorrector`) dùng lại đúng kết quả đó. Điều kiện theo chữ trên màn hình (hoa giữa câu, dính URL/email, gõ tắt, chế độ Tiếng Anh, ô email, omnibox…) dùng chung hàm của bridge: `EngineBridge.autoCorrectPreview` ↔ `tryAutoCorrect` ⇒ không tô ở chỗ dấu cách sẽ không sửa.
  - **Ứng viên chạm đúp** (mới, để có "Anhh" → Anh): bỏ một phím lặp liền nhau (`AutoCorrect.repeatCandidates`) — không cần bằng chứng hướng chạm, vẫn qua cùng ngưỡng tần suất/khoảng cách (`minFreq` 175, `margin` 30). Chỉ là phương án sau (xét khi không có ứng viên thay phím kề nào có bằng chứng chạm) và bỏ qua phím gõ đôi có nghĩa trong Telex (a e o d w + phím thanh): trộn chung thì P TEST tụt 97.3% → 96.5%; bản hiện tại 97.2% (AutoCorrectEvalTests, VT_SLOW_TESTS=1 — mô phỏng chưa có chạm đúp nên chưa đo được recall phần này). Áp cho cả dấu cách khi bật tự sửa ("ddii" → đi; "toii" không sửa vì "toi" không đủ phổ biến).
  - Ô 1 hiển thị “Anhh” (ngoặc kép cong, như ô nguyên văn iOS; Android bình thường không ngoặc, chỉ có ngoặc khi đang tô). Payload `keepTypedPrefix`/`KEEP_TYPED_PREFIX` + chữ gốc ⇒ chèn chữ gốc + ghi danh sách "từng hoàn tác tự sửa".
  - Ô tô nền: iOS = màu mặt phím chữ + chữ trên phím của theme (`KeyboardView.pillColors`); Android = màu chip thanh gợi ý của theme (`ImeTheme.chip`/`chipInk`, như pill Khôi phục). Khi tô, bỏ emoji ở ô cuối để ô đó là ứng viên kế.
  - Chi phí: thanh gợi ý tắt + tự sửa tắt ⇒ không ghi điểm chạm, không tính gì. Thanh bật ⇒ ghi điểm chạm (một struct/phím); `plan` chỉ chạy khi từ không khớp âm tiết nào; đọc context chỉ khi đã có bản sửa.
  - Cần điểm chạm: từ gõ bằng bàn phím cứng / từ vuốt / từ mở lại để sửa ⇒ không tô (như tự sửa). Thay thế văn bản + danh bạ (iOS) chỉ nạp khi bật tự sửa — tắt tự sửa thì ô tô nền có thể gợi ý cả tên trong danh bạ (chỉ là gợi ý).

## 9. Thứ tự làm

1. §7 (vuốt phím cách đổi từ đang soạn) và §8 (tô nền gợi ý sửa) — độc lập, nhỏ.
2. §4 nhóm "Gõ mixed Việt/Anh" + di chuyển công tắc + tìm kiếm — **xong iOS + Android** (macOS/Windows còn lại).
3. §2/§3 onboarding + hồ sơ; §5 thẻ cho người dùng cũ.
4. ~~Quyết định flag tần suất có vào hồ sơ `mixed` không~~ — đã chốt: có (§10).

## 10. Đã chốt (05/11/2026)

- Không có màn chọn Telex/VNI trong onboarding.
- Có lựa chọn thứ ba "Chủ yếu tiếng Anh" (hồ sơ `en`).
- Phím tắt đổi ngôn ngữ trên macOS/Windows: nhóm "Chuyển ngôn ngữ" chỉ hiện mục nào nền tảng đó có; kiểm tra lúc làm.
- `englishByFrequency` BẬT trong hồ sơ `mixed` và `en`.
- Dữ liệu tần suất tiếng Anh nguồn CC BY-SA 4.0 dùng trong engine (MIT) — chấp nhận, ghi nguồn ở docs/DATA-SOURCES.md.

## 11. Trạng thái triển khai (desktop) — 05/11/2026

Đã làm §2/§3/§4/§5 cho macOS, Windows, Linux (Linux có sẵn cửa sổ hướng dẫn bật bộ gõ + cửa sổ Cài đặt nên làm cùng đợt). **Bộ chọn nhanh hồ sơ** ở đầu nhóm (§4) — **đã làm trên cả ba** (cùng hành vi iOS/Android, §12 "Khớp / Tuỳ chỉnh"): ba dòng hồ sơ + dòng "Tuỳ chỉnh" (không bấm được); hồ sơ chỉ được đánh dấu khi các công tắc hồ sơ khớp đúng; hai hồ sơ cùng bộ công tắc ⇒ tô hồ sơ chọn gần nhất (`onboardingProfile`), chỉ xảy ra trên macOS (`mixed` ≡ `en`; Windows/Linux `en` khác `mixed` ở `startEnglish` / `default_vietnamese`); hỏi xác nhận (liệt kê công tắc sẽ đổi) chỉ khi đang "Tuỳ chỉnh". Áp = ghi giá trị §3 + `onboardingProfile`, không đụng `onboardingDone`/thẻ.
- macOS: `OnboardingLogic.match/changes/needsConfirmation` (`App/Sources/Onboarding.swift`), `SettingsModel.pickProfile/applyProfile` + `TypingTab.profilePicker` (dấu ✓, hộp `.alert`).
- Windows (06/11/2026, `docs/WINDOWS-APP-FEEL-SPEC.md` §4): màn chào chỉ còn MỘT trang "Đã sẵn sàng — gõ thử"; hai trang hồ sơ bỏ khỏi luồng chào — người mới dùng mặc định (= hồ sơ `vi`, `onboardingDone = 1`), chọn hồ sơ ở bộ chọn nhanh trong Cài đặt. Thẻ người dùng cũ giữ nguyên.
- Windows: `matchProfile/profileChanges/profileNeedsConfirmation` (`windows/app/core/onboarding.*`); trong Cài đặt mỗi hồ sơ là một thẻ có nút "Chọn" / "✓ Đang dùng" (đang dùng = không bấm được), xác nhận bằng MessageBox; trang dựng lại khi công tắc đổi làm đổi dòng đang dùng.
- Linux: `onboarding.match/changes/needs_confirmation/pick_profile` (`profile` ghi vào tệp trạng thái); dòng có dấu ✓ trong nhóm Gõ mixed, xác nhận bằng hộp `confirm`. Thêm `i18n.C_` (ngữ cảnh) vì "Tuỳ chỉnh" đã là tên tab ("Options"), ở bộ chọn là "Custom".

| | macOS | Windows | Linux |
|---|---|---|---|
| Màn chào | Chưa từng có ⇒ cửa sổ mới, hiện lần đầu VietTelex được chọn làm nguồn nhập (`App/Sources/Onboarding.swift`) | Cửa sổ chào sẵn có: trang cài đặt cũ → **Tiếp** → 2 trang mới (`windows/app/src/welcome.cpp`) | Cửa sổ hướng dẫn sẵn có: (bước bật bộ gõ nếu chưa xong) → 2 trang mới (`linux/settings/viettelex_settings/app.py`, phần thuần `onboarding.py`) |
| Hồ sơ `en` | = `mixed` (macOS không có chế độ tiếng Anh trong VietTelex; tiếng Anh = đổi nguồn nhập) | `mixed` + `startEnglish` mới (app chưa từng đổi Việt/Anh bắt đầu ở tiếng Anh) | `mixed` + `default_vietnamese = false` (key có sẵn) |
| Lưu trạng thái | `onboardingDone`, `onboardingProfile`, `mixedTypingCardPending` trong suite cài đặt | `onboardingDone`, `onboardingProfile`, `mixedCardPending` trong HKCU\Software\VietTelex | `$XDG_STATE_HOME/viettelex/onboarding` (`done`, `profile`, `card`) — không đụng hợp đồng `config.toml` |
| Nhận ra người dùng cũ | Suite đã có dữ liệu lúc process khởi động (mọi bản cũ ghi ít nhất `probeV2Reset`) và chưa có `onboardingDone` | Đã cài đặt người dùng từ bản trước (`decideWelcome` = MarkShown/Nothing) và chưa có `onboardingDone` | Đã có `config.toml` hoặc `app-state` và chưa có tệp trạng thái |
| Thẻ người dùng cũ | Đầu tab Gõ phím: "Xem" (cuộn tới nhóm) / "Đóng" | Thẻ đầu trang Kiểu gõ, nút "Xem" (cuộn tới mục) | Đầu trang Kiểu gõ, "Xem" / đóng |
| Nhóm "Gõ mixed Việt/Anh" | Mục ngay dưới Kiểu gõ (không thu gọn): tự khôi phục, ưu tiên khi trùng, ngữ cảnh, tự sửa, tần suất (từ Chính tả) + phím chuyển bộ gõ (từ tab Chung) | Mục ngay dưới Kiểu gõ: 5 công tắc trên (từ trang Chính tả) + phím chuyển + bắt đầu bằng tiếng Anh | "Gõ mixed Việt/Anh" + "Chuyển ngôn ngữ" ngay dưới Kiểu gõ (từ Tuỳ chỉnh): 5 công tắc + phím chuyển, nhớ theo app, app mới bắt đầu bằng tiếng Việt |

Chung cả ba: người mới bị đóng app giữa chừng ⇒ lần sau vẫn hiện (ghi `done = 0` ngay khi bắt đầu); "Bỏ qua" ở màn 1 = giữ mặc định, ở màn 2 = giữ hồ sơ vừa chọn; đóng cửa sổ = xong. Nhóm desktop là mục thường (không thu gọn) để thẻ cuộn tới được. Không vuốt phím cách / gõ vuốt trên desktop ⇒ nhóm chỉ có công tắc nền tảng đó có (§10).

Kiểm chứng:
- macOS: build + `OnboardingTests` (16) + `SettingsModelTests`, `PrivacyPaneTests`, `SettingsReloadCostTests`, `InfoPlistStringsTests`, `MemoryFootprintTests`, `AppSupportTests` đạt. **Chưa chạy thử thật** (quy tắc không đụng bộ gõ trên máy Phil): cửa sổ onboarding, việc gõ VietTelex vào ô gõ thử của chính process IME, cuộn tới nhóm.
- Windows: `ctest` máy chủ (10/10, `vtx_app_tests` 111 test gồm 5 test mới) + biên dịch chéo x64 (llvm-mingw) VietTelex.exe + TIP không lỗi/cảnh báo. **Chưa chạy trên Windows**: trang mới của cửa sổ chào, command link, thẻ/cuộn trong Cài đặt, `startEnglish` trong TIP.
- Linux: `make check` (162 test, gồm 16 test mới). **Chưa chạy GTK** (máy không có PyGObject).
- Bộ chọn nhanh (05/11/2026): macOS build + `OnboardingTests` (20, gồm 4 mới: khớp đúng, Tuỳ chỉnh, xác nhận, áp qua `SettingsModel`) + `SettingsModelTests`, `InfoPlistStringsTests` đạt; Windows `ctest` máy chủ 10/10 (`vtx_app_tests` 115, 4 mới) — **chưa biên dịch chéo** `settings_window.cpp` (Docker/OrbStack không chạy) và chưa chạy trên Windows; Linux `make check` 169 test (7 mới), chưa chạy GTK. Chưa mở thử giao diện trên cả ba.

## 12. Trạng thái triển khai — iOS + Android (05/11/2026)

**Đã làm §2, §3, §4 (bộ chọn nhanh), §5 trên iOS + Android.** macOS/Windows/Linux do nhánh riêng.

- Mã: phần thuần iOS `Shared/OnboardingProfile.swift` ↔ Android `keyboard/…/Onboarding.kt` (cùng số liệu, `OnboardingTests` / `OnboardingTest`); giao diện iOS `App/OnboardingView.swift` (+ bộ chọn trong `App/MixedTypingSection.swift`), Android `ui/Onboarding.kt` (+ `ui/MixedTyping.kt`).
- Luồng: lần đầu mở app hiện màn 1 (phủ toàn màn hình, trên thẻ "Bật bàn phím" sẵn có). Chọn hồ sơ ⇒ ghi giá trị ngay; bàn phím đã bật (Android: đã bật trong hệ thống) ⇒ sang màn 2, chưa bật ⇒ đóng, màn 2 tự hiện một lần khi quay lại app mà bàn phím đã bật. Màn 2 có "‹ Chọn lại" khi vừa đi từ màn 1. "Bỏ qua" ở màn 2 = giữ hồ sơ đã chọn, chỉ đóng. Android: chưa chọn VietTelex làm bàn phím ⇒ màn 2 có dòng "Chọn VietTelex…" mở bộ chọn bàn phím.
- Danh sách "Vừa bật" ở màn 2 = công tắc hồ sơ bật, theo cùng điều kiện hiện của nhóm Gõ mixed (Tự sửa / Đoán tần suất ẩn khi tắt ngữ cảnh hoặc VNI; Vuốt từ tiếng Anh chỉ khi Gõ vuốt bật).
- Hồ sơ `vi` ghi đúng mặc định hiện tại (ngữ cảnh BẬT, vuốt từ tiếng Anh BẬT). `collisionPrefersVietnamese` chỉ macOS — không có trên mobile.
- **Ngôn ngữ khởi đầu (`en`)**: ngôn ngữ đang gõ là trạng thái riêng của bàn phím (iOS: UserDefaults của extension, app không ghi được; Android: prefs `ime_state` của IME). App ghi yêu cầu một lần `keyboardLanguageRequest = "en@<mốc ms>"` (hồ sơ khác ghi `"vi@…"`) vào kho chung; bàn phím lần hiện kế tiếp thấy yêu cầu mới (khác `keyboardLanguageRequestApplied` nó nhớ) thì đặt ngôn ngữ một lần. Chọn lại hồ sơ ⇒ áp lại.
- **Khớp / Tuỳ chỉnh**: so đúng 6 key ở bảng §3. `mixed` và `en` cùng bộ công tắc ⇒ tô `en` khi `onboardingProfile` gần nhất là `en`, còn lại `mixed`. Bộ chọn: ba dòng hồ sơ + dòng "Tuỳ chỉnh" (không bấm được). Hỏi xác nhận khi cài đặt đang "Tuỳ chỉnh" và áp sẽ đổi ≥ 1 công tắc (hộp thoại liệt kê công tắc đổi); đang khớp một hồ sơ thì đổi thẳng.
- **Người dùng cũ**: chạy ĐẦU TIÊN lúc mở app (trước mọi chuyển đổi khác ghi key), chỉ khi chưa có `onboardingDone`: có bất kỳ key cài đặt nào (danh sách sao lưu + gõ tắt/mẫu câu/theme; iOS thêm cờ app bản cũ `rowAdjustStockBase`) ⇒ `onboardingDone = true` + thẻ một lần; không có ⇒ `onboardingDone = false` ghi tường minh (lần sau không đoán lại). Key bàn phím tự ghi (iOS `kbLastSeen`, `kbFullAccess`, `pasteNoPrompt`; Android emoji gần đây, mục dán đã mời, từ từng hoàn tác tự sửa) không tính — người mới bật bàn phím trước khi mở app vẫn được onboarding. Người dùng cũ chưa từng đổi cài đặt nào (Android; iOS chưa mở app từ 12/10/2026) được coi là người mới — chỉ khác là thấy onboarding, không có gì bị đổi nếu bỏ qua.
- Key thêm ngoài `onboardingDone` / `onboardingProfile`: `mixedTypingTip` (thẻ một lần), `keyboardLanguageRequest` (+ `…Applied` trong kho riêng bàn phím). Không key nào trong sao lưu / đồng bộ iCloud; Android Auto Backup có mang prefs `viettelex` ⇒ khôi phục máy mới coi như người dùng cũ (đúng ý).
- Bản Debug: iOS `-onboardingDemo choose|tryIt [-onboardingDemoProfile mixed]`, `-mixedTipDemo 1`; Android `am start … --es onboardingDemo choose|vi|mixed|en`, `--ez mixedTipDemo true`.
