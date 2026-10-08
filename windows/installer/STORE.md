# Microsoft Store: submission checklist

VietTelex is submitted to the Store as a **"MSI or EXE app"** in Partner Center. The Store shows the listing, and Windows downloads and runs **our signed MSI** from our own URL. MSIX is not used, because an MSIX package cannot register a system-wide TSF keyboard. `msix/AppxManifest.xml` is an optional companion-only template.

## 1. Installer requirements (every release)

- [ ] **Signed MSI.** The MSI and every PE file inside it are Authenticode-signed with Azure Trusted Signing (`signing/sign.ps1`), and the certificate chains to the Microsoft Trusted Root Program. Check with `signtool verify /pa /v <msi>`.
- [ ] **Versioned, HTTPS, immutable URL.** Each architecture gets one URL per version. The same bytes are published in two places:

  | Where | URL | Used by |
  |---|---|---|
  | Website mirror (no redirect) | `https://viettelex.com/download/windows/<VERSION>/VietTelex-<VERSION>-<arch>.msi` (files in `docs/download/windows/<VERSION>/`) | **Partner Center package URLs** (the Store wants a direct, non-redirecting URL) |
  | GitHub release, tag `windows-v<VERSION>` | `https://github.com/ptrinh/viettelex/releases/download/windows-v<VERSION>/VietTelex-<VERSION>-<arch>.msi` | `docs/stable.json` (in-app updater), winget, Chocolatey |

  `<arch>` is `x64` or `arm64`. The tag prefix is `windows-v`, not `win-v`. Check both before submitting: `curl -sI <url>` must return 200, and `shasum -a 256` must match `SHA256SUMS` on the release.

  Never re-upload a changed file under an existing tag or folder. A fix means a new version and new URLs, because the Store validates the file behind the URL.
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

Field limits (MSI/EXE listing, Microsoft Learn: *Add and edit Store listing info for MSI/EXE app* and the *Store submission API* listing object, checked 2026-10-08): description ≤ 10,000 characters, plain text, no URLs; short description ≤ 1,000 (only ~270 show without "more", so the texts below stay under 270); product features ≤ 20 × 200 characters, no bullets; **search terms ≤ 7, each ≤ 30 characters, ≤ 21 unique words in total**; screenshots 1–10 per language.

Fill the Vietnamese (vi-VN) listing first, then English (en-US).

### 2.1 Vietnamese (vi-VN)

**Short description** (≈ 200 characters):

```text
Bộ gõ tiếng Việt Telex/VNI nhanh, riêng tư cho Windows. Chạy trên TSF nên gõ được cả trong Chrome, Excel và ứng dụng quyền quản trị. Không gạch chân, không thu thập dữ liệu, mã nguồn mở, hỗ trợ ARM64.
```

**Description:**

```text
VietTelex là bộ gõ tiếng Việt tối giản, nhanh và ổn định cho Windows 10 và 11, cùng engine với VietTelex trên macOS, iOS và Android.

VietTelex là một bàn phím thật của Windows, chạy trên Text Services Framework (TSF), không dùng hook bàn phím toàn cục. Vì vậy gõ được ổn định trong Chrome, Edge, Word, Excel, Teams, Zalo, VS Code, và cả trong ứng dụng chạy quyền quản trị (Run as administrator).

• Gõ Telex hoặc VNI, bỏ dấu kiểu mới hoặc cũ, sửa dấu ở bất kỳ vị trí nào trong từ.
• Không gạch chân khi gõ, kể cả trong Command Prompt, PowerShell và Windows Terminal.
• Tự khôi phục từ tiếng Anh (gõ "thanks" vẫn ra "thanks"), kiểm tra chính tả tiếng Việt.
• Gõ tắt theo ý bạn; nhớ Việt/Anh riêng cho từng ứng dụng; chuyển bằng Ctrl+Shift, Alt+Z hoặc Win+Space.
• Không đụng vào ô mật khẩu; tự tắt trong Remote Desktop và máy ảo.
• Bản x64 và ARM64 gốc: chạy mượt trên máy Snapdragon/Windows on ARM.

Riêng tư: không telemetry, không thu thập dữ liệu, không gửi những gì bạn gõ đi đâu. VietTelex chỉ kết nối mạng khi bạn bấm Kiểm tra cập nhật.

Miễn phí, mã nguồn mở theo giấy phép MIT.
```

**Product features** (one per field):

```text
Gõ Telex hoặc VNI, bỏ dấu kiểu mới hoặc cũ
Chạy trên TSF, không hook bàn phím: gõ được trong Chrome, Excel và ứng dụng quyền quản trị
Không gạch chân khi gõ, kể cả Command Prompt và Windows Terminal
Tự khôi phục từ tiếng Anh, kiểm tra chính tả tiếng Việt
Gõ tắt và nhớ Việt/Anh theo từng ứng dụng
Không đụng vào ô mật khẩu
Không telemetry, không thu thập dữ liệu
Mã nguồn mở (MIT), miễn phí
Bản x64 và ARM64 gốc
```

**Search terms** (7 terms, 15 unique words):

| # | Term | Chars |
|---|---|---|
| 1 | `bộ gõ tiếng việt` | 16 |
| 2 | `bàn phím tiếng việt` | 19 |
| 3 | `telex` | 5 |
| 4 | `vni` | 3 |
| 5 | `gõ dấu` | 6 |
| 6 | `bo go tieng viet` | 16 |
| 7 | `vietnamese keyboard` | 19 |

### 2.2 English (en-US)

**Short description** (≈ 200 characters):

