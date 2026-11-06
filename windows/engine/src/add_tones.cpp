// Port of iOS/Keyboard/AddTones.swift + SyllableLM.swift (reader, the parts Thêm dấu
// and the parity fixture use) + VNLexicon2/SwipeLexicon/SwipeEnglish loaders. Same names
// and order as the Swift source; see there for the WHY. Float/double arithmetic follows
// the Swift expressions operation by operation (parity on add-tones.txt).
#include "viettelex/add_tones.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

#include "generated_tables.hpp"
#include "tables.hpp"
#include "viettelex/text_tools.hpp"

namespace vtx { namespace addtones {

namespace {

// Portable bit helpers (no intrinsics: not on any hot path).
int popcount64(uint64_t x) {
    x = x - ((x >> 1) & 0x5555555555555555ull);
    x = (x & 0x3333333333333333ull) + ((x >> 2) & 0x3333333333333333ull);
    x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0Full;
    return static_cast<int>((x * 0x0101010101010101ull) >> 56);
}
int ctz64(uint64_t x) { return x ? popcount64((x & (~x + 1)) - 1) : 64; }
int clz64(uint64_t x) {
    if (!x) return 64;
    int n = 0;
    while (!(x & (1ull << 63))) { x <<= 1; ++n; }
    return n;
}

// selectInByte[b·8 + k] = position of the k-th set bit of byte b.
struct SelectTable {
    uint8_t t[2048];
    SelectTable() {
        std::memset(t, 0, sizeof t);
        for (int b = 0; b < 256; ++b) {
            int x = b, k = 0;
            while (x) {
                t[b << 3 | k] = static_cast<uint8_t>(ctz64(static_cast<uint64_t>(x)));
                x &= x - 1;
                ++k;
            }
        }
    }
};
const SelectTable& selectTable() {
    static const SelectTable t;
    return t;
}

// Position of the r-th (0-based) set bit of x (Vigna broadword, = SyllableLM.selectInWord).
int selectInWord(uint64_t x, int r) {
    uint64_t s = x - ((x >> 1) & 0x5555555555555555ull);
    s = (s & 0x3333333333333333ull) + ((s >> 2) & 0x3333333333333333ull);
    s = (s + (s >> 4)) & 0x0F0F0F0F0F0F0F0Full;
    const uint64_t sums = s * 0x0101010101010101ull;
    const uint64_t le = ((static_cast<uint64_t>(r) * 0x0101010101010101ull | 0x8080808080808080ull) - sums) &
                        0x8080808080808080ull;
    const int place = ctz64(~le & 0x8080808080808080ull) - 7;
    const int k = r - static_cast<int>(((sums << 8) >> place) & 0xFF);
    return place + selectTable().t[static_cast<int>((x >> place) & 0xFF) << 3 | k];
}

uint32_t rd32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) | static_cast<uint32_t>(p[1]) << 8 | static_cast<uint32_t>(p[2]) << 16 |
           static_cast<uint32_t>(p[3]) << 24;
}
uint64_t rd64(const uint8_t* p) { return static_cast<uint64_t>(rd32(p)) | static_cast<uint64_t>(rd32(p + 4)) << 32; }

int efL(int64_t n, int64_t u) { return n > 0 && u >= n ? 63 - clz64(static_cast<uint64_t>(u / n)) : 0; }

constexpr int kShortRow = 8;
constexpr int kHeaderSize = 128;
constexpr int kSectionCount = 18;
constexpr int kVersion = 3;

}  // namespace

uint32_t fnv1a(const uint8_t* p, size_t n) {
    uint32_t h = 0x811C9DC5u;
    for (size_t i = 0; i < n; ++i) h = (h ^ p[i]) * 0x01000193u;
    return h;
}

// ================================================================ Lexicon (vnlexicon.bin)

uint32_t Lexicon::u32(size_t off) const { return rd32(data_ + off); }

bool Lexicon::load(const uint8_t* d, size_t n) {
    *this = Lexicon();
    if (!d || n < 64 || std::memcmp(d, "VNL2", 4) != 0) return false;
    data_ = d;
    size_ = n;
    const uint32_t ver = u32(4), count = u32(8), sections = u32(12);
    if (ver != 1 || sections != 6 || count == 0 || count > 100000 || 16 + 6 * 8 > n) return (*this = Lexicon(), false);
    size_t base[6], len[6];
    for (int i = 0; i < 6; ++i) {
        base[i] = u32(16 + static_cast<size_t>(i) * 8);
        len[i] = u32(16 + static_cast<size_t>(i) * 8 + 4);
        if (base[i] > n || len[i] > n - base[i]) return (*this = Lexicon(), false);
    }
    if (len[2] != len[0] || len[3] != (count + 1) * 4 || len[4] != (count + 1) * 4 || len[5] != count)
        return (*this = Lexicon(), false);
    count_ = static_cast<int>(count);
    folded_ = base[0];
    display_ = base[1];
    attrs_ = base[2];
    offsets_ = base[3];
    dispOffsets_ = base[4];
    freqs_ = base[5];
    // offsets must be monotonic and inside their sections
    for (int id = 0; id < count_; ++id) {
        const uint32_t a = u32(offsets_ + static_cast<size_t>(id) * 4), b = u32(offsets_ + static_cast<size_t>(id + 1) * 4);
        const uint32_t da = u32(dispOffsets_ + static_cast<size_t>(id) * 4), db = u32(dispOffsets_ + static_cast<size_t>(id + 1) * 4);
        if (a > b || b > len[0] || da > db || db > len[1]) return (*this = Lexicon(), false);
    }
    hash_ = fnv1a(d, n);
    // SwipeLexicon.forms: consecutive ids with the same folded key form one form
    std::string_view prev;
    size_t forms = 0;
    for (int pass = 0; pass < 2; ++pass) {  // count, then fill an exactly sized vector
        if (pass == 1) formStart_.reserve(forms + 1);
        for (int id = 0; id < count_; ++id) {
            const std::string_view f = folded(id);
            if (id > 0 && f == prev) continue;
            prev = f;
            if (pass == 0) ++forms;
            else formStart_.push_back(id);
        }
    }
    formStart_.push_back(count_);
    return true;
}

