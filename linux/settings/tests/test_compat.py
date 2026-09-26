import fnmatch
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from viettelex_settings import compat  # noqa: E402

HOME = "/home/u"


class FakeFS:
    """Filesystem + PATH giả: files = {path: nội dung}, bins = tập lệnh có trên PATH."""

    def __init__(self, files=None, bins=()):
        self.files = dict(files or {})
        self.bins = set(bins)

    def exists(self, p):
        return p in self.files or any(f.startswith(p.rstrip("/") + "/") for f in self.files)

    def read(self, p):
        return self.files.get(p, "")

    def which(self, b):
        return "/usr/bin/" + b if b in self.bins else None

    def glob(self, pattern):
        return sorted(f for f in self.files if fnmatch.fnmatch(f, pattern))

    def collect(self, env, framework=None):
        env = dict(env)
        env.setdefault("HOME", HOME)
        return compat.collect(env=env, home=HOME, exists=self.exists, read=self.read,
                              which=self.which, globber=self.glob, framework=framework)


def ids(issues):
    return [i["id"] for i in issues]


GNOME_WL = {"XDG_SESSION_TYPE": "wayland", "XDG_CURRENT_DESKTOP": "ubuntu:GNOME"}
GNOME_X11 = {"XDG_SESSION_TYPE": "x11", "XDG_CURRENT_DESKTOP": "ubuntu:GNOME"}


class ChromiumTests(unittest.TestCase):
    def test_wayland_with_chrome_and_code(self):
        fs = FakeFS({"/usr/share/applications/google-chrome.desktop": "",
                     "/usr/share/applications/code.desktop": ""})
        issues = compat.assess(fs.collect(GNOME_WL))
        it = next(i for i in issues if i["id"] == "chromium_wayland")
        self.assertIn("Google Chrome", it["title"])
        self.assertIn("VS Code", it["title"])
        self.assertIn(compat.WAYLAND_IME_FLAGS, it["fix"])
        self.assertIn("~/.config/chrome-flags.conf", it["fix"])
        self.assertIn("~/.config/code-flags.conf", it["fix"])
        self.assertIn("~/.local/share/applications/code.desktop", it["fix"])
        self.assertIn(compat.X11_FLAG, it["fix"])

    def test_x11_no_chromium_warning(self):
        fs = FakeFS({"/usr/share/applications/google-chrome.desktop": ""})
        self.assertNotIn("chromium_wayland", ids(compat.assess(fs.collect(GNOME_X11))))

    def test_wayland_without_apps(self):
        self.assertNotIn("chromium_wayland", ids(compat.assess(FakeFS().collect(GNOME_WL))))

    def test_wayland_display_only(self):
        fs = FakeFS(bins={"slack"})
        s = fs.collect({"WAYLAND_DISPLAY": "wayland-0"})
        self.assertEqual(s["session"], "wayland")
        self.assertIn("chromium_wayland", ids(compat.assess(s)))

    def test_flags_file_marks_configured(self):
        fs = FakeFS({"/usr/share/applications/google-chrome.desktop": "",
                     HOME + "/.config/chrome-flags.conf": "--enable-wayland-ime\n"})
        s = fs.collect(GNOME_WL)
        self.assertTrue(s["apps"]["chrome"]["configured"])
        self.assertNotIn("chromium_wayland", ids(compat.assess(s)))

    def test_user_desktop_override_marks_configured(self):
        fs = FakeFS({"/usr/share/applications/code.desktop": "",
                     HOME + "/.local/share/applications/code.desktop":
                         "Exec=/usr/share/code/code --ozone-platform=x11 %F\n"})
        self.assertTrue(fs.collect(GNOME_WL)["apps"]["code"]["configured"])

    def test_snap_and_flatpak_kind(self):
        fs = FakeFS({"/var/lib/snapd/desktop/applications/chromium_chromium.desktop": "",
                     "/var/lib/flatpak/exports/share/applications/com.discordapp.Discord.desktop": ""})
        s = fs.collect(GNOME_WL)
        self.assertEqual(s["apps"]["chromium"]["kind"], "snap")
        self.assertEqual(s["apps"]["discord"]["kind"], "flatpak")
        fix = next(i for i in compat.assess(s) if i["id"] == "chromium_wayland")["fix"]
        self.assertIn("snap/flatpak", fix)
        self.assertNotIn("sed ", fix)

    def test_kde_uses_text_input_v1(self):
        fs = FakeFS({"/usr/share/applications/google-chrome.desktop": ""})
        it = next(i for i in compat.assess(fs.collect(
            {"XDG_SESSION_TYPE": "wayland", "XDG_CURRENT_DESKTOP": "KDE"}))
            if i["id"] == "chromium_wayland")
        self.assertIn("--wayland-text-input-version=1", it["fix"])
        self.assertNotIn("version=3", it["fix"])


