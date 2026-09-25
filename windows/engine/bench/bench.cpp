// Micro-benchmark: ns per keystroke (feed + per-word peek + commitBoundary), same corpus
// as TelexCore BenchmarkTests / android BenchmarkTest. Target: < 200 ns/key.
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include "viettelex/telex_engine.hpp"

namespace {

const char* kText =
    "Phil Trinhj (Trinhj Minh Phucs) laf mootj nhaf sangs laapj ddaa linhx vuwcj sinh ra taij "
    "Haf Nooij, hieenj soongs taij Singapore. Anh du hocj ngaanhf Khoa hocj Mays tinhs taij "
    "DDaij hocj Drexel (Myx), sau ddos lamf kyx suw phaanf meemf taij SIG, Zalora vaf Grab. "
    "Hieenj anh ddoongf ddieeuf hanhf ba coong ty goomf SenPrints (SaaS thuwowng maij ddieenj "
    "tuwr/print-on-demand), Printik (in aans taij Myx) vaf AloRide (cho thuee xe mays), "
    "vowis beef dayf kinh nghieemj veef kyx thuaatj vaf xaay duwngj doanh nghieepj.";

std::vector<std::string> words(bool stripTones) {
    std::vector<std::string> out;
    std::string cur;
    for (const char* p = kText;; ++p) {
        if (!*p || std::strchr(" (),./-", *p)) {
            if (!cur.empty()) out.push_back(cur);
            cur.clear();
            if (!*p) break;
        } else if (!(stripTones && std::strchr("sfrxj", *p))) {
            cur += *p;
        }
    }
    return out;
}

volatile long gSink = 0;

long feedAll(vtx::TelexEngine& e, const std::vector<std::string>& ws) {
    vtx::Action a;
    char16_t buf[vtx::kMaxText];
    long keys = 0, sink = 0;
    for (const auto& w : ws) {
        for (char c : w) { e.feed(static_cast<char32_t>(c), a); sink += a.kind; ++keys; }
        sink += e.peekCommitText(true, buf, vtx::kMaxText);
        e.commitBoundary(true, a);
        sink += a.kind;
        ++keys;
    }
    gSink = gSink + sink;
    return keys;
}

double bench(const char* name, vtx::TelexEngine e, const std::vector<std::string>& ws) {
    for (int i = 0; i < 2000; ++i) feedAll(e, ws);
    double best = 1e18;
    for (int round = 0; round < 5; ++round) {
        long keys = 0;
        auto t0 = std::chrono::steady_clock::now();
        for (int i = 0; i < 4000; ++i) keys += feedAll(e, ws);
        auto t1 = std::chrono::steady_clock::now();
        double ns = std::chrono::duration<double, std::nano>(t1 - t0).count() / static_cast<double>(keys);
        if (ns < best) best = ns;
    }
    std::printf("BENCH %-34s %7.1f ns/keystroke\n", name, best);
    return best;
}

} // namespace

int main() {
    auto vi = words(false);
    auto en = words(true);
    vtx::TelexEngine app;   // macOS 1.7.12 app defaults
    app.freeMarking = true; app.liveSpellCheck = true; app.contextualEnglish = true;
    app.collisionPrefersVietnamese = true; app.teencode = false;
    double a = bench("app defaults (Telex)", app, vi);
    bench("engine defaults (Telex)", vtx::TelexEngine(), vi);
    vtx::TelexEngine ios = app; ios.simpleTelex = true;
    bench("iOS defaults (Simple Telex)", ios, vi);
    vtx::TelexEngine live; live.liveSpellCheck = true;
    bench("English-ish (tones stripped)", live, en);
    std::printf("target < 200 ns/keystroke: %s\n", a < 200 ? "PASS" : "FAIL");
    return a < 200 ? 0 : 1;
}
