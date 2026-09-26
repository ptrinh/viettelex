// viettelex.cpp — Fcitx5 input method addon "Tiếng Việt (VietTelex)".
//
// Thin adapter: every typing decision is in linux/common (viettelex::Session). This file
// maps Fcitx5 events onto it, keeps one Session per InputContext, remembers Vi/En per
// program, and reloads ~/.config/viettelex live (inotify on the Fcitx5 event loop).
// Compatible with Fcitx5 5.0.x (Ubuntu 22.04) through 5.1.x (24.04/26.04).
// On GNOME Wayland, Fcitx5 < 5.1.22 names every app "gnome-shell" (one shared context);
// the focused app is then read from gnome-shell over the session bus (GnomeAppMonitor).

#include "viettelex/app.h"
#include "viettelex/gnome.h"
#include "viettelex/gnome_monitor.h"
#include "viettelex/session.h"
#include "viettelex/settings.h"
#include "viettelex/watcher.h"

#include <fcitx-config/configuration.h>
#include <fcitx-config/iniparser.h>
#include <fcitx-config/option.h>
#include <fcitx-utils/event.h>
#include <fcitx-utils/eventdispatcher.h>
#include <fcitx-utils/i18n.h>
#include <fcitx-utils/key.h>
#include <fcitx-utils/log.h>
#include <fcitx/action.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/statusarea.h>
#include <fcitx/text.h>
#include <fcitx/userinterfacemanager.h>

#include <memory>
#include <string>

namespace {

namespace vt = viettelex;

FCITX_CONFIGURATION(
    VietTelexConfig,
    fcitx::Option<bool> vni{this, "VNI", "Kiểu gõ VNI (thay cho Telex)", false};
    fcitx::Option<bool> preeditUnderline{this, "PreeditUnderline", "Gạch chân chữ đang gõ", false};
    fcitx::Option<bool> noUnderline{this, "NoUnderline",
                                    "Sửa trực tiếp quanh con trỏ (surrounding; tự về preedit ở app không hỗ trợ)",
                                    false};
    fcitx::Option<bool> spellCheck{this, "SpellCheck", "Kiểm tra chính tả khi gõ", true};
    fcitx::Option<bool> autoRestore{this, "AutoRestore", "Tự khôi phục từ không phải tiếng Việt", true};
    fcitx::Option<bool> freeMarking{this, "FreeMarking", "Bỏ dấu tự do", true};
    fcitx::Option<bool> modernTone{this, "ModernTone", "Kiểu dấu mới (hoà, khoẻ, thuý)", false};
    fcitx::Option<bool> quickTelex{this, "QuickTelex", "Gõ nhanh (cc→ch, nn→ng…)", false};
    fcitx::Option<bool> perAppState{this, "PerAppState", "Nhớ Việt/Anh theo từng ứng dụng", true};
    fcitx::ExternalOption advanced{this, "Advanced", "Cài đặt nâng cao…", "viettelex-settings"};);

class VietTelexEngine;

// Settings::preeditUnderline, refreshed with every settings load (one Fcitx5 process).
bool g_preeditUnderline = false;

// fcitx::InputContext → viettelex::InputContext
class FcitxClient final : public vt::InputContext {
public:
    explicit FcitxClient(fcitx::InputContext *ic) : ic_(ic) {}