class OtherAppTests(unittest.TestCase):
    def test_kitty_x11(self):
        fs = FakeFS(bins={"kitty"})
        self.assertIn("kitty_x11", ids(compat.assess(fs.collect(GNOME_X11))))
        env = dict(GNOME_X11, GLFW_IM_MODULE="ibus")
        self.assertNotIn("kitty_x11", ids(compat.assess(fs.collect(env))))
        self.assertNotIn("kitty_x11", ids(compat.assess(fs.collect(GNOME_WL))))

    def test_jetbrains_x11(self):
        vm = HOME + "/.config/JetBrains/IntelliJIdea2025.2/idea64.vmoptions"
        fs = FakeFS({vm: "-Xmx2g\n"})
        it = next(i for i in compat.assess(fs.collect(GNOME_X11)) if i["id"] == "jetbrains_x11")
        self.assertEqual(it["fix"], compat.JETBRAINS_OPT)
        fs.files[vm] += compat.JETBRAINS_OPT + "\n"
        self.assertNotIn("jetbrains_x11", ids(compat.assess(fs.collect(GNOME_X11))))

    def test_jetbrains_toolbox_desktop(self):
        fs = FakeFS({HOME + "/.local/share/applications/jetbrains-pycharm.desktop": ""})
        self.assertTrue(fs.collect(GNOME_X11)["jetbrains"])

    def test_rofi(self):
        self.assertIn("rofi", ids(compat.assess(FakeFS(bins={"rofi"}).collect(GNOME_X11))))
        self.assertNotIn("rofi", ids(compat.assess(FakeFS().collect(GNOME_X11))))

    def test_gnome_overview_only_on_gnome(self):
        self.assertIn("gnome_overview", ids(compat.assess(FakeFS().collect(GNOME_WL))))
        self.assertNotIn("gnome_overview", ids(compat.assess(
            FakeFS().collect({"XDG_CURRENT_DESKTOP": "KDE"}))))

    def test_snap_fcitx5_jammy(self):
        files = {"/etc/os-release": 'NAME="Ubuntu"\nVERSION_ID="22.04"\n',
                 "/var/lib/snapd/desktop/applications/firefox_firefox.desktop": ""}
        fs = FakeFS(files)
        self.assertIn("snap_fcitx5_jammy", ids(compat.assess(fs.collect(GNOME_X11, "fcitx5"))))
        self.assertNotIn("snap_fcitx5_jammy", ids(compat.assess(fs.collect(GNOME_X11, "ibus"))))
        fs.files["/etc/os-release"] = 'VERSION_ID="24.04"\n'
        self.assertNotIn("snap_fcitx5_jammy", ids(compat.assess(fs.collect(GNOME_X11, "fcitx5"))))

    def test_terminals_note(self):
        self.assertIn("terminal_preedit", ids(compat.assess(
            FakeFS(bins={"tmux"}).collect(GNOME_X11))))
        self.assertNotIn("terminal_preedit", ids(compat.assess(FakeFS().collect({}))))

    def test_im_config_mode(self):
        self.assertEqual(compat.im_config_mode(""), "auto")
        self.assertEqual(compat.im_config_mode("# im-config\nrun_im default\n"), "auto")
        self.assertEqual(compat.im_config_mode("run_im auto\n"), "auto")
        self.assertEqual(compat.im_config_mode("run_im fcitx5\n"), "fcitx5")

    def test_imconfig_auto_both_frameworks(self):
        fs = FakeFS({"/usr/share/fcitx5/addon/viettelex.conf": ""}, bins={"fcitx5", "ibus-daemon"})
        kde = {"XDG_SESSION_TYPE": "x11", "XDG_CURRENT_DESKTOP": "KDE"}
        it = next(i for i in compat.assess(fs.collect(kde)) if i["id"] == "imconfig_auto")
        self.assertEqual(it["fix"], "im-config -n fcitx5")
        # GNOME: im-config không có tác dụng → không báo.
        self.assertNotIn("imconfig_auto", ids(compat.assess(fs.collect(GNOME_X11))))
        # Đã chọn hẳn fcitx5.
        fs.files[HOME + "/.xinputrc"] = "run_im fcitx5\n"
        self.assertNotIn("imconfig_auto", ids(compat.assess(fs.collect(kde))))

    def test_imconfig_needs_both_and_addon(self):
        kde = {"XDG_CURRENT_DESKTOP": "XFCE"}
        fs = FakeFS({"/usr/share/fcitx5/addon/viettelex.conf": ""}, bins={"fcitx5"})
        self.assertNotIn("imconfig_auto", ids(compat.assess(fs.collect(kde))))
        fs = FakeFS(bins={"fcitx5", "ibus-daemon"})
        self.assertNotIn("imconfig_auto", ids(compat.assess(fs.collect(kde))))

    def test_qt5_wayland_without_module(self):
        fs = FakeFS({"/usr/lib/x86_64-linux-gnu/libQt5Gui.so.5.15.3": ""})
        it = next(i for i in compat.assess(fs.collect(GNOME_WL, "ibus")) if i["id"] == "qt5_wayland")
        self.assertIn("QT_IM_MODULE=ibus", it["fix"])
        it = next(i for i in compat.assess(fs.collect(GNOME_WL, "fcitx5")) if i["id"] == "qt5_wayland")
        self.assertIn("QT_IM_MODULES=wayland;fcitx;ibus", it["fix"])
        self.assertNotIn("qt5_wayland", ids(compat.assess(
            fs.collect(dict(GNOME_WL, QT_IM_MODULE="fcitx"), "fcitx5"))))
        self.assertNotIn("qt5_wayland", ids(compat.assess(fs.collect(GNOME_X11, "fcitx5"))))
        self.assertNotIn("qt5_wayland", ids(compat.assess(FakeFS().collect(GNOME_WL, "fcitx5"))))

    def test_clean_machine_has_no_issues(self):
        self.assertEqual(compat.assess(FakeFS().collect({"XDG_SESSION_TYPE": "x11"})), [])

    def test_every_issue_well_formed(self):
        fs = FakeFS({"/usr/share/applications/code.desktop": "",
                     "/etc/os-release": 'VERSION_ID="22.04"\n',
                     "/var/lib/snapd/desktop/applications/firefox_firefox.desktop": ""},
                    bins={"kitty", "rofi", "tmux", "fcitx5", "ibus-daemon"})
        fs.files["/usr/lib/x86_64-linux-gnu/libQt5Gui.so.5"] = ""
        fs.files["/usr/share/fcitx5/addon/viettelex.conf"] = ""
        for env in (GNOME_WL, GNOME_X11):
            for it in compat.assess(fs.collect(env, "fcitx5")):
                self.assertEqual(set(it), {"id", "level", "title", "body", "fix"})
                self.assertIn(it["level"], ("warn", "info"))
                self.assertTrue(it["title"] and it["body"])


if __name__ == "__main__":
    unittest.main()
