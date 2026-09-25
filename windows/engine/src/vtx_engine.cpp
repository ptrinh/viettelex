// C ABI over vtx::TelexEngine (see include/viettelex/vtx_engine.h, API.md).
#include "viettelex/vtx_engine.h"
#include "viettelex/telex_engine.hpp"
#include <new>

static_assert(sizeof(char16_t) == sizeof(uint16_t), "UTF-16 unit size");
static_assert(VTX_MAX_TEXT == vtx::kMaxText, "text capacity mismatch");

struct vtx_engine {
    vtx::TelexEngine e;
};

namespace {
inline void toC(const vtx::Action& a, vtx_action* out) {
    if (!out) return;
    out->kind = a.kind;
    out->backspaces = a.backspaces;
    out->insert_len = a.length;
    for (int i = 0; i < a.length; ++i) out->insert[i] = static_cast<uint16_t>(a.text[i]);
    out->insert[a.length] = 0;
}
inline char16_t* u16(uint16_t* p) { return reinterpret_cast<char16_t*>(p); }
} // namespace

extern "C" {

vtx_engine* vtx_create(void) { return new (std::nothrow) vtx_engine(); }
vtx_engine* vtx_clone(const vtx_engine* e) { return e ? new (std::nothrow) vtx_engine(*e) : nullptr; }
void vtx_destroy(vtx_engine* e) { delete e; }

void vtx_set_flags(vtx_engine* h, uint32_t f) {
    if (!h) return;
    vtx::TelexEngine& e = h->e;
    e.freeMarking = (f & VTX_FREE_MARKING) != 0;
    e.modernTone = (f & VTX_MODERN_TONE) != 0;
    e.liveSpellCheck = (f & VTX_LIVE_SPELL_CHECK) != 0;
    e.simpleTelex = (f & VTX_SIMPLE_TELEX) != 0;
    e.teencode = (f & VTX_TEENCODE) != 0;
    e.quickTelex = (f & VTX_QUICK_TELEX) != 0;
    e.bracketVowels = (f & VTX_BRACKET_VOWELS) != 0;
    e.vniMode = (f & VTX_VNI) != 0;
    e.contextualEnglish = (f & VTX_CONTEXTUAL_ENGLISH) != 0;
    e.englishWordRestore = (f & VTX_ENGLISH_WORD_RESTORE) != 0;
    e.collisionPrefersVietnamese = (f & VTX_COLLISION_PREFERS_VI) != 0;
}

uint32_t vtx_get_flags(const vtx_engine* h) {
    if (!h) return 0;
    const vtx::TelexEngine& e = h->e;
    uint32_t f = 0;
    if (e.freeMarking) f |= VTX_FREE_MARKING;
    if (e.modernTone) f |= VTX_MODERN_TONE;
    if (e.liveSpellCheck) f |= VTX_LIVE_SPELL_CHECK;
    if (e.simpleTelex) f |= VTX_SIMPLE_TELEX;
    if (e.teencode) f |= VTX_TEENCODE;
    if (e.quickTelex) f |= VTX_QUICK_TELEX;
    if (e.bracketVowels) f |= VTX_BRACKET_VOWELS;
    if (e.vniMode) f |= VTX_VNI;
    if (e.contextualEnglish) f |= VTX_CONTEXTUAL_ENGLISH;
    if (e.englishWordRestore) f |= VTX_ENGLISH_WORD_RESTORE;
    if (e.collisionPrefersVietnamese) f |= VTX_COLLISION_PREFERS_VI;
    return f;
}

void vtx_feed(vtx_engine* h, uint32_t ch, vtx_action* out) {
    vtx::Action a;
    if (h) h->e.feed(static_cast<char32_t>(ch), a);
    toC(a, out);
}
void vtx_backspace(vtx_engine* h, vtx_action* out) {
    vtx::Action a;
    if (h) h->e.backspace(a);
    toC(a, out);
}
void vtx_commit_boundary(vtx_engine* h, int auto_restore, vtx_action* out) {
    vtx::Action a;
    a.kind = vtx::Action::None;
    if (h) h->e.commitBoundary(auto_restore != 0, a);
    toC(a, out);
}
int32_t vtx_commit_text(vtx_engine* h, int auto_restore, uint16_t* buf, int32_t cap) {
    return h ? h->e.commitText(auto_restore != 0, u16(buf), cap) : 0;
}
int32_t vtx_peek_commit_text(const vtx_engine* h, int auto_restore, uint16_t* buf, int32_t cap) {
    return h ? h->e.peekCommitText(auto_restore != 0, u16(buf), cap) : 0;
}
int32_t vtx_composed(const vtx_engine* h, uint16_t* buf, int32_t cap) {
    return h ? h->e.composed(u16(buf), cap) : 0;
}
int32_t vtx_raw_keystrokes(const vtx_engine* h, uint16_t* buf, int32_t cap) {
    return h ? h->e.rawKeystrokes(u16(buf), cap) : 0;
}
int vtx_is_empty(const vtx_engine* h) { return h ? h->e.isEmpty() : 1; }
void vtx_reset(vtx_engine* h) { if (h) h->e.reset(); }
void vtx_reset_context(vtx_engine* h) { if (h) h->e.resetContext(); }
int vtx_previous_word_english(const vtx_engine* h) { return h ? h->e.previousWordEnglish() : 0; }
int vtx_can_reopen_last_commit(const vtx_engine* h) { return h ? h->e.canReopenLastCommit() : 0; }
int32_t vtx_reopen_last_commit(vtx_engine* h, uint16_t* buf, int32_t cap) {
    return h ? h->e.reopenLastCommit(u16(buf), cap) : -1;
}
void vtx_forget_last_commit(vtx_engine* h) { if (h) h->e.forgetLastCommit(); }
int vtx_seed(vtx_engine* h, const uint16_t* word, int32_t len) {
    if (!h || (!word && len > 0)) return 0;
    return h->e.seed(reinterpret_cast<const char16_t*>(word), len) ? 1 : 0;
}
int vtx_is_overflowed(const vtx_engine* h) { return h ? h->e.isOverflowed() : 0; }

} // extern "C"
