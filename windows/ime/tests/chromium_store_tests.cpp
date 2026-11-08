// Field report 2026-10 (Windows, Messenger/Facebook in a Chromium browser): Telex
// "hai chuwowng trinhf hocj AI tuwf lowps 1" came out "ại chương tình ọc AI ừ óp 1" —
// letters gone. These tests drive the real session over a model of Chromium's TSF store
// (chromium_store.h: a cache that lags the page; edits land at the page's caret).
//
// Before the fix, the same model typed e.g. "hai chuưowng triìn hoọ AI tuừ loưps 1"
// (letters deleted / misplaced) in ~40% of random report schedules, and with a steady lag
// the field "fell back" — which hands it to VietTelex.exe's hook (blind backspace+retype).
#include "chromium_store.h"
#include "session.h"
#include "settings.h"
#include "test.h"

using namespace vtx;
using vtx::test::ChromiumLaggingStore;

namespace {

constexpr const char* kReport = "hai chuwowng trinhf hocj AI tuwf lowps 1";
constexpr const char* kWant = "hai chương trình học AI từ lớp 1";

struct ChromeRig {
    Settings settings;
    TypingSession s;
    ChromiumLaggingStore doc;
    // Every n-th key the browser refuses the synchronous edit session (0 = never):
    // TextService::OnKeyDown then resets the word and lets the key through.
    int refuseEvery = 0;
    int keys = 0;
    explicit ChromeRig(int lag) {
        s.setOutputMode(OutputMode::InPlace);
        SessionOptions o;
        o.engineFlags = settings.engineFlags();
        o.autoRestore = settings.autoRestore;
        o.reEditWord = settings.reEditWord;
        o.shortcuts = &settings.shortcuts;
        s.configure(o);
        s.setAsyncStore(true);  // what the TIP says for a Chromium (transitory) context
        doc.lag = lag;
    }
    void key(char c) {
        KeyInput k;
        k.kind = KeyKind::Char;
        k.ch = static_cast<unsigned char>(c);
        ++keys;
        bool eaten = false;
        if (s.wantsKey(k)) {
            // (A store refuses a synchronous lock while it holds one — not mid-composition
            // in this model.)
            if (refuseEvery && keys % refuseEvery == 0 && !doc.comp) s.reset();
            else eaten = s.handleKey(k, doc);
        }
        if (!eaten) {
            CHECK(!doc.comp);  // a key reaching the app never finds our composition open
            doc.appInsert(static_cast<char16_t>(c));
        }
        report();
    }
    // A renderer report; OnEndEdit (outside a composition) re-checks an in-place word.
    void report() {
        if (doc.report() && !doc.comp) s.verifyScreen(doc);
    }
    std::string type(const char* p) {
        for (; *p; ++p) key(*p);
        return utf16ToUtf8(doc.page.text);
    }
};

// Letters a reader sees: lower-case, diacritics stripped, Telex modifier keys dropped
// (a word that came out unaccented, "chuwowng", still holds every letter of "chương").
std::u16string letters(const std::u16string& s) {
    static const char16_t* const kFrom =
        u"àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ";
    static const char16_t* const kTo =
        u"aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd";
    std::u16string out;
    for (char16_t c : s) {
        if (c >= u'A' && c <= u'Z') c = static_cast<char16_t>(c - u'A' + u'a');
        for (size_t i = 0; kFrom[i]; ++i)
            if (kFrom[i] == c) { c = kTo[i]; break; }
        if (c == u'w' || c == u'f' || c == u's' || c == u'r' || c == u'x' || c == u'j' || c == u'z') continue;
        out += c;
    }
    return out;
}

// Every letter of `want` is still on the page, in order (extra ones allowed).
bool noLetterLost(const std::u16string& page, const char* want) {
    const std::u16string a = letters(page), b = letters(utf8ToUtf16(want));
    size_t i = 0;
    for (char16_t c : a)
        if (i < b.size() && c == b[i]) ++i;
    return i == b.size();
}

}  // namespace

TEST(chromium_store_without_lag_types_in_place) {
    ChromeRig r(0);
    CHECK_EQ(r.type(kReport), std::string(kWant));
    CHECK(r.s.wordMode() == OutputMode::InPlace);
    CHECK(!r.s.prefersComposition());
}

