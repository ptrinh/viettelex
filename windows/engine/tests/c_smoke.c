/* C ABI smoke test: compiles as C, drives the engine like the TIP would. */
#include <stdio.h>
#include <string.h>
#include "viettelex/vtx_engine.h"

static int fails = 0;
#define EXPECT(c) do { if (!(c)) { ++fails; printf("FAIL line %d: %s\n", __LINE__, #c); } } while (0)

static int eq16(const uint16_t* a, int n, const char* ascii_or_null, const uint16_t* w, int wn) {
    int i;
    if (ascii_or_null) { if ((int)strlen(ascii_or_null) != n) return 0; for (i = 0; i < n; ++i) if (a[i] != (uint16_t)ascii_or_null[i]) return 0; return 1; }
    if (n != wn) return 0;
    for (i = 0; i < n; ++i) if (a[i] != w[i]) return 0;
    return 1;
}

int main(void) {
    vtx_engine* e = vtx_create();
    vtx_engine* c;
    vtx_action a;
    uint16_t buf[VTX_MAX_TEXT];
    int32_t n;
    const char* keys = "vieetj";
    const uint16_t viet[] = {'v', 'i', 0x1EC7, 't'};      /* việt */
    const uint16_t thay[] = {'t', 'h', 0x1EA5, 'y'};      /* thấy */
    size_t i;

    EXPECT(e != NULL);
    EXPECT(vtx_get_flags(e) == VTX_ENGINE_DEFAULT_FLAGS);
    vtx_set_flags(e, VTX_FREE_MARKING | VTX_LIVE_SPELL_CHECK | VTX_CONTEXTUAL_ENGLISH |
                     VTX_COLLISION_PREFERS_VI | VTX_ENGLISH_WORD_RESTORE);
    EXPECT(vtx_get_flags(e) == (VTX_FREE_MARKING | VTX_LIVE_SPELL_CHECK | VTX_CONTEXTUAL_ENGLISH |
                                VTX_COLLISION_PREFERS_VI | VTX_ENGLISH_WORD_RESTORE));
    for (i = 0; i < strlen(keys); ++i) vtx_feed(e, (uint32_t)keys[i], &a);
    n = vtx_composed(e, buf, VTX_MAX_TEXT);
    EXPECT(eq16(buf, n, NULL, viet, 4));
    EXPECT(a.kind == VTX_REPLACE && a.backspaces == 2 && a.insert_len == 2 && a.insert[0] == 0x1EC7);

    c = vtx_clone(e);
    n = vtx_peek_commit_text(e, 1, buf, VTX_MAX_TEXT);
    EXPECT(eq16(buf, n, NULL, viet, 4));
    n = vtx_commit_text(c, 1, buf, VTX_MAX_TEXT);
    EXPECT(eq16(buf, n, NULL, viet, 4));
    EXPECT(vtx_is_empty(c));
    vtx_destroy(c);

    vtx_commit_boundary(e, 1, &a);
    EXPECT(a.kind == VTX_NONE);
    EXPECT(vtx_can_reopen_last_commit(e));
    n = vtx_reopen_last_commit(e, buf, VTX_MAX_TEXT);
    EXPECT(eq16(buf, n, NULL, viet, 4));
    vtx_reset(e);

    /* auto-restore: "google" -> boundary rewrites back to raw */
    for (i = 0; i < 6; ++i) vtx_feed(e, (uint32_t)"google"[i], &a);
    vtx_commit_boundary(e, 1, &a);
    EXPECT(a.kind == VTX_NONE || a.kind == VTX_REPLACE);
    vtx_backspace(e, &a);
    EXPECT(a.kind == VTX_PASSTHROUGH);

    EXPECT(vtx_seed(e, thay, 4) == 1);
    n = vtx_raw_keystrokes(e, buf, VTX_MAX_TEXT);
    EXPECT(eq16(buf, n, "thaays", NULL, 0));
    vtx_feed(e, 0x00E9, &a);
    EXPECT(a.kind == VTX_PASSTHROUGH);
    EXPECT(!vtx_is_overflowed(e));
    vtx_reset_context(e);
    EXPECT(!vtx_previous_word_english(e));
    vtx_destroy(e);
    printf("c abi smoke: %s\n", fails ? "FAIL" : "ok");
    return fails != 0;
}
