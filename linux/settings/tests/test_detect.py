import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from viettelex_settings import detect  # noqa: E402

PROFILE = """[Groups/0]
Name=Default
Default Layout=us
DefaultIM=viettelex

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=viettelex
Layout=
"""


def snap(**kw):
    base = {"env": {}, "xinputrc": "", "fcitx5_profile": "", "ibus_preload": "",
            "gnome_sources": "", "other_vn": []}
    base.update(kw)
    return base


class DetectTests(unittest.TestCase):
    def test_fcitx5_ok(self):
        a = detect.assess(snap(env={"GTK_IM_MODULE": "fcitx"}, fcitx5_running=True,
                               fcitx5_addon=True, fcitx5_profile=PROFILE))
        self.assertEqual(a["framework"], "fcitx5")
        self.assertTrue(a["ok"])

    def test_fcitx5_not_enabled(self):
        a = detect.assess(snap(env={"XMODIFIERS": "@im=fcitx"}, fcitx5_running=True,
                               fcitx5_addon=True, fcitx5_profile=PROFILE.replace("Name=viettelex\n", "")))
        self.assertFalse(a["enabled"]["fcitx5"])
        self.assertFalse(a["ok"])

    def test_defaultim_line_is_not_enabled(self):
        # DefaultIM=viettelex không có nghĩa là đã có Items.
        self.assertFalse(detect._fcitx5_enabled("DefaultIM=viettelex\n"))

    def test_ibus_gnome(self):
        a = detect.assess(snap(env={"GTK_IM_MODULE": "ibus"}, ibus_running=True, ibus_component=True,
                               gnome_sources="[('xkb', 'us'), ('ibus', 'viettelex')]"))
        self.assertEqual(a["framework"], "ibus")
        self.assertTrue(a["ok"])

    def test_xinputrc_fallback(self):
        a = detect.assess(snap(xinputrc="# im-config\nrun_im fcitx5\n"))
        self.assertEqual(a["framework"], "fcitx5")

    def test_nothing(self):
        a = detect.assess(snap())
        self.assertIsNone(a["framework"])
        self.assertFalse(a["ok"])

    def test_warnings(self):
        a = detect.assess(snap(env={"XDG_SESSION_TYPE": "wayland"}, other_vn=["ibus-bamboo"]))
        self.assertIn("other_vn", a["warnings"])
        self.assertIn("wayland_chromium", a["warnings"])


if __name__ == "__main__":
    unittest.main()
