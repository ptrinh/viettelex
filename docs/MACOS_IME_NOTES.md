# macOS Input Method — Hard-Won Registration Notes

Why a third-party IMKit input method does / doesn't appear in
**System Settings → Keyboard → Input Sources**. Written after a long debugging
session on **macOS 26.5 Tahoe**. Read this BEFORE touching signing / bundle id /
Info.plist again — every item below cost real time to discover.

> Lessons here are HISTORY (what broke and why) — the *current* per-app strategy
> selection lives in `TYPING-STRATEGIES.md` + `typing-modes.yml`; app lists
> named below may be stale.

## Đừng để hai self-report của app "bỏ phiếu" chống nhau — 2026-07-28 (issue #31)

Google Sheets trong Chrome: "phải double-click vào ô mới nhập được dữ liệu". Log
(v1.4.17) chỉ ra chuỗi nhân quả đầy đủ:

```
probe(verify) start=1 bs=1 len=1 caret=2 expReplace=2 expAppend=3 regionMatch=no → appended
verify: appended (strike 1/2)
probe(ax·verify) axMatch=no                      ← AX cache của Chromium cũng stale
probe(verify) start=1 bs=1 len=2 caret=2 expReplace=3 expAppend=4 regionMatch=nil → appended
verify: appended twice → marked text for this focus
reprobe t0=appended … axMatch2=yes imkMatch2=yes axLen=2 caret2=2   ← replace ĐÃ vào đúng chỗ
```

Ô đó **hoàn toàn khoẻ** (AX xác nhận), nhưng bị hạ xuống marked text — và **ô Sheets
đang được chọn mà chưa ở chế độ nhập thì bỏ qua marked text**, nên gõ gì cũng mất, tới
khi double-click. Hai phán đoán sai độc lập cộng lại:

1. **`regionMatch=no` được phép lật một caret trung thực.** Luật đó sinh ra vì Lark
   (caret rác hằng số trùng `expectedReplace`), nhưng `HonorTracker` (đòi 2 lần honored ở
   2 offset KHÁC nhau) đã lo ca Lark rồi. Còn `attributedSubstring` của Chromium thì
   **stale ngay sau `insertText`** — mismatch ở đó nghĩa là "read-back trễ", không phải
   "replace thất bại". Nay: caret == expectedReplace **và** region không khớp ⇒
   `.inconclusive` (hai self-report đánh nhau thì học được gì?), để AX phân xử.
2. **Cửa sổ "caret nói dối" đo từ sai mốc.** Trước đo từ `start`; đúng ra phải đo từ
   `expectedReplace`: replace để caret ở `expectedReplace`, append để ở
   `start+bs+len` (xa hơn về PHẢI) ⇒ mọi caret **bên trái `expectedReplace`** không thể
   là append, nó là báo cáo stale. Sheets trả caret=2 cho expReplace=3 (trễ đúng một
   edit) — trước bị coi là append, nay là inconclusive. Cửa sổ vẫn hẹp (`maxCaretLag=4`)
   nên caret rác hằng số của Lark (1 so với 30) vẫn là bằng chứng thật và vẫn bị hạ.

Nguyên tắc rút ra: **`.appended` chỉ được kết luận khi có ≥2 tín hiệu ĐỘC LẬP đồng ý**,
hoặc khi AX (ground truth) nói vậy. Một self-report đơn lẻ trái với self-report khác của
cùng app là "không biết", không phải "thất bại" — hạ mode oan tốn của người dùng nhiều
hơn là chờ thêm một probe.

## Ô mật khẩu: `IsSecureEventInputEnabled()` KHÔNG đủ — 2026-07-27

Field report: "điền password thấy nó inject thêm 1-2 ký tự".

`IsSecureEventInputEnabled()` chỉ đúng với app **tự bật secure input**: login window,
Keychain Access, `sudo` trong terminal, `NSSecureTextField` native. Một
`<input type="password">` trên web **KHÔNG** bật nó. Nên trước 1.4.19 engine vẫn compose
bình thường trong form đăng nhập của browser, và:

- chiến lược `.emptyReset` (omnibox browser + Office) chèn **U+202F** để huỷ inline
  autocomplete rồi backspace xoá đi — nếu ô password có JS handler nuốt/đổi thứ tự thì
  ký tự đó **sống sót** = đúng "1 ký tự lạ";
- `.selection` bấm Shift+← rồi ghi đè — trong ô password là ăn/thêm ký tự;
- và ô password rơi vào `.emptyReset` dễ hơn tưởng: per-field detector không đọc được
  cây AX (Gecko, hoặc Chromium chưa build tree) thì mặc định là *selection*.

**Tín hiệu đúng: subrole `AXSecureTextField`** (AppKit `NSSecureTextField` và mapping của
WebKit/Chromium cho password input đều dùng nó) → `SecureFieldDetector`. Hai đường bàn
phím đều passthrough hoàn toàn khi thấy nó, engine reset, không emit gì.

Ba chi tiết phải giữ:
1. **Chỉ subrole khớp CHÍNH XÁC mới tính secure.** Subrole thiếu/không đọc được phải coi
   là *không* secure — false positive là im lặng tắt gõ tiếng Việt ở mọi nơi.
