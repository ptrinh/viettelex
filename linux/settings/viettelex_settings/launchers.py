"""Tự thêm cờ IME Wayland cho app Chromium/Electron — file .desktop cấp người dùng.

Đi cùng `[experimental] no_underline = "forward-keys"` (SETTINGS.md §9): chế độ đó chỉ chạy
khi Chrome/Electron dùng IME Wayland gốc (text-input). App cài đặt chép file .desktop của hệ
thống / Flatpak / Snap sang `$XDG_DATA_HOME/applications` (ưu tiên cao hơn theo XDG) và chèn
cờ vào mọi dòng `Exec=` (mục chính + Desktop Actions). Người dùng không phải chạy lệnh nào.

Quy tắc sở hữu:
- File do ta tạo mang `X-VietTelex-Generated=<hash nguồn+cờ>` trong [Desktop Entry]. Chỉ file
  có dòng này mới bị ta sửa/xoá. File người dùng tự đặt cùng tên (không có dòng đó) KHÔNG bao
  giờ bị ghi đè — chỉ báo lại (`conflicts`).
- Mỗi lần app cài đặt mở (và khi bật/tắt): nguồn đổi ⇒ tạo lại; nguồn mất ⇒ xoá file của ta;
  tắt ⇒ xoá hết file của ta.

Không đọc `~/.config/<app>-flags.conf`: chỉ wrapper của Arch đọc file đó — wrapper
`google-chrome` của gói .deb Google (chromium `chrome/installer/linux/common/wrapper`) chỉ
`exec -a "$0" "$HERE/chrome" "$@"`, không đọc file cờ nào.

Module thuần (không GTK); mọi đường dẫn hệ thống đi qua tham số để test chạy ở thư mục tạm.
Danh sách app = `isChromiumApp` của `linux/common/src/app.cpp` (tests/test_launchers.py kiểm
đồng bộ bằng cách đọc mã C++).
"""

import hashlib
import os
import re
import shutil
import subprocess

MARKER_KEY = "X-VietTelex-Generated"
SOURCE_KEY = "X-VietTelex-Source"

ENABLE_IME = "--enable-wayland-ime"
TEXT_INPUT_VERSION = "--wayland-text-input-version"
# Mặc định của Chrome ≥ 140 / Electron ≥ 38 (chạy Wayland gốc khi phiên là Wayland). Chromium
# main đã bỏ hẳn cờ này (luôn "auto") ⇒ vô hại ở bản mới; ở Electron cũ (mặc định XWayland) nó
# là cách DUY NHẤT để app nhận IME Wayland.
OZONE_HINT = "--ozone-platform-hint=auto"

# Chrome ≥ 140 trên phiên Wayland: Wayland gốc + text-input-v3 mặc định (v3 mặc định từ
# Chromium 137, commit e48954bd; Wayland mặc định từ 140) ⇒ không cần cờ.
CHROME_DEFAULT_ON_MAJOR = 140
# KWin bỏ text-input-v1 (commit ef1b092db6, 27/02/2026 ⇒ Plasma 6.7). Cũ hơn: Fcitx khuyên v1.
KWIN_DROPPED_V1 = (6, 7)


def flags_for(text_input_version="3"):
    return [ENABLE_IME, "%s=%s" % (TEXT_INPUT_VERSION, text_input_version), OZONE_HINT]


# ---------------------------------------------------------------- isChromiumApp (bản Python)

