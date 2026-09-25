#pragma once
#include <cstdio>
#include <string>
#include <vector>

#include "utf.h"

namespace vtx::test {
struct Case {
    const char* name;
    void (*fn)();
};
std::vector<Case>& registry();
int& failures();
struct Reg {
    Reg(const char* n, void (*f)()) { registry().push_back({n, f}); }
};
inline std::string show(const std::u16string& s) { return utf16ToUtf8(s); }
inline std::string show(const std::string& s) { return s; }
template <class T>
inline std::string show(const T& v) { return std::to_string(v); }
}  // namespace vtx::test

#define TEST(name)                                              \
    static void name();                                         \
    static ::vtx::test::Reg name##_reg(#name, &name);           \
    static void name()

#define CHECK(cond)                                                              \
    do {                                                                         \
        if (!(cond)) {                                                           \
            std::printf("  %s:%d CHECK(%s)\n", __FILE__, __LINE__, #cond);       \
            ++::vtx::test::failures();                                           \
        }                                                                        \
    } while (0)

#define CHECK_EQ(a, b)                                                           \
    do {                                                                         \
        auto&& va_ = (a);                                                        \
        auto&& vb_ = (b);                                                        \
        if (!(va_ == vb_)) {                                                     \
            std::printf("  %s:%d %s == %s\n    got: [%s]\n    want: [%s]\n",     \
                        __FILE__, __LINE__, #a, #b,                              \
                        ::vtx::test::show(va_).c_str(),                          \
                        ::vtx::test::show(vb_).c_str());                         \
            ++::vtx::test::failures();                                           \
        }                                                                        \
    } while (0)
