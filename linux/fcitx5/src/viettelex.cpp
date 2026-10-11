// viettelex.cpp — Fcitx5 input method addon "Tiếng Việt (VietTelex)".
//
// Thin adapter: every typing decision is in linux/common (viettelex::Session). This file
// maps Fcitx5 events onto it, keeps one Session per InputContext, remembers Vi/En per
// program, and reloads ~/.config/viettelex live (inotify on the Fcitx5 event loop).
// Compatible with Fcitx5 5.0.x (Ubuntu 22.04) through 5.1.x (24.04/26.04).
// On GNOME Wayland, Fcitx5 < 5.1.22 names every app "gnome-shell" (one shared context);
// the focused app is then read from gnome-shell over the session bus (GnomeAppMonitor).
// Text tools ("Công cụ…" in the status area + the optional Thêm dấu hotkey) run the helper
// viettelex-text-tool off the main thread (viettelex::TextToolRunner) and commit the result
// over the selection. Menu labels follow Settings::uiLanguage; the tray icon follows Việt/Anh.
// Caret suggestions (phép tính, chip số, sửa lỗi gõ, thêm dấu, ngày giờ — caret_hints.h) are
// computed by the same helper in `--serve` mode (viettelex::HintService) and shown as the
// input panel's aux text, which Fcitx5 UIs draw in the popup at the caret.

#include "viettelex/app.h"
#include "viettelex/caret_hints.h"
#include "viettelex/gnome.h"
#include "viettelex/gnome_monitor.h"
#include "viettelex/session.h"
#include "viettelex/settings.h"
#include "viettelex/text_tools.h"
#include "viettelex/watcher.h"

#include <fcitx-config/configuration.h>
#include <fcitx-config/iniparser.h>
#include <fcitx-config/option.h>
#include <fcitx-utils/event.h>
#include <fcitx-utils/eventdispatcher.h>
#include <fcitx-utils/i18n.h>
#include <fcitx-utils/key.h>
#include <fcitx-utils/log.h>
#include <fcitx-utils/misc.h>
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
#include <fcitx/menu.h>
#include <fcitx/statusarea.h>
#include <fcitx/text.h>
#include <fcitx/userinterfacemanager.h>

#include <array>
#include <cstdlib>
#include <chrono>
#include <functional>
#include <memory>
#include <string>

