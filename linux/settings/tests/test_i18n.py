"""Ngôn ngữ giao diện: bản dịch đủ, mặc định tiếng Việt, 3 key mới của config.toml."""

import ast
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)
PKG = os.path.join(HERE, "..", "viettelex_settings")
sys.path.insert(0, os.path.join(HERE, ".."))
from viettelex_settings import compat, config, i18n  # noqa: E402

SOURCES = ("app.py", "compat.py", "config.py", "detect.py", "shortcuts.py", "updater.py")
VN_LETTER = re.compile(r"[À-ỹĐđ]")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[sd]")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def marked_strings():
    """Mọi literal trong _("…") / N_("…") của mã nguồn app."""
    out = {}
    for name in SOURCES:
        path = os.path.join(PKG, name)
        tree = ast.parse(read(path))
        for n in ast.walk(tree):
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in ("_", "N_"):
                if n.args and isinstance(n.args[0], ast.Constant) and isinstance(n.args[0].value, str):
                    out.setdefault(n.args[0].value, "%s:%d" % (name, n.lineno))
    return out


def unmarked_vietnamese(name):
    """Literal tiếng Việt KHÔNG bọc _() (trừ docstring và header file xuất)."""
    path = os.path.join(PKG, name)
    tree = ast.parse(read(path))
    skip = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in ("_", "N_"):
            skip.update(id(a) for a in n.args)
        if isinstance(n, (ast.Module, ast.FunctionDef, ast.ClassDef)) and n.body and \
                isinstance(n.body[0], ast.Expr) and isinstance(n.body[0].value, ast.Constant):
            skip.add(id(n.body[0].value))
    bad = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) not in skip \
                and VN_LETTER.search(n.value):
            if n.value.startswith("# VietTelex") or n.value in ("Ngôn ngữ / Language", "Tiếng Việt"):
                continue          # header file xuất; nhãn chọn ngôn ngữ song ngữ cố định
            bad.append("%s:%d %r" % (name, n.lineno, n.value[:40]))
    return bad


class CompletenessTests(unittest.TestCase):
    def test_every_marked_string_has_english(self):
        missing = ["%s  %r" % (where, s[:60]) for s, where in marked_strings().items()
                   if s not in i18n.EN]
        self.assertEqual(missing, [], "thiếu bản dịch EN:\n" + "\n".join(missing))

    def test_no_unused_english_entry(self):
        used = marked_strings()
        unused = [k[:60] for k in i18n.EN if k not in used]
        self.assertEqual(unused, [], "EN thừa (chuỗi gốc đã đổi/xoá?):\n" + "\n".join(unused))

    def test_no_unmarked_vietnamese_ui_string(self):
        bad = unmarked_vietnamese("app.py") + unmarked_vietnamese("compat.py")
        self.assertEqual(bad, [], "chuỗi tiếng Việt chưa bọc _():\n" + "\n".join(bad))

    def test_placeholders_match(self):
        for vi, en in i18n.EN.items():
            self.assertEqual(PLACEHOLDER.findall(vi), PLACEHOLDER.findall(en), vi)

    def test_english_is_really_translated(self):
        # Không để sót chữ Việt trong bản EN (trừ ví dụ gõ và tên "Tiếng Việt (VietTelex)").
        allowed = ("Tiếng Việt (VietTelex)", "tôi đi học", "việt", "không", "toán", "ơ", "ư",
                   "â/ê/ô", "ă", "đ", "lát", "lít", "hí", "í", "zẻ", "kó", "bíe", "thík",
                   "gòy", "ừk", "wá", "cư", "âm", "oà", "uý", "hòa", "thủy", "khỏe", "hoà",
                   "thuý", "khoẻ", "thơ", "ngư", "Gõ Nhanh", "ch", "Ư",
                   "tỷ", "tôi", "hôm nay", "ngày mai", "hôm qua", "bây giờ", "hópng", "tòc")
        for vi, en in i18n.EN.items():
            rest = en
            for a in sorted(allowed, key=len, reverse=True):
                rest = rest.replace(a, "")
            self.assertIsNone(VN_LETTER.search(rest), "%r → %r" % (vi, en))


