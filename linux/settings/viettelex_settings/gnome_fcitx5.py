"""Dùng Fcitx5 thay IBus trên GNOME (cấu hình theo người dùng, không cần root).

im-config không có tác dụng trên GNOME: gnome-shell tự chạy ibus-daemon, và trên Ubuntu
26.04 im-launch.desktop chỉ là Exec=/usr/bin/true ⇒ "im-config -n fcitx5" + đăng nhập lại
vẫn là IBus. Cách làm được (thử trên Ubuntu 26.04 GNOME Wayland, 10/2026):

  1. ~/.config/autostart/org.fcitx.Fcitx5.desktop — Fcitx5 tự chạy khi đăng nhập; nó thế
     chỗ ibus-daemon (frontend ibus của Fcitx5 phục vụ gnome-shell) và GNOME hiện icon
     Vᴛ/E của VietTelex trên thanh trên cùng.
  2. ~/.config/environment.d/90-viettelex-fcitx5.conf — GTK_IM_MODULE=fcitx… để app GTK
     (Firefox, Ptyxis, Text Editor…) nói chuyện thẳng với Fcitx5 qua fcitx5-gtk thay vì
     text-input-v3 của gnome-shell (gnome-shell bỏ attr ⇒ luôn gạch chân).
  3. ~/.config/fcitx5/profile có VietTelex — chỉ khi chưa có profile (không đè cấu hình cũ).

Đăng xuất/đăng nhập lại một lần. disable() gỡ đúng những file do đây tạo ra.
Chạy không cần GTK: viettelex-settings --use-fcitx5 | --use-ibus (install.sh gọi).
"""

import os

ENV_NAME = "90-viettelex-fcitx5.conf"
ENV_VARS = (
    ("GTK_IM_MODULE", "fcitx"),
    ("QT_IM_MODULE", "fcitx"),
    ("QT_IM_MODULES", "wayland;fcitx;ibus"),
    ("XMODIFIERS", "@im=fcitx"),
)
AUTOSTART_NAME = "org.fcitx.Fcitx5.desktop"
AUTOSTART_SOURCES = ("/usr/share/applications/org.fcitx.Fcitx5.desktop",
                     "/etc/xdg/autostart/org.fcitx.Fcitx5.desktop")
MARK = "X-VietTelex-Managed=true"
FALLBACK_DESKTOP = ("[Desktop Entry]\nType=Application\nName=Fcitx 5\nExec=fcitx5\n"
                    "Icon=fcitx\nNoDisplay=true\n")
PROFILE = ("[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=viettelex\n\n"
           "[Groups/0/Items/0]\nName=keyboard-us\nLayout=\n\n"
           "[Groups/0/Items/1]\nName=viettelex\nLayout=\n\n"
           "[GroupOrder]\n0=Default\n")


def _config_home(env=None):
    env = os.environ if env is None else env
    return env.get("XDG_CONFIG_HOME") or os.path.join(env.get("HOME") or os.path.expanduser("~"),
                                                       ".config")


def paths(env=None):
    base = _config_home(env)
    return {
        "env": os.path.join(base, "environment.d", ENV_NAME),
        "autostart": os.path.join(base, "autostart", AUTOSTART_NAME),
        "profile": os.path.join(base, "fcitx5", "profile"),
    }


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def env_content():
    return "# VietTelex: Fcitx5 thay IBus trên GNOME (xoá file này = quay về IBus)\n" + "".join(
        "%s=%s\n" % kv for kv in ENV_VARS)


def autostart_content(sources=AUTOSTART_SOURCES):
    """Bản .desktop của Fcitx5 + dấu MARK (để disable() chỉ xoá file mình tạo)."""
    text = next((t for t in map(_read, sources) if t), FALLBACK_DESKTOP)
    lines = [ln for ln in text.splitlines() if not ln.startswith(("Hidden=", "X-GNOME-Autostart-enabled="))]
    out, inserted = [], False
    for ln in lines:
        out.append(ln)
        if not inserted and ln.strip() == "[Desktop Entry]":
            out.append(MARK)
            inserted = True
    if not inserted:
        out = ["[Desktop Entry]", MARK] + out
    return "\n".join(out) + "\n"


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def is_enabled(env=None):
    p = paths(env)
    return _read(p["env"]) is not None and MARK in (_read(p["autostart"]) or "")


def enable(env=None, sources=AUTOSTART_SOURCES):
    """Ghi 3 file; trả danh sách file đã ghi. Autostart sẵn có của người dùng thì giữ nguyên."""
    p = paths(env)
    written = []
    _write(p["env"], env_content())
    written.append(p["env"])
    if _read(p["autostart"]) is None:
        _write(p["autostart"], autostart_content(sources))
        written.append(p["autostart"])
    if _read(p["profile"]) is None:
        _write(p["profile"], PROFILE)
        written.append(p["profile"])
    return written


def disable(env=None):
    """Xoá file env + autostart do enable() tạo (profile Fcitx5 giữ nguyên). Trả file đã xoá."""
    p = paths(env)
    removed = []
    for key in ("env", "autostart"):
        text = _read(p[key])
        if text is None or (key == "autostart" and MARK not in text):
            continue
        try:
            os.remove(p[key])
            removed.append(p[key])
        except OSError:
            pass
    return removed


def main(argv):
    if argv and argv[0] == "--use-fcitx5":
        for f in enable():
            print(f)
        print("Fcitx5 sẽ chạy thay IBus từ lần đăng nhập sau — đăng xuất rồi đăng nhập lại.")
        return 0
    if argv and argv[0] == "--use-ibus":
        for f in disable():
            print(f)
        print("Quay về IBus từ lần đăng nhập sau — đăng xuất rồi đăng nhập lại.")
        return 0
    return 2
