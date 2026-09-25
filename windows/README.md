# VietTelex for Windows

Spec: [docs/WINDOWS-SPEC.md](docs/WINDOWS-SPEC.md). Engine C ABI: [engine/API.md](engine/API.md).

| Dir | What |
|---|---|
| `engine/` | C++ port of TelexCore (static lib `viettelex_engine`) |
| `ime/core/` | Portable typing core: key mapping, `TypingSession` (composition / in-place), settings + snapshot, shortcuts, per-app policy, hotkey. Unit-tested on any OS. |
| `ime/src/` | `VietTelexTIP.dll`: the TSF text service (COM, `ITfTextInputProcessorEx`, key sink, composition with a no-underline display attribute, in-place mode, input-mode button, registration) |
| `app/` | `VietTelex.exe`: tray, Settings window, updater, per-app hook fallback, per-user setup |
| `installer/` | WiX MSI, MSIX template, winget templates, Azure Trusted Signing script, `build.ps1` |

## Build

```
# any OS: core + tests
cmake -S windows -B build && cmake --build build && ctest --test-dir build
# Windows (MSVC), one per architecture
cmake -S windows -B build-x64 -A x64 && cmake --build build-x64 --config Release
# full release: DLLs/EXE for x86/x64/ARM64, MSIs, winget manifests, signing
pwsh windows/installer/build.ps1
```

Cross-compile check without Windows (llvm-mingw in Docker):
`cmake -S windows -B b -G Ninja -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-clang++ -DCMAKE_C_COMPILER=x86_64-w64-mingw32-clang -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres`.
`ime/src/tsf_compat.h` fills in the TSF declarations mingw lacks. The MSVC + Windows SDK build is the one that ships.

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

## Microsoft Store

An MSIX package cannot register a system-wide TSF text service. TSF loads TIPs from the real HKLM `CTF\TIP` and `CLSID` keys into every process, and MSIX virtualizes registry writes. The recommended Store route is therefore a Partner Center **"MSI or EXE" submission** that points at the signed MSI:

- silent install: `msiexec /i VietTelex-<v>-x64.msi /qn`
- uninstall: `msiexec /x {ProductCode} /qn`

`installer/msix/AppxManifest.xml` is a template for the day packaged TIPs become possible. Today it can only carry the companion app.

## Needs a real Windows machine

- Everything in the TSF layer: activation, composition behaviour, OnEndEdit caret tracking, input scopes, the taskbar V/E button, and hotkey semantics. In particular, confirm that a key which `OnTestKeyDown` claims and `OnKeyDown` then does not eat still reaches the app.
- The spec §5.2 app matrix.
- MSI install/uninstall, ARM64X linking (see `installer/build.ps1`), and signing.
