// Settings window page plan (core/settings_pages.h, docs/SETTINGS-CLEANUP-SPEC.md) and the
// UI strings it relies on: where every switch lives, dimmed-not-hidden dependents, the
// profile picker still reaching its switches, the §3 labels, and no other input method
// named in any string.
#include <cstdio>
#include <cwchar>
#include <cwctype>
#include <string>
#include <vector>

#include "onboarding.h"
#include "settings.h"
#include "settings_pages.h"
#include "strings.h"
#include "test.h"

using namespace vtx;
using namespace vtx::app;

namespace {
using Field = bool Settings::*;

// Every switch the window shows (settings_window.cpp kToggles).
const Field kAllToggles[] = {
    &Settings::simpleTelex,      &Settings::freeMarking,        &Settings::quickTelex,
    &Settings::modernOrthography, &Settings::bracketVowels,     &Settings::autoRestore,
    &Settings::liveSpellCheck,   &Settings::contextualEnglish,  &Settings::collisionPrefersVietnamese,
    &Settings::teencode,         &Settings::reEditWord,         &Settings::autoUpdateCheck,
    &Settings::debugLogging,     &Settings::showTrayIcon,       &Settings::textToolsInMenu,
    &Settings::mathResults,      &Settings::numberChips,        &Settings::typoHints,
    &Settings::toneHints,        &Settings::dateHints,          &Settings::underlineMisspelled,
    &Settings::autoOffFullscreen, &Settings::gameMode,          &Settings::filterSensitive,
    &Settings::learnWords,       &Settings::retroactiveEnglish, &Settings::englishByFrequency,
    &Settings::startEnglish,
};

PageContext allOpen() {
    PageContext c;
    for (bool& e : c.expanded) e = true;
    return c;
}

std::vector<PageRow> allRows(const Settings& s, const PageContext& c) {
    std::vector<PageRow> out;
    for (int p = 0; p < static_cast<int>(SettingsPage::Count); ++p)
        for (const PageRow& r : settingsPageRows(static_cast<SettingsPage>(p), s, c)) out.push_back(r);
    return out;
}

const PageRow* rowOf(const std::vector<PageRow>& rows, Field f) {
    for (const PageRow& r : rows)
        if (r.kind == RowKind::Toggle && r.field == f) return &r;
    return nullptr;
}

bool placed(Field f, SettingsPage page, int expander) {
    SettingsPage p = SettingsPage::Count;
    int e = -2;
    return findToggle(f, p, e) && p == page && e == expander;
}
int ex(Expander e) { return static_cast<int>(e); }
}  // namespace

TEST(settings_pages_every_switch_once) {
    const std::vector<PageRow> rows = allRows(Settings(), allOpen());
    for (Field f : kAllToggles) {
        int n = 0;
        for (const PageRow& r : rows)
            if (r.kind == RowKind::Toggle && r.field == f) ++n;
        CHECK_EQ(n, 1);
    }
    int toggles = 0;
    for (const PageRow& r : rows)
        if (r.kind == RowKind::Toggle) ++toggles;
    CHECK_EQ(toggles, static_cast<int>(sizeof(kAllToggles) / sizeof(kAllToggles[0])));
}

