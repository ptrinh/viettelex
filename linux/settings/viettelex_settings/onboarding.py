"""Onboarding người dùng mới + thẻ "Gõ mixed Việt/Anh" cho người dùng cũ (docs/ONBOARDING-SPEC.md).

Hàm thuần (không GTK) để test chạy ở mọi máy.

- Hồ sơ = bộ giá trị cụ thể ghi thẳng vào config.toml (không lưu "chế độ" nào chi phối về sau).
- Trạng thái onboarding nằm NGOÀI config.toml (hợp đồng cài đặt với frontend giữ nguyên):
  $XDG_STATE_HOME/viettelex/onboarding, mỗi dòng "key=value":
    done=0|1      0 = người mới chưa xong (lần mở sau vẫn hiện), 1 = xong / bỏ qua / người cũ
    profile=…     vi | mixed | en — chỉ để hiển thị, không điều khiển hành vi
    card=0|1      1 = còn hiện thẻ "Gõ mixed Việt/Anh" (người dùng cũ), đóng là 0 mãi mãi
"""

import os

from . import config

PROFILES = ("vi", "mixed", "en")

# Công tắc gõ trộn theo thứ tự hiện ở màn "Gõ thử" (section, key).
MIXED_KEYS = (
    ("typing", "auto_restore"),
    ("typing", "contextual_english"),
    ("typing", "retroactive_english"),
    ("typing", "english_by_frequency"),
    ("typing", "collision_prefers_vietnamese"),
)
START_KEY = ("general", "default_vietnamese")

# Câu mẫu cho ô gõ thử (ví dụ gõ — không dịch).
SAMPLES = {
    "vi": ("Chiều nay mình đi cà phê nhé", "Cảm ơn bạn rất nhiều"),
    "mixed": ("Mai họp team lúc 9h, nhớ confirm nhé", "Chiều nay họp team, nhớ check mail nha",
              "File design mình gửi qua email rồi"),
    "en": ("See you at the meeting, nhớ mang laptop nhé", "Thanks, mai gặp nhé",
           "Please review the PR trước 5h"),
}
# Câu ví dụ trên thẻ của màn 1.
CARD_EXAMPLES = {
    "vi": "Chiều nay mình đi cà phê nhé",
    "mixed": "Chiều nay họp team, nhớ check mail nha",
    "en": "See you at the meeting, nhớ mang laptop nhé",
}


def profile_values(profile):
    """{(section, key): value} mà hồ sơ ghi vào config.toml. Hồ sơ lạ ⇒ ValueError."""
    if profile not in PROFILES:
        raise ValueError(profile)
    mixed = profile != "vi"
    return {
        ("typing", "auto_restore"): True,
        ("typing", "contextual_english"): True,
        ("typing", "retroactive_english"): mixed,
        ("typing", "english_by_frequency"): mixed,
        ("typing", "collision_prefers_vietnamese"): True,
        # Linux có chế độ tiếng Anh: hồ sơ "en" cho app mới mở bắt đầu bằng tiếng Anh.
        START_KEY: profile != "en",
    }


def apply_profile(cfg, profile):
    """Ghi bộ giá trị của hồ sơ (một lần ghi file)."""
    values = profile_values(profile)
    changes = {k: v for k, v in values.items() if cfg.get(*k) != v}
    if changes:
        cfg.apply(changes)


def turned_on(profile):
    """Công tắc hồ sơ BẬT (hiện ở màn Gõ thử, mỗi dòng một công tắc).
    Phần tử ("general", "default_vietnamese") = dòng "Bắt đầu bằng tiếng Anh" (đảo ngược)."""
    values = profile_values(profile)
    out = [k for k in MIXED_KEYS if values[k]]
    if not values[START_KEY]:
        out.append(START_KEY)
    return out


# ---------------------------------------------------------------- bộ chọn nhanh (§4)
# Đầu nhóm "Gõ mixed Việt/Anh" trong Cài đặt: ba hồ sơ + "Tuỳ chỉnh" — y như iOS/Android
# (iOS Shared/OnboardingProfile.swift OnboardingSettings, Android ui/MixedTyping.kt).

PROFILE_KEYS = MIXED_KEYS + (START_KEY,)


