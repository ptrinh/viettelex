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

#include "engine.h"

#include "viettelex/app.h"
#include "viettelex/gnome.h"
#include "viettelex/gnome_monitor.h"
#include "viettelex/session.h"
#include "viettelex/settings.h"
#include "viettelex/watcher.h"

#include <glib-unix.h>

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
};
Globals &G() {
    static Globals g;
    return g;
}

const vt::Settings &settings() { return G().watcher->settings(); }

constexpr guint kBackSpaceKeycode = 14;  // evdev KEY_BACKSPACE (IBus keycodes are X keycode − 8)

class IBusClient final : public vt::InputContext {
public:
    explicit IBusClient(IBusEngine *e) : e_(e) {}
    void setPreedit(const std::string &s) override {
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
        ibus_text_append_attribute(t, IBUS_ATTR_TYPE_UNDERLINE,
                                   settings().preeditUnderline ? IBUS_ATTR_UNDERLINE_SINGLE
                                                               : IBUS_ATTR_UNDERLINE_NONE,
                                   0, len);
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
    bool hasSelection() override {
        IBusText *text = nullptr;
        guint cursor = 0, anchor = 0;
        if (!read(text, cursor, anchor)) return false;
        return anchor != cursor;
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
    IBusText *label = ibus_text_new_from_static_string(vi ? "Tiếng Việt" : "English");
    ibus_property_set_label(self->modeProp, label);
    ibus_property_set_symbol(self->modeProp, ibus_text_new_from_static_string(vi ? "VI" : "EN"));
    ibus_property_set_state(self->modeProp, vi ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED);
    ibus_engine_update_property(IBUS_ENGINE(self), self->modeProp);
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
    auto policy = vt::resolveAppPolicy(*self->appId, settings(), surrounding, field);
    self->rememberState = policy.rememberState;
    self->session->setPassthrough(self->password || policy.off || policy.passthrough, client);
    self->session->setDisplayMode(policy.mode, client);
    self->session->setSurroundingEdits(policy.allowSurroundingEdits);
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
    }
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
        IBusClient client(engine);
        return self->session->processKey(ev, client) ? TRUE : FALSE;
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
    ibus_engine_register_properties(IBUS_ENGINE(self), self->props);
    updateModeProp(self);
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
    self->session->applySettings(settings());
    self->session->onToggle = [self](bool vi) { onToggled(self, vi); };

    self->props = ibus_prop_list_new();
    g_object_ref_sink(self->props);
    self->modeProp = ibus_property_new("InputMode", PROP_TYPE_TOGGLE,
                                       ibus_text_new_from_static_string("Tiếng Việt"), "viettelex",
                                       ibus_text_new_from_static_string("Chuyển Việt/Anh (Ctrl+Space)"), TRUE,
                                       TRUE, PROP_STATE_CHECKED, nullptr);
    ibus_prop_list_append(self->props, self->modeProp);
    ibus_prop_list_append(self->props,
                          ibus_property_new("Settings", PROP_TYPE_NORMAL,
                                            ibus_text_new_from_static_string("Cài đặt…"), "preferences-system",
                                            ibus_text_new_from_static_string("Mở VietTelex Settings"), TRUE,
                                            TRUE, PROP_STATE_UNCHECKED, nullptr));
    G().engines.insert(self);
}

void vt_ibus_globals_init() {
    G().watcher = std::make_unique<vt::SettingsWatcher>();
    G().appState = std::make_unique<vt::AppStateStore>(vt::appStatePath());
    G().appState->load();
    if (G().watcher->fd() >= 0) g_unix_fd_add(G().watcher->fd(), G_IO_IN, onSettingsFd, nullptr);
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
