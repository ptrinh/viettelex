/* VietTelex engine — C ABI. Port of TelexCore (Swift) TelexEngine; see API.md.
 * Pure C, no platform headers. UTF-16 text (uint16_t, same layout as WCHAR).
 * Thread-safety: one vtx_engine per thread/context; the library has no mutable globals. */
#ifndef VIETTELEX_VTX_ENGINE_H
#define VIETTELEX_VTX_ENGINE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct vtx_engine vtx_engine;          /* opaque */

/* Action kinds (mirror Swift TelexAction). */
enum {
    VTX_PASSTHROUGH = 0,   /* engine did not handle it: let the app insert the key  */
    VTX_REPLACE     = 1,   /* delete `backspaces` chars before caret, insert `insert` */
    VTX_NONE        = 2    /* nothing to do                                          */
};

#define VTX_MAX_TEXT 64    /* max UTF-16 units any engine string can have (+NUL fits) */

typedef struct vtx_action {
    int32_t  kind;                     /* VTX_PASSTHROUGH / VTX_REPLACE / VTX_NONE */
    int32_t  backspaces;               /* REPLACE only */
    int32_t  insert_len;               /* REPLACE only, UTF-16 units */
    uint16_t insert[VTX_MAX_TEXT];     /* REPLACE only, NUL-terminated */
} vtx_action;

/* Settings bitmask (names = Swift properties). */
enum {
    VTX_FREE_MARKING        = 1u << 0,   /* freeMarking            (app default ON)  */
    VTX_MODERN_TONE         = 1u << 1,   /* modernTone (hoà/thuý)  (app default OFF) */
    VTX_LIVE_SPELL_CHECK    = 1u << 2,   /* liveSpellCheck         (app default ON)  */
    VTX_SIMPLE_TELEX        = 1u << 3,   /* simpleTelex            (OFF) */
    VTX_TEENCODE            = 1u << 4,   /* teencode               (engine ON, app default OFF) */
    VTX_QUICK_TELEX         = 1u << 5,   /* quickTelex             (OFF) */
    VTX_BRACKET_VOWELS      = 1u << 6,   /* bracketVowels [ ] -> ơ ư (OFF) */
    VTX_VNI                 = 1u << 7,   /* vniMode                (OFF = Telex) */
    VTX_CONTEXTUAL_ENGLISH  = 1u << 8,   /* contextualEnglish      (app default ON) */
    VTX_ENGLISH_WORD_RESTORE= 1u << 9,   /* englishWordRestore     (ON; keep ON) */
    VTX_COLLISION_PREFERS_VI= 1u << 10   /* collisionPrefersVietnamese (app default ON) */
};
/* Engine defaults (== Swift TelexEngine()): TEENCODE | ENGLISH_WORD_RESTORE. */
#define VTX_ENGINE_DEFAULT_FLAGS (VTX_TEENCODE | VTX_ENGLISH_WORD_RESTORE)

vtx_engine* vtx_create(void);                    /* NULL on OOM */
vtx_engine* vtx_clone(const vtx_engine* e);      /* independent snapshot */
void        vtx_destroy(vtx_engine* e);

void     vtx_set_flags(vtx_engine* e, uint32_t flags);   /* safe mid-word */
uint32_t vtx_get_flags(const vtx_engine* e);

/* Keystrokes. `ch` is a UTF-32 code point (the typed character, case preserved).
   Only ASCII letters compose (+ digits in VNI, + [ ] { } with BRACKET_VOWELS);
   anything else returns VTX_PASSTHROUGH and the caller should treat it as a word
   boundary (call vtx_commit_boundary first, then insert the char itself). */
void vtx_feed(vtx_engine* e, uint32_t ch, vtx_action* out);
void vtx_backspace(vtx_engine* e, vtx_action* out);  /* PASSTHROUGH = let app delete */

/* Word boundary: applies auto-restore, resets the word. Caller inserts the boundary
   char afterwards. `auto_restore` = settings autoRestore (app default ON). */
void vtx_commit_boundary(vtx_engine* e, int auto_restore, vtx_action* out);

/* Composition-mode commit: returns the final text (restore applied), resets word.
   Return value = length in UTF-16 units (buf is NUL-terminated; cap >= VTX_MAX_TEXT
   is always enough). */
int32_t vtx_commit_text(vtx_engine* e, int auto_restore, uint16_t* buf, int32_t cap);
/* Same text commit_text would produce, without changing any state. */
int32_t vtx_peek_commit_text(const vtx_engine* e, int auto_restore, uint16_t* buf, int32_t cap);

int32_t vtx_composed(const vtx_engine* e, uint16_t* buf, int32_t cap);       /* current word on screen */
int32_t vtx_raw_keystrokes(const vtx_engine* e, uint16_t* buf, int32_t cap); /* raw keys of word */
int     vtx_is_empty(const vtx_engine* e);
/* Word exceeded 32 keys: a PASSTHROUGH from feed/backspace then means "key NOT recorded,
   app renders/deletes natively" (Swift isOverflowed). */
int     vtx_is_overflowed(const vtx_engine* e);

void vtx_reset(vtx_engine* e);            /* drop current word (caret moved etc.) */
void vtx_reset_context(vtx_engine* e);    /* also forget English context (focus/app switch) */
int  vtx_previous_word_english(const vtx_engine* e);

/* Re-open: ⌫ right after a boundary. If vtx_can_reopen_last_commit(), the caller
   deletes the boundary char, calls vtx_reopen_last_commit(); on success (>= 0) the
   word (returned in buf) is back in the buffer and editable. -1 = nothing/ mismatch. */
int     vtx_can_reopen_last_commit(const vtx_engine* e);
int32_t vtx_reopen_last_commit(vtx_engine* e, uint16_t* buf, int32_t cap);
void    vtx_forget_last_commit(vtx_engine* e);  /* boundary char no longer what ⌫ deletes */

/* reEditWord: rebuild state from a word already on screen (read via ITfRange::GetText).
   Returns 1 only if the word round-trips exactly; else 0 and engine is reset. */
int vtx_seed(vtx_engine* e, const uint16_t* word, int32_t len);

#ifdef __cplusplus
}
#endif

#endif /* VIETTELEX_VTX_ENGINE_H */
