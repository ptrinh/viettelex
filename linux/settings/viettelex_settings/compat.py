"""Tương thích ứng dụng — dò các app/môi trường hay mất bộ gõ và gợi ý cách sửa.

Tách thu thập (collect: đọc env + filesystem qua hàm tiêm vào) khỏi kết luận
(assess: hàm thuần trên dict) để unit test không cần máy Linux thật.
Mỗi cảnh báo: {"id", "level" ("warn"|"info"), "title", "body", "fix"} — fix là
lệnh/đoạn cấu hình copy được (có thể rỗng).
"""

import glob
import os
import shutil

WAYLAND_IME_FLAGS = "--enable-wayland-ime --wayland-text-input-version=3"
WAYLAND_IME_FLAGS_KDE = "--enable-wayland-ime --wayland-text-input-version=1"  # KWin: text-input-v1
X11_FLAG = "--ozone-platform=x11"
JETBRAINS_OPT = "-Drecreate.x11.input.method=true"

# Chrome ≥140 / Electron ≥38 mặc định chạy Wayland gốc → mất IME nếu thiếu cờ.
# (id, tên, lệnh, file .desktop, flatpak id, file cờ ~/.config/<x>-flags.conf)
CHROMIUM_APPS = (
    ("chrome", "Google Chrome", ("google-chrome", "google-chrome-stable"),
     ("google-chrome.desktop",), "com.google.Chrome", "chrome-flags.conf"),
    ("chromium", "Chromium", ("chromium", "chromium-browser"),
     ("chromium.desktop", "chromium-browser.desktop", "chromium_chromium.desktop"),
     "org.chromium.Chromium", "chromium-flags.conf"),
    ("code", "VS Code", ("code",), ("code.desktop", "code_code.desktop"),
     "com.visualstudio.code", "code-flags.conf"),
    ("slack", "Slack", ("slack",), ("slack.desktop", "slack_slack.desktop"),
     "com.slack.Slack", None),
    ("discord", "Discord", ("discord",), ("discord.desktop", "discord_discord.desktop"),
     "com.discordapp.Discord", None),
)

TERMINALS = ("gnome-terminal", "kgx", "ptyxis", "konsole", "kitty", "alacritty", "wezterm",
             "foot", "xterm", "tilix", "terminator", "tmux")


def desktop_dirs(home):
    return (
        "/usr/share/applications",
        "/usr/local/share/applications",
        "/var/lib/snapd/desktop/applications",
        "/var/lib/flatpak/exports/share/applications",
        os.path.join(home, ".local/share/flatpak/exports/share/applications"),
        os.path.join(home, ".local/share/applications"),
    )


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def _has_ime_flag(text):
    return "enable-wayland-ime" in text or "ozone-platform=x11" in text


def _os_version(os_release):
    for line in os_release.splitlines():
        k, _, v = line.partition("=")
        if k.strip() == "VERSION_ID":
            return v.strip().strip('"')
    return ""


def collect(env=None, home=None, exists=os.path.exists, read=_read, which=shutil.which,
            globber=glob.glob, framework=None):
    """Ảnh chụp (chỉ đọc). Mọi truy cập hệ thống qua tham số → test tiêm được."""
    env = os.environ if env is None else env
    home = home or env.get("HOME") or os.path.expanduser("~")
    xdg_config = env.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    dirs = desktop_dirs(home)
    user_apps = os.path.join(home, ".local/share/applications")

    def find_desktop(names):
        for d in dirs:
            for n in names:
                p = os.path.join(d, n)
                if exists(p):
                    return p
        return ""

    apps = {}
    for aid, name, bins, desktops, flatpak, flags_file in CHROMIUM_APPS:
        desk = find_desktop(desktops + (flatpak + ".desktop",))
        if not desk and not any(which(b) for b in bins):
            continue
        configured = False
        if flags_file and _has_ime_flag(read(os.path.join(xdg_config, flags_file))):
            configured = True
        for n in desktops:
            if _has_ime_flag(read(os.path.join(user_apps, n))):
                configured = True
        if desk.startswith("/var/lib/snapd/"):
            kind = "snap"
        elif "flatpak" in desk:
            kind = "flatpak"
        else:
            kind = "deb"
        apps[aid] = {"name": name, "desktop": desk, "kind": kind, "configured": configured,
                     "flags_file": flags_file or ""}

    jb_desktops = []
    for d in dirs:
        jb_desktops += globber(os.path.join(d, "jetbrains-*.desktop"))
        jb_desktops += globber(os.path.join(d, "*intellij*.desktop"))
        jb_desktops += globber(os.path.join(d, "*pycharm*.desktop"))
    jb_vmoptions = globber(os.path.join(xdg_config, "JetBrains", "*", "*.vmoptions"))
    jetbrains = bool(jb_desktops or jb_vmoptions
                     or exists(os.path.join(home, ".local/share/JetBrains/Toolbox")))
    jetbrains_configured = any(JETBRAINS_OPT in read(p) for p in jb_vmoptions)

    snap_apps = globber("/var/lib/snapd/desktop/applications/*.desktop")
    qt5 = bool(globber("/usr/lib/*/libQt5Gui.so.5*") or globber("/usr/lib/libQt5Gui.so.5*"))

    return {
        "session": (env.get("XDG_SESSION_TYPE") or
                    ("wayland" if env.get("WAYLAND_DISPLAY") else "")).lower(),
        "desktop": env.get("XDG_CURRENT_DESKTOP", ""),
        "framework": framework,
        "os_version": _os_version(read("/etc/os-release")),
        "apps": apps,
        "kitty": bool(which("kitty") or find_desktop(("kitty.desktop",))),
        "glfw_im_module": env.get("GLFW_IM_MODULE", ""),
        "jetbrains": jetbrains,
        "jetbrains_configured": jetbrains_configured,
        "rofi": bool(which("rofi")),
        "snap_apps": bool(snap_apps),
        "fcitx5_installed": bool(which("fcitx5")),
        "ibus_installed": bool(which("ibus-daemon") or which("ibus")),
        "fcitx5_addon": exists("/usr/share/fcitx5/addon/viettelex.conf"),
        "xinputrc": read(os.path.join(home, ".xinputrc")),
        "qt5": qt5,
        "qt_im_module": env.get("QT_IM_MODULE", ""),
        "terminals": sorted(t for t in TERMINALS if which(t)) + (["code"] if "code" in apps else []),
    }


