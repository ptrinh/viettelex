"""viettelex-settings — GTK4 + libadwaita (tương thích libadwaita 1.1 / GTK 4.6 của Ubuntu 22.04).

Mọi thay đổi ghi ngay vào ~/.config/viettelex/ (ghi nguyên tử); frontend Fcitx5/IBus
theo dõi thư mục bằng inotify nên áp tức thì, không cần khởi động lại bộ gõ.

Chỉ dùng API có từ libadwaita 1.0/1.1: PreferencesWindow/Page/Group, ActionRow,
ComboRow, ExpanderRow, Toast. (EntryRow/SwitchRow/MessageDialog/AboutWindow ≥ 1.2 — tránh.)
"""

import json
import os
import subprocess
import sys
import threading
from types import SimpleNamespace

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

from . import APP_ID, VERSION, compat, config, detect, gnome_fcitx5, i18n, launchers, shortcuts, updater  # noqa: E402
from .i18n import N_, _  # noqa: E402

WEBSITE = "https://ptrinh.github.io/viettelex/"
LEARN_URL = "https://ptrinh.github.io/viettelex/learn"
FAQ_URL = "https://ptrinh.github.io/viettelex/#faq"
BUG_URL = "https://github.com/ptrinh/viettelex/blob/main/BAO-LOI.md"
RELEASES_URL = "https://github.com/ptrinh/viettelex/releases"
STABLE_JSON = "https://viettelex.com/stable.json"  # trực tiếp HTTPS (github.io 301 qua http://)

APP_MODE_CHOICES = [
    ("auto", N_("Tự động")),
    ("preedit", N_("Chữ đang gõ (preedit)")),
    ("surrounding", N_("Sửa trực tiếp (surrounding)")),
    ("direct", N_("Gõ thẳng, sửa bằng Backspace")),
    ("off", N_("Tắt tiếng Việt")),
]
# Chế độ macOS (typing-modes.yml / file xuất từ máy Mac) → gần nhất trên Linux.
MAC_MODE_MAP = {"marked": "preedit", "inPlace": "surrounding", "passthrough": "off"}

BUILTIN_PREEDIT_APPS = ("gnome-terminal, kgx/ptyxis, konsole, kitty, alacritty, wezterm, "
                        "foot, xterm, tilix, terminator, LibreOffice")


def esc(s):
    return GLib.markup_escape_text(s)


def spawn(argv):
    try:
        subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        return True
    except OSError:
        return False


def open_uri(uri):
    try:
        Gio.AppInfo.launch_default_for_uri(uri, None)
    except GLib.Error:
        spawn(["xdg-open", uri])


# Gợi ý cạnh con trỏ (tab Tuỳ chỉnh → Công cụ văn bản): key config.toml [general], nhãn, mô tả.
HINT_SWITCHES = (
    ("math_results", N_("Hiện kết quả phép tính"),
     N_("Gõ phép tính rồi “=” (12*3=, 200+10%=, 125 x (4 + 5.5) =) → kết quả cạnh con trỏ; "
        "Tab hoặc Enter để chèn.")),
    ("number_chips", N_("Chip số dạng tiền"),
     N_("50k, 1tr2, 2 tỷ + dấu cách → 1.200.000 ₫ cạnh con trỏ; Tab để thay.")),
    ("typo_hints", N_("Gợi ý sửa lỗi gõ sai"),
     N_("Từ vừa gõ không phải tiếng Việt, tiếng Anh hay từ chat → gợi ý từ đúng khi gõ nhầm "
        "một phím kề hoặc đảo hai phím (tpoi → tôi). Tab để thay, Esc = đừng gợi ý từ này nữa.")),
    ("tone_hints", N_("Gợi ý thêm dấu cho câu không dấu"),
     N_("Từ 3 âm tiết không dấu, sau . ! ? hoặc khi dừng gõ một chút → câu có dấu "
        "(toi di hoc → tôi đi học). Tab để thay cả cụm. Mặc định tắt.")),
    ("date_hints", N_("Gợi ý ngày giờ"),
     N_("“hôm nay”, “ngày mai”, “hôm qua” → dd/mm/yyyy; “bây giờ” → giờ:phút (today, tomorrow, "
        "yesterday, now sau một từ tiếng Anh). Tab để thay.")),
)
HINT_SUMMARY = (
    ("text_tools_menu", N_("menu Công cụ…")),
    ("math_results", N_("phép tính")),
    ("number_chips", N_("chip số")),
    ("typo_hints", N_("sửa lỗi gõ")),
    ("tone_hints", N_("thêm dấu")),
    ("date_hints", N_("ngày giờ")),
)


def row(title, subtitle=None):
    r = Adw.ActionRow()
    r.set_title(esc(title))
    if subtitle:
        r.set_subtitle(esc(subtitle))
    return r


# ------------------------------------------------------------------ file dialogs

def choose_file(parent, save, suggested, callback):
    """Gtk.FileDialog (GTK ≥ 4.10) hoặc FileChooserNative (GTK 4.6 — Ubuntu 22.04)."""
    yaml_filter = Gtk.FileFilter()
    yaml_filter.set_name("YAML / JSON / TXT")
    for pat in ("*.yml", "*.yaml", "*.json", "*.txt"):
        yaml_filter.add_pattern(pat)
    if hasattr(Gtk, "FileDialog"):
        dlg = Gtk.FileDialog()
        filters = Gio.ListStore.new(Gtk.FileFilter)
        filters.append(yaml_filter)
        dlg.set_filters(filters)
        if save:
            dlg.set_initial_name(suggested)

        def done(d, res):
            try:
                f = d.save_finish(res) if save else d.open_finish(res)
            except GLib.Error:
                return
            if f and f.get_path():
                callback(f.get_path())
        (dlg.save if save else dlg.open)(parent, None, done)
        return
    action = Gtk.FileChooserAction.SAVE if save else Gtk.FileChooserAction.OPEN
    dlg = Gtk.FileChooserNative.new(_("Lưu file") if save else _("Mở file"), parent, action,
                                    _("Lưu") if save else _("Mở"), _("Huỷ"))
    dlg.add_filter(yaml_filter)
    if save:
        dlg.set_current_name(suggested)

    def on_response(d, resp):
        if resp == Gtk.ResponseType.ACCEPT and d.get_file() and d.get_file().get_path():
            callback(d.get_file().get_path())
        d.destroy()
    dlg.connect("response", on_response)
    dlg._keep = dlg  # giữ tham chiếu tới khi đóng
    dlg.show()


def confirm(parent, heading, body, ok_label, callback):
    """Hộp xác nhận; nút mặc định là Huỷ (Enter không làm nhầm)."""
    if hasattr(Adw, "MessageDialog"):
        d = Adw.MessageDialog.new(parent, heading, body)
        d.add_response("cancel", _("Huỷ"))
        d.add_response("ok", ok_label)
        d.set_response_appearance("ok", Adw.ResponseAppearance.DESTRUCTIVE)
        d.set_default_response("cancel")
        d.set_close_response("cancel")
        d.connect("response", lambda _d, r: callback() if r == "ok" else None)
        d.present()
        return
    d = Gtk.MessageDialog(transient_for=parent, modal=True,
                          message_type=Gtk.MessageType.WARNING,
                          buttons=Gtk.ButtonsType.NONE, text=heading, secondary_text=body)
    d.add_button(_("Huỷ"), Gtk.ResponseType.CANCEL)
    d.add_button(ok_label, Gtk.ResponseType.OK)
    d.set_default_response(Gtk.ResponseType.CANCEL)

    def on_resp(dd, r):
        dd.destroy()
        if r == Gtk.ResponseType.OK:
            callback()
    d.connect("response", on_resp)
    d.present()


# ------------------------------------------------------------------ main window

