// Updater.swift
// Update check + self-update: the only code in VietTelex that makes network requests
// itself. Two triggers: the "Kiểm tra cập nhật" button in Settings → General → Updates
// (manual, GitHub releases/latest), and the weekly stable-channel check, which runs only
// after the user opts in. A newer version is announced (notification + General tab);
// it is downloaded only when the user picks "Update now" (SelfUpdater below).
// Apple Translation language packs are downloaded by the system, only when the user
// requests one in Settings → Suggestions & tools. No telemetry.

import Foundation
import AppKit
import UserNotifications
import Security

enum UpdateCheck {
    /// Set by the weekly auto-check when a newer STABLE version exists, so General → Updates
    /// can show it (see `UpdateSection.onAppear`). This is the whole point of the notification
    /// rewrite: the news must never arrive as a modal in the middle of a sentence, and if
    /// notifications are denied General → Updates is the only place left to say it.
    /// Persisted so it survives the IME being relaunched between the check and the visit.
    nonisolated(unsafe) static var pendingUpdateVersion: String? {
        get { notifyDefaults.string(forKey: "pendingUpdateVersion").flatMap { $0.isEmpty ? nil : $0 } }
        set { notifyDefaults.set(newValue ?? "", forKey: "pendingUpdateVersion") }
    }

    /// Changelog for `pendingUpdateVersion`, persisted for the same reason it is: the
    /// weekly check and the General-tab visit are separated by an IME relaunch, and
    /// re-fetching on `onAppear` would put the network back on a path the user never
    /// clicked. Always written and cleared together with the version above.
    nonisolated(unsafe) static var pendingUpdateNotes: String? {
        get { notifyDefaults.string(forKey: "pendingUpdateNotes").flatMap { $0.isEmpty ? nil : $0 } }
        set { notifyDefaults.set(newValue ?? "", forKey: "pendingUpdateNotes") }
    }
    // Same suite AppState uses — including the XCTest isolation (see settingsSuiteName).
    private static let notifyDefaults = UserDefaults(suiteName: AppState.settingsSuiteName) ?? .standard

    /// Weekly auto-check — runs ONLY when the user opted in (Settings toggle,
    /// default OFF, so the no-network stance still holds: the toggle is the ask).
    /// Event-driven (called from activateServer, throttled by timestamp — no
    /// timers), and each new version is announced at most once.
    ///
    /// It follows the STABLE channel, not the newest GitHub release: users are only
    /// nudged toward versions the maintainer explicitly promoted by bumping
    /// docs/stable.json on the website (deployed by GitHub Pages). The manual
    /// button in General → Updates still checks releases/latest — that's the "I want it now"
    /// path.
    ///
    /// Issue #120 (1.7.8 user, 3+ weeks, never notified): the throttle used to be stamped
    /// BEFORE the fetch, so a failed check counted as "checked this week" and the failure
    /// was invisible. In ≤1.8.1 every fetch failed (github.io 301 → http://viettelex.com,
    /// refused by ATS), so the weekly check silently did nothing, forever. Now only a
    /// check that actually reached the manifest (`.update`/`.upToDate`) resets the weekly
    /// clock; a failure just backs off `autoCheckRetryInterval` and is logged.
    static func maybeAutoCheck(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        guard bundleIdentifier == AppState.stableBundleIdentifier,
              AppState.shared.autoUpdateCheck else { return }
        let now = Date().timeIntervalSince1970
        guard shouldAutoCheck(now: now,
                              lastSuccessAt: AppState.shared.lastAutoUpdateCheckAt,
                              lastAttemptAt: AppState.shared.lastAutoUpdateAttemptAt) else { return }
        // Stamped up front so a burst of activateServer calls can't start parallel fetches.
        AppState.shared.lastAutoUpdateAttemptAt = now
        Task {
            let outcome = await checkStable()
            if case let .failed(reason) = outcome {
                DebugLog.log("update auto-check failed: \(reason) — retry in ≥\(Int(autoCheckRetryInterval / 3600))h")
                return
            }
            await MainActor.run { AppState.shared.lastAutoUpdateCheckAt = now }
            guard case let .update(latest, _, notes) = outcome else { return }
            await MainActor.run {
                guard AppState.shared.lastNotifiedUpdateVersion != latest else { return }
                AppState.shared.lastNotifiedUpdateVersion = latest
                // Always record it first: General → Updates shows this even if the banner
                // never appears (permission denied / Do Not Disturb). The notes ride
                // along so that surface can answer "what changed?", not just "something did".
                pendingUpdateVersion = latest
                pendingUpdateNotes = notes
                UpdateNotifier.post(version: latest)
            }
        }
    }
    static let autoCheckInterval: TimeInterval = 7 * 24 * 3600
    /// After a FAILED weekly check (offline at wake, captive portal, DNS, server down):
    /// try again on a later activateServer, but not more often than this.
    static let autoCheckRetryInterval: TimeInterval = 6 * 3600

