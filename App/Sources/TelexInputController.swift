// TelexInputController.swift
// IMKInputController driving TelexCore. NO marked text: each transform is committed
// as real text in place via insertText(_:replacementRange:), so the composing word
// is never underlined and the caret always stays at the end — the behaviour
// Vietnamese typists expect. The engine emits a
// minimal (backspaces, insert) diff; we turn it into an in-place replacement using
// the client's real selection.

import Cocoa
import InputMethodKit
import TelexCore
import Carbon.HIToolbox

private let kNoRange = NSRange(location: NSNotFound, length: 0)

// No explicit @objc name: the class is exposed to the Objective-C runtime as
// "VietTelex.TelexInputController" (module-qualified), which is exactly the string
// Info.plist's InputMethodServerControllerClass declares and what IMK resolves via
// NSClassFromString. An explicit @objc(TelexInputController) renamed it to a bare
// "TelexInputController", so the lookup returned nil and macOS never registered the
// input method.
final class TelexInputController: IMKInputController {

    private var engine = TelexEngine()

    // Virtual keycodes we treat as word boundaries (besides punctuation chars).
    private let kDelete: UInt16 = 51
    private let kReturn: UInt16 = 36
    private let kEnter: UInt16 = 76
    private let kTab: UInt16 = 48
    private let kEscape: UInt16 = 53

    // In-place editing without marked text needs to know where the composed word
    // lives. We track it locally — the composition occupies [anchor, anchor+onLen),
    // caret at the end — and read selectedRange() only ONCE per word (its first
    // key). Reading it after every insert is stale under fast typing and corrupts
    // words ("được" -> "đựoc").
    private var anchor = 0        // document offset where the composition starts
    private var onLen = 0         // UTF-16 length of the composition on screen
    private var tracking = false  // is anchor/onLen valid for the current word?
    private var selToClear = 0    // selection length to overwrite on the first insert
    private var anchorVerified = false  // one-shot re-anchor done for this word?
    /// Timestamp of the last activateServer(Spotlight) — set on EVERY Spotlight
    /// activation, whatever the client was before it. Distinct from
    /// SpotlightDetector's visibility cache, which answers "is the overlay open
    /// right now"; this answers "did Spotlight's IMK session just get torn down
    /// and recreated" (field report 2026-08-11: Esc appears to reset the query
    /// without closing the overlay, cycling activateServer(iTerm)→
    /// activateServer(Spotlight) within ~1ms — the fresh session's
    /// client.selectedRange() then reported a stale huge caret (start=6632 in an
    /// emptied field), garbling the next word: "được" → "dđuưoựoược").
    private var lastSpotlightActivateNs: UInt64 = 0
    /// One-shot: set when the CURRENT activateServer(Spotlight) followed a
    /// PRIOR one closely enough that the fresh client's selectedRange() cannot be
    /// trusted as a real caret. Consumed by the very next word-start anchor.
    private var distrustNextAnchor = false

    /// Pure so the 5s window is pinned by a test without mocking IMKTextInput.
    /// lastActivateNs == 0 means "never activated before" — never distrust the
    /// very first Spotlight session of the process's life.
    static func spotlightReactivatedTooSoon(now: UInt64, lastActivateNs: UInt64,
                                            thresholdNs: UInt64 = 5_000_000_000) -> Bool {
        lastActivateNs != 0 && now &- lastActivateNs < thresholdNs
    }
    /// EDGE-TAP (06/08/2026): the current word is anchored at field offset 0 in an
    /// app the user pinned to In-place, so its edits run on the synthetic-key
    /// channel instead of insertText. Web editors (Discord/Slate) ignore a
    /// replacementRange that starts at a block boundary and APPEND instead
    /// ("cos" đầu message → "coó" — field 06/08); synthetic ⌫-retype is the one
    /// channel they honor there. The WHOLE word stays on the CGEvent channel
    /// (letters pass native, replaces go synthetic) — mixing insertText with
    /// native/synthetic keys races under fast typing (same rule as the
    /// .passthrough comment below). Manual In-place pins only: native apps'
    /// offset-0 in-place is honored, and pinned apps get no verify probes, so
    /// this is the only guard their first word has.
    private var edgeTapWord = false
    /// Echo budget of the edge word's synthetic bursts. macOS 26 strips the magic
    /// userData before events reach IMKit (measured: our own burst arrives
    /// "magic=false" even in TextEdit), so echoes are recognized by CONTENT:
    /// keycode 51 spends a backspace, characters==chunk spends a chunk. Whether
    /// a unicode chunk re-enters handle at all is app-dependent (Electron yes,
    /// native no — AppKit inserts it directly), which is exactly why a blind
    /// total count is wrong.
    private var edgeEchoBackspaces = 0
    private var edgeEchoChunks: [String] = []
    private var edgeEchoStampNs: UInt64 = 0

    // Consecutive failed in-place read-back probes per bundleID. A single failure is
    // usually the app being busy during the probe, not a real incompatibility, so we
    // require TWO in a row before condemning an app to marked text forever. In-memory
    // only (no persistence): a fresh launch re-probes from scratch, which is fine.
    private var probeFailures: [String: Int] = [:]

    // Pending SELF-REPORTED honored confirmations per bundleID: in-place is committed
    // only after honored probes at two DISTINCT expected-caret offsets (a constant
    // garbage caret — Lark reports 1, always — can coincide with one offset but never
    // two). AX-backed honored verdicts skip this and commit immediately. In-memory
    // only, like probeFailures.
    private var probeHonors: [String: InPlaceProbe.HonorTracker] = [:]

    // (Session-field probation was tried here and REMOVED by decision 2026-07-21:
    // without Accessibility there is no field identity, so every focus change
    // re-probed at the cost of 1-2 glitched words — field-tested as "không ổn".
    // The no-AX policy is now simply: known-good in-place apps stay in-place,
    // everything else is marked text, no probing. See AppState.usesMarkedText.)

    // Last per-key routing decision logged (deduped): the strategy chosen in handle()
    // is logged only when it changes, so the debug log shows one line per app/mode
    // transition instead of one per keystroke.
    private var lastDecisionLog = ""
    private var lastEntryLog = ""
    private func logDecision(_ message: @autoclosure () -> String) {
        // @autoclosure: the interpolated string must NOT be built per keystroke when
        // logging is off — these sit on the hot path (an eager String parameter was
        // allocating+formatting on every key).
        guard AppState.shared.debugLogging else { return }
        let s = message()
        // Dedup keeps the ring readable in normal use, but hides the per-key picture
        // during diagnosis — while the debug flag is on, log EVERY decision (400
        // ring lines is plenty for a short repro).
        lastDecisionLog = s
        DebugLog.log(s)
    }

    // Observes the mouse tap's reset signal: a click moved the caret, so drop any
    // composition (the tap can't reach this controller's private engine directly).
    private var resetObserver: NSObjectProtocol?

    // One-shot dump of every TSM hilite style's attribute dict (experiment 3).
    private static var dumpedHiliteDicts = false

    // EXPERIMENT (log-only, gated on debugLogging): deferred re-probe context.
    // Chromium-class apps (Lark) serve AX from an ASYNC browser-side cache that is
    // built lazily on first query — the synchronous read inside probeInPlace can race
    // a stale/optimistic tree, which is the suspected cause of Lark "faking" every
    // probe signal. On the NEXT keyDown (hundreds of ms later, tree settled) re-read
    // the same region + the field length and log whether the verdict would change.
    // Never alters classification — data gathering for a future deferred verdict.
    private var pendingReprobe: (id: String?, start: Int, len: Int, bs: Int,
                                 inserted: String, verdict: InPlaceProbe.Verdict)?

    // Per-FOCUS re-verification of learned-in-place apps (tester log 2026-07-23).
    // Classification is per APP, but Chromium-class apps host many editors: one
    // site honors replacementRange, the next (EditContext-style) APPENDS — and a
    // learned-good app was never probed again, so that field stayed broken until
    // a reload ("gõ không ra gì / tự bôi đen rồi replace"). One verify probe per
    // focus; a failure demotes to marked text for THIS focus only (the global
    // per-app classification is untouched). Both reset on activateServer and on
    // the click/⌘-combo reset notification — the focus anchors we actually get
    // from Chromium, which reports the whole window as one IMK client.
    private var fieldVerified = false
    private var fieldForcedMarked = false
    /// Last shadow probe (seconds, reference date) — see `shadowProbeInterval`.
    private var lastShadowProbe: TimeInterval = 0
    private static let shadowProbeInterval: TimeInterval = 1.0

    private var fieldVerifyStrikes = 0
    /// Probes whose self-report was IMPOSSIBLE (caret before our anchor) in this focus.
    /// They teach nothing, but a field that only ever produces them must still land in a
    /// mode that renders, so they are bounded (see the `.inconclusive` branch).
    private var fieldInconclusive = 0
    private static let maxInconclusive = 4

    /// Effective marked-text decision for the CURRENT field: a per-focus demotion
    /// (verify probe failed here) wins over the per-app classification, and so does
    /// a canvas-editor field verdict (Google Docs — its hidden input self-reports a
    /// consistent caret, so the verify probe never fires there while the canvas
    /// renders appended garbage; field report 2026-07-30 "Quoocs" → "Quoôcốc").
    /// Gated on usesAxDetect so a browser field verdict can never leak into other apps.
    private func usesMarkedNow(_ id: String?) -> Bool {
        fieldForcedMarked || AppState.shared.usesMarkedText(id)
            || (AppState.shared.usesAxDetect(id) && FocusedFieldDetector.wantsMarkedField)
    }

    #if DEBUG
    /// `handle()` resolves this ONCE per key and reuses it — a test pins that the
    /// decision is a pure read of state (no side effect that a second call would see).
    func _testUsesMarkedNow(_ id: String?) -> Bool { usesMarkedNow(id) }
    #endif

    /// Hoãn bao nhiêu ms trước khi re-post phím boundary (Enter/Tab/Esc), hay post
    /// ngay (nil). Chỉ hoãn cho web editor ở lớp marked: commit của chúng áp vào
    /// model JS bất đồng bộ nên Enter đồng bộ "gửi" trước khi từ cuối vào DOM (field
    /// 19/08: "thử xem"+Enter → TikTok post ra mỗi "thử"). 60ms: dư cho một vòng
    /// render của React/Lexical, vẫn dưới ngưỡng người dùng cảm nhận được độ trễ khi
    /// bấm gửi. Native app KHÔNG hoãn — insertText ở đó đã đồng bộ.
    static func boundaryRepostDelayMs(markedWebField: Bool) -> Int? {
        markedWebField ? 60 : nil
    }

    /// SPLIT-BRAIN → marked (lớp bug issue #55). Fire khi: client id routes họ tap,
    /// KHÁC app với frontmost, mà routing theo frontmost (góc nhìn của TAP — tap
    /// quyết mỗi phím bằng FrontmostApp) lại KHÔNG thuộc họ tap → tap sẽ pass và
    /// tap-defer của IMK thành chữ thô. `frontDefersToTap` là @autoclosure vì đó là
    /// cả một lần giải routing — chỉ được trả khi các điều kiện rẻ phía trước đã lọc
    /// (đường thường: sameApp=true, thoát ngay). KHÔNG kéo tap vào thay vì marked:
    /// tap thấy phím TRƯỚC IMK nên không thể biết IMK sắp nhường, còn cho tap route
    /// theo client id là dựa vào thứ tự activate/deactivate vốn flaky (client thiu
    /// → backspace-retype bắn nhầm vào app in-place, tệ hơn chữ thô).
    static func splitBrainToMarked(clientDefersToTap: Bool, sameApp: Bool,
                                   spotlightDefer: Bool, alreadyMarked: Bool,
                                   frontDefersToTap: @autoclosure () -> Bool) -> Bool {
        guard clientDefersToTap, !sameApp, !spotlightDefer, !alreadyMarked else { return false }
        return !frontDefersToTap()
    }

    // MARK: - Event handling (hot path)