# PHẢI trùng tập `names` trong isChromiumApp (linux/common/src/app.cpp) — có test so khớp.
CHROMIUM_NAMES = frozenset((
    "chrome", "google-chrome", "google-chrome-stable", "google-chrome-beta", "chromium",
    "chromium-browser", "chromium-freeworld", "brave", "brave-browser", "brave-browser-stable",
    "microsoft-edge", "microsoft-edge-stable", "vivaldi", "vivaldi-stable", "opera", "code",
    "code-oss", "code-insiders", "vscodium", "codium", "cursor",
    "electron", "slack", "discord", "signal-desktop", "obsidian", "zalo", "teams-for-linux",
    "coccoc", "coccoc-browser", "coccoc-browser-stable", "yandex-browser", "yandex-browser-stable",
    "thorium", "thorium-browser", "ungoogled-chromium", "google-chrome-unstable",
    "microsoft-edge-beta", "microsoft-edge-dev", "opera-beta", "opera-developer",
    "vivaldi-snapshot", "brave-browser-beta", "brave-browser-nightly",
    "cromite", "cromite-browser", "helium", "helium-browser", "slimjet", "slimjet-browser",
    "flashpeak-slimjet",
    "com.brave.browser", "com.microsoft.edge", "ru.yandex.browser", "vivaldi-flatpak",
    "io.github.ungoogled_software.ungoogled_chromium", "com.github.eloston.ungoogledchromium",
    "wavebox", "min-browser",
    "antigravity", "windsurf", "kiro", "trae", "void", "pearai", "positron",
    "signal", "org.signal.signal", "element", "element-desktop", "im.riot.riot",
    "mattermost", "mattermost-desktop", "com.mattermost.desktop", "rocketchat-desktop",
    "rocket.chat", "rocketchat", "caprine", "ferdium", "rambox", "franz", "beeper",
    "beepertexts", "vesktop", "teams_for_linux", "whatsapp-desktop-linux", "whatsappdesktop",
    "zalo-linux", "feishu", "bytedance-feishu", "bytedance-feishu-stable",
    "notion", "notion-app", "logseq", "joplin", "joplin-desktop", "joplin_desktop", "typora",
    "marktext", "notesnook", "anytype", "bitwarden", "bitwarden-desktop",
    "com.bitwarden.desktop", "1password", "com.onepassword.onepassword", "postman",
    "insomnia", "figma-linux", "figma_linux", "github-desktop", "io.github.shiftey.desktop",
    "io.github.shiftey",
    "gitkraken", "spotify", "com.spotify.client", "claude", "claude-desktop",
))


def normalize_app_id(raw):
    """= normalizeAppId (app.cpp)."""
    s = raw
    colon = s.rfind(":")
    if colon >= 0:
        s = s[colon + 1:]
    slash = max(s.rfind("/"), s.rfind("\\"))
    if slash >= 0:
        s = s[slash + 1:]
    if len(s) > len(".desktop") and s.endswith(".desktop"):
        s = s[:-len(".desktop")]
    s = "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in s)
    s = s.rstrip(" \n")
    us = s.find("_")
    if us > 0 and s[us + 1:] == s[:us]:
        s = s[:us]
    return s


def _short_name(i):
    dot = i.rfind(".")
    return i if dot < 0 else i[dot + 1:]


def is_chromium_app(app_id):
    """= isChromiumApp (app.cpp)."""
    i = normalize_app_id(app_id)
    if not i:
        return False
    if i in CHROMIUM_NAMES or _short_name(i) in CHROMIUM_NAMES:
        return True
    if i.startswith("appimagekit"):
        dash = i.find("-")
        if dash >= 0 and i[dash + 1:] in CHROMIUM_NAMES:
            return True
    if i.startswith("electron") and len(i) > 8 and i[8:].isdigit():
        return True
    if i.startswith("crx_") or i.startswith("coccoc"):
        return True
    for p in ("chrome-", "brave-", "msedge-", "vivaldi-", "opera-"):
        if i.startswith(p) and i.endswith("-default"):
            return True
    return False


# ---------------------------------------------------------------- Exec= (Desktop Entry spec)

