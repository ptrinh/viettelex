// dead_keys.h — dead keys and the Compose key while VietTelex is the input method (#161).
//
// A layout's dead keys (U.S. International: ' " ` ~ ^; German/French ´ ¨; AltGr dead keys)
// arrive as dead_* keysyms. Composing them is the job of the framework's own keyboard
// engine (Fcitx5 keyboard-*, ibus-engine-simple) — which does not run while VietTelex is the
// active input method. Forwarding the dead key and then eating the next letter (the Telex
// engine's) lost or garbled the accent, so the Session composes them itself, with ONE
// invariant per sequence: exactly one output, never zero, never two —
//   dead + composable letter  → the composed character   (´ e → é, ¨ u → ü, ~ n → ñ)
//   dead + Space / dead twice → the accent on its own     (´ Space → ' like the locale's Compose)
//   dead + anything else      → the accent, then the key  (´ x → 'x)
//   Esc / BackSpace / focus change / Ctrl-Alt-Super chord → the pending sequence is dropped.
// Rules come from the user's locale Compose table (libxkbcommon, loaded at run time: same
// table Fcitx5's keyboard engine uses, incl. ~/.XCompose and Multi_key sequences); without
// it a built-in table covers the common Latin dead keys.
// Idle cost for ordinary keys: one range check (wants()).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

struct xkb_compose_state;

namespace viettelex {

class DeadKeys {
public:
    enum class Step {
        Pass,           // not ours: process the key as usual
        Consumed,       // part of a pending sequence (or cancelled): the app must not see it
        Commit,         // `out` is the result; the key itself is done
        CommitThenKey,  // `out` (the pending accent) first, then process the key as usual
    };

    DeadKeys() = default;
    ~DeadKeys();
    DeadKeys(const DeadKeys &) = delete;
    DeadKeys &operator=(const DeadKeys &) = delete;

    // dead_grave … dead_* (0xfe50–0xfe93) or Multi_key.
    static bool startsSequence(uint32_t keysym) {
        return (keysym >= 0xfe50 && keysym <= 0xfe93) || keysym == 0xff20;
    }
    // Cheap pre-check before feed(): a sequence is pending or this key starts one.
    bool wants(uint32_t keysym) const { return !pending_.empty() || startsSequence(keysym); }
    bool pending() const { return !pending_.empty(); }

    // `unicode` = the key's character (0 = none), `mods` = VT_MOD_*. Press events only,
    // modifier-only keys never (the caller filters both).
    Step feed(uint32_t keysym, uint32_t unicode, uint32_t mods, std::string &out);
    // Drop a pending sequence (focus change, reset): nothing is output.
    void reset();

    // The accent a dead key types on its own (dead_acute → "'", dead_tilde → "~"); "" for
    // Multi_key / unknown keysyms.
    static std::string spacing(uint32_t deadKeysym);
    // Built-in table only (no libxkbcommon): ´ + e → "é"; "" = not composable.
    static std::string composeBuiltin(uint32_t deadKeysym, uint32_t unicode);

    // Tests / escape hatch (VIETTELEX_COMPOSE=builtin): ignore the locale Compose table.
    static void setBuiltinOnly(bool on);
    // True when the locale Compose table is loaded and used.
    static bool localeTableAvailable();

private:
    Step feedLocale(uint32_t keysym, std::string &out);
    Step feedBuiltin(uint32_t keysym, uint32_t unicode, std::string &out);
    std::string pendingAccents() const;
    std::vector<uint32_t> pending_;
    xkb_compose_state *state_ = nullptr;
};

}  // namespace viettelex