TEST(chromium_store_steady_lag_types_the_report_intact) {
    for (int lag = 1; lag <= 4; ++lag) {
        ChromeRig r(lag);
        CHECK_EQ(r.type(kReport), std::string(kWant));
        CHECK(r.s.prefersComposition());  // the field composes once the lag shows
        CHECK(!r.s.contextFellBack());     // ... and is never handed to the hook
    }
}

TEST(chromium_store_bursty_reports_type_the_report_intact) {
    // A busy page (React/Lexical): reports arrive only every k keys, then catch up.
    for (int k = 2; k <= 5; ++k) {
        for (int phase = 0; phase < k; ++phase) {
            ChromeRig r(1000);
            int i = 0;
            for (const char* p = kReport; *p; ++p, ++i) {
                r.key(*p);
                if ((i + phase) % k == 0) {
                    r.doc.catchUp();
                    if (!r.doc.comp) r.s.verifyScreen(r.doc);
                }
            }
            CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string(kWant));
            CHECK(!r.s.contextFellBack());
        }
    }
}

TEST(chromium_store_random_reports_and_refusals_never_lose_a_letter) {
    // Random report timing (sometimes a stale-but-newer state, sometimes a full catch-up)
    // and, for some runs, every 5th edit session refused. Accents may be missing on a
    // word typed while the store lagged; no typed letter may ever be lost or reordered.
    int intact = 0;
    for (unsigned seed = 1; seed <= 2000; ++seed) {
        ChromeRig r(1000);
        r.refuseEvery = seed % 7 == 0 ? 5 : 0;
        unsigned x = seed;
        for (const char* p = kReport; *p; ++p) {
            r.key(*p);
            x = x * 1103515245u + 12345u;
            const unsigned m = (x >> 16) % 4;
            if (m == 0) {
                r.doc.catchUp();
                if (!r.doc.comp) r.s.verifyScreen(r.doc);
            } else if (m == 1) {
                r.doc.lag = static_cast<int>((x >> 20) % 3);
                r.report();
                r.doc.lag = 1000;
            }
        }
        const bool ok = noLetterLost(r.doc.page.text, kWant);
        if (!ok) std::printf("  seed %u: %s\n", seed, utf16ToUtf8(r.doc.page.text).c_str());
        CHECK(ok);
        CHECK(!r.s.contextFellBack());
        if (utf16ToUtf8(r.doc.page.text) == kWant) ++intact;
    }
    CHECK(intact > 1500);  // most schedules: the whole sentence, accents included
}

TEST(chromium_store_stale_view_keeps_the_word_until_the_next_key) {
    // A report older than our last edit ("tu" while we typed "tư") is lag, not a change.
    ChromeRig r(1000);
    r.type("tu");
    r.doc.catchUp();
    r.key('w');
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("tư"));
    r.doc.view = r.doc.history[2];  // the page after "tu", before our edit
    r.s.verifyScreen(r.doc);
    CHECK(r.s.wordActive());
    r.doc.catchUp();
    r.type("f ");
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("từ "));
}

TEST(chromium_store_edit_key_on_a_stale_view_goes_through_as_typed) {
    // The view still lacks the "u" when "w" needs to edit it: an edit from that view would
    // land at the page's caret and eat the wrong letter. The key goes through instead.
    ChromeRig r(1000);
    r.type("tu");
    r.key('w');
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("tuw"));
    CHECK(r.s.prefersComposition());
    CHECK(!r.s.contextFellBack());
    r.doc.catchUp();
    r.type(" lowps ");
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("tuw lớp "));
    CHECK(r.s.wordMode() == OutputMode::Composition);
}

TEST(chromium_store_failures_never_hand_the_field_to_the_hook) {
    // TextService::OnKeyDown asks VietTelex.exe's hook to type a field whose in-place
    // edits failed (contextFellBack). In a browser that is the wrong cure: compose.
    ChromeRig r(1000);
    r.type("h");  // the view shows nothing yet: a lagging page, not an unreadable field
    r.type("ai ");
    CHECK(!r.s.contextFellBack());
    CHECK(r.s.prefersComposition());
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("hai "));
}

TEST(chromium_store_turns_reedit_off) {
    // Re-edit seeds the word from the view; in an async store the view may lack the
    // boundary just typed (" " still in flight) and the edit would hit the page's caret.
    for (int async = 0; async < 2; ++async) {
        ChromeRig r(0);
        r.s.setAsyncStore(async != 0);
        r.type("viet");
        r.s.reset();  // e.g. the caret was clicked back to the end of the word
        r.key('j');
        CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string(async ? "vietj" : "viẹt"));
    }
    ChromeRig r(0);
    r.s.resetContext();
    CHECK(!r.s.asyncStore());  // a new field is evaluated afresh by the TIP
}

