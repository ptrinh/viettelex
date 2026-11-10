"""shortcuts.yml + nhập/xuất — port 1:1 ShortcutImporter của macOS (App/Sources/AppState.swift).

Cùng parser dùng cho bảng cơ chế gõ (app: mode), như macOS. Khoá chứa ":" (hoặc mở đầu
# ; // " ') được ghi trong ngoặc kép; value trong ngoặc kép được escape (\\\\ \\" \\n) —
file do macOS/iOS/Android ghi đọc được ở đây và ngược lại; file cũ không ngoặc vẫn đọc như cũ.
"""

import json
import os

from .config import atomic_write, config_dir

HEADER = "# VietTelex — bảng gõ tắt"

# Swift CharacterSet.whitespaces ≈ khoảng trắng ngang (không gồm xuống dòng).
_WS = " \t\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000"


def shortcuts_path():
    return os.path.join(config_dir(), "shortcuts.yml")


def _escape(s):
    return (s.replace("\\", "\\\\").replace('"', '\\"')
            .replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n"))


def _unescape(s):
    if "\\" not in s:
        return s
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        i += 1
        if c != "\\":
            out.append(c)
            continue
        if i >= len(s):
            out.append("\\")
            break
        n = s[i]
        i += 1
        out.append({"n": "\n", "t": "\t", "\\": "\\", '"': '"'}.get(n, "\\" + n))
    return "".join(out)


def _quoted_prefix(s):
    """`"…"` ở đầu chuỗi → (nội dung đã unescape, phần còn lại); None nếu không đóng nháy."""
    raw = []
    i = 1
    while i < len(s):
        c = s[i]
        if c == "\\":
            if i + 1 >= len(s):
                return None
            raw.append(s[i:i + 2])
            i += 2
            continue
        if c == '"':
            return _unescape("".join(raw)), s[i + 1:]
        raw.append(c)
        i += 1
    return None


def _quote_key(k):
    needs = ":" in k or k.startswith(("#", ";", "//", '"', "'"))
    return '"' + _escape(k) + '"' if needs else k


def _quote_value(v):
    if "\n" in v or "\r" in v:
        return '"' + _escape(v) + '"'
    needs = v.startswith((" ", "'", '"', "#")) or v.endswith(" ")
    return '"' + _escape(v) + '"' if needs else v


def _lines(text):
    # Như Swift split theo \n, \r\n, \r (bỏ dòng rỗng).
    return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")


def parse(text):
    """JSON object chuỗi→chuỗi, hoặc flat YAML/txt mỗi dòng key:value.

    Trả dict, hoặc None khi không có mục nào đọc được (giống macOS)."""
    try:
        obj = json.loads(text)
        if isinstance(obj, dict) and obj and all(
                isinstance(k, str) and isinstance(v, str) for k, v in obj.items()):
            return obj
    except ValueError:
        pass
    if text.startswith("\ufeff"):
        text = text[1:]
    out = {}
    for raw in _lines(text):
        line = raw.strip(_WS)
        if not line or line.startswith((";", "#", "//")):
            continue
        q = _quoted_prefix(line) if line.startswith('"') else None
        if q is not None:
            key, after = q
            rest = after.lstrip(" \t")
            if not rest.startswith(":"):
                continue
            rest = rest[1:]
        else:
            colon = line.find(":")
            if colon < 0:
                continue
            key, rest = line[:colon], line[colon + 1:]
        key = key.strip(_WS)
        value = rest.strip(_WS)
        if len(value) >= 2 and value[0] == value[-1] == '"':
            value = _unescape(value[1:-1])
        elif len(value) >= 2 and value[0] == value[-1] == "'":
            value = value[1:-1]
        if not valid_key(key) or not value:
            continue
        out[key] = value
    return out or None


def export_yaml(shortcuts, header=HEADER):
    out = [header]
    for key in sorted(shortcuts):
        out.append("%s: %s" % (_quote_key(key), _quote_value(shortcuts[key])))
    return "\n".join(out) + "\n"


def one_line(value):
    """Value nhiều dòng hiện trên một dòng (macOS ShortcutRow.oneLine)."""
    return value.replace("\r\n", "\n").replace("\r", "\n").replace("\n", " ⏎ ")


def valid_key(key):
    return bool(key) and len(key) <= 64 and not any(c.isspace() for c in key)


def load(path=None):
    try:
        with open(path or shortcuts_path(), encoding="utf-8") as f:
            return parse(f.read()) or {}
    except (OSError, UnicodeDecodeError):
        return {}


def save(shortcuts, path=None):
    atomic_write(path or shortcuts_path(), export_yaml(shortcuts))
