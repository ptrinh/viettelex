"""Dò bộ khung gõ (Fcitx5 / IBus) và trạng thái VietTelex — phục vụ màn hình "Bắt đầu".

Tách phần thu thập (collect: đọc /proc, file, gsettings) khỏi phần kết luận
(assess: hàm thuần trên dict) để test được không cần máy có Fcitx5/IBus.
"""

import os
import shutil
import subprocess

FCITX5_ADDON = "viettelex"          # /usr/share/fcitx5/addon/viettelex.conf
IBUS_ENGINE = "viettelex"           # engine name trong /usr/share/ibus/component/viettelex.xml

FCITX5_ADDON_FILES = ("/usr/share/fcitx5/addon/viettelex.conf",)
IBUS_COMPONENT_FILES = ("/usr/share/ibus/component/viettelex.xml",)

# Bộ gõ Việt khác — bật cùng lúc dễ gõ đúp (spec §6: không can thiệp, chỉ báo).
OTHER_VN_IMS = {
    "/usr/share/ibus/component/unikey.xml": "ibus-unikey",
    "/usr/share/ibus/component/bamboo.xml": "ibus-bamboo",
    "/usr/share/fcitx5/addon/unikey.conf": "fcitx5-unikey",
    "/usr/share/fcitx5/addon/bamboo.conf": "fcitx5-bamboo",
}


def _running(names):
    found = set()
    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        return found
    for pid in pids:
        try:
            with open("/proc/%s/comm" % pid) as f:
                comm = f.read().strip()
        except OSError:
            continue
        if comm in names:
            found.add(comm)
    return found


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def _gsettings(schema, key):
    if not shutil.which("gsettings"):
        return ""
    try:
        r = subprocess.run(["gsettings", "get", schema, key], capture_output=True,
                           text=True, timeout=2)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def fcitx5_profile_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "fcitx5", "profile")


def collect():
    """Ảnh chụp môi trường (chỉ đọc, không sửa gì)."""
    running = _running({"fcitx5", "ibus-daemon"})
    xinputrc = _read(os.path.expanduser("~/.xinputrc"))
    return {
        "fcitx5_installed": bool(shutil.which("fcitx5")),
        "ibus_installed": bool(shutil.which("ibus-daemon") or shutil.which("ibus")),
        "fcitx5_running": "fcitx5" in running,
        "ibus_running": "ibus-daemon" in running,
        "fcitx5_addon": any(os.path.exists(p) for p in FCITX5_ADDON_FILES),
        "ibus_component": any(os.path.exists(p) for p in IBUS_COMPONENT_FILES),
        "fcitx5_profile": _read(fcitx5_profile_path()),
        "ibus_preload": _gsettings("org.freedesktop.ibus.general", "preload-engines"),
        "gnome_sources": _gsettings("org.gnome.desktop.input-sources", "sources"),
        "env": {k: os.environ.get(k, "") for k in (
            "GTK_IM_MODULE", "QT_IM_MODULE", "XMODIFIERS", "XDG_SESSION_TYPE",
            "XDG_CURRENT_DESKTOP")},
        "xinputrc": xinputrc,
        "other_vn": sorted(n for p, n in OTHER_VN_IMS.items() if os.path.exists(p)),
        "has_configtool": bool(shutil.which("fcitx5-configtool")),
        "has_gnome_settings": bool(shutil.which("gnome-control-center")),
        "has_ibus_setup": bool(shutil.which("ibus-setup")),
    }


def _fcitx5_enabled(profile):
    """~/.config/fcitx5/profile có mục `Name=viettelex` trong một Groups/*/Items/*."""
    for line in profile.splitlines():
        k, _, v = line.partition("=")
        if k.strip() == "Name" and v.strip() == FCITX5_ADDON:
            return True
    return False


def _ibus_enabled(preload, gnome_sources):
    return ("'%s'" % IBUS_ENGINE) in preload or ("('ibus', '%s')" % IBUS_ENGINE) in gnome_sources


def active_framework(snap):
    """Framework mà app đang dùng: 'fcitx5' | 'ibus' | None (theo env, rồi im-config, rồi process)."""
    env = snap.get("env", {})
    vals = [env.get("GTK_IM_MODULE", ""), env.get("QT_IM_MODULE", ""),
            env.get("XMODIFIERS", "")]
    joined = " ".join(v.lower() for v in vals)
    if "fcitx" in joined:
        return "fcitx5"
    if "ibus" in joined:
        return "ibus"
    rc = snap.get("xinputrc", "")
    for line in rc.splitlines():
        s = line.strip()
        if s.startswith("run_im"):
            if "fcitx" in s:
                return "fcitx5"
            if "ibus" in s:
                return "ibus"
    if snap.get("fcitx5_running"):
        return "fcitx5"
    if snap.get("ibus_running"):
        return "ibus"
    return None


def assess(snap):
    """Kết luận cho UI: framework, từng bước đã xong chưa, cảnh báo."""
    fw = active_framework(snap)
    if fw is None:
        # Chưa có gì chạy: ưu tiên cái đã cài VietTelex (Fcitx5 trước — quyết định đã chốt).
        if snap.get("fcitx5_addon"):
            fw = "fcitx5"
        elif snap.get("ibus_component"):
            fw = "ibus"
    installed = {
        "fcitx5": snap.get("fcitx5_addon", False),
        "ibus": snap.get("ibus_component", False),
    }
    enabled = {
        "fcitx5": _fcitx5_enabled(snap.get("fcitx5_profile", "")),
        "ibus": _ibus_enabled(snap.get("ibus_preload", ""), snap.get("gnome_sources", "")),
    }
    running = {"fcitx5": snap.get("fcitx5_running", False),
               "ibus": snap.get("ibus_running", False)}
    warnings = []
    if snap.get("other_vn"):
        warnings.append("other_vn")
    if snap.get("env", {}).get("XDG_SESSION_TYPE", "").lower() == "wayland":
        warnings.append("wayland_chromium")
    if fw == "ibus" and snap.get("fcitx5_running") and snap.get("ibus_running"):
        warnings.append("both_running")
    ok = bool(fw) and installed.get(fw, False) and running.get(fw, False) and enabled.get(fw, False)
    return {
        "framework": fw,
        "installed": installed,
        "enabled": enabled,
        "running": running,
        "ok": ok,
        "warnings": warnings,
        "other_vn": snap.get("other_vn", []),
    }