2. **Không post health probe (F20) khi ô password đang focus.** Dưới secure input tap
   không nhận event, nên marker mình post không được chính mình nuốt → nó rơi vào app
   đang focus. Và watchdog phải **không** tính đó là probe miss, kẻo báo "stale grant"
   oan rồi tear down tap đang lành.
3. Probe post cả **keyUp** (trước chỉ có keyDown → phím logic bị giữ ở app theo dõi
   key state).

Cache: TTL 300ms + invalidate khi `activateServer` (đổi ô/đổi app). Ký tự ĐẦU của
password mà đọc trễ thì vô hại — engine chỉ ghi lại text từ phím thứ hai của âm tiết.

## "Quyền Trợ năng bị kẹt": nguyên nhân thật và cách sửa dứt điểm — 2026-07-27

**Cơ chế.** Grant Accessibility nằm ở TCC.db hệ thống, mỗi dòng gồm bundle id + một
blob **`csreq`** — chính Designated Requirement của app lúc được cấp. Khi app xin event
tap, tccd đối chiếu chữ ký của tiến trình với `csreq` đó. Còn cái tick trong System
Settings thì **chỉ vẽ theo bundle id/path**, không verify lại `csreq`. Vì vậy trạng thái
"tick vẫn bật mà bị từ chối" là hoàn toàn có thật và người dùng không thể nhìn ra.

**`AXIsProcessTrusted()` KHÔNG đáng tin trong trạng thái này** — nó vẫn trả `true`
(Apple forums 758554: `tapCreate` trả NULL trong khi AX nói trusted). Dùng preflight
đúng quyền thay thế (DTS khuyến nghị, forums 727984):
`CGPreflightPostEventAccess()` / `CGPreflightListenEventAccess()`. Dấu vân tay của
trạng thái kẹt: `AXIsProcessTrusted() == true && CGPreflightPostEventAccess() == false`.

**Nguyên nhân xếp theo xác suất:**
1. Dòng TCC được tạo bởi một build **không phải** Developer ID của mình (ad-hoc/Xcode/
   XCTest host): `csreq` khi đó ghim cdhash hoặc leaf cert → mọi bản ký đúng sau này đều
   trượt, vĩnh viễn. `project.yml` build ad-hoc, nên `requestIfNeeded()` từ 27/07 **từ
   chối prompt** nếu team ≠ 84T567KMYD (`Accessibility.isOurSignedBuild`).
2. **Thay bundle khi tiến trình còn chạy**: inode cũ bị unlink, tiến trình đang chạy
   trượt validation. Apple ("Updating Mac Software", Quinn forums 703188) yêu cầu quit
   trước rồi swap. `SelfUpdater` nay `stopForUpdate()` (tháo tap) TRƯỚC `replaceItemAt`.
3. **Merge residue phá code seal.** Installer của `.pkg` **merge** payload: file bản cũ
   mà bản mới bỏ đi vẫn nằm lại → seal hỏng → tccd từ chối. `SelfUpdater` vốn dùng
   `replaceItemAt` (atomic, không merge); từ 27/07 `.pkg` có **preinstall** xoá bundle cũ
   để có cùng bảo đảm đó.
4. Bug tccd/Settings (macOS 13+), và trên Sequoia: tiến trình `LSBackgroundOnly` bị từ
   chối tap dù có grant (forums 758554) — VietTelex dùng `LSUIElement`/accessory nên
   **không** thuộc ca này (đã kiểm 27/07).

**Cách sửa trong app (thay 4 bước làm tay).** `tccutil reset Accessibility <bundle-id>`
xoá đúng dòng của mình → prompt lại sẽ ghi dòng MỚI theo chữ ký hiện tại; đây chính là
hiệu ứng của nút `−` rồi `+`, làm bằng code. Không cần root để reset **chính mình**, và
nó chỉ có thể XOÁ quyền, không bao giờ cấp. Quinn (forums 696174) cảnh báo Apple có thể
siết `tccutil` nếu app lạm dụng để nag người dùng ⇒ **chỉ chạy khi người dùng bấm nút**,
không bao giờ tự động/định kỳ. Prompt lại phải phát từ **chính tiến trình này** (nó là
code identity đang xin), nên không được `exit` trước khi prompt.

Không có tác dụng: kill tccd (respawn, không sửa csreq), sửa TCC.db trực tiếp (SIP),
`lsregister -kill` (đó là chuyện LaunchServices, không phải TCC).

