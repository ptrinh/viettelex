#include "settings_pages.h"

namespace vtx::app {

namespace {

using Field = bool Settings::*;

struct Builder {
    const Settings& s;
    const PageContext& ctx;
    std::vector<PageRow> rows;
    bool open = true;  // false while inside a collapsed expander
    int level = 0;     // 1 inside an expander

    void section(PageSection id) {
        level = 0;
        open = true;
        rows.push_back({RowKind::Section, static_cast<int>(id), nullptr, 0});
    }
    void expander(Expander e) {
        rows.push_back({RowKind::Expander, static_cast<int>(e), nullptr, 0});
        level = 1;
        open = ctx.isExpanded(e);
    }
    void endExpander() {
        level = 0;
        open = true;
    }
    void toggle(Field f, int extraIndent = 0) {
        if (open && !hiddenByParent(s, f)) rows.push_back({RowKind::Toggle, 0, f, level + extraIndent});
    }
    void control(PageControl c) {
        if (open) rows.push_back({RowKind::Control, static_cast<int>(c), nullptr, level});
    }
};

}  // namespace

bool isTelexOnly(bool Settings::*field) {
    return field == &Settings::simpleTelex || field == &Settings::freeMarking || field == &Settings::quickTelex;
}

bool hidesMixedGroup(const Settings& s) { return s.vniMode; }

bool hiddenByParent(const Settings& s, bool Settings::*field) {
    if (s.vniMode && isTelexOnly(field)) return true;
    // Tự khôi phục từ tiếng Anh off: no English restore ⇒ nothing to prefer on a collision,
    // nothing to guess by frequency.
    if (!s.autoRestore && (field == &Settings::collisionPrefersVietnamese || field == &Settings::englishByFrequency))
        return true;
    // Quyết định theo ngữ cảnh off: both experiments build on the context decision.
    if (!s.contextualEnglish && (field == &Settings::retroactiveEnglish || field == &Settings::englishByFrequency))
        return true;
    // The tray menu only exists with the tray icon (main.cpp).
    if (!s.showTrayIcon && field == &Settings::textToolsInMenu) return true;
    return false;
}

bool showsTrayStyle(const Settings& s) { return s.showTrayIcon; }

bool showsMixedCard(const Settings& s, const PageContext& ctx) { return ctx.mixedCardPending && !hidesMixedGroup(s); }

bool affectsLayout(bool Settings::*field) {
    return field == &Settings::autoRestore || field == &Settings::contextualEnglish ||
           field == &Settings::showTrayIcon;
}

std::vector<PageRow> settingsPageRows(SettingsPage page, const Settings& s, const PageContext& ctx) {
    Builder b{s, ctx, {}};
    switch (page) {
        case SettingsPage::Typing:
            if (ctx.conflicts) b.control(PageControl::ConflictCard);
            if (showsMixedCard(s, ctx)) b.control(PageControl::MixedCard);
            b.section(PageSection::InputStyle);
            b.control(PageControl::InputMethod);
            b.expander(Expander::TypingAdvanced);
            b.toggle(&Settings::simpleTelex);
            b.toggle(&Settings::freeMarking);
            b.toggle(&Settings::quickTelex);
            b.toggle(&Settings::modernOrthography);
            b.toggle(&Settings::teencode);
            b.toggle(&Settings::bracketVowels);
            b.toggle(&Settings::reEditWord);
            b.endExpander();
            // Gõ lẫn tiếng Anh (ONBOARDING-SPEC §4): the profile rows, English detection in
            // "Nâng cao". The two experiments sit under "Quyết định theo ngữ cảnh".
            b.section(PageSection::Mixed);
            if (hidesMixedGroup(s)) {
                // VNI: nothing in this group changes what is typed — one line instead.
                b.control(PageControl::MixedVniNote);
            } else {
                b.control(PageControl::ProfileRows);
                b.expander(Expander::MixedAdvanced);
                b.toggle(&Settings::autoRestore);
                b.toggle(&Settings::collisionPrefersVietnamese);
                b.toggle(&Settings::contextualEnglish);
                b.toggle(&Settings::retroactiveEnglish, 1);
                b.toggle(&Settings::englishByFrequency, 1);
                b.endExpander();
            }
            // Chuyển Việt/Anh: the switch key; how apps remember and start in "Nâng cao".
            b.section(PageSection::Switch);
            b.control(PageControl::SwitchHotkey);
            b.expander(Expander::SwitchAdvanced);
            b.control(PageControl::PerAppWin);
            b.toggle(&Settings::startEnglish);
            if (ctx.offerDefaultInput) b.control(PageControl::DefaultInput);
            b.control(PageControl::SwitchIndicator);
            b.endExpander();
            b.section(PageSection::Spelling);
            b.toggle(&Settings::liveSpellCheck);
            b.toggle(&Settings::underlineMisspelled);
            break;
        case SettingsPage::Suggestions:
            b.section(PageSection::Hints);
            b.toggle(&Settings::mathResults);
            b.toggle(&Settings::numberChips);
            b.toggle(&Settings::typoHints);
            b.toggle(&Settings::toneHints);
            b.toggle(&Settings::dateHints);
            b.toggle(&Settings::filterSensitive);
            b.toggle(&Settings::learnWords);
            b.control(PageControl::ClearLearned);
            b.control(PageControl::TextPredictionLink);
            b.expander(Expander::TextTools);
            b.toggle(&Settings::textToolsInMenu);
            b.control(PageControl::AddTonesHotkey);
            b.endExpander();
            break;
        case SettingsPage::Shortcuts: b.control(PageControl::ShortcutTable); break;
        case SettingsPage::Apps:
            b.control(PageControl::AppTable);
            b.expander(Expander::Games);
            b.toggle(&Settings::autoOffFullscreen);
            b.toggle(&Settings::gameMode);
            b.control(PageControl::GameHotkey);
            b.endExpander();
            break;
        case SettingsPage::General:
            b.control(PageControl::About);
            b.control(PageControl::UiLanguage);
            b.expander(Expander::Appearance);
            b.control(PageControl::IconPicker);
            b.toggle(&Settings::showTrayIcon);
            if (showsTrayStyle(s)) b.control(PageControl::TrayStyle);
            b.endExpander();
            b.section(PageSection::Updates);
            b.control(PageControl::CheckNow);
            b.toggle(&Settings::autoUpdateCheck);
            b.section(PageSection::Diagnostics);
            b.toggle(&Settings::debugLogging);
            b.section(PageSection::Uninstall);
            b.control(PageControl::Uninstall);
            b.control(PageControl::Links);
            break;
        default: break;
    }
    return b.rows;
}

bool findToggle(bool Settings::*field, SettingsPage& page, int& expander) {
    PageContext all;
    for (bool& e : all.expanded) e = true;
    Settings s;  // every parent on, so no dependent row is left out
    s.vniMode = false;
    s.autoRestore = s.contextualEnglish = s.showTrayIcon = true;
    for (int p = 0; p < static_cast<int>(SettingsPage::Count); ++p) {
        int current = -1;
        for (const PageRow& r : settingsPageRows(static_cast<SettingsPage>(p), s, all)) {
            if (r.kind == RowKind::Expander) current = r.id;
            else if (r.kind == RowKind::Section) current = -1;
            else if (r.kind == RowKind::Toggle && r.field == field) {
                page = static_cast<SettingsPage>(p);
                expander = r.indent > 0 ? current : -1;
                return true;
            }
        }
    }
    return false;
}

}  // namespace vtx::app