class SettingsWindow(Adw.PreferencesWindow):
    def __init__(self, app, cfg):
        super().__init__(application=app)
        self.cfg = cfg
        self.set_title(_("VietTelex — Cài đặt"))
        self.set_default_size(760, 700)
        self.refreshers = []          # hàm cập nhật widget khi file đổi từ bên ngoài
        self.telex_only = []          # dòng ẩn khi chọn VNI
        self.shortcut_map = shortcuts.load()
        self._last_written = None

        self.add(self._page_typing())
        self.add(self._page_options())
        self.add(self._page_shortcuts())
        self.add(self._page_modes())
        self.add(self._page_compat())
        self.add(self._page_about())
        self._apply_vni_visibility()
        self._watch_config_dir()
        # Làm mới file .desktop có cờ IME (nguồn đổi / gỡ app) mỗi lần mở app cài đặt.
        GLib.idle_add(lambda: (self.sync_launchers(), False)[1])

    # --- helpers ---------------------------------------------------------

    def toast(self, text):
        self.add_toast(Adw.Toast.new(esc(text)))

    def switch(self, group, section, key, title, subtitle=None, invert=False):
        r = row(title, subtitle)
        sw = Gtk.Switch(valign=Gtk.Align.CENTER)
        r.add_suffix(sw)
        r.set_activatable_widget(sw)

        def refresh():
            v = bool(self.cfg.get(section, key))
            sw.set_active(not v if invert else v)
        refresh()
        sw.connect("notify::active",
                   lambda s, _p: self.cfg.set(section, key, (not s.get_active()) if invert
                                               else s.get_active()))
        self.refreshers.append(refresh)
        group.add(r)
        return r

    def combo(self, group, section, key, title, choices, subtitle=None, on_change=None):
        r = Adw.ComboRow()
        r.set_title(esc(title))
        if subtitle:
            r.set_subtitle(esc(subtitle))
        r.set_model(Gtk.StringList.new([label for _v, label in choices]))
        values = [v for v, _l in choices]

        def refresh():
            cur = self.cfg.get(section, key)
            r.set_selected(values.index(cur) if cur in values else 0)
        refresh()

        def changed(rr, _p):
            i = rr.get_selected()
            if 0 <= i < len(values):
                self.cfg.set(section, key, values[i])
                if on_change:
                    on_change()
        r.connect("notify::selected", changed)
        self.refreshers.append(refresh)
        group.add(r)
        return r

    # --- page 1: Kiểu gõ -------------------------------------------------

    def _page_typing(self):
        page = Adw.PreferencesPage(title=_("Kiểu gõ"), icon_name="input-keyboard-symbolic")

        self.status_group = Adw.PreferencesGroup(title=_("Bộ gõ"))
        self.status_row = row(_("Đang kiểm tra…"))
        guide = Gtk.Button(label=_("Hướng dẫn bật bộ gõ…"), valign=Gtk.Align.CENTER)
        guide.connect("clicked", lambda _b: self.show_onboarding())
        self.status_row.add_suffix(guide)
        self.status_group.add(self.status_row)
        page.add(self.status_group)
        self.refresh_status()

        g = Adw.PreferencesGroup(title=_("Kiểu gõ"))
        self.combo(g, "typing", "input_method", _("Kiểu gõ"),
                   [("telex", "Telex"), ("vni", "VNI")],
                   on_change=self._apply_vni_visibility)
        self.vni_help = row(_("Gõ dấu bằng chữ số"),
                            _("Gõ dấu bằng chữ số thay cho chữ cái Telex: 1-5 = sắc/huyền/hỏi/ngã/nặng, "
                            "6 = â/ê/ô, 7 = ơ/ư, 8 = ă, 9 = đ, 0 = bỏ dấu. Chữ cái giữ nguyên. Nên bật "
                            "“Kiểm tra chính tả khi gõ” để số như “mp3” không bị biến thành dấu."))
        g.add(self.vni_help)
        self.telex_only += [
            self.switch(g, "typing", "simple_telex", _("Telex đơn giản"),
                        _("Chữ w đứng một mình luôn là 'w' (gõ 'uw' để ra ư). "
                        "Tắt = Telex đầy đủ (cw→cư).")),
            self.switch(g, "typing", "teencode", _("Chính tả teencode"),
                        _("Chấp nhận cách viết khi chat: w/z/k thay cho qu/d/c (wá, zui zẻ, kó) và "
                        "bíe, thík, gòy, ừk. Tắt = chỉ chính tả chuẩn, nên từ tiếng Anh như was, "
                        "war, worse, zoo giữ nguyên.")),
            self.switch(g, "typing", "quick_telex", _("Gõ nhanh (Quick Telex)"),
                        _("Gõ đúp phụ âm đầu để ra phụ âm ghép: cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, "
                        "pp→ph, tt→th.")),
            self.switch(g, "typing", "free_marking", _("Bỏ dấu tự do"),
                        _("Tắt = Telex nghiêm ngặt: dấu chỉ nhận khi gõ sát nguyên âm, hợp cho "
                        "English/code (data→data). Bật: dấu đặt tự do (ama→âm).")),
            self.switch(g, "typing", "bracket_vowels", _("Phím ngoặc: [ ra ơ, ] ra ư"),
                        _("Thói quen UniKey: “th[” → “thơ”, “ng]” → “ngư” ({ và } ra chữ hoa). "
                        "Nếu bạn gõ code thì nên để TẮT — khi bật, [ và ] thuộc về từ đang gõ "
                        "thay vì kết thúc từ.")),
        ]
        self.switch(g, "typing", "modern_tone", _("Bỏ dấu kiểu mới (oà, uý)"),
                    _("Tắt = kiểu cũ (hòa, thủy, khỏe). Bật = kiểu mới (hoà, thuý, khoẻ). "
                    "Chỉ đổi vị trí dấu ở oa/oe/uy."))
        page.add(g)
        return page

    def _apply_vni_visibility(self):
        vni = self.cfg.get("typing", "input_method") == "vni"
        self.vni_help.set_visible(vni)
        for r in self.telex_only:
            r.set_visible(not vni)

    def refresh_status(self):
        a = detect.assess(detect.collect())
        self.assessment = a
        fw = {"fcitx5": "Fcitx5", "ibus": "IBus"}.get(a["framework"])
        if a["ok"]:
            self.status_row.set_title(esc(_("VietTelex đang hoạt động")))
            self.status_row.set_subtitle(esc(_("Bộ khung gõ: %s. Chuyển Việt/Anh bằng %s.") % (
                fw, hotkey_label(self.cfg.get("general", "toggle_hotkey")) or _("menu bộ gõ"))))
        elif not fw:
            self.status_row.set_title(esc(_("Chưa có bộ khung gõ Fcitx5 hoặc IBus")))
            self.status_row.set_subtitle(esc(_("Cài gói viettelex-fcitx5 (khuyên dùng) hoặc "
                                             "viettelex-ibus, rồi làm theo hướng dẫn.")))
        else:
            self.status_row.set_title(esc(_("VietTelex chưa được bật trong %s") % fw))
            self.status_row.set_subtitle(esc(_("Bấm “Hướng dẫn bật bộ gõ…” để làm từng bước.")))

    # --- page 2: Tuỳ chỉnh -----------------------------------------------

    def _page_options(self):
        page = Adw.PreferencesPage(title=_("Tuỳ chỉnh"), icon_name="preferences-system-symbolic")

        # Tiêu đề song ngữ cố định: người không đọc được tiếng Việt vẫn tìm ra.
        g = Adw.PreferencesGroup()
        self.combo(g, "general", "ui_language", "Ngôn ngữ / Language",
                   [("vi", "Tiếng Việt"), ("en", "English")],
                   on_change=self._language_changed)
        page.add(g)

        g = Adw.PreferencesGroup(title=_("Chính tả"))
        self.switch(g, "typing", "auto_restore", _("Tự khôi phục từ không hợp lệ"),
                    _("Từ không phải tiếng Việt hợp lệ sẽ tự trả về đúng phím đã gõ khi kết thúc "
                    "từ (retore → retore)."))
        self.switch(g, "typing", "spell_check", _("Kiểm tra chính tả khi gõ"),
                    _("Ngừng bỏ dấu ngay khi từ không thể là tiếng Việt (google, github…) thay vì "
                    "đợi hết từ."))
        self.switch(g, "typing", "contextual_english", _("Quyết định theo ngữ cảnh"),
                    _("Sau một từ tiếng Anh, từ nhập nhằng kế tiếp mà chuỗi phím tạo thành một từ "
                    "tiếng Anh sẽ được giữ tiếng Anh thay vì tiếng Việt — “he is” → “he is”, không "
                    "phải “he í”. Sau từ tiếng Việt hoặc không rõ thì để tiếng Việt — “sao í”."))
        self.switch(g, "typing", "re_edit_word", _("Gõ thêm dấu cho từ ngay trước con trỏ"),
                    _("Đặt con trỏ ngay sau một từ đã gõ rồi gõ phím dấu để sửa dấu từ đó "
                    "(toan + s → toán)."))
        self.switch(g, "general", "underline_misspelled", _("Gạch đỏ âm tiết sai chính tả khi gõ"),
                    _("Chữ đang gõ được đánh dấu khi nó không thể thành âm tiết tiếng Việt (đc, "
                    "hópng, tòc): IBus gạch lượn sóng + chữ đỏ, Fcitx5 gạch chân. Chỉ ở chế độ chữ "
                    "đang gõ (preedit); từ giữ nguyên phím gõ hoặc sẽ tự khôi phục (tiếng Anh) "
                    "không bị đánh dấu."))
        page.add(g)

        g = Adw.PreferencesGroup(
            title=_("Khi từ vừa là tiếng Anh vừa là tiếng Việt"),
            description=_("Cho các từ như last/lát, list/lít, his/hí. Ưu tiên tiếng Việt: gõ đúp "
                        "phím dấu để giữ tiếng Anh (lisst → list). Ưu tiên tiếng Anh: đặt dấu ở "
                        "cuối từ để ra tiếng Việt (lits → lít). Trong câu tiếng Anh thì từ vẫn "
                        "giữ tiếng Anh dù chọn gì."))
        self.combo(g, "typing", "collision_prefers_vietnamese", _("Ưu tiên"),
                   [(True, _("Ưu tiên tiếng Việt")), (False, _("Ưu tiên tiếng Anh"))])
        page.add(g)

        g = Adw.PreferencesGroup(
            title=_("Hiển thị chữ đang gõ"),
            description=_("Chữ đang gõ (preedit): đúng chữ ở mọi app (GTK, Qt, Chrome, Electron). "
                        "Sửa trực tiếp: giống macOS, chỉ áp dụng ở app hỗ trợ surrounding text — "
                        "LibreOffice và app không hỗ trợ tự về preedit. Chỉnh riêng từng app ở "
                        "tab Bảng cơ chế gõ."))
        self.combo(g, "general", "display_mode", _("Cách hiện từ đang gõ"),
                   [("preedit", _("Chữ đang gõ (preedit)")), ("surrounding", _("Sửa trực tiếp (surrounding)"))])
        self.switch(g, "general", "preedit_underline", _("Gạch chân chữ đang gõ"),
                    _("Tắt = chữ đang gõ trông như chữ thường ở app GTK, Qt, VTE (X11). Chrome/Electron "
                    "và app Wayland trên GNOME vẫn tự vẽ gạch chân."))
        self.switch(g, "general", "terminal_direct", _("Terminal: gõ thẳng, sửa dấu bằng Backspace"),
                    _("Giống UniKey: không gạch chân trong gnome-terminal, tilix, konsole… khi app "
                    "nhận phím qua IBus GTK3 hoặc Fcitx5 (fcitx5-gtk3/fcitx5-qt). Terminal GTK4 "
                    "(Ptyxis, Console) và phiên Wayland GNOME vẫn dùng preedit."))
        self._no_underline_switch(g)
        page.add(g)

        # Công cụ văn bản: thu gọn được, MẶC ĐỊNH ĐÓNG (như macOS 1.8.2) — khi đóng, dòng tóm
        # tắt cho biết cái gì đang bật.
        g = Adw.PreferencesGroup()
        exp = Adw.ExpanderRow(expanded=False)
        exp.set_title(esc(_("Công cụ văn bản")))
        g.add(exp)
        tools = SimpleNamespace(add=exp.add_row)
        hint_rows = []
        intro = row(_("Công cụ cho vùng chọn"),
                    _("Bôi đen chữ ở app bất kỳ rồi chọn trong menu bộ gõ → Công cụ…: Thêm dấu "
                      "cho vùng chọn, HOA, thường, Hoa Đầu Từ, Hoa đầu câu, Xoá dấu. Không bao "
                      "giờ chạy ở ô mật khẩu."))
        exp.add_row(intro)
        hint_rows.append(self.switch(tools, "general", "text_tools_menu", _("Hiện công cụ văn bản trong menu"),
                         _("Menu “Công cụ…” của bộ gõ (khay Fcitx5 / menu IBus) liệt kê 6 công cụ trên.")))
        at = row(_("Phím tắt Thêm dấu"),
                 _("Thêm dấu cho đoạn không dấu đang bôi đen (toi di hoc → tôi đi học). Mặc định tắt."))
        self.addtones_btn = Gtk.Button(valign=Gtk.Align.CENTER)
        self.addtones_btn.connect("clicked", lambda _b: self.capture_hotkey(
            _("Phím tắt Thêm dấu"), _("Esc = huỷ · Backspace = tắt phím tắt."),
            self.set_addtones_hotkey, "action"))
        off = Gtk.Button(icon_name="edit-clear-symbolic", valign=Gtk.Align.CENTER,
                         tooltip_text=_("Tắt phím tắt"))
        off.add_css_class("flat")
        off.connect("clicked", lambda _b: self.set_addtones_hotkey(""))
        at.add_suffix(self.addtones_btn)
        at.add_suffix(off)
        exp.add_row(at)
        self.refreshers.append(self._refresh_addtones)
        self._refresh_addtones()
        hints = row(_("Gợi ý cạnh con trỏ"),
                    _("Hiện ngay cạnh con trỏ khi rất chắc; chỉ Tab mới áp dụng, phím khác bỏ qua, "
                      "Esc = bỏ gợi ý. Không bao giờ tự thay, không chạy ở ô mật khẩu. Cần gói "
                      "viettelex-text-tools."))
        exp.add_row(hints)
        for key, title, sub in HINT_SWITCHES:
            hint_rows.append(self.switch(tools, "general", key, _(title), _(sub)))

        def summary(*_a):
            on = [_(label) for key, label in HINT_SUMMARY if self.cfg.get("general", key)]
            exp.set_subtitle(esc(_("Đang bật: %s") % ", ".join(on) if on else _("Đang tắt hết")))
        for r in hint_rows:
            r.get_activatable_widget().connect("notify::active", summary)
        self.refreshers.append(summary)
        summary()
        page.add(g)

        g = Adw.PreferencesGroup(title=_("Chuyển Việt/Anh"))
        hk = row(_("Phím chuyển Việt/Anh"),
                 _("Mặc định Ctrl+Space. Không dùng Super+Space (GNOME dùng để đổi nguồn nhập)."))
        self.hotkey_btn = Gtk.Button(valign=Gtk.Align.CENTER)
        self.hotkey_btn.connect("clicked", lambda _b: self.capture_hotkey(
            _("Phím chuyển Việt/Anh"), _("Esc = huỷ · Backspace = tắt phím chuyển."),
            self.set_hotkey, "toggle"))
        reset = Gtk.Button(icon_name="edit-undo-symbolic", valign=Gtk.Align.CENTER,
                           tooltip_text=_("Về mặc định (Ctrl+Space)"))
        reset.add_css_class("flat")
        reset.connect("clicked", lambda _b: self.set_hotkey("Ctrl+space"))
        hk.add_suffix(self.hotkey_btn)
        hk.add_suffix(reset)
        g.add(hk)
        self.refreshers.append(self._refresh_hotkey)
        self._refresh_hotkey()
        self.switch(g, "general", "per_app_state", _("Nhớ Việt/Anh theo từng app"),
                    _("Mỗi app giữ trạng thái Việt/Anh riêng — chuyển sang terminal gõ tiếng Anh "
                    "không làm mất tiếng Việt ở trình soạn thảo."))
        self.switch(g, "general", "default_vietnamese", _("App mới mở bắt đầu bằng tiếng Việt"),
                    _("Tắt = app lần đầu gặp bắt đầu ở chế độ tiếng Anh."))
        forget = row(_("Quên trạng thái Việt/Anh đã nhớ"),
                     _("Xoá trạng thái đã nhớ của mọi app; lần sau mỗi app bắt đầu theo mặc định."))
        fb = Gtk.Button(label=_("Quên tất cả"), valign=Gtk.Align.CENTER)
        fb.connect("clicked", lambda _b: self.forget_app_state())
        forget.add_suffix(fb)
        g.add(forget)
        page.add(g)
        return page

    def _refresh_hotkey(self):
        hk = self.cfg.get("general", "toggle_hotkey")
        self.hotkey_btn.set_label(hotkey_label(hk) or _("Tắt"))

    def set_hotkey(self, value):
        self.cfg.set("general", "toggle_hotkey", value)
        self._refresh_hotkey()
        conflict = gnome_hotkey_conflict(value)
        if conflict:
            self.toast(_("Trùng phím tắt GNOME: %s — hãy chọn tổ hợp khác.") % conflict)

    def _refresh_addtones(self):
        hk = self.cfg.get("general", "add_tones_hotkey")
        self.addtones_btn.set_label(hotkey_label(hk) or _("Tắt"))

    def set_addtones_hotkey(self, value):
        self.cfg.set("general", "add_tones_hotkey", value)
        self._refresh_addtones()
        conflict = gnome_hotkey_conflict(value)
        if conflict:
            self.toast(_("Trùng phím tắt GNOME: %s — hãy chọn tổ hợp khác.") % conflict)

    # --- thử nghiệm: không gạch chân ở Chrome/Electron (SETTINGS.md §9) -------

    def _no_underline_switch(self, group):
        r = row(_("Bỏ gạch chân trong Chrome/Electron (thử nghiệm)"))
        sw = Gtk.Switch(valign=Gtk.Align.CENTER)
        r.add_suffix(sw)
        r.set_activatable_widget(sw)
        self.no_underline_row = r
        self._launcher_state = None       # (bật?, áp dụng được?) của lần đồng bộ gần nhất
        self._launcher_report = None
        self._update_no_underline_subtitle()

        def on():
            return self.cfg.get("experimental", "no_underline") == "forward-keys"

        def toggled(s, _p):
            if s.get_active() == on():
                return
            self.cfg.set("experimental", "no_underline", "forward-keys" if s.get_active() else "off")
            self.sync_launchers(announce=True)
        handler = sw.connect("notify::active", toggled)

        def refresh():
            if sw.get_active() != on():
                sw.handler_block(handler)
                sw.set_active(on())
                sw.handler_unblock(handler)
            if self._launcher_state is not None and self._launcher_state[0] != on():
                self.sync_launchers()      # file config.toml bị sửa từ bên ngoài
        refresh()
        self.refreshers.append(refresh)
        group.add(r)

    def _session(self):
        env = os.environ
        session = env.get("XDG_SESSION_TYPE") or ("wayland" if env.get("WAYLAND_DISPLAY") else "")
        return session.lower(), env.get("XDG_CURRENT_DESKTOP", "")

    def sync_launchers(self, announce=False):
        """Tạo / làm mới / gỡ file .desktop có cờ IME Wayland (launchers.py) — luồng nền."""
        enabled = self.cfg.get("experimental", "no_underline") == "forward-keys"
        session, desktop = self._session()
        fw = (getattr(self, "assessment", None) or {}).get("framework")
        appl = launchers.applicability(session, desktop, fw)
        self._launcher_state = (enabled, appl)

        def work():
            reopen = []
            try:
                kwin = launchers.kwin_version() if enabled and "kde" in desktop.lower() else None
                flags = launchers.flags_for(launchers.text_input_version(desktop, kwin))
                rep = launchers.sync(enabled, create_new=(appl == "ok"), flags=flags,
                                     default_on=launchers.default_on_versions() if enabled else {})
                rep["flags"] = flags
                if enabled and appl == "ok":
                    target = launchers.user_apps_dir()
                    entries = []
                    for did, name in rep["created"] + rep["updated"] + rep["unchanged"]:
                        try:
                            with open(os.path.join(target, did), encoding="utf-8") as f:
                                entries.append((did, name, f.read()))
                        except (OSError, UnicodeDecodeError):
                            pass
                    reopen = launchers.running_without_flag(entries)
            except Exception as e:  # không được làm hỏng app cài đặt
                rep = launchers._empty_report()
                rep["errors"].append(("", str(e)))
            GLib.idle_add(self._launchers_done, rep, reopen, enabled, appl, announce)
        threading.Thread(target=work, daemon=True).start()

    def _launchers_done(self, rep, reopen, enabled, appl, announce):
        self._launcher_report = (rep, reopen)
        self._update_no_underline_subtitle()
        if announce:
            names = ", ".join(n for _d, n in reopen)
            if not enabled:
                self.toast(_("Đã tắt — Chrome/Electron về gạch chân như cũ."))
            elif appl != "ok":
                self.toast(_("Đã bật, nhưng máy này chưa áp dụng được (xem dòng mô tả)."))
            elif names:
                self.toast(_("Thoát hẳn rồi mở lại %s để bỏ gạch chân.") % names)
            else:
                self.toast(_("Đã bật. Mở lại Chrome/Electron để bỏ gạch chân."))
        return False

    def _update_no_underline_subtitle(self):
        enabled = self.cfg.get("experimental", "no_underline") == "forward-keys"
        session, desktop = self._session()
        fw = (getattr(self, "assessment", None) or {}).get("framework")
        appl = launchers.applicability(session, desktop, fw)
        parts = [_("Chrome, VS Code, Slack, Discord… gõ thẳng như ở app khác; sửa dấu bằng phím "
                   "Backspace, lỗi thì tự về gạch chân. Chỉ GNOME Wayland (IBus hoặc Fcitx5) và "
                   "KDE Wayland (Fcitx5). Bật lên, VietTelex tự thêm cờ IME Wayland vào lối tắt "
                   "của các app này — mở lại app là xong.")]
        if appl == "not_wayland":
            parts.append(_("Phiên này là X11: không áp dụng, Chrome/Electron vẫn gạch chân."))
        elif appl == "kde_ibus":
            parts.append(_("KDE cần Fcitx5; IBus trên KDE chưa hỗ trợ."))
        elif appl == "unsupported_desktop":
            parts.append(_("Desktop này (%s) chưa hỗ trợ — chỉ GNOME và KDE Plasma.") %
                         (desktop or "?"))
        report = self._launcher_report
        if enabled and appl == "ok" and report:
            rep, reopen = report
            done = rep["created"] + rep["updated"] + rep["unchanged"]

            def listing(items):
                names = []
                for i in items:
                    if i[1] not in names:
                        names.append(i[1])
                return ", ".join(names)
            if done:
                parts.append(_("Đã thêm cờ cho: %s.") % listing(done))
            if rep["default_on"]:
                parts.append(_("Đã bật sẵn, không cần cờ: %s.") % listing(rep["default_on"]))
            if reopen:
                parts.append(_("Đang chạy bản cũ — thoát hẳn rồi mở lại: %s.") % listing(reopen))
            if rep["user_configured"]:
                parts.append(_("Lối tắt bạn tự sửa (đã có cờ): %s.") % listing(rep["user_configured"]))
            if rep["conflicts"]:
                parts.append(_("Không sửa lối tắt bạn tự tạo: %s — tự thêm %s vào dòng Exec=.") % (
                    ", ".join(i[2] for i in rep["conflicts"]),
                    " ".join(rep.get("flags") or launchers.flags_for())))
            if rep["x11"]:
                parts.append(_("Đang ép chạy X11, giữ nguyên (vẫn gạch chân): %s.") % listing(rep["x11"]))
            if rep["unsupported"]:
                parts.append(_("Không tự thêm cờ được: %s.") % listing(rep["unsupported"]))
            if not (done or rep["default_on"] or rep["user_configured"] or rep["conflicts"]
                    or rep["x11"] or rep["unsupported"]):
                parts.append(_("Chưa thấy app Chrome/Electron nào cài trên máy."))
            if rep["errors"]:
                parts.append(_("Lỗi khi ghi lối tắt: %s") % rep["errors"][0][1])
        self.no_underline_row.set_subtitle(esc("\n".join(parts)))

    def _language_changed(self):
        lang = self.cfg.get("general", "ui_language")
        if lang == i18n.language():
            return
        i18n.set_language(lang)
        app = self.get_application()
        if app is not None:
            GLib.idle_add(lambda: (app.rebuild_window(), False)[1])

    def capture_hotkey(self, heading, esc_hint, setter, kind):
        """kind "toggle" = phím chuyển Việt/Anh; "action" = phím công cụ (cần Ctrl/Alt/Super,
        không trùng phím chuyển)."""
        win = Gtk.Window(transient_for=self, modal=True, title=heading,
                         default_width=420, resizable=False)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_top=24,
                      margin_bottom=24, margin_start=24, margin_end=24)
        title = Gtk.Label(label=_("Nhấn tổ hợp phím mới…"))
        title.add_css_class("title-3")
        need = (_("Cần ít nhất một phím Ctrl/Alt/Shift/Super.") if kind == "toggle"
                else _("Cần ít nhất một phím Ctrl/Alt/Super."))
        hint = Gtk.Label(label=need + "\n" + esc_hint, justify=Gtk.Justification.CENTER)
        hint.add_css_class("dim-label")
        box.append(title)
        box.append(hint)
        win.set_child(box)
        ctl = Gtk.EventControllerKey()

        def pressed(_c, keyval, _code, state):
            name = Gdk.keyval_name(Gdk.keyval_to_lower(keyval)) or ""
            mods = []
            if state & Gdk.ModifierType.CONTROL_MASK:
                mods.append("Ctrl")
            if state & getattr(Gdk.ModifierType, "ALT_MASK", Gdk.ModifierType.MOD1_MASK
                               if hasattr(Gdk.ModifierType, "MOD1_MASK") else 0):
                mods.append("Alt")
            if state & Gdk.ModifierType.SHIFT_MASK:
                mods.append("Shift")
            if state & Gdk.ModifierType.SUPER_MASK:
                mods.append("Super")
            if name in ("Control_L", "Control_R", "Alt_L", "Alt_R", "Shift_L", "Shift_R",
                        "Super_L", "Super_R", "Meta_L", "Meta_R", "ISO_Level3_Shift"):
                return True
            if not mods and name == "Escape":
                win.close()
                return True
            if not mods and name == "BackSpace":
                setter("")
                win.close()
                return True
            if not mods:
                title.set_label(_("Cần thêm Ctrl, Alt, Shift hoặc Super"))
                return True
            value = config.normalize_hotkey("+".join(mods + [name]))
            if value is None:
                title.set_label(_("Không dùng được %s — chọn tổ hợp khác") % "+".join(mods + [name]))
                return True
            if kind == "action":
                err = config.action_hotkey_error(value, self.cfg.get("general", "toggle_hotkey"))
                if err == "modifier":
                    title.set_label(_("Cần thêm Ctrl, Alt hoặc Super"))
                    return True
                if err == "toggle":
                    title.set_label(_("%s đang là phím chuyển Việt/Anh — chọn tổ hợp khác")
                                    % hotkey_label(value))
                    return True
            elif value == self.cfg.get("general", "add_tones_hotkey"):
                title.set_label(_("%s đang là phím tắt Thêm dấu — chọn tổ hợp khác")
                                % hotkey_label(value))
                return True
            setter(value)
            win.close()
            return True
        ctl.connect("key-pressed", pressed)
        win.add_controller(ctl)
        win.present()

    def forget_app_state(self):
        path = os.path.join(config.state_dir(), "app-state")

        def do():
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
            except OSError:
                self.toast(_("Không xoá được %s") % path)
                return
            self.toast(_("Đã quên trạng thái Việt/Anh của mọi app."))
        confirm(self, _("Quên trạng thái Việt/Anh?"),
                _("Mọi app sẽ bắt đầu lại theo mặc định."), _("Quên tất cả"), do)

    # --- page 3: Gõ tắt --------------------------------------------------

    def _page_shortcuts(self):
        page = Adw.PreferencesPage(title=_("Gõ tắt"), icon_name="document-edit-symbolic")
        g = Adw.PreferencesGroup()
        self.switch(g, "typing", "shortcuts_enabled", _("Bật gõ tắt"),
                    _("Gõ từ tắt rồi dấu cách/dấu câu để bung ra cụm đầy đủ (ko → không)."))
        page.add(g)

        add = Adw.PreferencesGroup(title=_("Thêm / sửa gõ tắt"),
                                   description=_("Bấm một dòng để sửa."))
        box = Gtk.Box(spacing=6, margin_top=6, margin_bottom=6)
        self.sc_key = Gtk.Entry(placeholder_text=_("gõ"), width_chars=10, max_length=64)
        self.sc_val = Gtk.Entry(placeholder_text=_("thành"), hexpand=True)
        btn = Gtk.Button(label=_("Thêm"))
        btn.add_css_class("suggested-action")
        btn.connect("clicked", lambda _b: self.add_shortcut())
        self.sc_key.connect("activate", lambda _e: self.sc_val.grab_focus())
        self.sc_val.connect("activate", lambda _e: self.add_shortcut())
        box.append(self.sc_key)
        box.append(Gtk.Label(label="→"))
        box.append(self.sc_val)
        box.append(btn)
        add.add(box)
        io = Gtk.Box(spacing=6, halign=Gtk.Align.END, margin_top=6)
        imp = Gtk.Button(label=_("Nhập…"))
        imp.connect("clicked", lambda _b: choose_file(self, False, "", self.import_shortcuts))
        exp = Gtk.Button(label=_("Xuất ra YAML…"))
        exp.connect("clicked", lambda _b: choose_file(self, True, "viettelex-shortcuts.yml",
                                                        self.export_shortcuts))
        io.append(imp)
        io.append(exp)
        add.add(io)
        page.add(add)

        self.sc_group = Adw.PreferencesGroup(title=_("Bảng gõ tắt"))
        self.sc_rows = []
        page.add(self.sc_group)
        self._rebuild_shortcuts()
        return page

    def _rebuild_shortcuts(self):
        for r in self.sc_rows:
            self.sc_group.remove(r)
        self.sc_rows = []
        if not self.shortcut_map:
            r = row(_("Chưa có gõ tắt nào"), _("Thêm ở trên, hoặc Nhập… file YAML/JSON/TXT "
                    "(mỗi dòng một cặp key: value — cùng định dạng bản macOS, Gõ Nhanh, EVKey…)."))
            self.sc_group.add(r)
            self.sc_rows.append(r)
            return
        for key in sorted(self.shortcut_map):
            r = row(key, self.shortcut_map[key])
            r.set_activatable(True)
            r.connect("activated", lambda _r, k=key: self._edit_shortcut(k))
            d = Gtk.Button(icon_name="user-trash-symbolic", valign=Gtk.Align.CENTER,
                           tooltip_text=_("Xoá gõ tắt này"))
            d.add_css_class("flat")
            d.connect("clicked", lambda _b, k=key: self.remove_shortcut(k))
            r.add_suffix(d)
            self.sc_group.add(r)
            self.sc_rows.append(r)

    def _edit_shortcut(self, key):
        self.sc_key.set_text(key)
        self.sc_val.set_text(self.shortcut_map.get(key, ""))
        self.sc_val.grab_focus()

    def _save_shortcuts(self):
        shortcuts.save(self.shortcut_map)
        self._rebuild_shortcuts()

    def add_shortcut(self):
        k = self.sc_key.get_text().strip()
        v = self.sc_val.get_text().strip()
        if not shortcuts.valid_key(k):
            self.toast(_("Từ gõ tắt không được trống hay chứa dấu cách (tối đa 64 ký tự)."))
            return
        if not v:
            self.toast(_("Nhập cụm từ sẽ thay thế."))
            return
        self.shortcut_map[k] = v
        self._save_shortcuts()
        self.sc_key.set_text("")
        self.sc_val.set_text("")
        self.sc_key.grab_focus()

    def remove_shortcut(self, key):
        self.shortcut_map.pop(key, None)
        self._save_shortcuts()

    def import_shortcuts(self, path):
        d = read_table(path)
        if d is None:
            self.toast(_("Không đọc được file. Định dạng hỗ trợ: JSON, YAML, hoặc mỗi dòng một "
                       "cặp key:value."))
            return
        d = {k: v for k, v in d.items() if shortcuts.valid_key(k)}
        self.shortcut_map.update(d)
        self._save_shortcuts()
        self.toast(_("Đã nhập %d gõ tắt — gộp vào bảng hiện có (mục trùng lấy giá trị mới).")
                   % len(d))

    def export_shortcuts(self, path):
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(shortcuts.export_yaml(self.shortcut_map))
            self.toast(_("Đã lưu %s") % os.path.basename(path))
        except OSError:
            self.toast(_("Không lưu được file."))

    # --- page 4: Bảng cơ chế gõ -----------------------------------------

    def _page_modes(self):
        page = Adw.PreferencesPage(title=_("Bảng cơ chế gõ"), icon_name="view-list-symbolic")
        g = Adw.PreferencesGroup(
            title=_("Ép cơ chế gõ theo app"),
            description=_("App gõ sai hoặc hiện gạch chân khó chịu? Chọn riêng cho app đó. "
                        "Tự động = theo “Cách hiện từ đang gõ” ở tab Tuỳ chỉnh. Terminal và "
                        "LibreOffice mặc định dùng preedit (%s); terminal gõ thẳng khi hệ hỗ trợ. "
                        "“Gõ thẳng” chỉ có tác dụng ở app nhận phím qua IBus GTK3 / Fcitx5 GTK3-Qt.")
                        % BUILTIN_PREEDIT_APPS)
        box = Gtk.Box(spacing=6, margin_top=6, margin_bottom=6)
        self.mode_app = Gtk.Entry(hexpand=True,
                                  placeholder_text=_("Tên app (vd: org.gnome.texteditor, kitty, code)"))
        self.mode_pick = Gtk.DropDown.new_from_strings([_(l) for v, l in APP_MODE_CHOICES[1:]])
        btn = Gtk.Button(label=_("Thêm"))
        btn.add_css_class("suggested-action")
        btn.connect("clicked", lambda _b: self.add_app_mode())
        self.mode_app.connect("activate", lambda _e: self.add_app_mode())
        box.append(self.mode_app)
        box.append(self.mode_pick)
        box.append(btn)
        g.add(box)
        io = Gtk.Box(spacing=6, halign=Gtk.Align.END, margin_top=6)
        imp = Gtk.Button(label=_("Nhập…"))
        imp.connect("clicked", lambda _b: choose_file(self, False, "", self.import_modes))
        exp = Gtk.Button(label=_("Xuất ra YAML…"))
        exp.connect("clicked", lambda _b: choose_file(self, True, "viettelex-app-modes.yml",
                                                        self.export_modes))
        io.append(imp)
        io.append(exp)
        g.add(io)
        page.add(g)

        self.mode_group = Adw.PreferencesGroup(
            title=_("App đã chỉnh"),
            description=_("Tên app: Fcitx5 dùng tên chương trình; IBus dùng app-id Wayland hoặc "
                        "WM_CLASS (chữ thường)."))
        self.mode_rows = []
        page.add(self.mode_group)
        self.refreshers.append(self._rebuild_modes)
        self._rebuild_modes()
        return page

    def _rebuild_modes(self):
        for r in self.mode_rows:
            self.mode_group.remove(r)
        self.mode_rows = []
        modes = self.cfg.data["app_modes"]
        if not modes:
            r = row(_("Chưa có app nào"), _("Mọi app đang dùng chế độ Tự động."))
            self.mode_group.add(r)
            self.mode_rows.append(r)
            return
        values = [v for v, _l in APP_MODE_CHOICES]
        for app in sorted(modes):
            r = Adw.ComboRow()
            r.set_title(esc(app))
            r.set_model(Gtk.StringList.new([_(l) for _v, l in APP_MODE_CHOICES]))
            r.set_selected(values.index(modes[app]) if modes[app] in values else 0)
            r.connect("notify::selected",
                      lambda rr, _p, a=app: self._mode_changed(a, values[rr.get_selected()]))
            d = Gtk.Button(icon_name="user-trash-symbolic", valign=Gtk.Align.CENTER,
                           tooltip_text=_("Bỏ ghi đè cho app này"))
            d.add_css_class("flat")
            d.connect("clicked", lambda _b, a=app: self._mode_changed(a, "auto", rebuild=True))
            r.add_suffix(d)
            self.mode_group.add(r)
            self.mode_rows.append(r)

    def _mode_changed(self, app, mode, rebuild=False):
        self.cfg.set_app_mode(app, mode)
        if rebuild or mode == "auto":
            GLib.idle_add(self._rebuild_modes)

    def add_app_mode(self):
        app = self.mode_app.get_text().strip().lower()
        if not app or any(c.isspace() for c in app):
            self.toast(_("Nhập tên app (không chứa dấu cách)."))
            return
        mode = APP_MODE_CHOICES[1 + self.mode_pick.get_selected()][0]
        self.cfg.set_app_mode(app, mode)
        self.mode_app.set_text("")
        self._rebuild_modes()

    def import_modes(self, path):
        d = read_table(path)
        if d is None:
            self.toast(_("Không đọc được file. Định dạng hỗ trợ: JSON, YAML, hoặc mỗi dòng một "
                       "cặp key:value."))
            return
        good = {}
        for app, mode in d.items():
            mode = MAC_MODE_MAP.get(mode, mode)
            if mode in config.APP_MODES and app.strip():
                good[app] = mode
        self.cfg.set_app_modes(good)
        applied = len(good)
        self._rebuild_modes()
        self.toast(_("Đã nhập %d chế độ app. Mục có chế độ không hợp lệ bị bỏ qua.") % applied)

    def export_modes(self, path):
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(shortcuts.export_yaml(self.cfg.data["app_modes"],
                                              header="# VietTelex — bảng cơ chế gõ theo app (Linux)"))
            self.toast(_("Đã lưu %s") % os.path.basename(path))
        except OSError:
            self.toast(_("Không lưu được file."))

    # --- page 5: Tương thích ứng dụng -----------------------------------

    def _page_compat(self):
        page = Adw.PreferencesPage(title=_("Tương thích"), icon_name="dialog-information-symbolic")
        self.compat_page = page
        self.compat_groups = []
        self._rebuild_compat()
        return page

    def _rebuild_compat(self):
        for g in self.compat_groups:
            self.compat_page.remove(g)
        self.compat_groups = []
        try:
            fw = detect.assess(detect.collect())["framework"]
            issues = compat.assess(compat.collect(framework=fw))
        except Exception:  # dò môi trường không được phép làm hỏng app cài đặt
            issues = []
        g = Adw.PreferencesGroup(
            title=_("Tương thích ứng dụng"),
            description=_("Chỉ liệt kê lưu ý khớp với máy này.") if issues else
            _("Không phát hiện vấn đề nào với các ứng dụng đã cài."))
        again = Gtk.Button(icon_name="view-refresh-symbolic", valign=Gtk.Align.CENTER,
                           tooltip_text=_("Dò lại"))
        again.add_css_class("flat")
        again.connect("clicked", lambda _b: self._rebuild_compat())
        g.set_header_suffix(again)
        for it in issues:
            g.add(self._compat_row(it))
        self.compat_page.add(g)
        self.compat_groups.append(g)

    def _compat_row(self, it):
        icon = Gtk.Image.new_from_icon_name(
            "dialog-warning-symbolic" if it["level"] == "warn" else "dialog-information-symbolic")
        if it["level"] == "warn":
            icon.add_css_class("warning")
        if not it["fix"]:
            r = row(it["title"], it["body"])
            r.add_prefix(icon)
            return r
        r = Adw.ExpanderRow()
        r.set_title(esc(it["title"]))
        r.set_subtitle(esc(it["body"]))
        r.add_prefix(icon)
        copy = Gtk.Button(icon_name="edit-copy-symbolic", valign=Gtk.Align.CENTER,
                          tooltip_text=_("Chép lệnh"))
        copy.add_css_class("flat")
        copy.connect("clicked", lambda _b, t=it["fix"]: self.copy_text(t))
        r.add_action(copy)
        lbl = Gtk.Label(label=it["fix"], selectable=True, wrap=True, xalign=0,
                        margin_top=8, margin_bottom=8, margin_start=12, margin_end=12)
        lbl.add_css_class("monospace")
        r.add_row(lbl)
        return r

    def copy_text(self, text):
        self.get_clipboard().set_content(Gdk.ContentProvider.new_for_value(text))
        self.toast(_("Đã chép lệnh."))

    # --- page 6: Giới thiệu ----------------------------------------------

    def _page_about(self):
        page = Adw.PreferencesPage(title=_("Giới thiệu"), icon_name="help-about-symbolic")
        g = Adw.PreferencesGroup()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=12,
                      halign=Gtk.Align.CENTER)
        img = Gtk.Image.new_from_icon_name(APP_ID)
        img.set_pixel_size(128)
        box.append(img)
        name = Gtk.Label(label="VietTelex")
        name.add_css_class("title-1")
        box.append(name)
        ver = Gtk.Label(label=_("Phiên bản %s · Linux") % VERSION)
        ver.add_css_class("dim-label")
        box.append(ver)
        g.add(box)
        page.add(g)

        links = Adw.PreferencesGroup()
        for title, url in (("Website", WEBSITE), (_("Học gõ Telex"), LEARN_URL),
                           (_("Câu hỏi thường gặp"), FAQ_URL), (_("Hướng dẫn báo lỗi"), BUG_URL)):
            r = row(title)
            r.add_suffix(Gtk.Image.new_from_icon_name("adw-external-link-symbolic"))
            r.set_activatable(True)
            r.connect("activated", lambda _r, u=url: open_uri(u))
            links.add(r)
        page.add(links)

        upd = Adw.PreferencesGroup()
        self.update_row = row(_("Kiểm tra cập nhật"), _("Chỉ kết nối mạng khi bạn bấm nút này."))
        self.update_btn = Gtk.Button(label=_("Kiểm tra"), valign=Gtk.Align.CENTER)
        # Handler lưu lại để đổi hành động nút (Kiểm tra → Cập nhật → Khởi động lại) không chạy chồng.
        self._upd_handlers = [self.update_btn.connect("clicked", lambda _b: self.check_update())]
        self.update_row.add_suffix(self.update_btn)
        upd.add(self.update_row)
        page.add(upd)

        foot = Adw.PreferencesGroup()
        lic = Gtk.Label(label=_("Mã nguồn mở (MIT) · không thu thập dữ liệu · chạy hoàn toàn trên máy"))
        lic.add_css_class("dim-label")
        foot.add(lic)
        page.add(foot)
        return page

    def check_update(self):
        self.update_btn.set_sensitive(False)
        self.update_row.set_subtitle(esc(_("Đang kiểm tra…")))

        def work():
            try:
                with updater.urlopen(STABLE_JSON, timeout=8) as r:
                    info = json.loads(r.read().decode("utf-8"))
                st, lin = updater.state(info, VERSION)
                msg, url = updater.update_message(info, VERSION)
            except (OSError, ValueError):
                st, lin = "error", None
                msg, url = _("Không kết nối được máy chủ cập nhật."), None
            GLib.idle_add(self._update_done, st, lin, msg, url)
        threading.Thread(target=work, daemon=True).start()

    def _set_update_action(self, label, cb):
        self.update_btn.set_label(label)
        for h in getattr(self, "_upd_handlers", []):
            self.update_btn.disconnect(h)
        self._upd_handlers = [self.update_btn.connect("clicked", lambda _b: cb())]
        self.update_btn.set_sensitive(True)

    def _update_done(self, st, lin, msg, url):
        self.update_btn.set_sensitive(True)
        self.update_row.set_subtitle(esc(msg))
        if st == "available":
            self._set_update_action(_("Cập nhật lên %s") % lin["version"],
                                    lambda: self.run_update(lin))
        elif url:
            self._set_update_action(_("Mở trang tải"), lambda: open_uri(url))
        return False

    def run_update(self, lin):
        """Cập nhật một chạm: kho APT nếu đã thêm, không thì tải .deb (kiểm SHA256)."""
        self.update_btn.set_sensitive(False)
        self.update_row.set_subtitle(esc(_("Đang chuẩn bị cập nhật…")))

        def progress(text):
            GLib.idle_add(lambda: (self.update_row.set_subtitle(esc(text)), False)[1])

        def work():
            ok, msg, fallback = updater.run_update(lin, progress)
            GLib.idle_add(self._run_update_done, ok, msg, fallback, lin)
        threading.Thread(target=work, daemon=True).start()

    def _run_update_done(self, ok, msg, fallback, lin):
        self.update_row.set_subtitle(esc(msg))
        if ok:
            self._set_update_action(_("Khởi động lại bộ gõ"), self.restart_after_update)
        elif fallback:
            self._set_update_action(_("Mở trang tải"), lambda: open_uri(lin.get("url") or RELEASES_URL))
        else:
            self._set_update_action(_("Thử lại"), lambda: self.run_update(lin))
        return False

    def restart_after_update(self):
        fw = detect.active_framework(detect.collect())
        argv = updater.restart_im_argv(fw)
        if argv:
            spawn(argv)
        # Mở lại app bản mới (mã Python đã được thay trên đĩa).
        spawn(["viettelex-settings"])
        self.get_application().quit()

    # --- onboarding -------------------------------------------------------

    def show_onboarding(self):
        OnboardingWindow(self).present()

    # --- theo dõi file (frontend / Fcitx5 config UI có thể sửa) ------------

    def _watch_config_dir(self):
        d = Gio.File.new_for_path(config.config_dir())
        try:
            os.makedirs(config.config_dir(), exist_ok=True)
            self._monitor = d.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
        except (GLib.Error, OSError):
            return
        self._reload_pending = False
        self._monitor.connect("changed", self._on_dir_changed)

    def _on_dir_changed(self, *_a):
        if not self._reload_pending:
            self._reload_pending = True
            GLib.timeout_add(250, self._reload_from_disk)

    def _reload_from_disk(self):
        self._reload_pending = False
        before = config.dump(self.cfg.data)
        self.cfg.load()
        if config.dump(self.cfg.data) != before:
            if self.cfg.get("general", "ui_language") != i18n.language():
                self._language_changed()      # dựng lại cả cửa sổ — khỏi refresh từng dòng
                return False
            for f in self.refreshers:
                f()
            self._apply_vni_visibility()
        sc = shortcuts.load()
        if sc != self.shortcut_map:
            self.shortcut_map = sc
            self._rebuild_shortcuts()
        return False