    void setPreedit(const std::string &s) override {
        fcitx::Text text;
        if (!s.empty()) {
            // NoFlag = no underline: fcitx5-gtk (GTK2/3/4) and fcitx5-qt draw exactly these
            // formats; Wayland text-input-v3 clients (fcitx5 wayland_v2 frontend) draw their own.
            text.append(s, g_preeditUnderline ? fcitx::TextFormatFlag::Underline : fcitx::TextFormatFlag::NoFlag);
            text.setCursor(int(s.size()));
        }
        if (ic_->capabilityFlags().test(fcitx::CapabilityFlag::Preedit)) {
            ic_->inputPanel().setClientPreedit(text);
        } else {
            ic_->inputPanel().setPreedit(text);  // client can't draw preedit: show in the panel
        }
        ic_->updatePreedit();
        ic_->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
    }
    void commit(const std::string &s) override { ic_->commitString(s); }
    void deleteBeforeCursor(int n) override {
        if (n > 0) ic_->deleteSurroundingText(-n, unsigned(n));
    }
    // Direct (terminals on a D-Bus client with KeyEventOrderFix: fcitx5-gtk2/3, fcitx5-qt; see
    // vt::ClientHost). BackSpace AND the new text are forwarded keys: the client queues them
    // (gdk_event_put / QWindowSystemInterface) and commits forwarded printable keys through
    // its fallback IM context, so they stay in order. commitString would be applied at once,
    // ahead of the queued BackSpaces. Forwarded keys never pass through engines again.
    void directReplace(int backspaces, const std::string &s) override {
        const fcitx::Key bs(FcitxKey_BackSpace);
        for (int i = 0; i < backspaces; ++i) {
            ic_->forwardKey(bs, false);
            ic_->forwardKey(bs, true);
        }
        for (size_t i = 0; i < s.size();) {
            unsigned char b = static_cast<unsigned char>(s[i]);
            size_t n = b < 0x80 ? 1 : (b >> 5) == 6 ? 2 : (b >> 4) == 14 ? 3 : 4;
            uint32_t cp = n == 1 ? b : n == 2 ? (b & 0x1f) : n == 3 ? (b & 0x0f) : (b & 0x07);
            for (size_t k = 1; k < n && i + k < s.size(); ++k) cp = (cp << 6) | (s[i + k] & 0x3f);
            i += n;
            const fcitx::Key key(fcitx::Key::keySymFromUnicode(cp));
            ic_->forwardKey(key, false);
            ic_->forwardKey(key, true);
        }
    }
    bool textBeforeCursor(std::string &out) override {
        if (!ic_->capabilityFlags().test(fcitx::CapabilityFlag::SurroundingText)) return false;
        const auto &st = ic_->surroundingText();
        if (!st.isValid()) return false;
        const std::string &text = st.text();
        unsigned cursor = st.cursor();  // in characters
        size_t byte = 0;
        for (unsigned c = 0; c < cursor && byte < text.size(); ++c) {
            ++byte;
            while (byte < text.size() && (static_cast<unsigned char>(text[byte]) & 0xc0) == 0x80) ++byte;
        }
        out = text.substr(0, byte);
        return true;
    }
    // fcitx5-unikey (src/unikey-im.cpp) guards the same way: an invalid surrounding text
    // cannot rule a selection out.
    bool hasSelection() override {
        if (!ic_->capabilityFlags().test(fcitx::CapabilityFlag::SurroundingText)) return false;
        const auto &st = ic_->surroundingText();
        return !st.isValid() || !st.selectedText().empty();
    }

private:
    fcitx::InputContext *ic_;
};

class VietTelexState final : public fcitx::InputContextProperty {
public:
    VietTelexState(VietTelexEngine *engine, fcitx::InputContext *ic);
    vt::Session session;
    fcitx::InputContext *ic;
    std::string appId;     // effective id (the GNOME focused app for "gnome-shell")
    std::string clientId;  // ic->program()
    bool stateLoaded = false;
    bool rememberState = true;  // AppPolicy.rememberState of the current field
};

class VietTelexEngine final : public fcitx::InputMethodEngine {
public:
    explicit VietTelexEngine(fcitx::Instance *instance)
        : instance_(instance), appState_(vt::appStatePath()),
          factory_([this](fcitx::InputContext &ic) { return new VietTelexState(this, &ic); }) {
        appState_.load();
        instance_->inputContextManager().registerProperty("viettelexState", &factory_);
        modeAction_.setShortText("Tiếng Việt");
        modeAction_.connect<fcitx::SimpleAction::Activated>([this](fcitx::InputContext *ic) {
            if (!ic) return;
            auto *st = state(ic);
            FcitxClient client(ic);
            st->session.setVietnamese(!st->session.vietnamese(), client);
            onToggled(st, st->session.vietnamese());
        });
        instance_->userInterfaceManager().registerAction("viettelex-mode", &modeAction_);
        if (watcher_.fd() >= 0) {
            ioEvent_ = instance_->eventLoop().addIOEvent(
                watcher_.fd(), fcitx::IOEventFlag::In,
                [this](fcitx::EventSourceIO *, int, fcitx::IOEventFlags) {
                    try {
                        if (watcher_.drain()) applySettingsToAll();
                    } catch (...) {
                    }
                    return true;
                });
        }
        // Our Vi/En hotkey (Ctrl+Space) is also Fcitx5's default trigger key, which is handled
        // before engines see keys. While VietTelex is the active IM, catch it first so it
        // toggles Việt/Anh inside VietTelex (remembered per app) instead of leaving the IM.
        hotkeyWatcher_ = instance_->watchEvent(
            fcitx::EventType::InputContextKeyEvent, fcitx::EventWatcherPhase::PreInputMethod,
            [this](fcitx::Event &e) {
                try {
                    auto &ke = static_cast<fcitx::KeyEvent &>(e);
                    auto *ic = ke.inputContext();
                    if (ke.isRelease() || instance_->inputMethod(ic) != "viettelex") return;
                    auto *st = state(ic);
                    vt::KeyEvent ev = toVt(ke);
                    if (!st->session.isToggleHotkey(ev)) return;
                    ensureAppState(st);
                    FcitxClient client(ic);
                    st->session.processKey(ev, client);
                    ke.filterAndAccept();
                } catch (...) {
                }
            });
        syncConfigFromSettings();
        gnomeSession_ = vt::gnome::isGnomeWaylandSession();
    }

