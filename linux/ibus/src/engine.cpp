// engine.cpp — IBus engine "viettelex" (Tiếng Việt (VietTelex)).
//
// Thin GObject adapter over viettelex::Session (linux/common). One IBusEngine object per
// input context. Preedit is sent in IBUS_ENGINE_PREEDIT_COMMIT mode, so ibus-daemon
// commits the visible word itself on focus-out / reset — nothing typed is swallowed.
// Builds against IBus 1.5.26 (Ubuntu 22.04) and newer; app identity (per-app Vi/En
// memory, [app_modes]) comes from focus_in_id (IBus 1.5.28+), otherwise "default". On
// GNOME Wayland both are generic ("gnome-shell"/"default": one shared context for every
// app), so the focused app is read from gnome-shell over the session bus instead
// (viettelex::GnomeAppMonitor).
// Text tools ("Công cụ…" property menu + the optional Thêm dấu hotkey) run the helper
// viettelex-text-tool off the main thread (viettelex::TextToolRunner) and commit the result
// over the selection. Labels follow Settings::uiLanguage; the InputMode icon/symbol follow
// Việt/Anh (Vᴛ / E, like the macOS menu bar).
// Caret suggestions (phép tính, chip số, sửa lỗi gõ, thêm dấu, ngày giờ — caret_hints.h) are
// computed by the same helper in `--serve` mode (viettelex::HintService) and shown as the
// engine's auxiliary text, which ibus-ui-gtk3 and GNOME Shell draw in the popup at the caret.

#include "engine.h"

#include "viettelex/app.h"
#include "viettelex/caret_hints.h"
#include "viettelex/gnome.h"
#include "viettelex/gnome_monitor.h"
#include "viettelex/session.h"
#include "viettelex/settings.h"
#include "viettelex/text_tools.h"
#include "viettelex/watcher.h"

#include <glib-unix.h>

#include <chrono>
#include <cstdlib>
#include <functional>
#include <memory>
#include <set>
#include <string>

namespace vt = viettelex;

struct VtIBusEngine {
    IBusEngine parent;
    vt::Session *session;
    std::string *appId;     // effective id: clientId, or the GNOME focused app it stands for
    std::string *clientId;  // what IBus reported ("default" without focus_in_id)
    std::string *clientName;  // raw IBus client name ("gtk3-im:…", "xim", "gnome-shell")
    guint lastKeycode;        // keycode of the key being processed (for forwarded text)
    gboolean focused;
    IBusPropList *props;
    IBusProperty *modeProp;
    IBusProperty *settingsProp;
    IBusProperty *toolsProp;       // PROP_TYPE_MENU "Công cụ…"
    IBusPropList *toolsList;
    IBusProperty *toolProps[viettelex::kTextToolCount];
    // Text tool result that arrived while unfocused (the panel menu took focus): committed
    // on the next focus-in if still fresh.
    std::string *pendingResult;
    gint64 pendingUntil;        // g_get_monotonic_time() µs
    gboolean password;
    guint purpose, hints;       // last set_content_type
    gboolean rememberState;     // AppPolicy.rememberState of the current field
    // The client really sent surrounding text since this focus began. The capability bit
    // alone is not enough: IBus keeps an empty text for clients that never send one
    // (XIM, some Qt/Electron builds, terminals), so "nothing before the caret" was trusted.
    gboolean surroundingProven;
};

struct VtIBusEngineClass {
    IBusEngineClass parent;
};

G_DEFINE_TYPE(VtIBusEngine, vt_ibus_engine, IBUS_TYPE_ENGINE)

