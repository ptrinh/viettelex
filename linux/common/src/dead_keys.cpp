// dead_keys.cpp — see dead_keys.h (#161).

#include "viettelex/dead_keys.h"

#include "viettelex/keys.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>

namespace viettelex {

namespace {

// MARK: - built-in table (no libxkbcommon / no Compose file for the locale)

// `space` = dead key + Space (what en_US.UTF-8 Compose gives: ´ Space → '), `twice` = the
// dead key pressed twice, `bases[i]` (ASCII) + the dead key → the i-th character of `results`.
struct DeadSpec {
    uint32_t keysym;
    const char *space;
    const char *twice;
    const char *bases;
    const char *results;
};

const DeadSpec kDead[] = {
    {0xfe50, "`", "`", "aeiouAEIOUnNwWyY", "àèìòùÀÈÌÒÙǹǸẁẀỳỲ"},                          // dead_grave
    {0xfe51, "'", "´", "aeiouyAEIOUYcCnNsSzZgGlLrRwW", "áéíóúýÁÉÍÓÚÝćĆńŃśŚźŹǵǴĺĹŕŔẃẂ"},  // dead_acute
    {0xfe52, "^", "^", "aeiouAEIOUwWyY", "âêîôûÂÊÎÔÛŵŴŷŶ"},                              // dead_circumflex
    {0xfe53, "~", "~", "anoANOiIuUeEyY", "ãñõÃÑÕĩĨũŨẽẼỹỸ"},                              // dead_tilde
    {0xfe54, "¯", "¯", "aeiouAEIOU", "āēīōūĀĒĪŌŪ"},                                      // dead_macron
    {0xfe55, "˘", "˘", "aAgGuU", "ăĂğĞŭŬ"},                                              // dead_breve
    {0xfe56, "˙", "˙", "zZeEgGcCI", "żŻėĖġĠċĊİ"},                                        // dead_abovedot
    {0xfe57, "\"", "¨", "aeiouyAEIOUY", "äëïöüÿÄËÏÖÜŸ"},                                 // dead_diaeresis
    {0xfe58, "°", "°", "aAuU", "åÅůŮ"},                                                  // dead_abovering
    {0xfe59, "˝", "˝", "oOuU", "őŐűŰ"},                                                  // dead_doubleacute
    {0xfe5a, "ˇ", "ˇ", "cCdDeEnNrRsStTzZ", "čČďĎěĚňŇřŘšŠťŤžŽ"},                          // dead_caron
    {0xfe5b, "¸", "¸", "cCsStT", "çÇşŞţŢ"},                                              // dead_cedilla
    {0xfe5c, "˛", "˛", "aAeEiIuU", "ąĄęĘįĮųŲ"},                                          // dead_ogonek
};

const DeadSpec *spec(uint32_t keysym) {
    for (const auto &d : kDead)
        if (d.keysym == keysym) return &d;
    return nullptr;
}

// The i-th UTF-8 character of s ("" when out of range).
std::string nthChar(const char *s, size_t i) {
    const char *p = s;
    for (;;) {
        if (!*p) return "";
        const char *q = p + 1;
        while (*q && (static_cast<unsigned char>(*q) & 0xc0) == 0x80) ++q;
        if (i == 0) return std::string(p, size_t(q - p));
        --i;
        p = q;
    }
}

// MARK: - libxkbcommon Compose (dlopen: no build dependency, every desktop has it)

// xkbcommon-compose.h values (stable ABI).
enum { XKB_COMPOSE_FEED_IGNORED = 0 };
enum { XKB_COMPOSE_NOTHING = 0, XKB_COMPOSE_COMPOSING = 1, XKB_COMPOSE_COMPOSED = 2, XKB_COMPOSE_CANCELLED = 3 };

struct Xkb {
    bool ok = false;
    void *table = nullptr;
    xkb_compose_state *(*stateNew)(void *, int) = nullptr;
    void (*stateUnref)(xkb_compose_state *) = nullptr;
    int (*stateFeed)(xkb_compose_state *, uint32_t) = nullptr;
    void (*stateReset)(xkb_compose_state *) = nullptr;
    int (*stateStatus)(xkb_compose_state *) = nullptr;
    int (*stateUtf8)(xkb_compose_state *, char *, size_t) = nullptr;
    uint32_t (*stateOneSym)(xkb_compose_state *) = nullptr;
    int (*keysymUtf8)(uint32_t, char *, size_t) = nullptr;
};

std::atomic<bool> g_builtinOnly{false};

const Xkb &xkb() {
    static const Xkb api = [] {
        Xkb a;
        const char *force = std::getenv("VIETTELEX_COMPOSE");
        if (force && std::strcmp(force, "builtin") == 0) return a;
        void *lib = dlopen("libxkbcommon.so.0", RTLD_NOW | RTLD_LOCAL);
        if (!lib) return a;
        auto ctxNew = reinterpret_cast<void *(*)(int)>(dlsym(lib, "xkb_context_new"));
        auto tableNew =
            reinterpret_cast<void *(*)(void *, const char *, int)>(dlsym(lib, "xkb_compose_table_new_from_locale"));
        a.stateNew = reinterpret_cast<decltype(a.stateNew)>(dlsym(lib, "xkb_compose_state_new"));
        a.stateUnref = reinterpret_cast<decltype(a.stateUnref)>(dlsym(lib, "xkb_compose_state_unref"));
        a.stateFeed = reinterpret_cast<decltype(a.stateFeed)>(dlsym(lib, "xkb_compose_state_feed"));
        a.stateReset = reinterpret_cast<decltype(a.stateReset)>(dlsym(lib, "xkb_compose_state_reset"));
        a.stateStatus = reinterpret_cast<decltype(a.stateStatus)>(dlsym(lib, "xkb_compose_state_get_status"));
        a.stateUtf8 = reinterpret_cast<decltype(a.stateUtf8)>(dlsym(lib, "xkb_compose_state_get_utf8"));
        a.stateOneSym = reinterpret_cast<decltype(a.stateOneSym)>(dlsym(lib, "xkb_compose_state_get_one_sym"));
        a.keysymUtf8 = reinterpret_cast<decltype(a.keysymUtf8)>(dlsym(lib, "xkb_keysym_to_utf8"));
        if (!ctxNew || !tableNew || !a.stateNew || !a.stateUnref || !a.stateFeed || !a.stateReset ||
            !a.stateStatus || !a.stateUtf8 || !a.stateOneSym || !a.keysymUtf8)
            return a;
        void *ctx = ctxNew(0);
        if (!ctx) return a;
        // The locale the Compose table follows: what libX11 / GTK / Fcitx5 use.
        const char *loc = nullptr;
        for (const char *var : {"LC_ALL", "LC_CTYPE", "LANG"}) {
            const char *v = std::getenv(var);
            if (v && *v) {
                loc = v;
                break;
            }
        }
        a.table = tableNew(ctx, loc ? loc : "C", 0);
        a.ok = a.table != nullptr;  // ctx stays referenced by the table for the process
        return a;
    }();
    return api;
}

bool useLocale() { return !g_builtinOnly.load(std::memory_order_relaxed) && xkb().ok; }

}  // namespace

DeadKeys::~DeadKeys() {
    if (state_) xkb().stateUnref(state_);
}

void DeadKeys::setBuiltinOnly(bool on) { g_builtinOnly = on; }
bool DeadKeys::localeTableAvailable() { return useLocale(); }

void DeadKeys::reset() {
    pending_.clear();
    if (state_) xkb().stateReset(state_);
}

std::string DeadKeys::spacing(uint32_t deadKeysym) {
    if (const DeadSpec *d = spec(deadKeysym)) return d->space;
    if (deadKeysym == 0xff20 || !useLocale()) return "";
    // Another dead key (dead_belowdot, dead_hook…): what the locale gives it + Space.
    const Xkb &x = xkb();
    xkb_compose_state *st = x.stateNew(x.table, 0);
    if (!st) return "";
    std::string out;
    x.stateFeed(st, deadKeysym);
    x.stateFeed(st, ks::space);
    if (x.stateStatus(st) == XKB_COMPOSE_COMPOSED) {
        char buf[64] = {};
        int n = x.stateUtf8(st, buf, sizeof buf);
        if (n > 0 && size_t(n) < sizeof buf) out.assign(buf, size_t(n));
    }
    x.stateUnref(st);
    return out;
}

std::string DeadKeys::composeBuiltin(uint32_t deadKeysym, uint32_t unicode) {
    const DeadSpec *d = spec(deadKeysym);
    if (!d || unicode == 0 || unicode >= 0x80) return "";
    const char *at = std::strchr(d->bases, char(unicode));
    if (!at) return "";
    return nthChar(d->results, size_t(at - d->bases));
}

std::string DeadKeys::pendingAccents() const {
    std::string out;
    for (uint32_t k : pending_) out += spacing(k);
    return out;
}

DeadKeys::Step DeadKeys::feed(uint32_t keysym, uint32_t unicode, uint32_t mods, std::string &out) {
    out.clear();
    if (!pending_.empty()) {
        if (keysym == ks::Escape || keysym == ks::BackSpace) {
            reset();  // cancel: the accent was never shown, nothing to take back
            return Step::Consumed;
        }
        if (mods & (VT_MOD_CTRL | VT_MOD_ALT | VT_MOD_SUPER)) {
            reset();  // a shortcut (Ctrl+Z…) is not a letter to put an accent on
            return Step::Pass;
        }
    }
    return useLocale() ? feedLocale(keysym, out) : feedBuiltin(keysym, unicode, out);
}

DeadKeys::Step DeadKeys::feedLocale(uint32_t keysym, std::string &out) {
    const Xkb &x = xkb();
    if (!state_) state_ = x.stateNew(x.table, 0);
    if (!state_) return Step::Pass;
    if (x.stateFeed(state_, keysym) == XKB_COMPOSE_FEED_IGNORED) return pending_.empty() ? Step::Pass : Step::Consumed;
    switch (x.stateStatus(state_)) {
    case XKB_COMPOSE_COMPOSING:
        pending_.push_back(keysym);
        return Step::Consumed;
    case XKB_COMPOSE_COMPOSED: {
        char buf[64] = {};
        int n = x.stateUtf8(state_, buf, sizeof buf);
        if (n > 0 && size_t(n) < sizeof buf) out.assign(buf, size_t(n));
        else if (n == 0) {  // a keysym-only result: its character, if it has one
            n = x.keysymUtf8(x.stateOneSym(state_), buf, sizeof buf);
            if (n > 1) out.assign(buf, size_t(n - 1));  // count includes the NUL
        }
        if (out.empty()) out = pendingAccents();  // never zero
        reset();
        return out.empty() ? Step::Consumed : Step::Commit;
    }
    case XKB_COMPOSE_CANCELLED: {
        out = pendingAccents();
        reset();
        // The key that broke the sequence may start the next one (´ then `).
        if (startsSequence(keysym)) {
            std::string more;
            Step s = feedLocale(keysym, more);
            out += more;
            if (s == Step::Pass || s == Step::CommitThenKey) return out.empty() ? s : Step::CommitThenKey;
            return out.empty() ? Step::Consumed : Step::Commit;
        }
        return out.empty() ? Step::Pass : Step::CommitThenKey;
    }
    default:  // NOTHING: a dead key the locale's table does not know
        reset();
        out = spacing(keysym);
        return out.empty() ? Step::Pass : Step::Commit;
    }
}

DeadKeys::Step DeadKeys::feedBuiltin(uint32_t keysym, uint32_t unicode, std::string &out) {
    if (pending_.empty()) {
        if (!spec(keysym)) return Step::Pass;  // Multi_key / rare dead keys: left to the app as before
        pending_.push_back(keysym);
        return Step::Consumed;
    }
    const DeadSpec *d = spec(pending_.front());
    pending_.clear();
    if (keysym == ks::space) out = d->space;
    else if (keysym == d->keysym) out = d->twice;
    else out = composeBuiltin(d->keysym, unicode);
    if (!out.empty()) return Step::Commit;
    out = d->space;
    if (spec(keysym)) {  // another dead key: the first one's accent, the new one waits
        pending_.push_back(keysym);
        return Step::Commit;
    }
    return Step::CommitThenKey;
}

}  // namespace viettelex
