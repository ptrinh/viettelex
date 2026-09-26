// strings.h — UI strings, Vietnamese (default) and English (settings `uiLanguage`).
// Setting titles/descriptions reuse the macOS wording (App/Resources/*.lproj).
#pragma once

namespace vtx::app {

enum class S {
    // tray / app
    AppName,
    TrayTip,
    MenuSettings,
    MenuCheckUpdate,
    MenuAbout,
    MenuQuit,
    // navigation / page titles
    TabTyping,
    TabSpelling,
    TabShortcuts,
    TabApps,
    TabAbout,
    // section headers
    SecInputStyle,
    SecSwitch,
    SecAppearance,
    SecSpelling,
    SecShortcuts,
    SecApps,
    SecUpdates,
    SecDiagnostics,
    SecUninstall,
    // settings: title + description
    InputMethod, InputMethodDesc,
    Telex, Vni,
    SimpleTelex, SimpleTelexDesc,
    FreeMarking, FreeMarkingDesc,
    QuickTelex, QuickTelexDesc,
    ModernOrthography, ModernOrthographyDesc,
    BracketVowels, BracketVowelsDesc,
    AutoRestore, AutoRestoreDesc,
    LiveSpellCheck, LiveSpellCheckDesc,
    ContextualEnglish, ContextualEnglishDesc,
    CollisionPrefersVi, CollisionPrefersViDesc,
    Teencode, TeencodeDesc,
    ReEditWord, ReEditWordDesc,
    SwitchHotkey, SwitchHotkeyDesc,
    HotkeyCtrlShift, HotkeyWinSpace, HotkeyAltZ, HotkeyOff,
    MenuIcon, MenuIconDesc,
    IconVt, IconStar, IconFlag, IconLogo, IconVi,
    ShowTray, ShowTrayDesc,
    UiLanguage, UiLanguageDesc,
    AutoUpdateCheck, AutoUpdateCheckDesc,
    DebugLogging, DebugLoggingDesc,
    CheckNow, CheckNowDesc, CheckButton,
    Uninstall, UninstallDesc, UninstallButton, UninstallConfirm,
    // lists
    ShortcutsDesc,
    ShortcutKey, ShortcutValue,
    Add, Remove, Import, Export,
    AppsDesc,
    AppExe, AppModeLabel,
    ModeComposition, ModeInPlace, ModeHook, ModeOff,
    EmptyShortcuts, EmptyApps,
    // about
    AboutText,
    Version,
    LinkWebsite, LinkSource, LinkLearn,
    On, Off,
    // messages
    UpToDate,
    UpdateAvailable,
    UpdateFailed,
    UpdateBadSignature,
    ImportFailed,
    ElevatedHookNotice,
    Count
};

const wchar_t* tr(S id);
void setEnglish(bool en);

}  // namespace vtx::app
