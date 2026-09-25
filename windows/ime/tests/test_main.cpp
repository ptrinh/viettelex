// Minimal test harness (no third-party deps) for the portable TIP/app core.
#include "test.h"

#include <cstdio>

namespace vtx::test {
std::vector<Case>& registry() {
    static std::vector<Case> r;
    return r;
}
int& failures() {
    static int f = 0;
    return f;
}
}  // namespace vtx::test

int main() {
    int n = 0;
    for (auto& c : vtx::test::registry()) {
        int before = vtx::test::failures();
        c.fn();
        ++n;
        if (vtx::test::failures() != before) std::printf("FAILED: %s\n", c.name);
    }
    std::printf("%d tests, %d failed checks\n", n, vtx::test::failures());
    return vtx::test::failures() ? 1 : 0;
}
