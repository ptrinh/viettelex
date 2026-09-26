# VietTelex for Windows

Spec: [docs/WINDOWS-SPEC.md](docs/WINDOWS-SPEC.md). Engine C ABI: [engine/API.md](engine/API.md).

| Dir | What |
|---|---|
| `engine/` | C++ port of TelexCore (static lib `viettelex_engine`) |
| `ime/core/` | Portable typing core: key mapping, `TypingSession` (composition / in-place), settings + snapshot, shortcuts, per-app policy, hotkey. Unit-tested on any OS. |
| `ime/src/` | `VietTelexTIP.dll`: the TSF text service (COM, `ITfTextInputProcessorEx`, key sink, composition with a no-underline display attribute, in-place mode, input-mode button, registration) |
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

The signing target comes from `VTX_SIGN_ENDPOINT`, `VTX_SIGN_ACCOUNT` and `VTX_SIGN_PROFILE`, set in the environment or in the gitignored `installer/signing.local.env`. The access token comes from `az login`, or in CI from `AZURE_TENANT_ID`, `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET`. No secret is stored in the repo.

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

## Icons

All icons come from the macOS artwork, regenerated by `installer/icons/make_icons.py` (macOS only; it uses `sips`, nothing gets installed).

- **App icon:** `ime/res/viettelex.ico` holds 16–256 px. Sizes that exist as AppIcon PNGs are copied byte for byte; the rest are `sips` downscales. It is used for the exe, the MSI's Add/Remove entry, the Start menu shortcut and the Settings window.
- **Keyboard icon (settings `menuIcon`):** five choices — `vt` (default), `star`, `flag`, `logo`, `vi`. The retired `letter` value migrates to `vt`. The mapping lives in `ime/res/icon_ids.h` and is unit-tested.
  - **Taskbar input indicator** (the language-bar input-mode item, which follows Việt/Anh): theme glyphs `glyph_<vt|star|flag>_<v|e>_<dark|light>.ico`. `dark` is white for the dark taskbar and `light` is dark for the light taskbar, chosen from `SystemUsesLightTheme`; `e` is the English state at 40% opacity. `logo` uses the colour app icon, dimmed in English. `vi` draws "VI"/"EN" text at runtime.
  - **Static profile icon** (Win+Space list): `profile_<choice>.ico`, a white glyph with a dark outline so it reads on both flyout themes. The default is monochrome Vᴛ at IconIndex 13, which a unit test checks against the resource order. Changing the choice in Settings runs `VietTelex.exe --set-profile-icon <choice>` elevated, with one UAC prompt, to update the HKLM IconIndex.

  Why an elevated helper and not a user-writable icon file: the profile icon is loaded into every process, including elevated ones and the secure desktop, and no user-writable file should be parsed there. Installing a new version resets the icon to Vᴛ.
- **Tray icon:** off by default (`showTrayIcon`), because the taskbar indicator already shows the state. Start menu → VietTelex opens Settings.

## How typing works## How typing works

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
- **Store installs.** With a `/qn` install run as SYSTEM, the keyboard reaches users in one of two ways: they open VietTelex once, or they add "VietTelex" under Settings > Language > Tiếng Việt > Keyboards.
- The ARM64X forwarder on Snapdragon hardware: check that both a native ARM64 app and an emulated x64 app (e.g. an x64-only Electron app) type Vietnamese, and that the forwarded DLLs load from the install folder.
