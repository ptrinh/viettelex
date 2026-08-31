// AppState.swift
// Single source of truth for settings. UserDefaults-backed, read on the main
// (input) thread. There is no VI/EN enable/disable: Vietnamese is on whenever
// VietTelex is the active macOS input source; the OS drives switching (and its
// per-app input-source memory).

import Foundation
import TelexCore   // ClientPolicy (remote-desktop passthrough class)

extension Notification.Name {
    /// Posted by the mouse tap on any click: the caret may have moved, so any active
    /// composition must be abandoned.
    static let telexResetComposition = Notification.Name("com.viettelex.resetComposition")
}

final class AppState: @unchecked Sendable {
    static let shared = AppState()

    /// Real settings suite — EXCEPT under XCTest, where a separate suite isolates the
    /// test host: the host runs the real AppState, and tests that flip toggles
    /// (debugLogging, engine settings) were writing straight into the dev machine's
    /// live settings — every `xcodebuild test` silently reconfigured the installed
    /// IME (bitten 2026-07-30: debugLogging kept turning itself off mid-debugging).
    /// Same detection as main.swift's IMK/TCC guard.
    static let settingsSuiteName: String =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            ? "com.viettelex.settings.tests"
            : "com.viettelex.settings"

    let defaults = UserDefaults(suiteName: AppState.settingsSuiteName) ?? .standard

    /// Guards every mutable cache + flag below. Needed since the event tap moved to
    /// its own thread: Settings/controller write on MAIN while the tap callback reads
    /// on the TAP thread (usesTapMode/usesSelectionReplace/shortcuts/flags are on its
    /// per-key path). NSLock (non-recursive!) — public methods lock ONCE and call only
    /// unlocked `_helpers` inside; never call another locked member while holding it.
    /// Uncontended cost is tens of ns, invisible next to the ~ms XPC/event round trips.
    private let lock = NSLock()

    private enum Key {
        static let autoRestore = "autoRestore"
        static let freeMarking = "freeMarking"
        static let modernOrthography = "modernOrthography"
        static let liveSpellCheck = "liveSpellCheck"
        static let simpleTelex = "simpleTelex"
        static let quickTelex = "quickTelex"
        static let vniMode = "vniMode"
        static let contextualEnglish = "contextualEnglish"
        static let reEditWord = "reEditWord"
        static let shortcuts = "shortcuts"
        static let fallbackApps = "fallbackApps"      // learned: ignore replacementRange
        static let probedApps = "probedApps"          // learned: verified good
        static let manualModes = "manualAppModes"     // user override: bundleID -> AppMode
        static let keyboardLayout = "keyboardLayoutID" // ASCII layout Telex composes on
        static let bracketVowels = "bracketVowels"    // [ → ơ, ] → ư (UniKey habit)
    }

    /// A user-forced per-app handling strategy (Settings → Bảng chế độ gõ). Overrides
    /// the learned/probed classification entirely. `.auto` = no override (probe
    /// decides). All 5 typing strategies are selectable; the three tap-family modes
    /// (`tap`, `selection`, `emptyReset`) need Accessibility and fall back to marked
    /// text without it (never silently to in-place — that loses diacritics).
    /// `.axDetect` resolves per focused FIELD via the Accessibility tree (address
    /// bar → selection-replace, page content → TAP backspace-retype, Google-Docs
    /// class → marked; no AX → marked); see FocusedFieldDetector + gateRouting.
    /// `.passthrough` = IME behaves as OFF (remote-desktop class — raw scancodes).
    enum AppMode: String, CaseIterable {
        case auto, inPlace, marked, tap, selection, emptyReset, axDetect, passthrough
    }

    // In-memory caches (loaded once). All guarded by `lock` (see above).
    private var shortcutsCache: [String: String]
    private var fallbackAppsCache: Set<String>
    private var probedAppsCache: Set<String>
    private var manualModesCache: [String: String]

    /// Bundle id of the frontmost client, set in activateServer. MAIN-thread only
    /// (IMKit lifecycle + controller + Settings) — the tap thread uses
    /// FrontmostApp.shared.bundleID instead, so this needs no lock.
    var currentBundleID: String?

    // Defaults keys from the old VI/EN enable-disable + hotkey design, no longer read.
    // Removed once on launch so they don't linger in the settings suite.
    private static let legacyKeys = [
        "globalDefault", "perApp", "alwaysOffApps", "hotkeyKeyCode", "hotkeyModifiers",
    ]

    // Toggles TỐT NGHIỆP khỏi tab Thử nghiệm (17/08/2026): tính năng đã ổn định,
    // UI gỡ bỏ, mặc định BẬT cho tất cả. Key vẫn ĐƯỢC ĐỌC (property còn nguyên,
    // hot path còn dùng) nhưng giá trị OFF mà tester từng đặt bị xoá ở đây — không
    // còn UI nào để họ bật lại, giữ override cũ là kẹt vĩnh viễn ở đường chậm/kém
    // an toàn mà không ai biết. Khác legacyKeys (không còn đọc), đừng gộp chung.
    private static let graduatedKeys = [
        "reEditWord",             // Gõ thêm dấu cho từ ngay trước con trỏ
        "tapCascadeBreaker",      // Bộ ngắt chống tràn sự kiện
        "tapModifyEventInPlace",  // Sửa sự kiện phím tại chỗ
    ]

    private init() {
        // graduatedKeys xoá TRƯỚC mọi lần đọc bên dưới — xoá sau thì cache in-memory
        // của phiên này vẫn giữ giá trị OFF cũ và default-bật chỉ có hiệu lực từ lần
        // khởi động sau.
        for key in Self.graduatedKeys { defaults.removeObject(forKey: key) }
        // Engine toggles: cached in memory (see the property docs) — every one of these
        // was read from UserDefaults on EVERY keystroke, on both hot paths.
        _autoRestore = (defaults.object(forKey: Key.autoRestore) as? Bool) ?? true
        _freeMarking = (defaults.object(forKey: Key.freeMarking) as? Bool) ?? true
        _modernOrthography = (defaults.object(forKey: Key.modernOrthography) as? Bool) ?? false
        _liveSpellCheck = (defaults.object(forKey: Key.liveSpellCheck) as? Bool) ?? true
        _simpleTelex = (defaults.object(forKey: Key.simpleTelex) as? Bool) ?? false
        _quickTelex = (defaults.object(forKey: Key.quickTelex) as? Bool) ?? false
        _vniMode = (defaults.object(forKey: Key.vniMode) as? Bool) ?? false
        // LỊCH SỬ DEFAULT: OFF từ 03/08/2026 (hành vi đổi cách gõ diện rộng, user
        // chủ động bật). Bật ON 15/08/2026 (maintainer): sau hai tuần field-use +
        // các fix "position is"/"thiss is"/Enter-giữ-ngữ-cảnh, quyết định theo ngữ
        // cảnh đã đủ chín — người gõ lẫn Anh-Việt hưởng lợi ngay khỏi phải biết
        // toggle tồn tại; ai không muốn vẫn tắt được trong Cài đặt.
        _contextualEnglish = (defaults.object(forKey: Key.contextualEnglish) as? Bool) ?? true
        tapNativeFastPath = (defaults.object(forKey: "tapNativeFastPath") as? Bool) ?? true
        _tapModifyEventInPlace = (defaults.object(forKey: "tapModifyEventInPlace") as? Bool) ?? true
        _tapSkipSyntheticKeyUp = (defaults.object(forKey: "tapSkipSyntheticKeyUp") as? Bool) ?? true
        // D1 default ON since 2026-07-21 (was opt-in after the v1.2.1 hang scare):
        // field-run for a day with the queueDrained gate + 50ms AX timeout + posted-
        // events fallback and no stalls observed.
        _axSelectionReplace = (defaults.object(forKey: "axSelectionReplace") as? Bool) ?? true
        _tapCascadeBreaker = (defaults.object(forKey: "tapCascadeBreaker") as? Bool) ?? true
        _debugLogging = (defaults.object(forKey: "debugLogging") as? Bool) ?? false
        _safeUnknownApps = (defaults.object(forKey: "safeUnknownApps") as? Bool) ?? true
        _keyboardLayoutID = (defaults.object(forKey: Key.keyboardLayout) as? String) ?? ""
        _bracketVowels = (defaults.object(forKey: Key.bracketVowels) as? Bool) ?? false
        _switchHotkey = (defaults.object(forKey: "switchHotkey") as? String) ?? "off"
        shortcutsCache = (defaults.dictionary(forKey: Key.shortcuts) as? [String: String]) ?? [:]
        fallbackAppsCache = Set(defaults.stringArray(forKey: Key.fallbackApps) ?? [])
        probedAppsCache = Set(defaults.stringArray(forKey: Key.probedApps) ?? [])
        manualModesCache = (defaults.dictionary(forKey: Key.manualModes) as? [String: String]) ?? [:]
        for key in Self.legacyKeys { defaults.removeObject(forKey: key) }

        // Probe-rule v2 migration (one-time): probedApps learned under the old
        // single-confirmation rule can hold constant-caret false positives — Lark
        // was locked to the broken in-place path exactly this way. Clear the whole
        // learned in-place set; apps re-confirm cheaply (and more strictly) under
        // the two-distinct-offsets rule. fallbackApps is kept: appended verdicts
        // were positive failure evidence and remain trustworthy.
        if !defaults.bool(forKey: "probeV2Reset") {
            probedAppsCache = []
            defaults.removeObject(forKey: Key.probedApps)
            defaults.set(true, forKey: "probeV2Reset")
        }
    }

