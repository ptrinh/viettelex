// test_dead_keys — DeadKeys (dead_keys.h, #161): the "exactly one output per dead-key
// sequence" rule, with the built-in table and — when libxkbcommon + an en_US Compose file
// are present — the locale table. No other dependency (builds with any host compiler:
//   c++ -std=c++17 -Ilinux/common/include linux/common/src/dead_keys.cpp \
//       linux/common/tests/test_dead_keys.cpp -o /tmp/t && /tmp/t   (+ -ldl on old glibc)

#include "viettelex/dead_keys.h"
#include "viettelex/keys.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

using namespace viettelex;

static int g_fail = 0, g_pass = 0;
#define CHECK_EQ(a, b)                                                                         \
    do {                                                                                       \
        auto _a = (a);                                                                         \
        auto _b = (b);                                                                         \
        if (_a == _b) ++g_pass;                                                                \
        else {                                                                                 \
            ++g_fail;                                                                          \
            std::fprintf(stderr, "%s:%d: CHECK_EQ(%s, %s) failed\n", __FILE__, __LINE__, #a, #b); \
        }                                                                                      \
    } while (0)

namespace {

constexpr uint32_t dead_grave = 0xfe50, dead_acute = 0xfe51, dead_circumflex = 0xfe52, dead_tilde = 0xfe53,
                   dead_diaeresis = 0xfe57, dead_belowdot = 0xfe60, Multi_key = 0xff20;
using Step = DeadKeys::Step;

// What reaches the text for a key sequence: committed text, then the key itself when it is
// passed on ('·' marks a passed key without a character). Mirrors Session::processKey.
std::string run(DeadKeys &d, std::initializer_list<uint32_t> keys) {
    std::string screen;
    for (uint32_t k : keys) {
        const uint32_t uni = k < 0x100 ? k : 0;
        if (!d.wants(k)) {
            screen += uni ? std::string(1, char(uni)) : "·";
            continue;
        }
        std::string out;
        Step s = d.feed(k, uni, 0, out);
        screen += out;
        if (s == Step::Pass || s == Step::CommitThenKey) screen += uni ? std::string(1, char(uni)) : "·";
    }
    return screen;
}

void commonRules(const char *label) {
    std::fprintf(stderr, "-- %s\n", label);
    DeadKeys d;
    CHECK_EQ(run(d, {dead_acute}), std::string(""));  // pending: nothing yet
    CHECK_EQ(d.pending(), true);
    CHECK_EQ(run(d, {'e'}), std::string("é"));
    CHECK_EQ(d.pending(), false);
    CHECK_EQ(run(d, {dead_acute, 'E'}), std::string("É"));
    CHECK_EQ(run(d, {dead_diaeresis, 'u'}), std::string("ü"));
    CHECK_EQ(run(d, {dead_tilde, 'n'}), std::string("ñ"));
    CHECK_EQ(run(d, {dead_grave, 'a'}), std::string("à"));
    CHECK_EQ(run(d, {dead_circumflex, 'o'}), std::string("ô"));
    // dead + Space: the accent on its own (U.S. International: ' " ` ~ ^)
    CHECK_EQ(run(d, {dead_acute, ' '}), std::string("'"));
    CHECK_EQ(run(d, {dead_diaeresis, ' '}), std::string("\""));
    CHECK_EQ(run(d, {dead_grave, ' '}), std::string("`"));
    CHECK_EQ(run(d, {dead_tilde, ' '}), std::string("~"));
    CHECK_EQ(run(d, {dead_circumflex, ' '}), std::string("^"));
    // twice: the spacing accent itself
    CHECK_EQ(run(d, {dead_acute, dead_acute}), std::string("´"));
    // dead + a key it does not combine with: accent, then the key (never zero, never lost)
    CHECK_EQ(run(d, {dead_acute, 'x'}), std::string("'x"));
    CHECK_EQ(run(d, {dead_diaeresis, '1'}), std::string("\"1"));
    CHECK_EQ(run(d, {dead_acute, ks::Return}), std::string("'·"));
    // a second, different dead key: the first one's accent, the second still composes
    CHECK_EQ(run(d, {dead_acute, dead_grave, 'e'}), std::string("'è"));
    // Esc / BackSpace cancel: consumed, nothing typed, the next key is ordinary
    {
        std::string out;
        run(d, {dead_acute});
        CHECK_EQ(d.feed(ks::Escape, 0x1b, 0, out) == Step::Consumed, true);
        CHECK_EQ(out, std::string(""));
        CHECK_EQ(run(d, {'e'}), std::string("e"));
        run(d, {dead_acute});
        CHECK_EQ(d.feed(ks::BackSpace, 0x08, 0, out) == Step::Consumed, true);
        CHECK_EQ(run(d, {'e'}), std::string("e"));
    }
    // a shortcut chord drops the pending accent and goes through
    {
        std::string out;
        run(d, {dead_acute});
        CHECK_EQ(d.feed('z', 'z', VT_MOD_CTRL, out) == Step::Pass, true);
        CHECK_EQ(out, std::string(""));
        CHECK_EQ(d.pending(), false);
    }
    // focus change (reset): dropped
    run(d, {dead_acute});
    d.reset();
    CHECK_EQ(run(d, {'e'}), std::string("e"));
    // ordinary keys never reach the composer
    CHECK_EQ(d.wants('a'), false);
    CHECK_EQ(d.wants(ks::Escape), false);
    CHECK_EQ(d.wants(ks::BackSpace), false);
    CHECK_EQ(d.wants(dead_acute), true);
    CHECK_EQ(d.wants(Multi_key), true);
}

void builtinTable() {
    CHECK_EQ(DeadKeys::composeBuiltin(dead_acute, 'y'), std::string("ý"));
    CHECK_EQ(DeadKeys::composeBuiltin(0xfe5a, 's'), std::string("š"));  // dead_caron
    CHECK_EQ(DeadKeys::composeBuiltin(0xfe5b, 'C'), std::string("Ç"));  // dead_cedilla
    CHECK_EQ(DeadKeys::composeBuiltin(dead_acute, 'q'), std::string(""));
    CHECK_EQ(DeadKeys::composeBuiltin(dead_acute, 0xe9), std::string(""));
    CHECK_EQ(DeadKeys::spacing(dead_acute), std::string("'"));
    CHECK_EQ(DeadKeys::spacing(Multi_key), std::string(""));
    // every base has its result (the table's two strings line up)
    for (uint32_t dk = 0xfe50; dk <= 0xfe5c; ++dk)
        for (uint32_t c = 'A'; c <= 'z'; ++c) {
            if (c > 'Z' && c < 'a') continue;
            std::string r = DeadKeys::composeBuiltin(dk, c);
            if (r.empty()) continue;
            CHECK_EQ(r.size() >= 2 && r.size() <= 3, true);
        }
    // Multi_key without a locale table: left to the app as before
    DeadKeys d;
    std::string out;
    CHECK_EQ(d.feed(Multi_key, 0, 0, out) == Step::Pass, true);
    CHECK_EQ(d.pending(), false);
    // an unknown dead key too
    CHECK_EQ(d.feed(dead_belowdot, 0, 0, out) == Step::Pass, true);
}

void localeTable() {
    DeadKeys d;
    // Multi_key sequences (Compose key) come with the locale table.
    CHECK_EQ(run(d, {Multi_key, 'o', 'c'}), std::string("©"));
    CHECK_EQ(run(d, {Multi_key, 'e', '\''}), std::string("é"));
    // a dead key the built-in table lacks
    CHECK_EQ(run(d, {dead_belowdot, 'a'}), std::string("ạ"));
    // Multi_key + an invalid sequence: no accent to give, the key itself goes through
    CHECK_EQ(run(d, {Multi_key, ks::Return}), std::string("·"));
}

}  // namespace

int main() {
    // The locale table under test is en_US's (the rules users of U.S. International get).
    setenv("LC_ALL", "en_US.UTF-8", 1);
    DeadKeys::setBuiltinOnly(true);
    commonRules("built-in table");
    builtinTable();
    DeadKeys::setBuiltinOnly(false);
    if (DeadKeys::localeTableAvailable()) {
        commonRules("locale Compose table");
        localeTable();
    } else {
        std::fprintf(stderr, "-- locale Compose table: unavailable here (no libxkbcommon / Compose file), skipped\n");
    }
    std::printf("dead keys: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