// §4 desktop structure: Gõ phím · Gợi ý & công cụ · Gõ tắt · Ứng dụng · Chung.
TEST(settings_pages_structure) {
    // Kiểu gõ → Nâng cao, teencode included (it was on the Chính tả page).
    for (Field f : {&Settings::simpleTelex, &Settings::freeMarking, &Settings::quickTelex, &Settings::modernOrthography,
                    &Settings::teencode, &Settings::bracketVowels, &Settings::reEditWord})
        CHECK(placed(f, SettingsPage::Typing, ex(Expander::TypingAdvanced)));
    // Gõ lẫn tiếng Anh → Nâng cao: English detection.
    for (Field f : {&Settings::autoRestore, &Settings::collisionPrefersVietnamese, &Settings::contextualEnglish,
                    &Settings::retroactiveEnglish, &Settings::englishByFrequency})
        CHECK(placed(f, SettingsPage::Typing, ex(Expander::MixedAdvanced)));
    CHECK(placed(&Settings::startEnglish, SettingsPage::Typing, ex(Expander::SwitchAdvanced)));
    CHECK(placed(&Settings::liveSpellCheck, SettingsPage::Typing, -1));
    CHECK(placed(&Settings::underlineMisspelled, SettingsPage::Typing, -1));
    CHECK(placed(&Settings::numberChips, SettingsPage::Suggestions, -1));
    CHECK(placed(&Settings::learnWords, SettingsPage::Suggestions, -1));
    CHECK(placed(&Settings::textToolsInMenu, SettingsPage::Suggestions, ex(Expander::TextTools)));
    CHECK(placed(&Settings::gameMode, SettingsPage::Apps, ex(Expander::Games)));
    CHECK(placed(&Settings::autoOffFullscreen, SettingsPage::Apps, ex(Expander::Games)));
    CHECK(placed(&Settings::showTrayIcon, SettingsPage::General, ex(Expander::Appearance)));
    CHECK(placed(&Settings::debugLogging, SettingsPage::General, -1));

    // Collapsed (the default): the Typing page's top level is short — sections, the method,
    // the profile rows, the switch key, three expanders and the two spelling switches.
    const PageContext closed;
    const std::vector<PageRow> top = settingsPageRows(SettingsPage::Typing, Settings(), closed);
    int expanders = 0, toggles = 0;
    for (const PageRow& r : top) {
        if (r.kind == RowKind::Expander) ++expanders;
        if (r.kind == RowKind::Toggle) ++toggles;
        CHECK_EQ(r.indent, 0);
    }
    CHECK_EQ(expanders, 3);
    CHECK_EQ(toggles, 2);
    CHECK(top.size() <= 12);
    // The switch key is the main control of "Chuyển Việt/Anh", outside the expander.
    bool sawSwitchSection = false, hotkeyTop = false;
    for (const PageRow& r : top) {
        if (r.kind == RowKind::Section && r.id == static_cast<int>(PageSection::Switch)) sawSwitchSection = true;
        if (sawSwitchSection && r.kind == RowKind::Control && r.id == static_cast<int>(PageControl::SwitchHotkey))
            hotkeyTop = true;
    }
    CHECK(hotkeyTop);
    // The Windows word-prediction setting is a link row, not a switch.
    bool link = false;
    for (const PageRow& r : settingsPageRows(SettingsPage::Suggestions, Settings(), closed))
        if (r.kind == RowKind::Control && r.id == static_cast<int>(PageControl::TextPredictionLink)) link = true;
    CHECK(link);
    // Expanders never nest: every expander row is at page level.
    for (const PageRow& r : allRows(Settings(), allOpen()))
        if (r.kind == RowKind::Expander) CHECK_EQ(r.indent, 0);
}

// Telex-only switches under VNI: still shown, dimmed with "Chỉ áp dụng cho Telex".
TEST(settings_pages_vni_dims_telex_only) {
    Settings telex, vni;
    vni.vniMode = true;
    const std::vector<PageRow> a = allRows(telex, allOpen()), b = allRows(vni, allOpen());
    CHECK_EQ(a.size(), b.size());  // nothing hidden
    int dimmed = 0;
    for (Field f : kAllToggles) {
        const PageRow* r = rowOf(b, f);
        CHECK(r != nullptr);
        if (!r) continue;
        CHECK(rowOf(a, f)->dim == DimReason::None);
        if (r->dim == DimReason::TelexOnly) ++dimmed;
        CHECK((r->dim == DimReason::TelexOnly) == isTelexOnly(f));
    }
    CHECK_EQ(dimmed, 5);
    CHECK(isTelexOnly(&Settings::teencode) && isTelexOnly(&Settings::bracketVowels));
    CHECK(!isTelexOnly(&Settings::modernOrthography));  // tone placement applies to VNI too
}

// "Tự sửa từ phía trước" / "Đoán từ trùng theo tần suất": right under "Quyết định theo ngữ
// cảnh", dimmed (not hidden) while it is off.
TEST(settings_pages_contextual_dependents) {
    Settings s;
    s.contextualEnglish = false;
    const std::vector<PageRow> rows = settingsPageRows(SettingsPage::Typing, s, allOpen());
    size_t parent = rows.size();
    for (size_t i = 0; i < rows.size(); ++i)
        if (rows[i].kind == RowKind::Toggle && rows[i].field == &Settings::contextualEnglish) parent = i;
    CHECK(parent + 2 < rows.size());
    if (parent + 2 < rows.size()) {
        CHECK(rows[parent + 1].field == &Settings::retroactiveEnglish);
        CHECK(rows[parent + 2].field == &Settings::englishByFrequency);
        CHECK(rows[parent + 1].dim == DimReason::NeedsContextual);
        CHECK(rows[parent + 2].dim == DimReason::NeedsContextual);
        CHECK(rows[parent + 1].indent > rows[parent].indent);
    }
    s.contextualEnglish = true;
    CHECK(dimReason(s, &Settings::retroactiveEnglish) == DimReason::None);
    CHECK(dimReason(s, &Settings::englishByFrequency) == DimReason::None);
}

