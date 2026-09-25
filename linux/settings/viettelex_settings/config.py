"""config.toml — đọc/ghi đúng tập con TOML của linux/common/SETTINGS.md.

Không phụ thuộc thư viện ngoài (Ubuntu 22.04 có Python 3.10, chưa có tomllib).
Hàm thuần (parse/dump) tách riêng để test không cần GTK.

Ghi nguyên tử: config.toml.tmp → rename() (frontend theo dõi thư mục bằng inotify).
Key lạ (bản frontend mới hơn thêm vào) được GIỮ NGUYÊN khi ghi lại.
"""

import os

# Mặc định chính xác theo SETTINGS.md §2 (= bản macOS 1.7.12).
DEFAULTS = {
    "typing": {
        "input_method": "telex",
        "simple_telex": False,
        "free_marking": True,
        "modern_tone": False,
        "quick_telex": False,
        "spell_check": True,
        "auto_restore": True,
        "teencode": False,
        "contextual_english": True,
        "collision_prefers_vietnamese": True,
        "bracket_vowels": False,
        "shortcuts_enabled": True,
    },
    "general": {
        "display_mode": "preedit",
        "toggle_hotkey": "Ctrl+space",
        "per_app_state": True,
        "default_vietnamese": True,
    },
    "app_modes": {},
}

SECTION_ORDER = ["typing", "general", "app_modes"]
APP_MODES = ("preedit", "surrounding", "off")
INPUT_METHODS = ("telex", "vni")
DISPLAY_MODES = ("preedit", "surrounding")


def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "viettelex")


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "viettelex")


# ---------------------------------------------------------------- parsing

def _unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(n, "\\" + n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _escape(s):
    return (s.replace("\\", "\\\\").replace('"', '\\"')
             .replace("\n", "\\n").replace("\t", "\\t"))


def _read_string(text, i):
    """text[i] == '"'. Trả (chuỗi, vị trí sau dấu đóng) hoặc (None, i) nếu hỏng."""
    j = i + 1
    while j < len(text):
        if text[j] == "\\":
            j += 2
            continue
        if text[j] == '"':
            return _unescape(text[i + 1:j]), j + 1
        j += 1
    return None, i


def _parse_value(raw):
    raw = raw.strip()
    if raw.startswith('"'):
        val, end = _read_string(raw, 0)
        if val is None:
            return None
        rest = raw[end:].strip()
        if rest and not rest.startswith("#"):
            return None
        return val
    raw = raw.split("#", 1)[0].strip()
    if raw == "true":
        return True
    if raw == "false":
        return False
    try:
        return int(raw)
    except ValueError:
        return None


def parse(text):
    """Trả {section: {key: value}}. Dòng hỏng bị bỏ qua (không raise)."""
    data = {}
    section = ""
    for line in text.split("\n"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("["):
            end = s.find("]")
            if end > 1:
                section = s[1:end].strip()
                data.setdefault(section, {})
            continue
        if s.startswith('"'):
            key, end = _read_string(s, 0)
            if key is None:
                continue
            rest = s[end:].lstrip()
        else:
            eq = s.find("=")
            if eq <= 0:
                continue
            key, rest = s[:eq].strip(), s[eq:]
        if not rest.startswith("="):
            continue
        val = _parse_value(rest[1:])
        if val is None or not key:
            continue
        data.setdefault(section, {})[key] = val
    return data


def _fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    return '"' + _escape(str(v)) + '"'


def dump(data):
    """Ghi theo thứ tự cố định; section/key lạ nối sau (giữ nguyên, không mất)."""
    out = ["# VietTelex — cài đặt (ghi bởi viettelex-settings; xem linux/common/SETTINGS.md)"]
    sections = [s for s in SECTION_ORDER if s in data or s in DEFAULTS]
    sections += sorted(s for s in data if s not in SECTION_ORDER and s)
    for sec in sections:
        values = data.get(sec, {})
        out.append("")
        out.append("[%s]" % sec)
        if sec == "app_modes":
            for k in sorted(values):
                out.append('"%s" = %s' % (_escape(k), _fmt(values[k])))
            continue
        order = list(DEFAULTS.get(sec, {}))
        order += sorted(k for k in values if k not in order)
        for k in order:
            if k in values:
                out.append("%s = %s" % (k, _fmt(values[k])))
    return "\n".join(out) + "\n"


def normalize(data):
    """Điền mặc định + loại giá trị sai kiểu (giống frontend: sai kiểu → mặc định)."""
    out = {sec: dict(vals) for sec, vals in data.items() if isinstance(vals, dict)}
    for sec, vals in DEFAULTS.items():
        cur = out.setdefault(sec, {})
        for k, dv in vals.items():
            v = cur.get(k)
            if type(v) is not type(dv):
                cur[k] = dv
    t, g = out["typing"], out["general"]
    if t["input_method"] not in INPUT_METHODS:
        t["input_method"] = "telex"
    if g["display_mode"] not in DISPLAY_MODES:
        g["display_mode"] = "preedit"
    out["app_modes"] = {k: v for k, v in out["app_modes"].items()
                        if isinstance(v, str) and v in APP_MODES and k.strip()}
    return out


def atomic_write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


class Config:
    """Mô hình trong bộ nhớ + lưu ngay (frontend áp tức thì qua inotify)."""

    def __init__(self, path=None):
        self.path = path or os.path.join(config_dir(), "config.toml")
        self.data = normalize({})
        self.load()

    def load(self):
        try:
            with open(self.path, encoding="utf-8") as f:
                self.data = normalize(parse(f.read()))
        except (OSError, UnicodeDecodeError):
            self.data = normalize({})

    def get(self, section, key):
        return self.data[section][key]

    def set(self, section, key, value):
        if self.data.setdefault(section, {}).get(key) == value:
            return
        self.data[section][key] = value
        self.save()

    def set_app_mode(self, app, mode):
        app = app.strip().lower()
        if not app:
            return
        modes = self.data["app_modes"]
        if mode in APP_MODES:
            modes[app] = mode
        else:            # "auto" = bỏ ghi đè
            modes.pop(app, None)
        self.save()

    def save(self):
        atomic_write(self.path, dump(self.data))


# ---------------------------------------------------------------- hotkey (§4)

MODIFIERS = ("Ctrl", "Alt", "Shift", "Super")


def normalize_hotkey(text):
    """'ctrl + Space' → 'Ctrl+space'. Trả None nếu không hợp lệ; '' = tắt."""
    text = text.strip()
    if not text:
        return ""
    parts = [p.strip() for p in text.split("+")]
    if len(parts) < 2 or any(not p for p in parts):
        return None
    mods, key = parts[:-1], parts[-1]
    canon = []
    for m in mods:
        mm = {"control": "Ctrl", "ctl": "Ctrl", "win": "Super", "meta": "Super"}.get(
            m.lower(), m.capitalize())
        if mm not in MODIFIERS or mm in canon:
            return None
        canon.append(mm)
    canon.sort(key=MODIFIERS.index)
    if len(key) == 1:
        key = key.lower()
    elif key.lower() == "space":
        key = "space"
    if canon == ["Super"] and key == "space":
        return None       # GNOME dùng Super+Space — hợp đồng cấm
    return "+".join(canon + [key])
