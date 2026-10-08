# VietTelex for Windows

Spec: [docs/WINDOWS-SPEC.md](docs/WINDOWS-SPEC.md). Engine C ABI: [engine/API.md](engine/API.md).

| Dir | What |
|---|---|
| `engine/` | C++ port of TelexCore (static lib `viettelex_engine`), plus `viettelex_text`: text tools, NFC/NFD + Unicode case mapping, Thêm dấu with the vnlexicon / enlexicon / vnlm v3 readers (VietTelex.exe only, never the TIP) |
| `ime/core/` | Portable typing core: key mapping, `TypingSession` (composition / in-place), settings + snapshot, shortcuts, per-app policy, hotkey. Unit-tested on any OS. |
| `ime/src/` | `VietTelexTIP.dll`: the TSF text service (COM, `ITfTextInputProcessorEx`, key sink, composition with a no-underline display attribute, in-place mode, registration; no language-bar item since 1.0.8) |
| `app/` | `VietTelex.exe`: tray, Settings window, updater, per-app hook fallback, per-user setup |
| `installer/` | WiX MSI (x64, ARM64 with ARM64X forwarder), Store checklist `STORE.md`, winget templates, Azure Trusted Signing script, `build.ps1`, optional MSIX template |

## Build

```
# any OS: core + tests
cmake -S windows -B build && cmake --build build && ctest --test-dir build
# RELEASE (macOS): cross-compile x86/x64/ARM64 in Docker, sign, build MSIs, verify
windows/scripts/release.sh --version 1.0.0          # -> windows/dist/release/
# Windows dev build (MSVC), one per architecture
cmake -S windows -B build-x64 -A x64 && cmake --build build-x64 --config Release
```

`release.sh` does the following, and publishes nothing:

1. **Build.** It builds with llvm-mingw inside `mstorsjo/llvm-mingw` (`scripts/cross-build.sh`) and installs nothing on the host.
2. **Sign binaries.** It signs every `.dll` and `.exe` with `jsign --storetype TRUSTEDSIGNING`, timestamped (RFC 3161, `timestamp.acs.microsoft.com`).
3. **Build MSIs.** It builds them with `wixl`. The ARM64 MSI is an x64-shaped database with the Template `Arm64;1033`.
4. **Sign MSIs and verify.** It checks every signature with `osslsigncode` against `installer/microsoft-identity-verification-root-2020.pem`, then writes `SHA256SUMS`.

The signing target comes from `VTX_SIGN_ENDPOINT`, `VTX_SIGN_ACCOUNT` and `VTX_SIGN_PROFILE`, set in the environment or in the gitignored `installer/signing.local.env`. Signed releases also need `VTX_EXPECTED_PUBLISHER`: the certificate's subject CN, compiled into `VietTelex.exe` as the only publisher the self-updater accepts. `release.sh` checks it against the actual signatures. A build without it (dev builds, `build.ps1` without `-DVTX_EXPECTED_PUBLISHER=...`) refuses every downloaded update and only offers the release page. The access token comes from `az login`, or in CI from `AZURE_TENANT_ID`, `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET`. No secret is stored in the repo.

### MSI registration (no regsvr32)

The MSI writes the COM and TSF registration as Registry-table rows:

- `CLSID\{…}\InprocServer32` with `ThreadingModel=Apartment`,
- `CTF\TIP\{CLSID}` with `Enable`,
- the vi-VN `LanguageProfile` (Description, IconFile, IconIndex, Enable, `SubstituteLayout=0x04090409`),
- both `Category\Category` and `Category\Item` keys for every category.

These go into the 64-bit view (`TipNative`) and the 32-bit view (`TipX86`).

The rows are generated from `ime/core/registration.h`, the same data `DllRegisterServer` uses. The DLL refuses to register if its SDK GUIDs drift from that data. `vtx_regtable check` diffs the built MSI against it, and CTest (`vtx_regtable_roundtrip`) covers the checker.

There is no AppContainer ACL, because wixl has no `Permission` element. It isn't needed: the default `Program Files` ACL already grants read and execute to ALL (RESTRICTED) APPLICATION PACKAGES.

## Upgrading

To upgrade, install the new MSI over the old one. There are no repair packages. A normal major upgrade does this:

