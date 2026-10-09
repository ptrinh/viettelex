"""launchers.py: chèn cờ IME Wayland vào Exec=, tạo/làm mới/gỡ file .desktop của người dùng,
quy tắc sở hữu, đồng bộ danh sách app với isChromiumApp (app.cpp), ghi config khi bật/tắt."""

import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, ".."))
from viettelex_settings import config, launchers as L  # noqa: E402

APP_CPP = os.path.join(HERE, "..", "..", "common", "src", "app.cpp")
F = L.flags_for("3")
FS = " ".join(F)


class ExecRewriteTests(unittest.TestCase):
    def rw(self, value):
        return L.rewrite_exec(value, F)

    def test_plain(self):
        self.assertEqual(self.rw("/usr/bin/google-chrome-stable"),
                         ("/usr/bin/google-chrome-stable " + FS, "ok"))

    def test_field_code_stays_last(self):
        self.assertEqual(self.rw("/usr/bin/google-chrome-stable %U"),
                         ("/usr/bin/google-chrome-stable %s %%U" % FS, "ok"))
        self.assertEqual(self.rw("/usr/share/code/code --unity-launch %F")[0],
                         "/usr/share/code/code %s --unity-launch %%F" % FS)

    def test_existing_args_kept(self):
        self.assertEqual(self.rw("/usr/bin/google-chrome-stable --incognito")[0],
                         "/usr/bin/google-chrome-stable %s --incognito" % FS)

    def test_quoted_path_with_space(self):
        v = '"/opt/My App/my app" --foo %U'
        self.assertEqual(self.rw(v)[0], '"/opt/My App/my app" %s --foo %%U' % FS)

    def test_quoted_arg_with_escaped_quote(self):
        v = '/opt/x/app "--title=a \\\\"b\\\\" c" %U'
        new, st = self.rw(v)
        self.assertEqual(st, "ok")
        self.assertEqual(new, '/opt/x/app %s "--title=a \\\\"b\\\\" c" %%U' % FS)

    def test_env_prefix(self):
        self.assertEqual(self.rw("env FOO=1 BAR=2 /opt/x %U")[0], "env FOO=1 BAR=2 /opt/x %s %%U" % FS)
        self.assertEqual(self.rw("/usr/bin/env -u GTK_IM_MODULE FOO=1 /opt/x")[0],
                         "/usr/bin/env -u GTK_IM_MODULE FOO=1 /opt/x " + FS)

    def test_snap(self):
        v = "env BAMF_DESKTOP_FILE_HINT=/var/lib/snapd/desktop/applications/chromium_chromium.desktop /snap/bin/chromium %U"
        self.assertEqual(self.rw(v)[0], v.replace("/snap/bin/chromium", "/snap/bin/chromium " + FS))
        self.assertEqual(self.rw("snap run code --new-window")[0], "snap run code %s --new-window" % FS)
        self.assertEqual(L.program_of(v), ("snap", "chromium"))

    def test_flatpak(self):
        v = ("/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=/app/bin/chrome "
             "--file-forwarding com.google.Chrome @@u %U @@")
        self.assertEqual(self.rw(v)[0], v.replace("com.google.Chrome", "com.google.Chrome " + FS))
        self.assertEqual(L.program_of(v), ("flatpak", "com.google.Chrome"))
        v2 = "flatpak run com.visualstudio.code --new-window"
        self.assertEqual(self.rw(v2)[0], "flatpak run com.visualstudio.code %s --new-window" % FS)

    def test_flatpak_shell_command_unsupported(self):
        v = "flatpak run --command=sh com.x.App -c 'app --x'"
        self.assertEqual(self.rw(v), (v, "unsupported"))

    def test_shell_wrappers_unsupported(self):
        for v in ('sh -c "exec /opt/x %U"', "bash -c 'x'", "gtk-launch foo", ""):
            self.assertEqual(self.rw(v)[1], "unsupported" if v else "unsupported", v)

    def test_idempotent(self):
        once, _ = self.rw("/opt/x %U")
        self.assertEqual(self.rw(once), (once, "already"))

    def test_only_missing_flags_added(self):
        v = "/opt/x --enable-wayland-ime --wayland-text-input-version=1 %U"
        self.assertEqual(self.rw(v)[0],
                         "/opt/x --ozone-platform-hint=auto --enable-wayland-ime "
                         "--wayland-text-input-version=1 %U")

    def test_x11_forced_left_alone(self):
        for v in ("/opt/x --ozone-platform=x11 %U", "env GDK_BACKEND=x11 /opt/x",
                  "env ELECTRON_OZONE_PLATFORM_HINT=x11 /opt/x", "/opt/x --ozone-platform x11",
                  "/opt/x --disable-wayland-ime"):
            self.assertEqual(self.rw(v), (v, "x11"), v)


