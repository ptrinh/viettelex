/*
 * telexcore.h — C ABI of libtelexcore (the VietTelex TelexCore engine).
 *
 * One vt_engine per input context. Not thread-safe per handle (use a handle from one
 * thread at a time); distinct handles are independent. No allocation on the hot path:
 * results come back in caller-owned structs/buffers.
 *
 * String buffers (vt_peek, vt_composed, …) follow snprintf semantics: at most cap-1
 * bytes of UTF-8 plus a NUL are written, and the FULL byte length is returned, so a
 * return value >= cap means the output was truncated.
 */
#ifndef VIETTELEX_TELEXCORE_H
#define VIETTELEX_TELEXCORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VT_ABI_VERSION 1

typedef struct vt_engine vt_engine;

/* TelexAction */
enum {
    VT_ACTION_PASSTHROUGH = 0, /* not handled: the caller/app inserts the key itself   */
    VT_ACTION_REPLACE = 1,     /* delete `backspaces` chars before the caret, insert … */
    VT_ACTION_NONE = 2         /* nothing to do                                         */
};

/* Longest possible insert: 32 composed scalars x 3 UTF-8 bytes = 96 (+NUL). */
#define VT_INSERT_CAP 128

typedef struct vt_action {
    int32_t kind;              /* VT_ACTION_*                                          */
    int32_t backspaces;        /* REPLACE only: characters (Unicode scalars) to delete */
    int32_t insert_len;        /* REPLACE only: bytes in `insert` (excluding NUL)      */
    char insert[VT_INSERT_CAP]; /* REPLACE only: UTF-8, NUL-terminated                 */
} vt_action;

/* Engine options (TelexEngine properties). Defaults are the ENGINE defaults, which
 * differ from the app defaults (see linux/common/SETTINGS.md): frontends set all. */
enum {
    VT_FLAG_FREE_MARKING = 0,                 /* default false */
    VT_FLAG_MODERN_TONE = 1,                  /* default false */
    VT_FLAG_LIVE_SPELL_CHECK = 2,             /* default false */
    VT_FLAG_SIMPLE_TELEX = 3,                 /* default false */
    VT_FLAG_TEENCODE = 4,                     /* default TRUE  */
    VT_FLAG_QUICK_TELEX = 5,                  /* default false */
    VT_FLAG_BRACKET_VOWELS = 6,               /* default false */
    VT_FLAG_VNI = 7,                          /* default false */
    VT_FLAG_CONTEXTUAL_ENGLISH = 8,           /* default false */
    VT_FLAG_ENGLISH_WORD_RESTORE = 9,         /* default TRUE  */
    VT_FLAG_COLLISION_PREFERS_VIETNAMESE = 10 /* default false */
};

/* Lifecycle */
vt_engine *vt_engine_new(void);
void vt_engine_free(vt_engine *h);
int vt_abi_version(void);

/* Options; unknown flag ids are ignored / read false. */
void vt_engine_set_flag(vt_engine *h, int flag, bool on);
bool vt_engine_get_flag(const vt_engine *h, int flag);

/* Editing. `ch` is a Unicode scalar; non-composing characters return PASSTHROUGH
 * (route them through vt_commit first, as boundaries). */
void vt_feed(vt_engine *h, uint32_t ch, vt_action *out);
void vt_backspace(vt_engine *h, vt_action *out);
/* commitBoundary(autoRestore:) — resets the word; the caller inserts the boundary. */
void vt_commit(vt_engine *h, bool auto_restore, vt_action *out);
/* commitText(autoRestore:) — final text of the word (restore applied); resets. */
size_t vt_commit_text(vt_engine *h, bool auto_restore, char *buf, size_t cap);
/* peekCommitText(autoRestore:) — what vt_commit_text WOULD return; no state change. */
size_t vt_peek(const vt_engine *h, bool auto_restore, char *buf, size_t cap);

size_t vt_composed(const vt_engine *h, char *buf, size_t cap);
size_t vt_raw(const vt_engine *h, char *buf, size_t cap);

void vt_reset(vt_engine *h);          /* drop word + re-open snapshot              */
void vt_reset_context(vt_engine *h);  /* forget previous-word English context      */
void vt_forget_last_commit(vt_engine *h);

/* seed(word): rebuild state from on-screen text (re-edit). True if it round-trips. */
bool vt_seed(vt_engine *h, const char *utf8_word);
/* reopenLastCommit(): returns byte length of the reopened word written to buf, or -1
 * when there was nothing to reopen. */
long vt_reopen(vt_engine *h, char *buf, size_t cap);

bool vt_is_empty(const vt_engine *h);
bool vt_is_overflowed(const vt_engine *h);
bool vt_can_reopen(const vt_engine *h);
bool vt_previous_word_english(const vt_engine *h);

#ifdef __cplusplus
}
#endif

#endif /* VIETTELEX_TELEXCORE_H */