def _is_gnome(desktop):
    return "gnome" in desktop.lower()


def _is_kde(desktop):
    return "kde" in desktop.lower()


def im_config_mode(xinputrc):
    """Chế độ im-config của user: 'auto' khi chưa chọn (không có ~/.xinputrc / run_im auto|default)."""
    for line in xinputrc.splitlines():
        s = line.strip()
        if s.startswith("run_im"):
            parts = s.split()
            mode = parts[1] if len(parts) > 1 else ""
            return "auto" if mode in ("", "auto", "default") else mode
    return "auto"


def chromium_fix(apps, desktop):
    """Lệnh copy được cho các app Chromium/Electron chưa cấu hình."""
    flags = WAYLAND_IME_FLAGS_KDE if _is_kde(desktop) else WAYLAND_IME_FLAGS
    lines = ["# Chạy thử một lần:"]
    first = next(iter(apps.values()))
    exe = {"Google Chrome": "google-chrome", "Chromium": "chromium", "VS Code": "code",
           "Slack": "slack", "Discord": "discord"}[first["name"]]
    lines.append("%s %s" % (exe, flags))
    lines.append("")
    ff = [a for a in apps.values() if a["flags_file"] and a["kind"] == "deb"]
    if ff:
        lines.append("# Cố định, cách A — file cờ (app đọc khi khởi động):")
    for a in ff:
        lines.append("printf -- '%s\\n' >> ~/.config/%s" % (
            "\\n".join(flags.split()), a["flags_file"]))
    desk = [a for a in apps.values() if a["kind"] == "deb" and a["desktop"].startswith("/usr/")]
    if desk:
        lines.append("# Cố định, cách B — sửa dòng Exec của file .desktop (mọi app):")
        lines.append("mkdir -p ~/.local/share/applications")
        for a in desk:
            base = os.path.basename(a["desktop"])
            lines.append("sed 's|^Exec=\\([^ ]*\\)|Exec=\\1 %s|' %s > ~/.local/share/applications/%s"
                         % (flags, a["desktop"], base))
    others = [a["name"] for a in apps.values() if a["kind"] != "deb"]
    if others:
        lines.append("# %s (snap/flatpak): thêm cờ trên vào dòng Exec= của file .desktop" %
                     ", ".join(others))
    lines.append("")
    lines.append("# Hoặc chạy qua XWayland (chắc ăn nhất):  … %s" % X11_FLAG)
    return "\n".join(lines)


