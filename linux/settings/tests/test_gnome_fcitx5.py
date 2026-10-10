"""Fcitx5 thay IBus trên GNOME: ghi/gỡ đúng file của người dùng, không đè cấu hình sẵn có."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from viettelex_settings import gnome_fcitx5 as g  # noqa: E402

UPSTREAM = "[Desktop Entry]\nName=Fcitx 5\nExec=/usr/bin/fcitx5\nX-GNOME-Autostart-enabled=false\n"


class GnomeFcitx5Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = {"XDG_CONFIG_HOME": self.tmp.name}
        self.src = os.path.join(self.tmp.name, "upstream.desktop")
        with open(self.src, "w") as f:
            f.write(UPSTREAM)
        self.p = g.paths(self.env)

    def tearDown(self):
        self.tmp.cleanup()

    def read(self, key):
        with open(self.p[key]) as f:
            return f.read()

    def test_enable_writes_three_files(self):
        written = g.enable(self.env, sources=(self.src,))
        self.assertEqual(sorted(written), sorted(self.p.values()))
        self.assertIn("GTK_IM_MODULE=fcitx\n", self.read("env"))
        self.assertIn("XMODIFIERS=@im=fcitx\n", self.read("env"))
        auto = self.read("autostart")
        self.assertIn(g.MARK, auto)
        self.assertIn("Exec=/usr/bin/fcitx5", auto)
        self.assertNotIn("X-GNOME-Autostart-enabled=false", auto)
        self.assertIn("Name=viettelex", self.read("profile"))
        self.assertTrue(g.is_enabled(self.env))

    def test_existing_profile_and_autostart_kept(self):
        for key, text in (("profile", "[Groups/0]\nName=Mine\n"), ("autostart", "[Desktop Entry]\nExec=x\n")):
            os.makedirs(os.path.dirname(self.p[key]), exist_ok=True)
            with open(self.p[key], "w") as f:
                f.write(text)
        self.assertEqual(g.enable(self.env, sources=(self.src,)), [self.p["env"]])
        self.assertEqual(self.read("profile"), "[Groups/0]\nName=Mine\n")
        # Autostart của người dùng (không có dấu) ⇒ disable() không xoá.
        self.assertEqual(g.disable(self.env), [self.p["env"]])
        self.assertTrue(os.path.exists(self.p["autostart"]))

    def test_disable_removes_only_managed_files(self):
        g.enable(self.env, sources=(self.src,))
        self.assertEqual(sorted(g.disable(self.env)), sorted([self.p["env"], self.p["autostart"]]))
        self.assertFalse(g.is_enabled(self.env))
        self.assertTrue(os.path.exists(self.p["profile"]))
        self.assertEqual(g.disable(self.env), [])

    def test_fallback_desktop_when_fcitx5_file_missing(self):
        text = g.autostart_content(sources=(os.path.join(self.tmp.name, "missing"),))
        self.assertTrue(text.startswith("[Desktop Entry]\n" + g.MARK + "\n"))
        self.assertIn("Exec=fcitx5", text)


if __name__ == "__main__":
    unittest.main()