    // MARK: - Options
    // No VI/EN enable/disable: Vietnamese is ON whenever VietTelex is the active macOS
    // input source. English = switch input source (macOS remembers it per app).
    //
    // ENGINE TOGGLES BELOW ARE CACHED IN MEMORY, deliberately. All seven engine flags
    // are pushed into the engine on EVERY keystroke (TerminalTap's callback and the
    // IMKit controller both do it), and autoRestore is read at every word boundary —
    // that was 7-8 `UserDefaults.object(forKey:)` lookups per key on the hot path.
    // Same pattern as tapModifyEventInPlace &co: the getter reads the cache under
    // `lock`, the setter writes the cache AND persists, so live-toggling from Settings
    // still takes effect on the very next keystroke. Locked because Settings writes on
    // MAIN while the tap callback reads on the TAP thread.

    /// Auto-restore: at a word boundary, if the composed word is not a valid
    /// Vietnamese syllable (rule-based `SyllableValidator`, no dictionary), revert to
    /// the raw keystrokes — so English/typos come out as typed ("retore"→retỏe→
    /// retore). Default ON. Users who explicitly turned it off keep their choice.
    private var _autoRestore: Bool
    var autoRestore: Bool {
        get { lock.withLock { _autoRestore } }
        set { lock.withLock { _autoRestore = newValue }
              defaults.set(newValue, forKey: Key.autoRestore) }
    }

    /// "Bỏ dấu tự do" (free mark placement). When ON, modifier keys
    /// (circumflex aa/ee/oo, breve/horn w) reach back over consonants to the target
    /// vowel: "ama"→âm, "trangw"→trăng. When OFF (default = Minimal Telex / strict),
    /// a modifier only acts on the adjacent vowel, so English/code types cleanly
    /// ("ama"→ama, "trangw"→trangw; type "coot"/"trawng" to get the diacritic).
    /// Default ON since 1.3.1 (user decision 2026-07-21). Users who explicitly
    /// turned it off keep their choice (stored value wins).
    private var _freeMarking: Bool
    var freeMarking: Bool {
        get { lock.withLock { _freeMarking } }
        set { lock.withLock { _freeMarking = newValue }
              defaults.set(newValue, forKey: Key.freeMarking) }
    }

    /// The eight engine toggles, read in ONE lock round trip. Both hot paths push all
    /// of them into the engine on every keystroke (feed/backspace/boundary re-parse
    /// `raw` and honor them, so they must be current before any engine op). Reading
    /// them one property at a time meant EIGHT uncontended NSLock trips per key on
    /// each path — and worse, eight separate reads can straddle a user toggling a
    /// setting, handing the engine a mix of old and new. One snapshot is both faster
    /// and consistent.
    struct EngineFlags {
        var freeMarking = true, modernTone = false, liveSpellCheck = true
        var simpleTelex = false, quickTelex = false, vniMode = false
        var bracketVowels = false, contextualEnglish = true
    }

    func engineFlags() -> EngineFlags {
        lock.withLock {
            EngineFlags(freeMarking: _freeMarking, modernTone: _modernOrthography,
                        liveSpellCheck: _liveSpellCheck, simpleTelex: _simpleTelex,
                        quickTelex: _quickTelex, vniMode: _vniMode,
                        bracketVowels: _bracketVowels, contextualEnglish: _contextualEnglish)
        }
    }

    /// Sanity net for the snapshot above: every engine toggle must be carried, or a
    /// setting silently stops reaching the engine. Bump when adding a flag.
    static let engineFlagCount = 8

    /// Tone-placement style. false (default) = old style (hòa, thủy); true = modern
    /// (hoà, thuý). See `TelexEngine.modernTone`.
    private var _modernOrthography: Bool
    var modernOrthography: Bool {
        get { lock.withLock { _modernOrthography } }
        set { lock.withLock { _modernOrthography = newValue }
              defaults.set(newValue, forKey: Key.modernOrthography) }
    }

    /// Live spell-check: stop transforming a word mid-typing once it can't be valid
    /// Vietnamese (foreign words / URLs). Default ON. See `TelexEngine.liveSpellCheck`.
    private var _liveSpellCheck: Bool
    var liveSpellCheck: Bool {
        get { lock.withLock { _liveSpellCheck } }
        set { lock.withLock { _liveSpellCheck = newValue }
              defaults.set(newValue, forKey: Key.liveSpellCheck) }
    }

    /// Simple Telex: a standalone `w` stays literal (type `uw` for ư). Default OFF
    /// since 1.3.3 (user decision 2026-07-21 — full Telex incl. word-initial w→ư;
    /// English w-words rely on live spell-check + auto-restore). An explicit user
    /// choice is preserved. See `TelexEngine.simpleTelex`.
    private var _simpleTelex: Bool
    var simpleTelex: Bool {
        get { lock.withLock { _simpleTelex } }
        set { lock.withLock { _simpleTelex = newValue }
              defaults.set(newValue, forKey: Key.simpleTelex) }
    }

    /// Quick Telex ("gõ nhanh"): word-initial doubled consonant → onset digraph
    /// (cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, pp→ph, tt→th). Default OFF.
    /// See `TelexEngine.quickTelex`.
    private var _quickTelex: Bool
    var quickTelex: Bool {
        get { lock.withLock { _quickTelex } }
        set { lock.withLock { _quickTelex = newValue }
              defaults.set(newValue, forKey: Key.quickTelex) }
    }

    /// VNI input method (EXPERIMENTAL, default OFF). Digits carry the diacritics
    /// instead of Telex letters. See `TelexEngine.vniMode`.
    private var _vniMode: Bool
    var vniMode: Bool {
        get { lock.withLock { _vniMode } }
        set { lock.withLock { _vniMode = newValue }
              defaults.set(newValue, forKey: Key.vniMode) }
    }