**Các app khác ship gì:** espanso (#2562) và Karabiner: hướng dẫn làm tay; Hammerspoon
FAQ: `tccutil reset All org.hammerspoon.Hammerspoon`; BetterTouchTool: khuyên remove/
re-add. **Không ai tự động hoá im lặng** — state of the art là *phát hiện + một nút
reset & xin lại*, đúng cái VietTelex làm từ 1.4.18.

**Checklist phòng ngừa (mỗi release):** DR phải identity-based (bundle id + team OU,
không cdhash) — `make-release.sh` **fail build** nếu DR lệch; grant đầu tiên chỉ được
tạo từ bản notarized; quit/tháo tap trước khi swap bundle; pkg xoá bundle cũ; tap owner
không được `LSBackgroundOnly`; sau update tự kiểm bằng preflight + tapCreate.

## Debug logging KHÔNG được nằm trên hot path — 2026-07-27

`reprobeDeferred` (experiment log-only) chạy **đồng bộ trong `handle()`** ở phím ngay
sau mỗi lần replace, và gọi 2 lần `AXTextEdit` — mỗi call có thể block tới **50ms**
messaging timeout. Cộng thêm `probe(shadow)` chạy mỗi lần replace (tức mỗi phím có
dấu) với 1 IMK read-back + 1 AX read nữa.

Hệ quả: **cứ tester nào bật "Nhật ký gỡ lỗi" là thấy gõ dấu bị chậm** — rồi báo lỗi
latency, trong khi bản build bình thường (log tắt) không hề chậm (0.138 µs/phím).
Đúng cái bẫy Heisenberg: dụng cụ đo làm sai kết quả đo. Report issue #28
(meichengg, VNI trên Raycast).

Từ 27/07: AX read của reprobe chạy trên `axProbeQueue` (async, log từ đó — verdict
vốn không bao giờ được dùng), và shadow probe bị throttle 1 lần/giây. Quy tắc chung:
**mọi thứ chỉ để chẩn đoán phải chạy ngoài `handle()`**, hoặc bị lấy mẫu, không bao
giờ mỗi phím.

## Caret self-report có thể ở TOẠ ĐỘ KHÁC (Jira/ProseMirror) — 2026-07-27

Probe in-place phân loại app bằng caret sau khi replace: honored = `start+len`,
appended = `start+bs+len`. **Cả hai đều ≥ `start`.** Log tester (v1.4.12, Jira trong
Chrome, ô "Create bug"):

```
probe(verify) start=1339 bs=1 len=1 caret=1338 expReplace=1340 expAppend=1341 regionMatch=nil → appended
verify: appended (strike 1/2)
probe(verify) start=1339 … caret=1338 … → appended
verify: appended twice → marked text for this focus
…
probe(verify) start=2 bs=1 len=1 caret=0 expReplace=3 expAppend=4 regionMatch=no → appended
probe(ax·verify) axMatch=yes        ← AX nói replace ĐÃ vào đúng chỗ
```

Caret **thấp hơn cả anchor** → không thể là kết quả của replace *hay* append. Đây là
ProseMirror trả về position trong document model của nó (lệch vài đơn vị vì node
boundary), hoặc caret đọc được là bản cũ chưa cập nhật. Nhưng verdict cũ gom hết vào
`appended` → 2 strike → **hạ field xuống marked text GIỮA TỪ** (`engine.reset()`), và
đó chính là cái người dùng thấy: chữ bị "tự bôi đen rồi xoá", ra `cậcâ`.

**Luật hiện tại:** caret nằm sau anchor tối đa `maxCaretLag = 4` đơn vị ⇒
`.inconclusive` — không strike, không promote, probe lại lần sau (AX async vẫn có thể
kết luận). Cửa sổ hẹp có chủ ý: caret rác HẰNG SỐ (Lark luôn trả 1) khi gõ giữa ô sẽ
cách anchor rất xa nên vẫn là `.appended` và vẫn bị hạ sau 2 strike như cũ. Bounded:
4 lần inconclusive liên tiếp trong một focus thì vẫn hạ xuống marked text — không
biết gì cũng không được phép kéo dài mãi.

## The working recipe (do all of these; they are AND, not OR)

1. **Notarize + staple.** macOS 26 silently refuses to register an un-notarized
   input method — no log, survives logout. Proven with a control: a notarized
   third-party input method in the same `~/Library/Input Methods` registered on
   the first logout; our identical-but-unnotarized builds never did.
   `spctl -a -t exec <app>` must say **accepted** (Notarized), not "rejected
   (Unnotarized)". Sign Developer ID Application + hardened runtime, then
   `notarytool submit --wait` + `stapler staple`. See `Scripts/notarize-install.sh`.

2. **Bundle id must contain `inputmethod` as a segment.** e.g.
   `com.viettelex.inputmethod.telex`. `com.viettelex.ime` did NOT register.
   (Apple's own use `com.apple.inputmethod.*`.)
   The input-mode id must be the bundle id + a suffix
   (`com.viettelex.inputmethod.telex.vi`).

3. **`InputMethodServerControllerClass` in Info.plist must match the REAL ObjC
   class name.** This was the single nastiest bug. The Swift class had
   `@objc(TelexInputController)`, which registered it in the ObjC runtime as bare
   `TelexInputController`, but Info.plist declared `VietTelex.TelexInputController`.
   `NSClassFromString("VietTelex.TelexInputController")` → nil → IMK can't
   instantiate the controller → macOS never registers the input method.
   **Fix:** no explicit `@objc(name)` on the controller class. A Swift class that
   subclasses `IMKInputController` is auto-exposed as `Module.Class`
   (mangled `_TtC9VietTelex20TelexInputController`), which is exactly what
   `NSClassFromString("VietTelex.TelexInputController")` resolves. Verify with:
   `otool -ov <binary> | grep TelexInputController` → must show `_TtC9VietTelex...`,
   NOT bare `TelexInputController`.

4. **Bundle ids get POISONED — use a FRESH id after any broken install.**
   Installing a bundle id even once while it is invalid (unsigned / sandboxed /
   wrong class) caches a negative verdict for that id. After fixing everything,
   that same id STILL never registers (`TISRegisterInputSource` → noErr but the
   source is never enumerated, even after logout). We burned
   `com.viettelex.inputmethod` and `com.viettelex.ime` this way. The moment we
   used a brand-new id (`com.viettelex.inputmethod.telex`) with all the fixes, it
   registered. **Corollary: always notarize + fix BEFORE the first install of any
   id, so you never poison the id you intend to ship.**

5. Install to **`~/Library/Input Methods`** (user-owned, no sudo). `/Library`
   needs root:wheel ownership; a hand-copied bundle there is owned wrong and gets
   skipped.

6. **Sandbox OFF for the dev / Developer ID build.** Sandbox without a provisioning
   profile blocks registration; `get-task-allow` is rejected by notarization.
   Sandbox belongs ONLY to the MAS build (`VietTelex-MAS.entitlements`), signed
   Apple Distribution + a provisioning profile at submission.

## Things that are NOT the cause (ruled out — don't chase these again)

- **`Contents/CodeResources`** as a real file: that is the **stapled notarization
  ticket** (magic bytes `s8ch`), normal for a stapled app. Apps distributed without
  stapling lack it. Harmless.
- **`com.apple.provenance` / `com.apple.macl` xattrs**: kernel-managed, can't be
  stripped, present on other input methods too. Irrelevant.
- **MDM / config profiles**: none restrict input methods here.
- **Location `/Library` vs `~/Library`**: both work if ownership is right.
- **Missing localization (lproj / InfoPlist.strings)**: only affects the display
  name, not whether it enumerates.
- **A new Sequoia/Tahoe "approval" gate for IMEs**: does not exist (that's for
  DriverKit extensions, not input methods).

## Display name in the picker (not the raw id)

Once registered, the picker showed the raw id `com.viettelex.inputmethod.telex.vi`
instead of a readable name. The picker name comes from **`InfoPlist.strings` in an
`.lproj`**, keyed by the input-source id — NOT from
`tsInputModeAlternateMenuTitleStringKey` (that key only names the menu-bar item).

Fix: `App/Resources/{en,vi}.lproj/InfoPlist.strings` (bundled via `project.yml`):

```
"CFBundleName" = "VietTelex";
"com.viettelex.inputmethod.telex"    = "Tiếng Việt (VietTelex)";
"com.viettelex.inputmethod.telex.vi" = "Tiếng Việt (VietTelex)";
```

Changing the name needs a re-notarize + refresh (remove & re-add the source, or log
out/in) because the name is cached with the registration.

## Typing mechanism: NO marked text (Vietnamese habit)

Vietnamese typists expect: **no underline, caret always at the end**, characters
transform in place. So the controller does NOT use marked
text. Each engine transform is a minimal `(backspaces, insert)` diff applied in
place via `client.insertText(insert, replacementRange:)`, where the range is
`(selectedRange().location - backspaces, backspaces)`.

- This requires `client.selectedRange()` to return a real caret. It does in Cocoa
  apps (TextEdit, Safari, Mail, Office…). Verified: 0 "unusable" log events typing
  in TextEdit.
- Apps that return `NSNotFound` for `selectedRange()` (some terminals / Electron)
  can't be edited this way — the controller logs
  `selectedRange unusable … app=<bundleid>` (subsystem
  `com.viettelex.inputmethod.telex`, category `controller`) and best-effort inserts
  without deleting. Those apps need a per-app strategy (see checklist.md). Do NOT
  fall back to CGEvent backspaces from an IMKInputController: the synthesized
  Delete key re-enters `handle()` as `kDelete` and corrupts the engine — that was
  the original garbled-output bug.
**Dual-mode (final design).** Default = in-place (no underline). An unclassified
app is probed once (read-back after the first real replace); if it silently ignores
replacementRange (Terminal / iTerm — valid caret but no actual replace), it flips to
**marked-text mode** for every future keystroke and the choice is persisted
(`AppState.usesMarkedText` / `fallbackApps`). So normal apps stay clean (no
underline), and only terminals show the brief composing underline. This keeps the
IMKit architecture — no Accessibility permission, Mac-App-Store-compatible.

Why can't the no-underline feel cover iTerm too via pure IMKit? A CGEventTap app
that simulates real Backspace+retype keystrokes can, but that needs Accessibility
permission and cannot ship on the Mac App Store (sandbox forbids global event
posting). We chose the IMKit + App-Store path deliberately; terminals get marked
text as the trade-off — UNLESS the Developer ID build has Accessibility (see
terminal tap-mode below).

**Terminal tap-mode (Developer ID only).** Marked text in a terminal breaks shell
autocomplete (each key sits in the composition buffer until the boundary, so
zsh-autosuggestions / Tab never see partial input), and terminals also don't honor
IMKit `return true` suppression without a marked-text op — an IME literally cannot
stop the raw key there. So for terminal-class apps we bypass IMKit entirely:
`TerminalTapController` runs a `CGEventTap` (`.cgSessionEventTap`,
`.headInsertEventTap`) that intercepts keyDown BEFORE the terminal. Plain letters
pass through natively (shell sees them live → autocomplete works); a tone edit is
SUPPRESSED (return nil) and applied by synthesizing real Backspace + Unicode
(`SyntheticKeyboard`, posting to the session tap). Both Vietnamese AND autocomplete
work — the case pure IMKit cannot serve.

Key details (all learned the hard way):
- Needs Accessibility to create the tap and post events → Developer ID (non-sandbox)
  only. `usesTapMode` = `fallbackApps.contains(id) && AXIsProcessTrusted()`; the
  sandboxed MAS build can't be trusted and transparently stays on marked text.
- Re-entrancy: our posted events re-enter the tap and the IME. They are stamped via
  the event SOURCE's `userData` (`CGEventSource.userData = magic`) — the PER-EVENT
  `.eventSourceUserData` field does NOT survive posting; the source's value does.
  Both the tap and `handle()` check `isSynthetic` and pass them straight through.
  (Missing this caused a 9× Backspace cascade that wiped the line.)
- The tap only acts while VietTelex is the active input source (`imeActive`, set in
  activate/deactivateServer) so switching to ABC/US in a terminal really types
  English. It reads the frontmost app via `NSWorkspace`, and only for terminal
  (`fallbackApps`) apps; everything else passes through to the normal IMKit path.
- Grant/menu: the input-method menu's status line ("Tình trạng: Thiếu quyền")
  prompts + opens the Accessibility pane when clicked. After granting, restart the
  IME (or it re-attempts `TerminalTapController.start()` on the next activateServer).
- Gotcha: if Accessibility is stale (granted to an earlier signature) `AXIsProcessTrusted()`
  can return true while `CGEventPost` is silently dropped. Remove + re-add VietTelex
  in the Accessibility list to fix.
- **Gotcha: nothing expensive in the tap callback, or `tapDisabledByTimeout` leaks keys.**
  The callback runs per keystroke; if it's too slow the system DISABLES the tap
  (`.tapDisabledByTimeout`) and, until we re-enable it, physical keys fall through to
  the (terminal-broken) IMKit marked-text path → intermittent garbage
  ("wirwiwriaărirw" in a Claude Code TUI). Caused by calling
  `SpotlightDetector.isVisible` (a full `CGWindowListCopyWindowInfo` enumeration) on
  every key — now cached with a ~200ms TTL. Keep the callback O(1): set/dict lookups
  only, no window-list/AX/Workspace scans per key.
- **Gotcha: the IMKit controller and the tap MUST decide "is this a tap app?" from the
  SAME source.** The tap uses `NSWorkspace.frontmostApplication`; the controller used
  `currentBundleID` (the IMK client id from activateServer), which can be nil/stale.
  When nil, the controller thought "unknown app → in-place" and composed into a
  terminal the tap was already handling; a leaked physical key (brief tapDisabled
  window) then got composed by IMKit → intermittent garbage in iTerm/Claude Code
  ("Khoông..."). Debug snapshot showed `App: ?` + `in-place` while the tap was running.
  Fix: the controller's tap-defer check also consults `NSWorkspace.frontmostApplication`,
  so the two never disagree.
- **Arrow / navigation / F-keys must pass through, never re-emit as text.** In iTerm,
  `keyboardGetUnicodeString` returns arrows as CONTROL chars (len 1): Left 0x1C, Right
  0x1D, Up 0x1E, Down 0x1F — NOT the 0xF700–0xF8FF function-key range (that range shows
  up in some other apps). The non-letter branch would `emitBoundary` + `reemit` them as
  INSERTED TEXT (keyboardSetUnicodeString), so the terminal got a raw 0x1C instead of the
  arrow's escape sequence (`ESC[D`) → cursor/history navigation dead. Fix: in `handle()`,
  if `buf[0] < 0x20` (any control char — Return/Tab/Esc/Backspace are already handled by
  keycode before this point) or in 0xF700–0xF8FF, flush the word and `return pass` to
  deliver the real key. Verified with file-logging (`/tmp/viettelex-tap.log`) because
  os_log is not captured for this background input-method agent.
- **Fast-typing race → force strictly-increasing timestamps on every posted event.**
  Symptom: slow typing is correct, fast typing corrupts order — `nuwax` (→ "nữa")
  came out "nuẵ" (= as if "nuawx": the 'a' overtook the ư edit from 'w'). Root cause:
  `CGEvent.post` delivers in TIMESTAMP order, and events we create back-to-back get
  equal/near-equal `mach_absolute_time` stamps, so the window server reorders same-
  stamp events. Fix: `SyntheticKeyboard.stamp()` sets each posted event's `.timestamp`
  to `max(mach_absolute_time(), lastStamp+1)` before posting — strict monotonic order,
  FIFO restored. (Verified decisive: adding os_log to the hot path also "fixed" it by
  adding latency between posts — a Heisenbug; the timestamp fix holds with NO logging,
  ~17/17 fast `nuwax` correct.)
- **Native fast path + in-flight guard (fewer synthetic round trips).** Originally
  EVERY key was suppressed and re-emitted synthetically so that ordering versus
  synthetic edits could never break. That costs 2 posted events per plain letter.
  The current design restores native passthrough for NON-TRANSFORMING letters,
  guarded by an in-flight counter: each posted synthetic keyDown increments it, and
  it decrements when that event re-enters the tap. A letter passes natively ONLY
  when the counter is 0 (queue drained); while a burst is draining, keys still go
  through the timestamped synthetic channel. The tap callback is serial, so the
  decision cannot race; a 500ms silence self-heals a counter wedged by a dropped
  event (tap flap). Backspace/Return/Tab on an empty buffer get the same guard.
  Kill switch if reordering ever reappears on some setup:
  `defaults write com.viettelex.settings tapNativeFastPath -bool false`.

Two in-place gotchas (both fixed):
- **`insertText("", replacementRange:)` is a no-op in some apps (TextEdit).** So a
  pure-deletion backspace (delete a glyph, insert nothing) silently did nothing;
  the engine drained invisibly and only the Nth physical Backspace deleted. Fix:
  for a backspace whose action has an empty insert, return `false` and let the
  physical Backspace delete the (single) char. A tone-replacing backspace
  ("toán"→"tóa") has a non-empty insert and still goes through insertText.
- **Do NOT call `selectedRange()` after every insert.** Under fast typing it returns
  a stale caret (the app hasn't applied the previous insert yet), so the next
  replace lands at the wrong offset and corrupts the word ("được"→"đựoc"). Fix:
  track the composition locally — `anchor` (caret at the word's first key, read
  once) + `onLen` (UTF-16 length on screen) — and compute every replace range from
  those, not from a fresh selectedRange().
- **Never mix system passthrough-inserts with your own insertText.** Returning
  `false` for a non-transforming letter lets the SYSTEM insert it, on a different
  (async) channel than the `insertText` used for transforms. Under fast typing the
  system insert lags behind the insertText, they land out of order, and the word
  corrupts (still "được"→"đựoc" even with local tracking). Fix: insert EVERY
  composing letter yourself with `insertText` (consume the key, return true) so all
  edits go through one ordered channel. Likewise do backspace via insertText
  (rewrite the whole composition), reserving the physical Backspace only for
  deleting the final remaining glyph (where insertText("") would no-op).

Check the log after typing in a new app:
```bash
log show --last 5m --predicate 'subsystem == "com.viettelex.inputmethod.telex"' --style compact | grep unusable
```

## Registration only PERSISTS via the login scan

`TISRegisterInputSource` returns noErr and makes the source appear **transiently**
in `TISCreateInputSourceList`, but `cfprefsd` wipes it on reload — it does NOT
persist. The durable registration happens during the **login scan** (log out / log
in). So: install the correct, notarized, fresh-id bundle, then log out / log in
once. After that it stays.

Do NOT `killall cfprefsd` after registering — it erases the transient registration.

## App Qt nuốt shortcut khi CÓ BẤT KỲ IME nào active — 2026-08-15 (issue #54, Flameshot)

Triệu chứng: shortcut (⌘C, phím đơn) trong overlay chụp màn hình của Flameshot chết
khi VietTelex đang được chọn; layout thường (US/ABC) thì sống. Nhìn qua tưởng bug
của mình.

Cách phân xử — hai bước, mất 5 phút:
1. Debug log mức event: trong suốt lúc overlay mở, **không keyDown nào đi qua
   VietTelex** (không `handle ENTER`, không tap-emit; macOS vốn không route ⌘-chord
   vào IME, và tap pass chord nguyên vẹn). Event bị nuốt TRƯỚC KHI tới bộ gõ.
2. Phép thử quyết định: **Simple Telex của Apple cũng hỏng y hệt** → lỗi theo lớp
   "input source là IME thật" chứ không theo VietTelex.

Nguyên nhân: input context của Qt trên macOS làm rơi key-equivalent khi IME active.
Không fix được từ phía IME. Workaround cho user: per-app input source ("Automatically
switch to a document's input source" + một lần chọn ABC trong app Qt đó), hoặc
⌃Space sang ABC trước khi dùng. Trỏ user báo upstream, nhấn mạnh Apple IME cũng dính.

Tổng quát: gặp report "shortcut chết trong app X khi bật VietTelex" → hỏi ngay
"Simple Telex có dính không?" trước khi đào code. App Qt (Flameshot, OBS, VLC,
qBittorrent, Telegram bản Qt…) là ứng viên hàng đầu của lớp này.

## WebKit KHÔNG nuốt synthetic — nó bỏ event ĐẾN CÙNG LÚC (đo 2026-08-19)

Sửa lại hiểu biết từ #44/#47: comment cũ ghi "Safari/WebKit macOS 26 nuốt synthetic
burst của tap" — **sai cơ chế**. Đo trực tiếp vào page content Safari (probe tự
post + user đọc màn hình, macOS 26):

| Thí nghiệm | Kết quả |
|---|---|
| 1 ký tự qua `.cghidEventTap` | **sống** |
| 1 ký tự qua `.cgSessionEventTap` | **sống** |
| 3 ký tự, nghỉ 40ms giữa các phím | **sống** |
| burst `⌫ ⌫ + XY`, **không nghỉ** (gap 0µs) | **BỊ NUỐT TRỌN** |
| cùng burst, gap **1ms** giữa mỗi event | **sống** |
| gap 3ms / 5ms / 10ms / 20ms | **sống** |

Kết luận: điểm post KHÔNG quan trọng (HID và session như nhau); thứ bị bỏ là các
event mang timestamp/thời điểm **quá sát nhau** — WebKit coalesce hoặc rate-limit
chuỗi event không có gốc phần cứng. **Thêm ~1ms nhịp giữa mỗi event là burst sống
hoàn hảo** (⌫ ăn đúng, thứ tự đúng).

Hệ quả: lớp bug #44 (Safari), #47 (Spark), Outlook, MarkEdit đáng lẽ chữa được
bằng NHỊP, không phải bằng cách né sang in-place/marked. Xác nhận chéo: bộ gõ
event-tap khác (xkey) dùng injection delay 1000–6000µs mỗi phím — giờ biết vì sao
họ cần nó. Cái giá của nhịp: tone edit 1⌫+1 chữ = 4 event ⇒ ~4-8ms, dưới một
frame 60Hz, không cảm nhận được.

Ghi chú đo: process đo có `canPostEvents=true` nhưng `AXIsProcessTrusted()` báo
true trong khi đọc AX trả `-25204` (kAXErrorAPIDisabled) — post được mà đọc
không được. Đây lại là một biến thể "AXIsProcessTrusted nói dối", cùng họ với
mục stale-grant ở trên: dùng preflight đúng-quyền, đừng tin cờ tổng.

### …nhưng NHỊP KHÔNG DÙNG ĐƯỢC trong kiến trúc tap hiện tại (thử và REVERT 19/08)

Đã thử đúng lời giải mà bảng đo chỉ ra: gap 2ms giữa mỗi event (chỉ họ WebKit),
ngân sách 30ms/burst, bỏ carve-out để page content Safari đi tap. Kết quả
field-test NGAY ca đầu (comment TikTok, gõ nhanh): `chuur tichj gif` → **"chu
ticị gi"** — mất dấu, lộn chữ. Revert toàn bộ.

Nguyên nhân: `SyntheticKeyboard.apply` chạy **TRONG tap callback**, và callback là
SERIAL — mỗi µs nghỉ trong đó là một µs phím thật của user bị chặn ở cửa. Gõ
nhanh (~30ms/phím) mà burst giữ cửa 8-30ms thì phím kế tiếp dồn lại và engine
mất đồng bộ với màn hình. Nhịp cứu được WebKit nhưng phá chính hợp đồng
"engine ↔ màn hình" mà cả kiến trúc tap dựa vào.

Nghĩa là: **gap-0 không phải sơ suất, nó là hệ quả bắt buộc của việc post đồng bộ
trong callback.** Muốn dùng nhịp thì phải đổi kiến trúc: post burst trên một
serial queue RIÊNG (callback trả về ngay), và khi đó phải thiết kế lại toàn bộ
phần đồng bộ hiện có — `queueDrained`, in-flight counter, thứ tự với phím thật,
guard echo của Electron. Đó là việc lớn, chưa làm.

Cho tới lúc đó, đường né vẫn là đường đúng cho lớp WebKit: page content Safari →
IMKit in-place (carve-out #44), editor nào phá in-place → marked theo host
(`markedFieldURL`: Google Docs canvas, TikTok comment box). Bảng đo ở mục trên
vẫn giá trị — nó nói *vì sao* burst chết, và rằng ranh giới không phải "WebKit
chặn synthetic".

## Khoá secure input MỒ CÔI: process chết không nhả — 2026-08-18 (field case Lark)

Lark bật secure input (ô mật khẩu) rồi bị quit → `ps -p <pid>` trống nhưng
`ioreg` vẫn báo PID đó giữ `kCGSSessionSecureInputPID` — record kẹt theo PHIÊN,
`pkill` thêm gì cũng vô ích, mọi IME bên thứ ba vô hiệu. Bình thường macOS tự
dọn khi process chết; ca này là bookkeeping của WindowServer kẹt lại.

Gỡ, theo thứ tự rẻ → chắc:
1. **Khoá màn hình (⌃⌘Q) rồi mở lại** — FIELD-VERIFIED 18/08: loginwindow chiếm
   secure input lúc lock rồi nhả khi unlock, ghi đè record mồ côi. Đây là hint
   icon Vᵀ⃠ hiện khi `Holder.alive == false`.
2. Đăng xuất / đăng nhập lại — chắc chắn 100%.

Không chặn trước được: secure input là nguyên thủy bảo mật của OS, không có API
cho app thứ ba từ chối/nhả hộ (cố tình — nhả hộ được thì malware cũng làm được).
Fix gốc thuộc về app giữ khoá (lớp bug Electron: Enable không Disable khi thoát).

## ⌘R trong Xcode huỷ đăng ký input source — 2026-08-15 (học từ fork xkhanhs/vtx, 906640f)

Triệu chứng: IME **biến mất khỏi menu bar**, không crash, DebugLog trống. App vẫn
hoàn toàn lành — `spctl` → `accepted / Notarized Developer ID`, `stapler validate`
OK, process chạy đúng từ `~/Library/Input Methods/`. Nhưng `AppleEnabledInputSources`
đã bị **dựng lại từ mặc định**: IME rớt xuống chỉ còn trong `AppleInputSourceHistory`,
và macOS tự nhét `com.apple.inputmethod.VietnameseSimpleTelex` vào thế chỗ.

Dấu hiệu phân biệt "cả list bị reset" với "IME bị disable riêng": **layout non-Apple
của user (nếu có) cũng mất cùng** khỏi enabled list.

Thủ phạm: ⌘B/⌘R trong Xcode GUI build bundle vào DerivedData mặc định
(`~/Library/Developer/Xcode/DerivedData/…/Build/Products/{Debug,Release}`), và ⌘R
còn *chạy* bản đó. Bản chạy mang đúng `InputMethodConnectionName` như bản đã cài
(fork đo được: `pgrep -lf` ra hai process, `mdfind -name` ra ba bundle) — hai process
giành một connection name, macOS xử lý bằng cách dựng lại toàn bộ enabled list. Khớp
với "Registration only PERSISTS via the login scan" ở trên: đăng ký vốn mong manh,
một bundle trùng connection name đủ để thổi bay.

Luật: **build/cài bằng `Scripts/dev-install.sh`, không bao giờ ⌘R app chính trong
Xcode.** Mở Xcode để đọc/sửa code hay chạy test (⌘U) qua CLI runner thì theo dõi
được — xem thêm mục XCTest host cướp IMK trong dev-loop notes. Kiểm tra sức khoẻ:

```bash
pgrep -lf VietTelex          # đúng 1 dòng, path ~/Library/Input Methods/
mdfind -name "VietTelex.app" # không được ra bundle trong DerivedData
```

Khôi phục sau khi đã dọn bundle thừa: sửa `AppleEnabledInputSources` bằng
`defaults export` → edit → `defaults import com.apple.HIToolbox`, rồi
**logout/login** (đọc lại ngay sau import thì thấy đúng, nhưng menu bar chỉ cập
nhật sau login scan). Đừng `killall cfprefsd`. Nhớ thêm lại layout non-Apple đã
mất cùng — nó rơi im lặng.

## Debug commands

```bash
# Is it registered right now?
swift -e 'import Carbon; let l=TISCreateInputSourceList(nil,true)!.takeRetainedValue() as! [TISInputSource]; for s in l { if let p=TISGetInputSourceProperty(s,kTISPropertyInputSourceID){ let id=Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String; if id.contains("viettelex"){print(id)} } }'

spctl -a -t exec ~/Library/Input\ Methods/VietTelex.app          # must be "accepted"
xcrun stapler validate ~/Library/Input\ Methods/VietTelex.app    # must be "worked"
otool -ov ~/Library/Input\ Methods/VietTelex.app/Contents/MacOS/VietTelex | grep TelexInputController  # must be _TtC9VietTelex...
```

## Dev loop (minimize logouts)

- **Engine only** (`TelexCore`): `swift test` — no install, no logout.
- **IMK / controller / Info.plist**: `Scripts/notarize-install.sh` (~2 min for
  notarization) then log out / log in ONCE. As long as the bundle id does not
  change and each install is notarized, the id stays healthy and one logout after
  the first correct install is enough; subsequent notarized swaps of the same id
  refresh in place after re-selecting the input source.

## InputMethodConnectionName MUST be "<bundle-id>_Connection" (sandboxed clients)

Shipped for months as `VietTelex_Connection` — worked everywhere we tested, then
field reports: WhatsApp (MAS, sandboxed) typed NOTHING with VietTelex selected.
The input-source menu even showed no VietTelex section in those apps, and
activateServer never fired: a sandboxed client's NSConnection lookup of the IME
connection fails unless the name follows the modern convention
`$(PRODUCT_BUNDLE_IDENTIFIER)_Connection`. Non-sandboxed apps (Terminal, Chrome,
Electron) connect fine with any name — which is exactly why this hid for so long:
sandboxed apps were "covered" by the tap (needs Accessibility) and the IMKit path
never got exercised there until the tap was off.

Changing the name requires a logout/login (it is input-source registration
metadata). Diagnosis trail: missing menu section per-app → zero activateServer in
DebugLog → sandbox entitlement check → naming convention (vChewing dev guidelines).