def _tokens(value):
    """Tách giá trị Exec (nguyên văn trong file) thành [(start, end, text)] theo khoảng trắng
    ngoài ngoặc kép. Giữ vị trí để chèn cờ mà không đụng phần còn lại."""
    out, i, n = [], 0, len(value)
    while i < n:
        while i < n and (value[i] in " \t" or value.startswith("\\s", i)):
            i += 2 if value[i] == "\\" else 1
        if i >= n:
            break
        start, quoted = i, False
        while i < n:
            c = value[i]
            if quoted:
                if value.startswith('\\\\"', i):     # \" trong ngoặc, sau escape cấp chuỗi
                    i += 3
                    continue
                if c == "\\":
                    i += 2
                    continue
                if c == '"':
                    quoted = False
                i += 1
                continue
            if c in " \t" or value.startswith("\\s", i):
                break
            if c == '"':
                quoted = True
            elif c == "\\":
                i += 1
            i += 1
        out.append((start, min(i, n), _unquote(value[start:min(i, n)])))
    return out


def _unquote(tok):
    s = tok.replace("\\s", " ").replace("\\\\", "\\")
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        s = s[1:-1].replace('\\"', '"').replace("\\`", "`").replace("\\$", "$")
    return s


_ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Chạy chương trình KHÁC rồi mới tới app (cờ sẽ rơi vào wrapper) — không sửa.
UNSUPPORTED_WRAPPERS = frozenset((
    "sh", "bash", "dash", "zsh", "fish", "gtk-launch", "xdg-open", "gio", "kioclient",
    "kioclient5", "kioclient6", "flatpak-spawn", "distrobox-enter", "toolbox", "wine",
    "proton", "steam", "pkexec", "sudo", "gamemoderun", "firejail",
))
_X11_ENV = ("GDK_BACKEND=x11", "ELECTRON_OZONE_PLATFORM_HINT=x11", "ELECTRON_OZONE_PLATFORM_HINT=X11")


def _switch_name(flag):
    return flag.split("=", 1)[0]


def _forces_x11(texts):
    for k, t in enumerate(texts):
        if t in _X11_ENV or t in ("--ozone-platform=x11", "--ozone-platform-hint=x11",
                                  "--disable-wayland-ime"):
            return True
        if t in ("--ozone-platform", "--ozone-platform-hint") and k + 1 < len(texts) \
                and texts[k + 1] == "x11":
            return True
    return False


def program_of(value):
    """Chương trình thật mà Exec chạy: ("flatpak", app_id) | ("snap", tên) | ("bin", đường
    dẫn) | (None, lý do). Cùng logic với chỗ chèn cờ."""
    where = _insert_after(_tokens(value))
    return where[1], where[2]


def _insert_after(toks):
    """→ (chỉ số token đứng ngay trước cờ | None, loại, tên)."""
    texts = [t[2] for t in toks]
    k = 0
    if k < len(texts) and os.path.basename(texts[k]) == "env":
        k += 1
        while k < len(texts):
            t = texts[k]
            if t in ("-u", "--unset", "-C", "--chdir"):
                k += 2
            elif t.startswith("-") or _ENV_ASSIGN.match(t):
                k += 1
            else:
                break
    while k < len(texts) and _ENV_ASSIGN.match(texts[k]):
        k += 1
    if k >= len(texts):
        return None, None, "empty"
    prog = os.path.basename(texts[k])
    if prog == "flatpak":
        j = k + 1
        while j < len(texts) and texts[j].startswith("-"):      # tuỳ chọn toàn cục
            j += 1
        if j >= len(texts) or texts[j] != "run":
            return None, None, "unsupported"
        j += 1
        command = ""
        while j < len(texts) and texts[j].startswith("-"):
            if texts[j].startswith("--command="):
                command = texts[j].split("=", 1)[1]
            j += 1
        if j >= len(texts):
            return None, None, "unsupported"
        if os.path.basename(command) in UNSUPPORTED_WRAPPERS or os.path.basename(command) == "env":
            return None, None, "unsupported"
        return j, "flatpak", texts[j]
    if prog == "snap":
        if k + 1 < len(texts) and texts[k + 1] == "run":
            j = k + 2
            while j < len(texts) and texts[j].startswith("-"):
                j += 1
            if j < len(texts):
                return j, "snap", texts[j].split(".", 1)[0]
        return None, None, "unsupported"
    if prog in UNSUPPORTED_WRAPPERS or prog.startswith("%"):
        return None, None, "unsupported"
    if texts[k].startswith("/snap/bin/"):
        return k, "snap", prog.split(".", 1)[0]
    return k, "bin", texts[k]


