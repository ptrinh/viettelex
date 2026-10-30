// Packed sorted word set for membership-only lookups (English lists, common syllables).
// Words are grouped by length: bucket L is one string literal holding counts[L] words of
// exactly L bytes back to back, sorted bytewise — no per-word pointer/length/NUL, so the
// table costs ~1 byte per letter (an array of std::string_view costs 8 bytes per word
// on top of the text). Lookup = binary search inside the bucket of the key's length.
// The tables themselves are generated constant data (generated_tables.hpp).
#pragma once
#include <cstdint>

namespace vtx {

struct WordSet {
    int maxLen;
    const char* const* buckets; // [maxLen + 1]; bucket 0 unused
    const uint16_t* counts;     // [maxLen + 1]

    inline bool contains(const char* w, int len) const {
        if (len < 1 || len > maxLen) return false;
        const char* base = buckets[len];
        uint32_t lo = 0, hi = counts[len];
        while (lo < hi) {
            uint32_t mid = (lo + hi) / 2;
            const char* p = base + mid * static_cast<uint32_t>(len);
            int c = 0;
            for (int i = 0; i < len && c == 0; ++i)
                c = static_cast<int>(static_cast<uint8_t>(p[i])) - static_cast<int>(static_cast<uint8_t>(w[i]));
            if (c == 0) return true;
            if (c < 0) lo = mid + 1; else hi = mid;
        }
        return false;
    }
};

} // namespace vtx
