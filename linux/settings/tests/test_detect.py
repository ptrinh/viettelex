import os
import sys
import tempfile
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
        self.assertNotIn("lotus_uinput", a["warnings"])

    def test_lotus_is_another_vietnamese_im(self):
        self.assertEqual(detect.OTHER_VN_IMS.get("/usr/share/fcitx5/addon/lotus.conf"), "fcitx5-lotus")

    def test_lotus_uinput_warning(self):
        a = detect.assess(snap(other_vn=["fcitx5-lotus"], lotus_uinput=True))
        self.assertIn("other_vn", a["warnings"])
        self.assertIn("lotus_uinput", a["warnings"])


DEVICES_WITH_LOTUS = """I: Bus=0011 Vendor=0001 Product=0001 Version=ab41
N: Name="AT Translated Set 2 keyboard"
H: Handlers=sysrq kbd event0 leds

I: Bus=0003 Vendor=0000 Product=0000 Version=0000
N: Name="Lotus-Uinput-Server"
P: Phys=
H: Handlers=sysrq kbd event7
"""

DEVICES_PLAIN = """I: Bus=0011 Vendor=0001 Product=0001 Version=ab41
N: Name="AT Translated Set 2 keyboard"
H: Handlers=sysrq kbd event0 leds
"""


class LotusUinputTests(unittest.TestCase):
    """Dò server uinput của fcitx5-lotus trên một cây thư mục giả (addon + /proc)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.asked = []

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, text=""):
        full = self.root + path
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as f:
            f.write(text)

    def systemd(self, active):
        def check(unit):
            self.asked.append(unit)
            return active
        return check

    def test_no_lotus_addon_reads_nothing(self):
        self.write(detect.INPUT_DEVICES, DEVICES_WITH_LOTUS)
        self.assertFalse(detect.lotus_uinput_active(self.root, self.systemd(True), "phil"))
        self.assertEqual(self.asked, [])  # rẻ: không có Lotus thì không hỏi systemd

    def test_uinput_device_present(self):
        self.write(detect.LOTUS_ADDON)
        self.write(detect.INPUT_DEVICES, DEVICES_WITH_LOTUS)
        self.assertTrue(detect.lotus_uinput_active(self.root, self.systemd(False), "phil"))
        self.assertEqual(self.asked, [])

    def test_server_unit_running(self):
        self.write(detect.LOTUS_ADDON)
        self.write(detect.INPUT_DEVICES, DEVICES_PLAIN)
        self.assertTrue(detect.lotus_uinput_active(self.root, self.systemd(True), "phil"))
        self.assertEqual(self.asked, ["fcitx5-lotus-server@phil.service"])

    def test_lotus_in_preedit_mode(self):
        self.write(detect.LOTUS_ADDON)
        self.write(detect.INPUT_DEVICES, DEVICES_PLAIN)
        self.assertFalse(detect.lotus_uinput_active(self.root, self.systemd(False), "phil"))

    def test_unreadable_proc(self):
        self.write(detect.LOTUS_ADDON)
        self.assertFalse(detect.lotus_uinput_active(self.root, self.systemd(False), "phil"))

    def test_device_name_must_be_on_a_name_line(self):
        self.assertFalse(detect.lotus_uinput_device('P: Phys=Lotus-Uinput-Server\n'))
        self.assertTrue(detect.lotus_uinput_device('N: Name="Lotus-Uinput-Server"\n'))


if __name__ == "__main__":
    unittest.main()