// Fcitx5 clipboard addon (fcitx5-modules-dev): PRIMARY selection without external tools.
#if defined(VT_HAVE_FCITX_CLIPBOARD)
#if __has_include(<clipboard_public.h>)
#include <clipboard_public.h>
#elif __has_include(<fcitx-module/clipboard/clipboard_public.h>)
#include <fcitx-module/clipboard/clipboard_public.h>
#else
#undef VT_HAVE_FCITX_CLIPBOARD
#endif
#endif

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
    using ReadPrimary = std::function<bool(std::string &)>;
    // readPrimary: PRIMARY selection for selectionAtCaret (the clipboard addon's cache);
    // empty = a short external read (wl-paste / xclip / xsel).
    explicit FcitxClient(fcitx::InputContext *ic, ReadPrimary readPrimary = {})
        : ic_(ic), readPrimary_(std::move(readPrimary)) {}

    void setPreedit(const std::string &s, bool misspelled) override {
        fcitx::Text text;
        if (!s.empty()) {
            // NoFlag = no underline: fcitx5-gtk (GTK2/3/4) and fcitx5-qt draw exactly these
            // formats; Wayland text-input-v3 clients (fcitx5 wayland_v2 frontend) draw their own.
            // Misspelled (opt-in): Fcitx5 text formats carry no colour or error style, so the
            // mark is an underline — plus italic when every preedit is underlined anyway.
            fcitx::TextFormatFlags fmt = g_preeditUnderline ? fcitx::TextFormatFlag::Underline
                                                            : fcitx::TextFormatFlag::NoFlag;
            if (misspelled) {
                fmt = fcitx::TextFormatFlag::Underline;
                if (g_preeditUnderline) fmt |= fcitx::TextFormatFlag::Italic;
            }
            text.append(s, fmt);
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
    // [experimental] no_underline = "forward-keys" (Chromium/Electron on KWin Wayland, the
    // "wayland" frontend, or on GNOME Wayland through the "ibus" frontend serving gnome-shell
    // — vt::hostOrdersForwardedKeys): real BackSpace key events, then the Session commits.
    // A real keycode (X 22 = evdev KEY_BACKSPACE): the "wayland" frontend then sends
    // zwp_input_method_context_v1.key (KWin → wl_keyboard, handled in request order with
    // commit_string) and adds the release itself; the "ibus" frontend sends ForwardKeyEvent
    // with code 22 - 8 = 14 and gnome-shell's forward_key adds 8 back (code 0 would become
    // evdev key 0); the release is ours to send there.
    void forwardBackspaces(int n) override {
        const fcitx::Key bs(FcitxKey_BackSpace, fcitx::KeyStates(), 22);
        const std::string frontend = ic_->frontend() ? ic_->frontend() : "";
        const bool autoRelease = frontend == "wayland" || frontend == "wayland_v2";
        for (int i = 0; i < n; ++i) {
            ic_->forwardKey(bs, false);
            if (!autoRelease) ic_->forwardKey(bs, true);
        }
    }
    // Aux text below the (client) preedit: the input panel popup at the caret. Never the
    // client preedit itself, so the app's text is not touched until Tab.
    void showHint(const std::string &label) override {
        ic_->inputPanel().setAuxDown(fcitx::Text(label));
        ic_->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
    }
    void hideHint() override {
        ic_->inputPanel().setAuxDown(fcitx::Text());
        ic_->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
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
    // Verify-before-delete (Session) asks before every in-place edit: copy only the tail.
    bool textBeforeCursorTail(size_t maxChars, std::string &out) override {
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
        size_t start = byte;
        for (size_t n = 0; start > 0 && n < maxChars; ++n) {
            --start;
            while (start > 0 && (static_cast<unsigned char>(text[start]) & 0xc0) == 0x80) --start;
        }
        out.assign(text, start, byte - start);
        return true;
    }
    // fcitx5-unikey (src/unikey-im.cpp) guards the same way: an invalid surrounding text
    // cannot rule a selection out.
    bool hasSelection() override {
        if (!ic_->capabilityFlags().test(fcitx::CapabilityFlag::SurroundingText)) return false;
        const auto &st = ic_->surroundingText();
        return !st.isValid() || !st.selectedText().empty();
    }
    // Before a reach-back only (Session): GTK3 clients (fcitx5-gtk3: Firefox, Chromium, GTK3
    // apps) send anchor == cursor even with text selected — then PRIMARY against the caret.
    bool selectionAtCaret() override {
        if (!ic_->capabilityFlags().test(fcitx::CapabilityFlag::SurroundingText)) return false;
        const auto &st = ic_->surroundingText();
        if (!st.isValid()) return true;
        return vt::selectionAtCaret(st.text(), st.cursor(), st.anchor(), [this](std::string &p) {
            if (readPrimary_) return readPrimary_(p);
            return vt::readPrimarySelection(p, 150);
        });
    }

private:
    fcitx::InputContext *ic_;
    ReadPrimary readPrimary_;
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
    // Text tool result that arrived while this context had no focus (the tray menu took
    // it): committed on the next activation if still fresh.
    std::string pendingResult;
    std::chrono::steady_clock::time_point pendingUntil;
};

class VietTelexEngine final : public fcitx::InputMethodEngineV2 {
public:
    explicit VietTelexEngine(fcitx::Instance *instance)
        : instance_(instance), appState_(vt::appStatePath()),
          factory_([this](fcitx::InputContext &ic) { return new VietTelexState(this, &ic); }),
          runner_([this](std::function<void()> f) { dispatcher_.schedule(std::move(f)); }),
          hints_([this](std::function<void()> f) { dispatcher_.schedule(std::move(f)); }) {
        appState_.load();
        dispatcher_.attach(&instance_->eventLoop());
        instance_->inputContextManager().registerProperty("viettelexState", &factory_);
        modeAction_.setShortText(tr("Tiếng Việt"));
        modeAction_.connect<fcitx::SimpleAction::Activated>([this](fcitx::InputContext *ic) {
            if (!ic) return;
            auto *st = state(ic);
            FcitxClient client(ic);
            st->session.setVietnamese(!st->session.vietnamese(), client);
            onToggled(st, st->session.vietnamese());
        });
        instance_->userInterfaceManager().registerAction("viettelex-mode", &modeAction_);
        // "Công cụ…" → the six text tools (like macOS: VietTelex menu → Công cụ…).
        for (int i = 0; i < vt::kTextToolCount; ++i) {
            vt::TextTool tool = vt::textToolAt(i);
            auto &a = toolActions_[size_t(i)];
            a.connect<fcitx::SimpleAction::Activated>([this, tool](fcitx::InputContext *ic) {
                try {
                    if (ic) runTextTool(ic, tool);
                } catch (...) {
                }
            });
            instance_->userInterfaceManager().registerAction(std::string("viettelex-tool-") + vt::textToolId(tool),
                                                             &a);
            toolsMenu_.addAction(&a);
        }
        toolsAction_.setMenu(&toolsMenu_);
        instance_->userInterfaceManager().registerAction("viettelex-tools", &toolsAction_);
        // "Cài đặt…" opens the settings app, like the IBus property and the macOS menu.
        settingsAction_.setIcon("preferences-system");
        settingsAction_.connect<fcitx::SimpleAction::Activated>(
            [](fcitx::InputContext *) { fcitx::startProcess({"viettelex-settings"}); });
        instance_->userInterfaceManager().registerAction("viettelex-settings", &settingsAction_);
        updateLabels();
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
        // Watch focus changes from the start: gnome-shell refuses our own
        // GetRunningApplications (GNOME ≥ 41), so the monitor learns the focused app only from
        // the portal's call after a focus change. Started lazily, on the first gnome-shell
        // context, it missed every change before — with GTK_IM_MODULE=fcitx (GTK apps on the
        // dbus frontend) that is the first Chrome/Electron field, already focused: app stayed
        // "gnome-shell" and no_underline never applied.
        if (gnomeSession_) ensureGnomeMonitor();
    }

    ~VietTelexEngine() override {
        if (gnome_) gnome_->stop();  // joins; no callback runs after this
    }

    const vt::Settings &settings() const { return watcher_.settings(); }

    // Session → helper (worker thread) → back here on the event loop.
    void submitHint(fcitx::InputContext *ic, const vt::HintRequest &r) {
        auto ref = ic->watch();
        uint64_t gen = r.gen;
        hints_.submit(r, [this, ref, gen](bool ok, const vt::CaretSuggestion &c) {
            try {
                auto *ic = ref.get();
                if (!ok || !ic || !ic->hasFocus() || instance_->inputMethod(ic) != "viettelex") return;
                FcitxClient client(ic);
                state(ic)->session.deliverHint(gen, c, client);
            } catch (...) {
            }
        });
    }
    bool hintsAvailable() const { return hints_.available(); }

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
            FcitxClient client(ic, primaryReader(ic));
            refreshFieldFlags(st, client);
            vt::KeyEvent ev = toVt(event);
            if (st->session.isAddTonesHotkey(ev)) {
                // Consumed even when nothing is selected: the chord belongs to this tool.
                runTextTool(ic, vt::TextTool::AddTones);
                event.filterAndAccept();
                return;
            }
            if (st->session.processKey(ev, client)) event.filterAndAccept();
            static const bool debug = std::getenv("VIETTELEX_DEBUG") != nullptr;
            if (debug) {
                std::string before;
                bool ok = client.textBeforeCursorTail(24, before);
                FCITX_INFO() << "viettelex key: sym=" << ev.keysym << " mode="
                             << int(st->session.displayMode())
                             << " distrusted=" << st->session.surroundingDistrusted()
                             << " before(" << ok << ")=[" << before << "]";
            }
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
            updateToolsAction(ic);
            updateAction(st);
            commitPendingResult(st);
        } catch (...) {
        }
    }

    void deactivate(const fcitx::InputMethodEntry &entry, fcitx::InputContextEvent &event) override {
        reset(entry, event);
    }

    void reset(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
        try {
            auto *ic = event.inputContext();
            auto *st = state(ic);
            FcitxClient client(ic);
            // The client preedit is ALREADY committed — committing again types the word twice:
            // - FocusOut: by Fcitx5, or by the client when it has ClientUnfocusCommit;
            // - Reset from a ClientUnfocusCommit client (fcitx5-gtk2/3/4, fcitx5-qt): its reset
            //   commits the preedit before sending Reset — a click in Ptyxis/VTE gave "thửthử".
            // Any other reset (IM switch, Wayland / IBus-frontend clients, preedit shown in the
            // panel): commit it ourselves so it is not lost.
            const auto &caps = ic->capabilityFlags();
            bool clientCommits = caps.test(fcitx::CapabilityFlag::ClientUnfocusCommit) &&
                                 caps.test(fcitx::CapabilityFlag::Preedit);
            bool alreadyCommitted = event.type() == fcitx::EventType::InputContextFocusOut ||
                                    (event.type() == fcitx::EventType::InputContextReset && clientCommits);
            st->session.finish(client, !alreadyCommitted);
        } catch (...) {
        }
    }

    std::string subMode(const fcitx::InputMethodEntry &, fcitx::InputContext &ic) override {
        return tr(state(&ic)->session.vietnamese() ? "Tiếng Việt" : "English");
    }

    // Tray / panel icon follows Việt/Anh like the macOS menu bar: Vᴛ or E
    // (linux/packaging/data/icons — Scripts/make_linux_status_icons.swift).
    std::string subModeIconImpl(const fcitx::InputMethodEntry &, fcitx::InputContext &ic) override {
        return state(&ic)->session.vietnamese() ? "viettelex" : "viettelex-off";
    }
    std::string subModeLabelImpl(const fcitx::InputMethodEntry &, fcitx::InputContext &ic) override {
        return state(&ic)->session.vietnamese() ? "Vᴛ" : "E";
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
#if defined(VT_HAVE_FCITX_CLIPBOARD)
    // Declared before its first use: the loader's return type is deduced (auto).
    FCITX_ADDON_DEPENDENCY_LOADER(clipboard, instance_->addonManager());
#endif

    // PRIMARY from the clipboard addon's in-process cache (no IPC); empty = no addon. The
    // cache keeps the last text after the app drops the selection (GTK3 entry: select, then
    // End) — so a cached hit is confirmed with a short external read when a tool exists.
    FcitxClient::ReadPrimary primaryReader(fcitx::InputContext *ic) {
#if defined(VT_HAVE_FCITX_CLIPBOARD)
        return [this, ic](std::string &out) {
            auto *clip = clipboard();
            if (!clip) return vt::readPrimarySelection(out, 150);
            out = clip->call<fcitx::IClipboard::primary>(ic);
            if (out.empty()) return false;
            std::string live;
            if (vt::readPrimarySelection(live, 150) || vt::primarySelectionToolAvailable()) out = live;
            return !out.empty();
        };
#else
        (void)ic;
        return {};
#endif
    }

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
        ensureGnomeMonitor();
        return gnome_->resolve(clientId);
    }

    void ensureGnomeMonitor() {
        if (gnome_) return;
        gnome_ = std::make_unique<vt::GnomeAppMonitor>();
        gnome_->setOnChange([this] { dispatcher_.schedule([this] { onGnomeFocusChanged(); }); });
        gnome_->start();
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
        // "ibus" frontend: gnome-shell's own context (GNOME Wayland) vs any other IBus client.
        field.host = vt::fcitxClientHost(st->ic->frontend() ? st->ic->frontend() : "",
                                         caps.test(fcitx::CapabilityFlag::KeyEventOrderFix), st->ic->program(),
                                         gnomeSession_);
        // gnome-shell turns our forwarded keys into mutter events — dropped by mutter 50.
        if (field.host == vt::ClientHost::FcitxGnomeWayland)
            field.forwardedKeysDropped = !vt::gnome::mutterDeliversForwardedKeys(gnome_ ? gnome_->shellMajor() : 0);
        auto policy = vt::resolveAppPolicy(st->appId, settings(), surrounding, field);
        st->rememberState = policy.rememberState;
        bool password = caps.test(fcitx::CapabilityFlag::Password);
        st->session.setPassthrough(password || policy.off || policy.passthrough, client);
        st->session.setDisplayMode(policy.mode, client);
        st->session.setDeleteWithKeys(policy.deleteWithKeys);
        st->session.setSurroundingEdits(policy.allowSurroundingEdits);
        // VIETTELEX_DEBUG=1 in Fcitx5's environment: why a field got its mode (journal / stderr).
        static const bool debug = std::getenv("VIETTELEX_DEBUG") != nullptr;
        if (debug) {
            FCITX_INFO() << "viettelex: program=" << st->ic->program() << " app=" << st->appId
                         << " frontend=" << (st->ic->frontend() ? st->ic->frontend() : "")
                         << " host=" << int(field.host) << " surroundingCap="
                         << caps.test(fcitx::CapabilityFlag::SurroundingText)
                         << " surroundingValid=" << st->ic->surroundingText().isValid()
                         << " shell=" << (gnome_ ? gnome_->shellMajor() : 0)
                         << " keysDropped=" << field.forwardedKeysDropped << " terminal=" << field.terminal << " url=" << field.urlOrEmail
                         << " mode=" << int(policy.mode) << " deleteWithKeys=" << policy.deleteWithKeys;
        }
    }

    void applySettingsToAll() {
        const auto &s = watcher_.reload();
        syncConfigFromSettings();
        updateLabels();
        instance_->inputContextManager().foreach([this, &s](fcitx::InputContext *ic) {
            auto *st = state(ic);
            st->session.applySettings(s);
            if (ic->hasFocus() && instance_->inputMethod(ic) == "viettelex") {
                updateToolsAction(ic);
                updateAction(st);
                ic->updateUserInterface(fcitx::UserInterfaceComponent::StatusArea);
            }
            return true;
        });
    }

    bool english() const { return vt::isEnglishUi(settings().uiLanguage); }
    std::string tr(const char *vi) const { return vt::uiText(vi, english()); }

    void updateLabels() {
        toolsAction_.setShortText(tr("Công cụ…"));
        toolsAction_.setLongText(tr("Công cụ văn bản cho chữ đang bôi đen"));
        for (int i = 0; i < vt::kTextToolCount; ++i)
            toolActions_[size_t(i)].setShortText(vt::textToolLabel(vt::textToolAt(i), english()));
        settingsAction_.setShortText(tr("Cài đặt…"));
        settingsAction_.setLongText(tr("Mở VietTelex Settings"));
    }

    // "Hiện công cụ văn bản trong menu" (and only when the helper is installed); "Cài đặt…"
    // always comes last.
    void updateToolsAction(fcitx::InputContext *ic) {
        auto &area = ic->statusArea();
        area.removeAction(&toolsAction_);
        area.removeAction(&settingsAction_);
        if (settings().textToolsMenu && vt::textToolAvailable())
            area.addAction(fcitx::StatusGroup::InputMethod, &toolsAction_);
        area.addAction(fcitx::StatusGroup::InputMethod, &settingsAction_);
    }

    // MARK: text tools (Công cụ…) — see linux/common/include/viettelex/text_tools.h

    void runTextTool(fcitx::InputContext *ic, vt::TextTool tool) {
        auto *st = state(ic);
        ensureAppState(st);
        auto caps = ic->capabilityFlags();
        // Password / sensitive fields: never read them. Terminals: typing over a selection
        // replaces nothing there — the result would land at the prompt.
        if (caps.test(fcitx::CapabilityFlag::Password) || caps.test(fcitx::CapabilityFlag::Sensitive) ||
            caps.test(fcitx::CapabilityFlag::Terminal) || vt::isTerminalApp(st->appId) || runner_.busy())
            return;
        FcitxClient client(ic);
        st->session.finish(client, true);
        vt::TextToolRunner::Source source;
        const auto &sur = ic->surroundingText();
        std::string primary;
#if defined(VT_HAVE_FCITX_CLIPBOARD)
        if (auto *clip = clipboard()) primary = clip->call<fcitx::IClipboard::primary>(ic);
#endif
        if (caps.test(fcitx::CapabilityFlag::SurroundingText) && sur.isValid()) {
            // The app reports its text: its selection is authoritative.
            std::string sel = sur.selectedText();
            if (!sel.empty()) {
                source = [sel](std::string &out) {
                    out = sel;
                    return true;
                };
            } else {
                // No selection reported — GTK3 never reports one (no anchor): PRIMARY, but
                // only when it touches the caret, else nothing to do.
                source = [text = sur.text(), cursor = sur.cursor(), primary](std::string &out) {
                    std::string p = primary;
                    if (p.empty() && !vt::readPrimarySelection(p)) return false;
                    if (!vt::primaryAdjacentToCursor(text, cursor, p)) return false;
                    out = std::move(p);
                    return true;
                };
            }
        } else if (!primary.empty()) {
            source = [primary](std::string &out) {
                out = primary;
                return true;
            };
        } else {
            source = [](std::string &out) { return vt::readPrimarySelection(out); };
        }
        auto ref = ic->watch();
        runner_.start(tool, std::move(source),
                      [this, ref](bool changed, const std::string &input, const std::string &result) {
                          try {
                              onToolResult(ref.get(), changed, input, result);
                          } catch (...) {
                          }
                      });
    }

    void onToolResult(fcitx::InputContext *ic, bool changed, const std::string &input, const std::string &result) {
        if (!ic || !changed) return;
        auto *st = state(ic);
        // The selection changed while the helper ran: never overwrite something else.
        const auto &sur = ic->surroundingText();
        if (ic->capabilityFlags().test(fcitx::CapabilityFlag::SurroundingText) && sur.isValid() &&
            !sur.selectedText().empty() && sur.selectedText() != input)
            return;
        if (ic->hasFocus()) {
            commitToolResult(st, result);
        } else {
            st->pendingResult = result;
            st->pendingUntil = std::chrono::steady_clock::now() + std::chrono::seconds(3);
        }
    }

    void commitToolResult(VietTelexState *st, const std::string &result) {
        FcitxClient client(st->ic);
        st->session.finish(client, true);
        // Typing over the selection replaces it (GTK, Qt, Chromium, LibreOffice…).
        st->ic->commitString(result);
        st->session.focusIn();  // the text around the caret changed: forget the old word context
    }

    void commitPendingResult(VietTelexState *st) {
        if (st->pendingResult.empty()) return;
        std::string r;
        r.swap(st->pendingResult);
        if (std::chrono::steady_clock::now() <= st->pendingUntil) commitToolResult(st, r);
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
        modeAction_.setShortText(tr(vi ? "Tiếng Việt" : "English"));
        modeAction_.setLongText(tr(vi ? "Đang gõ tiếng Việt — bấm để chuyển sang English"
                                      : "Đang gõ English — bấm để chuyển sang tiếng Việt"));
        modeAction_.setIcon(vi ? "viettelex" : "viettelex-off");
        modeAction_.update(st->ic);
    }

    fcitx::Instance *instance_;
    vt::SettingsWatcher watcher_;
    vt::AppStateStore appState_;
    fcitx::FactoryFor<VietTelexState> factory_;
    fcitx::SimpleAction modeAction_;
    fcitx::SimpleAction toolsAction_;
    fcitx::Menu toolsMenu_;
    fcitx::SimpleAction settingsAction_;
    std::array<fcitx::SimpleAction, vt::kTextToolCount> toolActions_;
    std::unique_ptr<fcitx::EventSourceIO> ioEvent_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> hotkeyWatcher_;
    VietTelexConfig config_;
    bool gnomeSession_ = false;
    fcitx::EventDispatcher dispatcher_;               // declared before gnome_: outlives it
    std::unique_ptr<vt::GnomeAppMonitor> gnome_;
    vt::TextToolRunner runner_;                       // after dispatcher_: destroyed before it
    vt::HintService hints_;                           // after dispatcher_: destroyed before it
};

VietTelexState::VietTelexState(VietTelexEngine *engine, fcitx::InputContext *ic_) : ic(ic_) {
    session.applySettings(engine->settings());
    session.onToggle = [engine, this](bool vi) { engine->onToggled(this, vi); };
    if (engine->hintsAvailable())
        session.setHintSink([engine, this](const vt::HintRequest &r) { engine->submitHint(ic, r); });
}

class VietTelexFactory final : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new VietTelexEngine(manager->instance());
    }
};

}  // namespace

FCITX_ADDON_FACTORY(VietTelexFactory);