namespace {

// Process-wide state shared by every engine object.
struct Globals {
    std::unique_ptr<vt::SettingsWatcher> watcher;
    std::unique_ptr<vt::AppStateStore> appState;
    std::set<VtIBusEngine *> engines;
    std::unique_ptr<vt::GnomeAppMonitor> gnome;  // GNOME Wayland only
    std::unique_ptr<vt::TextToolRunner> runner;
    std::unique_ptr<vt::HintService> hints;  // caret suggestions (helper --serve)
};
Globals &G() {
    static Globals g;
    return g;
}

const vt::Settings &settings() { return G().watcher->settings(); }

bool english() { return vt::isEnglishUi(settings().uiLanguage); }
std::string tr(const char *vi) { return vt::uiText(vi, english()); }
// IBusText owns a copy of the string.
IBusText *text(const std::string &s) { return ibus_text_new_from_string(s.c_str()); }

constexpr guint kBackSpaceKeycode = 14;  // evdev KEY_BACKSPACE (IBus keycodes are X keycode − 8)

class IBusClient final : public vt::InputContext {
public:
    explicit IBusClient(IBusEngine *e) : e_(e) {}
    void setPreedit(const std::string &s, bool misspelled) override {
        if (s.empty()) {
            ibus_engine_update_preedit_text_with_mode(e_, ibus_text_new_from_static_string(""), 0, FALSE,
                                                      IBUS_ENGINE_PREEDIT_COMMIT);
            return;
        }
        IBusText *t = ibus_text_new_from_string(s.c_str());
        guint len = ibus_text_get_length(t);
        // An explicit NONE (not "no attribute"): GTK3/GTK4 IBus module, VTE and Qt's IBus
        // plugin draw exactly the attributes we send. Chromium and Wayland text-input-v3
        // clients (GNOME Shell drops style attributes) still draw their own underline.
        // Misspelled (opt-in): IBUS_ATTR_UNDERLINE_ERROR (GTK/Pango: wavy error underline)
        // and red text, which also shows in clients that ignore the underline style.
        ibus_text_append_attribute(t, IBUS_ATTR_TYPE_UNDERLINE,
                                   misspelled                    ? IBUS_ATTR_UNDERLINE_ERROR
                                   : settings().preeditUnderline ? IBUS_ATTR_UNDERLINE_SINGLE
                                                                 : IBUS_ATTR_UNDERLINE_NONE,
                                   0, len);
        if (misspelled) ibus_text_append_attribute(t, IBUS_ATTR_TYPE_FOREGROUND, 0xE01B24, 0, len);
        ibus_engine_update_preedit_text_with_mode(e_, t, len, TRUE, IBUS_ENGINE_PREEDIT_COMMIT);
    }
    void commit(const std::string &s) override {
        ibus_engine_commit_text(e_, ibus_text_new_from_string(s.c_str()));
    }
    void deleteBeforeCursor(int n) override {
        if (n > 0) ibus_engine_delete_surrounding_text(e_, -n, guint(n));
    }
    // Direct (terminals on the GTK2/3 IBus module, see vt::ClientHost): BackSpace and the new
    // text all go out as ForwardKeyEvent. The module gdk_event_put()s each one, so they reach
    // VTE in order; a forwarded printable key arrives with IBUS_FORWARD_MASK and the module
    // commits it itself (ibus_im_context_commit_event) — commit_text would be applied at once,
    // before the queued BackSpaces (the ordering bug ibus-bamboo papers over with sleeps).
    void directReplace(int backspaces, const std::string &s) override {
        for (int i = 0; i < backspaces; ++i) {
            ibus_engine_forward_key_event(e_, IBUS_KEY_BackSpace, kBackSpaceKeycode, 0);
            ibus_engine_forward_key_event(e_, IBUS_KEY_BackSpace, kBackSpaceKeycode, IBUS_RELEASE_MASK);
        }
        // A non-zero keycode keeps the module from looking the keysym up in the keymap
        // (which fails for ư/ơ/ử… and logs a warning); the keyval alone decides the text.
        guint keycode = reinterpret_cast<VtIBusEngine *>(e_)->lastKeycode;
        if (keycode == 0) keycode = kBackSpaceKeycode;
        for (const gchar *p = s.c_str(); *p; p = g_utf8_next_char(p)) {
            guint kv = ibus_unicode_to_keyval(g_utf8_get_char(p));
            ibus_engine_forward_key_event(e_, kv, keycode, 0);
            ibus_engine_forward_key_event(e_, kv, keycode, IBUS_RELEASE_MASK);
        }
    }
    // [experimental] no_underline = "forward-keys" (Chromium/Electron on GNOME Wayland): real
    // BackSpace keys, then the Session commits. gnome-shell turns ForwardKeyEvent into
    // clutter_input_method_forward_key and CommitText into an IM commit event — mutter ≥ 3.38
    // queues both as Clutter events in this order and flushes text_input.done before a
    // passed-through key, so the app gets wl_keyboard BackSpace, then the commit.
    void forwardBackspaces(int n) override {
        for (int i = 0; i < n; ++i) {
            ibus_engine_forward_key_event(e_, IBUS_KEY_BackSpace, kBackSpaceKeycode, 0);
            ibus_engine_forward_key_event(e_, IBUS_KEY_BackSpace, kBackSpaceKeycode, IBUS_RELEASE_MASK);
        }
    }
    // Auxiliary text: the candidate popup at the caret (never the preedit).
    void showHint(const std::string &label) override {
        ibus_engine_update_auxiliary_text(e_, ibus_text_new_from_string(label.c_str()), TRUE);
    }
    void hideHint() override { ibus_engine_hide_auxiliary_text(e_); }
    bool textBeforeCursor(std::string &out) override {
        IBusText *text = nullptr;
        guint cursor = 0, anchor = 0;
        if (!read(text, cursor, anchor)) return false;
        const gchar *s = ibus_text_get_text(text);
        if (!s) return false;
        glong len = g_utf8_strlen(s, -1);
        if (glong(cursor) > len) return false;
        const gchar *end = g_utf8_offset_to_pointer(s, glong(cursor));
        out.assign(s, size_t(end - s));
        return true;
    }
    // Verify-before-delete (Session) asks before every in-place edit: copy only the tail.
    bool textBeforeCursorTail(size_t maxChars, std::string &out) override {
        IBusText *text = nullptr;
        guint cursor = 0, anchor = 0;
        if (!read(text, cursor, anchor)) return false;
        const gchar *s = ibus_text_get_text(text);
        if (!s) return false;
        glong len = g_utf8_strlen(s, -1);
        if (glong(cursor) > len) return false;
        const gchar *end = g_utf8_offset_to_pointer(s, glong(cursor));
        const gchar *start = end;
        for (size_t n = 0; start > s && n < maxChars; ++n) start = g_utf8_prev_char(start);
        out.assign(start, size_t(end - start));
        return true;
    }
    bool hasSelection() override {
        IBusText *text = nullptr;
        guint cursor = 0, anchor = 0;
        if (!read(text, cursor, anchor)) return false;
        return anchor != cursor;
    }
    // Before a reach-back only (Session): the GTK3 IBus module (Firefox, Chromium, GTK3 apps)
    // sends anchor == cursor even with text selected — then PRIMARY against the caret, read
    // with a short timeout (rare: re-edit / ⌫ reopen / shortcut or auto-restore delete).
    bool selectionAtCaret() override {
        IBusText *text = nullptr;
        guint cursor = 0, anchor = 0;
        if (!read(text, cursor, anchor)) return false;
        const gchar *s = ibus_text_get_text(text);
        if (!s) return anchor != cursor;
        return vt::selectionAtCaret(s, cursor, anchor,
                                    [](std::string &p) { return vt::readPrimarySelection(p, 150); });
    }

private:
    bool read(IBusText *&text, guint &cursor, guint &anchor) {
        if (!(e_->client_capabilities & IBUS_CAP_SURROUNDING_TEXT)) return false;
        if (!reinterpret_cast<VtIBusEngine *>(e_)->surroundingProven) return false;
        ibus_engine_get_surrounding_text(e_, &text, &cursor, &anchor);
        return text != nullptr;
    }
    IBusEngine *e_;
};

void updateModeProp(VtIBusEngine *self) {
    bool vi = self->session->vietnamese();
    ibus_property_set_label(self->modeProp, text(tr(vi ? "Tiếng Việt" : "English")));
    // GNOME Shell shows the InputMode symbol as the indicator text; ibus-ui-gtk3 (and
    // icon-capable panels) show its icon. "Vᴛ" (small-cap T, U+1D1B) mimics the macOS menu-bar mark.
    ibus_property_set_symbol(self->modeProp, ibus_text_new_from_static_string(vi ? "Vᴛ" : "E"));
    ibus_property_set_icon(self->modeProp, vi ? "viettelex" : "viettelex-off");
    ibus_property_set_state(self->modeProp, vi ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED);
    ibus_engine_update_property(IBUS_ENGINE(self), self->modeProp);
}

// Labels in the UI language + visibility of "Công cụ…" (text_tools_menu, helper installed).
void refreshPropLabels(VtIBusEngine *self) {
    ibus_property_set_tooltip(self->modeProp, text(tr("Chuyển Việt/Anh (Ctrl+Space)")));
    ibus_property_set_label(self->settingsProp, text(tr("Cài đặt…")));
    ibus_property_set_tooltip(self->settingsProp, text(tr("Mở VietTelex Settings")));
    ibus_property_set_label(self->toolsProp, text(tr("Công cụ…")));
    ibus_property_set_tooltip(self->toolsProp, text(tr("Công cụ văn bản cho chữ đang bôi đen")));
    ibus_property_set_visible(self->toolsProp, settings().textToolsMenu && vt::textToolAvailable());
    for (int i = 0; i < vt::kTextToolCount; ++i)
        ibus_property_set_label(self->toolProps[i], text(vt::textToolLabel(vt::textToolAt(i), english())));
}

void onToggled(VtIBusEngine *self, bool vi) {
    if (settings().perAppState && self->rememberState) G().appState->set(*self->appId, vi);
    updateModeProp(self);
}

void refreshFieldFlags(VtIBusEngine *self) {
    IBusClient client(IBUS_ENGINE(self));
    bool surrounding = (IBUS_ENGINE(self)->client_capabilities & IBUS_CAP_SURROUNDING_TEXT) &&
                       self->surroundingProven;
    vt::FieldHints field;
    field.terminal = self->purpose == IBUS_INPUT_PURPOSE_TERMINAL;
    field.urlOrEmail = self->purpose == IBUS_INPUT_PURPOSE_URL || self->purpose == IBUS_INPUT_PURPOSE_EMAIL;
    field.numeric = self->purpose == IBUS_INPUT_PURPOSE_DIGITS || self->purpose == IBUS_INPUT_PURPOSE_NUMBER ||
                    self->purpose == IBUS_INPUT_PURPOSE_PHONE;
    field.sensitive = (self->hints & IBUS_INPUT_HINT_PRIVATE) != 0;
    field.host = vt::ibusClientHost(*self->clientName);
    // gnome-shell turns our forwarded keys into mutter events — dropped by mutter 50.
    if (field.host == vt::ClientHost::IBusWayland)
        field.forwardedKeysDropped = !vt::gnome::mutterDeliversForwardedKeys(G().gnome ? G().gnome->shellMajor() : 0);
    auto policy = vt::resolveAppPolicy(*self->appId, settings(), surrounding, field);
    self->rememberState = policy.rememberState;
    self->session->setPassthrough(self->password || policy.off || policy.passthrough, client);
    self->session->setDisplayMode(policy.mode, client);
    self->session->setDeleteWithKeys(policy.deleteWithKeys);
    self->session->setSurroundingEdits(policy.allowSurroundingEdits);
    // VIETTELEX_DEBUG=1 in ibus-daemon's environment: why a field got its mode (stderr).
    static const bool debug = std::getenv("VIETTELEX_DEBUG") != nullptr;
    if (debug)
        g_message("viettelex: client=%s app=%s host=%d surroundingCap=%d proven=%d purpose=%d shell=%d "
                  "keysDropped=%d mode=%d deleteWithKeys=%d",
                  self->clientName->c_str(), self->appId->c_str(), int(field.host),
                  (IBUS_ENGINE(self)->client_capabilities & IBUS_CAP_SURROUNDING_TEXT) != 0,
                  int(self->surroundingProven), int(self->purpose),
                  G().gnome ? G().gnome->shellMajor() : 0, int(field.forwardedKeysDropped), int(policy.mode), int(policy.deleteWithKeys));
}

std::string effectiveAppId(const std::string &clientId) {
    return G().gnome ? G().gnome->resolve(clientId) : clientId;
}

void loadAppState(VtIBusEngine *self) {
    const auto &s = settings();
    IBusClient client(IBUS_ENGINE(self));
    bool vi = s.perAppState ? G().appState->vietnamese(*self->appId, s.defaultVietnamese) : s.defaultVietnamese;
    self->session->setVietnamese(vi, client);
}

void applySettingsToAll() {
    const auto &s = G().watcher->reload();
    for (auto *e : G().engines) {
        e->session->applySettings(s);
        refreshFieldFlags(e);
        refreshPropLabels(e);
        if (e->focused) {
            // Re-register: panels rebuild the menu (labels, "Công cụ…" shown/hidden).
            ibus_engine_register_properties(IBUS_ENGINE(e), e->props);
            updateModeProp(e);
        }
    }
}

// MARK: - text tools (Công cụ…) — see linux/common/include/viettelex/text_tools.h

void commitToolResult(VtIBusEngine *self, const std::string &result) {
    IBusClient client(IBUS_ENGINE(self));
    self->session->finish(client, true);
    // Typing over the selection replaces it (GTK, Qt, Chromium, LibreOffice…).
    ibus_engine_commit_text(IBUS_ENGINE(self), ibus_text_new_from_string(result.c_str()));
    self->session->focusIn();  // the text around the caret changed: forget the old word context
}

void commitPendingResult(VtIBusEngine *self) {
    if (self->pendingResult->empty()) return;
    std::string r;
    r.swap(*self->pendingResult);
    if (g_get_monotonic_time() <= self->pendingUntil) commitToolResult(self, r);
}

void runTextTool(VtIBusEngine *self, vt::TextTool tool) {
    IBusEngine *engine = IBUS_ENGINE(self);
    // Password / private fields: never read them. Terminals: typing over a selection
    // replaces nothing there — the result would land at the prompt.
    if (self->password || (self->hints & IBUS_INPUT_HINT_PRIVATE) || self->purpose == IBUS_INPUT_PURPOSE_TERMINAL ||
        vt::isTerminalApp(*self->appId) || !G().runner || G().runner->busy())
        return;
    IBusClient client(engine);
    self->session->finish(client, true);
    vt::TextToolRunner::Source source;
    if ((engine->client_capabilities & IBUS_CAP_SURROUNDING_TEXT) && self->surroundingProven) {
        // The app reports its text: its selection is authoritative.
        IBusText *t = nullptr;
        guint cursor = 0, anchor = 0;
        ibus_engine_get_surrounding_text(engine, &t, &cursor, &anchor);
        const gchar *s = t ? ibus_text_get_text(t) : nullptr;
        if (!s) return;
        std::string sel;
        if (vt::selectionFromSurrounding(s, cursor, anchor, sel)) {
            source = [sel](std::string &out) {
                out = sel;
                return true;
            };
        } else {
            // No selection reported — GTK3 never reports one (no anchor): PRIMARY, but only
            // when it touches the caret, else nothing to do.
            source = [text = std::string(s), cursor](std::string &out) {
                std::string p;
                if (!vt::readPrimarySelection(p) || !vt::primaryAdjacentToCursor(text, cursor, p)) return false;
                out = std::move(p);
                return true;
            };
        }
    } else {
        source = [](std::string &out) { return vt::readPrimarySelection(out); };
    }
    G().runner->start(tool, std::move(source), [self](bool changed, const std::string &, const std::string &result) {
        try {
            // The engine may have been destroyed while the helper ran.
            if (!changed || !G().engines.count(self)) return;
            if (self->focused) {
                commitToolResult(self, result);
            } else {
                *self->pendingResult = result;
                self->pendingUntil = g_get_monotonic_time() + 3 * G_USEC_PER_SEC;
            }
        } catch (...) {
        }
    });
}

// Session → helper (worker thread) → back on the main loop.
void submitHint(VtIBusEngine *self, const vt::HintRequest &r) {
    if (!G().hints) return;
    uint64_t gen = r.gen;
    G().hints->submit(r, [self, gen](bool ok, const vt::CaretSuggestion &c) {
        try {
            // The engine may have been destroyed or lost focus while the helper ran.
            if (!ok || !G().engines.count(self) || !self->focused) return;
            IBusClient client(IBUS_ENGINE(self));
            self->session->deliverHint(gen, c, client);
        } catch (...) {
        }
    });
}

gboolean runOnMain(gpointer data) {
    auto *f = static_cast<std::function<void()> *>(data);
    try {
        (*f)();
    } catch (...) {
    }
    delete f;
    return G_SOURCE_REMOVE;
}

gboolean onSettingsFd(gint, GIOCondition, gpointer) {
    try {
        if (G().watcher->drain()) applySettingsToAll();
    } catch (...) {
    }
    return G_SOURCE_CONTINUE;
}

// Main loop: the GNOME focused app (or overview) changed / became known. Re-resolve the
// focused engines that stand for gnome-shell's shared context.
gboolean onGnomeFocusChanged(gpointer) {
    try {
        for (auto *e : G().engines) {
            if (!e->focused || !vt::gnome::isSharedShellClientId(*e->clientId)) continue;
            std::string id = effectiveAppId(*e->clientId);
            if (id == *e->appId) continue;
            *e->appId = id;
            // Vi/En memory of the new app; never flipped under a word being typed.
            if (!e->session->composing()) loadAppState(e);
            refreshFieldFlags(e);
            updateModeProp(e);
        }
    } catch (...) {
    }
    return G_SOURCE_REMOVE;
}

// MARK: - vfuncs

gboolean processKeyEvent(IBusEngine *engine, guint keyval, guint keycode, guint state) {
    // keysym (after layout) is what we read — AZERTY/Dvorak work
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    try {
        vt::KeyEvent ev;
        // A key we forwarded ourselves (Direct mode) that a client sent back: never re-process.
        ev.forwarded = (state & IBUS_FORWARD_MASK) != 0;
        if (!ev.forwarded && !(state & IBUS_RELEASE_MASK)) self->lastKeycode = keycode;
        ev.keysym = keyval;
        ev.unicode = ibus_keyval_to_unicode(keyval);
        ev.release = state & IBUS_RELEASE_MASK;
        if (state & IBUS_SHIFT_MASK) ev.mods |= vt::VT_MOD_SHIFT;
        if (state & IBUS_CONTROL_MASK) ev.mods |= vt::VT_MOD_CTRL;
        if (state & IBUS_MOD1_MASK) ev.mods |= vt::VT_MOD_ALT;
        if (state & (IBUS_SUPER_MASK | IBUS_MOD4_MASK)) ev.mods |= vt::VT_MOD_SUPER;
        if (self->session->isAddTonesHotkey(ev)) {
            // Consumed even when nothing is selected: the chord belongs to this tool.
            runTextTool(self, vt::TextTool::AddTones);
            return TRUE;
        }
        IBusClient client(engine);
        bool handled = self->session->processKey(ev, client);
        static const bool debug = std::getenv("VIETTELEX_DEBUG") != nullptr;
        if (debug && !ev.release) {
            std::string before;
            bool ok = client.textBeforeCursorTail(24, before);
            g_message("viettelex key: sym=%u fwd=%d mode=%d distrusted=%d before(%d)=[%s]", keyval,
                      int(ev.forwarded), int(self->session->displayMode()),
                      int(self->session->surroundingDistrusted()), int(ok), before.c_str());
        }
        return handled ? TRUE : FALSE;
    } catch (...) {
        return FALSE;
    }
}

void focusCommon(VtIBusEngine *self) {
    if (G().watcher->changedOnDisk()) applySettingsToAll();  // inotify fallback
    self->surroundingProven = FALSE;  // prove it again for this field
    self->focused = TRUE;
    *self->appId = effectiveAppId(*self->clientId);
    loadAppState(self);
    refreshFieldFlags(self);
    // Emits RequireSurroundingText: the client sends its text now (→ setSurroundingText),
    // and the GTK module drops the capability when the widget cannot provide it
    // (client/gtk2/ibusimcontext.c; ibus-bamboo does the same).
    {
        IBusText *text = nullptr;
        guint cursor = 0, anchor = 0;
        ibus_engine_get_surrounding_text(IBUS_ENGINE(self), &text, &cursor, &anchor);
    }
    self->session->focusIn();
    refreshPropLabels(self);
    ibus_engine_register_properties(IBUS_ENGINE(self), self->props);
    updateModeProp(self);
    commitPendingResult(self);
}

void focusIn(IBusEngine *engine) {
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    try {
        focusCommon(self);
    } catch (...) {
    }
    IBUS_ENGINE_CLASS(vt_ibus_engine_parent_class)->focus_in(engine);
}

#if IBUS_CHECK_VERSION(1, 5, 28)
void focusInId(IBusEngine *engine, const gchar *objectPath, const gchar *client) {
    (void)objectPath;
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    try {
        *self->clientId = vt::normalizeAppId(client ? client : "");
        *self->clientName = client ? client : "";
        focusCommon(self);
    } catch (...) {
    }
}
#endif

void focusOut(IBusEngine *engine) {
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    self->focused = FALSE;
    try {
        IBusClient client(engine);
        self->session->finish(client, false);  // PREEDIT_COMMIT: the daemon commits it
    } catch (...) {
    }
    IBUS_ENGINE_CLASS(vt_ibus_engine_parent_class)->focus_out(engine);
}

void reset(IBusEngine *engine) {
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    try {
        IBusClient client(engine);
        self->session->finish(client, false);
    } catch (...) {
    }
    IBUS_ENGINE_CLASS(vt_ibus_engine_parent_class)->reset(engine);
}

void disable(IBusEngine *engine) {
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    try {
        IBusClient client(engine);
        self->session->finish(client, true);
    } catch (...) {
    }
    IBUS_ENGINE_CLASS(vt_ibus_engine_parent_class)->disable(engine);
}

void setSurroundingText(IBusEngine *engine, IBusText *text, guint cursor, guint anchor) {
    IBUS_ENGINE_CLASS(vt_ibus_engine_parent_class)->set_surrounding_text(engine, text, cursor, anchor);
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    // Only real text proves it: ibus-daemon's engine proxy also pushes its cached empty
    // text. An empty field gets proven by the update that follows its first word.
    if (self->surroundingProven || !text || ibus_text_get_length(text) == 0) return;
    self->surroundingProven = TRUE;
    try {
        refreshFieldFlags(self);
    } catch (...) {
    }
}

void setCapabilities(IBusEngine *engine, guint caps) {
    engine->client_capabilities = caps;
    if (!(caps & IBUS_CAP_SURROUNDING_TEXT)) reinterpret_cast<VtIBusEngine *>(engine)->surroundingProven = FALSE;
    try {
        refreshFieldFlags(reinterpret_cast<VtIBusEngine *>(engine));
    } catch (...) {
    }
}

void setContentType(IBusEngine *engine, guint purpose, guint hints) {
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    self->password = purpose == IBUS_INPUT_PURPOSE_PASSWORD || purpose == IBUS_INPUT_PURPOSE_PIN;
    self->purpose = purpose;
    self->hints = hints;
    try {
        refreshFieldFlags(self);
    } catch (...) {
    }
    IBUS_ENGINE_CLASS(vt_ibus_engine_parent_class)->set_content_type(engine, purpose, hints);
}

void propertyActivate(IBusEngine *engine, const gchar *name, guint state) {
    (void)state;
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    std::string n = name ? name : "";
    if (n == "InputMode") {
        IBusClient client(engine);
        self->session->setVietnamese(!self->session->vietnamese(), client);
        onToggled(self, self->session->vietnamese());
    } else if (n == "Settings") {
        g_spawn_command_line_async("viettelex-settings", nullptr);
    } else if (n.rfind("Tool.", 0) == 0) {
        vt::TextTool tool = vt::TextTool::AddTones;
        try {
            if (vt::textToolFromId(n.substr(5), tool)) runTextTool(self, tool);
        } catch (...) {
        }
    }
}

void dispose(GObject *obj) {
    auto *self = reinterpret_cast<VtIBusEngine *>(obj);
    G().engines.erase(self);
    delete self->session;
    self->session = nullptr;
    delete self->appId;
    self->appId = nullptr;
    delete self->clientId;
    self->clientId = nullptr;
    delete self->clientName;
    self->clientName = nullptr;
    delete self->pendingResult;
    self->pendingResult = nullptr;
    g_clear_object(&self->props);
    G_OBJECT_CLASS(vt_ibus_engine_parent_class)->dispose(obj);
}

}  // namespace

