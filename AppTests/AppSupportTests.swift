import XCTest
import TelexCore
@testable import VietTelex

// Support-layer coverage: DebugLog ring semantics, Updater version logic +
// stubbed network paths, the Accessibility trust cache, and the safe (non-posting)
// SyntheticKeyboard state helpers. Detector getters are smoke-read only — their
// values depend on live system state (windows, AX), so asserting them would flake.
final class AppSupportTests: XCTestCase {

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        AppState.shared.debugLogging = false
        super.tearDown()
    }

    // MARK: DebugLog

    func testDebugLogRing() {
        let wasOn = AppState.shared.debugLogging
        defer { AppState.shared.debugLogging = wasOn }
        AppState.shared.debugLogging = false
        DebugLog.clear()
        DebugLog.log("must NOT be recorded")
        XCTAssertFalse(DebugLog.snapshot(header: []).contains("must NOT be recorded"))
        AppState.shared.debugLogging = true
        DebugLog.log("recorded line")
        let snap = DebugLog.snapshot(header: ["HEADER"])
        XCTAssertTrue(snap.contains("HEADER"))
        XCTAssertTrue(snap.contains("recorded line"))
        // Ring caps at 2000 (400 held only ~35s of debug-logged typing — testers'
        // incident had always scrolled out, 2026-07-30): oldest line evicted, never a crash.
        for i in 0..<2050 { DebugLog.log("filler \(i)") }
        let full = DebugLog.snapshot(header: [])
        XCTAssertFalse(full.contains("recorded line"))
        XCTAssertFalse(full.contains("filler 49\n"))  // \n-anchored: "filler 490" must not match
        XCTAssertTrue(full.contains("filler 50\n"))   // 2050 logged − 2000 cap = first kept
        XCTAssertTrue(full.contains("filler 2049"))
        DebugLog.clear()
        XCTAssertTrue(DebugLog.snapshot(header: []).contains("log empty"))
    }

    // MARK: Updater — pure logic

    func testVersionCompare() {
        XCTAssertTrue(UpdateCheck.isNewer("1.3.1", than: "1.3.0"))
        XCTAssertTrue(UpdateCheck.isNewer("1.10.0", than: "1.9.9"))   // numeric, not lexical
        XCTAssertTrue(UpdateCheck.isNewer("1.3.0.1", than: "1.3.0"))  // length mismatch
        XCTAssertFalse(UpdateCheck.isNewer("1.3.0", than: "1.3.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2.9", than: "1.3.0"))
        XCTAssertFalse(UpdateCheck.isNewer("garbage", than: "1.0"))   // non-numeric → 0
        XCTAssertFalse(UpdateCheck.currentVersion().isEmpty)
    }

    func testReleaseNotesSanitizing() {
        XCTAssertNil(UpdateCheck.sanitizeNotes(nil))
        XCTAssertNil(UpdateCheck.sanitizeNotes(""))
        XCTAssertNil(UpdateCheck.sanitizeNotes("\n\n  \n"))          // blank-only → nothing to show

        // Git trailers are commit plumbing; the release body carries them verbatim, and
        // stripping one must not leave a hole at the end (v1.6.3 shipped with exactly this).
        let body = "## Tính năng mới\n\n- Phím ngoặc `[` ra ơ\n\nCảm ơn bạn Tuấn Linh\n\n" +
                   "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n"
        let clean = UpdateCheck.sanitizeNotes(body)
        XCTAssertNotNil(clean)
        XCTAssertFalse(clean!.contains("Co-Authored-By"))
        XCTAssertFalse(clean!.hasSuffix("\n"))
        XCTAssertTrue(clean!.contains("Cảm ơn bạn Tuấn Linh"))
        XCTAssertFalse(clean!.contains("\n\n\n"))                    // blank runs collapsed
        XCTAssertTrue(UpdateCheck.isTrailer("Signed-off-by: A B"))
        XCTAssertTrue(UpdateCheck.isTrailer("Reviewed-By: A B"))
        XCTAssertFalse(UpdateCheck.isTrailer("Ví dụ: th[ → thơ"))    // a colon alone isn't a trailer
        XCTAssertFalse(UpdateCheck.isTrailer("- Bật ở Cài đặt: Thử nghiệm"))

        // Long bodies are truncated, not rendered whole into a 640pt window.
        let huge = UpdateCheck.sanitizeNotes(String(repeating: "x", count: 9000))
        XCTAssertEqual(huge?.count, UpdateCheck.notesCharacterCap + 1)   // + the ellipsis
    }

    // MARK: Default ngôn ngữ UI — chốt để không ai lật ngược (maintainer 15/08/2026)

    func testUILanguageDefaultsToVietnamese() {
        // "system" cho UI tiếng Anh trên máy để macOS tiếng Anh, trong khi gần như
        // toàn bộ user là người Việt → default thẳng "vi" (1.6.6). Xoá key trong
        // suite TEST (không phải suite thật — xem AppState.settingsSuiteName) để đọc
        // đúng giá trị mặc định của code, rồi trả lại nguyên trạng.
        let s = AppState.shared
        let saved = s.defaults.object(forKey: "uiLanguage")
        s.defaults.removeObject(forKey: "uiLanguage")
        XCTAssertEqual(s.uiLanguage, "vi", "default ngôn ngữ UI phải là tiếng Việt")
        // Và VTLocalized phải THẬT SỰ ra tiếng Việt ở default đó, không chỉ trả về key.
        XCTAssertEqual(VTLocalized("Settings"), "Tùy chỉnh")
        if let saved { s.defaults.set(saved, forKey: "uiLanguage") }
    }

    // MARK: Field report 14/08/2026 — "VietTelex tự nhiên bị mờ" = secure input

    func testSecureInputPIDExtraction() {
        // Shape thật của IOConsoleUsers: mảng session dict, chỉ session đang giữ
        // secure input mới mang key kCGSSessionSecureInputPID.
        let users: [[String: Any]] = [
            ["kCGSSessionUserNameKey": "loginwindow", "kCGSSessionOnConsoleKey": false],
            ["kCGSSessionUserNameKey": "ptrinh", "kCGSSessionSecureInputPID": 4242],
        ]
        XCTAssertEqual(SecureInputMonitor.extractSecureInputPID(consoleUsers: users), 4242)
        XCTAssertNil(SecureInputMonitor.extractSecureInputPID(consoleUsers: []))
        XCTAssertNil(SecureInputMonitor.extractSecureInputPID(consoleUsers: [["a": 1]]))
        // PID 0 nghĩa là "không ai giữ" trong một số bản macOS — không được coi là thủ phạm.
        XCTAssertNil(SecureInputMonitor.extractSecureInputPID(
            consoleUsers: [["kCGSSessionSecureInputPID": 0]]))
    }

    func testSecureInputHolderLabelIsGreppable() {
        // Label đi vào unified log + bug report: phải chứa cả tên lẫn PID, và không
        // vỡ khi không resolve được tên (process đã chết giữa chừng).
        XCTAssertEqual(SecureInputMonitor.Holder(pid: 123, name: "iTerm2", alive: true).label,
                       "iTerm2 (PID 123)")
        XCTAssertEqual(SecureInputMonitor.Holder(pid: 123, name: nil, alive: true).label, "PID 123")
        // Khoá mồ côi (field case 18/08: Lark chết không nhả): label phải nói rõ —
        // và alive nằm trong Equatable nên sống→chết tự thành transition được log.
        XCTAssertEqual(SecureInputMonitor.Holder(pid: 123, name: nil, alive: false).label,
                       "PID 123, exited")
        XCTAssertTrue(SecureInputMonitor.processIsAlive(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(SecureInputMonitor.processIsAlive(99_999_999))   // PID không tồn tại
        XCTAssertTrue(SecureInputMonitor.processIsAlive(0))             // không rõ ai giữ → đừng khuyên láo
        // Tên process của chính test host phải resolve được (đường NSRunningApplication).
        XCTAssertNotNil(SecureInputMonitor.processName(ProcessInfo.processInfo.processIdentifier))
    }

    func testBoundedDataEnforcesByteCap() async {
        // data: URLs keep the test off the network; the cap must apply while streaming.
        let small = URLRequest(url: URL(string: "data:text/plain,hello")!)
        let got = await UpdateCheck.boundedData(for: small, cap: 16)
        XCTAssertEqual(got.flatMap { String(data: $0, encoding: .utf8) }, "hello")

        let big = URLRequest(url: URL(string: "data:text/plain," +
                                      String(repeating: "x", count: 100))!)
        let over = await UpdateCheck.boundedData(for: big, cap: 16)
        XCTAssertNil(over)                                    // over cap → abandoned, not truncated

        let exact = await UpdateCheck.boundedData(for: small, cap: 5)
        XCTAssertEqual(exact.map { $0.count }, 5)             // cap boundary is inclusive
    }

    func testReleaseNoteBlockParsing() {
        let blocks = UpdateCheck.noteBlocks("## Tính năng mới\n\n- **Phím ngoặc**\n* second\nplain line")
        XCTAssertEqual(blocks.count, 4)                      // blank line dropped
        XCTAssertEqual(blocks[0].kind, .heading)
        XCTAssertEqual(blocks[0].text, "Tính năng mới")      // marker stripped, not rendered as "##"
        XCTAssertEqual(blocks[1].kind, .bullet)
        XCTAssertEqual(blocks[1].text, "**Phím ngoặc**")     // inline markdown left for Text
        XCTAssertEqual(blocks[2].kind, .bullet)              // "*" bullets too
        XCTAssertEqual(blocks[3].kind, .paragraph)
        XCTAssertEqual(UpdateCheck.noteBlocks("").count, 0)
        XCTAssertEqual(UpdateCheck.noteBlocks("###\n-  ").count, 0)   // markers with no text

        // ATX headings need a space after the hashes. An issue reference opening a line is
        // NOT a heading — treating it as one ate the "#" and bolded the rest.
        let issueRef = UpdateCheck.noteBlocks("#42 sửa lỗi gõ tắt")
        XCTAssertEqual(issueRef.first?.kind, .paragraph)
        XCTAssertEqual(issueRef.first?.text, "#42 sửa lỗi gõ tắt")
        XCTAssertTrue(UpdateCheck.isHeading("## Heading"))
        XCTAssertFalse(UpdateCheck.isHeading("#42"))

        XCTAssertEqual(UpdateCheck.releasePageURL(forVersion: "1.6.3")?.absoluteString,
                       "https://github.com/\(UpdateCheck.repo)/releases/tag/v1.6.3")
    }

    // MARK: Updater — network paths via a URLProtocol stub

    func testCheckPathsAgainstStubbedNetwork() async {
        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }

        // Stable manifest newer than current → .update with the manifest URL. The stable
        // channel has no changelog of its own, so it must go on to ask for the TAG's
        // release body (`releases/tags/v99.0.0`) — that's what gives both channels notes.
        StubURLProtocol.responder = { url in
            if url.absoluteString.contains("stable.json") {
                return (200, #"{"version":"99.0.0","url":"https://example.com/rel"}"#)
            }
            if url.absoluteString.contains("releases/tags/v99.0.0") {
                // ##"…"## delimiters, and the body starts with \n: a literal `"##` inside a
                // #"…"# raw string would close it early. The leading blank line also proves
                // sanitizeNotes trims it off the front.
                return (200, ##"{"tag_name":"v99.0.0","body":"\n## Heading\n- from the tag"}"##)
            }
            return (200, #"{"tag_name":"v99.0.0","html_url":"https://example.com/gh","body":"- from latest"}"#)
        }
        if case let .update(latest, url, notes) = await UpdateCheck.checkStable() {
            XCTAssertEqual(latest, "99.0.0")
            XCTAssertEqual(url.absoluteString, "https://example.com/rel")
            XCTAssertEqual(notes, "## Heading\n- from the tag")
        } else { XCTFail("expected .update from stable") }
        if case let .update(latest, _, notes) = await UpdateCheck.check() {
            XCTAssertEqual(latest, "99.0.0")
            XCTAssertEqual(notes, "- from latest")   // free: same response as the tag lookup
        } else { XCTFail("expected .update from latest") }

        // A release with no body is still an update — just without the notes box.
        StubURLProtocol.responder = { url in
            url.absoluteString.contains("stable.json")
                ? (200, #"{"version":"99.0.0","url":"https://example.com/rel"}"#)
                : (200, #"{"tag_name":"v99.0.0"}"#)
        }
        if case let .update(_, _, notes) = await UpdateCheck.checkStable() {
            XCTAssertNil(notes)
        } else { XCTFail("bodyless release must still be .update") }

        // The load-bearing invariant of the whole feature: the CHANGELOG lookup is
        // best-effort, so a tag endpoint that 404s (tag named differently, release deleted,
        // rate limit) must still yield .update — the version is the news, notes are extra.
        StubURLProtocol.responder = { url in
            url.absoluteString.contains("stable.json")
                ? (200, #"{"version":"99.0.0","url":"https://example.com/rel"}"#)
                : (404, #"{"message":"Not Found"}"#)
        }
        if case let .update(latest, _, notes) = await UpdateCheck.checkStable() {
            XCTAssertEqual(latest, "99.0.0")
            XCTAssertNil(notes)
        } else { XCTFail("a failed notes fetch must not fail the update check") }

        // Same version → upToDate.
        let cur = UpdateCheck.currentVersion()
        StubURLProtocol.responder = { url in
            url.absoluteString.contains("stable.json")
                ? (200, #"{"version":"\#(cur)"}"#)
                : (200, #"{"tag_name":"v\#(cur)"}"#)
        }
        if case .upToDate = await UpdateCheck.checkStable() {} else { XCTFail("stable upToDate") }
        if case .upToDate = await UpdateCheck.check() {} else { XCTFail("latest upToDate") }

        // HTTP error and junk payload → .failed, never a crash.
        StubURLProtocol.responder = { _ in (500, "boom") }
        if case .failed = await UpdateCheck.checkStable() {} else { XCTFail("stable failed") }
        if case .failed = await UpdateCheck.check() {} else { XCTFail("latest failed") }
        StubURLProtocol.responder = { _ in (200, "not json at all") }
        if case .failed = await UpdateCheck.checkStable() {} else { XCTFail("stable junk") }
        if case .failed = await UpdateCheck.check() {} else { XCTFail("latest junk") }
    }

    func testMaybeAutoCheckGuards() {
        let s = AppState.shared
        let savedOptIn = s.autoUpdateCheck
        let savedAt = s.lastAutoUpdateCheckAt
        defer { s.autoUpdateCheck = savedOptIn; s.lastAutoUpdateCheckAt = savedAt }
        // Opt-out: returns without touching the throttle timestamp.
        s.autoUpdateCheck = false
        s.lastAutoUpdateCheckAt = 0
        UpdateCheck.maybeAutoCheck()
        XCTAssertEqual(s.lastAutoUpdateCheckAt, 0)
        // Opted in but checked recently: throttle holds.
        s.autoUpdateCheck = true
        let now = Date().timeIntervalSince1970
        s.lastAutoUpdateCheckAt = now
        UpdateCheck.maybeAutoCheck()
        XCTAssertEqual(s.lastAutoUpdateCheckAt, now)
    }

    // MARK: Updater — bundle install (the "permission stuck after update" fix)

    // installBundle must swap in the new bundle WHOLESALE. The old `ditto newApp dest`
    // merged — it overwrote same-named files but left orphans from resources a new
    // version dropped/renamed, breaking the code seal so tccd refused the event tap.
    // These build throwaway directory trees (not real .app bundles) and assert the
    // on-disk result is byte-identical to the source, with no merge residue.
    private func writeTree(_ files: [String: String], at root: URL) throws {
        for (rel, body) in files {
            let f = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try body.write(to: f, atomically: true, encoding: .utf8)
        }
    }

    private func readTree(at root: URL) -> [String: String] {
        var out: [String: String] = [:]
        let base = root.standardizedFileURL.path
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return out }
        for case let url as URL in en {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard !isDir.boolValue else { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            out[rel] = (try? String(contentsOf: url, encoding: .utf8)) ?? "<binary>"
        }
        return out
    }

    func testInstallBundleFreshInstall() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt-install-fresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let src = tmp.appendingPathComponent("staging/VietTelex.app")
        let dest = tmp.appendingPathComponent("Input Methods/VietTelex.app")
        let payload = ["Contents/MacOS/VietTelex": "v2-binary",
                       "Contents/Info.plist": "v2-plist"]
        try writeTree(payload, at: src)

        try SelfUpdater.installBundle(from: src, to: dest)   // no existing dest → move

        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(readTree(at: dest), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path), "source should be consumed")
    }

    func testInstallBundleReplacesWholesaleAndDropsOrphans() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt-install-replace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let src = tmp.appendingPathComponent("staging/VietTelex.app")
        let dest = tmp.appendingPathComponent("Input Methods/VietTelex.app")

        // Old installed bundle: has a resource the new version renames away.
        try writeTree(["Contents/MacOS/VietTelex": "v1-binary",
                       "Contents/Info.plist": "v1-plist",
                       "Contents/Resources/old-lexicon.dat": "STALE",       // orphan-to-be
                       "Contents/CodeResources": "v1-seal"], at: dest)
        // New bundle: binary changed, lexicon renamed, no old-lexicon.dat.
        let payload = ["Contents/MacOS/VietTelex": "v2-binary",
                       "Contents/Info.plist": "v2-plist",
                       "Contents/Resources/lexicon-v2.dat": "FRESH",
                       "Contents/CodeResources": "v2-seal"]
        try writeTree(payload, at: src)

        try SelfUpdater.installBundle(from: src, to: dest)

        // Wholesale: dest is byte-identical to the new artifact — the orphan is GONE
        // (a merge would have kept old-lexicon.dat and broken the seal).
        XCTAssertEqual(readTree(at: dest), payload)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("Contents/Resources/old-lexicon.dat").path),
            "orphaned file from the old version must be removed (no merge)")
        // No leftover backup dir beside the installed bundle.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.deletingLastPathComponent().appendingPathComponent("VietTelex.app.bak").path),
            "backup must not linger after a successful replace")
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path), "source should be consumed")
    }

    // MARK: SelfUpdater — designated-requirement signature gate (security-scan
    // finding 2026-08-11, medium): the old gate substring-matched the team ID out
    // of `codesign -dv` text, which any app signed by the same Apple Developer Team
    // would satisfy. verifyDesignatedRequirement uses SecStaticCodeCheckValidity
    // against the FULL requirement (identifier + anchor + cert fields + team OU).

    /// The two ends of the release pipeline (Scripts/make-release.sh's DR guard and
    /// SelfUpdater's install-time gate) hand-carry the same requirement string
    /// because it can't be `import`ed across a shell script and a Swift app — this
    /// pins them byte-identical so the two can't silently drift apart.
    func testExpectedRequirementStringMatchesReleaseScript() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/make-release.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        guard let line = script.split(separator: "\n").first(where: { $0.hasPrefix("EXPECTED_DR=") })
        else { return XCTFail("EXPECTED_DR line not found in make-release.sh") }
        // EXPECTED_DR='designated => identifier "..." and ...' — strip the
        // `designated => ` prefix codesign -d -r- prints that make-release.sh
        // matches against verbatim, and the surrounding single quotes.
        var value = String(line.dropFirst("EXPECTED_DR=".count))
        XCTAssertTrue(value.hasPrefix("'") && value.hasSuffix("'"), "unexpected quoting in \(line)")
        value = String(value.dropFirst().dropLast())
        XCTAssertTrue(value.hasPrefix("designated => "))
        value = String(value.dropFirst("designated => ".count))
        XCTAssertEqual(SelfUpdater.expectedRequirementString, value)
    }

    /// The requirement must at minimum be a well-formed, parseable Designated
    /// Requirement string — a typo here would silently make every update fail
    /// (worse: if malformed in a way SecRequirementCreateWithString still accepts,
    /// it could accept MORE than intended). Doesn't need code-signing entitlements
    /// to run: this only exercises the requirement-language parser.
    func testExpectedRequirementStringParses() {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            SelfUpdater.expectedRequirementString as CFString, [], &requirement)
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(requirement)
    }

    /// The gate must REJECT an artifact that doesn't satisfy the requirement — the
    /// exact failure mode the old substring-match gate couldn't produce (any team
    /// member's signed app passed). The test bundle's own Contents/MacOS/xctest
    /// binary is signed by Apple, not by us, so it must fail our identifier+OU check.
    func testVerifyDesignatedRequirementRejectsWrongIdentity() {
        let xctestBinary = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        XCTAssertThrowsError(try SelfUpdater.verifyDesignatedRequirement(at: xctestBinary))
    }

    /// The positive case: a REAL Developer ID-signed VietTelex.app must pass. Skips
    /// gracefully where none is installed (CI, a fresh checkout) — this only proves
    /// the gate isn't so strict it rejects the app's OWN legitimate signature.
    func testVerifyDesignatedRequirementAcceptsOurOwnSignedApp() throws {
        let installed = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Input Methods/VietTelex.app")
        guard FileManager.default.fileExists(atPath: installed.path) else {
            throw XCTSkip("no installed VietTelex.app on this machine")
        }
        try SelfUpdater.verifyDesignatedRequirement(at: installed)   // must not throw
    }

    // MARK: Accessibility trust cache

    func testTrustOverrideAndCache() {
        Accessibility.testTrustOverride = true
        XCTAssertTrue(Accessibility.isTrusted)
        Accessibility.testTrustOverride = false
        XCTAssertFalse(Accessibility.isTrusted)
        Accessibility.testTrustOverride = nil
        Accessibility.invalidateCache()
        let real = Accessibility.isTrusted     // whatever TCC says on this machine…
        XCTAssertEqual(Accessibility.isTrusted, real)   // …the cache answers the same
    }

    /// PR #41's UI reader: sync, cache-bypassing — but it must still honor the
    /// DEBUG override BOTH ways, or every test that forces a trust state would
    /// leak the build machine's real TCC answer into the banner logic.
    func testReadTrustNowHonorsOverrideBothWays() {
        Accessibility.testTrustOverride = true
        XCTAssertTrue(Accessibility.readTrustNow())
        Accessibility.testTrustOverride = false
        XCTAssertFalse(Accessibility.readTrustNow())
        Accessibility.testTrustOverride = nil
        // No override: agrees with the machine's real TCC answer, and — since it
        // refreshes the shared cache on the way — a subsequent cached read agrees too.
        let real = Accessibility.readTrustNow()
        XCTAssertEqual(Accessibility.isTrusted, real)
    }

    // MARK: SyntheticKeyboard state helpers (safe: nothing is posted)

    func testSyntheticKeyboardStateHelpers() {
        SyntheticKeyboard.resetBreaker()
        XCTAssertFalse(SyntheticKeyboard.tripped)
        XCTAssertTrue(SyntheticKeyboard.queueDrained())
        SyntheticKeyboard.noteObservedSynthetic()   // underflow-safe at zero
        XCTAssertTrue(SyntheticKeyboard.queueDrained())
    }

    // MARK: Detector getters — smoke reads (values are live system state)

    func testDetectorSmokeReads() {
        _ = SpotlightDetector.isVisible
        _ = FocusedFieldDetector.wantsSelection
        _ = FocusedFieldDetector.isTextInput
    }
}