CHROME = """[Desktop Entry]
Version=1.0
Name=Google Chrome
Name[vi]=Google Chrome
# comment kept
Exec=/usr/bin/google-chrome-stable %U
StartupNotify=true
Terminal=false
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;
Actions=new-window;new-private-window;
StartupWMClass=Google-chrome
TryExec=/usr/bin/google-chrome-stable

[Desktop Action new-window]
Name=New Window
Exec=/usr/bin/google-chrome-stable

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=/usr/bin/google-chrome-stable --incognito
"""


class BuildOverrideTests(unittest.TestCase):
    def test_main_and_actions(self):
        out, st = L.build_override(CHROME, F, "/usr/share/applications/google-chrome.desktop")
        self.assertEqual(st, "ok")
        lines = out.split("\n")
        self.assertEqual(lines[0], "[Desktop Entry]")
        self.assertEqual(lines[1], "%s=%s" % (L.MARKER_KEY, L.source_hash(CHROME, F)))
        self.assertIn("Exec=/usr/bin/google-chrome-stable %s %%U" % FS, lines)
        self.assertIn("Exec=/usr/bin/google-chrome-stable " + FS, lines)
        self.assertIn("Exec=/usr/bin/google-chrome-stable %s --incognito" % FS, lines)
        # giữ nguyên các key khác
        for keep in ("TryExec=/usr/bin/google-chrome-stable", "Icon=google-chrome",
                     "StartupWMClass=Google-chrome", "# comment kept", "Name[vi]=Google Chrome"):
            self.assertIn(keep, lines)
        self.assertEqual(L.marker_of(out), L.source_hash(CHROME, F))
        # bỏ dòng thêm vào thì còn lại đúng nguồn với Exec đã đổi
        stripped = "\n".join(l for l in lines if not l.startswith("X-VietTelex-"))
        self.assertEqual(stripped, CHROME.replace("google-chrome-stable %U",
                                                  "google-chrome-stable %s %%U" % FS)
                         .replace("\nExec=/usr/bin/google-chrome-stable\n",
                                  "\nExec=/usr/bin/google-chrome-stable %s\n" % FS)
                         .replace("stable --incognito", "stable %s --incognito" % FS))

    def test_already_flagged_source(self):
        src = CHROME.replace("/usr/bin/google-chrome-stable", "/usr/bin/google-chrome-stable " + FS)
        self.assertEqual(L.build_override(src, F), (None, "already"))

    def test_x11_source(self):
        src = CHROME.replace("Exec=/usr/bin/google-chrome-stable %U",
                             "Exec=/usr/bin/google-chrome-stable --ozone-platform=x11 %U")
        self.assertEqual(L.build_override(src, F), (None, "x11"))

    def test_invalid_and_dbus(self):
        self.assertEqual(L.build_override("[Desktop Entry]\nType=Link\nURL=x\n", F)[1], "invalid")
        self.assertEqual(L.build_override(CHROME.replace("Type=Application", "Hidden=true"), F)[1],
                         "invalid")
        self.assertEqual(L.build_override(CHROME + "", F)[1], "ok")
        self.assertEqual(L.build_override(CHROME.replace("Terminal=false", "DBusActivatable=true"),
                                          F)[1], "dbus")

    def test_hash_changes_with_source_and_flags(self):
        h = L.source_hash(CHROME, F)
        self.assertNotEqual(h, L.source_hash(CHROME + "\n", F))
        self.assertNotEqual(h, L.source_hash(CHROME, L.flags_for("1")))


