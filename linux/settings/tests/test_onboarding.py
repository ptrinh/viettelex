"""Onboarding người dùng mới: hồ sơ → giá trị cài đặt, phát hiện người dùng cũ, bỏ qua giữ mặc định."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from viettelex_settings import config, onboarding  # noqa: E402

MIXED = ("auto_restore", "contextual_english", "retroactive_english", "english_by_frequency",
         "collision_prefers_vietnamese")


class Paths:
    def __init__(self):
        d = tempfile.mkdtemp()
        self.cfg = os.path.join(d, "config", "config.toml")
        self.state = os.path.join(d, "state", "onboarding")
        self.app_state = os.path.join(d, "state", "app-state")


def file_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class ProfileTests(unittest.TestCase):
    def test_vi_is_the_current_defaults(self):
        for (sec, key), v in onboarding.profile_values("vi").items():
            self.assertEqual(config.DEFAULTS[sec][key], v, key)

    def test_mixed_turns_every_mixed_switch_on(self):
        v = onboarding.profile_values("mixed")
        for key in MIXED:
            self.assertIs(v[("typing", key)], True, key)
        self.assertIs(v[("general", "default_vietnamese")], True)

    def test_en_is_mixed_plus_start_in_english(self):
        mixed, en = onboarding.profile_values("mixed"), onboarding.profile_values("en")
        for key in MIXED:
            self.assertEqual(en[("typing", key)], mixed[("typing", key)])
        self.assertIs(en[("general", "default_vietnamese")], False)

    def test_unknown_profile(self):
        with self.assertRaises(ValueError):
            onboarding.profile_values("fr")

    def test_turned_on(self):
        self.assertEqual(onboarding.turned_on("vi"),
                         [("typing", "auto_restore"), ("typing", "contextual_english"),
                          ("typing", "collision_prefers_vietnamese")])
        self.assertEqual(len(onboarding.turned_on("mixed")), 5)
        self.assertEqual(onboarding.turned_on("en")[-1], ("general", "default_vietnamese"))

    def test_apply_profile_writes_config(self):
        p = Paths()
        cfg = config.Config(p.cfg)
        onboarding.apply_profile(cfg, "en")
        again = config.Config(p.cfg)
        for (sec, key), v in onboarding.profile_values("en").items():
            self.assertEqual(again.get(sec, key), v, key)

    def test_apply_vi_on_fresh_config_writes_nothing(self):
        p = Paths()
        onboarding.apply_profile(config.Config(p.cfg), "vi")
        self.assertFalse(os.path.exists(p.cfg))

    def test_samples_exist_for_every_profile(self):
        for prof in onboarding.PROFILES:
            self.assertGreaterEqual(len(onboarding.SAMPLES[prof]), 2)
            self.assertTrue(onboarding.CARD_EXAMPLES[prof])


class DecideTests(unittest.TestCase):
    def test_decide_table(self):
        d = onboarding.decide
        self.assertEqual(d({}, False, False), "show")
        self.assertEqual(d({}, True, False), "upgrade")
        self.assertEqual(d({}, False, True), "upgrade")
        self.assertEqual(d({"done": "0"}, True, True), "show")
        self.assertEqual(d({"done": "1"}, False, False), "nothing")

    def test_state_round_trip(self):
        p = Paths()
        onboarding.save_state({"done": "1", "profile": "mixed", "card": "0"}, p.state)
        self.assertEqual(onboarding.load_state(p.state), {"done": "1", "profile": "mixed", "card": "0"})
        self.assertEqual(onboarding.load_state(p.state + ".missing"), {})
        self.assertEqual(onboarding.parse_state("# x\ndone = 1\nbad\n"), {"done": "1"})


class StartupTests(unittest.TestCase):
    def start(self, p):
        return onboarding.startup(p.cfg, p.state, p.app_state)

    def test_fresh_install_shows_and_stays_new_until_finished(self):
        p = Paths()
        self.assertEqual(self.start(p), "show")
        self.assertEqual(onboarding.load_state(p.state), {"done": "0"})
        # Lần mở sau, config.toml đã có (người dùng chỉnh gì đó) nhưng chưa xong ⇒ vẫn người mới.
        config.Config(p.cfg).set("typing", "teencode", True)
        self.assertEqual(self.start(p), "show")
        self.assertFalse(onboarding.card_pending(onboarding.load_state(p.state)))

    def test_skip_keeps_defaults(self):
        p = Paths()
        self.assertEqual(self.start(p), "show")
        st = onboarding.finish(None, p.state)
        self.assertEqual(st, {"done": "1"})
        self.assertFalse(os.path.exists(p.cfg))          # không ghi giá trị nào
        self.assertEqual(config.Config(p.cfg).data, config.normalize({}))
        self.assertEqual(self.start(p), "nothing")

    def test_finish_with_profile(self):
        p = Paths()
        self.start(p)
        self.assertEqual(onboarding.finish("mixed", p.state), {"done": "1", "profile": "mixed"})

    def upgrade_case(self, make):
        p = Paths()
        make(p)
        before = file_text(p.cfg) if os.path.exists(p.cfg) else None
        self.assertEqual(self.start(p), "nothing")
        st = onboarding.load_state(p.state)
        self.assertEqual(st, {"done": "1", "card": "1"})
        self.assertTrue(onboarding.card_pending(st))
        after = file_text(p.cfg) if os.path.exists(p.cfg) else None
        self.assertEqual(before, after)                  # không đổi giá trị nào của người cũ
        # Đóng thẻ ⇒ không hiện lại, kể cả lần mở sau.
        onboarding.dismiss_card(p.state)
        self.assertEqual(self.start(p), "nothing")
        self.assertFalse(onboarding.card_pending(onboarding.load_state(p.state)))

    def test_upgrade_with_existing_config(self):
        def make(p):
            os.makedirs(os.path.dirname(p.cfg))
            with open(p.cfg, "w", encoding="utf-8") as f:
                f.write("[typing]\nretroactive_english = false\nauto_restore = false\n")
        self.upgrade_case(make)

    def test_upgrade_with_only_app_state(self):
        def make(p):
            os.makedirs(os.path.dirname(p.app_state))
            with open(p.app_state, "w", encoding="utf-8") as f:
                f.write("kitty 0\n")
        self.upgrade_case(make)


if __name__ == "__main__":
    unittest.main()
