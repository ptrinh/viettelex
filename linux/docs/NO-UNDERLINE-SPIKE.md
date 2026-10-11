# Spike: gõ "không gạch chân" ở Chromium/Electron trên Wayland — không root (08/10/2026)

> Trạng thái: SPIKE + prototype sau cờ thử nghiệm (mặc định TẮT). Chưa chạy trên desktop thật.
> Phạm vi: Chromium/Electron (mọi trình duyệt Chromium, VS Code, Slack, Discord, PWA…) trên
> GNOME Wayland (IBus) và KDE Plasma Wayland (Fcitx5). Nguyên tắc §1 LINUX-SPEC giữ nguyên:
> không root, không uinput, không nhóm `input`, không capability.

## 0. Tóm tắt — khuyến nghị

**Làm theo hướng "BackSpace do chính bộ gõ forward" (`no_underline = "forward-keys"`)**, không
cần extension, không cần portal, không cần quyền gì thêm:

- Sửa dấu trong Chromium bằng **phím BackSpace thật** (ForwardKeyEvent của IBus / `forwardKey`
  của Fcitx5) rồi `commit` chữ mới — thay cho `delete_surrounding_text`.
- Lý do khả thi (đọc mã nguồn, §3): **mutter ≥ 3.38** đưa phím forward của IM và commit của IM
  vào **cùng một hàng đợi sự kiện Clutter** theo đúng thứ tự IM gửi (MR !1286), và flush
  `text_input.done` trước khi một phím đi qua; **KWin** xử lý `keysym`/`key`/`commit_string` của
  `zwp_input_method_context_v1` đồng bộ theo thứ tự request. **Chromium** (ozone/wayland) xử lý
  `wl_keyboard.key` và `text_input.done` đồng bộ trên cùng một thread (đọc mã); phía renderer
  (cả hai đi qua `WidgetInputHandler`) giả định giữ thứ tự — chưa đọc/đo ⇒ trang web thấy
  `keydown BackSpace` rồi mới thấy chữ mới, như khi người dùng gõ tay — thứ mà Draft.js/Lexical
  (Messenger) theo dõi được.
- Tại sao `delete_surrounding_text` hỏng ở Messenger dù gửi "nguyên tử": Blink
  `ExtendSelectionAndDelete → DeleteSelection` phát `beforeinput(deleteContentBackward)` nhưng
  **bỏ qua kết quả** (không tôn trọng `preventDefault`) rồi vẫn xoá DOM ⇒ editor tự quản model
  (Draft.js/Lexical) xoá thêm một lần nữa / lệch model → "⌫ xoá 2 lần", lặp chữ. Gom
  delete+commit vào một `done` (phương án 4) không chữa được điều đó.
- Không cần echo kiểu Lotus: phím IM forward **không quay lại IM** (mutter bỏ qua phím mang cờ
  `CLUTTER_EVENT_FLAG_INPUT_METHOD`; KWin đưa thẳng vào seat), và thứ tự đã do compositor bảo
  đảm. Thay vào đó Session **xác nhận kết quả** bằng surrounding text của Chromium ở các phím
  sau (§6.2), sai/không xác nhận được trong 1 s ⇒ quay về preedit cho ô đó.
- Phần còn phải kiểm trên máy thật (§7): Chrome/Electron phải chạy IME Wayland gốc
  (`--enable-wayland-ime --wayland-text-input-version=3`), KHÔNG qua module GTK4
  (`--gtk-version=4`), vì khi đó commit đi trên kết nối Wayland khác của GTK ⇒ mất thứ tự.
- Các phương án khác: GNOME Shell extension (không cần — chỉ dự phòng), libei/portal (thừa
  quyền, có icon "đang điều khiển từ xa", phải chờ echo kiểu Lotus), KWin `fake_input` (không
  cần trên KDE, toàn quyền giả lập input) → **không làm**.

| Desktop | Khuyến nghị | Ghi chú |
|---|---|---|
| GNOME Wayland (IBus, Ubuntu 22.04/24.04/26.04) | **forward-keys** (prototype) | cần app id thật (GnomeAppMonitor), surrounding đã chứng minh; GNOME 45 có lỗi thứ tự commit→phím (đã sửa ở 46) — không ảnh hưởng chuỗi BS→commit. **GNOME 50: tắt** — mutter 50 bỏ phím forward (§5.2) |
| KDE Plasma Wayland (Fcitx5 frontend `wayland`) | **forward-keys** (prototype) | cần Fcitx5 biết app id (`program`, chưa kiểm trên KWin); KWin master bỏ text-input-v1 (27/02/2026) ⇒ Chromium dùng v3 |
| X11 (mọi desktop) | giữ preedit | Chromium X11 dùng GTK IM context riêng; forward key qua module GTK đi `gdk_event_put` — chưa kiểm chứng |
| wlroots (Sway, Hyprland; Fcitx5 `wayland_v2`) | giữ preedit | forward = `zwp_virtual_keyboard_v1`, commit = `input_method_v2` — hai object, thứ tự chưa kiểm |
| Fcitx5 trên GNOME Wayland (frontend `ibus`, vd. Zorin OS) | **forward-keys** (prototype, 09/10/2026) | chỉ ngữ cảnh của chính gnome-shell (host `FcitxGnomeWayland`, §5.1): `program` = `gnome-shell` (hoặc id app `*.desktop` / `window:N` của ngữ cảnh ảo Fcitx5 mới) **và** phiên GNOME Wayland; client IBus khác qua cùng frontend (X11/XWayland, `GTK_IM_MODULE=ibus`) vẫn `FcitxIBus` ⇒ preedit. App id: GnomeAppMonitor như IBus. GNOME 45 / 50: như dòng IBus |

## 1. Bài toán