/// Minimal URLProtocol stub: answers every request from `responder` without
/// touching the network. Registered per-test; URLSession.shared consults
/// registered protocol classes for its default configuration.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: ((URL) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let (code, body) = Self.responder?(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let resp = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// Settings accessors round-trip: every UserDefaults-backed property reads back
// what it stores, and the explicit value is restored afterwards.
extension AppSupportTests {
    func testSettingsAccessorRoundTrips() {
        let s = AppState.shared
        // Bool accessors (save → flip → assert → restore).
        let bools: [(get: () -> Bool, set: (Bool) -> Void)] = [
            ({ s.autoRestore }, { s.autoRestore = $0 }),
            ({ s.freeMarking }, { s.freeMarking = $0 }),
            ({ s.modernOrthography }, { s.modernOrthography = $0 }),
            ({ s.liveSpellCheck }, { s.liveSpellCheck = $0 }),
            ({ s.simpleTelex }, { s.simpleTelex = $0 }),
            ({ s.quickTelex }, { s.quickTelex = $0 }),
            ({ s.vniMode }, { s.vniMode = $0 }),
            ({ s.contextualEnglish }, { s.contextualEnglish = $0 }),
            ({ s.bracketVowels }, { s.bracketVowels = $0 }),
            ({ s.tapModifyEventInPlace }, { s.tapModifyEventInPlace = $0 }),
            ({ s.tapSkipSyntheticKeyUp }, { s.tapSkipSyntheticKeyUp = $0 }),
            ({ s.axSelectionReplace }, { s.axSelectionReplace = $0 }),
            ({ s.tapCascadeBreaker }, { s.tapCascadeBreaker = $0 }),
            ({ s.debugLogging }, { s.debugLogging = $0 }),
            ({ s.advancedFeatures }, { s.advancedFeatures = $0 }),
            ({ s.autoUpdateCheck }, { s.autoUpdateCheck = $0 }),
            ({ s.axPromptShown }, { s.axPromptShown = $0 }),
        ]
        for accessor in bools {
            let saved = accessor.get()
            accessor.set(!saved)
            XCTAssertEqual(accessor.get(), !saved)
            accessor.set(saved)
            XCTAssertEqual(accessor.get(), saved)
        }
        // String/scalar accessors.
        let lang = s.uiLanguage
        s.uiLanguage = "vi"; XCTAssertEqual(s.uiLanguage, "vi")
        s.uiLanguage = lang
        let v = s.lastNotifiedUpdateVersion
        s.lastNotifiedUpdateVersion = "9.9.9"
        XCTAssertEqual(s.lastNotifiedUpdateVersion, "9.9.9")
        s.lastNotifiedUpdateVersion = v
        XCTAssertFalse(VTLocalized("Close").isEmpty)   // localization lookup path
        _ = s.tapNativeFastPath
    }