    /// Gate cho HAI hành vi "với ngược vào từ trước con trỏ":
    ///  • re-edit: phím dấu trên engine rỗng seed lại từ trên màn hình ("toan" + s
    ///    → "toán") — chỉ ở app đã chứng minh honor in-place, không ở ô omnibox;
    ///  • ⌫ re-open (issue #40, PR #42): xoá dấu cách mở lại từ vừa chốt
    ///    ("tháy ␣" + ⌫ + a → "thấy").
    ///
    /// LỊCH SỬ DEFAULT — đọc trước khi đổi lần nữa:
    ///  • 30/07/2026 ship experimental/OFF.
    ///  • 03/08 bật ON, 04/08 REVERT ngay trong ngày (423b7d2). Field report
    ///    (J2TeamNNL, 1.4.28): trên máy tester, phím w/s/a trên engine rỗng seed
    ///    ĐOÁN từ trên màn hình rồi transform bậy ("ưeqweqwe…"), các replace sai
    ///    offset sinh verify-probe verdict rác → field bị ép marked → "Enter 2 lần
    ///    mới gửi được".
    ///  • 14/08 bật ON lại (maintainer, sau một ngày field-test Discord/iTerm/
    ///    Chrome/TextEdit). Điều kiện đã khác về BẢN CHẤT, không phải "thử lại":
    ///    PR #42 thay ĐOÁN bằng snapshot chuỗi phím engine đã chốt + đối chiếu
    ///    màn hình TỪNG KÝ TỰ trước khi mở lại (lệch → bỏ qua, ⌫ hành xử như cũ);
    ///    gate keystream của #38 chặn seed xuyên boundary; poke AX cho app Electron
    ///    (1.5.11) làm verify đọc được caret thật thay vì degrade im lặng.
    ///    Chính lớp "đoán rồi transform bậy" của 04/08 giờ không còn đường chạy.
    var reEditWord: Bool {
        get { defaults.object(forKey: Key.reEditWord) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.reEditWord) }
    }

    /// Hotkey chuyển input source: "off" (default) / "ctrl-shift" / "opt-shift" /
    /// "cmd-shift". Cached + locked vì TAP THREAD đọc ở mỗi flagsChanged (mỗi lần
    /// nhấn/nhả modifier toàn hệ thống). Xem SwitchHotkey.swift.
    private var _switchHotkey: String
    var switchHotkey: String {
        get { lock.withLock { _switchHotkey } }
        set { lock.withLock { _switchHotkey = newValue }
              defaults.set(newValue, forKey: "switchHotkey") }
    }

    /// Biểu tượng bộ gõ trên menu bar: "vt" (mặc định) hoặc "star". Áp dụng bằng cách
    /// ghi đè MenuIcon.pdf trong bundle — đọc MenuIconSwitcher.swift cho các rủi ro
    /// đã cân nhắc (seal gãy, cần restart, tự áp lại sau mỗi lần update).
    var menuIcon: String {
        get { defaults.string(forKey: "menuIcon") ?? MenuIconSwitcher.defaultChoice }
        set { defaults.set(newValue, forKey: "menuIcon") }
    }

    /// Giành lại VietTelex khi macOS TỰ đổi input source theo document (Word coi mỗi
    /// ô comment là một document — field report 15/08/2026). EXPERIMENTAL, default
    /// OFF — giành selection với OS là vùng nhạy (bài học #32). Đọc trên MAIN khi có
    /// TIS notification (không phải hot path) → defaults-backed, không cache.
    var stickyInputSource: Bool {
        get { defaults.object(forKey: "stickyInputSource") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "stickyInputSource") }
    }

    /// `[` types ơ and `]` types ư (UniKey / macOS Simple Telex habit), `{`/`}` their
    /// uppercase — EXPERIMENTAL, default OFF. Requested on Facebook 2026-08-14 by a
    /// 15-year UniKey typist; opt-in because with it on the brackets are word KEYS and
    /// stop ending a word, which anyone typing `arr[i]` in code does not want.
    /// Read on the keystroke path via the engine mirror, so it is cached like the other
    /// engine toggles.
    private var _bracketVowels: Bool
    var bracketVowels: Bool {
        get { lock.withLock { _bracketVowels } }
        set { lock.withLock { _bracketVowels = newValue }
              defaults.set(newValue, forKey: Key.bracketVowels) }
    }

    /// Which ASCII keyboard layout Telex composes on — a kTISPropertyInputSourceID
    /// such as "com.apple.keylayout.Colemak". Empty = inherit whatever layout macOS
    /// carried over from the previously selected input source, the behaviour of every
    /// build up to 1.5.11. See KeyboardLayoutOverride for why inheriting is a coin
    /// flip and why the fix is our own keycode translation (both documented OS routes
    /// are inert on macOS 26 — measured by the VTX fork, ported with credit).
    ///
    /// Read on activateServer (focus changes), never on the keystroke path.
    private var _keyboardLayoutID: String = ""
    var keyboardLayoutID: String {
        get { lock.withLock { _keyboardLayoutID } }
        set { lock.withLock { _keyboardLayoutID = newValue }
              defaults.set(newValue, forKey: Key.keyboardLayout) }
    }

    /// POLICY 06/08/2026 "app lạ đi kênh an toàn": an app with NO rule anywhere
    /// (no manual pin, no built-in entry, no learned fallback) routes TAP when
    /// Accessibility is granted, MARKED when not — never probe-and-learn in-place.
    /// Rationale: the probe trusts self-reports (caret/AX), and Discord + Lark
    /// (bundle-id drift) both proved in-place failures can be INVISIBLE to
    /// self-reports — the probe "learns in-place OK" while the screen is wrong.
    /// Tap (EVKey/OpenKey model) and marked (composition standard) are the two
    /// channels with a real contract. In-place stays for the curated built-in
    /// list and manual pins. OFF = legacy behavior (in-place default + probe).
    private var _safeUnknownApps: Bool
    var safeUnknownApps: Bool {
        get { lock.withLock { _safeUnknownApps } }
        set { lock.withLock { _safeUnknownApps = newValue }
              defaults.set(newValue, forKey: "safeUnknownApps") }
    }

    /// Context-based decision (default ON since 15/08/2026 — see init for the history).
    /// See `TelexEngine.contextualEnglish`.
    private var _contextualEnglish: Bool
    var contextualEnglish: Bool {
        get { lock.withLock { _contextualEnglish } }
        set { lock.withLock { _contextualEnglish = newValue }
              defaults.set(newValue, forKey: Key.contextualEnglish) }
    }

    /// UI language override for the Settings window + menu, independent of the
    /// system language: "system" (follow macOS), "en", or "vi". Default "vi"
    /// (maintainer 15/08/2026): gần như toàn bộ user là người Việt nhưng nhiều máy
    /// để macOS tiếng Anh, nên "system" cho họ UI tiếng Anh — mặc định thẳng tiếng
    /// Việt, ai muốn English/system thì tự chọn trong Settings. Read by `VTLocalized`.
    var uiLanguage: String {
        get { defaults.string(forKey: "uiLanguage") ?? "vi" }
        set { defaults.set(newValue, forKey: "uiLanguage") }
    }

    /// Weekly auto update check — OPT-IN, default OFF, preserving the "no network
    /// unless you ask" stance (the toggle IS the ask). Main-thread only.
    var autoUpdateCheck: Bool {
        get { defaults.bool(forKey: "autoUpdateCheck") }
        set { defaults.set(newValue, forKey: "autoUpdateCheck") }
    }
    var lastAutoUpdateCheckAt: Double {
        get { defaults.double(forKey: "lastAutoUpdateCheckAt") }
        set { defaults.set(newValue, forKey: "lastAutoUpdateCheckAt") }
    }
    /// Newest version the user has already been alerted about (never nag twice).
    var lastNotifiedUpdateVersion: String {
        get { defaults.string(forKey: "lastNotifiedUpdateVersion") ?? "" }
        set { defaults.set(newValue, forKey: "lastNotifiedUpdateVersion") }
    }

    /// Show the power-user surface (Bảng chế độ gõ + Thử Nghiệm tabs). Default ON
    /// (maintainer decision 2026-08-12 — was OFF under the "cài xong là gõ"
    /// philosophy, but hiding the mode table / debug log made every support
    /// round-trip start with "bật advanced lên đã"). Toggle stays for users who
    /// prefer the minimal surface. Settings-UI only (main thread), no lock.
    var advancedFeatures: Bool {
        get { (defaults.object(forKey: "advancedFeatures") as? Bool) ?? true }
        set { defaults.set(newValue, forKey: "advancedFeatures") }
    }

    /// Tap-mode native fast path: non-transforming letters pass through natively
    /// (zero synthetic events) when no synthetic burst is in flight. Default ON.
    /// Kill switch if reordering ever reappears on some setup:
    ///   defaults write com.viettelex.settings tapNativeFastPath -bool false
    /// Read once at launch (per-key hot path).
    let tapNativeFastPath: Bool

    /// Task B1 — tap modify-event-in-place. When a tone edit is a pure single-char
    /// insert (0 backspaces) in Backspace-emit mode and no synthetic burst is draining,
    /// the tap rewrites the physical CGEvent's unicode string and lets it pass instead
    /// of suppressing it and posting 2 synthetic events — real keycode/timing kept,
    /// zero window-server round trips. Default ON. Cached in-memory (per-key hot path,
    /// no defaults hit); the setter persists a Settings-toggle change immediately, so it
    /// takes effect live on the next keystroke. Locked: Settings writes on main, the
    /// tap thread reads per key.
    private var _tapModifyEventInPlace: Bool
    var tapModifyEventInPlace: Bool {
        get { lock.withLock { _tapModifyEventInPlace } }
        set { lock.withLock { _tapModifyEventInPlace = newValue }
              defaults.set(newValue, forKey: "tapModifyEventInPlace") }
    }

    /// Task B2 — skip the synthetic keyUp on unicode inserts. Posts only the keyDown
    /// carrying the unicode string, halving posted events per insert to shave terminal
    /// typing latency. Ships ON; the toggle is a kill switch. Safe for the in-flight
    /// accounting: the tap mask is keyDown-only and the counter tracks downs only, so a
    /// dropped up never unbalances it. Locked cache; setter persists live.
    private var _tapSkipSyntheticKeyUp: Bool
    var tapSkipSyntheticKeyUp: Bool {
        get { lock.withLock { _tapSkipSyntheticKeyUp } }
        set { lock.withLock { _tapSkipSyntheticKeyUp = newValue }
              defaults.set(newValue, forKey: "tapSkipSyntheticKeyUp") }
    }

    /// D1 — AX selection-replace. For Chromium/Spotlight tone edits (`.selection` emit
    /// mode) collapse the Shift+Left ×N select + overtype burst — 2(N+1) posted events,
    /// ~3ms each — into ONE Accessibility text edit on the focused element. Shipped OFF
    /// (it runs a synchronous cross-process AX call INSIDE the tap callback, i.e. new
    /// hang surface, right after a keyboard-hang fix), then flipped to **default ON on
    /// 2026-07-21** after a day of field use with the queueDrained gate + 50ms AX
    /// timeout + posted-events fallback and no stalls — the Settings → Thử Nghiệm
    /// toggle is now a kill switch, not an opt-in. When
    /// on it only fires with the synthetic queue drained (the AX write mutates the field
    /// immediately while native keys already past the tap can't be tracked — the
    /// "nuwax"→"nuẵ" reorder class) and any AX failure falls back to the posted-events
    /// path. Cached stored var (hot path, no defaults hit); didSet persists live.
    private var _axSelectionReplace: Bool
    var axSelectionReplace: Bool {
        get { lock.withLock { _axSelectionReplace } }
        set { lock.withLock { _axSelectionReplace = newValue }
              defaults.set(newValue, forKey: "axSelectionReplace") }
    }

    /// Layer 3 — cascade circuit breaker. Kill switch (default ON) for the runaway
    /// guard in SyntheticKeyboard: if the tap posts more key events than any human
    /// could in a short window (> ~256 within 500ms), synthetic self-recognition has
    /// failed and our own events are storming back through handle() — the dead-keyboard
    /// hang. The breaker stops emitting, resets the engine, and disables the tap so keys
    /// pass through NATIVELY (Vietnamese-in-terminal off, but the keyboard is never
    /// dead). ON by default; flip OFF only if it ever misfires:
    ///   defaults write com.viettelex.settings tapCascadeBreaker -bool false
    /// Cached stored var (hot path, no defaults hit); didSet persists live.
    private var _tapCascadeBreaker: Bool
    var tapCascadeBreaker: Bool {
        get { lock.withLock { _tapCascadeBreaker } }
        set { lock.withLock { _tapCascadeBreaker = newValue }
              defaults.set(newValue, forKey: "tapCascadeBreaker") }
    }

    /// Debug logging (default OFF). Gates the in-memory `DebugLog` ring buffer of tap
    /// health events (create/teardown, breaker trips, emit counts — never typed text),
    /// which the user copies from Settings → Thử Nghiệm to share when reporting a hang.
    /// Off = `DebugLog.log` early-returns, so it costs nothing on the hot path.
    private var _debugLogging: Bool
    var debugLogging: Bool {
        get { lock.withLock { _debugLogging } }
        set { lock.withLock { _debugLogging = newValue }
              defaults.set(newValue, forKey: "debugLogging") }
    }

    // MARK: - Shortcuts (bảng gõ tắt)

    /// Read-only snapshot used at word boundaries (no disk hit).
    var shortcuts: [String: String] { lock.withLock { shortcutsCache } }

    func setShortcuts(_ dict: [String: String]) {
        lock.withLock { shortcutsCache = dict }
        defaults.set(dict, forKey: Key.shortcuts)
    }

    func upsertShortcut(key: String, value: String) {
        guard !key.isEmpty else { return }
        let snapshot = lock.withLock { shortcutsCache[key] = value; return shortcutsCache }
        defaults.set(snapshot, forKey: Key.shortcuts)
    }

    func removeShortcut(key: String) {
        let snapshot = lock.withLock { shortcutsCache.removeValue(forKey: key); return shortcutsCache }
        defaults.set(snapshot, forKey: Key.shortcuts)
    }

    // MARK: - Learned typing strategy (in-place replacementRange vs marked text)

    /// Apps where the in-place replacementRange path is known-broken but the learned
    /// probe can't be trusted to catch it. Two failure classes:
    ///
    ///  • Terminals (Terminal.app, iTerm2) — the CANONICAL fallback apps: they ignore
    ///    in-place `replacementRange` entirely, so they MUST run tap backspace-retype
    ///    (or marked text). They used to rely purely on the learned `fallbackAppsCache`,
    ///    but that cache is per-install UserDefaults: a reinstall/upgrade wipes it, and
    ///    until the app is re-probed (and iff the probe fails, which it doesn't always —
    ///    iTerm2 implements IMKit text input for CJK and can echo the read-back, so
    ///    `probeInPlace` false-positives and locks it to the broken in-place path) the
    ///    user silently loses Vietnamese in their terminal. Terminal support is a core
    ///    promise, so it is built in, never left to the probe.
    ///
    ///  • WhatsApp — a Mac Catalyst app: returns a valid caret (never falls back on a
    ///    NotFound selectedRange) AND echoes inserted text on read-back (so the probe
    ///    false-positives), yet ignores `replacementRange` so diacritics never render.
    ///
    /// TextMate has the same in-place breakage in practice. All force off in-place: →
    /// tap backspace-retype when Accessibility is granted, else marked text. Never probed.
    // MARK: - Manual per-app mode override (Experimental → App mode)

    /// Unlocked core of manualMode — call ONLY while holding `lock`.
    private func _manualMode(_ id: String) -> AppMode? {
        guard let raw = manualModesCache[id],
              let m = AppMode(rawValue: raw), m != .auto else { return nil }
        return m
    }

    /// The user-forced mode for `bundleID`, or nil when set to auto / unset.
    func manualMode(_ bundleID: String?) -> AppMode? {
        guard let id = bundleID else { return nil }
        return lock.withLock { _manualMode(id) }
    }
    func setManualMode(_ mode: AppMode, for bundleID: String) {
        let snapshot: [String: String] = lock.withLock {
            if mode == .auto { manualModesCache[bundleID] = nil }
            else { manualModesCache[bundleID] = mode.rawValue }
            return manualModesCache
        }
        defaults.set(snapshot, forKey: Key.manualModes)
    }
    var manualModes: [String: String] { lock.withLock { manualModesCache } }

    /// True if this app already has a fixed (non-auto) mode — a manual override OR a
    /// built-in pin. Used to hide already-configured apps from the "recent apps" picker.
    func isModeConfigured(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return lock.withLock { _manualMode(id) != nil }
            || Self.builtInFallbackApps.contains(id) || Self.markedTextApps.contains(id)
            || Self.builtInInPlaceApps.contains(id)
    }

    /// This client ignores in-place replacementRange (e.g. Terminal) -> use marked text.
    ///
    /// WITHOUT Accessibility the policy is deliberately blunt (decision 2026-07-21,
    /// after field-testing subtler schemes): in-place ONLY for apps positively known
    /// good (probed while trusted, built-in verified list, or a manual In-place pin);
    /// EVERYTHING else — including never-probed apps — is marked text, and no probing
    /// happens (needsProbe is false untrusted). Marked always renders correctly;
    /// "đơn giản, an toàn" beats clever-but-glitchy here.
    func usesMarkedText(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        let trusted = Accessibility.isTrusted   // own lock — read BEFORE ours, never nested
        return lock.withLock {
            if let m = _manualMode(id) {         // user override wins
                switch m {
                case .marked: return true
                // Tap-family override without Accessibility: marked text is the safe
                // degradation (in-place would silently drop diacritics on an app the
                // user explicitly said is broken).
                case .tap, .selection, .emptyReset, .axDetect: return !trusted
                case .inPlace, .auto, .passthrough: return false
                }
            }
            if fallbackAppsCache.contains(id) || Self.builtInFallbackApps.contains(id)
                || Self.markedTextApps.contains(id) { return true }
            // Safe-unknown policy: an unruled app is tap-family — marked is its
            // untrusted degradation, same as every fallback app above. probedApps
            // (learned in-place) intentionally does NOT rescue it: that cache is
            // the self-report the policy distrusts (Lark 06/08 learned it wrong).
            if _safeUnknownApps && _isUnknownApp(id) { return true }
            // Per-field (browser) app without Accessibility: the field walk itself
            // needs AX, so neither the omnibox dance nor page-content tap can run —
            // degrade the whole app to marked text (the composition contract), the
            // same rule every tap-family strategy already follows. In-place was the
            // old untrusted fallback here, and it is exactly the contract-free
            // channel the 2026-08 web-editor reports broke on (2026-08-06 policy).
            if Self.isPerFieldByDefault(id) { return !trusted }
            if trusted { return false }
            // Untrusted default: marked, unless positively known in-place-good.
            // (Remote-desktop passthrough is resolved in the controller BEFORE this.)
            return !(probedAppsCache.contains(id) || Self.builtInInPlaceApps.contains(id))
        }
    }

    /// Terminal tap-mode: an app that ignores replacementRange (would otherwise get
    /// marked text) gets full CGEvent backspace-retype instead, but only when the
    /// process is Accessibility-trusted (Developer ID build). The sandboxed Mac App
    /// Store build can never be trusted, so it transparently stays on marked text.
    /// markedTextApps are excluded: they must stay on marked text even when trusted.
    func usesTapMode(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        // Membership under our lock; Accessibility.isTrusted OUTSIDE it (it has its
        // own lock — never nest them).
        let wants = lock.withLock { _rawWants(id).tap }
        return wants && Accessibility.isTrusted
    }

    // MARK: - One-lock routing snapshot (hot path)

    /// What a bundle id wants from the tap family, BEFORE the Accessibility/detector
    /// gates. Single source of truth shared by the legacy per-mode getters and the
    /// one-lock `tapRouting` snapshot — so the two can never drift. Caller must hold
    /// `lock`.
    struct TapWants: Equatable {
        var tap = false
        var sel = SelWant.no
        var empty = false
        var any: Bool { tap || empty || sel != .no }
    }
    enum SelWant: Equatable { case no, yes, perField }

    /// No rule ANYWHERE for this app: not built-in (any mode), not a learned
    /// fallback, not remote-desktop. Learned in-place (probedAppsCache) is
    /// deliberately NOT "known" — it is the self-report cache the safe-unknown
    /// policy exists to distrust. Caller must hold `lock`.
    private func _isUnknownApp(_ id: String) -> Bool {
        !(fallbackAppsCache.contains(id)
          || Self.builtInFallbackApps.contains(id)
          || Self.markedTextApps.contains(id)
          || Self.builtInInPlaceApps.contains(id)
          || Self.isPerFieldByDefault(id)
          || Self.selectionAlwaysApps.contains(id)
          || Self.emptyResetApps.contains(id)
          || Self.builtInPassthroughApps.contains(id)
          || Self.wildcardMode(id) != nil
          || ClientPolicy.isRemoteDesktop(id))
    }

    private func _rawWants(_ id: String) -> TapWants {
        if let m = _manualMode(id) {                                // user override wins
            return TapWants(tap: m == .tap,
                            sel: m == .selection ? .yes : (m == .axDetect ? .perField : .no),
                            empty: m == .emptyReset)
        }
        // Wildcard rule (exact rule + learned tap-fallback thắng nó; xem wildcardRules).
        if Self.exactRuleMode(id) == nil, !fallbackAppsCache.contains(id),
           let w = Self.wildcardMode(id) {
            return TapWants(tap: w == .tap,
                            sel: w == .selection ? .yes : (w == .axDetect ? .perField : .no),
                            empty: w == .emptyReset)
        }
        return TapWants(
            tap: (fallbackAppsCache.contains(id) || Self.builtInFallbackApps.contains(id)
                  || (_safeUnknownApps && _isUnknownApp(id)))
                && !Self.markedTextApps.contains(id),
            sel: Self.selectionAlwaysApps.contains(id) ? .yes
                : Self.isPerFieldByDefault(id) ? .perField : .no,
            empty: Self.emptyResetApps.contains(id))
    }

    /// The resolved routing for the CURRENT key: every gate applied.
    struct TapRouting: Equatable {
        var tap = false
        var selection = false
        var emptyReset = false
        /// True → IMKit must not compose; the tap owns (or deliberately passes) the key.
        var tapDefer: Bool { tap || selection || emptyReset }
    }

    /// OR-merge of two apps' wants (IMKit consults both the client id and the
    /// frontmost app — see the tap-defer comment in TelexInputController.handle).
    /// Pure so the merge is pinned by tests. `.yes` outranks `.perField`: a manual
    /// `.selection` pin means selection unconditionally, whatever the field verdict.
    static func mergedWants(_ a: TapWants, _ b: TapWants) -> TapWants {
        TapWants(tap: a.tap || b.tap,
                 sel: (a.sel == .yes || b.sel == .yes) ? .yes
                    : (a.sel == .perField || b.sel == .perField) ? .perField : .no,
                 empty: a.empty || b.empty)
    }

    /// Applies the Accessibility + per-field gates to a wants snapshot. Pure, and
    /// LAZY on the externals — `trusted` costs a foreign lock (and a TCC refresh
    /// kick), `wantsSelection`/`wantsMarkedField` cost detector reads; a key in a
    /// plain in-place app must keep paying for NONE of them (exactly the laziness
    /// the legacy per-mode getters had).
    static func gateRouting(_ wants: TapWants,
                            trusted: () -> Bool,
                            wantsSelection: () -> Bool,
                            wantsMarkedField: () -> Bool,
                            pageContentInPlace: Bool = false) -> TapRouting {
        guard wants.any, trusted() else { return TapRouting() }
        // Per-field resolution (browsers, maintainer decision 2026-08-06): PAGE
        // CONTENT defaults to the TAP backspace-retype path — synthetic key events
        // are the only channel every web editor must handle (the EVKey/OpenKey
        // model). `insertText(replacementRange:)` has NO contract with JS editors
        // (Lexical/ProseMirror render from their own model): Docs appended and ⌫
        // died (07-30), Discord appended while EVERY self-report said honored
        // (08-05), Zalo froze with a constant caret (08-06) — three per-host
        // patches in one week, and the Discord class is provably undetectable
        // from inside. This replaces the host allowlist with the policy itself.
        // Order: omnibox (toolbar) → selection/emptyReset dance, unchanged; a
        // marked-class field (Google Docs) falls through to IMKit marked text;
        // everything else in the page → tap.
        //
        // WEBKIT CARVE-OUT (issue #44, 2026-08-13): every motivating bug above was
        // Chromium/Electron; Safari page content had run IMKit in-place since the
        // 21/07 per-field pilot with zero field reports — and on macOS 26 Safari
        // DROPS the tap's synthetic burst in web content outright (tap-emit fired,
        // screen unchanged; repro anotepad.com + reporter's bing.com). IMKit is the
        // one channel Apple's own engine is contractually good at, so WebKit page
        // content routes back to in-place (`pageContentInPlace`); the marked-class
        // fallthrough (Google Docs in Safari) stays.
        let perField = wants.sel == .perField
        let pageContent = perField && !wantsSelection()
        return TapRouting(
            tap: wants.tap || (pageContent && !wantsMarkedField() && !pageContentInPlace),
            selection: wants.sel == .yes || (perField && !pageContent),
            emptyReset: wants.empty)
    }

    /// WebKit-family browsers whose PAGE CONTENT types via IMKit in-place instead of
    /// the tap (see the WebKit carve-out in `gateRouting`). Omnibox/marked-class
    /// routing is identical to the Chromium browsers.
    static let webKitBrowsers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ]

    /// ONE lock acquisition + at most one trusted read + at most one detector read
    /// for the whole per-key routing decision. Replaces the 6-8 separate
    /// usesTapMode/usesSelectionReplace/usesEmptyReset round trips both hot paths
    /// used to make per keystroke (each its own lock trip, several re-reading
    /// Accessibility.isTrusted — doubling the TCC-refresh pressure).
    func tapRouting(_ bundleID: String?, front: String? = nil) -> TapRouting {
        let wants: TapWants = lock.withLock {
            var w = bundleID.map { _rawWants($0) } ?? TapWants()
            // The frontmost-app merge is a safety net for a NIL/uncertain client id
            // (leaking physical keys to a tap-routed terminal — see the tap-defer
            // comment in TelexInputController.handle). Spotlight's client id is never
            // uncertain: IMKit reports it faithfully every time (field-verified), so
            // merging in whatever sits BEHIND the overlay wrongly makes Spotlight
            // itself defer whenever that app wants tap/selection (e.g. Chrome, a
            // terminal) — issue #32: Spotlight over Chrome produced zero composition,
            // the same word over TextMate (in-place, no tap wants) worked fine. The
            // tap already force-passes Spotlight's own keys raw independently
            // (spotlightOverlayForcesRaw), so this merge buys Spotlight nothing.
            if let f = front, f != bundleID, bundleID != Self.spotlightBundleID {
                w = Self.mergedWants(w, _rawWants(f))
            }
            return w
        }
        return Self.gateRouting(wants,
                                trusted: { Accessibility.isTrusted },
                                wantsSelection: { FocusedFieldDetector.wantsSelection },
                                wantsMarkedField: { FocusedFieldDetector.wantsMarkedField },
                                // The per-field verdict belongs to the focused CLIENT —
                                // a cheap Set lookup, no laziness needed.
                                pageContentInPlace: Self.webKitBrowsers.contains(bundleID ?? front ?? ""))
    }

    // MARK: - Built-in typing-mode rules (typing-modes.yml)
    //
    // The per-app DEFAULTS ship as data, not code: typing-modes.yml at the repo
    // root is bundled as a resource —
    // contributors add rules without touching Swift, and its String→String format
    // is exactly what Bảng cơ chế gõ's "Nhập từ plist…" imports, so users can also
    // apply an edited copy locally as manual pins. The field lore that used to
    // live in comments here (Lark's edge-of-word breakage, Excel's unfixable
    // marked underline, Spotlight on macOS 26, WhatsApp's native rewrite) moved
    // into the plist header where contributors will actually see it.
    // Values are AppMode raw values; unknown values are logged and skipped.
    private static let builtInRules: [String: AppMode] = {
        guard let url = Bundle.main.url(forResource: "typing-modes", withExtension: "yml"),
              let data = try? Data(contentsOf: url),
              let dict = ShortcutImporter.parse(data)
        else {
            // Missing/corrupt resource: fall back to the CORE PROMISE alone —
            // Vietnamese-in-terminal must survive anything.
            Signposts.log.fault("typing-modes.yml missing/corrupt — terminal-only fallback")
            return ["com.apple.Terminal": .tap, "com.googlecode.iterm2": .tap]
        }
        var out: [String: AppMode] = [:]
        for (id, raw) in dict where !id.hasSuffix("*") {
            if let m = AppMode(rawValue: raw), m != .auto { out[id] = m }
            else { Signposts.log.fault("typing-modes.yml: unknown mode for \(id, privacy: .public)") }
        }
        return out
    }()

    /// Wildcard rules từ cùng file yml: "com.valvesoftware.*: passthrough" phủ mọi
    /// bundle id bắt đầu bằng prefix đó (dấu * chỉ được đứng CUỐI). Ưu tiên:
    /// Ép tay > exact rule > learned cache > wildcard > safe-unknown. Resolve một
    /// lần cho mỗi bundle id rồi memoize — hot path không tốn thêm.
    private static let wildcardRules: [(prefix: String, mode: AppMode)] = {
        guard let url = Bundle.main.url(forResource: "typing-modes", withExtension: "yml"),
              let data = try? Data(contentsOf: url),
              let dict = ShortcutImporter.parse(data)
        else { return [] }
        return dict.compactMap { id, raw in
            guard id.hasSuffix("*"), let m = AppMode(rawValue: raw), m != .auto else { return nil }
            return (prefix: String(id.dropLast()), mode: m)
        }
    }()
    private static let wildcardMemoLock = NSLock()
    nonisolated(unsafe) private static var wildcardMemo: [String: AppMode?] = [:]
    static func wildcardMode(_ id: String) -> AppMode? {
        if wildcardRules.isEmpty { return nil }
        wildcardMemoLock.lock(); defer { wildcardMemoLock.unlock() }
        if let hit = wildcardMemo[id] { return hit }
        let m = wildcardRules.first { id.hasPrefix($0.prefix) }?.mode
        if wildcardMemo.count > 512 { wildcardMemo.removeAll() }   // bounded, rebuilt on demand
        wildcardMemo[id] = m
        return m
    }
    /// Exact yml rule (mọi mode) — wildcard KHÔNG được đè một exact rule.
    static func exactRuleMode(_ id: String) -> AppMode? { builtInRules[id] }
    /// Built-in passthrough, gồm cả wildcard (exact rule khác mode thì thắng).
    static func isBuiltInPassthrough(_ id: String) -> Bool {
        if let exact = builtInRules[id] { return exact == .passthrough }
        return wildcardMode(id) == .passthrough
    }
    private static func builtInIDs(_ mode: AppMode) -> Set<String> {
        Set(builtInRules.compactMap { $0.value == mode ? $0.key : nil })
    }

    static let builtInFallbackApps = builtInIDs(.tap)
    static let builtInInPlaceApps = builtInIDs(.inPlace)
    static let markedTextApps = builtInIDs(.marked)
    private static let selectionApps = builtInIDs(.axDetect)   // per-field browsers
    /// Unconditional Shift+Left selection-replace (JetBrains-style IDEs: autocomplete
    /// is a POPUP, not an inline selection, so plain selection-overtype is correct).
    /// Was dead data until 2026-07-31 — the yml shipped 12 `selection` rules but
    /// nothing ever read builtInIDs(.selection).
    private static let selectionAlwaysApps = builtInIDs(.selection)
    private static let emptyResetApps = builtInIDs(.emptyReset)
    /// Extends ClientPolicy's compiled-in remote-desktop floor (kept as the safety
    /// net) with plist-declared passthrough apps.
    static let builtInPassthroughApps = builtInIDs(.passthrough)

    /// Composers that APPEND when insertText's replacementRange starts at their
    /// block boundary (offset 0) — the Slate class ("cos" đầu message → "coó",
    /// field 06-07/08/2026). Under a manual In-place pin these words run the
    /// EDGE-TAP synthetic channel instead. NOT a routing allowlist: it only
    /// picks the in-place FLAVOR inside a pin the user already made. Quill
    /// (Slack) and native apps honor offset-0 replacementRange — measured with
    /// edgeTapKill 07/08 — and must stay on direct insertText: their composers
    /// self-insert a newline for a swallowed Return, so the edge swallow+repost
    /// path DOUBLES it there.
    static let offset0AppendApps: Set<String> = ["com.hnc.Discord"]

    /// Terminals proper — byte-pipe apps with their own controller semantics.
    /// Stays in CODE (not the plist): it is behavior classification, not a rule
    /// users should move an app in or out of.
    static let terminalApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2",
    ]

    /// Chromium/Spotlight-style Shift+Left selection-replace (Developer ID only).
    /// For `.axDetect` apps the answer flips per focused FIELD (address bar yes,
    /// page content no) — resolved OUTSIDE our lock (the detector has its own).
    func usesSelectionReplace(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        let w = lock.withLock { _rawWants(id).sel }
        switch w {
        case .no: return false
        case .yes: return Accessibility.isTrusted
        case .perField: return Accessibility.isTrusted && FocusedFieldDetector.wantsSelection
        }
    }

    /// App resolves per-FIELD (axDetect) — default browsers or a manual pin. These
    /// are the apps whose AX tree the field detector must be able to READ, so the
    /// tap pokes Chromium's AXManualAccessibility switch for them (see
    /// FocusedFieldDetector.pokeChromiumAX).
    func usesAxDetect(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return lock.withLock {
            if let m = _manualMode(id) { return m == .axDetect }
            return Self.isPerFieldByDefault(id)
        }
    }

    /// Browsers resolve per field BY DEFAULT (no manual pin needed): omnibox/smart
    /// search → selection-replace, page content → in-place. Shipped after the
    /// Safari per-field pilot (2026-07-21) proved the AX field walk in the field.
    private static func isPerFieldByDefault(_ id: String) -> Bool {
        Self.selectionApps.contains(id)
    }

    /// Spotlight's REAL bundle id — IMKit reports it as the client while the overlay
    /// is focused (field-verified in the debug log), so manual modes key off it like
    /// any other app. Only the tap-side DETECTION needs the window scan (the
    /// frontmost app stays whatever is behind the overlay).
    static let spotlightBundleID = "com.apple.Spotlight"

    /// Apps with a built-in special strategy (per-field browsers, forced-marked like
    /// Excel), for the Settings mode table — it lists the installed ones so their
    /// default is visible.
    static var builtInSpecialApps: Set<String> {
        selectionApps.union(selectionAlwaysApps).union(emptyResetApps)
            .union(markedTextApps).union(builtInPassthroughApps)
    }


    /// Office-style empty-character reset before a Backspace-retype (Developer ID only).
    func usesEmptyReset(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        let wants = lock.withLock { _rawWants(id).empty }
        return wants && Accessibility.isTrusted
    }

    /// Which emit strategy a `.selection`-eligible tap keystroke actually uses.
    /// Called ONLY when `usesSelectionReplace` is already true, so the app is either
    /// a per-field browser (omnibox) or a manual/built-in `.selection` app:
    /// - Per-field browsers (`axDetect`: Chrome/Safari/Edge/Firefox…) have INLINE
    ///   autocomplete — the suggestion sits SELECTED to the right of the caret, so a
    ///   Shift+Left select-overtype is offset exactly like Backspace ("google" →
    ///   screen "goôgle" while the engine holds "gôgle", boundary restore "gooogle").
    ///   They need the U+202F autocomplete-cancel dance (`.emptyReset`).
    /// - Manual `.selection` pins (JetBrains IDEs etc.) have a separate autocomplete
    ///   POPUP, not an inline selection, so plain Shift+Left is correct — `.selection`.
    func selectionEmitMode(_ bundleID: String?) -> TapEmit {
        usesAxDetect(bundleID) ? .emptyReset : .selection
    }

    /// What Auto WANTS for this app — the IDEAL mode, independent of the current
    /// Accessibility state. Shown in the mode table's "Detected" column; the UI adds
    /// a "missing permission" suffix when the mode needs AX and it isn't granted
    /// (showing the degraded mode instead proved misleading: Chrome displayed
    /// "chưa dò" and Spotlight looked "locked to tap" whenever AX was off).
    /// nil = not classified yet (probe hasn't seen a real replace here).
    func autoResolvedMode(_ bundleID: String?) -> AppMode? {
        guard let id = bundleID else { return nil }
        if ClientPolicy.isRemoteDesktop(id) || Self.isBuiltInPassthrough(id) { return .passthrough }
        return lock.withLock {
            if Self.isPerFieldByDefault(id) { return .axDetect }
            if Self.selectionAlwaysApps.contains(id) { return .selection }
            if Self.emptyResetApps.contains(id) { return .emptyReset }
            if Self.markedTextApps.contains(id) { return .marked }
            if fallbackAppsCache.contains(id) || Self.builtInFallbackApps.contains(id) {
                return .tap
            }
            if Self.builtInInPlaceApps.contains(id) { return .inPlace }
            if Self.exactRuleMode(id) == nil, let w = Self.wildcardMode(id) { return w }
            if !_safeUnknownApps, probedAppsCache.contains(id) { return .inPlace }
            if _safeUnknownApps { return .tap }   // app lạ: kênh an toàn (marked khi thiếu AX)
            return nil
        }
    }

    /// One-shot probe needed: not yet classified either way. Never probe a built-in
    /// fallback app — it's known-broken in-place and would false-positive the probe.
    func needsProbe(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        // No probing while untrusted: the untrusted default is marked text (which
        // needs no verification), and a probe would require the in-place trial we
        // just decided not to risk.
        guard Accessibility.isTrusted else { return false }
        return lock.withLock {
            if _manualMode(id) != nil { return false }   // user pinned it; never probe
            // Safe-unknown policy: unruled apps route tap/marked, so there is no
            // in-place trial left to classify — the one-shot probe retires. The
            // per-focus VERIFY probe for curated in-place apps is separate
            // (isLearnedInPlace) and stays.
            if _safeUnknownApps { return false }
            return !fallbackAppsCache.contains(id) && !probedAppsCache.contains(id)
                && !Self.builtInFallbackApps.contains(id) && !Self.markedTextApps.contains(id)
                && !Self.builtInInPlaceApps.contains(id) // verified good — skip the probe
        }
    }

    /// Classified in-place-good WITHOUT a manual pin: probed-good or on the
    /// built-in verified list. Drives the per-focus verify probe (a user's manual
    /// In-place pin is a decision, not a classification — never second-guessed).
    func isLearnedInPlace(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return lock.withLock {
            _manualMode(id) == nil
                && (probedAppsCache.contains(id) || Self.builtInInPlaceApps.contains(id))
        }
    }

    /// In-place replacement verified working for this app.
    func markInPlaceGood(_ bundleID: String?) {
        guard let id = bundleID else { return }
        guard let snapshot: [String] = lock.withLock({
            guard !probedAppsCache.contains(id) else { return nil }
            probedAppsCache.insert(id)
            return Array(probedAppsCache)
        }) else { return }
        defaults.set(snapshot, forKey: Key.probedApps)
    }

    /// Ground-truth reversal: a deferred AX read proved in-place does NOT work here,
    /// overriding an earlier self-reported honored that may already have committed.
    func unmarkInPlaceGood(_ bundleID: String?) {
        guard let id = bundleID else { return }
        guard let snapshot: [String] = lock.withLock({
            guard probedAppsCache.contains(id) else { return nil }
            probedAppsCache.remove(id)
            return Array(probedAppsCache)
        }) else { return }
        defaults.set(snapshot, forKey: Key.probedApps)
    }

    /// This app must use marked text (in-place replacement doesn't work).
    func markUsesMarkedText(_ bundleID: String?) {
        guard let id = bundleID else { return }
        guard let snapshot: [String] = lock.withLock({
            guard !fallbackAppsCache.contains(id) else { return nil }
            fallbackAppsCache.insert(id)
            return Array(fallbackAppsCache)
        }) else { return }
        defaults.set(snapshot, forKey: Key.fallbackApps)
    }

    /// Learned lists, for the Settings UI (Tương thích ứng dụng).
    var learnedFallbackApps: [String] { lock.withLock { fallbackAppsCache.sorted() } }
    var learnedInPlaceApps: [String] { lock.withLock { probedAppsCache.sorted() } }

    /// Forget ALL user data for ONE app: the manual pin and any learned
    /// classification — the row's built-in default (if any) takes over again.
    func forgetApp(_ id: String) {
        setManualMode(.auto, for: id)
        let snapshots: (fb: [String]?, pr: [String]?) = lock.withLock {
            var f: [String]? = nil, p: [String]? = nil
            if fallbackAppsCache.remove(id) != nil { f = Array(fallbackAppsCache) }
            if probedAppsCache.remove(id) != nil { p = Array(probedAppsCache) }
            return (f, p)
        }
        if let f = snapshots.fb { defaults.set(f, forKey: Key.fallbackApps) }
        if let p = snapshots.pr { defaults.set(p, forKey: Key.probedApps) }
    }

    /// Forget everything learned about apps. A bad one-shot probe (app busy during
    /// the read-back) otherwise downgrades an app to marked text forever; this lets
    /// the user re-probe from scratch.
    func resetLearnedApps() {
        lock.withLock {
            fallbackAppsCache = []
            probedAppsCache = []
        }
        defaults.removeObject(forKey: Key.fallbackApps)
        defaults.removeObject(forKey: Key.probedApps)
    }

    /// Would this app type better with Accessibility granted (tap / selection-replace
    /// / empty-reset strategies)? Membership only — ignores the current trust state.
    func wantsAccessibility(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return lock.withLock {
            Self.selectionApps.contains(id) || Self.emptyResetApps.contains(id)
                || fallbackAppsCache.contains(id) || Self.builtInFallbackApps.contains(id)
        }
    }

    /// One-time "grant Accessibility" prompt already shown (first focus of an app
    /// that needs the event tap while the permission is missing).
    var axPromptShown: Bool {
        get { defaults.bool(forKey: "axPromptShown") }
        set { defaults.set(newValue, forKey: "axPromptShown") }
    }
}