def rewrite_exec(value, flags):
    """Chèn `flags` ngay sau chương trình (trước %U/%F và mọi tham số khác); `flatpak run …
    <appid>` ⇒ sau app id; `env A=1 /opt/x` ⇒ sau /opt/x.

    → (giá trị mới, trạng thái): "ok" | "already" (đủ cờ, giữ nguyên) | "x11" (đang ép X11 /
    tắt IME Wayland — giữ nguyên) | "unsupported" (sh -c, wrapper lạ — giữ nguyên)."""
    toks = _tokens(value)
    texts = [t[2] for t in toks]
    if _forces_x11(texts):
        return value, "x11"
    at, _kind, _name = _insert_after(toks)
    if at is None:
        return value, "unsupported"
    present = {_switch_name(t) for t in texts if t.startswith("--")}
    missing = [f for f in flags if _switch_name(f) not in present]
    if not missing:
        return value, "already"
    end = toks[at][1]
    return value[:end] + " " + " ".join(missing) + value[end:], "ok"


# ---------------------------------------------------------------- file .desktop

def _groups(text):
    """[(tên nhóm | None, [dòng])] — giữ nguyên từng dòng."""
    out, cur = [], (None, [])
    for line in text.split("\n"):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            out.append(cur)
            cur = (s[1:-1], [line])
        else:
            cur[1].append(line)
    out.append(cur)
    return out


def entry_values(text, group="Desktop Entry"):
    vals = {}
    for name, lines in _groups(text):
        if name != group:
            continue
        for line in lines[1:]:
            s = line.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            vals.setdefault(k.strip(), v.strip())
    return vals


def source_hash(source_text, flags):
    h = hashlib.sha256()
    h.update(source_text.encode("utf-8", "surrogateescape"))
    h.update(b"\0" + " ".join(flags).encode())
    return h.hexdigest()[:16]


def marker_of(text):
    """Giá trị X-VietTelex-Generated trong [Desktop Entry] (None = không phải file của ta)."""
    return entry_values(text).get(MARKER_KEY)


def build_override(source_text, flags, source_path=""):
    """Nội dung file override (hoặc None) + trạng thái: "ok" | "already" | "x11" |
    "unsupported" | "invalid" (không phải Application / Hidden / thiếu Exec) | "dbus"
    (DBusActivatable: launcher bỏ qua Exec)."""
    vals = entry_values(source_text)
    if vals.get("Type", "Application") != "Application" or vals.get("Hidden") == "true" \
            or not vals.get("Exec"):
        return None, "invalid"
    if vals.get("DBusActivatable") == "true":
        return None, "dbus"
    marker = source_hash(source_text, flags)
    main_status, changed = None, False
    out = []
    for name, lines in _groups(source_text):
        is_entry = name == "Desktop Entry"
        is_action = name is not None and name.startswith("Desktop Action ")
        new_lines = []
        for idx, line in enumerate(lines):
            s = line.lstrip()
            if is_entry and idx > 0 and s.startswith((MARKER_KEY + "=", SOURCE_KEY + "=")):
                continue        # nguồn lạ đã mang dấu của ta: không nhân đôi
            if (is_entry or is_action) and idx > 0 and s.startswith("Exec") and \
                    s[4:].lstrip().startswith("="):
                indent = line[:len(line) - len(s)]
                key, raw = s.split("=", 1)
                lead = raw[:len(raw) - len(raw.lstrip())]
                trail = raw[len(raw.rstrip()):]
                body = raw.strip()
                new, status = rewrite_exec(body, flags)
                if is_entry and main_status is None:
                    main_status = status
                    if status in ("x11", "unsupported"):
                        return None, status
                if status == "ok":
                    changed = True
                    line = "%s%s=%s%s%s" % (indent, key, lead, new, trail)
            new_lines.append(line)
            if is_entry and idx == 0:
                new_lines.append("%s=%s" % (MARKER_KEY, marker))
                if source_path:
                    new_lines.append("%s=%s" % (SOURCE_KEY, source_path))
        out.extend(new_lines)
    if main_status is None:
        return None, "invalid"
    if not changed:
        return None, "already"
    return "\n".join(out), "ok"