class MatchTests(unittest.TestCase):
    def test_desktop_ids(self):
        for did in ("google-chrome.desktop", "com.google.Chrome.desktop", "code.desktop",
                    "code_code.desktop", "chromium_chromium.desktop", "org.chromium.Chromium.desktop",
                    "com.visualstudio.code.desktop", "com.slack.Slack.desktop",
                    "com.discordapp.Discord.desktop", "md.obsidian.Obsidian.desktop",
                    "brave-browser.desktop", "microsoft-edge.desktop", "antigravity.desktop",
                    "com.brave.Browser.desktop", "chrome-abcdef-Default.desktop"):
            self.assertTrue(L.is_chromium_app(did), did)
        for did in ("firefox.desktop", "org.gnome.gedit.desktop", "chrome-remote-desktop-host",
                    "code-url-handler.desktop"):
            self.assertFalse(L.is_chromium_app(did), did)

    def test_names_in_sync_with_app_cpp(self):
        """CHROMIUM_NAMES == tập `names` trong isChromiumApp của linux/common/src/app.cpp."""
        with open(APP_CPP, encoding="utf-8") as f:
            src = f.read()
        m = re.search(r"bool isChromiumApp\(.*?\{\s*static const std::set<std::string> names = \{"
                      r"(.*?)\};", src, re.S)
        self.assertIsNotNone(m, "không tìm thấy isChromiumApp trong app.cpp")
        body = re.sub(r"//[^\n]*", "", m.group(1))
        cpp = set(re.findall(r'"([^"]*)"', body))
        self.assertEqual(cpp - L.CHROMIUM_NAMES, set(), "thiếu trong launchers.py")
        self.assertEqual(L.CHROMIUM_NAMES - cpp, set(), "thừa trong launchers.py")
        # các quy tắc tiền tố cũng có mặt bên C++
        for frag in ('startsWith(id, "appimagekit")', 'startsWith(id, "crx_")',
                     '"-default"', 'startsWith(id, "electron")'):
            self.assertIn(frag, src)


