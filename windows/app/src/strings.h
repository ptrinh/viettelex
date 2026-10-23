// strings.h — UI strings, Vietnamese (default) and English (settings `uiLanguage`).
// Setting titles/descriptions reuse the macOS wording (App/Resources/*.lproj).
#pragma once
#include <string>

namespace vtx::app {

enum class S {
    // tray / app
    AppName,
    TrayTip,
    MenuSettings,
    MenuCheckUpdate,
    MenuAbout,
    MenuHideTray,  // "Ẩn biểu tượng khay": hides the icon, the app keeps running
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
    // Text tools summary (collapsed section); caret hints (macOS 1.8.2) follow in their
    // own "Gợi ý" section (SecHints)
    TextToolsSummary,
    MathResults, MathResultsDesc,
    NumberChips, NumberChipsDesc,
    TypoHints, TypoHintsDesc,
    ToneHints, ToneHintsDesc,
    DateHints, DateHintsDesc,
    FilterSensitive, FilterSensitiveDesc,
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
    // Ctrl+Shift needs VietTelex active: make it Windows' default input method (Kiểu gõ page)
    DefaultInputTitle, DefaultInputDesc, DefaultInputButton,
    // Spelling page: caret hints section; how to reach Text tools with the tray icon off
    SecHints, TextToolsNoTray,
    // Tray menu: Chế độ game toggle
    MenuGameMode,
    // Học từ bạn gõ (Chính tả page, Gợi ý section, next to Lọc từ nhạy cảm)
    LearnWords, LearnWordsDesc, ClearLearned, ClearLearnedDesc, ClearLearnedButton, ClearLearnedConfirm,
    // Gợi ý chữ khi gõ (Chính tả page, Gợi ý section): word prediction follows Windows'
    // "Show text suggestions when typing on the physical keyboard" — state + a button to it
    TextPrediction, TextPredictionOn, TextPredictionOff, TextPredictionCaption, TextPredictionButton,
    // Tray icon style (Kiểu gõ page, Appearance) + the tray tooltip's state line
    TrayStyle, TrayStyleDesc, TrayStyleLetter, TrayStyleKeyboard, TrayStateVi, TrayStateEn,
    // Welcome: how to start typing; "make VietTelex the default keyboard" checkbox
    WelcomeHowTo, WelcomeDefaultInput,
    // Windows' own Ctrl+Shift hotkey (conflict card / dialog)
    WinHotkeyName, WinHotkeyDesc, WinHotkeyFix, WinHotkeyFixNote, WinHotkeyFixed, WinHotkeyFixFailed,
    // Tự sửa từ phía trước (Chính tả page, right under Quyết định theo ngữ cảnh, shown only
    // while that is on; experimental)
    RetroEnglish, RetroEnglishDesc,
    Count
};

const wchar_t* tr(S id);
void setEnglish(bool en);

// "Gợi ý chữ khi gõ" card: the state line for Windows' physical-keyboard text suggestions
// (`on` = readSystemTextPrediction()), then the caption saying VietTelex follows it.
S textPredictionState(bool on);
std::wstring textPredictionDesc(bool on);

}  // namespace vtx::app