    /// Pure schedule decision for the weekly check. `lastSuccessAt` is the last check that
    /// reached the manifest; `lastAttemptAt` the last one started (success or not).
    /// A timestamp in the future (clock moved back, or a stale value) never blocks
    /// forever — it counts as "due".
    static func shouldAutoCheck(now: TimeInterval, lastSuccessAt: TimeInterval,
                                lastAttemptAt: TimeInterval) -> Bool {
        func due(_ last: TimeInterval, _ every: TimeInterval) -> Bool {
            last > now || now - last >= every
        }
        return due(lastSuccessAt, autoCheckInterval) && due(lastAttemptAt, autoCheckRetryInterval)
    }

    /// The newer version still waiting for the user (weekly check found it, not installed
    /// yet) — nil once the running build has caught up, e.g. after a manual .pkg install,
    /// so nothing keeps advertising a version that is already here.
    static func outstandingUpdate(pending: String?, current: String) -> String? {
        guard let pending, isValidVersion(pending), isNewer(pending, than: current) else { return nil }
        return pending
    }

    /// Canonical repo (matches the git remote). GitHub redirects other casings.
    static let repo = "ptrinh/VietTelex"

    enum Outcome {
        case upToDate(String)                       // current == latest
        /// `notes` is the release body (Markdown), already sanitized — nil when GitHub
        /// had none or the fetch failed. Never a reason to fail the whole check.
        case update(latest: String, url: URL, notes: String?)
        case failed(String)                         // network / parse error
    }

    static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The STABLE channel: a tiny manifest the maintainer bumps BY HAND
    /// (docs/stable.json → GitHub Pages). Newest release ≠ stable — a fresh
    /// release soaks first; promoting it to every opted-in user is the explicit
    /// one-line edit of this file.
    /// Where the manifest lives, tried in order. The second is the SAME file (GitHub Pages
    /// serves docs/ from main) without the custom domain in between: ≤1.8.1 read only
    /// `ptrinh.github.io/viettelex/stable.json`, whose 301 goes through plain-http
    /// `http://viettelex.com` and is refused by App Transport Security — one hard-coded
    /// host was a single point of failure for every installed copy (issue #120).
    /// Every entry must stay https end to end, redirects included.
    static let stableManifestURLs = [
        "https://viettelex.com/stable.json",
        "https://raw.githubusercontent.com/ptrinh/viettelex/main/docs/stable.json",
    ]

    static func checkStable() async -> Outcome {
        var lastFailure = Outcome.failed("URL")
        for s in stableManifestURLs {
            guard let api = URL(string: s) else { continue }
            let outcome = await checkStable(at: api)
            if case .failed = outcome { lastFailure = outcome; continue }
            return outcome
        }
        return lastFailure
    }