// #139 (Canva in Brave): Telex "OOngs" ("Ống"). Typed fast, the second O came before the
// store showed the first one ("OOngs"); typed slowly, "OO" -> "Ô" worked but "s" came
// before the store showed "ng" ("Ôngs"). Each failure switched only THAT field to
// composition, and the web editor re-focuses its input often (OnSetFocus ->
// resetContext), so nearly every word was a "first word" again. Once a store of this app
// has lagged, later async fields compose from the first letter.
namespace {
// What the TIP does on a focus change followed by a word start (OnSetFocus ->
// resetContext; evaluateHostAtWordStart -> setAsyncStore for a Chromium context).
void refocus(ChromeRig& r) {
    r.s.resetContext();
    r.s.setAsyncStore(true);
}
}  // namespace

TEST(chromium_store_issue139_fast_first_word_then_refocused_fields_compose) {
    ChromeRig r(1000);  // the store never catches up while typing fast
    r.type("OOngs");
    // The first word in this app still goes through as typed (no letter lost).
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("OOngs"));
    CHECK(r.s.asyncStoreLagged());
    r.type(" ");
    for (int i = 0; i < 3; ++i) {
        refocus(r);
        CHECK(r.s.prefersComposition());
        r.type("OOngs ");
    }
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("OOngs Ống Ống Ống "));
    CHECK(!r.s.contextFellBack());  // never handed to the hook
}

TEST(chromium_store_issue139_slow_typing_tone_key_then_refocused_fields_compose) {
    ChromeRig r(1000);
    auto settle = [&] {
        r.doc.catchUp();
        if (!r.doc.comp) r.s.verifyScreen(r.doc);
    };
    r.key('O');
    settle();
    r.key('O');  // the store shows the first O: in place
    settle();
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("Ô"));
    r.key('n');
    r.key('g');
    r.key('s');  // the store does not show "ng" yet
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("Ôngs"));
    r.key(' ');
    settle();
    refocus(r);
    r.type("OOngs ");
    CHECK_EQ(utf16ToUtf8(r.doc.page.text), std::string("Ôngs Ống "));
}

TEST(chromium_store_lag_latch_survives_focus_changes_but_not_for_sync_stores) {
    // A store that never lagged keeps typing in place after a focus change.
    ChromeRig fine(0);
    fine.type("OOngs ");
    refocus(fine);
    CHECK(!fine.s.prefersComposition());
    CHECK(!fine.s.asyncStoreLagged());
    fine.type("OOngs ");
    CHECK_EQ(utf16ToUtf8(fine.doc.page.text), std::string("Ống Ống "));
    CHECK(fine.s.wordMode() == OutputMode::InPlace);
    // The latch only steers async (Chromium) fields: a classic store in the same app
    // (a native dialog, setAsyncStore(false)) keeps in-place.
    ChromeRig r(1000);
    r.type("OOngs ");
    CHECK(r.s.asyncStoreLagged());
    r.s.resetContext();
    r.s.setAsyncStore(false);
    CHECK(!r.s.prefersComposition());
}

// Field report 2026-11 (Windows 11 Start search, Telex): the FIRST word lost its tone key
// after "aa" ("taafng" -> "tâfng", "taangf taangf" -> "tângf tầng"); later words were fine.
// Modelled as Chromium's store: the replace "a" -> "â" reaches the page as delete + insert,
// and the next renderer report carries the state between the two (the view goes "back").
// The next key that needs an edit then goes through as typed (no letter lost, never an
// edit from a stale view) and the field composes from the next word on (#139 path).
namespace {
std::vector<std::string>* g_lines = nullptr;
void captureLog(const char* m) {
    if (g_lines) g_lines->push_back(m);
}
void settle(ChromeRig& r) {
    r.doc.catchUp();
    if (!r.doc.comp) r.s.verifyScreen(r.doc);
}
// Types `keys`; the renderer reports after each key, except: after key `halfAfter` (our
// replace) the report shows the page between its deletion and its insertion, and no
// further report arrives until the word ends (a space).
std::string searchWord(ChromeRig& r, const char* keys, int halfAfter) {
    bool held = false;
    for (int i = 0; keys[i]; ++i) {
        r.key(keys[i]);
        if (keys[i] == ' ') held = false;
        if (i == halfAfter) {
            r.doc.lag = 1;
            r.report();
            r.doc.lag = 1000;
            held = true;
        } else if (!held) {
            settle(r);
        }
    }
    return utf16ToUtf8(r.doc.page.text);
}
}  // namespace