def assess(snap):
    """Danh sách cảnh báo áp dụng cho máy này (rỗng = không có gì cần lưu ý)."""
    out = []
    session = snap.get("session", "")
    desktop = snap.get("desktop", "")
    fw = snap.get("framework")
    wayland = session == "wayland"
    x11 = session == "x11"

    todo = {k: v for k, v in snap.get("apps", {}).items() if not v.get("configured")}
    if wayland and todo:
        names = ", ".join(a["name"] for a in todo.values())
        body = ("Chrome ≥ 140 và app Electron ≥ 38 mặc định chạy Wayland gốc và không nhận bộ gõ "
                "nếu thiếu cờ %s." % (WAYLAND_IME_FLAGS_KDE if _is_kde(desktop) else WAYLAND_IME_FLAGS))
        if _is_gnome(desktop):
            body += " Cờ này chạy tốt với GNOME + IBus."
        body += " Cách khác: %s (chạy qua XWayland)." % X11_FLAG
        out.append({"id": "chromium_wayland", "level": "warn",
                    "title": "%s: cần cờ bật bộ gõ trên Wayland" % names,
                    "body": body, "fix": chromium_fix(todo, desktop)})

    if x11 and snap.get("kitty") and snap.get("glfw_im_module", "").lower() != "ibus":
        out.append({"id": "kitty_x11", "level": "warn",
                    "title": "kitty: cần GLFW_IM_MODULE=ibus",
                    "body": "Trên X11, kitty chỉ nhận bộ gõ khi có biến này (dùng cho cả IBus lẫn "
                            "Fcitx5). Đăng nhập lại sau khi thêm.",
                    "fix": "echo 'export GLFW_IM_MODULE=ibus' >> ~/.profile"})

    if x11 and snap.get("jetbrains") and not snap.get("jetbrains_configured"):
        out.append({"id": "jetbrains_x11", "level": "warn",
                    "title": "JetBrains IDE: thêm tuỳ chọn JVM",
                    "body": "Trên X11, IntelliJ/PyCharm… có thể mất bộ gõ sau khi đổi cửa sổ. "
                            "Help → Edit Custom VM Options…, thêm dòng dưới rồi khởi động lại IDE.",
                    "fix": JETBRAINS_OPT})

    if snap.get("rofi"):
        out.append({"id": "rofi", "level": "info",
                    "title": "rofi không hỗ trợ bộ gõ",
                    "body": "rofi không gõ được tiếng Việt có dấu. Dùng Ulauncher hoặc KRunner "
                            "(KDE) nếu cần tìm bằng tiếng Việt.", "fix": ""})

    if _is_gnome(desktop):
        out.append({"id": "gnome_overview", "level": "info",
                    "title": "Ô tìm kiếm Tổng quan GNOME có thể mất chữ đầu",
                    "body": "Gõ ngay khi vừa mở Tổng quan, chữ đầu tiên có thể bị rơi (lỗi IBus "
                            "upstream ibus#2246). Mở Tổng quan, chờ một nhịp rồi gõ.", "fix": ""})

    if fw == "fcitx5" and snap.get("os_version") == "22.04" and snap.get("snap_apps"):
        out.append({"id": "snap_fcitx5_jammy", "level": "warn",
                    "title": "App Snap + Fcitx5 trên Ubuntu 22.04",
                    "body": "Trên 22.04, app dạng Snap (Firefox, Chromium…) thường không nhận "
                            "Fcitx5. Dùng IBus (viettelex-ibus), hoặc cài bản .deb/Flatpak của app.",
                    "fix": "sudo apt install viettelex-ibus && im-config -n ibus"})

    if (not _is_gnome(desktop) and snap.get("fcitx5_installed") and snap.get("ibus_installed")
            and snap.get("fcitx5_addon") and im_config_mode(snap.get("xinputrc", "")) == "auto"):
        out.append({"id": "imconfig_auto", "level": "warn",
                    "title": "im-config đang để tự động: IBus sẽ thắng Fcitx5",
                    "body": "Máy có cả IBus lẫn Fcitx5; ngoài GNOME, im-config chế độ auto chọn "
                            "IBus. Muốn dùng VietTelex qua Fcitx5 thì chọn hẳn Fcitx5 rồi đăng "
                            "nhập lại.",
                    "fix": "im-config -n fcitx5"})

    if wayland and snap.get("qt5") and not snap.get("qt_im_module"):
        mod = "ibus" if fw == "ibus" else "fcitx"
        out.append({"id": "qt5_wayland", "level": "warn",
                    "title": "App Qt5 trên Wayland: thiếu QT_IM_MODULE",
                    "body": "App Qt5 chạy Wayland gốc không có bộ gõ nếu thiếu QT_IM_MODULE. "
                            "Qt ≥ 6.8.2 đọc QT_IM_MODULES (danh sách thử lần lượt). Đăng nhập "
                            "lại sau khi thêm.",
                    "fix": "mkdir -p ~/.config/environment.d\n"
                           "printf 'QT_IM_MODULE=%s\\nQT_IM_MODULES=wayland;%s\\n' "
                           ">> ~/.config/environment.d/90-viettelex.conf" %
                           (mod, "fcitx;ibus" if mod == "fcitx" else "ibus")})

    if snap.get("terminals"):
        out.append({"id": "terminal_preedit", "level": "info",
                    "title": "Terminal luôn gõ có gạch chân",
                    "body": "Trong terminal (kể cả terminal của VS Code, tmux, ssh) VietTelex luôn "
                            "dùng preedit — chữ gạch chân đến khi chốt từ. Đây là chủ đích: "
                            "terminal không cho sửa ngược chữ đã gửi.", "fix": ""})
    return out
