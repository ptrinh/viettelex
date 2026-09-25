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

    def test_typing_modes_file_parses(self):
        with open(os.path.join(REPO, "typing-modes.yml"), encoding="utf-8") as f:
            d = shortcuts.parse(f.read())
        self.assertEqual(d.get("com.apple.Terminal"), "tap")


if __name__ == "__main__":
    unittest.main()