- Chromium/Electron (và mọi app GNOME Wayland qua text-input-v3) luôn tự vẽ gạch chân preedit
  (LINUX-SPEC §3.1 bảng "Ai tôn trọng không gạch chân"). Muốn không gạch chân phải commit từng
  phím và sửa dấu trên chữ đã commit.
- Đường chuẩn để sửa là `delete_surrounding_text` + `commit`. Ở Chromium nó không tin được:
  - Chromium v3 `ZwpTextInputV3Impl::OnDone` áp delete trước rồi commit (một `done`), dựa trên
    `delete_around_range` của surrounding *đã gửi* (`TODO(crbug.com/40113488)`);
    `WaylandInputMethodContext::OnDeleteSurroundingText` còn ghi "data sent from delete
    surrounding text from exo is broken" (`TODO(crbug.com/40189286)`).
  - `InputMethodAuraLinux::OnDeleteSurroundingText` → `TextInputClient::ExtendSelectionAndDelete`
    → Blink `InputMethodController::ExtendSelectionAndDelete`: đặt selection rồi
    `DeleteSelection()` — phát `beforeinput` nhưng **không kiểm tra** nó bị huỷ hay chưa, sau đó
    `TypingCommand::DeleteSelection` vẫn chạy. Editor tự xử lý `beforeinput` (Draft.js, Lexical
    của Messenger) xoá một lần trong model, DOM bị xoá thêm lần nữa ⇒ đúng triệu chứng 1.0.6
    ("lặp chữ, ⌫ xoá 2 lần trên Messenger web"). VietTelex 1.0.7 đã thêm verify-before-delete
    và ép preedit cho cả họ Chromium.
- Phím BackSpace thật đi đường `keydown` → editor `preventDefault`/tự xoá → Blink tôn trọng.
  Đó là lý do Lotus (uinput) và ibus-bamboo (ForwardKeyEvent) "chạy được" ở web.

## 2. fcitx5-lotus làm thế nào (và vì sao không theo)

Đọc `LotusInputMethod/fcitx5-lotus` (main, 10/2026):

- `fcitx5-lotus-server@<user>.service`: `User=<proxy>`, `Group=input`,
  `AmbientCapabilities=CAP_SYS_NICE CAP_SYS_PTRACE`; udev `99-lotus.rules` chạy
  `setfacl -m u:<proxy>:rw /dev/uinput`. Addon gửi yêu cầu qua socket `SOCK_SEQPACKET` để server
  bắn BackSpace qua thiết bị uinput.
- `LotusState::performReplacement`: gửi `n + 1` BackSpace (thêm 1 nếu đoán có autofill), ngủ
  `pre_delay`/`post_delay` (2–8 ms × n). Phím uinput đi vòng **kernel → compositor → IM** nên IM
  thấy lại chúng ("echo"): `handleUInputKeyPress` cho n phím đầu đi qua app, nuốt phím cuối và
  commit trong lúc xử lý nó (`finishReplacement`, còn `sleep_for(2ms)` × 3 chờ surrounding);
  phím người dùng gõ trong lúc chờ bị đệm rồi phát lại (`replayBufferedKeys`); danh sách
  `ack_apps` (Chrome, Cốc Cốc…) cần "ACK workaround".
- Mô hình bảo mật: một tiến trình chạy nền có quyền ghi `/dev/uinput` (giả lập bất kỳ phím nào
  cho mọi phiên, kể cả màn hình khoá) + `CAP_SYS_PTRACE`. VietTelex từ chối (§1 LINUX-SPEC).
  Ngoài ra echo qua kernel là kênh *khác* với commit của IM ⇒ phải ngủ/chờ, đúng thứ VietTelex
  tránh (fcitx5-lotus #487: ngủ trong đường phím).

## 3. Phát hiện chính: compositor đã giữ thứ tự phím forward + commit

### 3.1 GNOME (mutter + gnome-shell, IBus)

- gnome-shell `js/misc/inputMethod.js` (giống nhau ở 42.0, 46.0, main):
  `_onForwardKeyEvent(keyval, keycode, state)` → `this.forward_key(keyval, keycode + 8, …)`;
  `_onCommitText` → `this.commit(text)`.
- mutter `clutter/clutter/clutter-input-method.c`: `clutter_input_method_forward_key` tạo phím
  mang `CLUTTER_EVENT_FLAG_INPUT_METHOD` rồi `clutter_event_put`; `clutter_input_method_commit`
  → `clutter_input_method_put_im_event(CLUTTER_IM_COMMIT)` → cũng `clutter_event_put`. Commit
  mutter **51760692** "clutter: Push commit/delete_surrounding as IM events" (MR !1286, có từ
  3.37.92/3.38.0): *"all actions triggered by the input method (commit and preedit buffer ones,
  but also synthesized key events) queue up the same way, and are thus processed in the exact
  same order than they are given to us."*
- `clutter_input_method_filter_key_event`: phím có cờ `INPUT_METHOD` → không gửi lại cho IM ⇒
  **không có echo**, engine không thấy lại BackSpace của mình.
