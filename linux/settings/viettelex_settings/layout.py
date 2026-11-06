"""Bố cục cài đặt (docs/SETTINGS-CLEANUP-SPEC.md) — phần thuần Python (không GTK) để test.

- Năm trang giống macOS / Windows: Gõ phím · Gợi ý & công cụ · Gõ tắt · Ứng dụng · Chung.
- Công tắc phụ thuộc (§0.4, bảng §6): mục con nằm NGAY DƯỚI mục cha cùng nhóm ⇒ ẨN khi cha làm nó
  vô tác dụng, bật lại cha là hiện ngay tại chỗ. Mục cha ở trang khác thì làm mờ + lý do — trên Linux
  hiện không có trường hợp nào. Mỗi điều kiện nhận `get(section, key)` = Config.get và chỉ ĐỌC —
  không đổi key, không đổi giá trị đã lưu, không đổi hành vi.
"""

from .i18n import N_

# Tên cho `--page`, đúng thứ tự trang. Tên cũ (trước khi thu gọn) vẫn mở đúng trang mới.
PAGES = ("typing", "suggestions", "shortcuts", "apps", "general")
PAGE_ALIASES = {"options": "suggestions", "modes": "apps", "compat": "apps", "about": "general"}


def page_index(name):
    """Tên trang (--page) → chỉ số trang; lạ ⇒ None."""
    name = PAGE_ALIASES.get(name, name)
    return PAGES.index(name) if name in PAGES else None


def is_vni(get):
    return get("typing", "input_method") == "vni"


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


def mixed_card_visible(pending, get):
    """Thẻ một lần "Bạn hay gõ trộn Anh/Việt?" (người dùng cũ): VNI ⇒ ẩn vì nút "Xem" trỏ tới
    nhóm đang ẩn; giữ cờ chưa xem nên đổi lại Telex thì thẻ hiện lại."""
    return bool(pending) and not is_vni(get)


# Bảng §6 — (section, key) của dòng con → điều kiện HIỆN. Dòng con nằm ngay dưới dòng cha trong
# cùng nhóm. Teencode và phím ngoặc chạy cả ở VNI nên KHÔNG có ở đây (trước đây làm mờ nhầm).
VISIBLE_WHEN = {
    # Chọn VNI: mục chỉ-Telex trong Nâng cao của Kiểu gõ.
    ("typing", "simple_telex"): lambda get: not is_vni(get),
    ("typing", "free_marking"): lambda get: not is_vni(get),
    ("typing", "quick_telex"): lambda get: not is_vni(get),
    # Tắt Tự khôi phục từ tiếng Anh: không còn gì để chọn khi trùng từ, không còn gì để đoán.
    ("typing", "collision_prefers_vietnamese"): lambda get: bool(get("typing", "auto_restore")),
    # Tắt Quyết định theo ngữ cảnh: hai mục thử nghiệm dựa trên ngữ cảnh.
    ("typing", "retroactive_english"): lambda get: bool(get("typing", "contextual_english")),
    ("typing", "english_by_frequency"): lambda get: bool(get("typing", "auto_restore"))
    and bool(get("typing", "contextual_english")),
    # Tắt Gợi ý từ: "Học từ bạn gõ" chỉ học khi gợi ý chạy (linux/common/SETTINGS.md §8b).
    ("general", "learn_words"): lambda get: bool(get("general", "word_prediction")),
    # Tắt Ngoặc kép cong và gạch dài: kiểu ngoặc chỉ dùng khi đổi ngoặc (session.cpp).
    ("general", "quote_style"): lambda get: bool(get("general", "smart_punctuation")),
}


def row_visible(key, get):
    """Dòng `key` có hiện không; key không phụ thuộc gì ⇒ luôn hiện."""
    cond = VISIBLE_WHEN.get(key)
    return True if cond is None else cond(get)