static void vt_ibus_engine_class_init(VtIBusEngineClass *klass) {
    GObjectClass *oc = G_OBJECT_CLASS(klass);
    oc->dispose = dispose;
    IBusEngineClass *ec = IBUS_ENGINE_CLASS(klass);
    ec->process_key_event = processKeyEvent;
    ec->focus_in = focusIn;
#if IBUS_CHECK_VERSION(1, 5, 28)
    ec->focus_in_id = focusInId;
#endif
    ec->focus_out = focusOut;
    ec->reset = reset;
    ec->disable = disable;
    ec->set_capabilities = setCapabilities;
    ec->set_surrounding_text = setSurroundingText;
    ec->set_content_type = setContentType;
    ec->property_activate = propertyActivate;
}

static void vt_ibus_engine_init(VtIBusEngine *self) {
    self->session = new vt::Session();
    self->appId = new std::string("default");
    self->clientId = new std::string("default");
    self->clientName = new std::string();
    self->lastKeycode = 0;
    self->focused = FALSE;
    self->password = FALSE;
    self->surroundingProven = FALSE;
    self->purpose = IBUS_INPUT_PURPOSE_FREE_FORM;
    self->hints = 0;
    self->rememberState = TRUE;
    self->pendingResult = new std::string();
    self->pendingUntil = 0;
    self->session->applySettings(settings());
    self->session->onToggle = [self](bool vi) { onToggled(self, vi); };
    if (G().hints && G().hints->available())
        self->session->setHintSink([self](const vt::HintRequest &r) { submitHint(self, r); });

    self->props = ibus_prop_list_new();
    g_object_ref_sink(self->props);
    self->modeProp = ibus_property_new("InputMode", PROP_TYPE_TOGGLE,
                                       ibus_text_new_from_static_string("Tiếng Việt"), "viettelex",
                                       ibus_text_new_from_static_string("Chuyển Việt/Anh (Ctrl+Space)"), TRUE,
                                       TRUE, PROP_STATE_CHECKED, nullptr);
    ibus_prop_list_append(self->props, self->modeProp);
    // "Công cụ…" → the six text tools (like macOS: VietTelex menu → Công cụ…).
    self->toolsList = ibus_prop_list_new();
    for (int i = 0; i < vt::kTextToolCount; ++i) {
        vt::TextTool tool = vt::textToolAt(i);
        std::string key = std::string("Tool.") + vt::textToolId(tool);
        self->toolProps[i] = ibus_property_new(key.c_str(), PROP_TYPE_NORMAL,
                                               text(vt::textToolLabel(tool, false)), nullptr, nullptr, TRUE, TRUE,
                                               PROP_STATE_UNCHECKED, nullptr);
        ibus_prop_list_append(self->toolsList, self->toolProps[i]);
    }
    self->toolsProp = ibus_property_new("Tools", PROP_TYPE_MENU, ibus_text_new_from_static_string("Công cụ…"),
                                        "edit-select-all", nullptr, TRUE, TRUE, PROP_STATE_UNCHECKED,
                                        self->toolsList);
    ibus_prop_list_append(self->props, self->toolsProp);
    self->settingsProp = ibus_property_new("Settings", PROP_TYPE_NORMAL,
                                           ibus_text_new_from_static_string("Cài đặt…"), "preferences-system",
                                           ibus_text_new_from_static_string("Mở VietTelex Settings"), TRUE, TRUE,
                                           PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(self->props, self->settingsProp);
    refreshPropLabels(self);
    G().engines.insert(self);
}

void vt_ibus_globals_init() {
    G().watcher = std::make_unique<vt::SettingsWatcher>();
    G().appState = std::make_unique<vt::AppStateStore>(vt::appStatePath());
    G().appState->load();
    if (G().watcher->fd() >= 0) g_unix_fd_add(G().watcher->fd(), G_IO_IN, onSettingsFd, nullptr);
    G().runner = std::make_unique<vt::TextToolRunner>(
        [](std::function<void()> f) { g_main_context_invoke(nullptr, runOnMain, new std::function<void()>(std::move(f))); });
    G().hints = std::make_unique<vt::HintService>(
        [](std::function<void()> f) { g_main_context_invoke(nullptr, runOnMain, new std::function<void()>(std::move(f))); });

    // Started now (not at first focus) so the focus changes since login are seen.
    if (vt::gnome::isGnomeWaylandSession()) {
        G().gnome = std::make_unique<vt::GnomeAppMonitor>();
        G().gnome->setOnChange([] { g_main_context_invoke(nullptr, onGnomeFocusChanged, nullptr); });
        G().gnome->start();
    }
}

GType vt_ibus_engine_type() { return vt_ibus_engine_get_type(); }

// IBus only sends FocusInId (which carries the client/app name) to engines constructed
// with has-focus-id = TRUE, a construct-only property the default factory path never
// sets — so engines are created here.
IBusEngine *vt_ibus_create_engine(IBusFactory *, const gchar *engineName, gpointer connection) {
    static guint counter = 0;
    gchar *path = g_strdup_printf("/org/freedesktop/IBus/Engine/VietTelex/%u", ++counter);
    GObject *obj = G_OBJECT(g_object_new(vt_ibus_engine_get_type(), "engine-name", engineName, "object-path", path,
                                         "connection", connection,
#if IBUS_CHECK_VERSION(1, 5, 28)
                                         "has-focus-id", TRUE,
#endif
                                         nullptr));
    g_free(path);
    return IBUS_ENGINE(obj);
}