def current_values(cfg):
    """{(section, key): value} đang có của đúng các key hồ sơ ghi."""
    return {k: bool(cfg.get(*k)) for k in PROFILE_KEYS}


def match(current, last_chosen=None):
    """Hồ sơ khớp ĐÚNG cài đặt hiện tại; None = "Tuỳ chỉnh". Hai hồ sơ cùng bộ công tắc (nền
    tảng không có chế độ tiếng Anh) ⇒ tô hồ sơ chọn gần nhất nếu nó là một trong hai, không thì
    hồ sơ đứng trước (`mixed`)."""
    hits = [p for p in PROFILES if profile_values(p) == current]
    if not hits:
        return None
    return last_chosen if last_chosen in hits else hits[0]


def changes(current, profile):
    """Key sẽ đổi nếu áp `profile` (theo thứ tự PROFILE_KEYS)."""
    target = profile_values(profile)
    return [k for k in PROFILE_KEYS if current.get(k) != target[k]]


def needs_confirmation(current, profile, last_chosen=None):
    """Hỏi xác nhận khi cài đặt đang "Tuỳ chỉnh" (người dùng đã tự chỉnh) và áp sẽ đổi ≥ 1
    công tắc; đang khớp một hồ sơ thì đổi thẳng."""
    return match(current, last_chosen) is None and bool(changes(current, profile))


def pick_profile(cfg, profile, state_file=None):
    """Áp hồ sơ từ bộ chọn nhanh: giá trị §3 + ghi `profile` (không đụng `done` / `card`)."""
    apply_profile(cfg, profile)
    return update_state(state_file, profile=profile)


def last_profile(state=None):
    st = load_state() if state is None else state
    p = st.get("profile")
    return p if p in PROFILES else None


# ---------------------------------------------------------------- trạng thái

def state_path():
    return os.path.join(config.state_dir(), "onboarding")


def parse_state(text):
    out = {}
    for line in text.split("\n"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def dump_state(state):
    return "".join("%s=%s\n" % (k, state[k]) for k in sorted(state))


def load_state(path=None):
    try:
        with open(path or state_path(), encoding="utf-8") as f:
            return parse_state(f.read())
    except (OSError, UnicodeDecodeError):
        return {}


def save_state(state, path=None):
    config.atomic_write(path or state_path(), dump_state(state))


def update_state(path=None, **changes):
    st = load_state(path)
    st.update({k: str(v) for k, v in changes.items()})
    save_state(st, path)
    return st


def decide(state, config_exists, app_state_exists):
    """"show" (người mới: chạy onboarding) | "upgrade" (người cũ lần đầu gặp bản có onboarding:
    đánh dấu xong + bật thẻ, KHÔNG đổi cài đặt) | "nothing"."""
    if "done" in state:
        return "show" if state["done"] == "0" else "nothing"
    if config_exists or app_state_exists:
        return "upgrade"
    return "show"


def startup(cfg_path=None, state_file=None, app_state_file=None):
    """Quyết định lúc mở app + ghi trạng thái tương ứng. Trả "show" | "nothing".

    Người mới: ghi done=0 NGAY (lần mở sau, khi config.toml đã có, vẫn là người mới).
    Người cũ: done=1, card=1; không chạm config.toml."""
    cfg_path = cfg_path or os.path.join(config.config_dir(), "config.toml")
    app_state_file = app_state_file or os.path.join(config.state_dir(), "app-state")
    st = load_state(state_file)
    d = decide(st, os.path.exists(cfg_path), os.path.exists(app_state_file))
    if d == "upgrade":
        update_state(state_file, done=1, card=1)
        return "nothing"
    if d == "show" and "done" not in st:
        update_state(state_file, done=0)
    return d


def finish(profile=None, state_file=None):
    """Xong / bỏ qua / đóng cửa sổ: done=1; profile chỉ ghi khi người dùng đã chọn."""
    changes = {"done": 1}
    if profile in PROFILES:
        changes["profile"] = profile
    return update_state(state_file, **changes)


def card_pending(state=None):
    st = load_state() if state is None else state
    return st.get("card") == "1"


def dismiss_card(state_file=None):
    return update_state(state_file, card=0)