class VersionTests(unittest.TestCase):
    def test_versions(self):
        st = ("Package: google-chrome-stable\nStatus: install ok installed\nVersion: 141.0.7390.54-1\n\n"
              "Package: chromium-browser\nVersion: 2:1snap1-0ubuntu2\n\n"
              "Package: microsoft-edge-stable\nVersion: 139.0.3405.86-1\n")
        v = L.dpkg_versions(st, set(L.DEB_PACKAGES.values()) | {"chromium-browser"})
        self.assertEqual(L.chromium_major(v["google-chrome-stable"]), 141)
        self.assertIsNone(L.chromium_major(v["chromium-browser"]))
        self.assertEqual(L.chromium_major(v["microsoft-edge-stable"]), 139)

    def test_default_on_versions_from_root(self):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(root + "/var/lib/dpkg")
            os.makedirs(root + "/snap/chromium/current/meta")
            with open(root + "/var/lib/dpkg/status", "w") as f:
                f.write("Package: google-chrome-stable\nVersion: 150.0.1.2-1\n")
            with open(root + "/snap/chromium/current/meta/snap.yaml", "w") as f:
                f.write("name: chromium\nversion: '148.0.7000.1'\n")
            self.assertEqual(L.default_on_versions(root),
                             {"google-chrome.desktop": 150, "chromium_chromium.desktop": 148})

    def test_text_input_version(self):
        self.assertEqual(L.text_input_version("ubuntu:GNOME", None), "3")
        self.assertEqual(L.text_input_version("KDE", (6, 6)), "1")
        self.assertEqual(L.text_input_version("KDE", (6, 7)), "3")
        self.assertEqual(L.text_input_version("KDE", None), "3")

    def test_kwin_version_parse(self):
        class R:
            stdout, stderr = "kwin 6.6.4\n", ""
        self.assertEqual(L.kwin_version(run=lambda *a, **k: R(), which=lambda b: "/usr/bin/" + b),
                         (6, 6))
        self.assertIsNone(L.kwin_version(which=lambda b: None))

    def test_applicability(self):
        self.assertEqual(L.applicability("x11", "ubuntu:GNOME", "ibus"), "not_wayland")
        self.assertEqual(L.applicability("", "ubuntu:GNOME", "ibus"), "not_wayland")
        self.assertEqual(L.applicability("wayland", "zorin:GNOME", "fcitx5"), "ok")
        self.assertEqual(L.applicability("wayland", "ubuntu:GNOME", "ibus"), "ok")
        self.assertEqual(L.applicability("wayland", "KDE", "fcitx5"), "ok")
        self.assertEqual(L.applicability("wayland", "KDE", "ibus"), "kde_ibus")
        self.assertEqual(L.applicability("wayland", "sway", "fcitx5"), "unsupported_desktop")


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        r = self.tmp.name
        self.sys = os.path.join(r, "usr/share/applications")
        self.flat = os.path.join(r, "flatpak/exports/share/applications")
        self.user = os.path.join(r, "home/.local/share/applications")
        for d in (self.sys, self.flat):
            os.makedirs(d)
        self.env = {"HOME": os.path.join(r, "home"),
                    "XDG_DATA_HOME": os.path.join(r, "home/.local/share"),
                    "XDG_DATA_DIRS": os.path.join(r, "usr/share")}
        self.dirs = L.source_dirs(self.env, extra=[os.path.join(r, "flatpak/exports/share")])
        self.put(self.sys, "google-chrome.desktop", CHROME)
        self.put(self.sys, "code.desktop", "[Desktop Entry]\nName=Visual Studio Code\nType=Application\n"
                 "Exec=/usr/share/code/code %F\nStartupWMClass=Code\n")
        self.put(self.sys, "code-url-handler.desktop", "[Desktop Entry]\nName=Visual Studio Code - URL "
                 "Handler\nType=Application\nNoDisplay=true\nExec=/usr/share/code/code --open-url %U\n"
                 "StartupWMClass=Code\n")
        self.put(self.sys, "firefox.desktop", "[Desktop Entry]\nName=Firefox\nType=Application\n"
                 "Exec=firefox %u\n")
        self.put(self.flat, "com.slack.Slack.desktop", "[Desktop Entry]\nName=Slack\nType=Application\n"
                 "Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=slack "
                 "--file-forwarding com.slack.Slack @@u %U @@\nX-Flatpak=com.slack.Slack\n")

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, d, name, text):
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, name), "w", encoding="utf-8") as f:
            f.write(text)

    def get(self, name):
        with open(os.path.join(self.user, name), encoding="utf-8") as f:
            return f.read()

    def sync(self, enabled=True, **kw):
        kw.setdefault("refresh_db", False)
        return L.sync(enabled, env=self.env, dirs=self.dirs, flags=F, **kw)

    def ids(self, items):
        return sorted(i[0] for i in items)

    def test_source_dirs_order_and_excludes_user(self):
        env = dict(self.env, XDG_DATA_DIRS="/a:/b:" + self.env["XDG_DATA_HOME"])
        self.assertEqual(L.source_dirs(env, extra=["/b", "/c"]),
                         ["/a/applications", "/b/applications", "/c/applications"])

    def test_create_then_unchanged(self):
        rep = self.sync()
        self.assertEqual(self.ids(rep["created"]), ["code-url-handler.desktop", "code.desktop",
                                                    "com.slack.Slack.desktop", "google-chrome.desktop"])
        self.assertFalse(os.path.exists(os.path.join(self.user, "firefox.desktop")))
        self.assertIn("com.slack.Slack " + FS + " @@u %U @@", self.get("com.slack.Slack.desktop"))
        self.assertIn("X-Flatpak=com.slack.Slack", self.get("com.slack.Slack.desktop"))
        rep2 = self.sync()
        self.assertEqual(rep2["created"] + rep2["updated"] + rep2["removed"], [])
        self.assertEqual(len(rep2["unchanged"]), 4)

    def test_source_changed_regenerates(self):
        self.sync()
        self.put(self.sys, "google-chrome.desktop", CHROME.replace("Name=Google Chrome\n",
                                                                   "Name=Google Chrome (new)\n"))
        rep = self.sync()
        self.assertEqual(self.ids(rep["updated"]), ["google-chrome.desktop"])
        self.assertIn("Name=Google Chrome (new)", self.get("google-chrome.desktop"))

    def test_source_removed_deletes_ours(self):
        self.sync()
        os.remove(os.path.join(self.flat, "com.slack.Slack.desktop"))
        rep = self.sync()
        self.assertEqual(self.ids(rep["removed"]), ["com.slack.Slack.desktop"])
        self.assertFalse(os.path.exists(os.path.join(self.user, "com.slack.Slack.desktop")))

    def test_disable_deletes_only_ours(self):
        self.sync()
        self.put(self.user, "my-notes.desktop", "[Desktop Entry]\nName=Mine\nExec=/opt/mine\n")
        self.put(self.user, "mimeapps.list", "[Default Applications]\n")
        rep = self.sync(enabled=False)
        self.assertEqual(len(rep["removed"]), 4)
        self.assertEqual(sorted(os.listdir(self.user)), ["mimeapps.list", "my-notes.desktop"])

    def test_user_override_never_overwritten(self):
        mine = "[Desktop Entry]\nName=My Chrome\nType=Application\nExec=/usr/bin/google-chrome-stable --foo\n"
        self.put(self.user, "google-chrome.desktop", mine)
        flagged = "[Desktop Entry]\nName=Code\nType=Application\nExec=/usr/share/code/code %s\n" % FS
        self.put(self.user, "code.desktop", flagged)
        rep = self.sync()
        self.assertEqual(self.ids(rep["conflicts"]), ["google-chrome.desktop"])
        self.assertEqual(self.ids(rep["user_configured"]), ["code.desktop"])
        self.assertEqual(self.get("google-chrome.desktop"), mine)
        self.assertEqual(self.get("code.desktop"), flagged)
        rep = self.sync(enabled=False)
        self.assertEqual(self.get("google-chrome.desktop"), mine)   # tắt cũng không đụng
        self.assertEqual(self.get("code.desktop"), flagged)

    def test_user_symlink_is_not_ours(self):
        os.makedirs(self.user)
        os.symlink(os.path.join(self.sys, "google-chrome.desktop"),
                   os.path.join(self.user, "google-chrome.desktop"))
        rep = self.sync()
        self.assertEqual(self.ids(rep["conflicts"]), ["google-chrome.desktop"])
        self.assertTrue(os.path.islink(os.path.join(self.user, "google-chrome.desktop")))

    def test_create_new_false_only_refreshes(self):
        rep = self.sync(create_new=False)
        self.assertEqual(rep["created"], [])
        self.assertFalse(os.path.exists(self.user) and os.listdir(self.user))
        self.sync()
        os.remove(os.path.join(self.sys, "code.desktop"))
        rep = self.sync(create_new=False)
        self.assertEqual(self.ids(rep["removed"]), ["code.desktop"])
        self.assertIn("google-chrome.desktop", self.ids(rep["unchanged"]))

    def test_default_on_skipped_and_removed(self):
        self.sync()
        rep = self.sync(default_on={"google-chrome.desktop": 141})
        self.assertEqual(self.ids(rep["default_on"]), ["google-chrome.desktop"])
        self.assertEqual(self.ids(rep["removed"]), ["google-chrome.desktop"])
        rep = self.sync(default_on={"google-chrome.desktop": 139})
        self.assertEqual(self.ids(rep["created"]), ["google-chrome.desktop"])
        # KDE cũ cần v1 ⇒ vẫn thêm cờ dù Chrome mới
        rep = L.sync(True, env=self.env, dirs=self.dirs, flags=L.flags_for("1"),
                     default_on={"google-chrome.desktop": 150}, refresh_db=False)
        self.assertEqual(rep["default_on"], [])
        self.assertIn("--wayland-text-input-version=1", self.get("google-chrome.desktop"))

    def test_flags_change_regenerates(self):
        self.sync()
        rep = L.sync(True, env=self.env, dirs=self.dirs, flags=L.flags_for("1"), refresh_db=False)
        self.assertEqual(len(rep["updated"]), 4)

    def test_x11_forced_source_reported(self):
        self.put(self.sys, "discord.desktop", "[Desktop Entry]\nName=Discord\nType=Application\n"
                 "Exec=/usr/bin/discord --ozone-platform=x11\n")
        rep = self.sync()
        self.assertEqual(self.ids(rep["x11"]), ["discord.desktop"])
        self.assertFalse(os.path.exists(os.path.join(self.user, "discord.desktop")))

    def test_first_dir_wins(self):
        # cùng desktop id ở hai nơi: nơi ưu tiên cao (đứng trước) là nguồn
        self.put(self.flat, "google-chrome.desktop", CHROME.replace("Google Chrome", "Other"))
        self.sync()
        self.assertIn("Name=Google Chrome", self.get("google-chrome.desktop"))
        self.assertIn(L.SOURCE_KEY + "=" + os.path.join(self.sys, "google-chrome.desktop"),
                      self.get("google-chrome.desktop"))

    def test_update_desktop_database_called_only_on_change(self):
        calls = []
        self.sync(refresh_db=True, run=lambda argv, **k: calls.append(argv),
                  which=lambda b: "/usr/bin/" + b)
        self.assertEqual(calls, [["/usr/bin/update-desktop-database", "-q", self.user]])
        self.sync(refresh_db=True, run=lambda argv, **k: calls.append(argv),
                  which=lambda b: "/usr/bin/" + b)
        self.assertEqual(len(calls), 1)

        def boom(*a, **k):
            raise OSError("x")
        self.sync(enabled=False, refresh_db=True, run=boom, which=lambda b: "/usr/bin/" + b)


