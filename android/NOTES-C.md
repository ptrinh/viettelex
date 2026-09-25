# NOTES-C — IME (agent C)

## Cần agent D (manifest / build)
- MainActivity: intent-filter deep link `viettelex://maucau` (ACTION_VIEW, BROWSABLE+DEFAULT,
  scheme `viettelex`, host `maucau`). IME mở bằng `setPackage(packageName)` + NEW_TASK|CLEAR_TOP.
- `androidResources { noCompress += listOf("bin") }` để mmap vnlexicon/emojisuggest (IME có
  fallback đọc cả file nếu vẫn nén).
- Service `.ime.VietTelexIME` đã khai đúng; `@xml/method` + `@string/ime_name` do C tạo
  (res/xml/method.xml, res/values/ime_strings.xml). settingsActivity = `.ui.MainActivity`.
- Không cần quyền mới (VIBRATE/INTERNET đã có).

## Settings dùng chung
- `com.viettelex.android.shared.VTPrefs`: `of(ctx)`, `settings(prefs)` (= KeyboardSettings.load),
  `templates(ctx)`. `DebugLog.tail/clear/file` cho tab Giới Thiệu.
- IME nghe `userlmResetAt` qua OnSharedPreferenceChangeListener ⇒ `model.reloadAfterExternalErase()`
  ngay (không đợi lần hiện sau), nên không bao giờ ghi lại model cũ.

## Gửi B (không sửa module B)
- API.md ghi `KeyboardSession(model, clipboard, main)`; code là `(model, clipboard, clock)` — IME theo code.
- `UserLangModel.finishLoad` parse seed.tsv trên MAIN lần chạy đầu (userlm trống) — nên parse ở io.

## Map nền tảng C đã chốt (theo §12)
- NO_SUGGESTIONS chỉ ẩn bar; ô số/điện thoại/ngày cũng ẩn bar. TYPE_NULL = literal + key event.
- Return: xuống dòng = KEYCODE_ENTER; hành động = performEditorAction. ⌫ thường (không soạn) =
  KEYCODE_DEL (xoá cả grapheme/selection, chạy cả terminal). Diff engine = deleteSurroundingTextInCodePoints.
- Trackpad = DPAD_LEFT/RIGHT (không cần biết vị trí con trỏ). 🗑 = commitText("") + deleteSurroundingText(20000, 20000).
- Phím 🌐 rộng 0.10 (iOS không ghi hệ số). Balloon kẹp trong khung IME (không vẽ ra ngoài cửa sổ).
- Cỡ chữ theo sp, kẹp fontScale 0.85…1.2 (phím cao cố định như iOS).

## Còn thiếu / chưa kiểm trên máy
- Chưa chạy trên thiết bị (không được cài): cần đo cold-start / PSS (log `VTKB perf`, `VTKB mem`
  ở bản debug), kiểm inset nav bar (gesture + 3 nút, API 35+ edge-to-edge) và ma trận field §13.
- emoji2 chưa thêm (quy tắc không thêm dependency) ⇒ máy cũ có thể hiện ô trống với emoji mới.
- TalkBack cho phím vẽ Canvas (ExploreByTouchHelper cần androidx.customview) chưa làm.

## Giao diện Gboard (26/09/2026)
- Màu: res/values{,-night}{,-v31}/ime_colors.xml (v31 = Material You động). Phím enter luôn là pill màu nhấn.
- `showSpaceLogo` giờ bật/tắt nhãn "Tiếng Việt" trên space (không còn logo Vᴛ) — D có thể đổi chữ toggle.
- Tham chiếu Gboard trên emulator không chụp được (Gboard chỉ hiện thanh công cụ bàn phím cứng).
