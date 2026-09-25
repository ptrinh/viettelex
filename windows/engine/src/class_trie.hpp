// Flat trie over the 33-letter class alphabet (port of ClassTrie in
// TelexCore/Sources/TelexCore/SyllableValidator.swift). Node i's child for class c
// lives at next[i * 33 + c]; -1 = absent. Root = node 0. mask(node): 0 = not a full
// word; nonzero = accepting, for rime tries the bits are the ALLOWED TONES.
// The tables themselves are generated constant data (generated_tables.hpp).
#pragma once
#include <cstdint>

namespace vtx {

constexpr int kClassCount = 33;

struct ClassTrie {
    const int16_t* next;
    const uint8_t* masks;

    // A class outside the alphabet (VNI literal digits wrap to 200+) has no child.
    inline int32_t step(int32_t node, uint8_t cls) const {
        if (cls >= kClassCount) return -1;
        return next[node * kClassCount + cls];
    }
    inline uint8_t mask(int32_t node) const { return masks[node]; }
};

} // namespace vtx
