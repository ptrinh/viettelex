import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from viettelex_settings import shortcuts  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


class ShortcutTests(unittest.TestCase):
    def test_sample_file_from_repo(self):
        with open(os.path.join(REPO, "sample-shortcuts.yml"), encoding="utf-8") as f:
            d = shortcuts.parse(f.read())
        self.assertEqual(d["ko"], "không")
        self.assertEqual(d["đc"], "được")

    def test_export_matches_macos_format(self):
        text = shortcuts.export_yaml({"b": " lead", "a": "x", "c": "#tag", "d": "'q"})
        self.assertEqual(text, '# VietTelex — bảng gõ tắt\na: x\nb: " lead"\nc: "#tag"\nd: "\'q"\n')

    def test_roundtrip(self):
        d = {"ko": "không", "sp": " có cách ", "url": "http://a.b:80"}
        self.assertEqual(shortcuts.parse(shortcuts.export_yaml(d)), d)

    def test_json_and_txt(self):
        self.assertEqual(shortcuts.parse('{"tk": "tài khoản"}'), {"tk": "tài khoản"})
        self.assertEqual(shortcuts.parse("; comment\n// c\nko:không\r\nbad line\nhas space: x\n"),
                         {"ko": "không"})

    def test_rules(self):
        self.assertIsNone(shortcuts.parse("<?xml version: 1?>\n"))   # key có khoảng trắng
        self.assertIsNone(shortcuts.parse(""))
        self.assertIsNone(shortcuts.parse("k" * 65 + ": v\n"))
        self.assertEqual(shortcuts.parse("a: 'q'\n"), {"a": "q"})
        self.assertIsNone(shortcuts.parse("a:\n"))

    # Khoá có ":" / mở đầu # ; // và value nhiều dòng — như macOS ShortcutImporter. File mẫu
    # linux/common/tests/data/shortcuts-macos.yml do chính exportYAML của macOS ghi ra; test C++
    # (test_common testShortcutFileQuoting) đọc cùng file.
    MAC_TABLE = {
        ":D": "😀", "a:b": "x", "#x": "hash", ";x": "semi", "//x": "slash", '"k': "dq", "'k": "sq",
        "sig": "Thân mến,\nPhil", "bs": "C:\\temp", "q": '"trích"', "sp": " có space ",
        "ko": "không", "url": "http://x", "tab": "a\tb",
    }

    def test_macos_fixture_byte_for_byte(self):
        path = os.path.join(REPO, "linux", "common", "tests", "data", "shortcuts-macos.yml")
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
        self.assertEqual(shortcuts.export_yaml(self.MAC_TABLE), text)
        self.assertEqual(shortcuts.parse(text), self.MAC_TABLE)

    def test_quoted_keys_round_trip(self):
        for key in (":D", "a:b", "#x", ";x", "//x", '"k', "'k"):
            d = {key: "v"}
            text = shortcuts.export_yaml(d)
            self.assertTrue(text.split("\n")[1].startswith('"'), text)
            self.assertEqual(shortcuts.parse(text), d, key)
        multi = {"sig": "Thân mến,\nPhil\r\nx", "bs": "C:\\temp\\n"}
        text = shortcuts.export_yaml(multi)
        self.assertEqual(text.count("\n"), 3)   # header + 2 dòng: không vỡ dòng
        self.assertEqual(shortcuts.parse(text), {"sig": "Thân mến,\nPhil\nx", "bs": "C:\\temp\\n"})

    def test_import_macos_export_line(self):
        self.assertEqual(shortcuts.parse('":D": 😀\n'), {":D": "😀"})
        self.assertEqual(shortcuts.parse('"a:b"  : x\n'), {"a:b": "x"})
        self.assertIsNone(shortcuts.parse('":D" 😀\n'))            # khoá ngoặc phải có ":"
        phone = ('# VietTelex — bảng gõ tắt\n"->": →\n":)": 🙂\nk2: không hai\nq: ""trích""\n'
                 'sig: "Thân mến,\\nPhil"\nsp: " có space "\n')
        self.assertEqual(shortcuts.parse(phone), {
            "->": "→", ":)": "🙂", "k2": "không hai", "q": '"trích"',
            "sig": "Thân mến,\nPhil", "sp": " có space "})
        self.assertEqual(shortcuts.parse("\ufeffko: không\r\ndc: được\r\n"), {"ko": "không", "dc": "được"})

    def test_json_import_with_newline_saves_one_line(self):
        d = shortcuts.parse('{"sig": "a\\nb", ":D": "😀"}')
        text = shortcuts.export_yaml(d)
        self.assertIn('sig: "a\\nb"\n', text)
        self.assertIn('":D": 😀\n', text)
        self.assertEqual(shortcuts.parse(text), d)

    def test_one_line(self):
        self.assertEqual(shortcuts.one_line("Thân mến,\nPhil"), "Thân mến, ⏎ Phil")
        self.assertEqual(shortcuts.one_line("x\r\ny"), "x ⏎ y")

    def test_typing_modes_file_parses(self):
        with open(os.path.join(REPO, "typing-modes.yml"), encoding="utf-8") as f:
            d = shortcuts.parse(f.read())
        self.assertEqual(d.get("com.apple.Terminal"), "tap")


if __name__ == "__main__":
    unittest.main()