class LanguageTests(unittest.TestCase):
    def tearDown(self):
        i18n.set_language("vi")

    def test_default_is_vietnamese(self):
        self.assertEqual(config.DEFAULTS["general"]["ui_language"], "vi")
        self.assertEqual(i18n.normalized(None), "vi")
        self.assertEqual(i18n.normalized(""), "vi")
        self.assertEqual(i18n.normalized("fr"), "vi")
        self.assertEqual(i18n.normalized("EN"), "vi")
        self.assertEqual(i18n.normalized("en"), "en")

    def test_default_ignores_system_locale(self):
        # Process mới với locale tiếng Anh: vẫn tiếng Việt khi config không nói gì.
        code = ("import sys; sys.path.insert(0, %r)\n"
                "from viettelex_settings import config, i18n\n"
                "c = config.Config(%r)\n"
                "i18n.set_language(c.get('general', 'ui_language'))\n"
                "print(i18n.language(), i18n._('Gõ tắt'))") % (
                    os.path.abspath(os.path.join(HERE, "..")),
                    os.path.join(tempfile.mkdtemp(), "missing.toml"))
        env = dict(os.environ, LANG="en_US.UTF-8", LC_ALL="en_US.UTF-8", LANGUAGE="en_US:en",
                   LC_MESSAGES="en_US.UTF-8")
        out = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True,
                             text=True, check=True).stdout.strip()
        self.assertEqual(out, "vi Gõ tắt")

    def test_switching(self):
        self.assertEqual(i18n._("Gõ tắt"), "Gõ tắt")
        i18n.set_language("en")
        self.assertEqual(i18n._("Gõ tắt"), "Shortcuts")
        self.assertEqual(i18n._("chuỗi lạ"), "chuỗi lạ")    # thiếu bản dịch ⇒ giữ tiếng Việt
        self.assertEqual(i18n.N_("Tự động"), "Tự động")    # N_ không dịch
        i18n.set_language("xx")
        self.assertEqual(i18n.language(), "vi")

    def test_compat_follows_language(self):
        snap = {"session": "x11", "desktop": "GNOME", "kitty": True, "glfw_im_module": ""}
        vi = {i["id"]: i["title"] for i in compat.assess(snap)}
        i18n.set_language("en")
        en = {i["id"]: i["title"] for i in compat.assess(snap)}
        self.assertEqual(vi.keys(), en.keys())
        self.assertEqual(en["kitty_x11"], "kitty: needs GLFW_IM_MODULE=ibus")
        self.assertNotEqual(vi["gnome_overview"], en["gnome_overview"])


class NewConfigKeysTests(unittest.TestCase):
    def test_defaults(self):
        d = config.normalize({})
        self.assertEqual(d["general"]["ui_language"], "vi")
        self.assertIs(d["general"]["text_tools_menu"], True)
        self.assertEqual(d["general"]["add_tones_hotkey"], "")

    def test_bad_values_fall_back(self):
        d = config.normalize(config.parse('[general]\nui_language = "fr"\ntext_tools_menu = 1\n'
                                          'add_tones_hotkey = "t"\n'))
        self.assertEqual(d["general"]["ui_language"], "vi")
        self.assertIs(d["general"]["text_tools_menu"], True)
        self.assertEqual(d["general"]["add_tones_hotkey"], "")

    def test_round_trip(self):
        path = os.path.join(tempfile.mkdtemp(), "config.toml")
        with open(path, "w", encoding="utf-8") as f:
            f.write("# giữ comment\n[general]\ntoggle_hotkey = \"Ctrl+space\"\nfuture_key = 3\n")
        c = config.Config(path)
        c.set("general", "ui_language", "en")
        c.set("general", "text_tools_menu", False)
        c.set("general", "add_tones_hotkey", "Ctrl+Alt+t")
        c2 = config.Config(path)
        self.assertEqual(c2.get("general", "ui_language"), "en")
        self.assertIs(c2.get("general", "text_tools_menu"), False)
        self.assertEqual(c2.get("general", "add_tones_hotkey"), "Ctrl+Alt+t")
        text = read(path)
        self.assertIn("# giữ comment", text)
        self.assertIn("future_key = 3", text)
        self.assertIn('ui_language = "en"', text)
        self.assertIn("text_tools_menu = false", text)
        self.assertIn('add_tones_hotkey = "Ctrl+Alt+t"', text)
        # dump chuẩn cũng giữ đủ
        self.assertEqual(config.normalize(config.parse(config.dump(c2.data)))["general"],
                         c2.data["general"])

    def test_action_hotkey_validation(self):
        err = config.action_hotkey_error
        self.assertIsNone(err("", "Ctrl+space"))
        self.assertIsNone(err("Ctrl+Alt+t", "Ctrl+space"))
        self.assertIsNone(err("Super+t", ""))
        self.assertEqual(err("Shift+t", "Ctrl+space"), "modifier")
        self.assertEqual(err("Ctrl+space", "ctrl + Space"), "toggle")
        self.assertIsNone(config.normalize_hotkey("Super+space"))


if __name__ == "__main__":
    unittest.main()
