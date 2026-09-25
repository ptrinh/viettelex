// engine.cpp — IBus engine "viettelex" (Tiếng Việt (VietTelex)).
//
// Thin GObject adapter over viettelex::Session (linux/common). One IBusEngine object per
// input context. Preedit is sent in IBUS_ENGINE_PREEDIT_COMMIT mode, so ibus-daemon
// commits the visible word itself on focus-out / reset — nothing typed is swallowed.
// Builds against IBus 1.5.26 (Ubuntu 22.04) and newer; app identity (per-app Vi/En
// memory, [app_modes]) needs focus_in_id from IBus 1.5.28+, otherwise a single "default"
// app is used.

#include "engine.h"

#include "viettelex/app.h"
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
    std::string *appId;
    IBusPropList *props;
    IBusProperty *modeProp;
    gboolean password;
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
};
Globals &G() {
    static Globals g;
    return g;
}

const vt::Settings &settings() { return G().watcher->settings(); }

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
        ibus_text_append_attribute(t, IBUS_ATTR_TYPE_UNDERLINE, IBUS_ATTR_UNDERLINE_SINGLE, 0, len);
        ibus_engine_update_preedit_text_with_mode(e_, t, len, TRUE, IBUS_ENGINE_PREEDIT_COMMIT);
    }
    void commit(const std::string &s) override {
        ibus_engine_commit_text(e_, ibus_text_new_from_string(s.c_str()));
    }
    void deleteBeforeCursor(int n) override {
        if (n > 0) ibus_engine_delete_surrounding_text(e_, -n, guint(n));
    }
    bool textBeforeCursor(std::string &out) override {
        if (!(e_->client_capabilities & IBUS_CAP_SURROUNDING_TEXT)) return false;
        IBusText *text = nullptr;
        guint cursor = 0, anchor = 0;
        ibus_engine_get_surrounding_text(e_, &text, &cursor, &anchor);
        if (!text) return false;
        const gchar *s = ibus_text_get_text(text);
        if (!s) return false;
        const gchar *end = g_utf8_offset_to_pointer(s, glong(cursor));
        out.assign(s, size_t(end - s));
        return true;
    }

private:
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
    if (settings().perAppState) G().appState->set(*self->appId, vi);
    updateModeProp(self);
}

void refreshFieldFlags(VtIBusEngine *self) {
    IBusClient client(IBUS_ENGINE(self));
    bool surrounding = IBUS_ENGINE(self)->client_capabilities & IBUS_CAP_SURROUNDING_TEXT;
    auto policy = vt::resolveAppPolicy(*self->appId, settings(), surrounding);
    self->session->setPassthrough(self->password || policy.off, client);
    self->session->setDisplayMode(policy.mode, client);
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

// MARK: - vfuncs

gboolean processKeyEvent(IBusEngine *engine, guint keyval, guint keycode, guint state) {
    (void)keycode;  // keysym (after layout) is what we read — AZERTY/Dvorak work
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    try {
        vt::KeyEvent ev;
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
    loadAppState(self);
    refreshFieldFlags(self);
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
        *self->appId = vt::normalizeAppId(client ? client : "");
        focusCommon(self);
    } catch (...) {
    }
}
#endif

void focusOut(IBusEngine *engine) {
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
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

void setCapabilities(IBusEngine *engine, guint caps) {
    engine->client_capabilities = caps;
    try {
        refreshFieldFlags(reinterpret_cast<VtIBusEngine *>(engine));
    } catch (...) {
    }
}

void setContentType(IBusEngine *engine, guint purpose, guint hints) {
    (void)hints;
    auto *self = reinterpret_cast<VtIBusEngine *>(engine);
    self->password = purpose == IBUS_INPUT_PURPOSE_PASSWORD || purpose == IBUS_INPUT_PURPOSE_PIN;
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
    ec->set_content_type = setContentType;
    ec->property_activate = propertyActivate;
}

static void vt_ibus_engine_init(VtIBusEngine *self) {
    self->session = new vt::Session();
    self->appId = new std::string("default");
    self->password = FALSE;
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