```text
Fast, private Vietnamese keyboard (Telex/VNI) for Windows. Built on TSF, so it works in Chrome, Excel and admin apps without a keyboard hook. No underline, no telemetry, open source, native ARM64.
```

**Description:**

```text
VietTelex is a minimal, fast and reliable Vietnamese input method for Windows 10 and 11, with the same engine as VietTelex on macOS, iOS and Android.

VietTelex is a real Windows keyboard built on the Text Services Framework (TSF), with no global keyboard hook. That is why it types reliably in Chrome, Edge, Word, Excel, Teams, Zalo and VS Code, and in apps running as administrator.

• Type with Telex or VNI, old or new tone placement, and fix tones anywhere in the word.
• No underline while typing, including Command Prompt, PowerShell and Windows Terminal.
• Restores English words automatically ("thanks" stays "thanks") and checks Vietnamese spelling.
• Custom shortcuts; remembers Vietnamese/English per app; switch with Ctrl+Shift, Alt+Z or Win+Space.
• Leaves password fields alone and turns itself off in Remote Desktop and virtual machines.
• Native x64 and ARM64 builds for Snapdragon / Windows on ARM PCs.

Private: no telemetry, no data collection, and nothing you type is ever sent anywhere. VietTelex only goes online when you press Check for updates.

Free and open source under the MIT License.
```

**Product features:**

```text
Telex or VNI, old or new tone placement
Built on TSF with no keyboard hook: works in Chrome, Excel and admin apps
No underline while typing, even in Command Prompt and Windows Terminal
Automatic English-word restore and Vietnamese spell check
Shortcuts and per-app Vietnamese/English memory
Leaves password fields alone
No telemetry, no data collection
Free and open source (MIT)
Native x64 and ARM64 builds
```

**Search terms** (7 terms, 11 unique words):

| # | Term | Chars |
|---|---|---|
| 1 | `vietnamese keyboard` | 19 |
| 2 | `vietnamese input method` | 23 |
| 3 | `vietnamese ime` | 14 |
| 4 | `telex` | 5 |
| 5 | `vni` | 3 |
| 6 | `tieng viet` | 10 |
| 7 | `bo go tieng viet` | 16 |

Search terms name only VietTelex's own features and the language. Never add another product's or company's name.

### 2.3 Screenshot shot-list

Desktop screenshots: PNG, landscape, **1366×768 or larger** (1920×1080 recommended; 4K accepted), ≤ 50 MB each, up to 10 per language, optional caption ≤ 200 characters. Upload per language, and use Vietnamese Windows UI for vi-VN where possible. Keep the important part in the top two-thirds, because the Store may overlay text on the bottom third. Do not add extra logos or marketing text. Use a clean desktop with no personal names, e-mail addresses, chats or accounts visible, and use sample text only.

| # | Shot | Caption (vi) | Caption (en) |
|---|---|---|---|
| 1 | Chrome or Edge: a search box or document with a full Vietnamese sentence just typed, no underline, the taskbar showing the **V** indicator | Gõ tiếng Việt trong Chrome, không gạch chân | Type Vietnamese in Chrome with no underline |
| 2 | Excel: a cell being edited with Vietnamese text, plus a few filled cells | Gõ trực tiếp trong ô Excel | Type straight into Excel cells |
| 3 | An app running **as administrator** (e.g. Notepad or Command Prompt with "Administrator" in the title bar) with Vietnamese text | Gõ được cả trong ứng dụng quyền quản trị, nhờ TSF | Works in admin apps too, thanks to TSF |
| 4 | Windows Terminal / PowerShell with a Vietnamese line | Không gạch chân, kể cả trong Terminal | No underline, even in the terminal |
| 5 | Settings, **Kiểu gõ** tab (Telex/VNI, tone placement) | Telex hoặc VNI, bỏ dấu kiểu mới hoặc cũ | Telex or VNI, old or new tone placement |
| 6 | Settings, **Chính tả** tab, next to a document where an English word was kept (e.g. "windows", "thanks") | Tự khôi phục từ tiếng Anh, kiểm tra chính tả | Automatic English restore and spell check |
| 7 | Settings, **Gõ tắt** tab with a few sample shortcuts | Gõ tắt theo ý bạn | Your own shortcuts |
| 8 | Settings, **Ứng dụng** tab (per-app Việt/Anh) | Nhớ Việt/Anh cho từng ứng dụng | Remembers Vietnamese/English per app |
| 9 | Taskbar icon choices (Vᴛ, ★, 🇻🇳, logo, VI) in light and dark theme | Chọn icon bàn phím, giao diện sáng/tối | Pick your keyboard icon, light or dark |
| 10 | Windows on ARM: Settings > System > About showing an ARM64 processor next to VietTelex typing | Chạy gốc trên máy ARM64 | Runs natively on ARM64 PCs |

## 3. Partner Center answers

- **Does the app collect personal data?** No. Link the privacy policy above anyway, because it is required for all apps.
- **Does the app update itself?** Yes. The optional *Kiểm tra cập nhật* (update check) downloads a newer signed MSI from the same GitHub Releases location. The Store allows self-updating MSI/EXE apps.
- **Restricted capabilities or drivers:** none. It is a user-mode TSF text service (COM in-proc DLL) plus a tray app.
- **Age rating questionnaire:** utility with no user-generated content and no online interaction.

## 4. Do not put in this file or the listing

No personal names, e-mail addresses, phone numbers, account or tenant IDs, or signing-account details. Those live only in Partner Center and CI secrets.
