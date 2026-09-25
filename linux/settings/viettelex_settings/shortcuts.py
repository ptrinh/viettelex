"""shortcuts.yml + nhập/xuất — port 1:1 ShortcutImporter của macOS (App/Sources/AppState.swift).

Cùng parser dùng cho bảng cơ chế gõ (app: mode), như macOS.
"""

import json
import os

from .config import atomic_write, config_dir

HEADER = "# VietTelex — bảng gõ tắt"


def shortcuts_path():
    return os.path.join(config_dir(), "shortcuts.yml")


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
    out = {}
    for raw in text.split("\n"):
        line = raw.strip(" \t\r")
        if not line or line.startswith((";", "#", "//")):
            continue
        colon = line.find(":")
        if colon < 0:
            continue
        key = line[:colon].strip(" \t")
        value = line[colon + 1:].strip(" \t")
        if len(value) >= 2 and ((value[0] == value[-1] == '"') or (value[0] == value[-1] == "'")):
            value = value[1:-1]
        if not key or not value or len(key) > 64 or any(c.isspace() for c in key):
            continue
        out[key] = value
    return out or None


def export_yaml(shortcuts, header=HEADER):
    out = [header]
    for key in sorted(shortcuts):
        v = shortcuts[key]
        needs_quotes = (v.startswith(" ") or v.endswith(" ")
                        or v.startswith(("'", '"', "#")))
        out.append('%s: "%s"' % (key, v) if needs_quotes else "%s: %s" % (key, v))
    return "\n".join(out) + "\n"


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