def hotkey_label(value):
    """'Ctrl+space' → 'Ctrl+Space' (chỉ để hiển thị; file giữ đúng tên keysym)."""
    if not value:
        return ""
    parts = value.split("+")
    key = parts[-1]
    key = key.upper() if len(key) == 1 else key[:1].upper() + key[1:]
    return "+".join(parts[:-1] + [key])


def read_table(path):
    try:
        with open(path, encoding="utf-8") as f:
            return shortcuts.parse(f.read())
    except (OSError, UnicodeDecodeError):
        return None


version_tuple = updater.version_tuple
update_message = updater.update_message


def gnome_hotkey_conflict(value):
    """Trả tên phím tắt GNOME trùng với `value` (chỉ kiểm vài phím hay đụng), hoặc None."""
    if not value:
        return None
    accel = "".join("<%s>" % {"Ctrl": "Control"}.get(m, m) for m in value.split("+")[:-1])
    accel += value.split("+")[-1]
    src = Gio.SettingsSchemaSource.get_default()
    schema = "org.gnome.desktop.wm.keybindings"
    if not src or not src.lookup(schema, True):
        return None
    s = Gio.Settings.new(schema)
    want = Gtk.accelerator_parse(accel)
    for key in ("switch-input-source", "switch-input-source-backward", "activate-window-menu",
                "switch-applications", "panel-run-dialog"):
        if key not in s.list_keys():
            continue
        for a in s.get_strv(key):
            if Gtk.accelerator_parse(a) == want:
                return key
    return None