    /// Maintainer decision 2026-08-12: the power-user surface (Bảng chế độ gõ +
    /// Thử Nghiệm) ships VISIBLE — hiding it made every support round-trip start
    /// with "bật advanced lên đã". A fresh install (key absent) must read true;
    /// an explicit user OFF must still stick.
    func testAdvancedFeaturesDefaultsOn() {
        let s = AppState.shared
        let saved = s.defaults.object(forKey: "advancedFeatures") as? Bool
        defer {
            if let saved { s.defaults.set(saved, forKey: "advancedFeatures") }
            else { s.defaults.removeObject(forKey: "advancedFeatures") }
        }
        s.defaults.removeObject(forKey: "advancedFeatures")
        XCTAssertTrue(s.advancedFeatures, "fresh install (no stored value) must show the advanced tabs")
        s.advancedFeatures = false
        XCTAssertFalse(s.advancedFeatures, "explicit OFF must survive the ON default")
    }

    /// Issue #40 (Discord): the markActive AX poke fires only when a reach-back
    /// feature can use the tree AND the app's keys go through the tap — axDetect
    /// browsers are poked by field scans already, and an opted-out machine must not
    /// touch other processes' AX at all.
    func testLazyAXPokeGate() {
        XCTAssertTrue(FocusedFieldDetector.lazyAXPokeWanted(reEditEnabled: true, routesTap: true))
        XCTAssertFalse(FocusedFieldDetector.lazyAXPokeWanted(reEditEnabled: false, routesTap: true))
        XCTAssertFalse(FocusedFieldDetector.lazyAXPokeWanted(reEditEnabled: true, routesTap: false))
        XCTAssertFalse(FocusedFieldDetector.lazyAXPokeWanted(reEditEnabled: false, routesTap: false))
    }