1. **QuitApp** (immediate, before InstallValidate) runs `VietTelexSetupHelper.exe --quit-app` from the MSI's Binary table. It sends `WM_CLOSE` to every VietTelex.exe main window, waits 3 s, then terminates only `VietTelex.exe` images. The app also answers `WM_QUERYENDSESSION`/`WM_ENDSESSION` by exiting.
2. **ReleaseTip** (deferred as SYSTEM, before RemoveFiles/InstallFiles) moves every in-use `VietTelexTIP*.dll` of this version or older (`--max-version`) aside to `*.old`, scheduled for silent deletion at the next boot. It is skipped when this package is the old version being removed (`NOT UPGRADINGPRODUCTCODE`).
3. The new files are installed. TIP DLL names carry the version (`VietTelexTIP_1_0_7.dll`) and get a per-version component GUID, so nothing overwrites a DLL that running apps have loaded, and the registry points at the new file immediately.
   - The old version is removed afterwards: RemoveExistingProducts sits between InstallExecute and InstallFinalize, one of the positions ICE63 allows. 1.0.6 put it elsewhere and failed with error 2613.
   - The COM/TSF registration lives in registry-only components that keep the ≤1.0.5 component GUIDs, so removing the old version keeps the keys the new one wrote.
   - `REBOOT=ReallySuppress` and Restart Manager disabled: no prompts.
