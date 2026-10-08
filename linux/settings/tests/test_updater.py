import hashlib
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from viettelex_settings import i18n, updater  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "..")
BASE = "https://github.com/ptrinh/viettelex/releases/download/linux-v1.0.4/"
SHA = "a" * 64

# stable.json thật hiện tại (1.8.1 macOS + windows, CHƯA có linux) — bug gốc: app so bản
# Linux với khoá gốc thì sẽ luôn báo "có bản mới 1.8.1" cho Linux 1.0.x.
LIVE_NO_LINUX = {
    "version": "1.8.1", "url": "https://github.com/ptrinh/viettelex/releases/tag/v1.8.1",
    "build": 110, "windows": {"version": "1.1.5"},
}


def lin(**kw):
    d = {"version": "1.0.4", "url": "https://github.com/ptrinh/viettelex/releases/tag/linux-v1.0.4",
         "download": BASE, "series": ["jammy", "noble"],
         "sha256": {n: SHA for n in (
             "libviettelex-core_1.0.4.noble1_amd64.deb", "viettelex-fcitx5_1.0.4.noble1_amd64.deb",
             "viettelex-settings_1.0.4.noble1_all.deb", "viettelex_1.0.4.noble1_all.deb")}}
    d.update(kw)
    return d


INSTALLED = {"libviettelex-core": "1.0.3~noble1", "viettelex-fcitx5": "1.0.3~noble1",
             "viettelex-settings": "1.0.3~noble1"}


class VersionTests(unittest.TestCase):
    def test_tuple(self):
        self.assertEqual(updater.version_tuple("1.0.3~noble1"), (1, 0, 3))
        self.assertEqual(updater.version_tuple("1.0"), updater.version_tuple("1.0.0"))
        self.assertGreater(updater.version_tuple("1.0.10"), updater.version_tuple("1.0.9"))


class StateTests(unittest.TestCase):
    def test_root_version_is_macos_not_linux(self):
        st, _ = updater.state(LIVE_NO_LINUX, "1.0.3")
        self.assertEqual(st, "noinfo")
        msg, url = updater.update_message(LIVE_NO_LINUX, "1.0.3")
        self.assertNotIn("1.8.1", msg)
        self.assertEqual(url, updater.RELEASES_URL)

    def test_older_equal_newer(self):
        info = dict(LIVE_NO_LINUX, linux=lin())
        self.assertEqual(updater.state(info, "1.0.3")[0], "available")
        self.assertEqual(updater.state(info, "1.0.4")[0], "latest")
        self.assertEqual(updater.state(info, "1.1.0")[0], "latest")
        self.assertEqual(updater.update_message(info, "1.0.3")[0], "Có bản mới: 1.0.4")
        self.assertEqual(updater.update_message(info, "1.0.4"),
                         ("Bạn đang dùng bản mới nhất (1.0.4).", None))

    def test_bad_linux_entry(self):
        for bad in (None, "1.0.4", {}, {"version": 104}):
            self.assertEqual(updater.state({"linux": bad}, "1.0.3")[0], "noinfo")
        self.assertEqual(updater.state([], "1.0.3")[0], "noinfo")

    def test_repo_stable_json_has_valid_linux_entry(self):
        path = os.path.join(ROOT, "docs", "stable.json")
        if not os.path.exists(path):  # cây nguồn gói .deb không kèm docs/
            self.skipTest("docs/stable.json không có trong cây này")
        with open(path, encoding="utf-8") as f:
            info = json.load(f)
        self.assertIsNotNone(updater.linux_info(info))
        # macOS/Windows giữ nguyên chỗ cũ.
        self.assertIn("version", info)
        self.assertIn("version", info["windows"])
        linux = info["linux"]
        self.assertTrue(linux["download"].startswith(updater.ALLOWED_DOWNLOAD_PREFIX))
        for name, sha in linux.get("sha256", {}).items():
            self.assertRegex(name, r"_%s\.[a-z]+1_(amd64|arm64|all)\.deb$" % linux["version"])
            self.assertRegex(sha, r"^[0-9a-f]{64}$")


class EnvTests(unittest.TestCase):
    def test_series(self):
        self.assertEqual(updater.series_from_version("1.0.3~jammy1"), "jammy")
        self.assertIsNone(updater.series_from_version("1.0.3"))
        mint = updater.parse_os_release('ID=linuxmint\nVERSION_CODENAME=wilma\nUBUNTU_CODENAME=noble\n')
        self.assertEqual(updater.detect_series({}, mint), "noble")
        self.assertEqual(updater.detect_series({"viettelex-ibus": "1.0.3~jammy1"}, mint), "jammy")
        self.assertEqual(updater.detect_series({}, {"VERSION_CODENAME": "noble"}), "noble")
        lmde = {"ID": "linuxmint", "VERSION_CODENAME": "faye", "DEBIAN_CODENAME": "bookworm"}
        self.assertEqual(updater.detect_series({}, lmde), "bookworm")
        self.assertEqual(updater.detect_series({"viettelex-fcitx5": "1.0.7~trixie1"}, lmde), "trixie")
        self.assertEqual(updater.series_from_version("1.0.7~resolute1"), "resolute")

    def test_dpkg_query(self):
        out = ("libviettelex-core 1.0.3~noble1 ii \nviettelex-ibus 1.0.2~noble1 rc \n"
               "viettelex-settings 1.0.3~noble1 ii \nfoo 1 ii \n")
        self.assertEqual(updater.parse_dpkg_query(out),
                         {"libviettelex-core": "1.0.3~noble1", "viettelex-settings": "1.0.3~noble1"})

    def test_apt_repo_configured(self):
        files = {"/etc/apt/sources.list.d/viettelex.sources":
                 "Types: deb\nURIs: https://ptrinh.github.io/viettelex-apt/\nSuites: noble\n"}
        self.assertEqual(updater.apt_repo_configured(lambda p: files.get(p, "")),
                         "/etc/apt/sources.list.d/viettelex.sources")
        commented = {"/etc/apt/sources.list.d/viettelex.list":
                     "# deb https://ptrinh.github.io/viettelex-apt/ noble main\n"}
        self.assertIsNone(updater.apt_repo_configured(lambda p: commented.get(p, "")))
        self.assertIsNone(updater.apt_repo_configured(lambda p: ""))