    /// reEditWord gates TWO reach-back behaviors — re-edit ("toan"+s→toán) and the ⌫
    /// re-open of PR #42 ("tháy ␣"+⌫+a→thấy, issue #40). Default flipped ON 14/08/2026
    /// after PR #42 replaced the GUESS that caused the 04/08 revert with a verified
    /// snapshot (see the AppState doc for the full history). Pinned in both directions:
    /// a fresh install has it on, and an explicit OFF must survive the ON default —
    /// that opt-out is the escape hatch if the 04/08 class ever resurfaces.
    func testReEditGateDefaultsOn() {
        let s = AppState.shared
        let saved = s.defaults.object(forKey: "reEditWord") as? Bool
        defer {
            if let saved { s.defaults.set(saved, forKey: "reEditWord") }
            else { s.defaults.removeObject(forKey: "reEditWord") }
        }
        s.defaults.removeObject(forKey: "reEditWord")
        XCTAssertTrue(s.reEditWord, "fresh install: reach-back behaviors on by default")
        s.reEditWord = false
        XCTAssertFalse(s.reEditWord, "explicit OFF must survive the ON default")
    }
}

// The key-ROUTING predicate shared by the IMKit controller and the terminal tap:
// which keys belong to the word (→ engine.feed) vs end it (→ boundary commit).
// Issue #28 (2026-07-27): VNI shipped working at the engine level but did nothing in
// the app because BOTH key paths gated on letters only, so every VNI digit was eaten
// as a word boundary ("a1" stayed "a1"). Pin the rule here.
final class WordKeyRoutingTests: XCTestCase {