    static func checkStable(at api: URL) async -> Outcome {
        let current = currentVersion()
        var req = URLRequest(url: api, timeoutInterval: 12)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else { return .failed("HTTP \(code)") }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stable = obj["version"] as? String,
                  isValidVersion(stable) else { return .failed("dữ liệu lạ") }
            let pageURL = (obj["url"] as? String).flatMap(URL.init(string:))
                ?? URL(string: "https://github.com/\(repo)/releases/latest")!
            guard isNewer(stable, than: current) else { return .upToDate(current) }
            // The manifest deliberately stays two lines the maintainer hand-edits, so the
            // changelog is read from the release that tag already points at — one source of
            // truth (the GitHub release body), no second thing to remember at promote time.
            return .update(latest: stable, url: pageURL,
                           notes: await releaseNotes(forVersion: stable))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The release body for one version's tag (`v1.6.3`), used by the STABLE channel —
    /// `/releases/latest` hands its body over for free, but `stable.json` only names a
    /// version, so that channel has to ask for the tag by name.
    ///
    /// Best-effort by construction: every failure path returns nil rather than throwing,
    /// because a missing changelog must never turn a real update into `.failed`. The
    /// version number is the news; the notes are the courtesy.
    static func releaseNotes(forVersion version: String) async -> String? {
        guard let api = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/v\(version)")
        else { return nil }
        var req = URLRequest(url: api, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("VietTelex/\(currentVersion())", forHTTPHeaderField: "User-Agent")
        guard let data = await boundedData(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return sanitizeNotes(obj["body"] as? String)
    }

    /// Longest changelog we will render. The Settings window is 640pt wide, not a browser;
    /// past this the "Full changelog" link is the better answer.
    static let notesCharacterCap = 2000

    /// Hard ceiling on any update-check response BEFORE it is buffered. `notesCharacterCap`
    /// trims what we render, but `URLSession.data(for:)` would still pull an arbitrarily
    /// large body into RAM first — and a release body is remote input. Real responses are
    /// a few KB; a megabyte of "release notes" is not news, it's a problem.
    static let responseByteCap = 1 << 20

    /// Fetch with the byte ceiling enforced during streaming: past the cap the transfer is
    /// abandoned and nil comes back, matching the notes' best-effort contract.
    static func boundedData(for req: URLRequest, cap: Int = responseByteCap) async -> Data? {
        guard let (bytes, resp) = try? await URLSession.shared.bytes(for: req) else { return nil }
        // Non-HTTP schemes (data: in tests) have no status code; HTTP must be 200.
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { return nil }
        var data = Data()
        data.reserveCapacity(min(cap, 64 * 1024))
        do {
            for try await byte in bytes {
                if data.count >= cap { return nil }
                data.append(byte)
            }
        } catch { return nil }
        return data
    }

    /// The release page for a version — same `v`-prefixed tag naming `SelfUpdater` uses to
    /// build the download URL. Derived rather than carried through `Outcome`, so the weekly
    /// channel (which only ever persists a version) can offer the link too.
    static func releasePageURL(forVersion version: String) -> URL? {
        URL(string: "https://github.com/\(repo)/releases/tag/v\(version)")
    }

    /// Make a remote release body safe to put on screen: drop git trailers, collapse the
    /// blank-line runs that leaves behind, and cap the length. Nothing here assumes the
    /// body is short, non-empty, or well-formed — it arrives over the network.
    static func sanitizeNotes(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var kept: [String] = []
        for line in raw.replacingOccurrences(of: "\r\n", with: "\n")
                       .split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isTrailer(trimmed) { continue }
            // Collapse runs of blanks (and drop leading ones) so stripping a trailer
            // doesn't leave a hole at the end of the notes.
            if trimmed.isEmpty, kept.last?.isEmpty ?? true { continue }
            kept.append(trimmed.isEmpty ? "" : String(line))
        }
        while kept.last?.isEmpty ?? false { kept.removeLast() }
        guard !kept.isEmpty else { return nil }
        let joined = kept.joined(separator: "\n")
        return joined.count > notesCharacterCap
            ? String(joined.prefix(notesCharacterCap)) + "…"
            : joined
    }

    /// Git trailer lines — `Co-Authored-By:`, `Signed-off-by:`, `Reviewed-by:` — which
    /// GitHub copies verbatim from the commit into the release body. Commit plumbing, not
    /// news: users opened the changelog to read what changed.
    static func isTrailer(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        let token = line[line.startIndex..<colon]
        guard !token.isEmpty, token.allSatisfy({ $0.isLetter || $0 == "-" }) else { return false }
        return token.lowercased().hasSuffix("-by")
    }

    /// Manual check (checkStable above is the weekly one; SelfUpdater downloads only after
    /// "Update now"). Called from the button in General → Updates. NOTE: GitHub's `/releases/latest` deliberately SKIPS pre-releases, so this
    /// is the newest STABLE release — a pre-release (v1.4.16 while stable is 1.4.15) is
    /// never pushed onto someone who just clicked "check". Same channel as the weekly
    /// auto-check in spirit; testers install a pre-release by hand.
    static func check() async -> Outcome {
        let current = currentVersion()
        guard let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return .failed("URL")
        }
        var req = URLRequest(url: api, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("VietTelex/\(current)", forHTTPHeaderField: "User-Agent")   // GitHub requires a UA
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else { return .failed("HTTP \(code)") }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { return .failed("dữ liệu lạ") }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard isValidVersion(latest) else { return .failed("dữ liệu lạ") }
            let pageURL = (obj["html_url"] as? String).flatMap(URL.init(string:))
                ?? URL(string: "https://github.com/\(repo)/releases/latest")!
            // This channel gets the changelog for free — the release body is already in
            // the response we just parsed for the tag. No second request.
            return isNewer(latest, than: current)
                ? .update(latest: latest, url: pageURL, notes: sanitizeNotes(obj["body"] as? String))
                : .upToDate(current)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// One block of a rendered changelog.
    ///
    /// GitHub returns Markdown, but SwiftUI's `Text` only interprets INLINE markdown
    /// (bold / code / links) — headings and bullets pass through as literal `##` and `-`.
    /// So the block markers are stripped here, and the view renders each `text` as inline
    /// markdown at the weight its `kind` calls for. Deliberately small: this is a release
    /// note, not a document, and a real Markdown engine is a dependency we don't need.
    struct NoteBlock: Identifiable {
        enum Kind: Equatable { case heading, bullet, paragraph }
        let id: Int
        let kind: Kind
        let text: String
    }

    /// An ATX heading needs a SPACE after the hashes — Markdown's own rule, and the reason
    /// a bare `hasPrefix("#")` is wrong: a release note opening with an issue reference
    /// ("#42 sửa lỗi gõ tắt") would otherwise be promoted to a heading with its `#` eaten,
    /// rendering as bold "42 sửa lỗi gõ tắt".
    static func isHeading(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("#") else { return false }
        let rest = trimmed.drop(while: { $0 == "#" })
        return rest.isEmpty || rest.hasPrefix(" ")
    }

    /// Split sanitized notes into renderable blocks. Blank lines are dropped: the view
    /// spaces blocks itself, so carrying them through would double the gaps.
    ///
    /// Fenced code blocks (```` ``` ````/`~~~`) are block syntax too: `Text` printed the
    /// fence lines literally (issue #120 screenshot: "brew install …" then a bare "```").
    /// Fence markers are dropped and each line inside becomes an inline code span. The
    /// "## Cài đặt / Install" section is dropped whole: it tells website readers how to
    /// download the .pkg or use brew — inside the app the "Update now" button IS that.
    static func noteBlocks(_ notes: String) -> [NoteBlock] {
        var out: [NoteBlock] = []
        var inFence = false
        var inInstallSection = false
        for line in notes.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if !inFence, isHeading(trimmed) {
                let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                inInstallSection = isInstallHeading(title)
            }
            guard !trimmed.isEmpty, !inInstallSection else { continue }
            let kind: NoteBlock.Kind
            var text = trimmed
            if inFence {
                kind = .paragraph
                // A code span can't hold its own delimiter; such a line stays plain text.
                text = trimmed.contains("`") ? trimmed : "`\(trimmed)`"
            } else if isHeading(trimmed) {
                kind = .heading
                text = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
                        || trimmed == "-" || trimmed == "*" {
                // The bare-marker case matters: a markerless bullet would otherwise fall
                // through as a paragraph reading "-" instead of being dropped as empty.
                kind = .bullet
                text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else {
                kind = .paragraph
            }
            guard !text.isEmpty else { continue }
            out.append(NoteBlock(id: out.count, kind: kind, text: text))
        }
        return out
    }

    /// Headings of the release body's download/install section (release template:
    /// "## Cài đặt"; English bodies "## Install"/"## Installation").
    static func isInstallHeading(_ title: String) -> Bool {
        let t = title.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        return ["cài đặt", "install", "installation", "cài đặt / install"].contains(t)
    }

    /// A remote version string is only trusted as 1–4 dot-separated groups of ASCII
    /// digits ("1.8.4"). It arrives from stable.json / the GitHub API and is later
    /// interpolated into a download URL AND a filesystem path (`SelfUpdater`'s work
    /// dir) BEFORE the signature gate runs — so "9.0/../../x" or anything with a slash,
    /// space or non-ASCII digit must be refused at the parse boundary. `isNewer` alone
    /// is no filter: it maps non-numeric parts to 0.
    static func isValidVersion(_ v: String) -> Bool {
        guard !v.isEmpty, v.utf8.count <= 32 else { return false }
        let groups = v.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(groups.count) else { return false }
        return groups.allSatisfy { g in
            !g.isEmpty && g.utf8.count <= 6 && g.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
        }
    }

    /// Numeric, dot-separated compare: "1.1.2" > "1.1.1" > "1.1".
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}


/// Weekly "a new version is out" banner.
///
/// This used to be a floating, activated NSAlert fired from `activateServer` — i.e. the
/// input method stole focus and swallowed keystrokes mid-sentence, once a week, at a
/// moment the user did not choose. A notification is the right shape for "news that can
/// wait": no focus change, no modal, dismissible, and it queues while Do Not Disturb is on.
/// Authorization is requested LAZILY on the first post (only opted-in users ever see the
/// system prompt); when it is refused we say nothing here and let General → Updates carry the
/// news via `UpdateCheck.pendingUpdateVersion`.
enum UpdateNotifier {
    static let categoryID = "viettelex.update"
    static let requestPrefix = "viettelex.update."

    /// Retained for the lifetime of the process: UNUserNotificationCenter keeps only a
    /// weak reference to its delegate.
    nonisolated(unsafe) private static var delegate: Delegate?

    @MainActor static func post(version: String) {
        let center = UNUserNotificationCenter.current()
        if delegate == nil {
            let d = Delegate()
            delegate = d
            center.delegate = d
        }
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }   // General → Updates is the fallback surface
            let content = UNMutableNotificationContent()
            content.title = String(format: VTLocalized("VietTelex %@ is available"), version)
            content.body = VTLocalized("Open Settings → General to install it.")
            content.userInfo = ["version": version]
            let req = UNNotificationRequest(identifier: requestPrefix + version,
                                            content: content, trigger: nil)
            center.add(req, withCompletionHandler: nil)
        }
    }

    /// Tapping the banner opens Settings → Chung (update block), where "Update now" is waiting —
    /// the user stays in control of WHEN the install happens.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            DispatchQueue.main.async {
                SettingsWindowController.shared.show(tab: .general, revealUpdate: true)
            }
            completionHandler()
        }
    }
}