std::string_view Lexicon::display(int id) const {
    if (!data_ || id < 0 || id >= count_) return {};
    const uint32_t lo = id == 0 ? 0 : u32(dispOffsets_ + static_cast<size_t>(id) * 4);
    const uint32_t hi = u32(dispOffsets_ + static_cast<size_t>(id + 1) * 4);
    return std::string_view(reinterpret_cast<const char*>(data_ + display_ + lo), hi - lo);
}

std::string_view Lexicon::folded(int id) const {
    if (!data_ || id < 0 || id >= count_) return {};
    const uint32_t a = u32(offsets_ + static_cast<size_t>(id) * 4), b = u32(offsets_ + static_cast<size_t>(id + 1) * 4);
    return std::string_view(reinterpret_cast<const char*>(data_ + folded_ + a), b - a);
}

uint8_t Lexicon::attr(int id, int i) const {
    if (!data_ || id < 0 || id >= count_ || i < 0) return 0;
    const uint32_t a = u32(offsets_ + static_cast<size_t>(id) * 4), b = u32(offsets_ + static_cast<size_t>(id + 1) * 4);
    if (static_cast<uint32_t>(i) >= b - a) return 0;
    return data_[attrs_ + a + static_cast<uint32_t>(i)];
}

int Lexicon::formIndex(std::string_view key) const {
    int lo = 0, hi = formCount();  // forms are sorted (the file is sorted by folded key)
    while (lo < hi) {
        const int mid = lo + (hi - lo) / 2;
        if (folded(formStart_[static_cast<size_t>(mid)]) < key) lo = mid + 1;
        else hi = mid;
    }
    return (lo < formCount() && folded(formStart_[static_cast<size_t>(lo)]) == key) ? lo : -1;
}

// ================================================================ English (enlexicon.bin)

bool EnglishLexicon::load(const uint8_t* b, size_t n) {
    data_ = nullptr;
    offs_ = std::vector<uint32_t>();
    if (!b || n < 8 || n > 0xFFFFFFFFu || std::memcmp(b, "VTE1", 4) != 0) return false;
    const uint32_t count = rd32(b + 4);
    if (count > (n - 8) / 3) return false;  // every record is ≥ 3 bytes
    auto fail = [this] {
        offs_ = std::vector<uint32_t>();
        return false;
    };
    size_t p = 8;
    offs_.reserve(count);
    for (uint32_t i = 0; i < count; ++i) {
        if (p + 2 > n) return fail();
        const size_t len = b[p];
        if (len == 0 || p + 2 + len > n) return fail();
        for (size_t j = 0; j < len; ++j)
            if (b[p + 2 + j] < 'a' || b[p + 2 + j] > 'z') return fail();
        offs_.push_back(static_cast<uint32_t>(p));
        p += 2 + len;
    }
    data_ = b;
    auto less = [this](uint32_t x, uint32_t y) {
        return std::string_view(reinterpret_cast<const char*>(data_ + x + 2), data_[x]) <
               std::string_view(reinterpret_cast<const char*>(data_ + y + 2), data_[y]);
    };
    if (!std::is_sorted(offs_.begin(), offs_.end(), less)) std::sort(offs_.begin(), offs_.end(), less);
    return true;
}

bool EnglishLexicon::contains(std::string_view w) const {
    const size_t i = lowerBound(w);
    return i < offs_.size() && word(i) == w;
}