    func testLettersAreAlwaysWordKeys() {
        for c in "abzABZ".utf8 {
            XCTAssertTrue(isWordKey(c, vniMode: false), "'\(Character(UnicodeScalar(c)))' must compose")
            XCTAssertTrue(isWordKey(c, vniMode: true))
        }
    }

    func testDigitsAreWordKeysOnlyInVNI() {
        for c in "0123456789".utf8 {
            XCTAssertFalse(isWordKey(c, vniMode: false), "a digit ends the word in Telex")
            XCTAssertTrue(isWordKey(c, vniMode: true), "a digit carries the diacritic in VNI")
        }
    }

    func testEverythingElseIsABoundaryInBothModes() {
        for c in " \t.,;:!?-_/\\[]{}()'\"@#$%^&*+=<>|~`".utf8 {
            XCTAssertFalse(isWordKey(c, vniMode: false))
            XCTAssertFalse(isWordKey(c, vniMode: true))
        }
    }
}

// Re-edit the word before the caret (experimental, opt-in): the two PURE pieces of the
// decision — which keys may trigger a read-back, and which trailing text counts as a
// re-editable word. The seeding itself is engine-side (TelexEngine.seed, round-trip
// checked there); the IMKit wiring needs a live client and is covered by hand.
final class ReEditWordTests: XCTestCase {

