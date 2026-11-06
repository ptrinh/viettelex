"""Bố cục cài đặt (docs/SETTINGS-CLEANUP-SPEC.md) — phần thuần Python (không GTK) để test.

- Năm trang giống macOS / Windows: Gõ phím · Gợi ý & công cụ · Gõ tắt · Ứng dụng · Chung.
- Công tắc phụ thuộc: làm mờ + ghi lý do, KHÔNG ẩn (§0.4). Mỗi điều kiện nhận `get(section,
  key)` = Config.get và chỉ ĐỌC — không đổi key, không đổi mặc định, không đổi hành vi.
"""

from .i18n import N_

# Tên cho `--page`, đúng thứ tự trang. Tên cũ (trước khi thu gọn) vẫn mở đúng trang mới.
PAGES = ("typing", "suggestions", "shortcuts", "apps", "general")
PAGE_ALIASES = {"options": "suggestions", "modes": "apps", "compat": "apps", "about": "general"}


def page_index(name):
    """Tên trang (--page) → chỉ số trang; lạ ⇒ None."""
    name = PAGE_ALIASES.get(name, name)
    return PAGES.index(name) if name in PAGES else None


# Lý do hiện trên dòng bị làm mờ (dịch lúc hiển thị bằng `_`).
REASON_TELEX_ONLY = N_("Chỉ áp dụng cho Telex.")
REASON_NEEDS_CONTEXT = N_("Cần bật Quyết định theo ngữ cảnh.")
REASON_NEEDS_PREDICTION = N_("Cần bật Gợi ý từ.")

# Mục chỉ-Telex trong "Nâng cao" của Kiểu gõ: làm mờ khi chọn VNI.
TELEX_ONLY_KEYS = (
    ("typing", "simple_telex"),
    ("typing", "free_marking"),
    ("typing", "quick_telex"),
    ("typing", "teencode"),
    ("typing", "bracket_vowels"),
)


def telex_only_enabled(get):
    return get("typing", "input_method") != "vni"


# Nhóm "Gõ lẫn tiếng Anh" (bộ chọn hồ sơ + Nâng cao): VNI đặt dấu bằng phím số nên từ tiếng Anh
# gõ ra nguyên vẹn — cả nhóm vô tác dụng ⇒ ẨN cả nhóm, thay bằng MỘT dòng (SETTINGS-CLEANUP-SPEC
# §1, ngoại lệ có chủ đích của §0.4). Không đổi key/giá trị: đổi lại Telex thấy y như cũ.
MIXED_DESCRIPTION = N_("Nhận diện tiếng Anh khi gõ lẫn Việt–Anh.")
MIXED_VNI_NOTE = N_("Gõ VNI không làm đổi từ tiếng Anh nên không cần chỉnh phần này.")


def mixed_group_hidden(get):
    """True ⇒ ẩn bộ chọn hồ sơ + Nâng cao của "Gõ lẫn tiếng Anh" (đang chọn VNI)."""
    return get("typing", "input_method") == "vni"


def mixed_group_description(get):
    """Dòng mô tả dưới tiêu đề nhóm: khi ẩn thì là dòng ghi chú VNI thay cho cả nhóm."""
    return MIXED_VNI_NOTE if mixed_group_hidden(get) else MIXED_DESCRIPTION


def retro_english_enabled(get):
    """"Tự sửa từ phía trước" / "Đoán từ trùng theo tần suất" cần "Quyết định theo ngữ cảnh"."""
    return bool(get("typing", "contextual_english"))


def learn_words_enabled(get):
    """"Học từ bạn gõ" chỉ có tác dụng khi "Gợi ý từ" bật (linux/common/SETTINGS.md §8b)."""
    return bool(get("general", "word_prediction"))


# (section, key) → (điều kiện, lý do): bảng dùng chung cho app.py và test.
DEPENDENCIES = dict(
    [(k, (telex_only_enabled, REASON_TELEX_ONLY)) for k in TELEX_ONLY_KEYS] + [
        (("typing", "retroactive_english"), (retro_english_enabled, REASON_NEEDS_CONTEXT)),
        (("typing", "english_by_frequency"), (retro_english_enabled, REASON_NEEDS_CONTEXT)),
        (("general", "learn_words"), (learn_words_enabled, REASON_NEEDS_PREDICTION)),
    ])


def dependent_state(key, get):
    """(bấm được?, lý do hoặc None) của dòng `key`; key không phụ thuộc gì ⇒ (True, None)."""
    dep = DEPENDENCIES.get(key)
    if dep is None:
        return True, None
    ok = dep[0](get)
    return ok, (None if ok else dep[1])


def dimmed_subtitle(reason, subtitle):
    """Chú thích khi bị làm mờ: lý do lên đầu, giữ mô tả gốc bên dưới."""
    if not reason:
        return subtitle or ""
    return reason + ("\n" + subtitle if subtitle else "")