    ~VietTelexEngine() override {
        if (gnome_) gnome_->stop();  // joins; no callback runs after this
    }

    const vt::Settings &settings() const { return watcher_.settings(); }

    static vt::KeyEvent toVt(const fcitx::KeyEvent &event) {
        const fcitx::Key &key = event.key();
        vt::KeyEvent ev;
        ev.keysym = uint32_t(key.sym());
        ev.unicode = fcitx::Key::keySymToUnicode(key.sym());
        ev.release = event.isRelease();
        auto states = key.states();
        if (states.test(fcitx::KeyState::Shift)) ev.mods |= vt::VT_MOD_SHIFT;
        if (states.test(fcitx::KeyState::Ctrl)) ev.mods |= vt::VT_MOD_CTRL;
        if (states.test(fcitx::KeyState::Alt)) ev.mods |= vt::VT_MOD_ALT;
        if (states.test(fcitx::KeyState::Super) || states.test(fcitx::KeyState::Super2))
            ev.mods |= vt::VT_MOD_SUPER;
        return ev;
    }

    // MARK: InputMethodEngine

    void keyEvent(const fcitx::InputMethodEntry &, fcitx::KeyEvent &event) override {
        try {
            auto *ic = event.inputContext();
            auto *st = state(ic);
            ensureAppState(st);
            FcitxClient client(ic);
            refreshFieldFlags(st, client);
            if (st->session.processKey(toVt(event), client)) event.filterAndAccept();
        } catch (...) {
            // never take fcitx5 down with us: the key simply reaches the app
        }
    }

    void activate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
        try {
            auto *ic = event.inputContext();
            if (watcher_.changedOnDisk()) applySettingsToAll();  // inotify fallback
            auto *st = state(ic);
            st->stateLoaded = false;
            ensureAppState(st);
            st->session.focusIn();
            ic->statusArea().addAction(fcitx::StatusGroup::InputMethod, &modeAction_);
            updateAction(st);
        } catch (...) {
        }
    }

    void deactivate(const fcitx::InputMethodEntry &entry, fcitx::InputContextEvent &event) override {
        reset(entry, event);
    }

    void reset(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
        try {
            auto *st = state(event.inputContext());
            FcitxClient client(event.inputContext());
            // FocusOut: Fcitx5 (or the client, with ClientUnfocusCommit) has ALREADY committed
            // the client preedit — committing again would type the word twice. Any other
            // reset (click / cursor move / IM switch): commit it ourselves so it is not lost.
            bool alreadyCommitted = event.type() == fcitx::EventType::InputContextFocusOut;
            st->session.finish(client, !alreadyCommitted);
        } catch (...) {
        }
    }