    func testOnlyModifierKeysTrigger() {
        for c in "sfrxjzwSFRXJZW".utf8 {
            XCTAssertTrue(TelexInputController.isDiacriticOnlyKey(c, vni: false),
                          "'\(Character(UnicodeScalar(c)))' is a Telex modifier")
        }
        // Ordinary letters — including the doublers a/e/o/d — must NOT trigger a read-back.
        for c in "abcdeghiklmnopqtuvy".utf8 {
            XCTAssertFalse(TelexInputController.isDiacriticOnlyKey(c, vni: false),
                           "'\(Character(UnicodeScalar(c)))' is a letter, not a modifier")
        }
        // VNI: the digits carry the diacritics, letters never do.
        for c in "0123456789".utf8 {
            XCTAssertTrue(TelexInputController.isDiacriticOnlyKey(c, vni: true))
        }
        for c in "sfrxjw".utf8 {
            XCTAssertFalse(TelexInputController.isDiacriticOnlyKey(c, vni: true),
                           "in VNI a letter is always literal")
        }
    }

    func testTrailingWordExtraction() {
        XCTAssertEqual(TelexInputController.trailingWord("xin chao toan"), "toan")
        XCTAssertEqual(TelexInputController.trailingWord("toan"), "toan")
        XCTAssertEqual(TelexInputController.trailingWord("Đường"), "Đường")
        XCTAssertEqual(TelexInputController.trailingWord("(hoa"), "hoa")
        // Stops at anything that is not a letter — no re-editable tail at all.
        XCTAssertNil(TelexInputController.trailingWord("mp3"))
        XCTAssertNil(TelexInputController.trailingWord("a-b-"))
        XCTAssertNil(TelexInputController.trailingWord("done "))
        XCTAssertNil(TelexInputController.trailingWord(""))
        XCTAssertNil(TelexInputController.trailingWord("x)"))
        // Longer than any syllable → not worth reading (the engine would refuse it).
        XCTAssertNil(TelexInputController.trailingWord("abcdefghijklmnop"))
    }
}

// TAP-path port of the same feature (2026-08-07 field report: worked in TextMate —
// in-place — but not in Google Chrome page content, which the 06/08 axDetect policy
// moved onto the tap). Only the PURE gate is unit-testable here — the AX read-back
// itself needs a live focused element, same limitation as the IMKit version above.
final class ReEditWordTapGateTests: XCTestCase {

    /// Issue #62 (Zalo, 26/08/2026): ⌫ nhanh rồi gõ "s" → seed AX cũ → "asa".
    /// Seed bị cấm trong cooldown sau ⌫ vật lý và khi queue synthetic chưa drain.
    func testNoSeedRightAfterPhysicalDelete() {
        // Trong cooldown 500ms sau ⌫ → đóng gate (chuỗi lỗi của #62).
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: false, queueDrained: true, msSinceDelete: 80))
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: false, queueDrained: true,
            msSinceDelete: TerminalTapController.reEditDeleteCooldownMs - 1))
        // Hết cooldown → mở lại.
        XCTAssertTrue(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: false, queueDrained: true,
            msSinceDelete: TerminalTapController.reEditDeleteCooldownMs))
    }

    func testNoSeedWhileSyntheticQueueInFlight() {
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: false, queueDrained: false, msSinceDelete: .max))
    }

    func testOpensOnlyInBackspaceEmitMode() {
        XCTAssertTrue(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: false))
        // The omnibox/search-bar's inline autocomplete is exactly what re-edit must
        // avoid — .selection and .emptyReset are the per-field browser modes for it.
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .selection,
            lastKeyWasBoundary: false))
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .emptyReset,
            lastKeyWasBoundary: false))
    }

    func testRequiresEmptyEngineEnabledSettingAndDiacriticKey() {
        XCTAssertTrue(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: false))
        // Mid-word (engine not empty): a plain tone edit, not a re-edit — never seed.
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: false, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: false))
        // Feature off.
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: false, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: false))
        // A plain letter never triggers the read-back, same as the IMKit gate.
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: false, emitMode: .backspace,
            lastKeyWasBoundary: false))
    }

    /// Issue #38 (2026-08-12): `git st` in PhpStorm's terminal — the space committed
    /// "git", but JetBrains' laggy AX tree still showed the text WITHOUT the space,
    /// so the tap re-edit seeded "git" across the boundary and the `s` of "st"
    /// became sắc ("gít"). A tone key whose PREVIOUS key was a boundary must never
    /// re-edit, whatever the AX text claims — the keystream can't be stale.
    func testToneKeyRightAfterBoundaryNeverReEdits() {
        XCTAssertFalse(TerminalTapController.reEditGateOpen(
            engineIsEmpty: true, reEditEnabled: true, isDiacriticKey: true, emitMode: .backspace,
            lastKeyWasBoundary: true))
    }
}

// Issue #40 — "tháy" ␣ ⌫ then `a` must give "thấy". The engine keeps the committed
// word (TelexEngine.reopenLastCommit, covered by ReopenTests) but may only put it back
// when the ⌫ is deleting a BOUNDARY CHARACTER: that is true only if the key that ended
// the word left exactly one character behind it. This is the pure half of that rule;
// the read-back that verifies the screen needs a live client/AX tree.
final class ReopenBoundaryKeyTests: XCTestCase {

    func testPrintableAsciiKeysInsertOneCharacter() {
        for s in [" ", ".", ",", "!", "-", "5", "(", "/", "~"] {
            XCTAssertTrue(TelexInputController.insertsOneCharacter(s),
                          "'\(s)' puts one character after the word")
        }
    }

    func testKeysThatInsertNothingOrSomethingElse() {
        // Arrow / function keys arrive as U+F700… — they move the caret, insert nothing.
        for scalar: UInt32 in [0xF700, 0xF701, 0xF702, 0xF703, 0xF729, 0xF72B] {
            XCTAssertFalse(TelexInputController.insertsOneCharacter(String(UnicodeScalar(scalar)!)),
                           "U+\(String(scalar, radix: 16)) is navigation, not text")
        }
        // Control characters (Return/Tab/Esc reach the keycode branch, but iTerm also
        // delivers arrows as 0x1C–0x1F) and DEL.
        for scalar: UInt32 in [0x00, 0x09, 0x0D, 0x1B, 0x1C, 0x1F, 0x7F] {
            XCTAssertFalse(TelexInputController.insertsOneCharacter(String(UnicodeScalar(scalar)!)))
        }
        // Non-ascii text and multi-character strings: not worth reasoning about.
        XCTAssertFalse(TelexInputController.insertsOneCharacter("–"))
        XCTAssertFalse(TelexInputController.insertsOneCharacter("ơ"))
        XCTAssertFalse(TelexInputController.insertsOneCharacter("ab"))
        XCTAssertFalse(TelexInputController.insertsOneCharacter(""))
        XCTAssertFalse(TelexInputController.insertsOneCharacter(nil))
    }
}

