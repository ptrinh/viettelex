import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from viettelex_settings import config  # noqa: E402

CONTRACT_EXAMPLE = '''
[typing]
input_method = "telex"              # "telex" | "vni"
simple_telex = false                # w đứng một mình không thành ư
free_marking = true
[general]
display_mode = "preedit"            # comment
toggle_hotkey = "Ctrl+space"
[app_modes]
# key = định danh app
"org.gnome.texteditor" = "surrounding"
"kitty" = "preedit"
'''


class ParseTests(unittest.TestCase):
    def test_contract_example(self):
        d = config.parse(CONTRACT_EXAMPLE)
        self.assertEqual(d["typing"]["input_method"], "telex")
        self.assertIs(d["typing"]["simple_telex"], False)
        self.assertEqual(d["general"]["toggle_hotkey"], "Ctrl+space")
        self.assertEqual(d["app_modes"], {"org.gnome.texteditor": "surrounding", "kitty": "preedit"})

    def test_defaults_match_contract(self):
        n = config.normalize({})
        self.assertEqual(n["typing"]["input_method"], "telex")
        self.assertTrue(n["typing"]["free_marking"])
        self.assertFalse(n["typing"]["modern_tone"])
        self.assertTrue(n["typing"]["contextual_english"])
        self.assertTrue(n["typing"]["collision_prefers_vietnamese"])
        self.assertFalse(n["typing"]["teencode"])
        self.assertEqual(n["general"]["display_mode"], "preedit")
        self.assertEqual(n["general"]["toggle_hotkey"], "Ctrl+space")
        self.assertFalse(n["general"]["preedit_underline"])  # "Gạch chân chữ đang gõ" off
        self.assertTrue(n["general"]["terminal_direct"])

    def test_wrong_type_falls_back_to_default(self):
        n = config.normalize(config.parse('[typing]\nfree_marking = "yes"\ninput_method = "abc"\n'
                                          '[app_modes]\n"x" = "bogus"\n"y" = "off"\n'))
        self.assertTrue(n["typing"]["free_marking"])
        self.assertEqual(n["typing"]["input_method"], "telex")
        self.assertEqual(n["app_modes"], {"y": "off"})
        n = config.normalize(config.parse('[app_modes]\n"kitty" = "direct"\n'))
        self.assertEqual(n["app_modes"], {"kitty": "direct"})

    def test_escapes_roundtrip(self):
        d = config.normalize({})
        d["app_modes"]['we"ird\\app'] = "off"
        back = config.normalize(config.parse(config.dump(d)))
        self.assertEqual(back, d)

    def test_unknown_keys_preserved(self):
        d = config.normalize(config.parse('[typing]\nfuture_flag = 3\n[future]\na = true\n'))
        text = config.dump(d)
        self.assertIn("future_flag = 3", text)
        self.assertIn("[future]", text)

    def test_dump_is_contract_subset(self):
        text = config.dump(config.normalize({}))
        for line in text.splitlines():
            s = line.strip()
            self.assertTrue(not s or s.startswith(("#", "[")) or " = " in s, line)
        self.assertNotIn("\r", text)

    def test_atomic_write_no_tmp_left(self):
        with tempfile.TemporaryDirectory() as d:
            c = config.Config(os.path.join(d, "viettelex", "config.toml"))
            c.set("typing", "quick_telex", True)
            self.assertEqual(os.listdir(os.path.join(d, "viettelex")), ["config.toml"])
            self.assertTrue(config.Config(c.path).get("typing", "quick_telex"))

    def test_app_mode_auto_removes_and_lowercases(self):
        with tempfile.TemporaryDirectory() as d:
            c = config.Config(os.path.join(d, "config.toml"))
            c.set_app_mode("Kitty", "surrounding")
            self.assertEqual(c.data["app_modes"], {"kitty": "surrounding"})
            c.set_app_mode("kitty", "auto")
            self.assertEqual(c.data["app_modes"], {})


