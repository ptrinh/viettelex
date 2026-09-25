// Replays the golden corpus generated from the Swift engine (TelexCore/Sources/GenGolden,
// `swift run gen-golden`) and requires a 100% match. Line format: see GenGolden/main.swift.
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include "support.hpp"
#ifdef VTX_HAVE_ZLIB
#include <zlib.h>
#endif

using namespace vt;

namespace {

std::string tok(const vtx::Action& a) {
    if (a.kind == vtx::Action::Passthrough) return "P";
    if (a.kind == vtx::Action::None) return "N";
    return "R" + std::to_string(a.backspaces) + "," + text(a);
}

void removeLast(std::u32string& s, int n) {
    size_t k = static_cast<size_t>(n) < s.size() ? static_cast<size_t>(n) : s.size();
    s.resize(s.size() - k);
}
void applyReplace(std::u32string& screen, const vtx::Action& a) {
    removeLast(screen, a.backspaces);
    for (int i = 0; i < a.length; ++i) screen.push_back(a.text[i]);
}

std::string replay(const std::string& flagsField, const std::string& opsUtf8) {
    std::string flags = flagsField == "-" ? "" : flagsField;
    vtx::TelexEngine e;
    bool autoRestore = configure(e, flags);
    std::string trace;
    auto add = [&](const std::string& t) { if (!trace.empty()) trace += '|'; trace += t; };
    std::u32string screen;
    std::u32string ops = fromUtf8(opsUtf8);
    vtx::Action a;
    if (!ops.empty() && ops[0] == U'@') {
        bool ok = e.seed(ops.data() + 1, static_cast<int>(ops.size() - 1));
        add(ok ? "1" : "0");
        screen = fromUtf8(composed(e));
    } else {
        for (size_t i = 0; i < ops.size(); ++i) {
            char32_t c = ops[i];
            switch (c) {
            case U' ': case U'.': case U',': {
                std::string p = peek(e, autoRestore);
                e.commitBoundary(autoRestore, a);
                if (a.kind == vtx::Action::Replace) applyReplace(screen, a);
                screen.push_back(c);
                add(p + "=>" + tok(a));
                break;
            }
            case U'<':
                e.backspace(a);
                if (a.kind == vtx::Action::Replace) applyReplace(screen, a); else removeLast(screen, 1);
                add(tok(a));
                break;
            case U'^': {
                char16_t b[vtx::kMaxText];
                int n = e.reopenLastCommit(b, vtx::kMaxText);
                if (n >= 0) { removeLast(screen, 1); add("o:" + toUtf8(b, n)); } else add("o~");
                break;
            }
            case U'#': e.reset(); add("N"); break;
            case U'!': e.resetContext(); add("N"); break;
            case U'%': add("c:" + commitText(e, autoRestore)); break;
            case U'`':
                if (i + 1 < ops.size()) { autoRestore = toggleFlag(e, static_cast<char>(ops[i + 1]), autoRestore); ++i; }
                add("t");
                break;
            default:
                e.feed(c, a);
                if (a.kind == vtx::Action::Passthrough) screen.push_back(c);
                else if (a.kind == vtx::Action::Replace) applyReplace(screen, a);
                add(tok(a));
            }
        }
    }
    return flagsField + "\t" + opsUtf8 + "\t" + trace + "\t" + toUtf8(screen) + "\t" + composed(e) + "\t" +
           raw(e) + "\t" + (e.previousWordEnglish() ? "1" : "0");
}

bool readAll(const char* path, std::string& data) {
    size_t len = std::strlen(path);
    bool gz = len > 3 && std::strcmp(path + len - 3, ".gz") == 0;
    if (gz) {
#ifdef VTX_HAVE_ZLIB
        gzFile f = gzopen(path, "rb");
        if (!f) return false;
        char buf[1 << 16];
        int n;
        while ((n = gzread(f, buf, sizeof buf)) > 0) data.append(buf, static_cast<size_t>(n));
        gzclose(f);
        return true;
#else
        std::fprintf(stderr, "built without zlib: pass a decompressed golden.tsv\n");
        return false;
#endif
    }
    FILE* f = std::fopen(path, "rb");
    if (!f) return false;
    char buf[1 << 16];
    size_t n;
    while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) data.append(buf, n);
    std::fclose(f);
    return true;
}

} // namespace

int runGolden(const char* path) {
    std::string data;
    if (!readAll(path, data)) { std::fprintf(stderr, "cannot read %s\n", path); return 1; }
    long total = 0, failed = 0;
    size_t pos = 0;
    while (pos < data.size()) {
        size_t eol = data.find('\n', pos);
        if (eol == std::string::npos) eol = data.size();
        std::string line = data.substr(pos, eol - pos);
        pos = eol + 1;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        ++total;
        size_t t1 = line.find('\t');
        size_t t2 = line.find('\t', t1 + 1);
        std::string actual = replay(line.substr(0, t1), line.substr(t1 + 1, t2 - t1 - 1));
        if (actual != line) {
            if (failed < 40) std::printf("expected: %s\n  actual: %s\n", line.c_str(), actual.c_str());
            ++failed;
        }
    }
    std::printf("golden: %ld/%ld match (%.4f%%)\n", total - failed, total,
                total ? 100.0 * static_cast<double>(total - failed) / static_cast<double>(total) : 0.0);
    if (total < 10000) { std::printf("golden corpus too small\n"); return 1; }
    return failed == 0 ? 0 : 1;
}