# ---------------------------------------------------------------- tìm nguồn

def user_apps_dir(env=None):
    env = os.environ if env is None else env
    home = env.get("HOME") or os.path.expanduser("~")
    base = env.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    return os.path.join(base, "applications")


def source_dirs(env=None, extra=None):
    """Thư mục applications hệ thống theo thứ tự ưu tiên XDG (+ Flatpak/Snap nếu XDG_DATA_DIRS
    thiếu). Không gồm thư mục của người dùng (đích ghi)."""
    env = os.environ if env is None else env
    home = env.get("HOME") or os.path.expanduser("~")
    dirs = [d for d in (env.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
    if extra is None:
        extra = [os.path.join(home, ".local/share/flatpak/exports/share"),
                 "/var/lib/flatpak/exports/share", "/var/lib/snapd/desktop"]
    out, seen = [], set()
    user = os.path.normpath(user_apps_dir(env))
    for d in dirs + list(extra):
        a = os.path.normpath(os.path.join(d, "applications"))
        if a in seen or a == user:
            continue
        seen.add(a)
        out.append(a)
    return out


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            return f.read()
    except OSError:
        return None


def find_sources(dirs):
    """{desktop id: (đường dẫn, nội dung)} của app họ Chromium (theo tên file hoặc
    StartupWMClass). Thư mục đứng trước thắng (như launcher)."""
    found, shadowed = {}, set()
    for d in dirs:
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for n in names:
            if not n.endswith(".desktop") or n in found or n in shadowed:
                continue
            p = os.path.join(d, n)
            if not os.path.isfile(p):
                continue
            text = _read(p)
            if text is None:
                continue
            shadowed.add(n)
            vals = entry_values(text)
            if is_chromium_app(n) or is_chromium_app(vals.get("StartupWMClass", "")):
                found[n] = (p, text)
    return found


# ---------------------------------------------------------------- "đã mặc định bật"?

DEB_PACKAGES = {
    "google-chrome.desktop": "google-chrome-stable",
    "google-chrome-beta.desktop": "google-chrome-beta",
    "google-chrome-unstable.desktop": "google-chrome-unstable",
    "microsoft-edge.desktop": "microsoft-edge-stable",
    "microsoft-edge-beta.desktop": "microsoft-edge-beta",
    "microsoft-edge-dev.desktop": "microsoft-edge-dev",
    "chromium.desktop": "chromium",
}


def dpkg_versions(status_text, wanted):
    out, pkg = {}, None
    for line in status_text.split("\n"):
        if line.startswith("Package: "):
            pkg = line[9:].strip()
        elif line.startswith("Version: ") and pkg in wanted:
            out[pkg] = line[9:].strip()
    return out


def chromium_major(version):
    """'141.0.7390.54-1' → 141; '2:1snap1-0ubuntu2' (gói chuyển tiếp sang snap) → None."""
    v = version.split(":", 1)[-1]
    m = re.match(r"(\d+)\.\d+\.\d+", v)
    return int(m.group(1)) if m else None


def default_on_versions(root=""):
    """{desktop id: major Chromium} cho app có số phiên bản = phiên bản Chromium (Chrome, Edge,
    Chromium .deb và snap chromium). App khác (Electron, Brave, Vivaldi…) không biết ⇒ vắng."""
    out = {}
    st = _read(root + "/var/lib/dpkg/status")
    if st:
        vers = dpkg_versions(st, set(DEB_PACKAGES.values()))
        for did, pkg in DEB_PACKAGES.items():
            if pkg in vers:
                major = chromium_major(vers[pkg])
                if major:
                    out[did] = major
    snap = _read(root + "/snap/chromium/current/meta/snap.yaml")
    if snap:
        m = re.search(r"^version:\s*'?\"?([0-9.]+)", snap, re.M)
        major = chromium_major(m.group(1)) if m else None
        if major:
            out["chromium_chromium.desktop"] = major
    return out


def kwin_version(run=subprocess.run, which=shutil.which):
    exe = which("kwin_wayland")
    if not exe:
        return None
    try:
        r = run([exe, "--version"], capture_output=True, text=True, timeout=2)
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"(\d+)\.(\d+)", (r.stdout or "") + (r.stderr or ""))
    return (int(m.group(1)), int(m.group(2))) if m else None


def text_input_version(desktop, kwin=None):
    """KWin < 6.7 (còn text-input-v1): v1 như wiki Fcitx khuyên; còn lại v3 (mặc định Chromium)."""
    if "kde" in desktop.lower() and kwin is not None and tuple(kwin) < KWIN_DROPPED_V1:
        return "1"
    return "3"


# ---------------------------------------------------------------- áp dụng được không

def applicability(session, desktop, framework):
    """"ok" | "not_wayland" | "kde_ibus" | "unsupported_desktop" — theo hostOrdersForwardedKeys:
    GNOME Wayland (IBus hoặc Fcitx5) và KDE Wayland + Fcitx5."""
    if (session or "").lower() != "wayland":
        return "not_wayland"
    d = (desktop or "").lower()
    if "gnome" in d:
        return "ok"
    if "kde" in d:
        return "ok" if framework == "fcitx5" else "kde_ibus"
    return "unsupported_desktop"


# ---------------------------------------------------------------- đồng bộ

def _write_atomic(path, text):
    tmp = path + ".viettelex-tmp"
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def owned_files(target):
    """{desktop id: nội dung} các file của ta trong thư mục đích."""
    out = {}
    try:
        names = os.listdir(target)
    except OSError:
        return out
    for n in names:
        p = os.path.join(target, n)
        if not n.endswith(".desktop") or os.path.islink(p) or not os.path.isfile(p):
            continue
        text = _read(p)
        if text is not None and marker_of(text):
            out[n] = text
    return out


def _empty_report():
    return {k: [] for k in ("created", "updated", "removed", "unchanged", "conflicts",
                            "user_configured", "x11", "unsupported", "default_on", "errors")}


def sync(enabled, create_new=True, env=None, dirs=None, flags=None, default_on=None,
         default_on_major=CHROME_DEFAULT_ON_MAJOR, refresh_db=True,
         run=subprocess.run, which=shutil.which):
    """Đưa thư mục `$XDG_DATA_HOME/applications` về đúng trạng thái.

    enabled=False ⇒ xoá mọi file của ta. create_new=False (vd. phiên X11) ⇒ chỉ làm mới/xoá
    file đã có, không tạo thêm. default_on: {desktop id: major} (app đã bật IME Wayland mặc
    định ⇒ bỏ qua). Trả báo cáo: mỗi mục là danh sách (desktop id, tên app[, đường dẫn])."""
    rep = _empty_report()
    target = user_apps_dir(env)
    flags = flags or flags_for()
    ours = owned_files(target)
    wanted = {}
    if enabled:
        srcs = find_sources(dirs if dirs is not None else source_dirs(env))
        skip_default = "%s=3" % TEXT_INPUT_VERSION in flags
        for did, (path, text) in sorted(srcs.items()):
            name = entry_values(text).get("Name", did[:-len(".desktop")])
            major = (default_on or {}).get(did)
            if skip_default and major is not None and major >= default_on_major:
                rep["default_on"].append((did, name))
                continue
            dest = os.path.join(target, did)
            if did not in ours and (os.path.lexists(dest)):
                user_text = _read(dest) or ""
                if ENABLE_IME in user_text:
                    rep["user_configured"].append((did, name, dest))
                else:
                    rep["conflicts"].append((did, name, dest))
                continue
            content, status = build_override(text, flags, path)
            if status in ("x11", "unsupported", "dbus"):
                rep["x11" if status == "x11" else "unsupported"].append((did, name))
                continue
            if content is None:
                continue
            wanted[did] = (name, content)
    changed = False
    for did, text in sorted(ours.items()):
        if did not in wanted:
            try:
                os.remove(os.path.join(target, did))
                rep["removed"].append((did, entry_values(text).get("Name", did)))
                changed = True
            except OSError as e:
                rep["errors"].append((did, str(e)))
    for did, (name, content) in sorted(wanted.items()):
        dest = os.path.join(target, did)
        if did in ours:
            if marker_of(ours[did]) == marker_of(content) and ours[did] == content:
                rep["unchanged"].append((did, name))
                continue
            key = "updated"
        else:
            if not create_new:
                continue
            key = "created"
        try:
            os.makedirs(target, exist_ok=True)
            _write_atomic(dest, content)
            rep[key].append((did, name))
            changed = True
        except OSError as e:
            rep["errors"].append((did, str(e)))
    if changed and refresh_db:
        exe = which("update-desktop-database")
        if exe:
            try:
                run([exe, "-q", target], capture_output=True, timeout=10)
            except (OSError, subprocess.SubprocessError):
                pass     # không bắt buộc: launcher GNOME/KDE tự theo dõi thư mục
    return rep


# ---------------------------------------------------------------- app đang chạy (cần mở lại)

def running_without_flag(entries, proc="/proc"):
    """Trong `entries` [(desktop id, tên, nội dung override)], app nào đang chạy mà tiến trình
    chính KHÔNG mang cờ IME (mở trước khi có override) ⇒ cần thoát hẳn rồi mở lại."""
    progs, taken = {}, set()
    # Một chương trình chỉ báo một lần (code.desktop + code-url-handler.desktop): ưu tiên mục
    # hiện trong menu.
    for did, name, content in sorted(entries, key=lambda e: (
            entry_values(e[2]).get("NoDisplay") == "true", e[0])):
        kind, prog = program_of(entry_values(content).get("Exec", ""))
        if kind and (kind, os.path.basename(prog)) not in taken:
            taken.add((kind, os.path.basename(prog)))
            progs[did] = (name, kind, prog)
    if not progs:
        return []
    seen = {}       # did → đã thấy tiến trình chính có cờ?
    try:
        pids = [p for p in os.listdir(proc) if p.isdigit()]
    except OSError:
        return []
    for pid in pids:
        raw = _read_bytes(os.path.join(proc, pid, "cmdline"))
        if not raw:
            continue
        argv = [a.decode("utf-8", "replace") for a in raw.split(b"\0") if a]
        if not argv or any(a.startswith("--type=") for a in argv):
            continue        # tiến trình con (renderer, gpu…) không mang cờ của người dùng
        cg = None
        for did, (_name, kind, prog) in progs.items():
            hit = False
            if kind == "bin":
                hit = os.path.basename(argv[0]) == os.path.basename(prog)
            else:
                if cg is None:
                    cg = (_read_bytes(os.path.join(proc, pid, "cgroup")) or b"").decode(
                        "utf-8", "replace")
                needle = ("app-flatpak-%s-" % prog) if kind == "flatpak" else ("snap.%s." % prog)
                hit = needle in cg
            if hit:
                seen[did] = seen.get(did, False) or (ENABLE_IME in argv)
    return [(did, progs[did][0]) for did, ok in sorted(seen.items()) if not ok]


def _read_bytes(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None