// The ⌫ guard: our tracked composition window may only be rewritten while the app's
// caret still agrees with it. Tester report 2026-07-27 (Chrome Web Store search box):
// the first ⌫ ate TWO characters and afterwards nothing typed showed up until a space —
// a React-controlled input had moved/re-rendered under the tracked range.
final class TrackedWindowFreshnessTests: XCTestCase {

    func testFreshWithinTheStaleCaretLagWindowNoSelection() {
        XCTAssertTrue(TelexInputController.trackedWindowIsFresh(caret: 12, selectionLength: 0, expected: 12))
        // A selection (inline autocomplete suffix) would be swallowed by the rewrite.
        XCTAssertFalse(TelexInputController.trackedWindowIsFresh(caret: 12, selectionLength: 3, expected: 12))
        // NỚI 05/08/2026: caret TRỄ trong lag window (Chromium trả selectedRange từ
        // cache một-edit-behind, cùng staleness InPlaceProbe.verdict đã khoan dung) —
        // Discord-web: caret=18 expected=19 ở ⌫ làm guard này drop composition và thả
        // ⌫ native, editor Lexical xóa nguyên text node → "đây" ⌫ 1 phát còn "đ".
        // Caret chỉ là nhân chứng độ tươi; range rewrite lấy từ bookkeeping của mình.
        XCTAssertTrue(TelexInputController.trackedWindowIsFresh(caret: 11, selectionLength: 0, expected: 12))
        XCTAssertTrue(TelexInputController.trackedWindowIsFresh(caret: 8, selectionLength: 0, expected: 12))   // lag 4 = biên
        XCTAssertFalse(TelexInputController.trackedWindowIsFresh(caret: 7, selectionLength: 0, expected: 12))  // quá lag window
        // Caret Ở TRƯỚC (ahead) vẫn là re-render/moved → drop như cũ (lớp Chrome Web
        // Store 2026-07-27: ⌫ đầu ăn 2 ký tự).
        XCTAssertFalse(TelexInputController.trackedWindowIsFresh(caret: 13, selectionLength: 0, expected: 12))
        // No caret at all → never rewrite blind.
        XCTAssertFalse(TelexInputController.trackedWindowIsFresh(caret: nil, selectionLength: 0, expected: 12))
        // Start of a field is a normal, fresh state.
        XCTAssertTrue(TelexInputController.trackedWindowIsFresh(caret: 0, selectionLength: 0, expected: 0))
    }

    /// Issue #37 (Google Docs on Safari): the guard exists for the IN-PLACE
    /// insertText(range) rewrite; marked mode never performs one — its ⌫ goes
    /// engine.backspace() → setMarkedText, correct by the composition session.
    /// Running the guard there dropped the composition on the first mid-word ⌫
    /// (`onLen` never advances in marked mode, so `expected` stayed at the anchor)
    /// and orphaned the underlined word — every later ⌫/space dead until a click.
    func testFreshnessGuardIsInPlaceOnly() {
        XCTAssertTrue(TelexInputController.backspaceFreshnessGuardApplies(marked: false))
        XCTAssertFalse(TelexInputController.backspaceFreshnessGuardApplies(marked: true))
    }
}

// The engine answers `.passthrough` once a word passes its 32-key capacity: from then on
// its raw/composed view is a stale prefix of what the app has on screen, so the KEY must
// be handled by the app, never diffed. Two controller branches used to ignore that:
// a tracked in-place ⌫ rewrote the window (first ⌫ wiped every overflow character, then
// ⌫ went dead for the rest of the word because each rewrite produced identical text), and
// a marked-text app re-set its unchanged prefix while consuming the event (33rd+ letters
// vanished silently). Both are invisible in a log, hence pinned here.
final class EnginePassthroughContractTests: XCTestCase {

    func testTrackedInPlaceBackspaceMustNotRewriteOnOverflow() {
        XCTAssertEqual(
            TelexInputController.passthroughPlan(overflowPassthrough: true, marked: false, isBackspace: true),
            .shrinkWindowAndPassThrough)
    }

    func testMarkedAppCommitsAndLetsTheKeyThroughOnOverflow() {
        // Both directions: the 33rd letter and a ⌫ on an overflowed word.
        XCTAssertEqual(
            TelexInputController.passthroughPlan(overflowPassthrough: true, marked: true, isBackspace: false),
            .commitAndPassThrough)
        XCTAssertEqual(
            TelexInputController.passthroughPlan(overflowPassthrough: true, marked: true, isBackspace: true),
            .commitAndPassThrough)
    }

    func testInPlaceLetterKeepsItsOwnOrderedInsert() {
        // In-place mode already inserts the overflow letter through our insertText
        // channel — it must NOT be diverted (a system passthrough-insert would race
        // our own edits and corrupt words).
        XCTAssertEqual(
            TelexInputController.passthroughPlan(overflowPassthrough: true, marked: false, isBackspace: false),
            .honorEngineAction)
    }

    func testNonPassthroughActionsAreLeftAlone() {
        for marked in [true, false] {
            for backspace in [true, false] {
                XCTAssertEqual(
                    TelexInputController.passthroughPlan(overflowPassthrough: false, marked: marked,
                                                         isBackspace: backspace),
                    .honorEngineAction)
            }
        }
    }

    func testPassthroughDetectionMatchesOnlyThePassthroughCase() {
        XCTAssertTrue(TelexInputController.isPassthrough(.passthrough))
        XCTAssertFalse(TelexInputController.isPassthrough(.none))
        XCTAssertFalse(TelexInputController.isPassthrough(.replace(backspaces: 0, insert: "a")))
        XCTAssertFalse(TelexInputController.isPassthrough(.replace(backspaces: 2, insert: "ế")))
    }

