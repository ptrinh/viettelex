# Microsoft Store: submission checklist

VietTelex is submitted to the Store as a **"MSI or EXE app"** in Partner Center. The Store shows the listing, and Windows downloads and runs **our signed MSI** from our own URL. MSIX is not used, because an MSIX package cannot register a system-wide TSF keyboard. `msix/AppxManifest.xml` is an optional companion-only template.

## 1. Installer requirements (every release)

- [ ] **Signed MSI.** The MSI and every PE file inside it are Authenticode-signed with Azure Trusted Signing (`signing/sign.ps1`), and the certificate chains to the Microsoft Trusted Root Program. Check with `signtool verify /pa /v <msi>`.
- [ ] **Versioned, HTTPS, immutable URL.** Each architecture gets one URL per version:
  - `https://github.com/ptrinh/viettelex/releases/download/win-v<VERSION>/VietTelex-<VERSION>-x64.msi`
  - `https://github.com/ptrinh/viettelex/releases/download/win-v<VERSION>/VietTelex-<VERSION>-arm64.msi`

  Never re-upload a changed file under an existing tag. A fix means a new version and a new URL, because the Store validates the file behind the URL.
- [ ] **Standalone installer.** It is a complete offline MSI with no downloader stub and nothing bundled.
- [ ] **Silent install switches.** Partner Center lists MSI switches automatically. If asked:

  | Operation | Command |
  |---|---|
  | Install (silent) | `msiexec /i VietTelex-<VERSION>-<arch>.msi /qn /norestart` |
  | Uninstall | `msiexec /x {ProductCode} /qn` |

  Exit codes are the standard MSI ones: `0` success, `3010` reboot required, `1618` another install in progress, `1603` failure.
- [ ] **Architectures.** x64 MSI for x64 devices. ARM64 MSI for ARM64 devices; it contains the ARM64X forwarder, so native ARM64 apps and emulated x64 apps both get the keyboard.
- [ ] **Minimum OS.** Windows 10 1903 (10.0.18362) or later.
- [ ] **Store version matches.** The package version in Partner Center equals `ime/version.h` / the MSI `ProductVersion`.
- [ ] **Install test.** Install from the URL on a clean VM with `/qn`, check that typing works, uninstall, and check that nothing is left behind (no `HKCU\Software\VietTelex`, no `%LOCALAPPDATA%\VietTelex`).

## 2. Listing

| Field | Value |
|---|---|
| Product name | VietTelex |
| Category | Utilities & tools |
| Pricing | Free |
| Privacy policy URL | https://viettelex.com/privacy-policy |
| Website | https://viettelex.com |
| Support contact | https://github.com/ptrinh/viettelex/issues |
| License | MIT (open source) |
| Languages | Vietnamese (primary), English |

**Short description (vi):** Bộ gõ tiếng Việt Telex/VNI tối giản, nhanh, ổn định, không thu thập dữ liệu.

**Description (vi):**

> VietTelex là bộ gõ tiếng Việt cho Windows, chạy như một bàn phím của hệ thống (Text Services Framework).
> - Gõ Telex hoặc VNI, không gạch chân từ đang gõ.
> - Tự khôi phục từ tiếng Anh (google, windows…), kiểm tra chính tả khi gõ.
> - Gõ tắt, nhập/xuất bảng gõ tắt.
> - Nhớ Việt/Anh riêng cho từng ứng dụng; phím chuyển Ctrl+Shift hoặc Win+Space.
> - Không gõ vào ô mật khẩu.
> - Không thu thập dữ liệu, không kết nối mạng trừ khi bạn bấm Kiểm tra cập nhật. Mã nguồn mở (MIT).

**Short description (en):** A minimal, fast, stable Vietnamese keyboard (Telex/VNI) with no data collection.

**Description (en):**

> VietTelex is a Vietnamese input method for Windows that runs as a system keyboard (Text Services Framework): Telex or VNI with no underline while typing, automatic English-word restore, shortcuts, per-app Vietnamese/English memory, and password fields left alone. No data collection, and no network access unless you click "Check for updates". Open source (MIT).

**Search terms:** vietnamese, tiếng việt, telex, vni, bộ gõ, keyboard, ime

**Screenshots (1366×768 or larger):** the Settings tabs Kiểu gõ, Chính tả and Gõ tắt; Word with Vietnamese text; the taskbar V/E indicator.

## 3. Partner Center answers

- **Does the app collect personal data?** No. Link the privacy policy above anyway, because it is required for all apps.
- **Does the app update itself?** Yes. The optional *Kiểm tra cập nhật* (update check) downloads a newer signed MSI from the same GitHub Releases location. The Store allows self-updating MSI/EXE apps.
- **Restricted capabilities or drivers:** none. It is a user-mode TSF text service (COM in-proc DLL) plus a tray app.
- **Age rating questionnaire:** utility with no user-generated content and no online interaction.

## 4. Do not put in this file or the listing

No personal names, e-mail addresses, phone numbers, account or tenant IDs, or signing-account details. Those live only in Partner Center and CI secrets.