# ------------------------------------------------------------------ onboarding

class OnboardingWindow(Adw.Window):
    """Hướng dẫn bật bộ gõ — dò Fcitx5/IBus, làm hộ những bước làm được an toàn."""

    def __init__(self, parent):
        super().__init__(transient_for=parent, modal=True, default_width=600,
                         default_height=640, title=_("Bật bộ gõ VietTelex"))
        self.parent_win = parent
        self.toasts = Adw.ToastOverlay()
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Adw.HeaderBar()
        refresh = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text=_("Kiểm tra lại"))
        refresh.connect("clicked", lambda _b: self.rebuild())
        header.pack_start(refresh)
        outer.append(header)
        self.scroller = Gtk.ScrolledWindow(vexpand=True)
        outer.append(self.scroller)
        self.toasts.set_child(outer)
        self.set_content(self.toasts)
        self.rebuild()

    def toast(self, text):
        self.toasts.add_toast(Adw.Toast.new(esc(text)))

    def step(self, group, done, title, subtitle, button=None, action=None):
        r = row(title, subtitle)
        icon = Gtk.Image.new_from_icon_name("emblem-ok-symbolic" if done
                                             else "dialog-warning-symbolic")
        icon.add_css_class("success" if done else "warning")
        r.add_prefix(icon)
        if button and action and not done:
            b = Gtk.Button(label=button, valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda _b: action())
            r.add_suffix(b)
        group.add(r)

    def rebuild(self):
        a = detect.assess(detect.collect())
        snap_env = {k: os.environ.get(k, "") for k in ("XDG_CURRENT_DESKTOP",)}
        gnome = "GNOME" in snap_env["XDG_CURRENT_DESKTOP"].upper()
        page = Adw.PreferencesPage()
        fw = a["framework"]
        choose = Adw.PreferencesGroup(
            title=_("Bộ khung gõ"),
            description=_("VietTelex là một input method của Fcitx5 (khuyên dùng — độ trễ thấp nhất, "
                        "hợp KDE) hoặc IBus (mặc định của Ubuntu/GNOME)."))
        if not fw:
            self.step(choose, False, _("Chưa thấy Fcitx5 hay IBus"),
                      _("Cài một trong hai gói: sudo apt install viettelex-fcitx5 (hoặc "
                      "viettelex-ibus), rồi mở lại hướng dẫn này."))
            page.add(choose)
            self._finish(page, a)
            return
        name = "Fcitx5" if fw == "fcitx5" else "IBus"
        self.step(choose, True, _("Đang dùng %s") % name,
                  _("Theo tiến trình đang chạy và biến môi trường của phiên đăng nhập này."))
        page.add(choose)
        if gnome:
            self._gnome_choice(page, a, fw)

        g = Adw.PreferencesGroup(title=_("Các bước"))
        pkg = "viettelex-fcitx5" if fw == "fcitx5" else "viettelex-ibus"
        self.step(g, a["installed"][fw], _("1. Cài gói %s") % pkg,
                  _("Đã cài.") if a["installed"][fw] else
                  _("sudo apt install %s (hoặc cài file .deb tải từ trang phát hành).") % pkg)
        if fw == "fcitx5":
            self.step(g, a["running"]["fcitx5"], _("2. Fcitx5 đang chạy"),
                      _("Đang chạy.") if a["running"]["fcitx5"] else
                      _("Bấm “Dùng Fcitx5” ở trên rồi đăng xuất/đăng nhập lại.") if gnome else
                      _("Khởi động Fcitx5. Nếu mỗi lần đăng nhập đều phải bật tay: chạy "
                      "im-config -n fcitx5 rồi đăng nhập lại."),
                      None if gnome else _("Khởi động Fcitx5"), self.start_fcitx5)
            self.step(g, a["enabled"]["fcitx5"], _("3. Thêm VietTelex vào nhóm bộ gõ"),
                      _("Đã có trong nhóm bộ gõ Fcitx5.") if a["enabled"]["fcitx5"] else
                      _("Thêm “Tiếng Việt (VietTelex)” vào nhóm hiện tại. Không cần đăng xuất."),
                      _("Thêm") if a["installed"]["fcitx5"] and a["running"]["fcitx5"] else None,
                      self.add_fcitx5)
            if a["running"]["fcitx5"] and shutil_which("fcitx5-configtool"):
                r = row(_("Cấu hình Fcitx5…"), _("Đổi thứ tự bộ gõ, phím chuyển giữa các bộ gõ."))
                b = Gtk.Button(label=_("Mở"), valign=Gtk.Align.CENTER)
                b.connect("clicked", lambda _b: spawn(["fcitx5-configtool"]))
                r.add_suffix(b)
                g.add(r)
        else:
            self.step(g, a["running"]["ibus"], _("2. IBus đang chạy"),
                      _("Đang chạy. Vừa cài gói xong thì bấm “Khởi động lại IBus” để IBus thấy "
                      "VietTelex.") if a["running"]["ibus"] else _("Khởi động IBus."),
                      _("Khởi động IBus"), lambda: self.run_ok(["ibus-daemon", "-drx"], _("Đã khởi động IBus.")))
            self.step(g, a["enabled"]["ibus"], _("3. Thêm VietTelex vào nguồn nhập"),
                      _("Đã có trong nguồn nhập.") if a["enabled"]["ibus"] else
                      (_("Cài đặt → Bàn phím → Nguồn nhập → + → Tiếng Việt → VietTelex. "
                       "Hoặc bấm Thêm để làm hộ.") if gnome else
                       _("Mở IBus Preferences → Input Method → Add → Vietnamese → VietTelex.")),
                      _("Thêm") if a["installed"]["ibus"] else None, lambda: self.add_ibus(gnome))
            r = row(_("Khởi động lại IBus"), _("Cần sau khi cài/cập nhật gói viettelex-ibus."))
            b = Gtk.Button(label="ibus restart", valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda _b: self.run_ok(["ibus", "restart"], _("Đã khởi động lại IBus.")))
            r.add_suffix(b)
            g.add(r)
            if gnome and shutil_which("gnome-control-center"):
                r = row(_("Mở Cài đặt Bàn phím…"), _("Nơi thêm/bớt và sắp xếp nguồn nhập của GNOME."))
                b = Gtk.Button(label=_("Mở"), valign=Gtk.Align.CENTER)
                b.connect("clicked", lambda _b: spawn(["gnome-control-center", "keyboard"]))
                r.add_suffix(b)
                g.add(r)
        page.add(g)
        self._finish(page, a)

    def _gnome_choice(self, page, a, fw):
        """GNOME: im-config không có tác dụng ⇒ nút đổi hẳn sang Fcitx5 / quay về IBus."""
        g = Adw.PreferencesGroup(
            title=_("Fcitx5 thay IBus trên GNOME"),
            description=_("Với Fcitx5, app GTK (Firefox, Terminal, Text Editor…) không gạch chân chữ "
                        "đang gõ và thanh trên cùng hiện icon VietTelex. Chrome/Electron vẫn có thể "
                        "gạch chân (xem tab Tương thích)."))
        if a["gnome_fcitx5"]:
            r = row(_("Đã đặt Fcitx5 chạy thay IBus"),
                    _("Đang có hiệu lực.")
                    if fw == "fcitx5" and "fcitx" in os.environ.get("GTK_IM_MODULE", "") else
                    _("Chưa có hiệu lực — đăng xuất rồi đăng nhập lại."))
            b = Gtk.Button(label=_("Quay về IBus"), valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda _b: self.use_ibus())
        elif not a["installed"]["fcitx5"]:
            r = row(_("Dùng Fcitx5 thay IBus"),
                    _("Cài gói trước: sudo apt install viettelex-fcitx5"))
            b = None
        else:
            r = row(_("Dùng Fcitx5 thay IBus"),
                    _("Fcitx5 tự chạy khi đăng nhập, app GTK nhận chữ thẳng từ Fcitx5. Đăng "
                      "xuất/đăng nhập lại một lần."))
            b = Gtk.Button(label=_("Dùng Fcitx5"), valign=Gtk.Align.CENTER)
            b.add_css_class("suggested-action")
            b.connect("clicked", lambda _b: self.use_fcitx5())
        if b:
            r.add_suffix(b)
        g.add(r)
        page.add(g)

    def use_fcitx5(self):
        try:
            gnome_fcitx5.enable()
        except OSError:
            self.toast(_("Không ghi được cấu hình trong ~/.config."))
            return
        self.toast(_("Xong — đăng xuất rồi đăng nhập lại để dùng Fcitx5."))
        GLib.timeout_add(800, lambda: (self.rebuild(), False)[1])

    def use_ibus(self):
        gnome_fcitx5.disable()
        self.toast(_("Xong — đăng xuất rồi đăng nhập lại để quay về IBus."))
        GLib.timeout_add(800, lambda: (self.rebuild(), False)[1])

    def _finish(self, page, a):
        warn = Adw.PreferencesGroup(title=_("Lưu ý"))
        has = False
        if "other_vn" in a["warnings"]:
            has = True
            self.step(warn, False, _("Có bộ gõ tiếng Việt khác: %s") % ", ".join(a["other_vn"]),
                      _("Bật cùng lúc hai bộ gõ Việt dễ bị gõ đúp dấu. Chỉ để một bộ trong danh "
                      "sách nguồn nhập (hoặc gỡ gói kia)."))
        if "lotus_uinput" in a["warnings"]:
            has = True
            stop = "sudo systemctl disable --now " + detect.LOTUS_SERVER_UNIT % "$USER"
            self.step(warn, False, _("fcitx5-lotus đang chạy chế độ uinput"),
                      _("Lotus ở chế độ uinput gửi phím BackSpace thật: đổi bộ gõ hay cửa sổ giữa "
                        "chừng một từ có thể xoá thừa chữ khi gõ bằng VietTelex. Nên chỉ giữ một bộ "
                        "gõ tiếng Việt; nếu vẫn dùng Lotus, chuyển Lotus sang Preedit hoặc tắt "
                        "server: %s") % stop)
        if "both_running" in a["warnings"]:
            has = True
            self.step(warn, False, _("Fcitx5 và IBus cùng chạy"),
                      _("Nên chỉ dùng một bộ khung gõ: im-config -n fcitx5 (hoặc ibus) rồi đăng "
                      "nhập lại."))
        if "wayland_chromium" in a["warnings"]:
            has = True
            self.step(warn, True, _("Phiên Wayland: Chrome/Electron (VS Code, Slack…)"),
                      _("Nếu không gõ được tiếng Việt trong Chrome hay app Electron, chạy app với "
                      "%s (hoặc %s). Lệnh copy sẵn ở tab Tương thích.") %
                      (compat.WAYLAND_IME_FLAGS, compat.X11_FLAG))
        if has:
            page.add(warn)

        t = Adw.PreferencesGroup(title=_("Thử gõ"),
                                 description=_("Bật VietTelex (%s) rồi gõ: vieejt → việt") %
                                 (hotkey_label(self.parent_win.cfg.get("general", "toggle_hotkey")) or _("menu bộ gõ")))
        e = Gtk.Entry(placeholder_text=_("Thử gõ tại đây…"), margin_top=6)
        t.add(e)
        page.add(t)
        self.scroller.set_child(page)
        self.parent_win.refresh_status()

    def run_ok(self, argv, msg):
        if spawn(argv):
            self.toast(msg)
            GLib.timeout_add(1500, lambda: (self.rebuild(), False)[1])
        else:
            self.toast(_("Không chạy được %s") % argv[0])

    def start_fcitx5(self):
        self.run_ok(["fcitx5", "-d", "-r"], _("Đã khởi động Fcitx5."))

    def add_fcitx5(self):
        """Thêm VietTelex vào nhóm hiện tại qua DBus Controller1 của Fcitx5."""
        try:
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            proxy = Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.NONE, None,
                                           "org.fcitx.Fcitx5", "/controller",
                                           "org.fcitx.Fcitx.Controller1", None)
            group = proxy.call_sync("CurrentInputMethodGroup", None,
                                    Gio.DBusCallFlags.NONE, 2000, None).unpack()[0]
            layout, items = proxy.call_sync("InputMethodGroupInfo", GLib.Variant("(s)", (group,)),
                                            Gio.DBusCallFlags.NONE, 2000, None).unpack()
            if any(i[0] == detect.FCITX5_ADDON for i in items):
                self.toast(_("VietTelex đã có trong nhóm bộ gõ."))
            else:
                items = list(items) + [(detect.FCITX5_ADDON, "")]
                proxy.call_sync("SetInputMethodGroupInfo",
                                GLib.Variant("(ssa(ss))", (group, layout, items)),
                                Gio.DBusCallFlags.NONE, 2000, None)
                try:
                    proxy.call_sync("Save", None, Gio.DBusCallFlags.NONE, 2000, None)
                except GLib.Error:
                    pass
                self.toast(_("Đã thêm VietTelex vào nhóm “%s”.") % group)
        except GLib.Error:
            if shutil_which("fcitx5-configtool"):
                spawn(["fcitx5-configtool"])
                self.toast(_("Không thêm tự động được — hãy thêm “VietTelex” trong cửa sổ cấu hình."))
            else:
                self.toast(_("Không kết nối được Fcitx5 — hãy khởi động Fcitx5 trước."))
        GLib.timeout_add(800, lambda: (self.rebuild(), False)[1])

    def add_ibus(self, gnome):
        src = Gio.SettingsSchemaSource.get_default()
        entry = ("ibus", detect.IBUS_ENGINE)
        try:
            if gnome and src and src.lookup("org.gnome.desktop.input-sources", True):
                s = Gio.Settings.new("org.gnome.desktop.input-sources")
                cur = list(s.get_value("sources").unpack())
                if entry not in cur:
                    s.set_value("sources", GLib.Variant("a(ss)", cur + [entry]))
                self.toast(_("Đã thêm VietTelex vào nguồn nhập — chuyển bằng Super+Space."))
            elif src and src.lookup("org.freedesktop.ibus.general", True):
                s = Gio.Settings.new("org.freedesktop.ibus.general")
                cur = list(s.get_strv("preload-engines"))
                if detect.IBUS_ENGINE not in cur:
                    s.set_strv("preload-engines", cur + [detect.IBUS_ENGINE])
                spawn(["ibus", "restart"])
                self.toast(_("Đã thêm VietTelex vào IBus."))
            elif shutil_which("ibus-setup"):
                spawn(["ibus-setup"])
            else:
                self.toast(_("Không tìm thấy cấu hình IBus."))
        except GLib.Error:
            self.toast(_("Không thêm được — hãy thêm tay trong Cài đặt → Bàn phím."))
        GLib.timeout_add(800, lambda: (self.rebuild(), False)[1])