class PlanTests(unittest.TestCase):
    def test_apt_path_only_installed(self):
        p = updater.plan(lin(), INSTALLED, "noble", "amd64", "/etc/apt/sources.list.d/viettelex.sources")
        self.assertEqual(p, {"kind": "apt", "packages": [
            "libviettelex-core", "viettelex-fcitx5", "viettelex-settings"]})
        self.assertEqual(updater.helper_argv(p)[:3], ["pkexec", updater.HELPER, "apt"])

    def test_deb_path_names(self):
        p = updater.plan(lin(), INSTALLED, "noble", "amd64", None)
        self.assertEqual(p["kind"], "deb")
        names = [f[0] for f in p["files"]]
        self.assertEqual(names, ["libviettelex-core_1.0.4.noble1_amd64.deb",
                                 "viettelex-fcitx5_1.0.4.noble1_amd64.deb",
                                 "viettelex-settings_1.0.4.noble1_all.deb"])
        self.assertTrue(all(u == BASE + n for n, u, _ in p["files"]))
        self.assertEqual(updater.helper_argv(p, "/tmp/x"), ["pkexec", updater.HELPER, "deb", "/tmp/x"])

    def test_text_tools_updated_too(self):
        inst = dict(INSTALLED, **{"viettelex-text-tools": "1.0.3~noble1"})
        p = updater.plan(lin(sha256={}), inst, "noble", "amd64", "/etc/apt/sources.list.d/viettelex.sources")
        self.assertIn("viettelex-text-tools", p["packages"])
        self.assertEqual(updater.deb_asset_name("viettelex-text-tools", "1.0.4", "noble", "arm64"),
                         "viettelex-text-tools_1.0.4.noble1_arm64.deb")

    def test_deb_path_unsupported(self):
        self.assertEqual(updater.plan(lin(), INSTALLED, "resolute", "amd64", None)["kind"], "unsupported")
        self.assertEqual(updater.plan(lin(), INSTALLED, "noble", "riscv64", None)["kind"], "unsupported")
        self.assertEqual(updater.plan(lin(), {}, "noble", "amd64", None)["kind"], "unsupported")
        # thiếu checksum → không cài
        self.assertEqual(updater.plan(lin(sha256={}), INSTALLED, "noble", "amd64", None)["kind"],
                         "unsupported")
        # host lạ → không tải
        evil = lin(download="https://evil.example/")
        self.assertEqual(updater.plan(evil, INSTALLED, "noble", "amd64", None)["kind"], "unsupported")
        self.assertFalse(updater.is_allowed_download("https://evil.example/x.deb"))
        self.assertTrue(updater.is_allowed_download(BASE + "viettelex_1.0.4.noble1_all.deb"))


class ChecksumAndResultTests(unittest.TestCase):
    def test_verify(self):
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(b"deb")
        try:
            good = hashlib.sha256(b"deb").hexdigest()
            self.assertTrue(updater.verify_sha256(f.name, good))
            self.assertTrue(updater.verify_sha256(f.name, good.upper()))
            self.assertFalse(updater.verify_sha256(f.name, SHA))
            self.assertFalse(updater.verify_sha256(f.name + ".missing", good))
        finally:
            os.unlink(f.name)

    def test_messages(self):
        ok, m = updater.result_message(0, "", "1.0.4")
        self.assertTrue(ok)
        self.assertIn("1.0.4", m)
        self.assertIn("Khởi động lại bộ gõ", m)
        for code in (126, 127):
            ok, m = updater.result_message(code, "", "1.0.4")
            self.assertFalse(ok)
            self.assertIn("huỷ", m)
        self.assertIn("bận", updater.result_message(3, "", "1.0.4")[1])
        self.assertIn("bận", updater.result_message(
            4, "E: Could not get lock /var/lib/dpkg/lock-frontend", "1.0.4")[1])
        out = "\n".join("line %d" % i for i in range(20)) + "\nE: Broken packages"
        ok, m = updater.result_message(4, out, "1.0.4")
        self.assertFalse(ok)
        self.assertIn("E: Broken packages", m)
        self.assertNotIn("line 5\n", m)

    def test_english(self):
        i18n.set_language("en")
        try:
            info = dict(LIVE_NO_LINUX, linux=lin())
            self.assertEqual(updater.update_message(info, "1.0.3")[0], "New version available: 1.0.4")
            self.assertIn("Cancelled", updater.result_message(126, "", "1.0.4")[1])
            self.assertIn("Updated to 1.0.4", updater.result_message(0, "", "1.0.4")[1])
        finally:
            i18n.set_language("vi")

    def test_restart(self):
        self.assertEqual(updater.restart_im_argv("fcitx5"), ["fcitx5", "-r", "-d"])
        self.assertEqual(updater.restart_im_argv("ibus"), ["ibus", "restart"])
        self.assertIsNone(updater.restart_im_argv(None))


if __name__ == "__main__":
    unittest.main()