- `src/wayland/meta-wayland-text-input.c`: `done` được hoãn sang idle `CLUTTER_PRIORITY_EVENTS+1`
  để gom; trước khi một phím IM/không bị lọc được gửi cho client thì `flush_done` (42: trong
  `handle_event` cho phím mang cờ IM; 46+: trong `update`, commit **381048cf**, đóng
  mutter#3090). GNOME **45.x** có hồi quy 7716b62fa2 làm mất flush ⇒ chuỗi *commit → phím* có
  thể đảo (ibus-hangul, mutter#3090); chuỗi của ta là *phím → commit* nên không bị, nhưng phím
  ranh giới sau commit vẫn có thể đảo trên 45 như mọi bộ gõ — Ubuntu không phát hành GNOME 45 LTS.
- Kết quả trên dây Wayland tới Chromium: `wl_keyboard.key(BackSpace)` ×n, rồi
  `zwp_text_input_v3.commit_string` + `done`.
- Kinh nghiệm cộng đồng: chế độ ForwardKeyEvent của ibus-bamboo "chạy tốt nhất trên GNOME
  Wayland" (diễn đàn Arch #283571, 2023; gnome-shell 43.3-1 làm hỏng tạm, 43.3-2 sửa).
  ibus-bamboo vẫn ngủ 10–30 ms/phím vì lỗi thứ tự ở *X11 GTK* (`gdk_event_put`), không phải mutter.

### 3.2 KDE (KWin + Fcitx5 frontend `wayland` = zwp_input_method_v1)

- Fcitx5 `src/frontend/waylandim/waylandimserver.h` `forwardKeyDelegate`: phím có keycode và
  không modifier → `sendKeyToVK` → `zwp_input_method_context_v1.key(code-8)` (tự gửi luôn
  release); không keycode → `keysym`. `mayCommitAsText` bỏ qua `\b`.
- KWin `src/inputmethod.cpp`: `InputMethod::key` → `seat()->notifyKeyboardKey` (wl_keyboard,
  đồng bộ); `keysymReceived` → text-input-v2 keysym hoặc `forwardKeySym` → `notifyKeyboardKey`;
  `commitString` → text-input-v3 `commit_string` + `done` ngay. Tất cả trong handler request,
  đúng thứ tự Fcitx5 gửi. (`deleteSurroundingText` gửi `done` riêng ⇒ delete và commit là hai
  lô ở client.)
- KWin bỏ text-input-v1 (commit ef1b092db6, 27/02/2026: "Chromium now has native TextInputV3
  support"; bản Plasma đầu tiên mang thay đổi: chưa kiểm) ⇒ Chromium trên KWin mới dùng v3; các
  bản trước (từ 5.27) còn v1 (wiki Fcitx khuyên `=1` cho KWin). Cả hai: phím đi `wl_keyboard`,
  commit đi text-input — cùng thứ tự trên dây.

### 3.3 Chromium (client)

- `ui/ozone/platform/wayland/host/wayland_keyboard.cc`: `OnKey → ProcessKey → DispatchKey`
  đồng bộ; `InputMethodAuraLinux::DispatchKeyEvent` với context Wayland không lọc ⇒
  `DispatchKeyEventPostIME` ngay.
- `zwp_text_input_v3.cc` `OnDone` → `OnCommitString` → `InputMethodAuraLinux::OnCommit` →
  `InsertText` ngay (ngoài DispatchKeyEvent).
- Phía renderer: phím và `ImeCommitText` đều đi qua `WidgetInputHandler`; **giả định** giữ thứ
  tự (chưa đọc mã renderer, chưa đo) — mục 2–3 của kế hoạch kiểm thử tay (§7) kiểm điều này.
- **GTK/Qt thì không**: GTK đưa `wl_keyboard` vào hàng đợi GDK nhưng phát `commit` ngay khi
  nhận `done`; Qt dùng `QWindowSystemInterface` (bất đồng bộ) cho phím, `sendEvent` cho commit.
  Vì vậy forward-keys **chỉ** cho họ Chromium; app GTK/Qt đã có surrounding text tin được.
- Chromium chạy IME qua module GTK4 (`--gtk-version=4`, không `--enable-wayland-ime`): commit
  đi trên kết nối Wayland *riêng của GTK* ⇒ mất thứ tự. Không phân biệt được từ phía IM
  (cả hai đều là text-input-v3) ⇒ dựa vào xác nhận §6.2 + hướng dẫn cờ trong tab Tương thích.

## 4. Đánh giá 4 phương án

| | 1. KWin (fake_input / IM forward) | 2. GNOME (extension / IBus forward) | 3. libei qua portal | 4. delete+commit một `done` |
|---|---|---|---|---|
| Khả thi | **Có**, qua chính `forwardKey` của Fcitx5 (đã là IM của KWin). `org_kde_kwin_fake_input` không cần | **Có**, qua chính ForwardKeyEvent của IBus (mutter giữ thứ tự). Extension không cần | Có, nhưng phím vào như bàn phím thật → đi qua IM → phải echo/chờ như Lotus | Không chữa được Draft.js (Blink bỏ qua `beforeinput` bị huỷ) |
| Bảo mật | Không thêm quyền. `fake_input`: global hạn chế, `authenticate` của KWin "TODO: make secure" — quyền giả lập toàn hệ | Không thêm quyền. Extension: chạy trong gnome-shell, toàn quyền shell | Phiên RemoteDesktop: quyền giả lập bàn phím toàn phiên cho tiến trình bộ gõ | Không |
| UX | Không hỏi gì; bật cờ trong config | Không hỏi gì. Extension: cài + bật tay, vỡ theo phiên bản shell | Hộp thoại đồng ý ("typically… a dialog"); `persist_mode=2` + `restore_token` (RemoteDesktop v2) nhớ lần sau; chỉ báo "đang điều khiển từ xa" tuỳ DE (chưa kiểm) | — |
| Thứ tự | KWin xử lý request đồng bộ, Chromium đồng bộ | mutter MR !1286 + flush done; Chromium đồng bộ | Hai kênh (EIS vs IM) ⇒ cần chờ echo + đệm phím + timeout | Một `done` nhưng Blink vẫn xoá DOM |
| Lỗi có thể | Chromium qua GTK4 IM; app id chưa biết; BackSpace vào vùng chọn | như trái; GNOME 45; ô shell (Alt+F2) mang id app bên dưới | mất echo, phím người dùng chen giữa, chậm | lặp chữ / xoá 2 lần |
| Bảo trì | Thấp (dùng API có sẵn) | Thấp. Extension: cao (mỗi bản GNOME) | Cao (libei, portal, chính sách từng DE) | — |

**InputCapture portal** là để *bắt* input (Barrier/Input Leap), không phải để giả lập — loại.

## 5. Theo desktop

- **GNOME Wayland** — mọi app gõ qua gnome-shell (client `gnome-shell`, host `IBusWayland`). Cần
  app id thật: `GnomeAppMonitor` (LINUX-SPEC §6.1). Bật forward-keys khi id thuộc họ Chromium,
  surrounding đã chứng minh, ô không phải URL/terminal/số/mật khẩu. Ubuntu 22.04 = GNOME 42 có
  đủ hàng đợi IM (≥ 3.38) và flush cho phím IM; 24.04 = 46 có bản sửa 381048cf.
- **KDE Wayland** — Fcitx5 là IM của KWin (frontend `wayland`, host `FcitxWayland`). App id lấy
  từ `program` của Fcitx5 (có hay không trên KWin: chưa kiểm); thiếu ⇒ id chung ⇒ preedit. Qt/GTK trên KDE đi `fcitx`/Qt
  text-input riêng — không đổi.
- **X11** — giữ preedit. Chromium X11 tự gạch chân mọi attr (`composition_text_util_pango.cc`);
  forward key qua module IBus GTK3 đi `gdk_event_put` trong khi commit phát ngay (LINUX-SPEC
  §3.1) — với Chromium chưa kiểm. Có thể thử sau với host `IBusGtk`/`FcitxOrdered` nếu cần.
- **Fcitx5 trên GNOME Wayland** (Zorin OS, Ubuntu + `im-config -n fcitx5`) — xem §5.1.
- **wlroots** — Fcitx5 `wayland_v2` forward bằng `zwp_virtual_keyboard_v1`, commit bằng
  `zwp_input_method_v2`: hai object, compositor xử lý theo thứ tự nhận nhưng chưa đọc kỹ ⇒ giữ
  preedit (host `FcitxWaylandV2` tách riêng để bật sau).

### 5.1 Fcitx5 trên GNOME Wayland (frontend `ibus`) — 09/10/2026

gnome-shell chỉ nói giao thức IBus D-Bus, nên trên GNOME Wayland Fcitx5 phục vụ nó qua frontend
`ibus` (giả làm ibus-daemon). Nhưng frontend đó cũng phục vụ mọi client IBus khác (app X11 /
XWayland với `GTK_IM_MODULE=ibus`, Qt `QIBusInputContext`) ⇒ `frontend == "ibus"` không đủ.

**Tín hiệu đã chọn (theo từng input context, không dựa env toàn cục):**
`fcitxIBusIsGnomeShell(program, phiênGnomeWayland)` (`common/src/app.cpp`) ⇒ host `FcitxGnomeWayland`.

- gnome-shell tạo ngữ cảnh bằng `create_input_context_async('gnome-shell', …)`
  (`js/misc/inputMethod.js`, 42.0 → main). Fcitx5 `IBusFrontend::createInputContext` giữ tên
  không chung chung làm `program` (chỉ `""`, `QIBusInputContext`, `gtk-im` mới bị thay bằng tên
  tiến trình qua `GetConnectionUnixProcessID`) ⇒ `program() == "gnome-shell"`. Client X11 gửi
  `gtk3-im:<prgname>` / `gtk-im` (→ tên tiến trình, vd. `chrome`) / `QIBusInputContext` — không bao
  giờ là `gnome-shell`.
- Fcitx5 bản có `GnomeAppMonitor` riêng (`src/frontend/ibusfrontend/gnomeappmonitor.cpp`, chỉ bật
  khi desktop GNOME + `XDG_SESSION_TYPE=wayland` + không flatpak, nhận gnome-shell bằng **pid
  người gọi** == pid của `org.gnome.Shell`): engine thấy `VirtualInputContext` (frontend vẫn `ibus`)
  mỗi app, `program` = id ShellApp (`google-chrome.desktop`, `window:12`; overview = `gnome-shell`).
  Tên `*.desktop` / `window:N` không client IBus nào gửi ⇒ cũng nhận là gnome-shell. Addon không
  hỏi được pid người gọi (API công khai không có) ⇒ dùng tên.
- Kèm điều kiện phiên GNOME Wayland (`isGnomeWaylandSession()` của tiến trình Fcitx5,
  `XDG_CURRENT_DESKTOP` chứa GNOME — Zorin là `zorin:GNOME`): trên GNOME X11, ngữ cảnh
  `gnome-shell` chỉ phục vụ ô của chính shell, app X11 có IM module riêng.
- Đã loại: `InputContext::display()` — ngữ cảnh `ibus` nhận focus group mặc định
  (`Instance::defaultFocusGroup` ưu tiên nhóm `wayland:`), giống hệt cho client X11 ⇒ không phân
  biệt được; env `WAYLAND_DISPLAY`/`XDG_SESSION_TYPE` một mình — phiên Wayland vẫn có app
  XWayland; cờ capability — gnome-shell và module GTK đều báo PREEDIT|FOCUS|SURROUNDING.

**Thứ tự:** `IBusInputContext::forwardKeyDelegate` phát signal `ForwardKeyEvent` (keycode − 8,
`bus()->flush()`), `commitStringDelegate` phát `CommitText` — cùng một kết nối D-Bus tới
gnome-shell ⇒ gnome-shell nhận theo thứ tự gửi; `_onForwardKeyEvent` → `forward_key(keyval,
keycode + 8, …)`, `_onCommitText` → `commit()` — từ đây y hệt đường IBus (hàng đợi Clutter MR
!1286, flush `done` 6f316345). Khác IBus duy nhất: không qua ibus-daemon (bớt một chặng, không
thêm kênh). Keycode: addon gửi `Key(BackSpace, 0, 22)` ⇒ Fcitx5 gửi 14 ⇒ gnome-shell cộng 8 =
22 (đúng evdev KEY_BACKSPACE + 8); release do addon gửi (frontend `ibus` không tự thêm).
Cảnh báo GNOME 45 (mutter#3090) áp dụng y như IBus: chỉ ranh giới commit→phím, không ảnh hưởng
chuỗi BS→commit.

**App id:** gnome-shell là client nên `program` là `gnome-shell`. Fcitx5 cũ (không có app
monitor riêng — Zorin 17 / Ubuntu 22.04 Fcitx5 5.0.x, 24.04 5.1.7): addon đã dùng chung
`GnomeAppMonitor` của `linux/common` (cùng cơ chế với engine IBus: theo dõi reply
`GetRunningApplications` mà xdg-desktop-portal-gnome nhận) cho id chung `gnome-shell`. Fcitx5 mới:
`program` của ngữ cảnh ảo là id app luôn (`google-chrome.desktop` → `google-chrome`). Chưa có id
thật (portal thiếu, đang chờ reply, overview, `window:N`) ⇒ id chung ⇒ preedit.


### 5.2 GNOME 50: mutter bỏ phím forward — 11/10/2026

Thử trên Ubuntu 26.04 (GNOME Shell 50.1, mutter 50.1-0ubuntu2.4), VS Code 1.141 + Chromium
Wayland, cả IBus lẫn Fcitx5 5.1.19: `forward-keys` bật đúng (app id, surrounding đã chứng minh)
nhưng **BackSpace forward không tới app**, commit vẫn tới ⇒ "thuw" → "thuư"; xác nhận phát hiện
lệch và về preedit, nhưng chữ đã sai.

Nguyên nhân (mutter, không phải VietTelex/Fcitx5): từ 50.alpha (e68b5882, "Drop virtual device
field from ClutterEvent structs") `clutter_input_method_forward_key` tạo key event với
`source_device = NULL`, mà `clutter_event_key_new` vẫn `g_return_val_if_fail
(CLUTTER_IS_INPUT_DEVICE (source_device), NULL)` ⇒ trả NULL, phím mất (journal có critical
`clutter_event_key_new`). Issue mutter #4853 (bộ gõ tiếng Việt daklak gặp y hệt), sửa bằng
!5121 (2710ddc8) — **chỉ có từ 51.0**, không backport về nhánh `gnome-50`; Ubuntu 26.04 chưa
vá (changelog tới 50.1-0ubuntu2.5).

Xử lý: `GnomeAppMonitor` đọc `org.gnome.Shell` `ShellVersion` lúc khởi động;
`gnome::mutterDeliversForwardedKeys(major)` = `major > 0 && major != 50` (chưa biết ⇒ không);
engine đặt `FieldHints::forwardedKeysDropped` cho host `IBusWayland` / `FcitxGnomeWayland` ⇒
`resolveAppPolicy` giữ preedit. App cài đặt: `launchers.applicability(..., gnome_major=50)` →
`"gnome_50"`, dòng mô tả giải thích. Không có đường thay thế trên GNOME 50:
`delete_surrounding_text` là đúng cái Draft.js/Lexical không theo được (§1).

## 6. Prototype (commit này)

### 6.1 Cấu hình + chính sách

- `config.toml`: `[experimental] no_underline = "off" | "forward-keys"` (mặc định `off`; giá trị
  lạ = `off`). Hợp đồng: `common/SETTINGS.md` §9. App cài đặt: nút "Bỏ gạch chân trong
  Chrome/Electron (thử nghiệm)" (tab Tuỳ chỉnh) — bật thì tự tạo lối tắt `.desktop` có cờ IME
  Wayland cho mọi app họ Chromium đã cài (§6.4).
- `resolveAppPolicy` (`common/src/app.cpp`): `forward-keys` + `isChromiumApp(id)` +
  `hostOrdersForwardedKeys(host)` (`IBusWayland`, `FcitxWayland`, `FcitxGnomeWayland`) + surrounding đã chứng minh +
  không pin + không phải id chung / URL / terminal / số / nhạy cảm ⇒ `mode = Surrounding`,
  `deleteWithKeys = true`, `allowSurroundingEdits = false` (không re-edit, không ⌫ mở lại từ —
  chỉ sửa trong từ đang gõ, gõ tắt, tự khôi phục). Pin `[app_modes]` luôn thắng. Danh sách
  Chromium tách ra `isChromiumApp` (vẫn nằm trong `isForcedPreeditApp` — đường mặc định không đổi).
- Fcitx5 frontend `wayland_v2` nay là `ClientHost::FcitxWaylandV2` (trước gộp với `wayland`);
  Direct không đổi (cả hai đều "không").

### 6.2 Session (`common/src/session.cpp`)

- `InputContext::forwardBackspaces(n)` (mặc định = `deleteBeforeCursor`). IBus:
  `ibus_engine_forward_key_event(BackSpace, 14, 0/RELEASE)`; Fcitx5: `forwardKey(Key(BackSpace,
  0, 22))`, frontend `wayland`/`wayland_v2` tự thêm release. Keycode thật bắt buộc: gnome-shell
  cộng 8, mutter gửi `event_code` cho client (keycode 0 ⇒ phím evdev 0).
- `replaceBeforeCursor`: khi `deleteWithKeys_`: `forwardBackspaces(n)` rồi `commit(chữ mới)`
  (không cần commit rỗng như text-input-v3). Mọi chỗ khác (verify-before-delete, chặn vùng chọn,
  distrust → preedit) dùng lại nguyên đường Surrounding.
- **Xác nhận (không chờ, không timer)**, `checkKeyEdit` ở đầu mỗi phím:
  - `ackTrail_`: chữ VietTelex biết nằm trước con trỏ (≤ 48 ký tự): mọi commit, phím ranh giới
    app tự gõ, ⌫ của app, mỗi BackSpace forward và chữ thay. `ackStates_`: mọi giá trị trước đó
    kể từ lần host xác nhận gần nhất (host áp dụng *muộn* nhưng *không đảo*, nên chỉ được hiện
    đúng một trong các trạng thái này).
  - Lần đầu trail bắt đầu (focus, click, Enter…): ghi `seed` = 8 ký tự host đang hiện trước con
    trỏ. Khi chưa neo, mọi trạng thái so như `seed + trạng thái` ⇒ "yỳ" không qua được "ỳ"
    (BackSpace đầu tiên bị mất), " " không khớp nhầm khoảng trắng có sẵn của host.
  - Host hiện đúng trail ⇒ **xác nhận**: neo trail vào chữ thật của host (+8 ký tự ngữ cảnh;
    biết cả "đầu ô" ⇒ so bằng nhau thay vì so đuôi).
  - Host hiện một trạng thái cũ ⇒ **đang trễ** (sửa tiếp vẫn an toàn vì kênh có thứ tự).
  - Khác mọi trạng thái, hoặc đang có sửa bằng BackSpace mà quá `kKeyEditAckTimeoutMs = 1000 ms`
    chưa xác nhận ⇒ **lỗi**: bỏ từ đang gõ (chữ để nguyên trên màn hình), `distrust()` ⇒ preedit
    tới lần focus sau. Chỉ gõ thường mà lệch (trang tự đổi chữ: emoji, autocomplete) ⇒ bắt đầu
    theo dõi lại, không phạt.
  - Chi phí: một lần đọc đuôi surrounding (≤ ~60 ký tự, đã có sẵn trong process) mỗi phím khi
    cờ bật; tắt cờ = 0 chi phí (không đọc gì).

### 6.3 Kiểm thử tự động (`common/tests/test_common.cpp`, ctest `common`)

`AsyncHost`: host áp dụng *muộn* theo đúng thứ tự (BackSpace forward, commit, phím app), báo
surrounding sau khi áp dụng; lỗi tiêm được: mất BackSpace, BackSpace đôi (trang xoá 2 lần),
commit đôi (Draft.js), surrounding đóng băng; đồng hồ giả.

| Test | Nội dung |
|---|---|
| `testForwardKeysTypesInPlace` | không preedit, không `del:`, mỗi `bs:n` đi ngay trước commit của nó |
| `testForwardKeysHostLags` | host trễ 2/3/5 phím, không báo gì một lúc, ⌫ của người dùng — không fallback |
| `…LostBackspace` / `…DoubledBackspace` / `…DuplicatedCommit` | phát hiện ở phím kế, về preedit, không gửi BackSpace nữa, `focusIn` mở lại |
| `testForwardKeysTimeout` | surrounding không cập nhật: trong 1 s vẫn gõ tại chỗ, quá 1 s ⇒ preedit |
| `testForwardKeysSelectionAndKeys` | vùng chọn ⇒ không BackSpace; Enter/tắt cờ ⇒ bỏ theo dõi |
| `testForwardKeysPolicy` / `…Config` | bảng chính sách (host, app, ô, pin, mặc định tắt), parse/serialize |
| `testForwardKeysAgreesWithSurrounding` | 1000 kịch bản ngẫu nhiên × chữ có sẵn trong ô: cùng kết quả với Surrounding (không re-edit), host trung thực không bao giờ fallback |
| `testForwardKeysRandomFaults` | 1000 kịch bản, một lỗi ngẫu nhiên, host trễ 1–3 phím: luôn đúng chữ hoặc fallback — không bao giờ sai mà im lặng |

Kết quả (Docker `viettelex-build:noble-arm64`): ctest đủ bộ xanh; chạy thêm
`VT_STRESS_ROUNDS=60000` (60 000 vòng mỗi test ngẫu nhiên): 0 lỗi. Đo phụ: host trung thực nhưng
trễ 1–3 phím *và* ô có sẵn chữ ⇒ 24/20 000 kịch bản (0,12 %) fallback thừa về preedit (seed lấy
lúc host còn trễ) — an toàn, không sai chữ.

### 6.4 Cờ IME Wayland tự động (app cài đặt, 10/10/2026)

Mặc định hiện tại (đọc mã Chromium main + ghi chú phát hành, 10/10/2026):

- **Chrome/Chromium ≥ 137**: text-input-v3 bật mặc định — `kWaylandTextInputV3`
  `FEATURE_ENABLED_BY_DEFAULT` (commit e48954bd "[ozone/wayland] Make WaylandTextInputV3 enabled by
  default", 10/04/2025; chromiumdash: bản đầu 137.0.7121.0). `IsImeEnabled()` trả true khi feature
  bật mà không cần `--enable-wayland-ime`; `GtkUiPlatformWayland::CreateInputMethodContext` trả
  `nullptr` ("Use text-input-v3 on Wayland") ⇒ không còn module GTK trên Wayland.
- **Chrome ≥ 140**: `--ozone-platform-hint=auto` thành mặc định (Wayland gốc khi phiên là Wayland);
  Chromium main đã bỏ hẳn cờ hint (`SetOzonePlatformForLinuxIfNeeded` tự chọn Wayland).
- **Electron ≥ 38** (Chromium 140): "Electron now runs as a native Wayland app by default"
  (`--ozone-platform` mặc định `auto`, bỏ `ELECTRON_OZONE_PLATFORM_HINT`) ⇒ cũng có text-input-v3.
- ⇒ Chrome/Electron cập nhật thì **không cần cờ** trên GNOME. Cần cờ: Electron < 38 (mặc định
  XWayland — cần `--ozone-platform-hint=auto` mới sang Wayland), Chromium 128–136, KDE với KWin
  < 6.7 (Fcitx khuyên text-input-v1). Không đọc được phiên bản (Electron, Brave, Vivaldi…) ⇒ vẫn
  thêm cờ (vô hại khi đã là mặc định). Chrome/Edge/Chromium .deb + snap chromium ≥ 140 ⇒ bỏ qua.
- Cờ thêm: `--enable-wayland-ime --wayland-text-input-version=3 --ozone-platform-hint=auto`
  (KWin < 6.7: `=1`). Cách chèn, quy tắc sở hữu file: `common/SETTINGS.md` §9.1.
- Không dùng `~/.config/chrome-flags.conf`: wrapper `google-chrome` của gói .deb
  (`chrome/installer/linux/common/wrapper`) không đọc file đó (chỉ gói AUR của Arch).
- Gợi ý "mở lại app" phía bộ gõ (khi app Chromium tới qua module GTK/XWayland): **không làm**.
  Kênh duy nhất có sẵn là gợi ý cạnh con trỏ (`showHint`, aux text) — gắn với Tab = áp dụng,
  phải thêm loại gợi ý mới + lưu "đã báo" + chạy trong đường phím. Thay vào đó app cài đặt dò
  `/proc`: app đang chạy mà tiến trình chính không mang `--enable-wayland-ime` ⇒ báo "thoát hẳn
  rồi mở lại …" ngay khi bật.

Nguồn: https://chromium.googlesource.com/chromium/src/+/e48954bdc391fcba2fd20a5a40a8a16332cf1638 ;
https://chromiumdash.appspot.com/commit/e48954bdc391fcba2fd20a5a40a8a16332cf1638 ; Chromium main
`ui/base/ui_base_features.cc`, `ui/ozone/platform/wayland/host/wayland_input_method_context.cc`
(`IsImeEnabled`, `CreateTextInput`), `ui/gtk/wayland/gtk_ui_platform_wayland.cc`,
`ui/linux/display_server_utils.cc`, `chrome/installer/linux/common/wrapper` ;
https://www.electronjs.org/blog/electron-38-0 ;
https://www.omgubuntu.co.uk/2025/08/chrome-140-wayland-auto-detection-linux ;
https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland .

## 7. Còn phải kiểm trên máy thật — kế hoạch kiểm thử tay

Không chạy được phiên GNOME/KDE thật ở đây. Đã cân nhắc Docker headless (`gnome-shell
--headless` + Chromium + IBus + Mutter RemoteDesktop để bơm phím + CDP đọc DOM): cần image
GNOME + Chromium vài GB, và gnome-shell headless + IBus trong
container nhiều ẩn số ⇒ không làm trong spike này.

Chuẩn bị (mỗi máy), không cần gõ lệnh:

1. Cập nhật VietTelex (bản từ nhánh này).
2. Mở **VietTelex** (app cài đặt) → tab **Tuỳ chỉnh** → bật **"Bỏ gạch chân trong Chrome/Electron
   (thử nghiệm)"**. Dòng mô tả liệt kê app đã thêm cờ / đã bật sẵn / cần mở lại.
3. **Thoát hẳn** Chrome / VS Code / Slack… (Chrome: menu → Thoát, kể cả chạy nền) rồi mở lại từ
   menu ứng dụng hoặc dock.

Kiểm (tuỳ chọn) `chrome://gpu` → "Ozone platform: wayland". Mở app từ terminal thì không có cờ
của lối tắt — Chrome ≥ 140 / Electron ≥ 38 vẫn đúng vì đã là mặc định. Trang thử: `data:text/html,<textarea>`,
`data:text/html,<div contenteditable>`, messenger.com (Lexical), facebook.com ô bình luận
(Draft.js/Lexical), Google Docs, Slack/Discord (Electron), VS Code.

| # | Bước | Mong đợi |
|---|---|---|
| 1 | Ubuntu 24.04 GNOME Wayland + IBus, Chrome ở trên, gõ `tieesng vieejt dduwowcj ` vào textarea | Không gạch chân; ra "tiếng việt được " |
| 2 | Như 1 ở Messenger (ô chat) và bình luận Facebook | Không lặp chữ, ⌫ xoá đúng 1 ký tự, gửi tin đúng chữ |
| 3 | Gõ nhanh hết mức (giữ nhịp ~10 phím/s) một đoạn 3 câu; so với gõ trên gedit | Giống hệt; không ký tự thừa |
| 4 | Thanh địa chỉ (omnibox) | Gạch chân (ô URL ⇒ preedit) |
| 5 | Bôi đen chữ trong textarea rồi gõ `aa` | Thay vùng chọn bằng "â", không xoá thừa |
| 6 | `journalctl --user -f` / `ibus engine` + `dbus-monitor "interface='org.freedesktop.IBus.Engine'"` | Thấy `ForwardKeyEvent(0xff08, 14, …)` rồi `CommitText` |
| 7 | Mở Chrome bằng `--gtk-version=4` (không `--enable-wayland-ime`), làm lại 1–3 | Nếu lặp/sai chữ: phải tự về gạch chân sau ≤ 1 s (fallback); ghi lại |
| 8 | VS Code, Slack, Discord (Electron, cờ Ozone tương ứng) | Như 1–2 |
| 9 | Ubuntu 22.04 (GNOME 42) làm lại 1–3 | Như trên |
| 10 | Kubuntu/KDE Plasma 6 Wayland + Fcitx5 (Virtual Keyboard = Fcitx 5), Chrome v3 (và v1 nếu KWin ≤ 6.6) | Như 1–5 |
| 11 | KDE: `fcitx5-diagnose` phần "Frontend" + `WAYLAND_DEBUG=1 google-chrome … 2>&1 \| grep -E "wl_keyboard@.*key\|commit_string"` | Thứ tự `key(14)` ×n trước `commit_string` |
| 12 | Tắt nút trong app cài đặt | Về như 1.0.7: Chrome gạch chân; `~/.local/share/applications` không còn file có `X-VietTelex-Generated` |
| 12b | Bật lại; xem `~/.local/share/applications/google-chrome.desktop` (hoặc `code.desktop`…) | `Exec=` (cả Desktop Actions) có cờ ngay sau chương trình, trước `%U`; `Icon`/`TryExec`/`StartupWMClass` giữ nguyên; app vẫn hiện đúng trong menu/dock |
| 13 | Máy tải nặng (`stress -c $(nproc)`), gõ như 3 | Hoặc đúng chữ, hoặc tự về gạch chân; không bao giờ sai chữ mà vẫn không gạch chân |
| 14 | Zorin OS / Ubuntu GNOME Wayland + Fcitx5 (`im-config -n fcitx5`), Chrome + VS Code/Antigravity với cờ Ozone, làm lại 1–5 | Như 1–5 |
| 15 | Như 14: `dbus-monitor --session "interface='org.freedesktop.IBus.InputContext'"` (frontend `ibus` của Fcitx5 nằm trên session bus) | `ForwardKeyEvent(65288, 14, …)` nhấn + nhả cho mỗi BS rồi `CommitText` |
| 16 | Như 14 nhưng một app XWayland với `GTK_IM_MODULE=ibus` (vd. `google-chrome --ozone-platform=x11`) | Gạch chân (host `FcitxIBus`) |

Ghi lại cho mỗi dòng: phiên bản GNOME/KWin, Chrome, IBus/Fcitx5, kết quả, có fallback không
(VietTelex về gạch chân giữa chừng = fallback).

## 8. Rủi ro

- Chromium chạy IME qua GTK4 hoặc XWayland: thứ tự không bảo đảm; chỉ có lưới an toàn §6.2
  (phát hiện ở phím kế / ≤ 1 s, chữ sai đã nằm trên màn hình *một* lần).
- Lỗi ngay lần sửa đầu tiên sau khi con trỏ dời mà host còn trễ lúc đó: có thể không phát hiện
  (seed cũ = an toàn, seed thiếu = "eẽ" lọt). Hiếm nếu Chromium báo surrounding nhanh hơn nhịp
  gõ (chưa đo).
- Trang web chặn/đổi nghĩa phím BackSpace (editor code, game, phím tắt riêng) ⇒ xoá sai; xác
  nhận sẽ thấy lệch ⇒ preedit. Ô có autocomplete chèn chữ phía sau con trỏ không ảnh hưởng
  BackSpace; chèn phía trước ⇒ lệch ⇒ preedit.
- Shift đang giữ khi sửa (chữ hoa): Chromium nhận Shift+BackSpace = BackSpace. Phím Ctrl/Alt
  luôn kết thúc từ trước (không có Ctrl+BackSpace).
- GNOME 45 (không LTS): hồi quy flush mutter#3090 ảnh hưởng mọi bộ gõ (commit ↔ phím ranh giới).
- `ForwardKeyEvent` bị gnome-shell bỏ khi không có focus (`priv->focus` NULL) ⇒ mất BackSpace ⇒
  phát hiện được (test "lost BackSpace").
- Bảo trì: chỉ dùng API IM có sẵn; rủi ro là Chromium đổi cách xử lý `wl_keyboard`/text-input
  (theo dõi khi Chrome lớn ra bản) và mutter/KWin đổi hàng đợi (đã ổn định từ 2020).

## 9. Nguồn (đọc ngày 08/10/2026)

- mutter: `clutter/clutter/clutter-input-method.c`, `clutter-input-focus.c`,
  `src/wayland/meta-wayland-text-input.c` (main, 42.0, 46.0) —
  https://gitlab.gnome.org/GNOME/mutter ; commit 51760692 / MR
  https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/1286 ; commit 6f316345 "wayland: Flush
  text_input.done event after IM key event"; commit 381048cf / MR
  https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/3536 ; issue
  https://gitlab.gnome.org/GNOME/mutter/-/issues/3090 (hồi quy 7716b62fa2, GNOME 45).
- gnome-shell `js/misc/inputMethod.js` (42.0, 46.0, main) — https://gitlab.gnome.org/GNOME/gnome-shell
- KWin `src/inputmethod.cpp`, `src/wayland/textinput_v3.cpp`,
  `src/backends/fakeinput/fakeinputbackend.cpp` (master) — https://invent.kde.org/plasma/kwin ;
  commit ef1b092db6 "wayland: Drop TextInputV1"; MR https://invent.kde.org/plasma/kwin/-/merge_requests/3403
  (thêm text-input-v1 cho Chromium, 5.27).
- Fcitx5 `src/frontend/waylandim/waylandimserver.{h,cpp}`, `waylandimserverbase.cpp`,
  `src/frontend/ibusfrontend/ibusfrontend.cpp` — https://github.com/fcitx/fcitx5 ; wiki
  https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland (KWin: ưu tiên text-input-v1 cho Chromium,
  "Chromium support for text-input-v1 is not very stable").
- Chromium `ui/ozone/platform/wayland/host/{wayland_keyboard,wayland_input_method_context,
  zwp_text_input_v3,zwp_text_input_v1}.cc`, `ui/base/ime/linux/input_method_auralinux.cc`,
  `third_party/blink/renderer/core/editing/ime/input_method_controller.cc` —
  https://chromium.googlesource.com/chromium/src (main); crbug.com/40113488, crbug.com/40189286
  (TODO trong mã).
- fcitx5-lotus `src/lotus-state.cpp`, `src/ack-apps.h`, `server/lotus-server.cpp`,
  `misc/fcitx5-lotus-server@.service.in`, `misc/99-lotus.rules.in` —
  https://github.com/LotusInputMethod/fcitx5-lotus
- ibus-bamboo `engine_backspace.go` — https://github.com/BambooEngine/ibus-bamboo ; diễn đàn Arch
  https://bbs.archlinux.org/viewtopic.php?id=283571
- IBus `src/ibusengine.c` (`ibus_engine_forward_key_event`) — https://github.com/ibus/ibus
- xdg-desktop-portal RemoteDesktop (`persist_mode`/`restore_token`, `ConnectToEIS` từ v2) —
  https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.RemoteDesktop.html
