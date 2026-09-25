"""config.toml — đọc/ghi đúng tập con TOML của linux/common/SETTINGS.md.

Không phụ thuộc thư viện ngoài (Ubuntu 22.04 có Python 3.10, chưa có tomllib).
Hàm thuần (parse/dump) tách riêng để test không cần GTK.

Ghi nguyên tử: config.toml.tmp → rename() (frontend theo dõi thư mục bằng inotify).
Ghi TẠI CHỖ (SETTINGS.md "Ghi chung file"): hộp cấu hình Fcitx5 cũng ghi file này, nên mỗi
lần đổi chỉ nạp lại file rồi sửa đúng dòng của key vừa đổi — comment, thứ tự và key lạ
giữ nguyên (update_text).
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
        "re_edit_word": True,
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


def _line_key(s):
    """Dòng `key = value` (đã strip) → (key, phần sau '='), hoặc (None, None)."""
    if s.startswith('"'):
        key, end = _read_string(s, 0)
        rest = s[end:].lstrip() if key is not None else ""
    else:
        eq = s.find("=")
        key, rest = (s[:eq].strip(), s[eq:]) if eq > 0 else (None, "")
    if not key or not rest.startswith("="):
        return None, None
    return key, rest[1:]


def _trailing_comment(raw_value):
    """Phần `# …` sau giá trị (bỏ qua # nằm trong chuỗi)."""
    v = raw_value.lstrip()
    if v.startswith('"'):
        val, end = _read_string(v, 0)
        tail = v[end:] if val is not None else ""
    else:
        i = v.find("#")
        tail = v[i:] if i >= 0 else ""
    i = tail.find("#")
    return tail[i:] if i >= 0 else ""


def _key_text(section, key):
    return '"%s"' % _escape(key) if section == "app_modes" else key


def update_text(text, changes):
    """Áp `changes` {(section, key): value | None(xoá)} lên nội dung file, sửa tại chỗ.

    Dòng khác (comment, key lạ, section lạ) giữ nguyên từng byte. Key chưa có thì thêm
    vào cuối section của nó (tạo section ở cuối file nếu chưa có)."""
    lines = text.split("\n") if text else []
    if lines and lines[-1] == "":
        lines.pop()
    pending = dict(changes)
    out, section, sec_end = [], "", {}
    for line in lines:
        s = line.strip()
        if s.startswith("[") and s.find("]") > 1:
            section = s[1:s.find("]")].strip()
            out.append(line)
            sec_end[section] = len(out)
            continue
        key, raw = (None, None) if not s or s.startswith("#") else _line_key(s)
        if key is not None and (section, key) in pending:
            v = pending.pop((section, key))
            if v is None:
                continue
            indent = line[:len(line) - len(line.lstrip())]
            comment = _trailing_comment(raw)
            newline = "%s%s = %s" % (indent, _key_text(section, key), _fmt(v))
            out.append(newline + ("  " + comment if comment else ""))
        else:
            out.append(line)
        if section in sec_end and s:
            sec_end[section] = len(out)
    # Key mới: chèn sau dòng không trống cuối cùng của section (giữ dòng trống ngăn cách).
    by_sec = {}
    for (sec, key), v in pending.items():
        if v is not None:
            by_sec.setdefault(sec, []).append((key, v))
    for sec in sorted(by_sec, key=lambda x: -sec_end.get(x, -1)):
        new = ["%s = %s" % (_key_text(sec, k), _fmt(v)) for k, v in sorted(by_sec[sec])]
        if sec in sec_end:
            at = sec_end[sec]
            out[at:at] = new
        else:
            if out and out[-1].strip():
                out.append("")
            out.append("[%s]" % sec)
            out += new
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

    def _read_text(self):
        try:
            with open(self.path, encoding="utf-8") as f:
                return f.read()
        except (OSError, UnicodeDecodeError):
            return ""

    def apply(self, changes):
        """Nạp lại file (có thể vừa bị hộp cấu hình Fcitx5 sửa), sửa đúng các key đổi, ghi."""
        text = self._read_text()
        self.data = normalize(parse(text))
        atomic_write(self.path, update_text(text, changes))
        for (sec, key), v in changes.items():
            if v is None:
                self.data.setdefault(sec, {}).pop(key, None)
            else:
                self.data.setdefault(sec, {})[key] = v

    def set(self, section, key, value):
        if self.data.setdefault(section, {}).get(key) == value:
            return
        self.apply({(section, key): value})

    def set_app_mode(self, app, mode):
        self.set_app_modes({app: mode})

    def set_app_modes(self, modes):
        """{app: mode}; mode ngoài APP_MODES ("auto") = bỏ ghi đè."""
        changes = {}
        for app, mode in modes.items():
            app = app.strip().lower()
            if app:
                changes[("app_modes", app)] = mode if mode in APP_MODES else None
        if changes:
            self.apply(changes)


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
