// surrounding_cache.h — one surrounding-text read per frontend callback.
//
// IBus: every ibus_engine_get_surrounding_text() emits a RequireSurroundingText D-Bus signal
// and returns a NEW reference to the IBusText (IBus 1.5.26 … main: `*text =
// g_object_ref (priv->surrounding_text)`), and the Session asks 3–5 times per key in
// Surrounding mode. Within one engine callback the answer cannot change (the client's next
// SetSurroundingText is dispatched by the main loop after we return), so the frontend reads
// once and serves the copy (until the frontend itself edits the text: invalidate()).
#pragma once

#include <functional>
#include <string>
#include <utility>

namespace viettelex {

struct SurroundingSnapshot {
    std::string text;  // UTF-8
    unsigned cursor = 0, anchor = 0;  // characters
};

class SurroundingCache {
public:
    // fetch: fills the snapshot, false = nothing reported. Called at most once.
    using Fetch = std::function<bool(SurroundingSnapshot &)>;
    explicit SurroundingCache(Fetch fetch) : fetch_(std::move(fetch)) {}
    const SurroundingSnapshot *get() {
        if (!fetched_) {
            fetched_ = true;
            ok_ = fetch_ && fetch_(snap_);
        }
        return ok_ ? &snap_ : nullptr;
    }
    // After an edit the source updates itself (IBus: ibus_engine_delete_surrounding_text
    // rewrites its local copy): read again next time.
    void invalidate() { fetched_ = ok_ = false; }

private:
    Fetch fetch_;
    SurroundingSnapshot snap_;
    bool fetched_ = false, ok_ = false;
};

}  // namespace viettelex