class RunningTests(unittest.TestCase):
    def test_running_without_flag(self):
        with tempfile.TemporaryDirectory() as proc:
            def pid(n, argv, cgroup=""):
                os.makedirs(os.path.join(proc, str(n)))
                with open(os.path.join(proc, str(n), "cmdline"), "wb") as f:
                    f.write(b"\0".join(a.encode() for a in argv) + b"\0")
                with open(os.path.join(proc, str(n), "cgroup"), "w") as f:
                    f.write(cgroup)
            pid(10, ["/usr/bin/google-chrome-stable"])                         # cũ, không cờ
            pid(11, ["/usr/bin/google-chrome-stable", "--type=renderer"])      # con: bỏ qua
            pid(20, ["/usr/share/code/code", L.ENABLE_IME])                   # đã có cờ
            pid(30, ["/app/slack/slack"], "0::/user.slice/app-flatpak-com.slack.Slack-123.scope\n")
            entries = [
                ("google-chrome.desktop", "Chrome", "[Desktop Entry]\nExec=/usr/bin/google-chrome-stable %s %%U\n" % FS),
                ("code.desktop", "Code", "[Desktop Entry]\nExec=/usr/share/code/code %s %%F\n" % FS),
                ("com.slack.Slack.desktop", "Slack", "[Desktop Entry]\nExec=flatpak run com.slack.Slack %s\n" % FS),
                ("discord.desktop", "Discord", "[Desktop Entry]\nExec=/usr/bin/discord %s\n" % FS),
                ("google-chrome-a.desktop", "Chrome URL", "[Desktop Entry]\nNoDisplay=true\n"
                 "Exec=/usr/bin/google-chrome-stable %s --x\n" % FS),
            ]
            self.assertEqual(L.running_without_flag(entries, proc=proc),
                             [("com.slack.Slack.desktop", "Slack"), ("google-chrome.desktop", "Chrome")])


