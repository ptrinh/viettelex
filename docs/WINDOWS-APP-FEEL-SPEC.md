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

## Bản portable (duyệt 06/11/2026)

Lựa chọn phụ cho máy không có quyền cài / muốn thử nhanh. Bản cài (TSF) vẫn là bản chính.

- **Gói:** `VietTelex-<ver>-portable-{x64,arm64}.zip` (exe đã ký) — giải nén, chạy `VietTelex.exe`.
  Không cần quyền quản trị, không ghi HKLM, không đăng ký COM/TSF.
- **Cách gõ:** hook bàn phím toàn hệ thống (đường "Dự phòng" đã có, `hook_fallback.cpp`) cho MỌI app.
  Ô mật khẩu / terminal / per-app "Luôn tiếng Anh" giữ nguyên quy tắc. App chạy quyền quản trị: không
  gõ được (UIPI) — báo rõ trong tooltip/HDSD.
- **Nhận diện chế độ:** có file `portable.ini` (hoặc `VietTelex.portable`) cạnh exe ⇒ chế độ portable.
  Cài đặt lưu cạnh exe (`settings.ini`/json); fallback `%APPDATA%\VietTelex` nếu thư mục chỉ đọc.
  Không bao giờ đụng TSF/registry hệ thống; không tự khởi động cùng Windows trừ khi người dùng bật
  (HKCU Run, trỏ đúng đường dẫn exe hiện tại).
- **Gặp bản cài sẵn:** nếu VietTelex (TSF) đã cài và đang chọn, bản portable không chạy hook song
  song (tránh bỏ dấu hai lần) — báo và thoát hoặc nhường.
- **Cập nhật:** không tự cập nhật; "Kiểm tra cập nhật" mở trang tải zip mới.
- **Khay + Ctrl+Shift + màn chào:** giống bản cài (mục 2–5), bỏ phần chọn bàn phím Windows.
- **Phát hành:** `release.sh` đóng thêm 2 zip (exe ký + `portable.ini` + README ngắn) + SHA256SUMS;
  trang tải: dòng "Không cài được? Dùng bản portable". HDSD: mục portable + đánh đổi (trình duyệt/
  Word kém hơn bản cài, app quyền quản trị, một số game).
- **Test:** logic thuần (nhận diện chế độ, đường dẫn cài đặt, quyết định nhường bản cài) trên host.

## Trạng thái triển khai (06/11/2026)

Đã làm toàn bộ mục 1–6 + bản portable. Quyết định nằm trong lõi thuần, test trên host
(`windows/app/tests/app_feel_tests.cpp`, `portable_zip_test.sh`); phần Win32/TSF giữ mỏng.

| Mục | Lõi (test host) | Win32 |
|---|---|---|
| 1. Cài xong là gõ được | `app_feel.h planKeyboardAtStart`: thiếu trong danh sách / lần đầu ⇒ thêm + mặc định + chọn; sau "Thoát" ⇒ chọn lại; người cũ đã có VietTelex ⇒ không đụng | `main.cpp ensureKeyboardAtStart`, `tip_control.cpp` (`vietTelexInUserList`, `selectVietTelexForSession` = `ActivateProfile(TF_IPPMF_FORSESSION)`) |
| 2. Khay mặc định bật cho người mới, chữ V/E, bấm trái đổi Việt/Anh | `isNewUser` / `applyNewUserDefaults`; `trayClickAction` | `main.cpp trayLeftClick` (bấm đúp = Cài đặt); menu thêm "Thoát VietTelex" |
| 3. Trạng thái "đang tắt" | `trayStateFor` (V / E / Off) | biểu tượng mờ (`CreateDimmedIcon`), tooltip; bấm trái = chọn lại VietTelex. Không thông báo |
| 4. Màn chào một trang | `welcomeResolveRow` (chỉ bộ gõ khác đang chạy / "Vietnamese Telex" của Windows) | `welcome.cpp` viết lại; "Xử lý…" mở hộp xung đột sẵn có. Hồ sơ gõ không còn trong luồng chào (người mới = mặc định, chỉnh trong Cài đặt) |
| 5. Thoát từ khay | `pickExitLayout` (bàn phím trước đó ⇒ US ⇒ không phải tiếng Việt) | `quitFromTray`: chọn lại cho phiên + cờ `reselectOnStart` |
| 6. Tài liệu + trang tải | test: HDSD/trang tải không nêu tên bộ gõ khác | `docs/hdsd`, `docs/en/guide`, trang tải: một nút tự chọn x64/ARM64 (`userAgentData`), không chắc ⇒ hiện cả hai; khối "Không cài được? Dùng bản portable" (link zip lấy từ `stable.json` `windows.portable_x64/arm64`, chưa có ⇒ trang Releases) |
| Portable | `portable.h`: marker, đường dẫn `settings.ini`, `KeyValueFile`, nhường bản cài (`yields`), `hookPlan`, ô mật khẩu Win32, autostart | `settings_store.cpp` (kho `settings.ini`, không snapshot), `foreground.cpp`, `hook_fallback.cpp publishForegroundPortable`, mutex/lớp cửa sổ riêng, Ctrl+Shift tự đổi, "Khởi động cùng Windows" trong menu khay, cập nhật = mở trang tải; `scripts/make-portable.sh` + `release.sh` (zip từ exe đã ký, kiểm exe trong zip = exe đã ký, SHA256SUMS) |

**Chưa chạy trên Windows thật** (chỉ ctest host + biên dịch chéo llvm-mingw x86/x64/ARM64, TIP
498 KB < 520 KB): chọn bàn phím cho phiên/cửa sổ (`ActivateProfile`, `WM_INPUTLANGCHANGEREQUEST`)
và Thoát trả bàn phím cũ; bấm trái khay đổi Việt/Anh (TIP đọc lại trạng thái khi app lấy lại focus);
biểu tượng mờ; màn chào mới; toàn bộ bản portable (hook mọi app, gõ trong cửa sổ của chính nó,
`settings.ini` cạnh exe / `%APPDATA%`, nhường bản cài, autostart). Ô mật khẩu của trình duyệt/UWP
không thấy được từ hook — bản portable chỉ nhận ra ô mật khẩu Win32 (ghi trong HDSD). Đổi phím
chuyển sang Alt+Z không có tác dụng ở bản portable (chỉ Ctrl+Shift và bấm khay).