/// Look up a UI string honoring the user's chosen `AppState.uiLanguage`. Keys are
/// the English source strings (dev region = en); "vi" reads vi.lproj, "en" falls
/// back to the key (= English), "system" uses the system-resolved main bundle.
/// Used by both the SwiftUI Settings window and the AppKit menu/alerts so an
/// explicit language pick applies everywhere, immediately (views re-render via the
/// SettingsModel's @Published language).
func VTLocalized(_ key: String) -> String {
    let lang = AppState.shared.uiLanguage
    if lang != "system",
       let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    return Bundle.main.localizedString(forKey: key, value: key, table: nil)
}


/// Universal shortcut-table parser: accepts every format users bring from other
/// IMEs (field request 2026-07-22) — plist/XML, JSON, flat YAML ("key: value"),
/// and plain text ("key:value", ";" or "#" comments). Returns
/// nil when nothing parseable is found.
enum ShortcutImporter {
    /// Flat-YAML export — human-readable, round-trips through parse(), and
    /// other IMEs' users can eyeball-edit it. Values with YAML-special leading
    /// chars or wrapping spaces get double quotes.
    static func exportYAML(_ shortcuts: [String: String]) -> String {
        var out = "# VietTelex — bảng gõ tắt\n"
        for key in shortcuts.keys.sorted() {
            let value = shortcuts[key]!
            let needsQuotes = value.hasPrefix(" ") || value.hasSuffix(" ")
                || value.hasPrefix("'") || value.hasPrefix("\"") || value.hasPrefix("#")
            out += needsQuotes ? "\(key): \"\(value)\"\n" : "\(key): \(value)\n"
        }
        return out
    }

