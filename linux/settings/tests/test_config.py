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

    def test_wrong_type_falls_back_to_default(self):
        n = config.normalize(config.parse('[typing]\nfree_marking = "yes"\ninput_method = "abc"\n'
                                          '[app_modes]\n"x" = "bogus"\n"y" = "off"\n'))
        self.assertTrue(n["typing"]["free_marking"])
        self.assertEqual(n["typing"]["input_method"], "telex")
        self.assertEqual(n["app_modes"], {"y": "off"})

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