    std::string subMode(const fcitx::InputMethodEntry &, fcitx::InputContext &ic) override {
        return state(&ic)->session.vietnamese() ? "Tiếng Việt" : "English";
    }

    // MARK: config (Fcitx5 config UI → config.toml; the watcher then applies it)

    const fcitx::Configuration *getConfig() const override { return &config_; }

    void setConfig(const fcitx::RawConfig &raw) override {
        config_.load(raw, true);
        std::string text;
        vt::readFile(vt::configPath(), text);
        auto b = [](bool v) { return std::string(v ? "true" : "false"); };
        text = vt::setConfigValue(text, "typing", "input_method", *config_.vni ? "\"vni\"" : "\"telex\"");
        text = vt::setConfigValue(text, "typing", "spell_check", b(*config_.spellCheck));
        text = vt::setConfigValue(text, "typing", "auto_restore", b(*config_.autoRestore));
        text = vt::setConfigValue(text, "typing", "free_marking", b(*config_.freeMarking));
        text = vt::setConfigValue(text, "typing", "modern_tone", b(*config_.modernTone));
        text = vt::setConfigValue(text, "typing", "quick_telex", b(*config_.quickTelex));
        text = vt::setConfigValue(text, "general", "display_mode",
                                  *config_.noUnderline ? "\"surrounding\"" : "\"preedit\"");
        text = vt::setConfigValue(text, "general", "per_app_state", b(*config_.perAppState));
        text = vt::setConfigValue(text, "general", "preedit_underline", b(*config_.preeditUnderline));
        vt::writeFileAtomic(vt::configPath(), text);
        applySettingsToAll();  // don't wait for inotify
    }

    void reloadConfig() override { applySettingsToAll(); }

    VietTelexState *state(fcitx::InputContext *ic) { return ic->propertyFor(&factory_); }

    void onToggled(VietTelexState *st, bool vi) {
        if (settings().perAppState && st->rememberState) appState_.set(st->appId, vi);
        updateAction(st);
        st->ic->updateUserInterface(fcitx::UserInterfaceComponent::StatusArea);
    }

private:
    void ensureAppState(VietTelexState *st) {
        if (st->stateLoaded) return;
        st->stateLoaded = true;
        st->clientId = vt::normalizeAppId(st->ic->program());
        st->appId = effectiveAppId(st->clientId);
        const auto &s = settings();
        FcitxClient client(st->ic);
        bool vi = s.perAppState ? appState_.vietnamese(st->appId, s.defaultVietnamese) : s.defaultVietnamese;
        st->session.setVietnamese(vi, client);
        refreshFieldFlags(st, client);
    }

    // GNOME Wayland + a shared "gnome-shell" context (Fcitx5 < 5.1.22 — newer ones name
    // the app themselves): started on first sight, then signal-driven.
    std::string effectiveAppId(const std::string &clientId) {
        if (!gnomeSession_ || !vt::gnome::isSharedShellClientId(clientId)) return clientId;
        if (!gnome_) {
            dispatcher_.attach(&instance_->eventLoop());
            gnome_ = std::make_unique<vt::GnomeAppMonitor>();
            gnome_->setOnChange([this] { dispatcher_.schedule([this] { onGnomeFocusChanged(); }); });
            gnome_->start();
        }
        return gnome_->resolve(clientId);
    }

    void onGnomeFocusChanged() {
        try {
            instance_->inputContextManager().foreach([this](fcitx::InputContext *ic) {
                if (!ic->hasFocus() || instance_->inputMethod(ic) != "viettelex") return true;
                auto *st = state(ic);
                if (!st->stateLoaded || !vt::gnome::isSharedShellClientId(st->clientId)) return true;
                std::string id = gnome_->resolve(st->clientId);
                if (id == st->appId) return true;
                st->appId = id;
                FcitxClient client(ic);
                // Vi/En memory of the new app; never flipped under a word being typed.
                if (!st->session.composing()) {
                    const auto &s = settings();
                    st->session.setVietnamese(
                        s.perAppState ? appState_.vietnamese(id, s.defaultVietnamese) : s.defaultVietnamese, client);
                }
                refreshFieldFlags(st, client);
                updateAction(st);
                ic->updateUserInterface(fcitx::UserInterfaceComponent::StatusArea);
                return true;
            });
        } catch (...) {
        }
    }