def shutil_which(name):
    import shutil
    return shutil.which(name)


# ------------------------------------------------------------------ app

class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        # Ngôn ngữ giao diện: theo config (mặc định tiếng Việt, KHÔNG theo locale của máy).
        self.cfg = config.Config()
        i18n.set_language(self.cfg.get("general", "ui_language"))
        self.win = None
        self.want_onboarding = False
        self.add_main_option("onboarding", 0, GLib.OptionFlags.NONE, GLib.OptionArg.NONE,
                             _("Mở hướng dẫn bật bộ gõ"), None)
        self.add_main_option("no-onboarding", 0, GLib.OptionFlags.NONE, GLib.OptionArg.NONE,
                             _("Không tự mở hướng dẫn khi bộ gõ chưa bật"), None)
        self.add_main_option("page", 0, GLib.OptionFlags.NONE, GLib.OptionArg.STRING,
                             _("Mở tab: typing|options|shortcuts|modes|compat|about"), "TAB")

    def do_command_line(self, cmdline):
        opts = cmdline.get_options_dict().end().unpack()
        self.want_onboarding = bool(opts.get("onboarding"))
        self.page = opts.get("page")
        self.no_onboarding = bool(opts.get("no-onboarding"))
        self.activate()
        return 0

    def do_activate(self):
        Gtk.Window.set_default_icon_name(APP_ID)
        if not self.win:
            self.win = SettingsWindow(self, self.cfg)
        pages = {"typing": 0, "options": 1, "shortcuts": 2, "modes": 3, "compat": 4, "about": 5}
        if getattr(self, "page", None) in pages:
            self._select_page(pages[self.page])
        self.win.present()
        auto = not self.win.assessment["ok"] and not getattr(self, "no_onboarding", False)
        if self.want_onboarding or auto:
            self.want_onboarding = False
            GLib.idle_add(lambda: (self.win.show_onboarding(), False)[1])

    def rebuild_window(self):
        """Đổi ngôn ngữ: dựng lại cửa sổ (mọi nhãn) ngay, giữ nguyên tab đang mở."""
        old = self.win
        if old is None:
            return
        index = self._current_page()
        self.win = SettingsWindow(self, old.cfg)
        self._select_page(index)
        self.win.present()
        if getattr(old, "_monitor", None) is not None:
            old._monitor.cancel()
        old.destroy()

    def _current_page(self):
        stack = _find(self.win, Adw.ViewStack)
        if not stack:
            return 0
        cur, child, i = stack.get_visible_child(), stack.get_first_child(), 0
        while child is not None:
            if child == cur:
                return i
            child, i = child.get_next_sibling(), i + 1
        return 0

    def _select_page(self, index):
        # PreferencesWindow không có API chọn trang theo chỉ số ở libadwaita 1.1.
        child, i = None, 0
        stack = _find(self.win, Adw.ViewStack)
        if not stack:
            return
        child = stack.get_first_child()
        while child is not None:
            if i == index:
                stack.set_visible_child(child)
                return
            child, i = child.get_next_sibling(), i + 1


def _find(widget, cls):
    if isinstance(widget, cls):
        return widget
    c = widget.get_first_child()
    while c is not None:
        f = _find(c, cls)
        if f:
            return f
        c = c.get_next_sibling()
    return None


def main(argv=None):
    return App().run(argv if argv is not None else sys.argv)