    /// Also receive flagsChanged (default is keyDown only): the composition is
    /// committed the moment a ⌘/⌃/⌥ MODIFIER is pressed — see handle() below.
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }

        // A ⌘/⌃/⌥ modifier just went DOWN: end any composition NOW, one event cycle
        // BEFORE the shortcut's letter arrives. Committing inside the same cycle as
        // the combo (the old approach) lost the first press — the app swallows a key
        // equivalent delivered while its IME session is open/closing (⌘A while
        // composing did nothing; after the fix for that, the FIRST ⌘A/⌥⌫ still
        // needed a second press). The modifier physically precedes the letter by
        // ~50-100ms, so by the time ⌘A is delivered the session has long been torn
        // down and the app handles it immediately. Side effect (accepted): tapping a
        // lone modifier mid-word finalizes the word.
        if event.type == .flagsChanged {
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               !engine.isEmpty, let client = sender as? IMKTextInput {
                logDecision("modifier down mid-composition → early commit")
                endComposition(client)
            }
            return false
        }

        guard event.type == .keyDown,
              let client = sender as? IMKTextInput else { return false }

        // Signpost the whole IMKit round trip; the end message names the strategy
        // that actually handled this key (see Instrumentation.swift).
        var spMode = "passthrough"
        let spState = Signposts.poster.beginInterval("imk.handle",
                                                     id: Signposts.poster.makeSignpostID())
        // privacy: .public — os_signpost redacts interpolated strings to "<private>"
        // by default, which collapses the per-strategy breakdown in xctrace exports.
        // The label is an internal strategy name, never user text.
        defer { Signposts.poster.endInterval("imk.handle", spState, "\(spMode, privacy: .public)") }

        // Our own terminal tap-mode output (synthetic Backspace / Unicode) loops back
        // through the input system. Pass it straight to the app WITHOUT re-feeding the
        // engine (a synthetic Backspace would otherwise re-enter as kDelete).
        // Confirm handle() is reached BEFORE the synthetic guard, and record whether
        // this real key is being mistaken for one of ours (isSynthetic) and why
        // (source pid vs our pid). Deduped per app so it's one line, not per-key.
        // Recognize OUR output by the magic userData only — NOT the posting pid.
        // Chromium/Electron (Slack, Lark) hand real keys to the IME stamped with our
        // pid, which the pid check dropped as synthetic (untypable Vietnamese).
        let synth = SyntheticKeyboard.isSyntheticMagic(event)
        let entryID = AppState.shared.currentBundleID ?? FrontmostApp.shared.bundleID ?? "?"
        if entryID != lastEntryLog || AppState.shared.debugLogging {   // no dedupe while debugging
            lastEntryLog = entryID
            let cg = event.cgEvent
            let srcPid = cg?.getIntegerValueField(.eventSourceUnixProcessID) ?? -1
            let ud = cg?.getIntegerValueField(.eventSourceUserData) ?? -1
            DebugLog.log("handle ENTER app=\(entryID) synthetic=\(synth) magic=\(ud == SyntheticKeyboard.magic) "
                + "srcPid=\(srcPid) myPid=\(getpid())")
        }

        if synth {
            // An edge-burst echo that arrived with its magic INTACT (older macOS)
            // must still spend its slot, or the budget wedges and eats a real key.
            if event.keyCode == kDelete, edgeEchoBackspaces > 0 { edgeEchoBackspaces -= 1 }
            else if let chars = event.characters, chars == edgeEchoChunks.first { edgeEchoChunks.removeFirst() }
            return false
        }

        // Echo of an edge-tap burst (see edgeEchoBackspaces/Chunks): pass it to
        // the app untouched — the engine already holds the post-replace state.
        // Content match, not count: a real key mid-drain (physical 'r' between
        // our ⌫ and "ư") matches neither and composes normally. Self-heals like
        // queueDrained: a lost echo must not linger, so a stale budget (>1s
        // since the burst) is discarded.
        if edgeEchoBackspaces > 0 || !edgeEchoChunks.isEmpty {
            if DispatchTime.now().uptimeNanoseconds &- edgeEchoStampNs > 1_000_000_000 {
                edgeEchoBackspaces = 0
                edgeEchoChunks = []
            } else if event.keyCode == kDelete, edgeEchoBackspaces > 0 {
                edgeEchoBackspaces -= 1
                logDecision("edge-echo ⌫ swallowed, bs left=\(edgeEchoBackspaces)")
                return false
            } else if let chars = event.characters, chars == edgeEchoChunks.first {
                edgeEchoChunks.removeFirst()
                logDecision("edge-echo chunk swallowed, chunks left=\(edgeEchoChunks.count)")
                return false
            }
        }

        // Word-table class (maintainer repro 23/08/2026): the tap witnessed a
        // Tab/arrow that this client swallowed — handle() never saw it, so the word
        // this key would continue was in fact ended in another cell/position. Drop
        // BEFORE processing, so this key starts a fresh word anchored at the REAL
        // caret. Same recovery as the mouse-click .telexResetComposition path,
        // which is exactly why clicking into the next cell already worked.
        if NavKeyWitness.consume(keycode: Int64(event.keyCode)) {
            logDecision("nav key swallowed by app → composition dropped before this key")
            dropComposition(cause: "nav-key-swallowed")
            onLen = 0
        }

        // A real key reaching handle() proves VietTelex is the selected source —
        // un-latch a stale imeActive=false so tap-mode apps aren't left dormant
        // (see noteIMKKeyProvesSelected).
        TerminalTapController.shared.noteIMKKeyProvesSelected()

        // Secure input active (password field, or an app holding secure input like
        // some chat apps): DROP the pending composition without rewriting it, then
        // pass through untouched. We must NOT call boundary() here: boundary runs
        // shortcut expansion / auto-restore via applyInPlace, i.e. an insertText into
        // the CURRENT client — now a password field — using a stale anchor from the
        // previous field, which would leak the old word into the secure input. A plain
        // engine drop is the only safe teardown. (endComposition is also wrong: its
        // marked-text branch finalizes with insertText(engine.composed), the very
        // injection we must avoid in a secure field.)
        // A password field is off limits for composition. `IsSecureEventInputEnabled()`
        // catches native secure input; SecureFieldDetector catches the web
        // `<input type="password">` case, which does NOT switch secure input on and was
        // therefore composed into normally (field report 2026-07-27).
        if SecureFieldDetector.isSecure {
            engine.reset(); tracking = false; onLen = 0
            logDecision("handle \(AppState.shared.currentBundleID ?? "?"): secure FIELD → passthrough (no compose)")
            return false
        }
        if IsSecureEventInputEnabled() {
            logDecision("handle \(AppState.shared.currentBundleID ?? "?"): secure-input → discard (raw passthrough)")
            discardComposition(); return false
        }

        // Passthrough resolution. Manual .passthrough = unconditional IME-off for the
        // app. Remote-desktop / VM / screen-share apps (built-in list) forward raw
        // scancodes for the SESSION canvas — but their OWN chrome (PC-name field,
        // search box) is ordinary text input, so with Accessibility we compose there:
        // only when the focused element's AX role is a real text input; unsure →
        // passthrough (composing into the canvas would type garbage into the guest
        // OS, while the reverse merely loses Vietnamese in a name field).
        // Same as the secure-input branch: drop, never boundary()/rewrite — the
        // anchor belongs to the previous field, and this window forwards raw keys.
        let earlyID = AppState.shared.currentBundleID
        let earlyManual = AppState.shared.manualMode(earlyID)
        if earlyManual == .passthrough {
            logDecision("handle \(earlyID ?? "?"): manual passthrough → discard (raw)")
            discardComposition(); return false
        }
        if earlyManual == nil,
           ClientPolicy.isRemoteDesktop(earlyID)
               || earlyID.map({ AppState.builtInPassthroughApps.contains($0) }) == true,
           !(Accessibility.isTrusted && FocusedFieldDetector.isTextInput) {
            logDecision("handle \(earlyID ?? "?"): remote-desktop → discard (raw passthrough)")
            discardComposition(); return false
        }

        // EXPERIMENT (log-only): deferred re-probe of the previous keystroke's edit,
        // now that the app's AX tree has had time to settle. See `pendingReprobe`.
        if let p = pendingReprobe {
            pendingReprobe = nil
            reprobeDeferred(p, client)
        }

        // Modifier combos (⌘⌃⌥) are never Telex input: finish and pass through.
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if !mods.isEmpty {
            // Modifier+Delete while a MARKED composition is open: committing and
            // passing the key loses the FIRST press — the just-closing composition
            // session swallows it (Terminal: "goo" → gô, Option+Delete needed two
            // presses to kill the word). The word those shortcuts delete backward IS
            // the composition, so consume the key and kill the composition directly:
            // same net effect, single press. In-place mode has no composition session
            // (text is already real), so it keeps the normal commit-and-pass path.
            if event.keyCode == kDelete, !engine.isEmpty,
               usesMarkedNow(AppState.shared.currentBundleID) {
                client.setMarkedText("", selectionRange: kNoRange, replacementRange: kNoRange)
                engine.reset()
                tracking = false
                spMode = "marked"
                logDecision("marked composition killed by modifier+Delete (single press)")
                return true
            }
            endComposition(client); return false
        }

        // No internal enable/disable: if VietTelex is the active input source we always
        // compose. To type English, switch macOS input source (the OS remembers it
        // per app when "automatically switch" is on).

        // Decide tap-defer by the ACTUAL frontmost app — the SAME source the tap uses
        // (FrontmostApp cache) — not the IMK client id, which can be nil/stale. If the
        // client id is nil we'd otherwise think "unknown app → in-place" and wrongly
        // compose into a terminal the tap is handling; when the tap then leaks a
        // physical key (a brief tapDisabled window), IMKit composes it → intermittent
        // garbage in iTerm/Claude Code. Using the frontmost app keeps controller and
        // tap in sync.
        let frontID = FrontmostApp.shared.bundleID
        let id = AppState.shared.currentBundleID ?? frontID

        // Apps the CGEvent tap handles (terminals via Backspace, Chromium browsers &
        // Spotlight via Shift+Left selection-replace): the tap already intercepted and
        // synthesized these before the IME, so never compose here — let anything that
        // slipped through insert natively.
        // Spotlight types IN-PLACE by default (field-verified clean on macOS 26,
        // even with the gray inline suggestion — the historical autocomplete race
        // that forced tap selection-replace is gone; it's in builtInInPlaceApps).
        // Only an explicit tap-family manual pick still routes it to the tap.
        // ORDER MATTERS for CPU: consult the manual pin FIRST — isVisible kicks a
        // CGWindowList background scan every 200ms while typing, which nobody needs
        // unless Spotlight was explicitly pinned to a tap-family mode (rare).
        let spotlightManual = AppState.shared.manualMode(AppState.spotlightBundleID)
        let spotlightDefersToTap = (spotlightManual == .selection
                || spotlightManual == .tap || spotlightManual == .emptyReset)
            && SpotlightDetector.isVisible
        // ONE lock + one trusted read + (at most) one detector read for the whole
        // decision — this used to be 6 separate calls, each re-locking AppState and
        // several re-reading Accessibility.isTrusted.
        let routing = AppState.shared.tapRouting(id, front: frontID)
        // SPLIT-BRAIN GUARD (lớp bug issue #55): client id routes về họ tap (thường
        // là XPC service lạ rơi vào safe-unknown) nhưng TAP thì quyết theo FRONTMOST
        // — nếu frontmost không thuộc họ tap, tap sẽ pass nguyên phím: IMK nhường,
        // tap cũng nhường, chữ ra THÔ. Phát hiện tại đúng phím này (client id là bên
        // vừa đưa event — không thể thiu; frontmost đọc từ cache đáng tin) và rơi về
        // MARKED cho focus hiện tại: đúng chữ tuyệt đối, chỉ có gạch chân — đúng
        // tinh thần safe-unknown khi kênh tap không với tới. Ca nào field-verify
        // in-place tốt thì thêm rule vào typing-modes.yml như documentPopoverViewService.
        // Không đụng Spotlight (defer vô điều kiện là CHỦ ĐÍCH — đọc NOTE dưới).
        if Self.splitBrainToMarked(clientDefersToTap: routing.tapDefer,
                                   sameApp: id == frontID,
                                   spotlightDefer: spotlightDefersToTap,
                                   alreadyMarked: fieldForcedMarked,
                                   frontDefersToTap: AppState.shared.tapRouting(frontID).tapDefer) {
            fieldForcedMarked = true
            logDecision("split-brain: client \(id ?? "?") routes tap, front \(frontID ?? "?") won't engage → marked for this focus")
            Signposts.log.notice("split-brain → marked: client=\(id ?? "?", privacy: .public) front=\(frontID ?? "?", privacy: .public)")
        }
        if (routing.tapDefer && !fieldForcedMarked) || spotlightDefersToTap {
            // NOTE: SpotlightDetector.isVisible defers UNCONDITIONALLY, even when the
            // tap is dormant (Accessibility not trusted / sandboxed build). That means
            // Spotlight typing gets raw passthrough with NO composition at all. This is
            // INTENTIONAL, not a bug: IMKit composing into Spotlight's inline
            // autocomplete corrupts the text, so raw passthrough is the lesser evil.
            // Do not "fix" this by gating on Accessibility.isTrusted.
            spMode = "tap-defer"
            // tapAlive/quar/tripped: a tap-defer while the tap is dead is the "raw
            // ASCII, status OK" failure — without these three fields the log cannot
            // distinguish "tap composed this key" from "nobody did" (2026-07-30).
            // Only evaluated when debugLogging is on (autoclosure).
            logDecision("handle \(id ?? "?")/front=\(frontID ?? "?"): tap-defer "
                + "(tap=\(routing.tap) sel=\(routing.selection) empty=\(routing.emptyReset) "
                + "spotlight=\(SpotlightDetector.isVisible) "
                + "tapAlive=\(TerminalTapController.shared.isRunning) "
                + "quar=\(TerminalTapController.shared.isQuarantined) "
                + "tripped=\(SyntheticKeyboard.tripped))")
            return false
        }
        logDecision("handle \(id ?? "?")/front=\(frontID ?? "?"): "
            + "\(usesMarkedNow(id) ? "marked" : "in-place") "
            + "needsProbe=\(AppState.shared.needsProbe(id))")
        // Only resolve the label when something is actually recording. `usesMarkedNow`
        // is NOT cheap — it re-runs the whole per-app + per-field policy (≈50 set
        // ONE resolution of the marked decision for this key, reused by every branch
        // below. `usesMarkedNow` is NOT cheap — it re-runs the whole per-app + per-field
        // policy (≈50 set lookups + several lock trips), and it used to be called 3–4
        // times per keystroke. Safe to reuse within one call: the only thing that flips
        // it mid-key is a verify demotion inside probeInPlace, and every path that can
        // reach probeInPlace (⌫, boundary keys, replace) RETURNS before the reuse sites.
        // Perf audit 17/08/2026.
        let markedNow = usesMarkedNow(id)
        spMode = markedNow ? "marked"
               : (tracking || engine.isEmpty ? "in-place" : "in-place-per-op")

        // Reflect the current "bỏ dấu tự do" setting before any engine op (feed,
        // backspace and boundary all re-parse `raw` and honor this flag).
        engine.apply(AppState.shared.engineFlags())

        switch event.keyCode {
        case kDelete:
            if engine.isEmpty {
                // ⌫ on the boundary character the last word ended with puts the caret
                // back at that word's end, and the user is going to keep editing it
                // ("tháy" ␣ ⌫ then `a` → "thấy" — issue #40). Re-open it into the buffer
                // so the next key modifies the word instead of starting a new one.
                if tryReopenLastCommit(client, id: id) { return false }
                // Backspacing with an empty buffer deletes previously-committed text: the
                // "previous word" relationship is now unclear, so drop the English context
                // (undetermined → Vietnamese). In-word backspace (buffer non-empty) keeps it —
                // the preceding word hasn't changed.
                engine.resetContext()
                return false
            }
            // Our tracked window must still MATCH the field before we rewrite it. A
            // ⌫-rewrite is `insertText(composed, range(anchor, onLen))`: if the app has
            // meanwhile moved the caret, re-rendered (React-controlled inputs do), or
            // holds a SELECTION (inline autocomplete suffix), that range covers text we
            // never composed — the rewrite then eats an extra character, and every later
            // insert targets a range that no longer exists, so nothing shows up until a
            // space re-anchors the word. Tester report 2026-07-27 (Chrome Web Store search
            // box: "lần đầu xóa liền 2 ký tự, sau đó gõ không hiện gì nữa"). On any
            // disagreement, hand the key to the app and forget the composition: the user
            // loses a diacritic re-placement on that ⌫, never text.
            //
            // IN-PLACE ONLY (issue #37, 2026-08-13): this window arithmetic guards the
            // insertText(range) rewrite that marked mode never performs — a marked ⌫
            // goes engine.backspace() → setMarkedText, correct by the composition
            // session itself. `tracking` is still set at word-start in marked mode
            // while `onLen` never advances there, so `expected` stayed at the anchor
            // and Safari+Google-Docs (caret reported at the marked text's END) tripped
            // the guard on the FIRST mid-word ⌫: composition dropped, the underlined
            // text orphaned on screen, every later ⌫/space dead until a click —
            // reporter's "không thể xoá cũng như bấm space để thoát khỏi từ".
            if tracking, Self.backspaceFreshnessGuardApplies(marked: markedNow) {
                let sel = client.selectedRange()
                let expected = anchor + onLen
                if !Self.trackedWindowIsFresh(caret: sel.location == NSNotFound ? nil : sel.location,
                                              selectionLength: sel.length, expected: expected) {
                    // host: DIAGNOSTIC ONLY (FocusedFieldDetector.debugLastHost, never
                    // routing) — names the site for a future report on a lag this deep
                    // (field report 2026-08-06: caret behind by 6, past the Discord-class
                    // tolerance, on an unidentified Chrome tab).
                    DebugLog.log("backspace: tracked window stale "
                        + "(caret=\(sel.location == NSNotFound ? "NotFound" : String(sel.location))"
                        + " len=\(sel.length) expected=\(expected) host=\(FocusedFieldDetector.debugLastHost ?? "?")) "
                        + "→ pass through, drop composition")
                    dropComposition(cause: "backspace-window-stale")
                    onLen = 0
                    return false
                }
            }
            let action = engine.backspace()
            // OVERFLOW (word longer than the engine's 32-char capacity): backspace()
            // returns .passthrough and the app must delete natively — the engine's view
            // is a stale 32-char prefix of what is on screen. Must be decided BEFORE
            // either the marked or the tracking branch: marked would re-set the same
            // prefix and swallow the key; the tracking rewrite would wipe every
            // overflow character on the first ⌫ and then rewrite identical text
            // forever (⌫ dead for the rest of the word).
            switch Self.passthroughPlan(overflowPassthrough: Self.isPassthrough(action) && engine.isOverflowed,
                                        marked: markedNow, isBackspace: true) {
            case .commitAndPassThrough:
                endComposition(client)
                return false
            case .shrinkWindowAndPassThrough:
                onLen = max(0, onLen - 1)
                return false
            case .honorEngineAction:
                break
            }
            if markedNow { updateMarked(client); return true }
            if edgeTapWord {
                // Edge word stays on the CGEvent channel: plain deletion passes the
                // physical ⌫ through; a tone re-place ("toán"->"tóa") goes synthetic.
                switch action {
                case let .replace(_, insert) where insert.isEmpty:
                    onLen = max(0, onLen - 1)
                    if engine.isEmpty { tracking = false; edgeTapWord = false }
                    return false
                case let .replace(bs, insert):
                    noteEdgeBurst(SyntheticKeyboard.applyForEdge(backspaces: bs, insert: insert))
                    onLen = (engine.composed as NSString).length
                    return true
                default:
                    return true
                }
            }
            if tracking {
                // Rewrite the whole composition via insertText (ordered, non-empty);
                // also handles tone re-placement on delete ("toán"->"tóa").
                let composed = engine.composed
                if composed.isEmpty {
                    // Last glyph gone: physical Backspace removes the remaining char
                    // (insertText("", range) is a no-op in some apps).
                    onLen = 0; tracking = false
                    return false
                }
                client.insertText(composed, replacementRange: NSRange(location: anchor, length: onLen))
                onLen = (composed as NSString).length
                return true
            }
            // Non-tracking (per-op selectedRange): apply the diff action.
            switch action {
            case let .replace(_, insert) where insert.isEmpty:
                return false                       // physical Backspace
            case let .replace(bs, insert):
                applyInPlace(bs: bs, insert: insert, client)   // tone re-place: "toán"->"tóa"
                return true
            default:
                return true
            }

        case kReturn, kEnter, kTab, kEscape:
            // A newline starts a fresh line/prompt with no preceding word ("is" → "í"):
            // reset AFTER boundary() commits + classifies the current word. The defer
            // must live at CASE scope — nested inside `if { defer {...} }` its scope is
            // that if-block and it fires IMMEDIATELY, wiping the context BEFORE
            // boundary() decides the restore ("early too⏎" sent "early tô" while
            // "early too␣" restored fine — field report 15/08/2026, WhatsApp).
            let newlineKey = event.keyCode == kReturn || event.keyCode == kEnter
            defer { if newlineKey { engine.resetContext() } }
            // KNOWN LIMITATION — while a MARKED composition is open in a terminal,
            // the first boundary press only commits; the second acts ("vậy⏎⏎").
            // Tried and closed (2026-07-21): delivering the key's byte through
            // insertText after the commit — Terminal STRIPS control characters
            // (\r, \n, \t, ESC) from IME-inserted text (paste-bracketing-style
            // sanitizing; branch fired in logs, nothing reached the pty). This
            // two-press behavior is also standard CJK composition UX. Single-press
            // Enter in terminals is what the TAP path provides — grant Accessibility.
            boundaryCommitInFlight = true
            let wasEdge = edgeTapWord
            let rewrote = boundary(client)
            boundaryCommitInFlight = false
            // Return/Tab/Esc do not put ONE character after the word the way a space
            // does — Enter sends the message in a chat app, Tab moves focus, Esc
            // inserts nothing — so a following ⌫ is not deleting a boundary character
            // and must not re-open the word (see tryReopenLastCommit).
            engine.forgetLastCommit()
            logDecision("boundary-key code=\(event.keyCode) rewrote=\(rewrote)")
            // When the commit REWROTE the word (gõ tắt "ko"→"không", auto-restore
            // "thooiiii"), web-view editors (WhatsApp) apply that insertText
            // asynchronously — an immediately-delivered Return fires "send" on the
            // OLD text. With Accessibility we swallow the real key and re-post a
            // stamped COPY of it (HID source intact) so it lands AFTER the edit;
            // the copy re-enters handle() with an empty engine and passes through.
            // EDGE (Slate-class): burst async vừa post — Return PHẢI được nuốt và
            // re-post sau burst; Slate không tự chèn newline cho phím bị nuốt nên
            // không double (Discord verified). Check TRƯỚC nhánh pin bên dưới.
            if rewrote, wasEdge, Accessibility.isTrusted, let cg = event.cgEvent {
                SyntheticKeyboard.postBoundaryCopy(of: cg)
                return true
            }
            // MANUAL In-place pin (không phải built-in): expansion vừa áp SYNC qua
            // insertText ngay trong handle này, nên Return native theo sau là ĐÃ
            // đúng thứ tự — trả false, không nuốt, không re-post. Nuốt+re-post ở
            // đây nhân đôi newline trên Quill/ProseMirror (Slack/Claude): composer
            // các app đó tự chèn newline cho cả phím Return bị IME nuốt (field
            // 07/08: 'ko'+Shift+Enter → 'không' + 2 dòng). Built-in in-place
            // (WhatsApp) giữ nuốt+re-post: insertText của nó áp async, Return
            // native sẽ gửi tin nhắn với text CŨ (field 1.5.1).
            if rewrote, AppState.shared.manualMode(AppState.shared.currentBundleID) == .inPlace {
                return false
            }
            if rewrote, Accessibility.isTrusted, let cg = event.cgEvent {
                // Web editor ở lớp MARKED (Docs canvas, comment box TikTok): insertText
                // của commit áp BẤT ĐỒNG BỘ vào model JS, nên Enter re-post ngay lập
                // tức vẫn tới TRƯỚC khi DOM có từ cuối → app "gửi" với text CŨ (field
                // report 19/08: gõ "thử xem" + Enter → TikTok post ra mỗi "thử").
                // Hoãn một nhịp bằng asyncAfter — KHÁC hẳn vụ nhịp-trong-callback đã
                // revert cùng ngày: ở đây callback trả về NGAY, không giữ cửa phím nào.
                let key = CGKeyCode(cg.getIntegerValueField(.keyboardEventKeycode))
                let flags = cg.flags
                if let ms = Self.boundaryRepostDelayMs(markedWebField: markedNow
                                                        && FocusedFieldDetector.wantsMarkedField) {
                    logDecision("boundary re-post hoãn \(ms)ms (marked web editor)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
                        SyntheticKeyboard.postBoundaryKey(key, flags: flags)
                    }
                } else {
                    SyntheticKeyboard.postBoundaryCopy(of: cg)
                }
                return true
            }
            // No Accessibility → no re-post. Returning false raced the async
            // MARKED commit and the terminal submitted the line missing its tail
            // ("cho tôi⏎" → "cho tô", tester log #6 2026-07-23, Warp untrusted).
            // Swallow instead: first press commits the word, the second acts —
            // the documented two-press UX for marked compositions, no text loss.
            if rewrote, !Accessibility.isTrusted,
               usesMarkedNow(AppState.shared.currentBundleID) {
                return true
            }
            return false

        default:
            break
        }

        // VNI: the DIGITS carry the diacritics ("a1"→á, "tie61ng"→tiếng), so in VNI mode
        // they must reach the engine instead of ending the word. In Telex a digit is a
        // boundary as before (field report issue #28, 2026-07-27: VNI did nothing in the
        // app because every digit was consumed here — engine-level VNI tests all passed).
        guard let chars = effectiveCharacters(event), let ch = chars.first, let ascii = ch.asciiValue,
              isWordKey(ascii, vniMode: engine.vniMode,
                        bracketVowels: engine.bracketVowels) else {
            // space / punctuation / any non-letter ends the word. Brackets signal a
            // code-ish context (arr[i], {json}, (x)); skip auto-restore there so a
            // token isn't "corrected" (auto-restore is off around [ ] { }).
            // The composed word itself is committed unchanged.
            let boundaryChar = effectiveCharacters(event)?.utf8.first
            let wasEdge = edgeTapWord
            let rewrote = boundary(client, suppressAutoRestore: boundaryChar.map(isBracket) ?? false)
            // Only a key that leaves exactly ONE character after the word may be
            // ⌫-ed back into it (issue #40). Arrow/function keys land here too — they
            // move the caret and insert nothing, so the word is no longer adjacent.
            if !Self.insertsOneCharacter(effectiveCharacters(event)) { engine.forgetLastCommit() }
            // Edge word rewritten at the boundary (shortcut/auto-restore): the
            // rewrite is a synthetic burst still in the session queue — a native
            // boundary key would overtake it. Same cure as Return below: swallow
            // and re-post so the key lands AFTER the burst.
            if rewrote, wasEdge, Accessibility.isTrusted, let cg = event.cgEvent {
                SyntheticKeyboard.postBoundaryCopy(of: cg)
                return true
            }
            if let remapped = remappedInsert(event) {
                client.insertText(remapped, replacementRange: kNoRange)
                return true
            }
            return false
        }

        // First key of a new word: anchor the caret once (never again mid-word).
        // If the app can't report a caret here (some Electron apps: Claude), fall
        // back to per-op selectedRange (still in-place, no underline) rather than
        // forcing marked text. Only a failed probe pushes an app to marked text.
        if engine.isEmpty {
            let sel = client.selectedRange()
            if distrustNextAnchor {
                // Spotlight's session just cycled (see lastSpotlightActivateNs) — the
                // caret it reports for this first key cannot be trusted (measured:
                // start=6632 in a field that was actually empty). Same safe path as
                // "no caret at all": skip tracking for this one word rather than
                // anchor on a number that will garble every insert after it.
                distrustNextAnchor = false
                tracking = false; selToClear = 0
                DebugLog.log("word-start anchor distrusted (post-Spotlight-cycle): reported loc=\(sel.location)")
            } else if sel.location != NSNotFound {
                // A non-empty selection (e.g. after ⌘A) must be OVERWRITTEN by the
                // first key, not inserted-before. Remember its length and fold it
                // into the first insert's replacementRange below.
                anchor = sel.location; onLen = 0; tracking = true
                anchorVerified = false
                selToClear = sel.length
                // Diagnostic (counts only, never text): field report 2026-08-06
                // ("bôi đen rồi gõ … thay vì replace thì viết thêm") has no log
                // evidence yet of WHERE the fold breaks — this pins whether a
                // selection was even seen at word-start, so a future capture can
                // show whether the re-anchor below (fresh caret further right)
                // shifted `anchor` out from under this `selToClear` extent.
                if sel.length > 0 {
                    DebugLog.log("selection at word-start: loc=\(sel.location) len=\(sel.length)")
                }
            } else {
                tracking = false; selToClear = 0
            }
            // Edge chỉ cho composer Slate-class (append ở offset 0). Đo 07/08:
            // Quill (Slack) honor offset-0 → đi insertText trực tiếp, và Return
            // với nó KHÔNG được nuốt/re-post (xem offset0AppendApps).
            edgeTapWord = AppState.offset0AppendApps.contains(id ?? "")
                && Self.edgeTapEligible(
                manualInPlace: AppState.shared.manualMode(id) == .inPlace,
                caret: (tracking && sel.location != NSNotFound) ? sel.location : nil,
                trusted: Accessibility.isTrusted)
            // Diagnostic: Discord/Slate reports a NONZERO caret in an EMPTY message
            // box (field 06/08: "cos" still → "coó" with the pin; probe start=2 ⇒
            // word anchored at 1). Pin the actual value per app before widening
            // the eligibility predicate. Pinned-app word starts only, counts only.
            if AppState.shared.manualMode(id) == .inPlace {
                logDecision("word-start pin-inPlace caret=\(sel.location == NSNotFound ? -1 : sel.location) selLen=\(sel.length) edge=\(edgeTapWord)")
            }
        }

        // RE-EDIT (experimental, opt-in): a tone/mark key on an EMPTY engine right after a
        // word means "add this diacritic to that word" ("toan" + s → toán). Seed the
        // engine from the text on screen so the normal replace machinery does the edit.
        if engine.isEmpty, tracking, selToClear == 0,
           AppState.shared.reEditWord, Self.isDiacriticOnlyKey(ascii, vni: engine.vniMode) {
            tryReEditWord(caret: anchor, client, id: id)
        }

        let action = engine.feed(ch)
        // OVERFLOW in a MARKED app: feed() returned .passthrough WITHOUT recording the
        // key, so re-setting the marked text (unchanged 32-char prefix) while consuming
        // the event made the 33rd+ characters vanish. Mirror the tap's overflow
        // handling: finalize what is composed, then deliver the key through the SAME
        // ordered insertText channel (returning false would race the async marked
        // commit in terminals — see the Return-key note above). The
        // engine restarts on the next key, so the tail composes as a fresh syllable —
        // no diacritic re-placement across the 32-char break, but never lost text.
        // (In-place mode is unaffected: its .passthrough branch inserts the letter
        // itself, which is already correct.)
        if case .commitAndPassThrough = Self.passthroughPlan(overflowPassthrough: Self.isPassthrough(action) && engine.isOverflowed,
                                                            marked: markedNow, isBackspace: false) {
            endComposition(client)
            client.insertText(String(ch), replacementRange: kNoRange)
            return true
        }
        if markedNow { updateMarked(client); return true }
        switch action {
        case .passthrough:
            if edgeTapWord, KeyboardLayoutOverride.translator == nil {
                // Edge word: the app inserts the raw key natively — same CGEvent
                // queue as the synthetic replaces below, so ordering holds. A
                // selection at offset 0 (⌘A) is overwritten by the native key.
                // (With a layout pinned, "natively" would type the WRONG letter —
                // fall through to the insertText path, which carries our character.)
                selToClear = 0
                onLen += 1
                return false
            }
            // Insert the letter ourselves (do NOT return false to let the system
            // insert it): mixing a system passthrough-insert with our insertText
            // transforms races under fast typing and corrupts words ("được"->"đựoc").
            // Every edit must go through the one ordered insertText channel.
            if tracking {
                if selToClear > 0 {
                    DebugLog.log("selection fold (letter) \(id ?? "?"): range=(\(anchor + onLen),\(selToClear))")
                }
                client.insertText(String(ch), replacementRange: NSRange(location: anchor + onLen, length: selToClear))
                selToClear = 0
                onLen += 1
            } else {
                client.insertText(String(ch), replacementRange: kNoRange)
            }
            return true
        case .none:
            return true
        case let .replace(bs, insert):
            if edgeTapWord {
                noteEdgeBurst(SyntheticKeyboard.applyForEdge(backspaces: bs, insert: insert))
                onLen = (engine.composed as NSString).length
                return true
            }
            applyInPlace(bs: bs, insert: insert, client)
            return true
        }
    }


    /// The ⌫ freshness guard protects the IN-PLACE rewrite only — marked mode edits
    /// through its composition session (engine.backspace → setMarkedText) and needs no
    /// window arithmetic; running the guard there is what orphaned Google-Docs-in-
    /// Safari compositions (issue #37: `onLen` never advances in marked mode, so the
    /// guard compared the caret against the ANCHOR and dropped the word on the first
    /// mid-word ⌫). Pure so the polarity is pinned by tests.
    static func backspaceFreshnessGuardApplies(marked: Bool) -> Bool { !marked }

    /// Does the app's caret still agree with our tracked composition window? Only then
    /// may a ⌫ rewrite the window blind. Three ways it can lie, all fatal to the
    /// arithmetic: no caret at all, a live SELECTION (an inline autocomplete suffix would
    /// be swallowed by our replacementRange), or a caret anywhere other than exactly the
    /// end of what we composed (the app re-rendered or moved it). Pure function so the
    /// rule is pinned by tests — the failure it prevents (an extra character eaten, then
    /// every later insert landing nowhere) is invisible in a log until it's too late.
    static func trackedWindowIsFresh(caret: Int?, selectionLength: Int, expected: Int) -> Bool {
        guard let caret else { return false }
        guard selectionLength == 0 else { return false }
        // Exact match OR within the Chromium stale-caret lag window: right after our
        // insertText, Chromium answers selectedRange from a cache that is one edit
        // behind (the SAME staleness InPlaceProbe.verdict tolerates — Discord-web
        // 2026-08-05: caret=18 expected=19 on ⌫ made this check drop the composition
        // and pass the delete natively → "xóa linh tinh, mất chữ đ"). The caret here
        // is only a FRESHNESS WITNESS — the rewrite range comes from our own
        // anchor/onLen bookkeeping, which the deferred AX reads confirmed correct in
        // every measured stale-answer case. A caret AHEAD of expected, any live
        // selection (inline autocomplete), or a lag beyond the window still drops —
        // that is the 2026-07-27 Chrome Web Store class this guard exists for.
        let lag = expected - caret
        return lag >= 0 && lag <= InPlaceProbe.maxCaretLag
    }

    // MARK: - Engine .passthrough (32-char overflow) contract

    /// What the controller must do when the engine answers `.passthrough`.
    enum PassthroughPlan: Equatable {
        /// Not a passthrough (or a case the normal branches already handle correctly):
        /// carry on with the regular marked / in-place handling.
        case honorEngineAction
        /// Marked-text app: finalize the composition, then let the key act on real text.
        /// Re-setting the marked string here would re-render an unchanged stale prefix
        /// and swallow the key.
        case commitAndPassThrough
        /// Tracked in-place ⌫: the app deletes the character natively, so our tracked
        /// window shrinks by one and NOTHING may be rewritten.
        case shrinkWindowAndPassThrough
    }

    /// Once a word exceeds the engine's 32-key capacity it answers `.passthrough`
    /// WITHOUT recording the key: its `raw`/`composed` view is a stale prefix of what is
    /// on screen, so it refuses to diff and the APP must handle the key. The action
    /// alone is NOT the signal — an ordinary literal letter also answers `.passthrough`
    /// (recorded, composition live) — so callers must gate on `engine.isOverflowed` too;
    /// treating every passthrough as overflow committed the marked composition on the
    /// FIRST letter of every word. Pure function because both violations this pins were
    /// silent in logs: a tracked ⌫ that rewrote the window wiped every overflow
    /// character and then went dead for the rest of the word, and a marked-text app
    /// that re-set its unchanged prefix dropped the 33rd+ letters outright.
    static func passthroughPlan(overflowPassthrough: Bool, marked: Bool, isBackspace: Bool) -> PassthroughPlan {
        guard overflowPassthrough else { return .honorEngineAction }
        if marked { return .commitAndPassThrough }
        // In-place ⌫: never rewrite. In-place letter: the existing `.passthrough` branch
        // already inserts the character through our own ordered channel — leave it.
        return isBackspace ? .shrinkWindowAndPassThrough : .honorEngineAction
    }

    static func isPassthrough(_ action: TelexAction) -> Bool {
        if case .passthrough = action { return true }
        return false
    }

    // MARK: - Re-edit the word before the caret (experimental)

    /// Does this key put exactly ONE printable character on screen after the word it
    /// just ended? Only then is the next ⌫ deleting a boundary character, which is the
    /// precondition for re-opening the word (issue #40, see `tryReopenLastCommit`).
    /// Printable ASCII only: a non-ascii scalar (arrow/function keys arrive as
    /// U+F700…, option-key symbols as real text) either isn't inserted at all or isn't
    /// something worth reasoning about. Pure so the rule is pinned by tests.
    /// What this key would type on the layout the user pinned. Falls back to
    /// `event.characters` — the pre-pin behaviour — whenever no remapping is in force,
    /// which is every case except "pinned a layout AND macOS is on a different one".
    /// Modifier combos never reach here: handle() passes ⌘⌃⌥ through before this.
    private func effectiveCharacters(_ event: NSEvent) -> String? {
        guard let translator = KeyboardLayoutOverride.translator,
              let ch = translator.character(keyCode: event.keyCode,
                                            shift: event.modifierFlags.contains(.shift))
        else { return event.characters }
        return String(ch)
    }

    /// Text to insert in place of the system's, for a key we would otherwise let
    /// macOS type. nil = pass through untouched, exactly as before.
    ///
    /// Returning false from handle() means "macOS, type this key" — and macOS types
    /// it with the layout we are overriding. So wherever a pass-through would now
    /// produce the wrong letter, we have to insert ours and swallow the key instead.
    private func remappedInsert(_ event: NSEvent) -> String? {
        guard KeyboardLayoutOverride.translator != nil,
              let ours = effectiveCharacters(event),
              ours != event.characters,
              Self.insertsOneCharacter(ours)
        else { return nil }
        return ours
    }

    static func insertsOneCharacter(_ characters: String?) -> Bool {
        guard let characters, characters.count == 1,
              let ascii = characters.first?.asciiValue else { return false }
        return ascii >= 0x20 && ascii != 0x7F
    }

    /// Keys that can only ever ADD a diacritic, never a letter: the Telex tone keys
    /// (s f r x j), the tone remover (z) and the horn/breve modifier (w) — or, in VNI,
    /// the digits. The doubler letters (a e o d) are deliberately NOT here: they are
    /// ordinary letters too, so a plain "ca" + "a" keeps behaving exactly as before and
    /// re-edit costs a text read-back only on keys that are unambiguously modifiers.
    static func isDiacriticOnlyKey(_ ascii: UInt8, vni: Bool) -> Bool {
        if vni { return isAsciiDigit(ascii) }
        switch ascii | 0x20 {                     // fold case
        case UInt8(ascii: "s"), UInt8(ascii: "f"), UInt8(ascii: "r"), UInt8(ascii: "x"),
             UInt8(ascii: "j"), UInt8(ascii: "z"), UInt8(ascii: "w"):
            return true
        default:
            return false
        }
    }

    /// The trailing word in `text` (the characters just before the caret) that a
    /// diacritic key could still modify. Letters only — it stops at a space, digit,
    /// punctuation or symbol, so "mp3", "a-b" and "x)" have no re-editable tail. Returns
    /// nil when there is none, or when the run is longer than a syllable can be (the
    /// engine would refuse it anyway, and reading further is pointless).
    static func trailingWord(_ text: String, maxLength: Int = 12) -> String? {
        var word = ""
        for ch in text.reversed() {
            guard ch.isLetter else { break }
            word.insert(ch, at: word.startIndex)
            if word.count > maxLength { return nil }
        }
        return word.isEmpty ? nil : word
    }

    /// Seed the engine from the word already on screen so the key about to be fed edits
    /// IT instead of starting a new one. Silent no-op whenever anything is uncertain —
    /// the alternative is rewriting text the user never asked to change:
    ///  • only apps already PROVEN to honor in-place replacement (learned in-place),
    ///    never a marked-text field and never a per-field/omnibox browser field whose
    ///    inline autocomplete rewrites text underneath us;
    ///  • only a canonical (precomposed) read-back — an NFD field would make our UTF-16
    ///    arithmetic cut into combining marks;
    ///  • only when `engine.seed` ROUND-TRIPS the word, which is what rejects English
    ///    words, other tone-placement styles and anything untypable.
    private func tryReEditWord(caret: Int, _ client: IMKTextInput, id: String?) {
        guard caret > 0, AppState.shared.isLearnedInPlace(id), !usesMarkedNow(id) else { return }
        // Browsers are excluded PER FIELD, not per app: only the address/search bar has the
        // inline autocomplete that makes re-editing unsafe, and blanket-excluding every
        // browser turned the feature off exactly where people type most — inside the page
        // (report 2026-07-27: "đưa con trỏ về sau chữ 'toán', ấn 2 … không được", in Zen).
        if AppState.shared.usesAxDetect(id), FocusedFieldDetector.wantsSelection {
            DebugLog.log("re-edit \(id ?? "?"): skipped (field resolves to selection-replace)")
            return
        }
        let window = min(caret, 24)
        guard let sub = client.attributedSubstring(from: NSRange(location: caret - window,
                                                                 length: window)) else { return }
        let text = sub.string
        guard text == text.precomposedStringWithCanonicalMapping else {
            DebugLog.log("re-edit \(id ?? "?"): skipped (field text is not precomposed)")
            return
        }
        guard let word = Self.trailingWord(text) else { return }
        let wordLen = (word as NSString).length
        guard wordLen <= caret, engine.seed(word) else { return }
        // The composition now IS that on-screen word: point the tracking window at it so
        // the next replace lands on the word's own characters. `anchorVerified` is set —
        // the anchor came from a caret read taken one line ago, not a stale word start.
        anchor = caret - wordLen
        onLen = wordLen
        anchorVerified = true
        DebugLog.log("re-edit \(id ?? "?"): seeded \(wordLen) chars before caret")
    }

    // MARK: - Re-open the last committed word on ⌫ (issue #40)

    /// The ⌫ about to be delivered deletes the boundary character that ended the last
    /// word — so put that word back in the buffer, the way every other Vietnamese IME
    /// does ("tháy" ␣ ⌫ `a` → "thấy" instead of "tháya").
    ///
    /// Unlike `tryReEditWord` this never guesses WHICH word: the engine kept the exact
    /// keystrokes it committed, and only while nothing else touched it since. What is
    /// still unknown is whether the SCREEN agrees — the app may have swallowed the
    /// boundary key, autocorrected the word, or moved the caret — so the characters the
    /// word should occupy are read back and compared before anything is re-opened. On
    /// any disagreement the composition is dropped and the ⌫ behaves exactly as before.
    /// Returns true iff the buffer now holds the word; the ⌫ itself always passes
    /// through and deletes the boundary character.
    private func tryReopenLastCommit(_ client: IMKTextInput, id: String?) -> Bool {
        // Gated behind the SAME experimental toggle as re-edit (maintainer decision
        // 13/08/2026): both features answer "may an empty-engine key reach back into
        // the word before the caret?", so one opt-in covers the pair. Default OFF —
        // the reEdit 1.4.28 default-ON revert is the standing lesson.
        guard AppState.shared.reEditWord else { return false }
        // Marked-text apps commit through setMarkedText/insertText, so the word on
        // screen is finalized text no composition can reclaim.
        guard engine.canReopenLastCommit, !usesMarkedNow(id) else { return false }
        // Same per-FIELD exclusion as `tryReEditWord`: an omnibox/search bar rewrites
        // text underneath us via inline autocomplete, so the replace that follows a
        // re-open would land in a field that is editing itself. (Reachable from here
        // whenever the tap is not running — no Accessibility — and IMKit handles the
        // browser in-place.)
        if AppState.shared.usesAxDetect(id), FocusedFieldDetector.wantsSelection {
            engine.forgetLastCommit()
            DebugLog.log("⌫ re-open \(id ?? "?"): skipped (field resolves to selection-replace)")
            return false
        }
        let sel = client.selectedRange()
        // A live SELECTION means this ⌫ deletes that instead of the boundary character,
        // and with no caret there is no anchor to re-open at. Either way: forget the
        // word — the boundary character is gone by the next key, so a later ⌫ must not
        // resurrect it.
        guard sel.location != NSNotFound, sel.length == 0 else {
            engine.forgetLastCommit()
            return false
        }
        guard let word = engine.reopenLastCommit() else { return false }
        let wordLen = (word as NSString).length
        let start = sel.location - 1 - wordLen          // this ⌫ removes the boundary char
        guard start >= 0,
              let sub = client.attributedSubstring(from: NSRange(location: start, length: wordLen)),
              sub.string == word                        // NFD field ⇒ mismatch ⇒ skip, as intended
        else {
            engine.reset()
            DebugLog.log("⌫ re-open \(id ?? "?"): skipped (screen disagrees)")
            return false
        }
        // The composition IS that on-screen word now: point the tracking window at it,
        // exactly like the re-edit path does after a successful seed.
        anchor = start
        onLen = wordLen
        tracking = true
        anchorVerified = true
        selToClear = 0
        edgeTapWord = false
        DebugLog.log("⌫ re-open \(id ?? "?"): \(wordLen) chars back in the buffer")
        return true
    }

    // MARK: - In-place mode (default: no marked text, caret stays at end)

    /// Replace `bs` chars before the caret with `insert`, using our locally tracked
    /// position (no per-key selectedRange()). Unclassified apps are probed on the
    /// first real replace (read-back at the target region); apps that ignore
    /// replacementRange (Terminal) flip to marked text.
    private func applyInPlace(bs: Int, insert: String, _ client: IMKTextInput) {
        let id = AppState.shared.currentBundleID
        let start: Int
        // A pending selection (e.g. after ⌘A) must be overwritten by this first
        // replacement, exactly as the .passthrough branch does. selToClear is only set
        // while tracking; fold it into the replacementRange so the selection is removed
        // by the same insert, then clear it (a later insert must not re-scope to it).
        // On a first-key replace bs == 0, so start == anchor and the range is
        // (anchor, selToClear) — the whole selection. onLen must NOT subtract
        // selToClear: the selection was never part of the composition length, so
        // `onLen += insert.length - bs` stays correct after the removal.
        var clear = 0
        if tracking {
            // One-shot RE-ANCHOR at the word's first replace. Right after a newline
            // (Discord/Slate-class editors) the word-start selectedRange read is
            // STALE — it still reports the pre-newline caret, so the anchor is short
            // and the first tone edit writes into the wrong spot ("thử" typed on a
            // fresh line came out "thuử"). By the first replace the editor has
            // settled, so re-read once; trust the fresh caret ONLY when it is
            // FURTHER RIGHT than expected — a smaller read is the old fast-typing
            // staleness ("được"→"đựoc") that the once-per-word anchor exists to
            // ignore.
            if !anchorVerified {
                anchorVerified = true
                let fresh = client.selectedRange()
                let expected = anchor + onLen
                if fresh.location != NSNotFound, fresh.location > expected {
                    // selToClear (if any) was captured against the OLD anchor — a
                    // shift here moves `start` below but NOT the selection's own
                    // extent, so a pending selection at this exact moment is the
                    // scenario the 2026-08-06 "bôi đen … viết thêm thay vì replace"
                    // report needs to distinguish (see the word-start log).
                    DebugLog.log("re-anchor \(id ?? "?"): stale word-start caret, +\(fresh.location - expected)"
                        + (selToClear > 0 ? " (pending selToClear=\(selToClear))" : ""))
                    anchor += fresh.location - expected
                }
            }
            start = anchor + onLen - bs
            clear = selToClear
            selToClear = 0
            logDecision("applyInPlace \(id ?? "?"): start=\(start) bs=\(bs) insLen=\((insert as NSString).length) clear=\(clear) anchor=\(anchor) onLen=\(onLen)")
            if clear > 0 {
                DebugLog.log("selection fold \(id ?? "?"): range=(\(start),\(bs + clear)) bs=\(bs) clear=\(clear)")
            }
        } else {
            let sel = client.selectedRange()
            guard sel.location != NSNotFound, sel.location >= bs else {
                // The key is consumed with NOTHING inserted — if an app lands here on
                // every keystroke, typing shows nothing at all. Log it loudly.
                DebugLog.log("in-place ABORT \(id ?? "?"): selectedRange=\(sel.location == NSNotFound ? "NotFound" : String(sel.location)) bs=\(bs) → marked next word, key swallowed")
                inPlaceFailedHard(id); return
            }
            start = sel.location - bs
        }
        guard start >= 0 else {
            DebugLog.log("in-place ABORT \(id ?? "?"): start=\(start) < 0, key swallowed")
            inPlaceFailedHard(id); return
        }
        client.insertText(insert, replacementRange: NSRange(location: start, length: bs + clear))
        onLen += (insert as NSString).length - bs

        // Probe ONLY on a real, clean replacement (bs > 0, no pending selection).
        // A pure insert (bs == 0) lands identically whether or not the app honors
        // replacementRange, so it must never CONFIRM "in-place good" — that premature
        // confirm on a plain insert was the false-positive that locked iTerm2/WhatsApp
        // onto the broken in-place path. Only a replace distinguishes the two.
        let realProbe = InPlaceProbe.shouldProbe(insertLength: (insert as NSString).length,
                                                 bs: bs, clear: clear,
                                                 needsProbe: AppState.shared.needsProbe(id))
        // EXPERIMENT: with debugLogging on, also SHADOW-probe apps that are already
        // classified (or manually pinned to in-place) — same reads, same logs, but the
        // verdict is never acted on. This is how the deferred re-probe can be exercised
        // against Lark (pin it to In-place in Thử Nghiệm → App mode, enable Debug
        // logging, type a few tone edits, copy the log).
        // Per-focus VERIFY of a learned-in-place app: the first real replacement in
        // each focus re-checks that THIS field honors replacementRange (sites inside
        // one browser differ — see fieldVerified). Passive on good fields (read-only
        // probe of an edit that already happened); a failure demotes this focus to
        // marked text. This is NOT the removed 2026-07-21 session-field probation:
        // unknown apps aren't re-probed per focus — only apps already classified
        // in-place-good get a read-back check, so good fields never glitch.
        let verifyProbe = !realProbe && !fieldVerified
            && AppState.shared.isLearnedInPlace(id)
            && InPlaceProbe.shouldProbe(insertLength: (insert as NSString).length,
                                        bs: bs, clear: clear, needsProbe: true)
        // Throttled: the shadow probe costs an IMK read-back + an AX read PER EDIT, i.e.
        // per diacritic key. Unthrottled it made typing feel slow for every tester who
        // turned Debug logging on (issue #28, 2026-07-27) — and a sample every
        // `shadowProbeInterval` carries the same diagnostic signal.
        let shadowDue = Date.timeIntervalSinceReferenceDate - lastShadowProbe >= Self.shadowProbeInterval
        let shadowProbe = !realProbe && !verifyProbe && AppState.shared.debugLogging && shadowDue
            && InPlaceProbe.shouldProbe(insertLength: (insert as NSString).length,
                                        bs: bs, clear: clear, needsProbe: true)
        if shadowProbe { lastShadowProbe = Date.timeIntervalSinceReferenceDate }
        if realProbe || verifyProbe || shadowProbe {
            probeInPlace(inserted: insert, start: start, bs: bs, client,
                         kind: realProbe ? .real : (verifyProbe ? .verify : .shadow))
        }
    }


    /// Drop the composition, LOGGING the cause when it wasn't empty. A silent mid-word
    /// drop is what turns a VNI word into its raw tail: the tone DIGIT then lands on an
    /// empty engine, where it has no vowel to mark and stays literal ("d9o65" → "đô5",
    /// report issue #28 2026-07-27). Telex hides the same fault better (a stray "s"),
    /// so the causes were never worth naming before — now they are.
    private func dropComposition(cause: String) {
        if !engine.isEmpty {
            DebugLog.log("composition dropped mid-word (cause=\(cause)) len=\((engine.composed as NSString).length)")
        }
        engine.reset()
        tracking = false
        edgeTapWord = false
        edgeEchoBackspaces = 0
        edgeEchoChunks = []
    }

    /// Book an edge burst's echo budget (see edgeEchoBackspaces/Chunks).
    private func noteEdgeBurst(_ posted: (backspaces: Int, chunks: [String])) {
        edgeEchoBackspaces += posted.backspaces
        edgeEchoChunks.append(contentsOf: posted.chunks)
        edgeEchoStampNs = DispatchTime.now().uptimeNanoseconds
        logDecision("edge-burst booked: bs=\(edgeEchoBackspaces) chunks=\(edgeEchoChunks.count)")
    }

    /// In-place aborted before inserting anything (bogus selectedRange): condemn the
    /// app to marked text (persisted) and abandon the composition.
    private func inPlaceFailedHard(_ id: String?) {
        AppState.shared.markUsesMarkedText(id)
        dropComposition(cause: "in-place-failed-hard")
    }

    /// After a real in-place REPLACE into an unknown app, verify the old characters
    /// were actually replaced (not appended). Read back the region we targeted,
    /// `[start, start+len)`: a compliant app now holds `inserted` there; an app that
    /// ignored `replacementRange` (Terminal, iTerm2's CJK IMKit path, Catalyst) still
    /// holds the OLD characters. Because the engine strips the common prefix, the
    /// first char of `inserted` is guaranteed to differ from the old char at `start`,
    /// so this discriminates even on a 1-char window — unlike the old probe, which
    /// read back the text before the CARET (present in BOTH cases → false-positive).
    /// A failure switches the app to marked-text mode.
    /// Serial queue for the probe's Accessibility ground-truth read. The AX call has
    /// a 50ms messaging timeout — running it synchronously inside probeInPlace put a
    /// potential 50ms stall on the keystroke that probes a new app. The verdict only
    /// affects FUTURE keystrokes, so the read is inherently deferrable. Deferring is
    /// also MORE accurate: Chromium-class apps build their AX tree lazily/async, so a
    /// T+0 read races a stale cache (measured — the Lark experiment) while a read a
    /// beat later sees the settled tree.
    private static let axProbeQueue = DispatchQueue(label: "com.viettelex.ax-probe", qos: .userInitiated)

    /// How a probe's verdict is applied: `.real` classifies the app (persisted),
    /// `.shadow` only logs (debugLogging experiment).
    enum ProbeKind { case real, verify, shadow }

    /// TRUE while handle() is committing because of a BOUNDARY key (Return/Enter/
    /// Tab/Escape). Main-thread confined (only handle() touches it).
    private var boundaryCommitInFlight = false

    /// A verify probe fired by a boundary commit is evidence-free: Enter typically
    /// SENDS the message and the app clears the field, so the async caret/region
    /// read describes the reset field, not our edit — the tester log 2026-08-04
    /// shows every "appended twice → marked" demotion taking its deciding strike
    /// from a probe ~1ms after Enter ("Enter 2 lần mới gửi được" class). Downgrade
    /// those to shadow (log-only, no strikes, no classification). Pure so the rule
    /// is pinned by tests.
    static func effectiveProbeKind(_ kind: ProbeKind, boundaryCommit: Bool) -> ProbeKind {
        (kind == .verify && boundaryCommit) ? .shadow : kind
    }

    private func probeInPlace(inserted: String, start: Int, bs: Int, _ client: IMKTextInput,
                              kind rawKind: ProbeKind) {
        let kind = Self.effectiveProbeKind(rawKind, boundaryCommit: boundaryCommitInFlight)
        if kind != rawKind { logDecision("probe: boundary commit → verify downgraded to shadow") }
        let len = (inserted as NSString).length
        // Primary signal: the post-edit caret (hard for an app to fake — it needs it
        // to place its candidate window). Fallback: the target-region read-back, used
        // only when the caret is unavailable (some apps echo it, so it must never
        // override a caret that says "appended").
        let sel = client.selectedRange()
        let caret: Int? = sel.location == NSNotFound ? nil : sel.location
        var region: String? = nil
        if start >= 0, let sub = client.attributedSubstring(from: NSRange(location: start, length: len)) {
            region = sub.string
        }
        // PRELIMINARY verdict from the self-reported signals only. The Accessibility
        // ground-truth read happens ASYNC below and can override this verdict when it
        // lands (axProbeQueue doc above) — it never blocks the keystroke.
        let verdict = InPlaceProbe.verdict(axRegion: nil, caret: caret, start: start, bs: bs,
                                           insertLength: len, regionReadback: region,
                                           inserted: inserted)
        // Structural diagnostics only — never the typed text itself. `regionMatch`
        // is a bool (did the read-back equal what we inserted), not the content.
        DebugLog.log("probe\(kind == .shadow ? "(shadow)" : (kind == .verify ? "(verify)" : "")) \(AppState.shared.currentBundleID ?? "?"): "
            + "start=\(start) bs=\(bs) len=\(len) "
            + "caret=\(caret.map(String.init) ?? "none") expReplace=\(start + len) expAppend=\(start + bs + len) "
            + "regionMatch=\(region.map { $0 == inserted ? "yes" : "no" } ?? "nil") → \(verdict)")
        let id = AppState.shared.currentBundleID
        // EXPERIMENT: arm the deferred re-read for the next keyDown (debugLogging only —
        // the extra AX calls must never run on a stock hot path).
        if AppState.shared.debugLogging {
            pendingReprobe = (id, start, len, bs, inserted, verdict)
        }

        // Async ground-truth read. Fired for shadow probes too (log-only there).
        // MANUAL In-place pin: skip every AX follow-up. The verdict can't be used
        // (a pin is never demoted), and the read itself is the suspect in the
        // Discord "mất focus giữa lúc gõ" report 07/08 — touching the AX tree of
        // an Electron app nudges Chromium's accessibility mode, which can blur/
        // re-render the composer. IMK self-report probes (XPC) stay for the
        // debug-log picture; only the AX churn goes.
        if AppState.shared.manualMode(AppState.shared.currentBundleID) == .inPlace { return }
        Self.axProbeQueue.async { [weak self] in
            let axRegion = AXTextEdit.readString(at: start, length: len)
            guard axRegion != nil else { return }   // AX unavailable → preliminary stands
            DispatchQueue.main.async {
                self?.applyAXVerdict(axRegion: axRegion, inserted: inserted, id: id, kind: kind)
            }
        }

        switch kind {
        case .shadow:
            // Data-gathering only: log + arm the re-read, never touch the
            // classification or the engine.
            return
        case .verify:
            // TWO consecutive appended verdicts before demoting (tester log #4:
            // Chrome's attributedSubstring right after insertText can be STALE —
            // regionMatch=no with an HONEST caret — and the one-shot demote reset
            // the engine mid-word, turning "lỗi lệch" into "lôxi lêjch"). A first
            // strike keeps fieldVerified=false so the NEXT replace re-probes; an
            // honored read or an AX exoneration clears the strike.
            switch verdict {
            case .appended:
                fieldVerifyStrikes += 1
                if fieldVerifyStrikes >= 2 {
                    fieldVerified = true
                    fieldForcedMarked = true
                    DebugLog.log("verify: appended twice → marked text for this focus")
                    dropComposition(cause: "verify-appended")
                } else {
                    DebugLog.log("verify: appended (strike 1/2) — will re-probe next replace")
                }
            case .inconclusive:
                // The caret landed BEFORE our anchor — impossible for either outcome, so
                // the app is self-reporting garbage (see InPlaceProbe.verdict). No strike,
                // no promotion: leave the field unverified so the next replace probes
                // again, and let the async AX read settle it if it can. Bound it though —
                // a field that never produces real evidence still has to end up somewhere
                // safe, so after `maxInconclusive` of them fall back to marked text.
                fieldInconclusive += 1
                if fieldInconclusive >= Self.maxInconclusive {
                    fieldVerified = true
                    fieldForcedMarked = true
                    DebugLog.log("verify: \(fieldInconclusive)× stale self-report → marked text for this focus")
                    dropComposition(cause: "verify-impossible-caret")
                } else {
                    DebugLog.log("verify: stale self-report (caret lags the edit) — no verdict "
                        + "(\(fieldInconclusive)/\(Self.maxInconclusive)), will re-probe")
                }
            case .honored:
                fieldVerifyStrikes = 0
                fieldInconclusive = 0
                fieldVerified = true
            }
        case .real:
            applyPreliminaryVerdict(verdict, id: id, expReplace: start + len)
        }
    }

    /// Classification from the SELF-REPORTED signals (caret / read-back) — the part
    /// that must never lock an app in on thin evidence. Honored commits only after two
    /// confirmations at DISTINCT offsets (Lark's constant garbage caret reads honored
    /// whenever expReplace coincides with it — see InPlaceProbe.HonorTracker); appended
    /// needs two in a row (a single failure may just be the app being busy).
    private func applyPreliminaryVerdict(_ verdict: InPlaceProbe.Verdict, id: String?, expReplace: Int) {
        switch verdict {
        case .inconclusive:
            // Impossible self-report (caret before the anchor): classify NOTHING. The app
            // keeps `needsProbe`, so the next real replace probes again; the async AX read
            // may also land and decide. Never persist a mode on garbage.
            DebugLog.log("probe: stale self-report (caret lags the edit) → no classification, keep probing")
            return
        case .honored:
            if let id {
                var tracker = probeHonors[id] ?? InPlaceProbe.HonorTracker()
                if tracker.recordHonored(expReplace: expReplace) {
                    AppState.shared.markInPlaceGood(id)
                    probeHonors[id] = nil
                } else {
                    probeHonors[id] = tracker   // keep probing until a distinct offset confirms
                }
                probeFailures[id] = nil         // a good read clears the streak
            }
        case .appended:
            // A failure also voids any half-collected honored confirmation: the next
            // honored (if any) must start the two-distinct-offsets count over.
            if let id {
                probeHonors[id] = nil
                let n = (probeFailures[id] ?? 0) + 1
                if n >= 2 {
                    probeFailures[id] = nil
                    AppState.shared.markUsesMarkedText(id)
                } else {
                    probeFailures[id] = n
                }
            } else {
                AppState.shared.markUsesMarkedText(id)
            }
            dropComposition(cause: "probe-appended")
        }
    }

    /// The deferred Accessibility ground truth landed (main thread). It is
    /// authoritative: it reports the field's REAL content independent of the app's
    /// IMKit self-report, and it read the tree after it settled. It overrides whatever
    /// the preliminary verdict did — including un-committing an in-place promotion.
    private func applyAXVerdict(axRegion: String?, inserted: String, id: String?, kind: ProbeKind) {
        let match = axRegion == inserted
        DebugLog.log("probe(ax\(kind == .shadow ? "·shadow" : (kind == .verify ? "·verify" : ""))) \(id ?? "?"): axMatch=\(match ? "yes" : "no")")
        guard kind != .shadow else { return }
        if kind == .verify {
            // axMatch=YES is strong evidence (the tree holds exactly what we
            // inserted — a stale cache would still show the OLD text): clear the
            // strikes and, if the self-report already demoted this focus, undo it
            // (only between words — never flip modes mid-composition).
            // axMatch=NO stays LOG ONLY: Chromium serves AX from an async cache and
            // a stale read false-alarms (the Lark lesson; acting on it demoted
            // healthy fields mid-word).
            if match {
                fieldVerifyStrikes = 0
                fieldInconclusive = 0
                fieldVerified = true
                if fieldForcedMarked, engine.isEmpty, AppState.shared.currentBundleID == id {
                    fieldForcedMarked = false
                    DebugLog.log("verify(ax): replace landed — exonerated, back to in-place for this focus")
                }
            }
            return
        }
        if match {
            AppState.shared.markInPlaceGood(id)
            if let id { probeFailures[id] = nil; probeHonors[id] = nil }
        } else {
            AppState.shared.unmarkInPlaceGood(id)   // reverse a self-report-based commit
            AppState.shared.markUsesMarkedText(id)
            if let id { probeFailures[id] = nil; probeHonors[id] = nil }
            // Abandon the composition ONLY if the user is still in the condemned app —
            // by the time the read lands, focus (and the engine) may belong elsewhere.
            if AppState.shared.currentBundleID == id {
                dropComposition(cause: "probe-ax-appended")
            }
        }
    }

    /// EXPERIMENT (log-only): re-read the previous probe's target region on the NEXT
    /// keyDown — after the app's (possibly lazily-built, async) AX tree has settled —
    /// and log whether each signal now agrees with the t0 verdict. Three outcomes we
    /// are looking for on Lark (pinned to In-place + Debug logging on):
    ///   • axMatch2=no while t0 said honored → the t0 AX read raced a stale cache;
    ///     a deferred verdict WOULD auto-detect Lark (no hardcode needed).
    ///   • axMatch2=yes → Lark's AX genuinely reports the inserted text; per-app /
    ///     per-framework pinning stays the only option.
    ///   • axMatch2=nil → AX unavailable until a real AT connects; same conclusion.
    /// `axLen` is the content-independent cross-check: append leaves the field
    /// longer than a replace by `bs` per edit. Logs carry match booleans and lengths
    /// only — never the typed text.
    private func reprobeDeferred(_ p: (id: String?, start: Int, len: Int, bs: Int,
                                       inserted: String, verdict: InPlaceProbe.Verdict),
                                 _ client: IMKTextInput) {
        let nowID = AppState.shared.currentBundleID ?? FrontmostApp.shared.bundleID
        guard nowID == p.id else {
            DebugLog.log("reprobe \(p.id ?? "?"): skipped (focus now \(nowID ?? "?"))")
            return
        }
        // The IMK reads must stay on the main thread; the AX ones must NOT run here.
        // Each AXTextEdit call can block for its 50ms messaging timeout, and this runs
        // INSIDE handle() on the key right after every diacritic edit — a log-only
        // experiment was stalling real typing whenever a tester enabled Debug logging
        // ("gõ đến ký tự có dấu bị chậm", issue #28 2026-07-27). Read AX on the probe
        // queue and log from there; the verdict was never acted on anyway.
        var imk2: String? = nil
        if let sub = client.attributedSubstring(from: NSRange(location: p.start, length: p.len)) {
            imk2 = sub.string
        }
        let sel = client.selectedRange()
        // Pin In-place: no AX touches (see the probeInPlace gate) — log the IMK
        // half only, from here, without the probe-queue AX round trip.
        if AppState.shared.manualMode(AppState.shared.currentBundleID) == .inPlace {
            DebugLog.log("reprobe \(p.id ?? "?"): t0=\(p.verdict) start=\(p.start) bs=\(p.bs) len=\(p.len) "
                + "ax=skipped(pin) imkMatch2=\(imk2.map { $0 == p.inserted ? "yes" : "no" } ?? "nil") "
                + "caret2=\(sel.location == NSNotFound ? "none" : String(sel.location))")
            return
        }
        Self.axProbeQueue.async {
            let ax2 = AXTextEdit.readString(at: p.start, length: p.len)
            let axLen = AXTextEdit.readLength()
            DebugLog.log("reprobe \(p.id ?? "?"): t0=\(p.verdict) start=\(p.start) bs=\(p.bs) len=\(p.len) "
                + "axMatch2=\(ax2.map { $0 == p.inserted ? "yes" : "no" } ?? "nil") "
                + "imkMatch2=\(imk2.map { $0 == p.inserted ? "yes" : "no" } ?? "nil") "
                + "axLen=\(axLen.map(String.init) ?? "nil") "
                + "caret2=\(sel.location == NSNotFound ? "none" : String(sel.location))")
        }
    }

    // MARK: - Marked-text mode (fallback for Terminal-like apps)

    /// Show the composed syllable as marked text, caret at the end. Reliable in apps
    /// that ignore in-place replacementRange; shows a brief underline while composing.
    private func updateMarked(_ client: IMKTextInput) {
        let s = engine.composed
        let caret = NSRange(location: (s as NSString).length, length: 0)
        // EXPERIMENT 3 — background instead of underline? TSM styles 6 (BlockFill)
        // and 8 (SelectedText) are BACKGROUND hilite styles; their mark(forStyle:)
        // dicts may carry more than style 9's bare clause segment. Log every style's
        // dict once, render with BlockFill.
        let len = (s as NSString).length
        let range = NSRange(location: 0, length: len)
        if AppState.shared.debugLogging, !Self.dumpedHiliteDicts {
            Self.dumpedHiliteDicts = true
            for style in 2...9 {
                let d = mark(forStyle: style, at: range) as? [NSAttributedString.Key: Any] ?? [:]
                DebugLog.log("markForStyle(\(style)) dict: \(d)")
            }
        }
        // Near-invisible composition underline — SHIPPED (field-accepted 2026-07-21).
        // The formula, derived the hard way: a VALID underline style (1 = thin) so
        // clients honor the span at all — style 0 reads as "unspecified" and falls
        // back to the default black underline (why every earlier attempt failed) —
        // plus a near-invisible color: alpha ≈ 1/255, NOT fully clear (Chromium
        // treats pure transparent as "use the text color"). Attribute transport was
        // proven by field-testing style 5 → visibly thicker underline. Base dict
        // from mark(forStyle:) keeps the clause segment the transport expects.
        // (No Excel special case: Excel paints its own thick composition underline
        // and ignores every attribute variant — field-tested exhaustively 2026-07-21.
        // Its clean path is empty-reset tap, i.e. real characters, not marked text.)
        var attrs = mark(forStyle: 2 /* kTSMHiliteRawText */, at: range)
            as? [NSAttributedString.Key: Any] ?? [:]
        attrs[.underlineStyle] = 1
        attrs[.underlineColor] = NSColor(calibratedWhite: 0, alpha: 0.004)
        let attributed = NSAttributedString(string: s, attributes: attrs)
        client.setMarkedText(attributed, selectionRange: caret, replacementRange: kNoRange)
        DebugLog.log("setMarked \(AppState.shared.currentBundleID ?? "?"): len=\((s as NSString).length)")
    }

    // MARK: - Word boundary (shortcuts + auto-restore), then reset

    /// Commit the pending word AND fully tear down the IME composition session
    /// before a shortcut is forwarded. In marked-text apps (Electron/Claude) a
    /// still-open composition swallows ⌘-shortcuts — ⌘A "select all" did nothing
    /// while a word was composing. Clearing the marked text explicitly after the
    /// commit ends the session so the shortcut reaches the app.
    /// A modifier combo (⌘A, ⌃…) arrived mid-word:
    /// drop the composition with NO auto-restore and NO shortcut expansion —
    /// leave the word EXACTLY as composed — then let the shortcut key pass through.
    /// In-place text is already on screen (we insert every key), so a reset suffices;
    /// marked text isn't real yet, so finalize it to the composed word first.
    private func endComposition(_ client: IMKTextInput) {
        if !engine.isEmpty, usesMarkedNow(AppState.shared.currentBundleID) {
            client.insertText(engine.composed, replacementRange: kNoRange)
            client.setMarkedText("", selectionRange: kNoRange, replacementRange: kNoRange)
        }
        engine.reset()
        tracking = false
        onLen = 0
    }

    /// Tear the composition down WITHOUT any rewrite, insertText, or setMarkedText —
    /// used at boundaries where touching the client is unsafe (secure input, remote
    /// desktop): the anchor may belong to a previous field and the target window must
    /// not receive injected text. Unlike endComposition this never finalizes marked
    /// text (no insertText(composed)); unlike boundary it never expands shortcuts or
    /// auto-restores. Whatever was already on screen stays as-is; the engine forgets it.
    private func discardComposition() {
        engine.reset()
        tracking = false
        onLen = 0
    }

    @discardableResult
    /// EDGE-TAP eligibility, decided once per word at its first key. Pure — pinned
    /// by EdgeTapTests. Manual In-place pin ONLY (built-in in-place apps honor
    /// offset-0; the pin is the user's escape hatch on web editors where offset-0
    /// replacementRange gets APPENDED — "cos" → "coó" at message start). Untrusted
    /// can't post synthetic keys, so the word falls back to plain in-place.
    ///
    /// caret <= 1, not == 0: an EMPTY Slate box (Discord) reports caret=1 — the
    /// empty block holds a phantom placeholder the caret sits "after", removed
    /// once text lands (measured 06/08: empty box word-start caret=1 twice, but
    /// the word after "abc " starts at 4, not 5 ⇒ the 1 was a lie and text really
    /// occupies 0…). A GENUINE offset-1 word start (one leading char, no space) is
    /// rare, and the synthetic channel is position-independent — correct there
    /// too, at worst a flicker.
    static func edgeTapEligible(manualInPlace: Bool, caret: Int?, trusted: Bool) -> Bool {
        guard let caret else { return false }
        return manualInPlace && trusted && caret <= 1
    }

    private func boundary(_ client: IMKTextInput, suppressAutoRestore: Bool = false,
                          allowShortcuts: Bool = true) -> Bool {
        let wasEdge = edgeTapWord
        defer { tracking = false; onLen = 0; edgeTapWord = false }
        guard !engine.isEmpty else { engine.reset(); return false }
        let marked = usesMarkedNow(AppState.shared.currentBundleID)
        let word = engine.composed
        // Raw keystrokes must be read BEFORE engine.reset() clears them. A shortcut key
        // that contains Telex triggers (s f r x j w, doubled vowels) never survives
        // composition — "vn"→"vn" but "cf" composes away — so a shortcut whose key IS
        // the raw form could never match on `word` alone.
        let rawWord = engine.rawKeystrokes
        let onScreen = word.unicodeScalars.count

        // Shortcut expansion (bảng gõ tắt) takes precedence over the composed word.
        // Try the composed word first, then fall back to the raw keystrokes so a
        // shortcut key containing trigger letters still matches. On-screen backspace
        // count stays `onScreen` (the composed scalar count) either way.
        if allowShortcuts, !word.isEmpty,
           let expansion = AppState.shared.shortcuts[word] ?? AppState.shared.shortcuts[rawWord] {
            engine.reset()
            if marked { client.insertText(expansion, replacementRange: kNoRange) }
            else if wasEdge { noteEdgeBurst(SyntheticKeyboard.applyForEdge(backspaces: onScreen, insert: expansion)) }
            else { applyInPlace(bs: onScreen, insert: expansion, client) }
            return true
        }

        // Auto-restore non-Vietnamese words to their raw keystrokes (resets engine).
        // Suppressed next to brackets (code context).
        let autoRestore = AppState.shared.autoRestore && !suppressAutoRestore
        let restored = engine.commitText(autoRestore: autoRestore)
        if marked {
            // Commit the marked text (replaces it with the final word).
            client.insertText(restored, replacementRange: kNoRange)
            return true
        } else if restored != word {
            if wasEdge { noteEdgeBurst(SyntheticKeyboard.applyForEdge(backspaces: onScreen, insert: restored)) }
            else { applyInPlace(bs: onScreen, insert: restored, client) }
            return true
        }
        return false
    }

    // MARK: - IMK lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // Pin the layout Telex composes on BEFORE anything reads a key. Without this
        // the layout is whatever the previously selected input source happened to be
        // (ABC → QWERTY, Colemak → Colemak), so the same input method typed two
        // different keyboards depending on switch history — see KeyboardLayoutOverride.
        // Re-asserted every activation, not just once: macOS can drop the override
        // across an input-source cycle, and the call is a cached Carbon lookup.
        KeyboardLayoutOverride.apply(AppState.shared.keyboardLayoutID)
        // New field: both AX verdicts (is it a password field? does it want selection-
        // replace?) describe the PREVIOUS one until their scans re-run.
        SecureFieldDetector.invalidate()
        FocusedFieldDetector.invalidate()
        dropComposition(cause: "activateServer")
        // A nav-key stamp left by the previous client must not drop the first word
        // typed in this one (NavKeyWitness — the very key that moved focus here may
        // have been a swallowed Tab).
        NavKeyWitness.reset()
        engine.resetContext()   // new field/app: don't inherit the last word's English context
        fieldVerified = false
        fieldForcedMarked = false
        fieldVerifyStrikes = 0
        fieldInconclusive = 0
        if let client = sender as? IMKTextInput {
            AppState.shared.currentBundleID = client.bundleIdentifier()
            // Spotlight took focus: stamp the visibility cache NOW — the overlay-raw
            // gate in the tap must not wait for a CGWindowList scan that only lands
            // after the first keys have already been mis-composed (2026-07-31).
            if AppState.shared.currentBundleID == AppState.spotlightBundleID {
                SpotlightDetector.noteFocused()
                let now = DispatchTime.now().uptimeNanoseconds
                // ASSIGN (not just set-true): an arm from a rapid cycle the user
                // never typed after must not survive into a fresh session opened
                // minutes later — every activation recomputes the verdict, so a
                // slow reopen clears any stale arm (review find 2026-08-12).
                distrustNextAnchor = Self.spotlightReactivatedTooSoon(now: now,
                                                                      lastActivateNs: lastSpotlightActivateNs)
                if distrustNextAnchor {
                    DebugLog.log("Spotlight re-activated within 5s (gapNs=\(now &- lastSpotlightActivateNs)) → distrust next word's anchor")
                }
                lastSpotlightActivateNs = now
            } else {
                // Any OTHER client activating is authoritative proof Spotlight no
                // longer owns the keyboard (macOS wouldn't route activateServer here
                // otherwise) — clear the visibility cache NOW rather than waiting on
                // the passive CGWindowList re-scan, whose backoff can leave it stale
                // for 500ms+ after a long-open Spotlight session (issue: Chrome
                // omnibox typed right after Esc got its first few keys raw-passed).
                SpotlightDetector.noteUnfocused()
                // Per-field browser: start the field-verdict scan NOW, not on the
                // first keystroke — issue #32 round 3 (see prefetch's doc): the
                // first word after refocus otherwise runs on the stale "page
                // content" default and a tone key bare-⌫'s the omnibox.
                if AppState.shared.usesAxDetect(AppState.shared.currentBundleID) {
                    FocusedFieldDetector.prefetch()
                }
            }
            // What identifier does this client REPORT? (Catalyst/Electron apps may not
            // report what NSWorkspace says — a mismatch mis-routes every mode lookup.)
            DebugLog.log("activateServer client=\(AppState.shared.currentBundleID ?? "nil") front=\(FrontmostApp.shared.bundleID ?? "?")")
            maybePromptAccessibility(AppState.shared.currentBundleID)
            UpdateCheck.maybeAutoCheck()   // opt-in weekly; two cheap guards inside
        }
        // VietTelex is the active input source now: let the terminal tap act (it must
        // stay dormant when the user switches to ABC/US). ensureRunning() also revives
        // a tap that died (Accessibility toggled off/on invalidates the mach port), so
        // focusing a terminal / re-selecting the source self-heals it.
        TerminalTapController.shared.markActive()
        TerminalTapController.shared.ensureRunning()

        if resetObserver == nil {
            // queue: .main — the poster is the TAP thread now, and this block mutates
            // the controller's engine/tracking, which are MAIN-thread state. Ordering
            // is preserved: the click/⌘-combo that triggers the post physically
            // precedes the next keystroke, so its main-queue block is enqueued before
            // IMK delivers that key to handle() through the same main run loop.
            resetObserver = NotificationCenter.default.addObserver(
                forName: .telexResetComposition, object: nil, queue: .main) { [weak self] _ in
                self?.dropComposition(cause: "resetComposition-notification")
                self?.fieldVerified = false
                self?.fieldForcedMarked = false
                self?.fieldVerifyStrikes = 0
                self?.fieldInconclusive = 0
                self?.onLen = 0
            }
        }
    }

    override func commitComposition(_ sender: Any!) {
        // EDGE-TAP: the app processing our own synthetic ⌫/insert echoes makes
        // AppKit ask the IME to commit — SILENTLY resetting the engine mid-word
        // (the "thưr" trace: echoes swallowed clean, then commitComposition, then
        // 'r' fed an empty engine). Within the echo window this commit is an
        // artifact of our own burst, not a user action: ignore it. Real session
        // ends still work — clicks go through the reset notification and focus
        // changes through deactivateServer/activateServer, both of which drop
        // the composition themselves.
        if edgeTapWord,
           DispatchTime.now().uptimeNanoseconds &- edgeEchoStampNs < 500_000_000 {
            logDecision("commitComposition ignored (edge echo window)")
            return
        }
        if let client = sender as? IMKTextInput {
            // NO shortcut expansion here (tester bug 2026-07-23): some apps
            // (omnibox/Spotlight-style fields) force-commit after every
            // keystroke, which expanded a single-letter shortcut ("r"→"rồi")
            // mid-word — "t","r" became "trồi". Expansion belongs to EXPLICIT
            // boundaries only (space/punctuation/Return/Tab).
            boundary(client, allowShortcuts: false)
            // A FORCED commit, not a boundary key: nothing was inserted after the word,
            // so the next ⌫ is deleting the word's own last letter and must not re-open
            // it (see tryReopenLastCommit).
            engine.forgetLastCommit()
        } else {
            engine.reset()
            tracking = false
        }
    }

    override func deactivateServer(_ sender: Any!) {
        dropComposition(cause: "deactivateServer")
        if let obs = resetObserver { NotificationCenter.default.removeObserver(obs); resetObserver = nil }
        // Input source switched away from VietTelex (or focus lost): the tap must not
        // transform keys, so the user really types English in terminals. BUT with
        // per-document input switching, IMK can call this on a stale client AFTER the
        // newly focused client's activateServer — so only turn the tap off if VietTelex
        // is genuinely no longer the OS-selected source (else we'd clobber the fresh
        // activate and typing would pass through until a focus cycle; see IMEActivation).
        TerminalTapController.shared.markInactive(stillSelected: Self.isVietTelexSelected())
        super.deactivateServer(sender)
    }

    /// True when the CURRENTLY selected keyboard input source is VietTelex — the single
    /// source of truth the flaky activate/deactivate ordering must defer to. Called
    /// only on lifecycle transitions / TIS notifications, never on the keystroke hot
    /// path, so the Carbon TIS copy is fine here. Matches both the input source and its
    /// `.vi` input mode by bundle-id prefix — THIS build's own id (see `OwnBundle`), so
    /// a dev build registered under a separate id still recognizes itself.
    static func isVietTelexSelected() -> Bool {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return false }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return inputSourceIsOurs(id)
    }

    /// Does this input-source id belong to the RUNNING build? Split out of
    /// `isVietTelexSelected` so the prefix rule is testable without a live TIS —
    /// `own` is the seam a test uses to replay the dev-build id mismatch that put the
    /// tap dormant mid-word (see `OwnBundle`). An EMPTY `own` matches nothing: bare
    /// `hasPrefix("")` is true for every id, which would claim VietTelex is selected
    /// while the user types in ABC. `OwnBundle` already refuses to produce one — this
    /// is the guard at the comparison itself, where the hazard actually lives.
    static func inputSourceIsOurs(_ id: String, own: String = OwnBundle.id) -> Bool {
        !own.isEmpty && id.hasPrefix(own)
    }

    // MARK: - Input-method menu (IMK-provided, no NSStatusItem)

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "VietTelex")
        // macOS appends a standard "Edit Text Substitutions…" item to input-method
        // menus. Strip it (and any trailing separator) each time the menu opens.
        menu.delegate = self

        // Status first — nhưng CHỈ khi có chuyện (maintainer 15/08/2026): "Tình
        // trạng: OK" thường trực là nhiễu, ẨN đi khi mọi thứ ổn. Tính năng ẩn
        // "click status → copy debug snapshot" KHÔNG mất: nó chuyển xuống dòng
        // version bên dưới (click được ở mọi trạng thái).
        let statusTitle: String?
        if let holder = SecureInputMonitor.shared.activeHolder {
            // Hiếm khi tới được đây (secure input thường đá selection sang ABC nên
            // menu này không mở được), nhưng ca "secure input tạm thời trong ô
            // password mà VietTelex vẫn selected" thì thấy. Không click-action:
            // thủ phạm là app khác, mình không tắt hộ được.
            statusTitle = VTLocalized("Status: Blocked by Secure Input") + " — \(holder.label)"
        } else if !Accessibility.isTrusted {
            statusTitle = VTLocalized("Status: Permission needed")
        } else if TerminalTapController.shared.trustLooksStale {
            statusTitle = VTLocalized("Status: Permission stale — click to fix")
        } else if TerminalTapController.shared.isQuarantined || SyntheticKeyboard.tripped {
            // The tap paused itself (probe-miss quarantine / cascade breaker). Without
            // this state the menu said "OK" while terminals typed raw ASCII and even an
            // input-source switch couldn't revive it (quarantine blocks ensureRunning) —
            // field report 2026-07-30. Click = retryNow(), the documented explicit
            // user action that outranks the backoff.
            statusTitle = VTLocalized("Status: Tap paused — click to retry")
        } else {
            statusTitle = nil                       // OK = im lặng, không chiếm dòng
        }
        if let statusTitle {
            let status = NSMenuItem(title: statusTitle,
                                    action: #selector(showStatus(_:)), keyEquivalent: "")
            status.target = self
            menu.addItem(status)
        }

        // Version + build, disabled: testers report "which build?" straight from the
        // menu without opening Settings. Not localized — it's an identifier.
        // (Tính năng ẩn click-copy-snapshot đã BỎ hẳn 15/08/2026 — maintainer;
        // snapshot vẫn lấy được qua Cài đặt → Thử nghiệm → Copy debug log.)
        let bundle = Bundle(for: TelexInputController.self)
        let ver = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let version = NSMenuItem(title: "VietTelex \(ver) (build \(build))", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        // Chế độ gõ đang áp dụng + click = copy snapshot giải thích VÌ SAO chọn nó
        // (maintainer 19/08/2026). Trả lời đúng câu hỏi hay gặp nhất trong bug report:
        // "app này đang gõ kiểu gì, và vì sao".
        let strategy = NSMenuItem(title: VTLocalized("Typing mode") + ": "
                                    + strategyLabel(AppState.shared.currentBundleID, localized: true),
                                 action: #selector(copyStrategySnapshot(_:)), keyEquivalent: "")
        strategy.target = self
        strategy.toolTip = VTLocalized("Click: open the typing-modes guide + copy debug info")
        menu.addItem(strategy)

        // Everything else lives in the Settings window (Chung + Gõ tắt tabs). The menu
        // stays minimal: status + Settings.
        let settings = NSMenuItem(title: VTLocalized("Settings…"), action: #selector(openSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        // System Settings → Keyboard (Text Input / Input Sources) — where users
        // add/remove the input source and reach the Edit… sheet.
        let sysSettings = NSMenuItem(title: VTLocalized("System Settings…"),
                                     action: #selector(openSystemKeyboardSettings(_:)), keyEquivalent: "")
        sysSettings.target = self
        menu.addItem(sysSettings)

        return menu
    }

    @objc private func openSystemKeyboardSettings(_ sender: Any?) {
        Self.openKeyboardInputSources()
    }

    /// Shared by the IME menu and the Settings window: open System Settings →
    /// Keyboard and (with Accessibility) press through to All Input Sources.
    static func openKeyboardInputSources() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        // No URL deep-links into the "All Input Sources" Edit… sheet, so with
        // Accessibility we press the button ourselves: in the Keyboard pane the
        // Input-Sources summary line mentions our own name ("… and ViệtTelex") —
        // a locale-independent anchor; the FIRST AXButton after it inside the
        // same row group is Edit… (verified via UI-tree dump on macOS 26; the
        // second is Text Replacements…, and Dictation's own Edit… lives in a
        // different group so it can never match). Without AX, or if the tree
        // changed, fall back to a how-to popup over the open pane.
        guard Accessibility.isTrusted else { showInputSourcesHowTo(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            for attempt in 0..<6 {
                Thread.sleep(forTimeInterval: attempt == 0 ? 1.2 : 0.5)
                if pressInputSourcesEdit() { return }
            }
            DispatchQueue.main.async { showInputSourcesHowTo() }
        }
    }

    /// Shared by the Settings window: open System Settings → Keyboard → Keyboard
    /// Shortcuts… → Input Sources — where the actual switch-input-source HOTKEY
    /// lives (distinct from openKeyboardInputSources() above, which reaches the
    /// Edit… sheet that adds/removes sources). Field request 2026-08-07.
    static func openInputSourceHotkeySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        // No URL reaches past the Keyboard pane here either. Two AX presses:
        // "Keyboard Shortcuts…" opens a sheet with a category sidebar (Dock,
        // Display, Mission Control, Window management, Keyboard, INPUT SOURCES,
        // Screenshots…); selecting that row shows the actual hotkey. Both anchors
        // are button/row DESCRIPTIONS, so they follow the system language — unlike
        // the "ViệtTelex"-name anchor above, there's no app-specific text to hang
        // onto here, so this only matches English or Vietnamese (the two this app
        // ships) and falls back to a how-to popup on any other system language,
        // exactly like the existing Edit… flow does when its tree doesn't match.
        // Verified live via UI-tree dump on macOS 26 (English) 2026-08-07.
        guard Accessibility.isTrusted else { showInputSourceHotkeyHowTo(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            var opened = false
            for attempt in 0..<6 {
                Thread.sleep(forTimeInterval: attempt == 0 ? 1.2 : 0.5)
                if pressKeyboardShortcutsButton() { opened = true; break }
            }
            guard opened else {
                DispatchQueue.main.async { showInputSourceHotkeyHowTo() }
                return
            }
            for attempt in 0..<6 {
                Thread.sleep(forTimeInterval: attempt == 0 ? 0.6 : 0.4)
                if selectInputSourcesShortcutsRow() { return }
            }
            DispatchQueue.main.async { showInputSourceHotkeyHowTo() }
        }
    }

    private static func showInputSourceHotkeyHowTo() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = VTLocalized("Input source hotkey howto title")
        alert.informativeText = VTLocalized("Input source hotkey howto body")
        alert.addButton(withTitle: VTLocalized("OK"))
        alert.runModal()
    }

    /// Presses the "Keyboard Shortcuts…" button in the Keyboard pane's main
    /// window (NOT the Edit… button — a different button in the same pane).
    private static func pressKeyboardShortcutsButton() -> Bool {
        guard let settings = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
        else { return false }
        let app = AXUIElementCreateApplication(settings.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &winRef) == .success,
              let window = winRef else { return false }
        // Sheet already up from an earlier attempt → nothing left to press here.
        var sheetsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window as! AXUIElement, "AXSheets" as CFString, &sheetsRef) == .success,
           let sheets = sheetsRef as? [AXUIElement], !sheets.isEmpty {
            return true
        }
        guard let button = findButtonByDescription(window as! AXUIElement,
                                                    matching: ["Keyboard Shortcuts", "Phím tắt bàn phím"],
                                                    depth: 0)
        else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// Selects the "Input Sources shortcuts" row in the Keyboard Shortcuts sheet's
    /// category sidebar (AXRow > … > description, not AXStaticText — a different
    /// shape than the Edit… anchor above).
    private static func selectInputSourcesShortcutsRow() -> Bool {
        guard let settings = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
        else { return false }
        let app = AXUIElementCreateApplication(settings.processIdentifier)
        var winsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &winsRef)
        guard let windows = winsRef as? [AXUIElement] else { return false }
        for window in windows {
            guard let row = findRowByDescendantDescription(window,
                                                            matching: ["Input Sources shortcuts", "Nguồn nhập"],
                                                            depth: 0)
            else { continue }
            return AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success
        }
        return false
    }

    /// First AXButton (reading order) whose description matches one of `needles`.
    private static func findButtonByDescription(_ el: AXUIElement, matching needles: [String], depth: Int) -> AXUIElement? {
        if depth > 15 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        if roleRef as? String == kAXButtonRole as String {
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
            if let d = descRef as? String, needles.contains(where: { d.contains($0) }) { return el }
        }
        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let kids = kidsRef as? [AXUIElement] else { return nil }
        for k in kids {
            if let found = findButtonByDescription(k, matching: needles, depth: depth + 1) { return found }
        }
        return nil
    }

    /// First AXRow (reading order) with a descendant whose description matches one
    /// of `needles`. Used for sidebar category lists where the label lives one or
    /// two levels below the row, not on the row itself.
    private static func findRowByDescendantDescription(_ el: AXUIElement, matching needles: [String], depth: Int) -> AXUIElement? {
        if depth > 20 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        if roleRef as? String == "AXRow", descriptionExists(in: el, matching: needles, depth: 0) {
            return el
        }
        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let kids = kidsRef as? [AXUIElement] else { return nil }
        for k in kids {
            if let found = findRowByDescendantDescription(k, matching: needles, depth: depth + 1) { return found }
        }
        return nil
    }

    /// True if any descendant (any role) of `el` has a description matching one of
    /// `needles` — used to test an AXRow's subtree without caring which role/depth
    /// carries the label (macOS 26's sidebar puts it on an AXUnknown two levels down).
    private static func descriptionExists(in el: AXUIElement, matching needles: [String], depth: Int) -> Bool {
        if depth > 5 { return false }
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
        if let d = descRef as? String, needles.contains(where: { d.contains($0) }) { return true }
        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let kids = kidsRef as? [AXUIElement] else { return false }
        for k in kids where descriptionExists(in: k, matching: needles, depth: depth + 1) { return true }
        return false
    }

    /// AX couldn't (or isn't allowed to) press Edit… — tell the user where it is.
    private static func showInputSourcesHowTo() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = VTLocalized("Input sources howto title")
        alert.informativeText = VTLocalized("Input sources howto body")
        alert.addButton(withTitle: VTLocalized("OK"))
        alert.runModal()
    }

    /// Find the Input-Sources row in System Settings' AX tree (anchored on our
    /// own source name, which is locale-independent) and press the single
    /// button inside that row — the Edit… sheet opener. Returns true when
    /// pressed or when the sheet is already up.
    private static func pressInputSourcesEdit() -> Bool {
        guard let settings = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
        else { return false }
        let app = AXUIElementCreateApplication(settings.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &winRef) == .success,
              let window = winRef else { return false }

        // The Edit… press SUCCEEDED on an earlier attempt if a sheet is already
        // up — stop here. Walking again would anchor on the "ViệtTelex" row
        // INSIDE the sheet and press deeper into it (field bug 2026-07-23).
        var sheetsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window as! AXUIElement, "AXSheets" as CFString, &sheetsRef) == .success,
           let sheets = sheetsRef as? [AXUIElement], !sheets.isEmpty {
            return true
        }

        // Real tree (dumped on macOS 26, English + Vietnamese OS):
        //   AXGroup                       ← the Input-Sources row
        //     AXStaticText "Input Sources"
        //     AXStaticText "U.S. and ViệtTelex"   ← locale-independent anchor
        //     AXButton  desc="Edit…"              ← what we want
        //     AXButton  desc="Text Replacements…"
        // Rule: inside the anchor's OWN parent group only (never climb — the
        // Dictation row has its own Edit…), press the first button that comes
        // AFTER the anchor in child order. Anything unexpected → press nothing;
        // the caller then shows the how-to popup.
        guard let anchor = findAnchorText(window as! AXUIElement, depth: 0) else { return false }
        var parentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(anchor, kAXParentAttribute as CFString, &parentRef) == .success,
              let parent = parentRef else { return false }
        let row = parent as! AXUIElement
        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(row, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let kids = kidsRef as? [AXUIElement] else { return false }
        guard let anchorIdx = kids.firstIndex(where: { CFEqual($0, anchor) }) else { return false }
        for el in kids.dropFirst(anchorIdx + 1) {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
            if roleRef as? String == kAXButtonRole as String {
                return AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    /// First static text (reading order) whose value mentions our input source
    /// or the Input-Sources label. "Telex" comes from the enabled-sources
    /// summary ("U.S. and ViệtTelex"), which shows our name in every OS
    /// language; the label strings only help on English/Vietnamese systems.
    private static func findAnchorText(_ el: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 12 { return nil }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        if roleRef as? String == kAXStaticTextRole as String {
            var valRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valRef)
            if let v = valRef as? String,
               v.contains("Telex") || v.contains("Input Sources") || v.contains("Nguồn nhập") {
                return el
            }
        }
        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let kids = kidsRef as? [AXUIElement] else { return nil }
        for k in kids {
            if let found = findAnchorText(k, depth: depth + 1) { return found }
        }
        return nil
    }


    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show(tab: .general)
    }

    /// Trang giải thích các kiểu gõ (In-place/Tap/Marked…) — GitHub render sẵn
    /// docs/TYPING-STRATEGIES.md; GitHub Pages serve .md dạng raw nên không dùng
    /// viettelex.com cho file này.
    static let typingModesGuideURL = "https://ptrinh.github.io/viettelex/typing-modes"

    @objc private func copyStrategySnapshot(_ sender: Any?) {
        // Async: menu input-method còn đang đóng (cùng lý do đã ghi ở showStatus).
        // Click dòng "Chế độ gõ": copy debug VÀ mở trang hướng dẫn các kiểu gõ
        // (maintainer 23/08 — user cuối bấm vào vì muốn hiểu, dev/tester thì cần
        // snapshot; browser mở ra là feedback đủ rõ nên bỏ alert ở đường này).
        DispatchQueue.main.async { [weak self] in
            self?.showDebugLog(alert: false)
            if let url = URL(string: Self.typingModesGuideURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func showStatus(_ sender: Any?) {
        // Defer to the next runloop tick: the input-method menu is still dismissing
        // when this fires, and running an NSAlert modal synchronously from that context
        // in a background (accessory) agent doesn't surface the window. Async + activate
        // makes it appear reliably.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !Accessibility.isTrusted { self.grantAccessibility() }
            else if TerminalTapController.shared.trustLooksStale { self.showStaleTrustRepair() }
            else if TerminalTapController.shared.isQuarantined || SyntheticKeyboard.tripped {
                DebugLog.log("menu: user retry from tap-paused state")
                TerminalTapController.shared.retryNow()
            }
            else { self.showDebugLog() }
        }
    }

    /// Stale-grant repair: macOS lists VietTelex as allowed but refuses the tap — the
    /// stored TCC requirement no longer matches this binary, so the checkbox is a lie
    /// (see Accessibility.grantLooksStale). Removing the entry and adding it back is what
    /// fixes it, and `tccutil reset` does exactly that to our OWN row — so the primary
    /// button now does it for the user instead of walking them through four steps in
    /// System Settings. The manual route stays as the second button, because a row that
    /// macOS refuses to delete (MDM/system default) can only be fixed by hand.
    @objc private func showStaleTrustRepair() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = VTLocalized("Stale permission title")
        alert.informativeText = VTLocalized("Stale permission body")
        alert.addButton(withTitle: VTLocalized("Repair automatically"))
        alert.addButton(withTitle: VTLocalized("Open Accessibility Settings"))
        alert.addButton(withTitle: VTLocalized("Close"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            repairStaleTrust()
        case .alertSecondButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            TerminalTapController.shared.retryNow()
        default:
            TerminalTapController.shared.retryNow()
        }
    }

    /// Delete our own TCC row, then ask for the permission again so macOS writes a fresh
    /// one against the CURRENT signature. The re-prompt must come from THIS process (it is
    /// the requesting code identity), so we do not exit; the grant toggle then fires the
    /// com.apple.accessibility.api notification and the tap starts on its own.
    private func repairStaleTrust() {
        let didReset = Accessibility.resetOwnGrant()
        DebugLog.log("stale-grant repair: tccutil reset \(didReset ? "ok" : "FAILED") "
            + "→ trusted=\(AXIsProcessTrusted()) canPost=\(Accessibility.canPostEvents)")
        // Ask again. When the row is gone this shows the system TCC dialog; when macOS
        // kept it (MDM-managed), nothing appears — hence the manual fallback below.
        Accessibility.requestIfNeeded()
        TerminalTapController.shared.retryNow()
        let done = NSAlert()
        done.messageText = VTLocalized(didReset ? "Repair started title" : "Repair failed title")
        done.informativeText = VTLocalized(didReset ? "Repair started body" : "Repair failed body")
        done.addButton(withTitle: VTLocalized("Open Accessibility Settings"))
        done.addButton(withTitle: VTLocalized("Close"))
        NSApp.activate(ignoringOtherApps: true)
        done.window.level = .floating
        done.window.orderFrontRegardless()
        if done.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        TerminalTapController.shared.retryNow()
    }

    /// One-time gentle prompt on the FIRST activation with the permission missing —
    /// no longer waiting for the user to focus a tap-needing app (they'd type happily
    /// in Notes, then hit Terminal days later and think the IME broke). Shown once
    /// ever (axPromptShown); declining is remembered.
    private func maybePromptAccessibility(_ id: String?) {
        guard !AppState.shared.axPromptShown,
              !Accessibility.isTrusted else { return }
        AppState.shared.axPromptShown = true
        DispatchQueue.main.async { [weak self] in
            self?.grantAccessibility()
        }
    }

    /// Missing permission: show OUR explanatory popup. We deliberately do NOT call
    /// `AXIsProcessTrustedWithOptions(prompt:)` here — that fires the system TCC
    /// dialog too, so clicking the status opened Settings AND our popup at once. The
    /// popup's "Mở Cài đặt" button opens the Accessibility pane on demand instead.
    private func grantAccessibility() {
        NSApp.setActivationPolicy(.regular)
        let alert = NSAlert()
        alert.messageText = VTLocalized("Accessibility permission needed")
        alert.informativeText = VTLocalized("VietTelex needs Accessibility to type Vietnamese in Terminal/iTerm and browsers.\n\nOpen System Settings → Privacy & Security → Accessibility and enable VietTelex (if it’s already there, untick then tick it again).")
        alert.addButton(withTitle: VTLocalized("Open Settings"))
        alert.addButton(withTitle: VTLocalized("Close"))
        // We're an accessory (agent) app, so a plain runModal() can open the alert
        // BEHIND the frontmost app — the user then has to click our Dock icon to find
        // it (the reported bug). Activate the app AND force the alert window frontmost
        // (float level + orderFrontRegardless) right before running it modally.
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = .floating
        alert.window.orderFrontRegardless()
        alert.window.makeKeyAndOrderFront(nil)
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Permission OK: show a debug snapshot of the runtime state.
    /// Nhãn chế độ gõ ĐANG áp dụng cho app hiện tại — dùng cho cả dòng menu (tiếng
    /// Việt hoá) lẫn snapshot (giữ nguyên tiếng Anh để grep bug report). tapRouting,
    /// không phải các getter per-mode: page content trong browser routes sang tap BY
    /// POLICY (06/08) mà app không hề nằm trong set tap-mode nào.
    func strategyLabel(_ id: String?, localized: Bool) -> String {
        let routing = AppState.shared.tapRouting(id)
        if routing.selection { return localized ? VTLocalized("Selection-replace") : "tap · selection-replace (Chromium)" }
        if routing.tap { return localized ? VTLocalized("Tap (backspace)") : "tap · backspace" }
        if routing.emptyReset { return localized ? VTLocalized("Empty-reset") : "tap · emptyReset" }
        if usesMarkedNow(id) { return localized ? VTLocalized("Marked text") : "IMKit · marked text" }
        return localized ? VTLocalized("In-place") : "IMKit · in-place"
    }

    private func showDebugLog(alert: Bool = true) {
        // Snapshot là lúc user đang thắc mắc "sao thế này" — re-check secure input
        // ngay thay vì đợi nhịp poll 5s.
        SecureInputMonitor.shared.check(reason: "snapshot")
        let id = AppState.shared.currentBundleID ?? "?"
        // tapRouting, not the per-mode getters: page content in browsers routes to
        // tap BY POLICY (2026-08-06) without the app ever being in a tap-mode set,
        // so the old usesTapMode-based label showed "in-place" for a key the tap
        // actually handled.
        let mode = strategyLabel(id, localized: false)
        let s = AppState.shared
        let bundle = Bundle(for: TelexInputController.self)
        let ver = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        // Log payload — deliberately ENGLISH (and NOT routed through VTLocalized) so a
        // pasted bug report is greppable regardless of the reporter's UI language.
        func onOff(_ v: Bool) -> String { v ? "on" : "off" }
        let lines = [
            "VietTelex \(ver) (build \(build))",
            "Accessibility: \(Accessibility.isTrusted ? "OK" : "missing")",
            "Terminal tap: \(TerminalTapController.shared.isRunning ? "running" : "off")"
                + (TerminalTapController.shared.isQuarantined ? " (quarantined)" : "")
                + (SyntheticKeyboard.tripped ? " (breaker tripped)" : ""),
            SecureInputMonitor.shared.snapshotLine,
            "Spotlight visible: \(SpotlightDetector.isVisible ? "yes" : "no")",
            "Current app: \(id)"
                + (FrontmostApp.shared.bundleID.map { $0 == id ? "" : "  (frontmost: \($0))" } ?? ""),
            "Strategy: \(mode)",
            "",
            "— why this strategy —",
            "Built-in rule: \(AppState.shared.autoResolvedMode(id).map { "\($0)" } ?? "none (unknown app)")",
            "Manual pin: \(AppState.shared.manualMode(id).map { "\($0)" } ?? "none")",
            "Learned: \(AppState.shared.isLearnedInPlace(id) ? "in-place OK" : "—")"
                + (AppState.shared.usesTapMode(id) ? " / tap-fallback" : ""),
            "Unknown apps → safe channel: \(onOff(s.safeUnknownApps))",
            "Field verdict: selection=\(FocusedFieldDetector.wantsSelection ? "yes" : "no")"
                + " marked=\(FocusedFieldDetector.wantsMarkedField ? "yes" : "no")"
                + " forcedMarked=\(fieldForcedMarked ? "yes" : "no")",
            "Web host: \(FocusedFieldDetector.debugLastHost ?? "—")",
            "AX role chain: [\(FocusedFieldDetector.debugRoleChain())]",
            "",
            "Simple Telex: \(onOff(s.simpleTelex))",
            "Free marking: \(onOff(s.freeMarking))",
            "Modern tone placement: \(onOff(s.modernOrthography))",
            "Live spell check: \(onOff(s.liveSpellCheck))",
            "Auto restore: \(onOff(s.autoRestore))",
        ]
        // Copy vào clipboard để user dán thẳng vào báo lỗi (lúc có sự cố thì gõ lại
        // không đáng tin). CÓ alert xác nhận: đây là dòng menu TƯỜNG MINH ("Chế độ
        // gõ: …"), khác hidden feature click-dòng-version đã bỏ 15/08 — user bấm có
        // chủ đích thì phải biết chuyện gì vừa xảy ra.
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        guard alert else { return }   // đường mở-web: browser hiện ra là feedback đủ
        let box = NSAlert()
        box.messageText = VTLocalized("Debug info copied")
        box.informativeText = VTLocalized("Paste it into your bug report (⌘V).")
        box.addButton(withTitle: VTLocalized("OK"))
        box.runModal()
    }

}

extension TelexInputController: NSMenuDelegate {
    // Remove the system-appended "Edit Text Substitutions…" item (+ dangling
    // separator). Try both hooks: menuNeedsUpdate (early) and menuWillOpen (right
    // before display, after the system has appended its items).
    func menuNeedsUpdate(_ menu: NSMenu) { stripSystemItems(menu) }
    func menuWillOpen(_ menu: NSMenu) { stripSystemItems(menu) }

    private func stripSystemItems(_ menu: NSMenu) {
        let subs = Selector(("orderFrontSubstitutionsPanel:"))
        for item in menu.items where item.action == subs || item.title.localizedCaseInsensitiveContains("substitution") {
            menu.removeItem(item)
        }
        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }
}

@inline(__always)
func isAsciiDigit(_ c: UInt8) -> Bool {
    c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")
}

@inline(__always)
func isAsciiLetter(_ c: UInt8) -> Bool {
    (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z")) ||
    (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
}

/// Does this key belong to the WORD (feed it to the engine) or end it (boundary)?
/// The ONE routing rule both key paths (IMKit controller + terminal tap) must agree on.
/// In VNI the digits carry the diacritics ("a1"→á), so they are word keys; in Telex a
/// digit ends the word. Extracted so AppTests can pin it — issue #28 (2026-07-27) was
/// exactly this predicate being letters-only while the engine happily accepted digits.
@inline(__always)
func isWordKey(_ c: UInt8, vniMode: Bool, bracketVowels: Bool = false) -> Bool {
    isAsciiLetter(c) || (vniMode && isAsciiDigit(c))
        || (bracketVowels && isBracketVowelKey(c))
}

/// `[ ] { }` — the keys the bracket-vowel option turns into ơ/ư. They must be WORD
/// keys while it is on (a boundary would commit the word before the engine sees the
/// vowel) and plain boundaries while it is off — see AppState.bracketVowels.
@inline(__always)
func isBracketVowelKey(_ c: UInt8) -> Bool {
    c == UInt8(ascii: "[") || c == UInt8(ascii: "]")
        || c == UInt8(ascii: "{") || c == UInt8(ascii: "}")
}

@inline(__always)
private func isBracket(_ c: UInt8) -> Bool {
    switch c {
    case UInt8(ascii: "["), UInt8(ascii: "]"),
         UInt8(ascii: "{"), UInt8(ascii: "}"),
         UInt8(ascii: "("), UInt8(ascii: ")"):
        return true
    default:
        return false
    }
}