FCITX_WRITTEN = """# viết tay
[typing]
input_method = "telex"   # kiểu gõ
free_marking = true
future_flag = 7

[general]
toggle_hotkey = "Ctrl+space"

[app_modes]
"kitty" = "preedit"
"#weird" = "off"  # giữ

[future]
x = true
"""


class InPlaceTests(unittest.TestCase):
    def test_only_changed_line_differs(self):
        out = config.update_text(FCITX_WRITTEN, {("typing", "free_marking"): False})
        a, b = FCITX_WRITTEN.splitlines(), out.splitlines()
        self.assertEqual(len(a), len(b))
        self.assertEqual([i for i in range(len(a)) if a[i] != b[i]], [3])
        self.assertEqual(b[3], "free_marking = false")

    def test_comment_kept_on_changed_line(self):
        out = config.update_text(FCITX_WRITTEN, {("typing", "input_method"): "vni"})
        self.assertIn('input_method = "vni"  # kiểu gõ', out)

    def test_new_key_appended_to_its_section(self):
        out = config.update_text(FCITX_WRITTEN, {("typing", "re_edit_word"): False,
                                                 ("app_modes", "code"): "surrounding"})
        d = config.parse(out)
        self.assertIs(d["typing"]["re_edit_word"], False)
        self.assertEqual(d["typing"]["future_flag"], 7)
        self.assertEqual(d["app_modes"], {"kitty": "preedit", "#weird": "off", "code": "surrounding"})
        self.assertIn("[future]\nx = true", out)
        lines = out.splitlines()
        self.assertLess(lines.index("re_edit_word = false"), lines.index("[general]"))

    def test_delete_app_mode(self):
        out = config.update_text(FCITX_WRITTEN, {("app_modes", "kitty"): None})
        self.assertNotIn("kitty", out)
        self.assertIn('"#weird" = "off"  # giữ', out)

    def test_missing_section_and_empty_file(self):
        out = config.update_text("", {("general", "display_mode"): "surrounding"})
        self.assertEqual(config.parse(out), {"general": {"display_mode": "surrounding"}})
        out = config.update_text("[typing]\na = true\n", {("app_modes", "x"): "off"})
        self.assertEqual(config.parse(out)["app_modes"], {"x": "off"})

    def test_config_set_picks_up_external_edit(self):
        # Fcitx5 sửa file sau khi app đã nạp: lần ghi sau của app không được đè mất.
        with tempfile.TemporaryDirectory() as d:
            c = config.Config(os.path.join(d, "config.toml"))
            c.set("typing", "quick_telex", True)
            with open(c.path, "a") as f:
                f.write("[typing]\nteencode = true\n")
            c.set("typing", "simple_telex", True)
            with open(c.path) as f:
                d2 = config.normalize(config.parse(f.read()))
            self.assertTrue(d2["typing"]["teencode"])
            self.assertTrue(d2["typing"]["simple_telex"])
            self.assertTrue(d2["typing"]["quick_telex"])

    def test_re_edit_word_default_on(self):
        self.assertTrue(config.normalize({})["typing"]["re_edit_word"])


class HotkeyTests(unittest.TestCase):
    def test_normalize(self):
        self.assertEqual(config.normalize_hotkey("ctrl + Space"), "Ctrl+space")
        self.assertEqual(config.normalize_hotkey("Shift+Ctrl+Z"), "Ctrl+Shift+z")
        self.assertEqual(config.normalize_hotkey("Alt+F12"), "Alt+F12")
        self.assertEqual(config.normalize_hotkey(""), "")

    def test_rejects(self):
        self.assertIsNone(config.normalize_hotkey("Super+space"))   # GNOME
        self.assertIsNone(config.normalize_hotkey("space"))
        self.assertIsNone(config.normalize_hotkey("Hyper+a"))
        self.assertIsNone(config.normalize_hotkey("Ctrl+Ctrl+a"))


if __name__ == "__main__":
    unittest.main()