class ConfigToggleTests(unittest.TestCase):
    def test_default_off_and_normalize(self):
        self.assertEqual(config.normalize({})["experimental"]["no_underline"], "off")
        d = config.normalize(config.parse('[experimental]\nno_underline = "weird"\n'))
        self.assertEqual(d["experimental"]["no_underline"], "off")
        d = config.normalize(config.parse('[experimental]\nno_underline = "forward-keys"\n'))
        self.assertEqual(d["experimental"]["no_underline"], "forward-keys")

    def test_toggle_writes_in_place(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "config.toml")
            original = ('# my comment\n[typing]\ninput_method = "telex"  # keep\n\n'
                        '[general]\nfoo_unknown = 3\n')
            with open(p, "w") as f:
                f.write(original)
            c = config.Config(p)
            c.set("experimental", "no_underline", "forward-keys")
            with open(p) as f:
                on = f.read()
            self.assertTrue(on.startswith(original))
            self.assertIn('[experimental]\nno_underline = "forward-keys"\n', on)
            c.set("experimental", "no_underline", "off")
            with open(p) as f:
                off = f.read()
            self.assertEqual(off, on.replace('"forward-keys"', '"off"'))
            self.assertEqual(config.Config(p).get("experimental", "no_underline"), "off")
            self.assertFalse(os.path.exists(p + ".tmp"))

    def test_existing_experimental_line_kept_with_comment(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "config.toml")
            with open(p, "w") as f:
                f.write('[experimental]\nno_underline = "off"   # thử\nother = true\n')
            config.Config(p).set("experimental", "no_underline", "forward-keys")
            with open(p) as f:
                self.assertEqual(f.read(), '[experimental]\nno_underline = "forward-keys"  # thử\n'
                                           'other = true\n')


if __name__ == "__main__":
    unittest.main()