/// In-place self-update. The bundle lives in USER-writable
/// ~/Library/Input Methods, so no admin rights are needed:
/// download the release app.zip → verify the Developer ID signature →
/// ditto over the installed bundle → exit (macOS relaunches the IME on the
/// next keystroke; already-open apps may need an input-source flip, same as
/// any IME restart).
enum SelfUpdater {
    static func canInstallUpdate(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == AppState.stableBundleIdentifier
    }

    /// `onFailure` runs on the main thread when the install did NOT happen (network,
    /// signature gate, unzip, swap). There is no success callback on purpose: a
    /// successful install ends in `exit(0)`.
    static func run(version: String, onFailure: (() -> Void)? = nil) {
        guard canInstallUpdate(bundleIdentifier: Bundle.main.bundleIdentifier) else {
            DebugLog.log("skip self-update: this is not the stable input method bundle")
            DispatchQueue.main.async { onFailure?() }
            return
        }
        // Re-checked here, not just at parse time: `version` can also come from a value
        // persisted by an older build (pendingUpdateVersion), and it is about to be
        // spliced into a URL. Refuse rather than force-unwrap.
        guard UpdateCheck.isValidVersion(version),
              let zipURL = URL(string:
                "https://github.com/ptrinh/viettelex/releases/download/v\(version)/VietTelex-\(version).app.zip")
        else {
            DispatchQueue.main.async { onFailure?() }
            return
        }
        // Random, never-before-used work dir: nothing remote-controlled goes into a path
        // we create and later delete, and there is no stale dir to remove first. Cleaned
        // up on EVERY exit path (success falls through to exit(0) after the removal).
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("viettelex-update-\(UUID().uuidString)", isDirectory: true)
        Task.detached {
            do {
                let (tmp, response) = try await URLSession.shared.download(from: zipURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NSError(domain: "SelfUpdater", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
                }
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

                try runTool("/usr/bin/ditto", ["-xk", tmp.path, work.path])
                let newApp = work.appendingPathComponent("VietTelex.app")
                guard FileManager.default.fileExists(atPath: newApp.path) else {
                    throw NSError(domain: "SelfUpdater", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "app missing in zip"])
                }
                // Signature gate: the seal must be intact (--verify --deep --strict),
                // AND the artifact must match OUR exact designated requirement — not
                // just "some app signed by our team". Security-scan finding 2026-08-11
                // (medium): the old gate substring-matched `codesign -dv`'s team-id text,
                // which lets through ANY app signed by the same Apple Developer Team ID,
                // not specifically com.viettelex.inputmethod.telex. The requirement string
                // is the SAME one Scripts/make-release.sh already enforces at release time
                // (identifier + Apple anchor + Developer ID cert extension + team OU) —
                // one designated requirement, checked at both ends of the pipeline.
                try runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
                try verifyDesignatedRequirement(at: newApp)
                // Đúng bản đã hỏi, và mới hơn bản đang chạy: một bản cũ hơn (dù ký đúng)
                // không được đè lên — chống hạ cấp + chống zip đặt nhầm tên.
                let downloaded = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
                let running = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                if let reason = versionRefusal(downloaded: downloaded, requested: version, running: running) {
                    throw NSError(domain: "SelfUpdater", code: 6,
                                  userInfo: [NSLocalizedDescriptionKey: reason])
                }

                let dest = ("~/Library/Input Methods/VietTelex.app" as NSString).expandingTildeInPath
                // Stop the event tap BEFORE the bundle under us is replaced. Apple's
                // update guidance (and Quinn in forums/thread/703188) is to quit the code
                // whose bundle you are about to swap: TCC identifies us by code signature,
                // and a live tap owned by a process whose backing bundle just got unlinked
                // is exactly the state that comes back as "listed but refused" after an
                // update. We exit a few lines below anyway — this just makes sure the tap
                // is gone first, not at some arbitrary point during teardown.
                // Swap fails (disk, permissions…) ⇒ the IME keeps running the OLD bundle:
                // the tap must come back now, not after the 600 s update quarantine
                // (terminals would type raw for ten minutes).
                try await installStoppingTap(
                    stop: { TerminalTapController.shared.stopForUpdate() },
                    install: { try installBundle(from: newApp, to: URL(fileURLWithPath: dest)) },
                    resume: { TerminalTapController.shared.resumeAfterFailedUpdate() })
                // Refresh the LaunchServices registration so the Text Input system relaunches
                // from the new bundle (mirrors notarize-install.sh).
                try? runTool("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", dest])
                try? FileManager.default.removeItem(at: work)

                await MainActor.run {
                    UpdateCheck.pendingUpdateVersion = nil   // installed; nothing left to nag about
                    UpdateCheck.pendingUpdateNotes = nil
                    let done = NSAlert()
                    done.messageText = String(format: VTLocalized("Updated to %@"), version)
                    done.informativeText = VTLocalized("Update done body")
                    done.addButton(withTitle: VTLocalized("Restart input method"))
                    NSApp.activate(ignoringOtherApps: true)
                    done.window.level = .floating
                    done.window.orderFrontRegardless()
                    _ = done.runModal()
                    // exit(0) skips applicationWillTerminate: save "Học từ bạn gõ" now.
                    LearnedWords.shared.flush()
                    exit(0)   // macOS relaunches the IME (new binary) on demand
                }
            } catch {
                try? FileManager.default.removeItem(at: work)
                await MainActor.run {
                    onFailure?()
                    let fail = NSAlert()
                    fail.messageText = VTLocalized("Update failed")
                    fail.informativeText = String(format: VTLocalized("Update failed body"), error.localizedDescription)
                    fail.addButton(withTitle: VTLocalized("Open releases page"))
                    fail.addButton(withTitle: VTLocalized("Close"))
                    NSApp.activate(ignoringOtherApps: true)
                    fail.window.level = .floating
                    fail.window.orderFrontRegardless()
                    if fail.runModal() == .alertFirstButtonReturn,
                       let u = URL(string: "https://github.com/ptrinh/viettelex/releases/latest") {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
        }
    }

    /// nil = OK to install; otherwise why not. The downloaded bundle must report exactly
    /// the version we asked for (a mislabeled asset is not that release) and be strictly
    /// newer than the running one (never downgrade, never reinstall the same build).
    static func versionRefusal(downloaded: String?, requested: String, running: String?) -> String? {
        guard let downloaded, UpdateCheck.isValidVersion(downloaded) else {
            return "downloaded app has no valid version"
        }
        guard downloaded == requested else {
            return "downloaded app is \(downloaded), expected \(requested)"
        }
        if let running, UpdateCheck.isValidVersion(running),
           !UpdateCheck.isNewer(downloaded, than: running) {
            return "\(downloaded) is not newer than the running \(running)"
        }
        return nil
    }

    /// Stop the tap (MAIN), swap the bundle, and if the swap throws, bring the tap back
    /// (MAIN) before rethrowing — the update quarantine must not outlive a failed swap.
    static func installStoppingTap(stop: @MainActor () -> Void,
                                   install: () throws -> Void,
                                   resume: @MainActor () -> Void) async throws {
        await MainActor.run { stop() }
        do {
            try install()
        } catch {
            await MainActor.run { resume() }
            throw error
        }
    }

    /// Install `newApp` over `dest`, ATOMICALLY and WHOLESALE — never `ditto newApp dest`
    /// into an existing bundle. `ditto` MERGES: it overwrites same-named files but leaves
    /// behind any resource a new version dropped or renamed. Those orphans break the code
    /// seal, so tccd refuses the event tap even though the Accessibility row still shows
    /// "allowed" (the "permission stuck after update" bug). `replaceItemAt` swaps in exactly
    /// the signed/notarized artifact — no merge residue — so the seal stays intact and the
    /// identity-based grant re-validates cleanly. On a fresh install (no `dest`) it's a move.
    static func installBundle(from newApp: URL, to dest: URL) throws {
        if FileManager.default.fileExists(atPath: dest.path) {
            _ = try FileManager.default.replaceItemAt(dest, withItemAt: newApp,
                                                      backupItemName: "VietTelex.app.bak")
        } else {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: newApp, to: dest)
        }
    }

    /// The exact designated requirement Scripts/make-release.sh's DR guard defines and
    /// verifies before an artifact is ever uploaded — pins identifier + Apple anchor +
    /// Developer ID Application cert extension + team OU, all four together. Kept as a
    /// single source of truth in comments on both ends since it can't be `import`ed
    /// across a shell script and a Swift app; `testExpectedRequirementStringMatchesReleaseScript`
    /// asserts the two stay byte-identical.
    static let expectedRequirementString =
        "identifier \"com.viettelex.inputmethod.telex\" and anchor apple generic " +
        "and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ " +
        "and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ " +
        "and certificate leaf[subject.OU] = \"84T567KMYD\""

    /// Throws unless `url` satisfies `expectedRequirementString` via
    /// `SecStaticCodeCheckValidity` — the OS's own designated-requirement evaluator,
    /// not a text-parse of `codesign -dv` output (fragile across macOS/codesign
    /// versions, and — the bug this replaces — a plain substring match on the team ID
    /// alone, which any app from the same Apple Developer Team could satisfy).
    static func verifyDesignatedRequirement(at url: URL) throws {
        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            throw NSError(domain: "SelfUpdater", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "couldn't read code signature (\(status))"])
        }
        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(expectedRequirementString as CFString, [], &requirement)
        guard status == errSecSuccess, let req = requirement else {
            throw NSError(domain: "SelfUpdater", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "couldn't parse designated requirement (\(status))"])
        }
        status = SecStaticCodeCheckValidity(code, SecCSFlags(), req)
        guard status == errSecSuccess else {
            throw NSError(domain: "SelfUpdater", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "unexpected signing identity (\(status))"])
        }
    }

    @discardableResult
    private static func runTool(_ path: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "SelfUpdater", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(path) exit \(p.terminationStatus)"])
        }
        return p.terminationStatus
    }

}