TEST(start_search_first_word_report_reproduced_by_the_async_store_model) {
    {
        ChromeRig r(1000);
        CHECK_EQ(searchWord(r, "taafng ", 2), std::string("tâfng "));  // the reported first word
        CHECK(r.s.prefersComposition());
        CHECK(!r.s.contextFellBack());
        CHECK_EQ(searchWord(r, "taafng ", 2), std::string("tâfng tầng "));
    }
    {
        ChromeRig r(1000);
        CHECK_EQ(searchWord(r, "taangf ", 2), std::string("tângf "));
        CHECK_EQ(searchWord(r, "taangf", 2), std::string("tângf tầng"));
    }
}

TEST(start_search_async_box_composing_from_the_first_letter_keeps_the_first_word) {
    // What the TIP does for a shell search box on an async store (app_policy.h
    // shellSearchPrefersComposition): composition from the first letter, as the second
    // word of the report already did.
    struct Case {
        const char* keys;
        const char* want;
    };
    for (const Case& c : {Case{"taafng", "tầng tầng"}, Case{"taangf", "tầng tầng"}, Case{"huyeenf", "huyền huyền"},
                          Case{"tieenf", "tiền tiền"}}) {
        ChromeRig r(1000);
        r.s.setPreferComposition(true);
        searchWord(r, c.keys, 2);
        searchWord(r, " ", -1);
        CHECK_EQ(searchWord(r, c.keys, 2), std::string(c.want));
        CHECK(!r.s.contextFellBack());
    }
}

TEST(word_dropping_decisions_are_logged_without_text) {
    Settings st;
    SessionOptions o;
    o.engineFlags = st.engineFlags();
    o.autoRestore = st.autoRestore;
    o.reEditWord = st.reEditWord;
    o.log = captureLog;
    std::vector<std::string> lines;
    g_lines = &lines;
    {
        ChromeRig r(1000);
        r.s.configure(o);
        searchWord(r, "taaf", 2);
        // A sync field: a word the app changed under us is logged too.
        ChromeRig s(0);
        s.s.configure(o);
        s.s.setAsyncStore(false);
        s.type("vie");
        s.doc.page = s.doc.view = {u"x", 1};
        s.key('e');
        // A word dropped mid-way (a focus change) in an async store, then its tone key:
        // logged only with debug logging on (it costs a read).
        for (bool verbose : {false, true}) {
            ChromeRig f(0);
            SessionOptions v = o;
            v.verboseLog = verbose;
            f.s.configure(v);
            f.type("taa");
            f.s.resetContext();
            f.s.setAsyncStore(true);
            const size_t before = lines.size();
            f.key('f');
            CHECK_EQ(utf16ToUtf8(f.doc.page.text), std::string("tâf"));
            bool reEditOff = false;
            for (size_t i = before; i < lines.size(); ++i)
                if (lines[i].find("re-edit: a tone key right after a word, reaching back is off here (async store)") !=
                    std::string::npos)
                    reEditOff = true;
            CHECK(reEditOff == verbose);
        }
        // A tone key starting a word after a space is ordinary typing: never logged.
        ChromeRig sp(0);
        SessionOptions v = o;
        v.verboseLog = true;
        sp.s.configure(v);
        const size_t before = lines.size();
        sp.type("ta sao");
        for (size_t i = before; i < lines.size(); ++i) CHECK(lines[i].find("re-edit") == std::string::npos);
    }
    g_lines = nullptr;
    bool asyncDrop = false, syncDrop = false;
    for (const std::string& l : lines) {
        if (l.find("key needs an edit -> as typed, word dropped (read ") != std::string::npos) asyncDrop = true;
        if (l.find("text before the caret no longer ends with the word -> word dropped") != std::string::npos)
            syncDrop = true;
        CHECK(l.find("\xC3\xA2") == std::string::npos);  // never typed text ("â")
        CHECK(l.find("\xC3\xAA") == std::string::npos);  // ("ê")
    }
    CHECK(asyncDrop);
    CHECK(syncDrop);
}