// (a) The profile picker writes the same keys as before, and each one is on the page that
// holds the picker.
TEST(settings_pages_profile_switches_reachable) {
    for (Field f : profileFields()) {
        SettingsPage p = SettingsPage::Count;
        int e = -2;
        CHECK(findToggle(f, p, e));
        CHECK(p == SettingsPage::Typing);
    }
    Settings s;
    applyProfile(s, TypingProfile::En);
    CHECK(s.startEnglish && s.contextualEnglish && s.englishByFrequency);
    applyProfile(s, TypingProfile::Vi);
    CHECK(!s.startEnglish);
    // The page plan never writes settings.
    Settings before;
    (void)allRows(before, allOpen());
    TypingProfile m = TypingProfile::En;
    CHECK(matchProfile(before, "", m) && m == TypingProfile::Vi);
}

// (d) §3 labels (vi) and the new page/group names.
TEST(settings_strings_labels) {
    setEnglish(false);
    CHECK(std::wcscmp(tr(S::FreeMarking), L"Bỏ dấu tự do") == 0);
    CHECK(std::wcscmp(tr(S::ModernOrthography), L"Bỏ dấu kiểu mới (oà, uý)") == 0);
    CHECK(std::wcscmp(tr(S::ReEditWord), L"Sửa dấu từ đã gõ") == 0);
    CHECK(std::wcscmp(tr(S::NumberChips), L"Gợi ý số tiền") == 0);
    CHECK(std::wcscmp(tr(S::AutoRestore), L"Tự khôi phục từ tiếng Anh") == 0);
    CHECK(std::wcsstr(tr(S::AutoRestoreDesc), L"google, github") != nullptr);
    CHECK(std::wcscmp(tr(S::SecMixed), L"Gõ lẫn tiếng Anh") == 0);
    CHECK(std::wcscmp(tr(S::SecSwitch), L"Chuyển Việt/Anh") == 0);
    CHECK(std::wcscmp(tr(S::Advanced), L"Nâng cao") == 0);
    CHECK(std::wcsstr(tr(S::DimTelexOnly), L"Chỉ áp dụng cho Telex") != nullptr);
    CHECK(std::wcsstr(tr(S::DimNeedsContextual), L"Cần bật Quyết định theo ngữ cảnh") != nullptr);
    CHECK(std::wcsstr(tr(S::CollisionPrefersViDesc), L"lisst → list") != nullptr);
    CHECK(std::wcscmp(tr(S::TabTyping), L"Gõ phím") == 0);
    CHECK(std::wcscmp(tr(S::TabSpelling), L"Gợi ý & công cụ") == 0);
    CHECK(std::wcscmp(tr(S::TabShortcuts), L"Gõ tắt") == 0);
    CHECK(std::wcscmp(tr(S::TabApps), L"Ứng dụng") == 0);
    CHECK(std::wcscmp(tr(S::TabAbout), L"Chung") == 0);
    CHECK(std::wcsstr(tr(S::ProfileIntro), L"Gõ phím → Gõ lẫn tiếng Anh") != nullptr);
    CHECK(std::wcsstr(tr(S::MixedCardDesc), L"Gõ lẫn tiếng Anh") != nullptr);
    setEnglish(true);
    CHECK(std::wcscmp(tr(S::SecMixed), L"Mixed Vietnamese/English typing") == 0);
    setEnglish(false);
}

// (c) No string names another Vietnamese input method (names stored ROT13 so this file
// does not spell them either).
TEST(settings_strings_no_other_input_method_names) {
    const char* const kRot13[] = {"havxrl", "bcraxrl", "rixrl", "ivrgxrl", "tbgvrativrg", "ynonaxrl", "onzobb", "kxrl"};
    std::vector<std::wstring> names;
    for (const char* r : kRot13) {
        std::wstring n;
        for (const char* c = r; *c; ++c) n.push_back(static_cast<wchar_t>((*c - 'a' + 13) % 26 + 'a'));
        names.push_back(n);
    }
    for (int en = 0; en < 2; ++en) {
        setEnglish(en != 0);
        for (int i = 0; i < static_cast<int>(S::Count); ++i) {
            std::wstring s;
            for (const wchar_t* p = tr(static_cast<S>(i)); *p; ++p)
                s.push_back(*p < 128 ? static_cast<wchar_t>(std::towlower(*p)) : *p);  // ASCII case-fold
            for (const std::wstring& n : names)
                if (s.find(n) != std::wstring::npos) {
                    std::printf("  string %d (%s) names another input method\n", i, en ? "en" : "vi");
                    CHECK(false);
                }
        }
    }
    setEnglish(false);
}
