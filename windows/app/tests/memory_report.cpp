// memory_report — heap bytes each language-data component of VietTelex.exe allocates, and what
// the app's start sequence (text_actions.cpp textActionsConfigure) allocates in the installed and
// the portable configuration. A counting global operator new (this executable only) measures
// live heap bytes; the data files are read into buffers BEFORE measuring (on Windows they are
// the exe's RCDATA, image-mapped, never copied).
//
// Run: ctest -R memory_report -V (or the binary directly). Exits non-zero when a budget below is
// exceeded, so a change that makes startup load data again (or bloats a table) fails CI.
//
// What this does NOT measure: Windows working set (DLL images, GDI/USER objects, GDI+, stacks,
// the resource pages the readers touch). Those need a real Windows run (Task Manager / VMMap).
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <new>
#include <string>
#include <vector>

#include <viettelex/add_tones.hpp>

#include "caret_hint_ipc.h"
#include "learned_words.h"
#include "settings.h"
#include "typo_fix.h"
#include "word_prediction.h"

// ---- counting allocator (size header; max_align_t keeps alignment) ----------------------------
namespace {
size_t g_live = 0, g_peak = 0;
constexpr size_t kHdr = alignof(std::max_align_t) > sizeof(size_t) ? alignof(std::max_align_t) : sizeof(size_t);
void* countedAlloc(size_t n) {
    void* p = std::malloc(n + kHdr);
    if (!p) return nullptr;
    *static_cast<size_t*>(p) = n;
    g_live += n;
    if (g_live > g_peak) g_peak = g_live;
    return static_cast<char*>(p) + kHdr;
}
void countedFree(void* p) {
    if (!p) return;
    char* b = static_cast<char*>(p) - kHdr;
    g_live -= *reinterpret_cast<size_t*>(b);
    std::free(b);
}
}  // namespace

void* operator new(size_t n) {
    if (void* p = countedAlloc(n)) return p;
    throw std::bad_alloc();
}
void* operator new[](size_t n) { return operator new(n); }
void* operator new(size_t n, const std::nothrow_t&) noexcept { return countedAlloc(n); }
void* operator new[](size_t n, const std::nothrow_t&) noexcept { return countedAlloc(n); }
void operator delete(void* p) noexcept { countedFree(p); }
void operator delete[](void* p) noexcept { countedFree(p); }
void operator delete(void* p, size_t) noexcept { countedFree(p); }
void operator delete[](void* p, size_t) noexcept { countedFree(p); }
void operator delete(void* p, const std::nothrow_t&) noexcept { countedFree(p); }
void operator delete[](void* p, const std::nothrow_t&) noexcept { countedFree(p); }

using namespace vtx;
using namespace vtx::app;

namespace {

std::vector<uint8_t> readFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

int g_failed = 0;
void row(const char* what, long long bytes, long long budget = -1) {
    const bool over = budget >= 0 && bytes > budget;
    if (over) ++g_failed;
    if (budget >= 0)
        std::printf("  %-58s %9lld B  (budget %lld)%s\n", what, bytes, budget, over ? "  OVER BUDGET" : "");
    else
        std::printf("  %-58s %9lld B\n", what, bytes);
}

}  // namespace

int main() {
    const std::vector<uint8_t> vl = readFile(VTX_KB_RESOURCES "/vnlexicon.bin");
    const std::vector<uint8_t> el = readFile(VTX_KB_RESOURCES "/enlexicon.bin");
    const std::vector<uint8_t> lm = readFile(VTX_KB_RESOURCES "/vnlm.bin");
    if (vl.empty() || el.empty() || lm.empty()) {
        std::printf("data files missing under " VTX_KB_RESOURCES "\n");
        return 1;
    }
    std::printf("embedded data (image-mapped RCDATA on Windows, not heap): vnlexicon %zu B, enlexicon %zu B, "
                "vnlm %zu B\n",
                vl.size(), el.size(), lm.size());

    // ---- components, one by one -----------------------------------------------------------
    std::printf("components (live heap after building):\n");
    size_t base = g_live;
    auto* data = new addtones::LanguageData();
    const size_t ldSelf = g_live - base;
    base = g_live;
    data->lexicon.load(vl.data(), vl.size());
    const size_t lex = g_live - base;
    base = g_live;
    data->english.load(el.data(), el.size());
    const size_t en = g_live - base;
    base = g_live;
    data->lm.load(lm.data(), lm.size(), data->lexicon.hash(), data->lexicon.count());
    const size_t lmHeap = g_live - base;
    const long long dataTotal = static_cast<long long>(ldSelf + lex + en + lmHeap);
    row("LanguageData object", static_cast<long long>(ldSelf));
    row("  Lexicon (vnlexicon form index)", static_cast<long long>(lex), 32 * 1024);
    row("  EnglishLexicon (enlexicon word index)", static_cast<long long>(en), 96 * 1024);
    row("  SyllableLM (vnlm, read in place)", static_cast<long long>(lmHeap), 0);
    row("LanguageData total", dataTotal, 128 * 1024);

    base = g_live;
    {
        typo::LexiconSource src(*data, Settings{}.engineFlags());
        row("typo::LexiconSource (first typo-fix job, TIP only)", static_cast<long long>(g_live - base));
    }
    base = g_live;
    {
        predict::Model m(*data);
        row("predict::Model (first prediction job, TIP only)", static_cast<long long>(g_live - base));
    }
    base = g_live;
    {
        learn::Model m(nullptr, 0);
        row("learn::Model, empty (Học từ bạn gõ, TIP only)", static_cast<long long>(g_live - base));
    }
    delete data;

    // ---- the app's start sequence ----------------------------------------------------------
    // text_actions.cpp: textActionsConfigure() -> learnedSettingsChanged() -> hint jobs told
    // "no learned model". Same calls in both configurations (portable = no TIP, so no job ever
    // arrives; installed = jobs come later, from the TIP).
    std::printf("start sequence (textActionsConfigure), heap still held after it:\n");
    for (const char* mode : {"installed", "portable"}) {
        struct Loader {
            const std::vector<uint8_t>*vl, *el, *lm;
            int loads = 0;
            addtones::LanguageData* data = nullptr;
        } ld{&vl, &el, &lm};
        int& loads = ld.loads;
        addtones::LanguageData*& loaded = ld.data;
        base = g_live;
        {
            // One pointer captured (fits std::function's inline buffer, like the app's captureless
            // loader): the row below then counts only what the start sequence itself keeps.
            Loader* p = &ld;
            HintJobs jobs([p]() -> const addtones::LanguageData* {
                ++p->loads;
                p->data = new addtones::LanguageData();
                p->data->load(p->vl->data(), p->vl->size(), p->el->data(), p->el->size(), p->lm->data(), p->lm->size());
                return p->data;
            });
            jobs.setLearned(nullptr);
            jobs.setFilterSensitive(true);
            const long long held = static_cast<long long>(g_live - base);
            row((std::string(mode) + ": heap after start").c_str(), held, 0);
            if (loads != 0) {
                std::printf("  %s: language data loaded at start (%d)  FAIL\n", mode, loads);
                ++g_failed;
            }
        }
        delete loaded;
    }
    std::printf("peak heap during this report: %zu B\n", g_peak);
    std::printf(g_failed ? "memory_report: %d budget(s) exceeded\n" : "memory_report: ok\n", g_failed);
    return g_failed ? 1 : 0;
}
