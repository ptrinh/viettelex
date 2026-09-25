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

## ARM64 (supported from v1)

Windows on ARM runs native ARM64 apps and emulated x64 apps side by side, and both read the same 64-bit `InprocServer32` path. The ARM64 MSI therefore installs three DLLs:

| File | What |
|---|---|
| `VietTelexTIP.dll` | ARM64X **pure forwarder**. This is the registered COM server. |
| `VietTelexTIP_arm64.dll` | The real TIP for native ARM64 apps. |
| `VietTelexTIP_x64.dll` | The real TIP for emulated x64 apps. It is the x64 build, renamed. |

The forwarder follows Microsoft's "Arm64X pure forwarder DLL" recipe. `ime/src/arm64x/empty.cpp` is compiled twice, once plain and once with `/arm64EC`. Then `link /DLL /NOENTRY /MACHINE:ARM64X /DEFARM64NATIVE:arm64_exports.def /DEF:x64_exports.def` links both objects into one DLL.

- CMake does this automatically in every MSVC ARM64 build (`ime/CMakeLists.txt`); there is no manual relink.
- `installer/build.ps1` copies the x64 TIP in as `VietTelexTIP_x64.dll`, checks with `dumpbin` that the forwarder is ARM64X, and builds the ARM64 MSI.
- The native `regsvr32` loads the forwarder. The forwarded `DllRegisterServer` then registers the forwarder's path, not its own (`ime/core/com_path.h`, unit-tested).
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
- MSI install/uninstall and signing.
- The ARM64X forwarder on Snapdragon hardware: check that both a native ARM64 app and an emulated x64 app (e.g. an x64-only Electron app) type Vietnamese, and that the forwarded DLLs load from the install folder.