    // Password fields, [app_modes] and surrounding capability can change per focus.
    void refreshFieldFlags(VietTelexState *st, FcitxClient &client) {
        auto caps = st->ic->capabilityFlags();
        // Proven = advertised AND the client actually sent a valid text for this field.
        bool surrounding = caps.test(fcitx::CapabilityFlag::SurroundingText) && st->ic->surroundingText().isValid();
        vt::FieldHints field;
        field.terminal = caps.test(fcitx::CapabilityFlag::Terminal);
        field.urlOrEmail = caps.test(fcitx::CapabilityFlag::Url) || caps.test(fcitx::CapabilityFlag::Email);
        field.numeric = caps.test(fcitx::CapabilityFlag::Digit) || caps.test(fcitx::CapabilityFlag::Number) ||
                        caps.test(fcitx::CapabilityFlag::Dialable);
        field.sensitive = caps.test(fcitx::CapabilityFlag::Sensitive);
        field.host = vt::fcitxClientHost(st->ic->frontend() ? st->ic->frontend() : "", caps.test(fcitx::CapabilityFlag::KeyEventOrderFix));
        auto policy = vt::resolveAppPolicy(st->appId, settings(), surrounding, field);
        st->rememberState = policy.rememberState;
        bool password = caps.test(fcitx::CapabilityFlag::Password);
        st->session.setPassthrough(password || policy.off || policy.passthrough, client);
        st->session.setDisplayMode(policy.mode, client);
        st->session.setSurroundingEdits(policy.allowSurroundingEdits);
    }

    void applySettingsToAll() {
        const auto &s = watcher_.reload();
        syncConfigFromSettings();
        instance_->inputContextManager().foreach([this, &s](fcitx::InputContext *ic) {
            auto *st = state(ic);
            st->session.applySettings(s);
            return true;
        });
    }

    void syncConfigFromSettings() {
        const auto &s = settings();
        config_.vni.setValue(s.vni);
        config_.noUnderline.setValue(s.displayMode == vt::DisplayMode::Surrounding);
        config_.preeditUnderline.setValue(s.preeditUnderline);
        g_preeditUnderline = s.preeditUnderline;
        config_.spellCheck.setValue(s.spellCheck);
        config_.autoRestore.setValue(s.autoRestore);
        config_.freeMarking.setValue(s.freeMarking);
        config_.modernTone.setValue(s.modernTone);
        config_.quickTelex.setValue(s.quickTelex);
        config_.perAppState.setValue(s.perAppState);
    }

    void updateAction(VietTelexState *st) {
        bool vi = st->session.vietnamese();
        modeAction_.setShortText(vi ? "Tiếng Việt" : "English");
        modeAction_.setLongText(vi ? "Đang gõ tiếng Việt — bấm để chuyển sang English"
                                   : "Đang gõ English — bấm để chuyển sang tiếng Việt");
        modeAction_.setIcon(vi ? "viettelex" : "viettelex-off");
        modeAction_.update(st->ic);
    }

    fcitx::Instance *instance_;
    vt::SettingsWatcher watcher_;
    vt::AppStateStore appState_;
    fcitx::FactoryFor<VietTelexState> factory_;
    fcitx::SimpleAction modeAction_;
    std::unique_ptr<fcitx::EventSourceIO> ioEvent_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> hotkeyWatcher_;
    VietTelexConfig config_;
    bool gnomeSession_ = false;
    fcitx::EventDispatcher dispatcher_;               // declared before gnome_: outlives it
    std::unique_ptr<vt::GnomeAppMonitor> gnome_;
};

VietTelexState::VietTelexState(VietTelexEngine *engine, fcitx::InputContext *ic_) : ic(ic_) {
    session.applySettings(engine->settings());
    session.onToggle = [engine, this](bool vi) { engine->onToggled(this, vi); };
}

class VietTelexFactory final : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new VietTelexEngine(manager->instance());
    }
};

}  // namespace

FCITX_ADDON_FACTORY(VietTelexFactory);
