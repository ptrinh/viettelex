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
    ModeComposition, ModeInPlace, ModeHook, ModeOff, ModeDirect,
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
    // 1.1.5: per-app Việt/Anh — who remembers depends on how you switch
    HotkeyNoteWinPerApp, HotkeyNoteWinGlobal, HotkeyNoteWinUnknown,
    PerAppWin, PerAppWinOn, PerAppWinOff, PerAppWinUnknown, PerAppEnableButton, PerAppOpenButton,
    // Công cụ văn bản (tray submenu, Thêm dấu hotkey)
    SecTextTools,
    TextToolsInMenu, TextToolsInMenuDesc,
    AddTonesHotkey, AddTonesHotkeyDesc,
    MenuTextTools,
    ToolAddTones, ToolUpper, ToolLower, ToolTitle, ToolSentence, ToolStrip,
    // Gợi ý cạnh con trỏ (macOS 1.8.2), in the collapsible Text tools section
    TextToolsSummary,
    MathResults, MathResultsDesc,
    NumberChips, NumberChipsDesc,
    TypoHints, TypoHintsDesc,
    ToneHints, ToneHintsDesc,
    DateHints, DateHintsDesc,
    // opt-in red squiggle on the composition (Chính tả page)
    UnderlineMisspelled, UnderlineMisspelledDesc,
    // Games / fullscreen, floating V/E indicator (Kiểu gõ page)
    SecGames,
    AutoOffFullscreen, AutoOffFullscreenDesc,
    GameMode, GameModeDesc,
    GameModeHotkey, GameModeHotkeyDesc,
    SwitchIndicator, SwitchIndicatorDesc, IndicatorAuto,
    ToastGameOn, ToastGameOff,
    // Other Vietnamese input methods (welcome window + Kiểu gõ page)
    ConflictTitle, ConflictDesc, ConflictButton,
    ConflictDlgIntro, ConflictOpenLocation, ConflictHowToQuit, ConflictQuitHelp,
    ConflictRemoveMs, ConflictRemoveMsNote, ConflictOpenLangSettings, ConflictRemoved, ConflictRemoveFailed,
    ConflictNone,
    // Welcome (first run)
    WelcomeTitle, WelcomeIntro, WelcomeMethod, WelcomeSwitch, WelcomeTray, WelcomeTrayNote,
    WelcomeImport, WelcomeDone, WelcomeOpenSettings,
    // Chuyển từ UniKey (import result)
    ImportResult, ImportSkipped, ImportViqr,
    Count
};

const wchar_t* tr(S id);
void setEnglish(bool en);

}  // namespace vtx::app