4. **LaunchApp** starts the new app, which opens Settings.
5. **Single-instance handoff:** a newer exe that finds an older instance running (compared by the version in the hidden window's title) closes it and takes over.
6. **In-app update:** it starts `msiexec` plus a detached watcher (a copy of the exe in `%TEMP%`), then exits. If the install is cancelled, the watcher restarts the installed app.

## Per-host text policy (1.1.2)

In-place is the default and needs a document that really contains the text before the caret. At each word start the TIP classifies the focused context with `classifyContext()` in `ime/core/app_policy.h`, following Mozc's rule in `tip_transitory_extension.cc`:

| Context | What happens |
|---|---|
| No context, `GUID_COMPARTMENT_KEYBOARD_DISABLED` or `EMPTYCONTEXT` set (games, canvases) | Keys are not eaten. |
| Read-only, or an ANSI focus window (`!IsWindowUnicode`: VBA editor, ANSI apps) | Keys pass through literally. |
| `TF_TMAE_CONSOLE` (conhost, OpenConsole, Windows Terminal) | Composition only; never read back. |
| Not `TF_SS_TRANSITORY` (Word, WPF, Firefox) | Full context: in-place. |
| Transitory with a transitory-extension parent (classic Edit/RichEdit) | Read and edit through the parent context if that parent is not transitory. If the parent refuses an edit session, composition for that focus. |
| Transitory and CUAS-emulated (compartment `{A94C5FD2-…}` bit 1: IMM32 apps such as Qt/Telegram, Java/JetBrains, AutoCAD, Adobe) | Composition from the first key. |
| Transitory otherwise (Chromium: Chrome, Edge, Brave, Electron, WebView2 always report transitory) | Full context: in-place. 1.1.1 wrongly composed here. |

Also:
- **Terminal rules:** built-in composition rules for terminals (conhost, openconsole, windowsterminal, mintty, alacritty, wezterm, ConEmu, PuTTY, KiTTY, Tabby) and off rules for VM and remote viewers.
- **Unrecognised hosts:** if a field shows none of the typed text, composition from the second key.
- **Emptied composition:** a composition the app empties (Excel autocomplete) ends the word.
- **WebView2:** `msedgewebview2.exe` takes its per-app rules and memory from the root-owner exe (new Teams, new Outlook).
- **Hook mode:** it warns once, non-modally, when the foreground app is elevated. UIPI blocks SendInput there.

## Direct mode and the underline (1.1.3)

The goal is no underline anywhere possible.

- **Direct hosts:** where TSF cannot edit in place, VietTelex.exe's low-level hook types UniKey/OpenKey-style. It eats the key and sends one `SendInput` batch of N backspaces plus `KEYEVENTF_UNICODE` text, so a user key can never interleave, and the engine tracks the word blind. The hosts:
  - consoles (conhost, OpenConsole, Windows Terminal, mintty, Alacritty, WezTerm, ConEmu, PuTTY, KiTTY, Tabby) through built-in `direct` rules;
  - fields the TIP classifies at run time: CUAS/IMM apps (Qt/Telegram, Java/JetBrains, Adobe, AutoCAD) and fields that show none of the typed text (xterm.js in the VS Code terminal). The TIP posts `AppCommand::DirectMode` for them.
- **Injected keys:** they carry `dwExtraInfo = kInjectedMagic` and are never processed again, by the hook or by the TIP (`GetMessageExtraInfo`).
- **Hook thread:** the hook runs on its own high-priority thread. A raw-input watchdog reinstalls it when Windows removes it (`LowLevelHooksTimeout`).
- **When composition remains:** only if VietTelex.exe is not running, or an app is set to composition by hand. It always uses the `TF_LS_NONE` attribute (no line, no colours). Hosts that may still draw their own marking: legacy conhost's conversion area and some IMM-based Java/Qt builds. Chromium honours `TF_LS_NONE` when the attribute provider is registered, which is checked in tests.
- **Not yet:** the U+202F autocomplete break that OpenKey uses in browsers. Browsers use in-place, which handles forward selections.

## Direct fallback per field (1.1.4)

Direct stays on only where it provably works; otherwise that one field goes back to composition (`TF_LS_NONE`, done by the TIP in-process).

- **Integrity (UIPI):** if the target process runs at a higher integrity than VietTelex.exe, or its token cannot be read, the hook does not type for it and the TIP composes. This replaces the old balloon-only warning.
- **Echo check:** after each Direct edit a background thread (not on the key path, ~80 ms later, latest edit only) reads what the host really shows before the caret. For conhost it uses `AttachConsole` + `ReadConsoleOutputCharacter`; for Windows Terminal and other hosts it uses UIA `TextPattern`, else `ValuePattern` (Qt/Java/Adobe). Two mismatches in the same field (focus hwnd + control id) mark it `VietTelex.NoDirect` for the rest of the focus, and the event is logged (debug logging). Hosts that expose nothing stay on Direct.
- **Send failures:** if `SendInput` sends fewer events than requested, that field switches to composition at once.
- **Races:** if the foreground changes between the key and the injection, or the secure desktop is up, the edit is dropped and the word resets.
- The rules are pure functions in `app/core/direct_policy.*` with unit tests.

## Consoles, handover, per-app Việt/Anh, debug log (1.1.5)

- **Console identity:** for a console window (`ConsoleWindowClass`), `GetWindowThreadProcessId` reports the client (cmd.exe) and that client's thread, not conhost. The hook and the tray now key such windows as `conhost.exe`, the name the TIP and the built-in Direct rule use. In 1.1.4 the hook looked up `cmd.exe`, found no rule and did nothing, while the TIP stayed out on its own `conhost.exe` rule, so every word came out raw.
- **Handover ack:** the TIP stays out of a field only while the hook's `VietTelex.DirectOn` property is on the window. Until then it composes (no underline). When the hook takes over mid-focus, it waits for a word boundary (`HookArming`), so the TIP and the hook never type the same word.
- **Việt/Anh for the hook and tray:** the TIP sets `VietTelex.Lang` (1 = Việt, 2 = Anh) on its focus window and removes it on deactivation. That property is the only source for consoles; other windows fall back to the keyboard layout plus the per-app memory. Injected backspaces now carry a scan code.
- **Per-app memory (in-TIP switch: Ctrl+Shift, Alt+Z):** kept in `HKCU\Software\VietTelex\AppLanguage\<exe>` and restored whenever a window gets focus. AppContainer and low-IL hosts (Start search, UWP) can't use HKCU: the TIP asks the app to store the value (`AppCommand::SetAppLanguage`), and the app mirrors the map to `%LOCALAPPDATA%\VietTelex\applang.txt`, which those hosts can read. Every restore decision is logged.
- **Win+Space / input source (VietTelex ↔ ENG):** this is Windows' own per-app setting ("Let me use a different input method for each app window", `SPI_GETTHREADLOCALINPUTSETTINGS`). Settings → Kiểu gõ shows its state and has a button that turns it on (`SPI_SETTHREADLOCALINPUTSETTINGS`, saved and broadcast). If turning it on doesn't work, the button opens `ms-settings:typing` instead.
- **Debug log:** when "Ghi nhật ký gỡ lỗi" is on, the TIP (in every host), the app, the hook and the verifier append to `%LOCALAPPDATA%\VietTelex\debug.log`. The file rotates to `debug.1.log` at about 1 MB. Each line carries a timestamp, pid, exe and component. AppContainer hosts fall back to their own temp folder (`VietTelex-debug.log`). The log records decisions (rule, window class, handover, SendInput counts, echo results, fallbacks) and never typed text, only key classes and lengths.

## Text tools (Công cụ văn bản)

The macOS text tools (`App/Sources/TextActions.swift`) for the selection in any app: Thêm dấu cho vùng chọn, HOA, thường, Hoa Đầu Từ, Hoa đầu câu, Xoá dấu.

- **Entry points:** the tray menu's **Công cụ văn bản** submenu (setting `textToolsInMenu`, default on; the tray icon itself is off by default) and an optional global **Thêm dấu hotkey** (`addTonesHotkey`: `off` (default), `ctrl-alt-t`, `ctrl-shift-t`, `win-alt-t`; `RegisterHotKey`, so it also works when another keyboard is active). Both are on the Spelling tab. There is no language-bar menu: the TIP has had no language-bar item since 1.0.8.
- **Transforms:** `engine/src/text_tools.cpp` and `engine/src/add_tones.cpp`, a port of `TextTools.swift`, `AddTones.swift` and the `SyllableLM.swift` v3 reader. They produce the same results as iOS and Android on the shared fixtures `iOS/KeyboardTests/Fixtures/{text-tools,add-tones,vnlm-parity}.txt`, tested by CTest `text_tools`. The Unicode tables (NFC/NFD, full case mapping with Final_Sigma, General Category) are generated by `engine/tools/gen_unicode.py` and cross-checked against Python's `unicodedata` with `engine/tests/unicode-sample.txt`.
- **Data:** `vnlexicon.bin`, `enlexicon.bin` and `vnlm.bin` from `iOS/Keyboard/Resources` (the same files as iOS, Android and macOS) are embedded as RCDATA in `VietTelex.exe`. The readers work in place on the image-mapped resource, which is demand-paged and never copied, and they load on first use. If the LM is missing or doesn't match the lexicon, Thêm dấu runs on the lexicon alone. The TIP never loads any of it.
- **Read and replace, in this order:**
  1. **Through TSF.** VietTelex.exe posts a request to the TIP's message-only window for the focused thread (`ime/core/text_tool_ipc.h`). The TIP reads the selection in an edit session, handling classic Edit/RichEdit through the transitory-extension parent like typing does. It sends the text to the app (`WM_COPYDATA`); the app transforms it and sends the result back. The TIP replaces exactly the range it read, and only if that range is still the selection with the same text, then puts the caret after it.
     - Password/PIN input scopes are refused.
     - In a readable store, an empty selection means "nothing selected": it beeps rather than send Ctrl+C, which in VS Code copies the whole line.
  2. **Ctrl+C / Ctrl+V fallback.** This runs when there is no TSF selection: consoles, CUAS/IMM32 apps, another keyboard active, or no answer within 600 ms. It works like macOS `PasteboardBridge`:
     1. Wait for the hotkey's modifiers to be released.
     2. Snapshot every clipboard format (HGLOBAL formats byte for byte, EMF copied; GDI/private handles skipped, and CF_BITMAP is re-synthesised from CF_DIB).
     3. Send Ctrl+C (marked `kInjectedMagic`) and wait for the sequence number to change. Then transform the text and put it on the clipboard, with the Windows opt-out formats for clipboard history, cloud clipboard and monitors.
     4. Send Ctrl+V. After 600 ms, restore the snapshot if the clipboard is still ours.
  - The fallback never runs in terminals or consoles (Ctrl+C would interrupt), VM/remote viewers, `ES_PASSWORD` edits or elevated apps (UIPI).
- **The TIP window** is titled `VietTelexTip:<thread id>` and found by that title. Its class name includes the version and module address, so a class that an unloaded TIP left registered can never supply a stale window procedure. `DllCanUnloadNow` also unregisters it.
- **One request at a time.** A failure beeps. Decisions go to the debug log (lengths only, never text).
- **Hotkey and Ctrl+Shift:** RegisterHotKey eats the T of Ctrl+Shift+T, so the TIP disarms its Ctrl+Shift switch chord when a request arrives.

## Caret hints (Gợi ý cạnh con trỏ, macOS 1.8.2)

Five suggestions shown in a small window at the caret. Each has its own switch in Settings → Chính tả → Công cụ văn bản (collapsible, collapsed by default). None replaces anything by itself: **Tab** applies (Enter too for maths), **Esc** hides it (and, for typo fixes, stops suggesting that word this session; for tones, that sentence), any other key hides it and goes through.

| Setting | Default | Example |
|---|---|---|
| `mathResults` | on | `12*3=`, `200+10%=`, `125 x (4 + 5.5) =` → `= 36` (inserts `36`) |
| `numberChips` | on | `50k␣`, `1tr2␣`, `2 tỷ␣` → `1.200.000 ₫` (money formats only) |
| `typoHints` | on | `tpoi␣` → `tôi`: one neighbour key on a physical keyboard or two keys swapped, only for words that are not Vietnamese, English or chat words |
| `toneHints` | off | `toi di hoc.` or a 0.9 s pause after a space → `tôi đi học` (≥ 3 unaccented syllables) |
| `dateHints` | on | `hôm nay␣`/`ngày mai␣`/`hôm qua␣` → `28/09/2026`, `bây giờ␣` → `21:35`; `today`/`tomorrow`/`yesterday`/`now` only after an English word |

- **Logic:** pure and shared-fixture tested. `ime/core/caret_hints.*` holds the TIP side: maths and number chips (`math-results.txt`, `number-chips.txt`), dates, the tone-run tracker and the typo gate. `app/core/typo_fix.*` holds the typo fixer, which uses the lexicon. Its precision eval (`typo_eval_precision_floor`) reproduces the macOS numbers exactly: P 98.1 %, R 20.7 %.
- **Cost:** with all five off, a key costs one flag read. With any on, the TIP keeps the chunk being typed (raw keys since the last space). Only a trigger (`=`, or a space or `. ! ?` worth checking) arms a 40 ms timer, so the app has inserted the key first. After that come one async read session and the caret rectangle (`ITfContextView::GetTextExt`, then the character before the caret, then `GetGUIThreadInfo`).
- **Out of process:** typo fixes and tones need the language data, which stays in VietTelex.exe like the text tools (`ime/core/caret_hint_ipc.h`, `WM_COPYDATA` both ways). The TIP only shows an answer if no key was typed since, and it re-reads the screen before showing and again before replacing.
- **Window:** `ime/src/hint_popup.*` — a top-most `WS_EX_NOACTIVATE | WS_EX_TRANSPARENT` popup that never takes focus or clicks. It is light or dark following `AppsUseLightTheme`, auto-hides after 8 s, and hides when the caret moves.
- **Not here:** password/PIN input scopes, `ES_PASSWORD` edits, secure desktop, consoles and fields typed by the hook (Direct mode), composition-only contexts, and English mode (the TIP is not typing then).

## Onboarding (first run)

Decisions are pure functions in `app/core/onboarding.*` with unit tests; the Win32 side is `main.cpp` (`--setup-user`), `welcome.cpp` and `conflicts.cpp`.

- **Per-user activation through Active Setup.** The MSI writes `HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{D1246D27-55D1-45DC-96F6-60BF26027142}` with `StubPath = "<exe>" --setup-user --active-setup`, `Version = 1,0` and `IsInstalled = 1`. At every user's next logon, Windows runs the stub once for that user, so a Store/Intune/`msiexec /qn` install as SYSTEM reaches everyone.
  - **Why Active Setup:** HKLM RunOnce only reaches the first user to log on. HKLM Run runs at every logon, forever. A logon scheduled task needs the Task Scheduler API, which wixl cannot author. Writing other users' HKCU from SYSTEM misses users created later.
  - **Fixed version:** the stub runs once per user, not once per release, so an upgrade never re-adds a keyboard the user removed. Uninstall (`--cleanup-user`) deletes the user's Active Setup entry, so a reinstall sets them up again.
  - **No UI in the stub:** it runs before the desktop exists and only sets `welcomePending`. The autostart (`--background`) then shows the welcome window.
  - **Idempotent (`planUserSetup`):**

    | Run | What happens |
    |---|---|
    | As SYSTEM | Nothing. |
    | The installer, as a user | Always makes sure of the keyboard and autostart. |
    | Active Setup or app start | Acts only for a user who was never set up. |

  - **Limit:** a user who is already signed in when the Store installs gets the keyboard when they open VietTelex or sign in again.
- **Welcome window (`decideWelcome`):** shown once per user. It offers Telex/VNI, the switch key, the tray icon, other input methods and "Chuyển gõ tắt từ UniKey / OpenKey…".
  - `showTrayIcon` stays off by default. The box is ticked in advance only when UniKey, EVKey or OpenKey is running, because those users are used to a tray indicator.
  - Users upgrading from a version without onboarding never see it.
- **Other Vietnamese input methods:** detected only when the welcome window or the Kiểu gõ page is shown, and never in the background. Two kinds are checked:
  - running UniKey (`UniKeyNT.exe`), EVKey, OpenKey, VKey and GoTiengViet, by process image name;
  - Microsoft's Vietnamese keyboards in the user's list: any enabled vi-VN profile that is not VietTelex (Telex, Number-key, or the legacy layout), found with `ITfInputProcessorProfileMgr::EnumProfiles`.

  The warning shows on the Kiểu gõ page and in the welcome window, and opens a task dialog with these actions:
  - open the other app's folder;
  - show how to quit it (from its tray icon) and how to keep it from starting with Windows;
  - remove a Microsoft keyboard from the list with `InstallLayoutOrTip(ILOT_UNINSTALL)`, falling back to `ms-settings:regionlanguage`.

  VietTelex never quits or uninstalls other software.
- **"Chuyển từ UniKey" (`app/core/macro_import.*`):** Nhập… reads the formats below. The fixtures in `app/tests/fixtures/macros` are byte-exact.

  | Format | Source | How it is read |
  |---|---|---|
  | UniKey | `ukengine/mactab.cpp` | Header `;DO NOT DELETE THIS LINE*** version=1 ***` with a UTF-8 BOM (Windows build), then `key:text` split at the first colon, untrimmed. |
  | OpenKey | `Macro.cpp` | Header `;Compatible OpenKey Macro Data file for UniKey*** version=1 ***`, then the first-colon split. A key starting with `:` takes the next field. |
  | Generic | — | VietTelex/macOS JSON and YAML, `key:value` and `key<TAB>value` text. |

  - **Encodings:** UTF-8 with or without BOM, UTF-16LE with or without BOM, and UTF-16BE with BOM. Anything else is refused, never imported as mojibake.
  - **Old UniKey files** (VIQR, without the `version=1` line) are imported unconverted, with a warning.
  - **EVKey's** export format could not be checked against public sources. Its files go through the generic path.
  - **UniKey's switch-key setting** is not imported: its registry location could not be checked against public sources.

## Games, fullscreen, V/E indicator

Decisions are pure functions in `app/core/game_logic.*`, the TIP side is `ime/core/game_ipc.h`, and the Win32 side is `app/src/game_mode.cpp` and `switch_toast.cpp`.

- **Tự tắt tiếng Việt khi chơi game toàn màn hình** (`autoOffFullscreen`, default on). VietTelex.exe watches foreground changes with a WinEvent hook, installed only while the setting is on. It asks `SHQueryUserNotificationState`:

  | State | Result |
  |---|---|
  | `QUNS_RUNNING_D3D_FULL_SCREEN` | Keys pass through. |
  | `QUNS_PRESENTATION_MODE`, with a captionless foreground that covers its monitor | Keys pass through. |
  | `QUNS_BUSY` (Chrome F11, YouTube fullscreen, video players) | Typing as usual. |

  - **Late fullscreen:** a game often turns exclusive-fullscreen after it comes to the front. So a new foreground window that covers its monitor gets at most three one-shot re-checks (0.3, 1.5 and 4 s). Nothing polls, and nothing runs per key.
  - **Telling the TIP:** VietTelex.exe posts `kTipSuspendMsg` to the TIP window of the game's threads and sets `VietTelex.Suspend` on its top-level window. A TIP activated later reads that property on focus.
  - **While suspended:** the TIP eats nothing, including Ctrl+Shift and Alt+Z, which games bind. A word in progress is committed as typed, and the hook types nothing. Việt/Anh is never changed, so leaving the game restores everything.
  - **Borderless-window games are not detected.** Use Chế độ game, or "Luôn tiếng Anh" for the game on the Ứng dụng page.
- **Chế độ game** (`gameMode`, Kiểu gõ page, and an optional hotkey `gameModeHotkey`):
  - **What it does:** every key passes through, in every app. It reaches every TIP through the snapshot, and the foreground TIP at once.
  - **Never stuck on:** it is cleared whenever VietTelex.exe starts, and a TIP ignores it while the app is not running.
  - **Hotkey:** the default is off, because a global hotkey takes its chord away from every app, and Ctrl+Alt is AltGr on some layouts. The choices are `ctrl-alt-g` and `ctrl-shift-alt-g`, never Win+G or Win+Alt+G (Xbox Game Bar).
- **Floating V/E indicator** (`switchIndicator`: `auto` by default, `on`, `off`; `auto` means "while the tray icon is hidden").
  - **Trigger:** the TIP posts `AppCommand::UserSwitched` only for a Ctrl+Shift or Alt+Z switch, not for a focus change.
  - **Window:** a click-through, never-activated popup shows V or E for 1 s, below the caret (`GetGUIThreadInfo`) or in the work area's bottom-right corner.
  - **Never shown** over a D3D or presentation fullscreen, or while keys pass through.
  - **Cost:** nothing on the typing path.

## Terminals and AI CLIs (Direct mode Backspace)

- **The bug class:** with other IMEs, a CLI that reads the pty (Claude Code, Gemini CLI, other Node/Ink apps) receives BS `0x08` instead of DEL `0x7F` for Backspace. It does not delete, and the retyped word doubles.
- **What VietTelex sends** (`directEditEvents`, unit-tested): each backspace is `VK_BACK` as a virtual key with scan code `0x0E`, exactly like the physical key. Windows Terminal and conhost's VT input translate it to DEL, and legacy console readers get the same `KEY_EVENT` record. A control character is never sent as `KEYEVENTF_UNICODE`. The text goes as Unicode, and there are no modifier events.
- **New guard (`injectionModifiersSafe`):** a batch is dropped (the word resets) if Ctrl, Alt or Win is down at injection. Otherwise `VK_BACK` would become Ctrl+Backspace (`0x08`, or delete-word in GUI apps) or Alt+Backspace (`ESC DEL`, delete-word in readline).
- **Residual risk, not fixable from the IME:** a CLI that treats one pty read as one key would get "DEL DEL text" together. Windows Terminal stays Direct by default, which means no underline and shell autocomplete intact. For such a CLI, set `windowsterminal.exe` (and `conhost.exe`) to Composition on the Ứng dụng page; then only committed text reaches the app. The override beating the built-in rule is unit-tested.

## Icons

All icons come from the macOS artwork, regenerated by `installer/icons/make_icons.py` (macOS only; it uses `sips`, nothing gets installed).

- **App icon:** `ime/res/viettelex.ico` holds 16–256 px. Sizes that exist as AppIcon PNGs are copied byte for byte; the rest are `sips` downscales. It is used for the exe, the MSI's Add/Remove entry, the Start menu shortcut and the Settings window.
- **Keyboard icon (settings `menuIcon`):** five choices — `vt` (default), `star`, `flag`, `logo`, `vi`. The retired `letter` value migrates to `vt`. The mapping lives in `ime/res/icon_ids.h` and is unit-tested.
  - **Tray icon** (optional, the only Việt/Anh indicator since 1.0.8, when the TIP's separate language-bar item was dropped because it doubled the taskbar icon). It follows the foreground app: the TIP posts `AppCommand::StateChanged`, and the app watches foreground changes. It uses theme glyphs `glyph_<vt|star|flag>_<v|e>_<dark|light>.ico`. `dark` is white for the dark taskbar and `light` is dark for the light taskbar, chosen from `SystemUsesLightTheme`; `e` is the English state at 40% opacity. `logo` uses the colour app icon, dimmed in English. `vi` draws "VI"/"EN" text at runtime.
  - **Static profile icon** (Win+Space list): `profile_<choice>.ico`, a white glyph with a dark outline so it reads on both flyout themes. The default is monochrome Vᴛ at IconIndex 13, which a unit test checks against the resource order. Changing the choice in Settings runs `VietTelex.exe --set-profile-icon <choice>` elevated, with one UAC prompt, to update the HKLM IconIndex.

  Why an elevated helper and not a user-writable icon file: the profile icon is loaded into every process, including elevated ones and the secure desktop, and no user-writable file should be parsed there. Installing a new version resets the icon to Vᴛ.
- **Tray icon:** off by default (`showTrayIcon`), because the taskbar indicator already shows the state. Start menu → VietTelex opens Settings.

## How typing works

- **Composition mode (default):** the word being typed is a TSF composition whose display attribute is `TF_LS_NONE`, so it is not underlined. A word boundary commits `vtx_commit_text`, and the boundary key then goes on to the app.
- **In-place mode (per app):** engine REPLACE actions become "delete N chars before the caret, insert text". Each delete is checked against the text actually on screen; if they differ, the session resets and the key is typed as-is.
- Re-edit (`reEditWord`) follows macOS: only diacritic-only keys (`s f r x j z w`, or VNI digits) re-open the word before the caret. ⌫ right after a boundary re-opens the last word.
- Literal fields: password, PIN, number, telephone, e-mail. Two exceptions are deliberate:
  - `IS_URL` is not literal, because the Chrome/Edge address bar is where people search in Vietnamese.
  - `IS_PRIVATE` is not literal, because it only means "do not learn" (InPrivate windows).
- The TIP registers with the US layout as substitute. Keys it passes through therefore never go through the stock Vietnamese layout, which would turn `1` into `ă`.
- **Switch hotkey (`switchHotkey`):**
  - `ctrl-shift` (default): a clean press-and-release, detected inside the TIP.
  - `win-space`: the system switcher.
  - `alt-z`: a TSF preserved key.
  - `off`.
- Vietnamese/English is remembered per exe under `HKCU\Software\VietTelex\AppLanguage`. It is kept in memory only inside AppContainers and on the secure desktop.

## Settings

- `VietTelex.exe` writes `HKCU\Software\VietTelex`: one value per key, with `shortcuts` and `appModes` stored as REG_BINARY JSON.
- It also writes a binary snapshot to `%LOCALAPPDATA%\VietTelex\settings.bin`. The folder ACL grants read access to ALL (RESTRICTED) APPLICATION PACKAGES.
- The TIP only parses the snapshot, so there is one parser for normal and AppContainer processes. It re-checks the file's timestamp on focus change and after a menu command. There is no timer and no polling.
- Deviation from spec §9: the TIP does not read the registry directly.
- **UI language** (`uiLanguage`, the "Ngôn ngữ / Language" picker, Typing tab): `vi` by default whatever the Windows display language, `en` switches the Settings window and the tray menu immediately. All strings, including the text tools, live in `app/src/strings.cpp` in both languages, and a `static_assert` keeps the table complete.
- `addTonesHotkey`, `gameModeHotkey` and `switchIndicator` are registry-only: they are not in the TIP snapshot. `autoOffFullscreen` and `gameMode` are appended snapshot bits. `textToolsInMenu` and the five caret-hint switches are appended snapshot bits (an older snapshot leaves them at their defaults).

## ARM64 (supported from v1)

Windows on ARM runs native ARM64 apps and emulated x64 apps side by side, and both read the same 64-bit `InprocServer32` path. The ARM64 MSI therefore installs three DLLs:

| File | What |
|---|---|
| `VietTelexTIP.dll` | ARM64X **pure forwarder**. This is the registered COM server. |
| `VietTelexTIP_arm64.dll` | The real TIP for native ARM64 apps. |
| `VietTelexTIP_x64.dll` | The real TIP for emulated x64 apps. It is the x64 build, renamed. |

The forwarder follows Microsoft's "Arm64X pure forwarder DLL" recipe. `ime/src/arm64x/empty.cpp` is compiled once for ARM64 and once for ARM64EC. The two objects are linked with `/MACHINE:ARM64X /DEFARM64NATIVE:arm64_exports.def /DEF:x64_exports.def` into one DLL, and the linker needs `_load_config_used`, or the loader cannot see the EC view.

- **Release (macOS):** `scripts/cross-build.sh` does this with llvm-mingw's `lld-link`. It takes the load config from the ARM64X-aware mingw-w64 CRT, then checks that the result is COFF-ARM64X, carries CHPE metadata, and forwards native exports to `_arm64` and EC exports to `_x64`.
- **Windows dev builds:** MSVC ARM64 builds do the same through CMake (`ime/CMakeLists.txt`).
- **Registration:** the MSI registers the forwarder as `InprocServer32`. The icon comes from `VietTelexTIP_arm64.dll`, which is exactly what `DllRegisterServer` in the arm64 half writes (`ime/core/com_path.h`).
- 32-bit x86 apps use the separately registered x86 DLL, as on x64 machines.

## Microsoft Store

VietTelex is submitted as a Partner Center **"MSI or EXE app"** that points at the signed MSI. Requirements:

- a signed MSI (Azure Trusted Signing),
- a versioned, HTTPS, immutable download URL per architecture (a GitHub Releases asset under `win-v<VERSION>`; never replaced),
- silent install `msiexec /i <msi> /qn /norestart` and uninstall `msiexec /x {ProductCode} /qn`.

Checklist and listing text: [installer/STORE.md](installer/STORE.md). An MSIX package cannot register a system-wide TSF text service, so `installer/msix/AppxManifest.xml` is an **optional, companion-only** template and is not part of the submission.

## Needs a real Windows machine

- Everything in the TSF layer: activation, composition behaviour, OnEndEdit caret tracking, input scopes, the taskbar V/E button, and hotkey semantics. In particular, confirm that a key which `OnTestKeyDown` claims and `OnKeyDown` then does not eat still reaches the app.
- The spec §5.2 app matrix.
- **MSI install and uninstall on Windows.** Export `HKLM\SOFTWARE\Microsoft\CTF\TIP\{CLSID}` after `regsvr32 VietTelexTIP.dll` and after an MSI install, then diff the two. The values to confirm are `SubstituteLayout` (stored as a DWORD) and the `Enable` values.
- **Chrome underline.** Check that Chrome and Edge now show no underline. The display-attribute provider is registered (its category row is unit-tested and diffed against the MSI), and the attribute is `TF_LS_NONE`. If they still underline, set `chrome.exe` to "Sửa trực tiếp" on the Ứng dụng page to test in-place mode. It is not the default for browsers, because the omnibox's inline autocomplete keeps a selection that in-place editing resets on.
- **Store installs (Active Setup).** After a `/qn` install as SYSTEM, sign out and in (or sign in as a second user): the keyboard must be in the list without opening VietTelex, the welcome window must appear once the desktop is up, and `HKCU\Software\Microsoft\Active Setup\Installed Components\{D1246D27-…}` must hold `Version=1,0`. Remove the keyboard by hand, sign out and in: it must not come back. Upgrade the MSI: the stub must not run again.
- **Onboarding:** the welcome window (DPI, keyboard navigation), conflict detection with UniKey/EVKey/OpenKey running, and with Microsoft's Vietnamese Telex / Number-key keyboard in the list — including that "remove from list" (InstallLayoutOrTip ILOT_UNINSTALL) really removes it, and falls back to ms-settings otherwise. Import a real UniKey (`Lưu` from its macro dialog) and OpenKey export.
- **Games / fullscreen:** a D3D exclusive-fullscreen game (WASD not eaten, Ctrl+Shift not toggling), Alt+Tab out and back, Chrome F11 / YouTube fullscreen still typing, a PowerPoint slideshow, the Chế độ game hotkey, the V/E indicator near the caret (Notepad) and in the corner (Chrome), never stealing focus.
- **Terminals + AI CLIs:** Claude Code / Gemini CLI in Windows Terminal and in a legacy conhost window, Direct mode (default) and with `windowsterminal.exe` set to composition.
- **Caret hints:** that the popup sits at the caret (GetTextExt) in Notepad, Word, WordPad, Chrome/Edge, VS Code and a UWP/WinUI field. Check too that it never steals focus, that Tab/Enter/Esc are eaten only while it shows, and that Tab replaces exactly the suggested text.
- **Text tools:**
  - The TSF path in Word, Notepad, WordPad (classic RichEdit through the parent context), Chrome/Edge/VS Code (Chromium TSF) and a UWP/WinUI field.
  - The clipboard fallback in a Qt/Java app with ENG active, including that the original clipboard (text, image, files) comes back.
  - The tray path's refocus.
  - That clipboard history (Win+V) skips our content.
  - That Ctrl+Shift+T does not also toggle Việt/Anh.
- The ARM64X forwarder on Snapdragon hardware: check that both a native ARM64 app and an emulated x64 app (e.g. an x64-only Electron app) type Vietnamese, and that the forwarded DLLs load from the install folder.