size_t EnglishLexicon::lowerBound(std::string_view w) const {
    size_t lo = 0, hi = offs_.size();
    while (lo < hi) {
        const size_t mid = lo + (hi - lo) / 2;
        if (word(mid) < w) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

// ================================================================ SyllableLM (vnlm.bin v3)

uint64_t SyllableLM::u64(int base, int64_t wi) const { return rd64(d_ + base + (wi << 3)); }
int SyllableLM::u32At(int base, int64_t i) const { return static_cast<int>(rd32(d_ + base + (i << 2))); }

int SyllableLM::bits(int base, int64_t pos, int width) const {
    const int64_t wi = pos >> 6;
    const int sh = static_cast<int>(pos & 63);
    uint64_t v = u64(base, wi) >> sh;
    if (sh + width > 64) v |= u64(base, wi + 1) << (64 - sh);
    return static_cast<int>(v & ((uint64_t{1} << width) - 1));
}

bool SyllableLM::bit(int base, int64_t p) const { return ((d_[base + (p >> 3)] >> (p & 7)) & 1) != 0; }

int SyllableLM::select0(const EF& e, int64_t r) const {
    const int64_t t = r >> e.selShift;
    const int p = u32At(e.sel, t);
    int64_t k = r - (t << e.selShift);
    if (k == 0) return p;
    int64_t wi = (static_cast<int64_t>(p) + 1) >> 6;
    if (wi >= e.words) return e.words << 6;
    uint64_t w = ~u64(e.high, wi) & (~uint64_t{0} << ((p + 1) & 63));
    while (true) {
        const int c = popcount64(w);
        if (c >= k) break;
        k -= c;
        ++wi;
        if (wi >= e.words) return e.words << 6;
        w = ~u64(e.high, wi);
    }
    return static_cast<int>((wi << 6) + selectInWord(w, static_cast<int>(k - 1)));
}

void SyllableLM::bucket(const EF& e, int64_t h, int64_t& pos, int64_t& idx) const {
    if (h == 0) { pos = 0; idx = 0; return; }
    const int64_t z = select0(e, h - 1);
    pos = z + 1;
    idx = z + 1 - h;
}

int SyllableLM::runLength(const EF& e, int64_t pos) const {
    int64_t wi = pos >> 6;
    int sh = static_cast<int>(pos & 63), n = 0;
    while (wi < e.words) {
        const int ones = ctz64(~(u64(e.high, wi) >> sh));
        if (ones < 64 - sh) return n + ones;
        n += 64 - sh;
        ++wi;
        sh = 0;
    }
    return n;
}

int SyllableLM::find(const EF& e, int64_t x) const {
    int64_t pos, idx;
    bucket(e, x >> e.l, pos, idx);
    const int64_t t = x & e.mask();
    int64_t lo = idx, hi = idx + runLength(e, pos);
    while (lo < hi) {
        const int64_t m = (lo + hi) >> 1;
        const int v = low(e, static_cast<int>(m));
        if (v < t) lo = m + 1;
        else if (v > t) hi = m;
        else return static_cast<int>(m);
    }
    return -1;
}

void SyllableLM::lowerBound(const EF& e, int64_t x, int64_t& outIdx, int64_t& outPos) const {
    int64_t pos, idx;
    bucket(e, x >> e.l, pos, idx);
    const int64_t t = x & e.mask();
    int64_t lo = idx, hi = idx + runLength(e, pos);
    while (lo < hi) {
        const int64_t m = (lo + hi) >> 1;
        if (low(e, static_cast<int>(m)) < t) lo = m + 1;
        else hi = m;
    }
    outIdx = lo;
    outPos = pos + lo - idx;
}

int SyllableLM::scanFind(const EF& e, int64_t lo, int64_t pos, int64_t x) const {
    int64_t wi = pos >> 6;
    uint64_t w = u64(e.high, wi) & (~uint64_t{0} << (pos & 63));
    int64_t m = lo;
    const int64_t end = std::min<int64_t>(e.n, lo + kShortRow);
    while (m < end) {
        while (w == 0) {
            ++wi;
            if (wi >= e.words) return -1;
            w = u64(e.high, wi);
        }
        const int64_t k = (((wi << 6) + ctz64(w) - m) << e.l) | low(e, static_cast<int>(m));
        if (k >= x) return k == x ? static_cast<int>(m) : -1;
        w &= w - 1;
        ++m;
    }
    return m < e.n ? find(e, x) : -1;
}

template <class F>
void SyllableLM::scan(const EF& e, int lo, int64_t pos, int n, F&& body) const {
    if (n <= 0) return;
    int64_t wi = pos >> 6;
    uint64_t w = u64(e.high, wi) & (~uint64_t{0} << (pos & 63));
    for (int m = lo; m < lo + n; ++m) {
        while (w == 0) {
            ++wi;
            if (wi >= e.words) return;
            w = u64(e.high, wi);
        }
        body(m, (((wi << 6) + ctz64(w) - m) << e.l) | low(e, m));
        w &= w - 1;
    }
}

SyllableLM::Row SyllableLM::rowAt(int b) const {
    Row r;
    r.lo = u32At(biRow_, b);
    r.hi = u32At(biRow_, b + 1);
    r.l = efL(r.hi - r.lo, count_);
    r.zero = u32At(biZero_, b);
    r.lowOff = u32At(biLowOff_, b);
    return r;
}

template <class F>
void SyllableLM::biScan(const Row& r, F&& body) const {
    if (r.lo >= r.hi) return;
    const int64_t start = r.start();
    int64_t wi = start >> 6;
    uint64_t w = u64(bi_.high, wi) & (~uint64_t{0} << (start & 63));
    const int l = r.l;
    const uint64_t mask = (uint64_t{1} << l) - 1;
    int64_t li = r.lowOff >> 6;
    uint64_t lb = u64(biLow_, li) >> (r.lowOff & 63);
    int la = 64 - (r.lowOff & 63);
    for (int m = r.lo; m < r.hi; ++m) {
        while (w == 0) {
            ++wi;
            if (wi >= bi_.words) return;
            w = u64(bi_.high, wi);
        }
        uint64_t v;
        if (la >= l) {
            v = lb & mask;
            lb = l < 64 ? lb >> l : 0;
            la -= l;
        } else {
            ++li;
            const uint64_t nx = u64(biLow_, li);
            v = (lb | nx << la) & mask;
            lb = nx >> (l - la);
            la += 64 - l;
        }
        body(m, static_cast<int>((((wi << 6) + ctz64(w) - start - (m - r.lo)) << l) | static_cast<int64_t>(v)));
        w &= w - 1;
    }
}

int SyllableLM::biFind(const Row& r, int c) const {
    const int n = r.hi - r.lo;
    if (n == 0) return -1;
    if (n <= kShortRow) {
        const int64_t start = r.start();
        int64_t wi = start >> 6;
        uint64_t w = u64(bi_.high, wi) & (~uint64_t{0} << (start & 63));
        for (int m = r.lo; m < r.hi; ++m) {
            while (w == 0) {
                ++wi;
                if (wi >= bi_.words) return -1;
                w = u64(bi_.high, wi);
            }
            const int64_t k = (((wi << 6) + ctz64(w) - start - (m - r.lo)) << r.l) | rowLow(r, m);
            if (k >= c) return k == c ? m : -1;
            w &= w - 1;
        }
        return -1;
    }
    const int64_t h = static_cast<int64_t>(c) >> r.l, t = c & ((int64_t{1} << r.l) - 1);
    int64_t pos = r.start(), idx = r.lo;
    if (h > 0) {
        const int64_t z = r.zero + h - 1;
        pos = static_cast<int64_t>(select0(bi_, z)) + 1;
        idx = pos - z - 1;
    }
    if ((pos >> 6) >= bi_.words) return -1;
    uint64_t w = u64(bi_.high, pos >> 6) >> (pos & 63);
    while (w & 1) {
        const int v = rowLow(r, static_cast<int>(idx));
        if (v >= t) return v == t ? static_cast<int>(idx) : -1;
        ++pos;
        ++idx;
        if ((pos & 63) == 0) {
            if ((pos >> 6) >= bi_.words) return -1;
            w = u64(bi_.high, pos >> 6);
        } else {
            w >>= 1;
        }
    }
    return -1;
}

int SyllableLM::context(int j) const {
    if (!bit(hasTri_, j)) return -1;
    return u32At(triRank_, j >> 6) + popcount64(u64(hasTri_, j >> 6) & ((uint64_t{1} << (j & 63)) - 1));
}

float SyllableLM::Bigram::pmi(int next) const {
    if (!lm_ || size() <= 0 || next < 0 || next >= lm_->count_) return 0;
    const int j = lm_->biFind(row_, next);
    return (j >= 0 ? lm_->biScoreAt(j) : g2_) + lm_->adj(next);
}

float SyllableLM::Bigram::explicitPmi(int next) const {
    if (!lm_ || size() <= 0 || next < 0 || next >= lm_->count_) return 0;
    const int j = lm_->biFind(row_, next);
    return j >= 0 ? lm_->biScoreAt(j) + lm_->adj(next) : 0;
}

SyllableLM::Bigram SyllableLM::bigram(int prev) const {
    Bigram b;
    if (!d_ || prev < 0 || prev >= count_) return b;
    b.lm_ = this;
    b.g2_ = q(static_cast<int8_t>(d_[g2Base_ + prev]));
    b.row_ = rowAt(prev);
    return b;
}

float SyllableLM::score(int prev2, int prev1, int w) const {
    if (!d_ || prev1 < 0 || prev1 >= count_) return 0;
    if (w < 0 || w >= count_) return 0;
    const float g2 = q(static_cast<int8_t>(d_[g2Base_ + prev1]));
    int k = -1;
    if (prev2 >= 0 && prev2 < count_) {
        const int j = biFind(rowAt(prev2), prev1);
        if (j >= 0) k = context(j);
    }
    const Row row = rowAt(prev1);
    if (k >= 0) {
        const int64_t triBase = static_cast<int64_t>(k) * count_;
        int64_t lo, pos;
        lowerBound(tri_, triBase, lo, pos);
        const float g3 = q(cbValue(cbgBase_, g3Base_, k, bitsG_));
        const int t = scanFind(tri_, lo, pos, triBase + w);
        if (t >= 0) return q(cbValue(cb3Base_, triScore_, t, bits3_));
        const int j = biFind(row, w);
        const float s2 = j >= 0 ? biScoreAt(j) : g2;
        return g3 + s2;
    }
    const int j = biFind(row, w);
    return j >= 0 ? biScoreAt(j) : g2;
}

// ---------------------------------------------------------------- Context (word prediction)

void SyllableLM::Bigram::forEachImpl(NextFn fn, void* ctx) const {
    if (!lm_ || size() <= 0) return;
    const SyllableLM* lm = lm_;
    lm->biScan(row_, [&](int m, int c) { fn(ctx, c, lm->biScoreAt(m) + lm->adj(c)); });
}

SyllableLM::TriCursor SyllableLM::triStart(int64_t lo, int64_t pos, int64_t base) const {
    TriCursor t;
    t.m = lo;
    t.base = base;
    t.end = base + count_;
    t.wi = pos >> 6;
    if (t.wi >= tri_.words) return t;
    t.w = u64(tri_.high, t.wi) & (~uint64_t{0} << (pos & 63));
    triNext(t);
    return t;
}

void SyllableLM::triNext(TriCursor& t) const {
    t.c = kEnd;
    if (t.m >= tri_.n) return;
    while (t.w == 0) {
        ++t.wi;
        if (t.wi >= tri_.words) return;
        t.w = u64(tri_.high, t.wi);
    }
    const int64_t k = (((t.wi << 6) + ctz64(t.w) - t.m) << tri_.l) | low(tri_, static_cast<int>(t.m));
    if (k >= t.end) return;
    t.c = static_cast<int>(k - t.base);
    t.v = q(cbValue(cb3Base_, triScore_, t.m, bits3_));
    t.w &= t.w - 1;
    ++t.m;
}

bool SyllableLM::context(int prev2, int prev1, Context& out) const {
    out = Context();
    if (!d_ || prev1 < 0 || prev1 >= count_) return false;
    out.lm_ = this;
    out.g2_ = q(static_cast<int8_t>(d_[g2Base_ + prev1]));
    int k = -1;
    if (prev2 >= 0 && prev2 < count_) {
        const int j = biFind(rowAt(prev2), prev1);
        if (j >= 0) k = context(j);
    }
    out.bi_ = rowAt(prev1);
    if (k < 0) return true;
    out.triBase_ = static_cast<int64_t>(k) * count_;
    lowerBound(tri_, out.triBase_, out.triLo_, out.triPos_);
    out.g3_ = q(cbValue(cbgBase_, g3Base_, k, bitsG_));
    return true;
}

bool SyllableLM::Context::trigramPmi(int w, float& pmi) const {
    if (!lm_ || triBase_ < 0 || w < 0 || w >= lm_->count_) return false;
    const int t = lm_->scanFind(lm_->tri_, triLo_, triPos_, triBase_ + w);
    if (t < 0) return false;
    pmi = lm_->q(lm_->cbValue(lm_->cb3Base_, lm_->triScore_, t, lm_->bits3_)) + lm_->adj(w);
    return true;
}

float SyllableLM::Context::explicitPmi(int w) const {
    if (!lm_ || w < 0 || w >= lm_->count_) return 0;
    if (triBase_ >= 0) {
        const int t = lm_->scanFind(lm_->tri_, triLo_, triPos_, triBase_ + w);
        if (t >= 0) return lm_->q(lm_->cbValue(lm_->cb3Base_, lm_->triScore_, t, lm_->bits3_)) + lm_->adj(w);
    }
    const int j = lm_->biFind(bi_, w);
    return j >= 0 ? lm_->biScoreAt(j) + lm_->adj(w) : 0;
}

int SyllableLM::Context::forEachTrigramImpl(NextFn fn, void* ctx) const {
    if (!lm_ || triBase_ < 0) return 0;
    TriCursor t = lm_->triStart(triLo_, triPos_, triBase_);
    int n = 0;
    while (t.c != kEnd) {
        fn(ctx, t.c, t.v + lm_->adj(t.c));
        ++n;
        lm_->triNext(t);
    }
    return n;
}

void SyllableLM::Context::forEachNextImpl(NextFn fn, void* ctx) const {
    if (!lm_) return;
    const SyllableLM* lm = lm_;
    TriCursor t;
    if (triBase_ >= 0) t = lm->triStart(triLo_, triPos_, triBase_);
    const float back = triBase_ >= 0 ? g3_ : 0;
    lm->biScan(bi_, [&](int m, int c) {
        while (t.c < c) {
            fn(ctx, t.c, t.v + lm->adj(t.c));
            lm->triNext(t);
        }
        if (t.c == c) {
            fn(ctx, c, t.v + lm->adj(c));
            lm->triNext(t);
        } else {
            fn(ctx, c, back + lm->biScoreAt(m) + lm->adj(c));
        }
    });
    while (t.c != kEnd) {
        fn(ctx, t.c, t.v + lm->adj(t.c));
        lm->triNext(t);
    }
}

float SyllableLM::uniAdj(int w) const { return (!d_ || w < 0 || w >= count_) ? 0 : adj(w); }

uint32_t SyllableLM::modelChecksum() const {
    if (!d_) return 0;
    uint32_t h = 0x811C9DC5u;
    auto mix = [&h](int64_t b) { h = (h ^ static_cast<uint8_t>(b & 0xFF)) * 0x01000193u; };
    auto mix32 = [&mix](int64_t v) { for (int s = 0; s < 32; s += 8) mix(v >> s); };
    for (int b = 0; b < count_; ++b) {
        biScan(rowAt(b), [&](int j, int c) {
            mix32(static_cast<int64_t>(b) * count_ + c);
            mix(d_[biScore_ + j]);
            mix(bit(hasTri_, j) ? 1 : 0);
        });
    }
    for (int k = 0; k < triContexts_; ++k) mix(cbValue(cbgBase_, g3Base_, k, bitsG_));
    scan(tri_, 0, 0, triEntries_, [&](int t, int64_t key) {
        mix32(key);
        mix(cbValue(cb3Base_, triScore_, t, bits3_));
    });
    return h;
}

bool SyllableLM::payloadHashOK() const {
    return d_ && rd32(d_ + 40) == fnv1a(d_ + kHeaderSize, size_ - kHeaderSize);
}

bool SyllableLM::load(const uint8_t* d, size_t size, uint32_t lexiconHash, int lexiconCount) {
    *this = SyllableLM();
    if (!d || size < static_cast<size_t>(kHeaderSize) || size > 0x7FFFFFFF || std::memcmp(d, "VNM1", 4) != 0) return false;
    auto u32 = [d](int off) { return static_cast<int64_t>(rd32(d + off)); };
    if (u32(4) != kVersion || u32(8) != lexiconCount || static_cast<uint32_t>(u32(12)) != lexiconHash || u32(16) <= 0)
        return false;
    int64_t off[kSectionCount + 1];
    for (int i = 0; i <= kSectionCount; ++i) off[i] = u32(48 + i * 4);
    const int64_t n = lexiconCount, nb = u32(20), nk = u32(24), nt = u32(28);
    const int tL = d[32], b3 = d[34], bg = d[35], bs = d[36], ts = d[37];
    if (!(tL < 32 && d[33] == 8 && b3 >= 1 && b3 <= 8 && bg >= 1 && bg <= 8 && bs >= 1 && bs <= 16 && ts >= 1 &&
          ts <= 16))
        return false;
    if (tL != efL(nt, nk * n) || off[kSectionCount] != static_cast<int64_t>(size) || off[0] != kHeaderSize) return false;
    for (int i = 0; i < kSectionCount; ++i)
        if (off[i] > off[i + 1]) return false;
    if (off[7] - off[4] < 3 * (n + 1) * 4) return false;
    const int64_t rowEnd = u32(static_cast<int>(off[4] + n * 4)), zeroEnd = u32(static_cast<int>(off[5] + n * 4)),
                  lowEnd = u32(static_cast<int>(off[6] + n * 4));
    auto pad = [](int64_t bytes) { return ((bytes + 7) & ~int64_t{7}) + 8; };
    auto sel = [&pad](int64_t zeros, int s) { return pad(zeros > 0 ? (((zeros - 1) >> s) + 1) * 4 : 0); };
    const int64_t tz = ((nk * n) >> tL) + 1;
    const int64_t want[kSectionCount] = {pad(n),
                                         pad(n),
                                         pad(int64_t{1} << b3),
                                         pad(int64_t{1} << bg),
                                         pad((n + 1) * 4),
                                         pad((n + 1) * 4),
                                         pad((n + 1) * 4),
                                         pad((lowEnd + 7) / 8),
                                         pad((nb + zeroEnd + 7) / 8),
                                         sel(zeroEnd, bs),
                                         pad(nb),
                                         pad((nb + 7) / 8),
                                         pad(((nb >> 6) + 1) * 4),
                                         pad((nk * bg + 7) / 8),
                                         pad((nt * tL + 7) / 8),
                                         pad((nt + tz + 7) / 8),
                                         sel(tz, ts),
                                         pad((nt * b3 + 7) / 8)};
    if (rowEnd != nb) return false;
    for (int i = 0; i < kSectionCount; ++i)
        if (off[i + 1] - off[i] != want[i]) return false;

    d_ = d;
    size_ = size;
    count_ = lexiconCount;
    qPerNat_ = static_cast<float>(u32(16));
    biEntries_ = static_cast<int>(nb);
    triContexts_ = static_cast<int>(nk);
    triEntries_ = static_cast<int>(nt);
    bits3_ = b3;
    bitsG_ = bg;
    g2Base_ = static_cast<int>(off[0]);
    adjBase_ = static_cast<int>(off[1]);
    cb3Base_ = static_cast<int>(off[2]);
    cbgBase_ = static_cast<int>(off[3]);
    biRow_ = static_cast<int>(off[4]);
    biZero_ = static_cast<int>(off[5]);
    biLowOff_ = static_cast<int>(off[6]);
    biLow_ = static_cast<int>(off[7]);
    bi_ = EF{biEntries_, 0, static_cast<int>(off[7]), static_cast<int>(off[8]), static_cast<int>(off[9]),
             static_cast<int>((off[9] - off[8]) / 8), bs};
    biScore_ = static_cast<int>(off[10]);
    hasTri_ = static_cast<int>(off[11]);
    triRank_ = static_cast<int>(off[12]);
    g3Base_ = static_cast<int>(off[13]);
    tri_ = EF{triEntries_, tL, static_cast<int>(off[14]), static_cast<int>(off[15]), static_cast<int>(off[16]),
              static_cast<int>((off[16] - off[15]) / 8), ts};
    triScore_ = static_cast<int>(off[17]);
    return true;
}

// ================================================================ LanguageData

bool LanguageData::load(const uint8_t* vl, size_t vln, const uint8_t* el, size_t eln, const uint8_t* lm_, size_t lmn) {
    if (!lexicon.load(vl, vln)) return false;
    english.load(el, eln);  // optional
    lm.load(lm_, lmn, lexicon.hash(), lexicon.count());  // optional
    return true;
}

// ================================================================ AddTones.restore

namespace {

const std::u32string kPunct = U".,;:!?\"'()[]{}…“”‘’-–—«»";

bool isWs(char32_t c) { return c == U' ' || c == U'\t' || c == U'\n' || c == U'\r' || c == 0x00A0; }
bool isAsciiLetter(char32_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
bool isUpperAscii(char32_t c) { return c >= 'A' && c <= 'Z'; }
bool isPunct(char32_t c) { return kPunct.find(c) != std::u32string::npos; }

// ---- CuratedPairs (twin of iOS/Keyboard/CuratedPairs.swift; data generated) ----
#include "curated_pairs.inc"

template <size_t N>
bool sortedContains(const char* const (&keys)[N], const std::string& k) {
    const char* const* it = std::lower_bound(keys, keys + N, k.c_str(),
                                             [](const char* a, const char* b) { return std::strcmp(a, b) < 0; });
    return it != keys + N && k == *it;
}
/// (x, a → b) in the table: pair "a b", or triple "x a b" when x is known.
bool curatedHas(const std::string* x, const std::string& a, const std::string& b) {
    if (sortedContains(kCuratedPairs, a + " " + b)) return true;
    return x && sortedContains(kCuratedTriples, *x + " " + a + " " + b);
}
/// Some triple starts with (x, a).
bool curatedHasTriple(const std::string& x, const std::string& a) {
    const std::string h = x + " " + a + " ";
    const char* const* end = kCuratedTriples + sizeof(kCuratedTriples) / sizeof(kCuratedTriples[0]);
    const char* const* it = std::lower_bound(kCuratedTriples, end, h.c_str(),
                                             [](const char* l, const char* r) { return std::strcmp(l, r) < 0; });
    return it != end && std::strncmp(*it, h.c_str(), h.size()) == 0;
}
/// Pair term (a → b): no personal model here ⇒ curatedW when `on` and in the table, else 0
/// (= Swift pairTerm with personal == nil).
double pairTerm(const Params& p, bool on, const std::string* x, const std::string& a, const std::string& b) {
    return on && curatedHas(x, a, b) ? p.curatedW : 0.0;
}

bool opensEnglishRun(const std::string& w) {
    return tables::contains(gen::kEnglishContextWords, w.data(), static_cast<int>(w.size()));
}
bool isNeutralLoanword(const std::string& w) {
    return tables::contains(gen::kNeutralLoanwords, w.data(), static_cast<int>(w.size()));
}

struct Tok {
    int start = 0, end = 0;
    std::string word;  // lowercase ascii
    bool breakBefore = false, breakAfter = false;
    int form = -1;
    bool english = false, ambiguous = false, keep = false;
    bool valid = false;  // false = chunk kept as is (breaks the bigram chain)
};

std::vector<Tok> tokenize(const std::u32string& s) {
    std::vector<Tok> out;
    const int n = static_cast<int>(s.size());
    int i = 0;
    while (i < n) {
        if (isWs(s[static_cast<size_t>(i)])) { ++i; continue; }
        int j = i;
        while (j < n && !isWs(s[static_cast<size_t>(j)])) ++j;
        int a = i, b = j;
        while (a < b && !isAsciiLetter(s[static_cast<size_t>(a)])) ++a;
        while (b > a && !isAsciiLetter(s[static_cast<size_t>(b - 1)])) --b;
        bool ok = a < b;
        for (int k = i; ok && k < a; ++k) ok = isPunct(s[static_cast<size_t>(k)]);
        for (int k = b; ok && k < j; ++k) ok = isPunct(s[static_cast<size_t>(k)]);
        for (int k = a; ok && k < b; ++k) ok = isAsciiLetter(s[static_cast<size_t>(k)]);
        if (!ok) { out.emplace_back(); i = j; continue; }
        bool upperInside = false, allUpper = true;
        for (int k = a; k < b; ++k) {
            const bool up = isUpperAscii(s[static_cast<size_t>(k)]);
            if (k > a && up) upperInside = true;
            if (!up) allUpper = false;
        }
        if (upperInside && !allUpper) { out.emplace_back(); i = j; continue; }
        Tok t;
        t.valid = true;
        t.start = a;
        t.end = b;
        for (int k = a; k < b; ++k) {
            char c = static_cast<char>(s[static_cast<size_t>(k)]);
            t.word.push_back(c >= 'A' && c <= 'Z' ? static_cast<char>(c + 32) : c);
        }
        t.breakBefore = a > i;
        t.breakAfter = b < j;
        out.push_back(std::move(t));
        i = j;
    }
    return out;
}

void classify(std::vector<Tok>& toks, const LanguageData& d) {
    for (Tok& t : toks) {
        if (!t.valid) continue;
        t.form = d.lexicon.formIndex(t.word);
        const bool en = d.english.contains(t.word) || opensEnglishRun(t.word);
        if (t.form < 0) {
            t.keep = true;
            t.english = en && !isNeutralLoanword(t.word);
        } else if (en) {
            t.ambiguous = true;
        }
    }
    bool changed = true;
    while (changed) {
        changed = false;
        for (size_t k = 0; k < toks.size(); ++k) {
            Tok& t = toks[k];
            if (!t.valid || !t.ambiguous || t.keep) continue;
            const Tok* p = nullptr;
            if (k > 0 && !t.breakBefore && toks[k - 1].valid && !toks[k - 1].breakAfter) p = &toks[k - 1];
            const Tok* q = nullptr;
            if (k + 1 < toks.size() && !t.breakAfter && toks[k + 1].valid && !toks[k + 1].breakBefore) q = &toks[k + 1];
            if ((p && p->english) || (q && q->english)) {
                t.keep = true;
                t.english = true;
                changed = true;
            }
        }
    }
}

// Second-order Viterbi (AddTones.viterbi3 — twin of the Swift / Kotlin code, keep identical).
// State = (candidate r at i−1, candidate s at i):
//   S1[r][s] = emit0[r] + tr(·, r, s) + emit1[s]
//   Si[r][s] = max_q S(i−1)[q][r] + tr(q, r, s) + emit_i[s]   (ties → smallest q)
// tr(q, r, s) = bigramW·max(floor, pmi): pmi = the EXPLICIT trigram entry (q, r, s) of vnlm.bin
// (s3 + uniAdj) when there is one, else the bigram PMI(r → s) as in the first-order path (no γ3
// back-off penalty — measured worse on the dev set); 0 when r has no bigram row and no trigram.
void viterbi3(const std::vector<std::vector<int>>& ids, const std::vector<std::vector<std::u32string>>& words,
              const std::vector<std::vector<std::string>>& w8, int from, const LanguageData& d, const Params& p,
              std::vector<std::u32string>& chosen, std::vector<bool>& hasChoice) {
    const int n = static_cast<int>(ids.size());
    const bool on = p.curated;
    // pair terms between positions i−1 and i (curated, no triple context): pers[r·kc + s]
    std::vector<double> pers;
    auto pairs = [&](int i) {
        const auto& a = w8[static_cast<size_t>(i - 1)];
        const auto& b = w8[static_cast<size_t>(i)];
        pers.assign(a.size() * b.size(), 0.0);
        for (size_t r = 0; r < a.size(); ++r)
            for (size_t s = 0; s < b.size(); ++s) pers[r * b.size() + s] = pairTerm(p, on, nullptr, a[r], b[s]);
    };
    auto emit = [&](int id) { return p.freqW * static_cast<double>(d.lexicon.freq(id)) / 255.0; };
    // bigram transition matrix between positions i−1 and i: bi[r·kc + s]
    std::vector<double> bi;
    std::vector<bool> biKnown;
    auto bigrams = [&](const std::vector<int>& b, const std::vector<int>& c) {
        bi.assign(b.size() * c.size(), 0.0);
        biKnown.assign(b.size(), false);
        for (size_t r = 0; r < b.size(); ++r) {
            const SyllableLM::Bigram row = d.lm.bigram(b[r]);
            if (row.size() <= 0) continue;
            biKnown[r] = true;
            for (size_t s = 0; s < c.size(); ++s)
                bi[r * c.size() + s] = p.bigramW * std::max(p.floor, static_cast<double>(row.pmi(c[s])));
        }
    };
    const std::vector<int>& c0 = ids[0];
    const std::vector<int>& c1 = ids[1];
    bigrams(c0, c1);
    pairs(1);
    std::vector<double> prev(c0.size() * c1.size());
    for (size_t r = 0; r < c0.size(); ++r) {
        const double e0 = emit(c0[r]);
        for (size_t s = 0; s < c1.size(); ++s) {
            const size_t x1 = r * c1.size() + s;
            prev[x1] = e0 + (bi[x1] + pers[x1]) + emit(c1[s]);
        }
    }
    std::vector<std::vector<int>> back(static_cast<size_t>(n));
    std::vector<double> cur, tr;
    SyllableLM::Context x;
    for (int i = 2; i < n; ++i) {
        const std::vector<int>& a = ids[static_cast<size_t>(i - 2)];
        const std::vector<int>& b = ids[static_cast<size_t>(i - 1)];
        const std::vector<int>& c = ids[static_cast<size_t>(i)];
        const size_t ka = a.size(), kb = b.size(), kc = c.size();
        bigrams(b, c);
        pairs(i);
        const auto& wa = w8[static_cast<size_t>(i - 2)];
        const auto& wb = w8[static_cast<size_t>(i - 1)];
        const auto& wc = w8[static_cast<size_t>(i)];
        // tr[(q·kb + r)·kc + s]: bigram, overridden by explicit trigram entries, + pair term
        // (a curated triple (q, r → s) recomputes the pair term with context q)
        tr.resize(ka * kb * kc);
        for (size_t q = 0; q < ka; ++q)
            for (size_t r = 0; r < kb; ++r) {
                double* t = &tr[(q * kb + r) * kc];
                std::copy(bi.begin() + static_cast<std::ptrdiff_t>(r * kc),
                          bi.begin() + static_cast<std::ptrdiff_t>((r + 1) * kc), t);
                if (d.lm.context(a[q], b[r], x) && x.hasTrigram()) {
                    for (size_t s = 0; s < kc; ++s) {
                        float v;
                        if (x.trigramPmi(c[s], v)) t[s] = p.bigramW * std::max(p.floor, static_cast<double>(v));
                    }
                }
                const bool tq = on && curatedHasTriple(wa[q], wb[r]);
                for (size_t s = 0; s < kc; ++s) t[s] += tq ? pairTerm(p, on, &wa[q], wb[r], wc[s]) : pers[r * kc + s];
            }
        cur.assign(kb * kc, 0.0);
        std::vector<int>& bk = back[static_cast<size_t>(i)];
        bk.assign(kb * kc, 0);
        for (size_t r = 0; r < kb; ++r)
            for (size_t s = 0; s < kc; ++s) {
                double best = -INFINITY;
                int arg = 0;
                for (size_t q = 0; q < ka; ++q) {
                    const double v = prev[q * kb + r] + tr[(q * kb + r) * kc + s];
                    if (v > best) {
                        best = v;
                        arg = static_cast<int>(q);
                    }
                }
                cur[r * kc + s] = best + emit(c[s]);
                bk[r * kc + s] = arg;
            }
        prev.swap(cur);
    }
    const size_t kc = ids[static_cast<size_t>(n - 1)].size();
    size_t top = 0;
    for (size_t x2 = 1; x2 < prev.size(); ++x2)
        if (prev[x2] > prev[top]) top = x2;
    int r = static_cast<int>(top / kc), s = static_cast<int>(top % kc);
    for (int i = n - 1; i >= 1; --i) {
        chosen[static_cast<size_t>(from + i)] = words[static_cast<size_t>(i)][static_cast<size_t>(s)];
        hasChoice[static_cast<size_t>(from + i)] = true;
        if (i == 1) break;
        const int q = back[static_cast<size_t>(i)][static_cast<size_t>(r) * ids[static_cast<size_t>(i)].size() +
                                                   static_cast<size_t>(s)];
        s = r;
        r = q;
    }
    chosen[static_cast<size_t>(from)] = words[0][static_cast<size_t>(r)];
    hasChoice[static_cast<size_t>(from)] = true;
}

void viterbi(const std::vector<Tok>& toks, int from, int to, const LanguageData& d, const Params& p,
             std::vector<std::u32string>& chosen, std::vector<bool>& hasChoice) {
    const int n = to - from;
    std::vector<std::vector<int>> ids(static_cast<size_t>(n));
    std::vector<std::vector<std::u32string>> words(static_cast<size_t>(n));
    std::vector<std::vector<std::string>> w8(static_cast<size_t>(n));  // UTF-8 (CuratedPairs keys)
    for (int i = 0; i < n; ++i) {
        const int f = toks[static_cast<size_t>(from + i)].form;
        for (int id = d.lexicon.formFirstId(f); id < d.lexicon.formEndId(f); ++id) {
            ids[static_cast<size_t>(i)].push_back(id);
            const std::string_view disp = d.lexicon.display(id);
            words[static_cast<size_t>(i)].push_back(text::fromUtf8(disp.data(), disp.size()));
            w8[static_cast<size_t>(i)].emplace_back(disp);
        }
    }
    const bool haveLm = d.lm.ok();
    if (p.trigram && haveLm && n >= 3) {
        viterbi3(ids, words, w8, from, d, p, chosen, hasChoice);
        return;
    }
    std::vector<std::vector<double>> score(static_cast<size_t>(n));
    std::vector<std::vector<int>> back(static_cast<size_t>(n));
    for (int i = 0; i < n; ++i) {
        const auto& cur = ids[static_cast<size_t>(i)];
        score[static_cast<size_t>(i)].assign(cur.size(), 0);
        back[static_cast<size_t>(i)].assign(cur.size(), 0);
        std::vector<SyllableLM::Bigram> rows;
        if (i > 0 && haveLm)
            for (int prev : ids[static_cast<size_t>(i - 1)]) rows.push_back(d.lm.bigram(prev));
        for (size_t s = 0; s < cur.size(); ++s) {
            const double emit = p.freqW * static_cast<double>(d.lexicon.freq(cur[s])) / 255.0;
            if (i == 0) {
                score[0][s] = emit;
                back[0][s] = -1;
                continue;
            }
            double best = -INFINITY;
            int arg = 0;
            const auto& prevIds = ids[static_cast<size_t>(i - 1)];
            for (size_t r = 0; r < prevIds.size(); ++r) {
                double tr = 0.0;
                if (!rows.empty()) {
                    const SyllableLM::Bigram& row = rows[r];
                    if (row.size() > 0) tr = p.bigramW * std::max(p.floor, static_cast<double>(row.pmi(cur[s])));
                }
                tr += pairTerm(p, p.curated, nullptr, w8[static_cast<size_t>(i - 1)][r], w8[static_cast<size_t>(i)][s]);
                const double v = score[static_cast<size_t>(i - 1)][r] + tr;
                if (v > best) {
                    best = v;
                    arg = static_cast<int>(r);
                }
            }
            score[static_cast<size_t>(i)][s] = best + emit;
            back[static_cast<size_t>(i)][s] = arg;
        }
    }
    int s = 0;
    const auto& last = score[static_cast<size_t>(n - 1)];
    for (size_t x = 1; x < last.size(); ++x)
        if (last[x] > last[static_cast<size_t>(s)]) s = static_cast<int>(x);
    for (int i = n - 1; i >= 0; --i) {
        chosen[static_cast<size_t>(from + i)] = words[static_cast<size_t>(i)][static_cast<size_t>(s)];
        hasChoice[static_cast<size_t>(from + i)] = true;
        s = back[static_cast<size_t>(i)][static_cast<size_t>(s)];
    }
}

}  // namespace

Result restore(const std::u32string& text, const LanguageData& d, const Params& p) {
    Result res;
    res.text = text;
    if (!d.ok()) return res;
    std::vector<Tok> toks = tokenize(text);
    classify(toks, d);
    std::vector<std::u32string> chosen(toks.size());
    std::vector<bool> hasChoice(toks.size(), false);
    size_t k = 0;
    while (k < toks.size()) {
        const Tok& t = toks[k];
        if (!t.valid || t.keep) {
            if (t.valid && t.english) ++res.enTokens;
            ++k;
            continue;
        }
        size_t e = k + 1;
        while (e < toks.size()) {
            const Tok& u = toks[e];
            if (!u.valid || u.keep || u.breakBefore || toks[e - 1].breakAfter) break;
            ++e;
        }
        res.vnTokens += static_cast<int>(e - k);
        viterbi(toks, static_cast<int>(k), static_cast<int>(e), d, p, chosen, hasChoice);
        k = e;
    }
    for (size_t i = 0; i < toks.size(); ++i) {
        const Tok& t = toks[i];
        if (!t.valid || !hasChoice[i]) continue;
        const std::u32string& w = chosen[i];
        // w != t.word (lowercase ascii)
        bool same = w.size() == t.word.size();
        for (size_t c = 0; same && c < w.size(); ++c) same = w[c] == static_cast<char32_t>(t.word[c]);
        if (same) continue;
        ++res.changed;
        for (int c = 0; c < t.end - t.start && static_cast<size_t>(c) < w.size(); ++c) {
            const char32_t orig = text[static_cast<size_t>(t.start + c)];
            char32_t out = w[static_cast<size_t>(c)];
            if (isUpperAscii(orig)) {
                const std::u32string up = text::upper(out);
                if (!up.empty()) out = up[0];
            }
            res.text[static_cast<size_t>(t.start + c)] = out;
        }
    }
    return res;
}

}}  // namespace vtx::addtones