    /// The real overflow trigger, so the tests above stay tied to the engine contract
    /// rather than to an assumption about it. NOTE: `.passthrough` alone is NOT the
    /// overflow signal — ordinary literal letters (the very first "a") also answer
    /// `.passthrough` while being recorded. Overflow = `.passthrough` AND
    /// `engine.isOverflowed` (key NOT recorded, composed frozen).
    func testEngineOverflowContractPastCapacity() {
        var engine = TelexEngine()
        for _ in 0..<32 {
            _ = engine.feed("a")
            XCTAssertFalse(engine.isOverflowed)            // keys 1–32 are recorded
        }
        let frozen = engine.composed
        let a33 = engine.feed("a")                          // 33rd key: NOT recorded
        XCTAssertTrue(TelexInputController.isPassthrough(a33))
        XCTAssertTrue(engine.isOverflowed)
        XCTAssertEqual(engine.composed, frozen)             // stale prefix stays put
        XCTAssertTrue(TelexInputController.isPassthrough(engine.backspace())) // and every ⌫ after
        XCTAssertTrue(engine.isOverflowed)
        XCTAssertTrue(TelexInputController.isPassthrough(engine.backspace()))
    }

    /// A plain first letter answers `.passthrough` too (recorded, composition live) —
    /// it must NOT be treated as overflow, or marked-text composition would be
    /// committed on the first key of every word.
    func testOrdinaryLiteralPassthroughIsNotOverflow() {
        var engine = TelexEngine()
        let a1 = engine.feed("a")
        XCTAssertTrue(TelexInputController.isPassthrough(a1))
        XCTAssertFalse(engine.isOverflowed)
        XCTAssertEqual(engine.composed, "a")                // the key WAS recorded
        XCTAssertEqual(
            TelexInputController.passthroughPlan(
                overflowPassthrough: TelexInputController.isPassthrough(a1) && engine.isOverflowed,
                marked: true, isBackspace: false),
            .honorEngineAction)                              // marked path stays live
    }
}

// Password fields must never be composed into. `IsSecureEventInputEnabled()` only covers
// apps that switch secure input on — a web <input type="password"> does not, and the
// `.emptyReset` strategy's U+202F placeholder then lands in the password as a stray
// character (field report 2026-07-27: "điền password thấy nó inject thêm 1-2 ký tự").
// The AX subrole is the signal; this pins its polarity, because a false POSITIVE would
// silently stop Vietnamese typing everywhere.
final class SecureFieldDetectionTests: XCTestCase {

    func testOnlyTheExplicitPasswordSubroleCounts() {
        XCTAssertTrue(SecureFieldDetector.isSecureSubrole("AXSecureTextField"))
        // Ordinary fields and every "we don't know" answer must read as NOT secure.
        for subrole in ["AXStandardWindow", "AXSearchField", "AXTextField", "", "AXUnknown"] {
            XCTAssertFalse(SecureFieldDetector.isSecureSubrole(subrole), "'\(subrole)' is not a password field")
        }
        XCTAssertFalse(SecureFieldDetector.isSecureSubrole(nil), "no subrole → compose as usual")
    }
}

// Multi-char unicode inserts must be posted one CHARACTER per event: Chromium routes
// a multi-char CGEvent string through a slower path than a plain 1-char keydown, so a
// following event can overtake it in the renderer — web terminal, 2026-08-01:
// "vim test." became "vim t.est" (the boundary "." passed the "est" restore burst).
final class UnicodeInsertChunkingTests: XCTestCase {
    func testSplitsPerCharacter() {
        XCTAssertEqual(SyntheticKeyboard.unicodeInsertChunks("est"), ["e", "s", "t"])
        XCTAssertEqual(SyntheticKeyboard.unicodeInsertChunks("."), ["."])
        XCTAssertEqual(SyntheticKeyboard.unicodeInsertChunks(""), [])
    }
    func testKeepsPrecomposedAndCombiningPairsWhole() {
        XCTAssertEqual(SyntheticKeyboard.unicodeInsertChunks("ệt"), ["ệ", "t"])
        // A decomposed pair (e + combining circumflex + dot below) must stay one chunk —
        // splitting scalars would post an orphan combining mark.
        let decomposed = "e\u{0302}\u{0323}t"
        XCTAssertEqual(SyntheticKeyboard.unicodeInsertChunks(decomposed).count, 2)
    }

    /// End-to-end invariant, not just the pure chunker: every chunk that reaches the
    /// POST SITE is exactly one Character. Pins postUnicode's routing through the
    /// chunker — a future "optimization" that batches the string into one event again
    /// would reintroduce the renderer reorder ("t.est") and turn this red. (The test
    /// host has no event source, so nothing is actually posted — the seam records
    /// sizes before the source guard.)
    func testPostSiteNeverSeesAMultiCharacterChunk() {
        SyntheticKeyboard._testPostUnicode("est")
        XCTAssertEqual(SyntheticKeyboard._testChunkSizes, [1, 1, 1])
        SyntheticKeyboard._testPostUnicode("ệt")
        XCTAssertEqual(SyntheticKeyboard._testChunkSizes, [1, 1])
        SyntheticKeyboard._testPostUnicode("")
        XCTAssertEqual(SyntheticKeyboard._testChunkSizes, [])
    }
}

// A verify probe whose replace was applied by a BOUNDARY key (Return/Enter/Tab/Esc)
// reads a field the app may have already consumed — Enter SENDS the message and the
// composer clears, so the async caret describes the reset field, not our edit.
// Tester log 2026-08-04: every "appended twice → marked" demotion took its deciding
// strike ~1ms after Enter → mọi app phải Enter 2 lần. Boundary probes are log-only.
final class BoundaryProbeDowngradeTests: XCTestCase {
    func testVerifyAtBoundaryBecomesShadow() {
        XCTAssertEqual(TelexInputController.effectiveProbeKind(.verify, boundaryCommit: true), .shadow)
    }
    func testEverythingElseUnchanged() {
        XCTAssertEqual(TelexInputController.effectiveProbeKind(.verify, boundaryCommit: false), .verify)
        XCTAssertEqual(TelexInputController.effectiveProbeKind(.real, boundaryCommit: true), .real)
        XCTAssertEqual(TelexInputController.effectiveProbeKind(.real, boundaryCommit: false), .real)
        XCTAssertEqual(TelexInputController.effectiveProbeKind(.shadow, boundaryCommit: true), .shadow)
    }
}