    static func parse(_ data: Data) -> [String: String]? {
        // 1. JSON object of strings
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           !dict.isEmpty {
            return dict
        }
        // 2. Line-based: plain txt ("key:value", ";" comments) and flat YAML
        //    ("key: value", "#" comments). One entry per line, first ":" splits.
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var out: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            // YAML niceties: strip a matching pair of quotes
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            // Key filter serves three masters: SHORTCUT keys (typed abbreviations —
            // never contain whitespace), typing-modes BUNDLE IDS (no whitespace,
            // but legitimately >32 chars: the old 32 cap silently killed the shipped
            // rules for com.apple.SafariTechnologyPreview/org.mozilla.
            // firefoxdeveloperedition/com.citrix.receiver.icaviewer.mac — found
            // 2026-07-31), and REJECTING junk formats (a plist's DOCTYPE line splits
            // on ":" into a key WITH spaces — the whitespace test is what keeps
            // parse() answering nil for plist XML now that the cap is 64).
            guard !key.isEmpty, !value.isEmpty, key.count <= 64,
                  !key.contains(where: { $0.isWhitespace }) else { continue }
            out[key] = value
        }
        return out.isEmpty ? nil : out
    }
}

extension TelexEngine {
    /// Push a whole settings snapshot into the engine. Lives here (App target), not in
    /// TelexCore, so the engine package stays free of app types.
    mutating func apply(_ f: AppState.EngineFlags) {
        freeMarking = f.freeMarking
        modernTone = f.modernTone
        liveSpellCheck = f.liveSpellCheck
        simpleTelex = f.simpleTelex
        quickTelex = f.quickTelex
        vniMode = f.vniMode
        bracketVowels = f.bracketVowels
        contextualEnglish = f.contextualEnglish
    }
}
