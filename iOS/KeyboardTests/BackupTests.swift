// Sao lưu/đồng bộ: khứ hồi JSON, tương thích phiên bản, fixture chung với Android
// (Fixtures/backup-*.json — android/keyboard/.../BackupTests.kt đọc cùng file),
// gộp khi nhập, LWW đồng bộ iCloud (mô phỏng 2 máy + KVS giả).
import XCTest

final class BackupTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: BackupTests.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    /// Kho theme tự tạo trong fixture (chuỗi chuẩn — Android đọc + so cùng chuỗi).
    static let customThemes = ##"{"custom":{"dark":"same","id":"custom","light":{"accent":"#0A84FF","bg":"#EEEEEE","ink":"#000000","key":"#FFFFFF","special":"#DDDDDD"},"name":{"vi":"Thử"},"v":1}}"##

    /// Payload đúng bằng nội dung backup-ios-v1.json.
    static let iosPayload: BackupPayload = {
        var s: [String: SettingValue] = [:]
        for spec in BackupSettings.all where spec.key != "hardwareTelex" {
            if case .bool(let d) = spec.kind { s[spec.key] = .bool(d) }
        }
        s["hapticFeedback"] = .bool(true); s["modernTone"] = .bool(true); s["numberRow"] = .bool(true)
        s["reEditWords"] = .bool(false); s["showSpaceLogo"] = .bool(false); s["swipeTyping"] = .bool(true)
        s["rowHeightAdjust"] = .int(-3); s["autoCorrect"] = .bool(true); s["autoCapitalize"] = .bool(false)
        s["autoSpaceAfterPunct"] = .bool(true); s["suggestInNoSuggestFields"] = .bool(false)
        s["keyboardTransparency"] = .int(40); s["keyLabelTransparency"] = .int(20)
        s["uiLanguage"] = .string("en")
        s["keySound"] = .bool(true); s["keySoundVolume"] = .int(70); s["keySoundStyle"] = .string("wood")
        s[KeyStyleStore.key] = .string(PerThemeKeyStyleTests.golden)   // Tuỳ chỉnh nâng cao theo theme
        s[CustomThemeStore.key] = .string(BackupTests.customThemes)   // Giao diện JSON: theme tự tạo
        return BackupPayload(
            createdAt: iso.date(from: "2026-09-27T08:00:00Z"), platform: "ios", settings: s,
            shortcuts: ["ko": "không", "stk": "số tài khoản", "đc": "được"],
            templates: [BackupTemplate(label: "👋", text: "Chào buổi sáng"),
                        BackupTemplate(label: "", text: "Anh nói \"ok\" nhé\nDòng 2")],
            learnedWords: LearnedWords(uni: ["cảm": 7, "ơn": 6, "nhiều": 4, "viettelex": 5], bi: ["cảm": ["ơn": 5]],
                                       tri: ["cảm\u{1}ơn": ["nhiều": 3]], manual: ["VietTelex"]))
    }()

    // MARK: codec

    func testRoundTrip() throws {
        let p = Self.iosPayload
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(p)), p)
    }

    func testRoundTripWithoutOptionalSections() throws {
        let p = BackupPayload(createdAt: nil, platform: "ios", settings: nil, shortcuts: [:], templates: nil, learnedWords: nil)
        let back = try BackupCodec.decode(BackupCodec.encode(p))
        XCTAssertEqual(back, p)
        XCTAssertNil(back.settings); XCTAssertNil(back.templates); XCTAssertNil(back.learnedWords)
    }

    /// Bộ mã hoá iOS sinh ĐÚNG nội dung fixture (so theo cây JSON) — Android đọc fixture này.
    func testEncoderMatchesSharedFixture() throws {
        let mine = try JSONSerialization.jsonObject(with: BackupCodec.encode(Self.iosPayload)) as? NSDictionary
        let golden = try JSONSerialization.jsonObject(with: fixture("backup-ios-v1")) as? NSDictionary
        XCTAssertEqual(mine, golden)
    }

    func testReadsIOSFixture() throws {
        XCTAssertEqual(try BackupCodec.decode(fixture("backup-ios-v1")), Self.iosPayload)
    }

    /// File Android ghi đọc được trên iOS.
    func testReadsAndroidFixture() throws {
        let p = try BackupCodec.decode(fixture("backup-android-v1"))
        XCTAssertEqual(p.platform, "android")
        XCTAssertEqual(p.settings?["simpleTelex"], .bool(false))
        XCTAssertEqual(p.settings?["quickTelex"], .bool(true))
        XCTAssertEqual(p.settings?["hardwareTelex"], .bool(false))
        XCTAssertEqual(p.settings?["rowHeightAdjust"], .int(4))
        XCTAssertEqual(p.settings?.count, 22)
        XCTAssertEqual(p.settings?[KeyStyleStore.key], .string(PerThemeKeyStyleTests.golden))   // chuỗi chuẩn trùng Android
        XCTAssertEqual(p.settings?["shortcutsEnabled"], .bool(false))
        XCTAssertEqual(p.shortcuts, ["mn": "mọi người", "vn": "Việt Nam"])
        XCTAssertEqual(p.templates, [BackupTemplate(label: "📍", text: "Mình đang trên đường tới"),
                                     BackupTemplate(label: "IP❓", text: "https://api.ipify.org")])
        XCTAssertNil(p.learnedWords)
    }

    /// Bản mới hơn (version 2, minReaderVersion 1): trường/key lạ bỏ qua, sai kiểu bỏ qua, kẹp phạm vi.
    func testForwardCompatibleFile() throws {
        let p = try BackupCodec.decode(fixture("backup-future-v2"))
        XCTAssertEqual(p.settings, ["simpleTelex": .bool(false), "rowHeightAdjust": .int(10)])
        XCTAssertEqual(p.shortcuts, ["hn": "Hà Nội"])
        XCTAssertEqual(p.templates, [BackupTemplate(label: "🙂", text: "Cảm ơn")])
    }

    func testRejectsTooNewAndForeignFiles() throws {
        XCTAssertThrowsError(try BackupCodec.decode(fixture("backup-too-new"))) {
            XCTAssertEqual($0 as? BackupError, .tooNew(7))
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"format\":\"other\"}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notBackup)
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("- \"a | b\"".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notJSON)
        }
    }

    func testBOMAccepted() throws {
        let d = Data([0xEF, 0xBB, 0xBF]) + (try fixture("backup-android-v1"))
        XCTAssertEqual(try BackupCodec.decode(d).platform, "android")
    }

    // MARK: store (UserDefaults thật, suite riêng)

    private func makeStore() -> (BackupStore, URL) {
        let suite = "vt.backup.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = BackupStore(defaults: d, containerURL: dir,
                                defaultTemplates: { [BackupTemplate(label: "👋", text: "Chào buổi sáng")] })
        return (store, dir)
    }

    func testSnapshotDefaultsAndLocalKeyMapping() {
        let (s, _) = makeStore()
        s.defaults.set(false, forKey: "reEditWord")       // tên iOS cục bộ
        s.defaults.set(15, forKey: "rowHeightAdjust")
        let snap = s.snapshot(includeLearned: false)
        XCTAssertEqual(snap.settings?["reEditWords"], .bool(false))
        XCTAssertEqual(snap.settings?["rowHeightAdjust"], .int(10))
        XCTAssertEqual(snap.settings?["simpleTelex"], .bool(true))   // mặc định
        XCTAssertNil(snap.settings?["hardwareTelex"])                // iOS không có
        XCTAssertEqual(snap.templates, [BackupTemplate(label: "👋", text: "Chào buổi sáng")])
        XCTAssertNil(snap.learnedWords)
    }

    /// Công tắc emoji / nút Dán / chọn phím thông minh phải theo bản sao lưu (27/09).
    func testSnapshotIncludesPerfSwitches() throws {
        let (s, _) = makeStore()
        for k in ["emojiSuggest", "pasteButton", "smartTouch", "autoCapitalize"] { s.defaults.set(false, forKey: k) }
        let snap = s.snapshot(includeLearned: false)
        for k in ["emojiSuggest", "pasteButton", "smartTouch", "autoCapitalize"] { XCTAssertEqual(snap.settings?[k], .bool(false), k) }
        let (t, _) = makeStore()
        _ = t.apply(try BackupCodec.decode(BackupCodec.encode(snap)))
        for k in ["emojiSuggest", "pasteButton", "smartTouch", "autoCapitalize"] { XCTAssertEqual(t.defaults.object(forKey: k) as? Bool, false, k) }
    }

    /// Tự sửa từ gõ sai (Thử nghiệm, mặc định TẮT) đi theo sao lưu.
    func testSnapshotIncludesAutoCorrect() throws {
        let (s, _) = makeStore()
        XCTAssertEqual(s.snapshot(includeLearned: false).settings?["autoCorrect"], .bool(false))
        s.defaults.set(true, forKey: "autoCorrect")
        let snap = s.snapshot(includeLearned: false)
        XCTAssertEqual(snap.settings?["autoCorrect"], .bool(true))
        let (t, _) = makeStore()
        _ = t.apply(try BackupCodec.decode(BackupCodec.encode(snap)))
        XCTAssertEqual(t.defaults.object(forKey: "autoCorrect") as? Bool, true)
    }

    /// "Chiều cao thanh gợi ý" (suggestionBarHeight) đi theo sao lưu; mặc định "medium"; lạ ⇒ bỏ qua.
    func testSnapshotIncludesSuggestionBarHeight() throws {
        let (s, _) = makeStore()
        XCTAssertEqual(s.snapshot(includeLearned: false).settings?[SuggestionBarHeight.key], .string("medium"))
        s.defaults.set("high", forKey: SuggestionBarHeight.key)
        let snap = s.snapshot(includeLearned: false)
        XCTAssertEqual(snap.settings?[SuggestionBarHeight.key], .string("high"))
        let (t, _) = makeStore()
        _ = t.apply(try BackupCodec.decode(BackupCodec.encode(snap)))
        XCTAssertEqual(SuggestionBarHeight.load(t.defaults), .high)
        let bad = Data(#"{"format":"viettelex-backup","version":1,"settings":{"suggestionBarHeight":"huge"}}"#.utf8)
        XCTAssertNil(try BackupCodec.decode(bad).settings?[SuggestionBarHeight.key])
    }

    /// "Màu chữ gợi ý" (suggestionInk) đi theo sao lưu; mặc định "muted" (Xám); lạ ⇒ bỏ qua.
    func testSnapshotIncludesSuggestionInk() throws {
        let (s, _) = makeStore()
        XCTAssertEqual(s.snapshot(includeLearned: false).settings?[SuggestionInk.key], .string("muted"))
        s.defaults.set("bright", forKey: SuggestionInk.key)
        let snap = s.snapshot(includeLearned: false)
        XCTAssertEqual(snap.settings?[SuggestionInk.key], .string("bright"))
        let (t, _) = makeStore()
        _ = t.apply(try BackupCodec.decode(BackupCodec.encode(snap)))
        XCTAssertEqual(SuggestionInk.load(t.defaults), .bright)
        let bad = Data(#"{"format":"viettelex-backup","version":1,"settings":{"suggestionInk":"neon"}}"#.utf8)
        XCTAssertNil(try BackupCodec.decode(bad).settings?[SuggestionInk.key])
    }

    /// "Độ nhạy con trỏ" (trackpadSpeed) đi theo sao lưu; mặc định "medium"; lạ ⇒ bỏ qua.
    func testSnapshotIncludesTrackpadSpeed() throws {
        let (s, _) = makeStore()
        XCTAssertEqual(s.snapshot(includeLearned: false).settings?[TrackpadSpeed.key], .string("medium"))
        s.defaults.set("slow", forKey: TrackpadSpeed.key)
        let snap = s.snapshot(includeLearned: false)
        XCTAssertEqual(snap.settings?[TrackpadSpeed.key], .string("slow"))
        let (t, _) = makeStore()
        _ = t.apply(try BackupCodec.decode(BackupCodec.encode(snap)))
        XCTAssertEqual(TrackpadSpeed.load(t.defaults), .slow)
        let bad = Data(#"{"format":"viettelex-backup","version":1,"settings":{"trackpadSpeed":"turbo"}}"#.utf8)
        XCTAssertNil(try BackupCodec.decode(bad).settings?[TrackpadSpeed.key])
    }

    /// Ngôn ngữ giao diện (uiLanguage, kiểu chuỗi) đi theo sao lưu; mặc định "vi";
    /// giá trị lạ bị bỏ qua cả khi nhập file lẫn khi đồng bộ.
    func testUILanguageBackupRoundTrip() throws {
        let (s, _) = makeStore()
        XCTAssertEqual(s.snapshot(includeLearned: false).settings?["uiLanguage"], .string("vi"))
        s.defaults.set("en", forKey: "uiLanguage")
        let snap = s.snapshot(includeLearned: false)
        XCTAssertEqual(snap.settings?["uiLanguage"], .string("en"))
        let (t, _) = makeStore()
        _ = t.apply(try BackupCodec.decode(BackupCodec.encode(snap)))
        XCTAssertEqual(t.defaults.string(forKey: "uiLanguage"), "en")
        XCTAssertEqual(L10n.stored(t.defaults), "en")

        let bad = Data(#"{"format":"viettelex-backup","version":1,"settings":{"uiLanguage":"fr","numberRow":true}}"#.utf8)
        let p = try BackupCodec.decode(bad)
        XCTAssertNil(p.settings?["uiLanguage"])
        XCTAssertEqual(p.settings?["numberRow"], .bool(true))
        XCTAssertEqual(SettingValue.fromSyncString("en", key: "uiLanguage"), .string("en"))
        XCTAssertNil(SettingValue.fromSyncString("fr", key: "uiLanguage"))
        XCTAssertEqual(SettingValue.string("en").syncString, "en")
    }

    func testImportAndroidFileIntoIOSStore() throws {
        let (s, _) = makeStore()
        s.setShortcuts(["mn": "mình", "ko": "không"])
        let msg = s.apply(try BackupCodec.decode(fixture("backup-android-v1")))
        XCTAssertEqual(s.defaults.object(forKey: "simpleTelex") as? Bool, false)
        XCTAssertEqual(s.defaults.object(forKey: "reEditWord") as? Bool, true)
        XCTAssertNil(s.defaults.object(forKey: "hardwareTelex"))
        XCTAssertEqual(s.defaults.integer(forKey: "rowHeightAdjust"), 4)
        XCTAssertEqual(s.shortcuts(), ["mn": "mọi người", "vn": "Việt Nam", "ko": "không"])
        XCTAssertEqual(s.templates().map(\.text),
                       ["Chào buổi sáng", "Mình đang trên đường tới", "https://api.ipify.org"])
        XCTAssertTrue(msg.contains("2 gõ tắt"), msg)
        XCTAssertTrue(msg.contains("2 mẫu câu mới"), msg)
    }

    func testStoreRoundTripAcrossDevices() throws {
        let (a, _) = makeStore(); let (b, _) = makeStore()
        a.defaults.set(true, forKey: "quickTelex"); a.defaults.set(-2, forKey: "rowHeightAdjust")
        a.setShortcuts(["hn": "Hà Nội"])
        a.setTemplates([BackupTemplate(label: "x", text: "một"), BackupTemplate(label: "", text: "hai")])
        a.mergeLearnedWords(LearnedWords(uni: ["việt": 3], bi: ["tiếng": ["việt": 2]], tri: [:]))
        let file = BackupCodec.encode(a.snapshot(includeLearned: true))
        b.apply(try BackupCodec.decode(file))
        XCTAssertEqual(b.settings(), a.settings())
        XCTAssertEqual(b.shortcuts(), a.shortcuts())
        XCTAssertEqual(b.templates().map(\.text), ["Chào buổi sáng", "một", "hai"])
        XCTAssertEqual(b.learnedWords(), a.learnedWords())
    }

    /// Thứ tự gõ tắt "mới nhất trước" (ShortcutOrder) đi qua file sao lưu; file cũ không có mốc vẫn đọc được.
    func testShortcutOrderSurvivesBackup() throws {
        let (a, _) = makeStore(); let (b, _) = makeStore()
        a.setShortcuts(["ko": "không", "mn": "mọi người", "cty": "công ty"])
        a.setShortcutTimes(["mn": 2_000, "ko": 1_000, "gone": 5])
        let p = a.snapshot(includeLearned: false)
        XCTAssertEqual(p.shortcutsAdded, ["mn": 2_000, "ko": 1_000])     // khoá đã xoá không ra file
        let decoded = try BackupCodec.decode(BackupCodec.encode(p))
        XCTAssertEqual(decoded.shortcutsAdded, ["mn": 2_000, "ko": 1_000])
        b.apply(decoded)
        XCTAssertEqual(ShortcutOrder.sorted(b.shortcuts().keys, times: b.shortcutTimes()), ["mn", "ko", "cty"])
        // file không có mục shortcutsAdded (bản cũ / Android cũ) ⇒ nil, nhập vẫn chạy
        var old = p; old.shortcutsAdded = nil
        XCTAssertNil(try BackupCodec.decode(BackupCodec.encode(old)).shortcutsAdded)
    }

    /// iCloud: mục kéo về từ máy khác lên đầu danh sách; mục bị xoá bỏ mốc.
    func testSyncPulledShortcutsGoToTop() {
        let cloud = FakeCloud()
        let (a, _) = makeStore(); let (b, _) = makeStore()
        b.setShortcuts(["aa": "cũ"])
        SyncEngine.run(local: b, cloud: cloud, now: 1000)
        a.setShortcuts(["zz": "mới"])
        SyncEngine.run(local: a, cloud: cloud, now: 2000)
        SyncEngine.run(local: b, cloud: cloud, now: 3000)
        XCTAssertEqual(ShortcutOrder.sorted(b.shortcuts().keys, times: b.shortcutTimes()), ["zz", "aa"])
        a.setShortcuts(["aa": "cũ"])          // A xoá "zz"
        SyncEngine.run(local: a, cloud: cloud, now: 4000)
        SyncEngine.run(local: b, cloud: cloud, now: 5000)
        XCTAssertNil(b.shortcutTimes()["zz"])
    }

    /// Từ thêm tay (Từ điển cá nhân) đi qua sao lưu và KHÔNG mất khi nhập gộp.
    func testManualWordsSurviveBackupImport() throws {
        let (a, _) = makeStore(); let (b, _) = makeStore()
        a.mergeLearnedWords(LearnedWords(uni: ["việt": 3], manual: ["Kubernetes"]))
        b.mergeLearnedWords(LearnedWords(uni: ["nam": 2], manual: ["VietTelex"]))
        b.apply(try BackupCodec.decode(BackupCodec.encode(a.snapshot(includeLearned: true))))
        let lw = b.learnedWords()!
        XCTAssertEqual(Set(lw.manual), ["VietTelex", "Kubernetes"])
        XCTAssertEqual(lw.uni["kubernetes"], 1)
        XCTAssertEqual(lw.uni["nam"], 2)
        // file ghi ra đọc được bằng UserLangModel: từ thêm tay được gợi ý ngay
        let dir = try XCTUnwrap(b.containerURL)
        let m = UserLangModel(fileURL: dir.appendingPathComponent("userlm.plist"), synchronous: true)
        XCTAssertEqual(m.manualCompletions("kube"), ["Kubernetes"])
    }

    func testLearnedWordsMergeTakesMax() {
        let (s, _) = makeStore()
        s.mergeLearnedWords(LearnedWords(uni: ["a": 5, "b": 1], bi: ["a": ["b": 2]], tri: [:]))
        s.mergeLearnedWords(LearnedWords(uni: ["a": 3, "c": 2], bi: ["a": ["b": 4, "c": 1]], tri: [:]))
        XCTAssertEqual(s.learnedWords(),
                       LearnedWords(uni: ["a": 5, "b": 1, "c": 2], bi: ["a": ["b": 4, "c": 1]], tri: [:]))
    }

    /// File ghi ra là store nhị phân của UserLangModel (userlm.bin, VTL2), không còn plist.
    func testLearnedFileLayoutMatchesUserLangModel() throws {
        let (s, dir) = makeStore()
        s.mergeLearnedWords(LearnedWords(uni: ["a": 1], bi: [:], tri: [:]))
        let bin = dir.appendingPathComponent("userlm.bin")
        let data = try Data(contentsOf: bin)
        XCTAssertEqual(Array(data.prefix(4)), Array("VTL2".utf8))
        let d = try XCTUnwrap(UserLMCodec.decode(data))
        XCTAssertEqual(d.tables.uniDict(), ["a": 1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("userlm.plist").path))
    }

    // MARK: LWW merge

    func testMergeIsLastWriterWinsPerKey() {
        let a: SyncDomain = ["x": SyncEntry(v: "1", t: 10), "y": SyncEntry(v: "a", t: 50)]
        let b: SyncDomain = ["x": SyncEntry(v: "2", t: 20), "y": SyncEntry(v: nil, t: 40), "z": SyncEntry(v: "z", t: 1)]
        let m = SyncMerge.merge(a, b)
        XCTAssertEqual(SyncMerge.live(m), ["x": "2", "y": "a", "z": "z"])
        XCTAssertEqual(SyncMerge.merge(b, a), m)                 // giao hoán
        XCTAssertEqual(SyncMerge.merge(m, m), m)                 // luỹ đẳng
    }

    func testTieBreakDeterministic() {
        let a: SyncDomain = ["k": SyncEntry(v: "false", t: 5)]
        let b: SyncDomain = ["k": SyncEntry(v: "true", t: 5)]
        let c: SyncDomain = ["k": SyncEntry(v: nil, t: 5)]
        XCTAssertEqual(SyncMerge.merge(a, b), SyncMerge.merge(b, a))
        XCTAssertEqual(SyncMerge.live(SyncMerge.merge(a, c)), ["k": "false"])   // hoà: giá trị thắng tombstone
    }

    func testStampDetectsEditsAndDeletes() {
        let ledger: SyncDomain = ["a": SyncEntry(v: "1", t: 1), "b": SyncEntry(v: "2", t: 1), "c": SyncEntry(v: nil, t: 1)]
        let st = SyncMerge.stamp(current: ["a": "1", "b": "3", "d": "4"], ledger: ledger, now: 100)
        XCTAssertEqual(st["a"], SyncEntry(v: "1", t: 1))
        XCTAssertEqual(st["b"], SyncEntry(v: "3", t: 100))
        XCTAssertEqual(st["d"], SyncEntry(v: "4", t: 100))
        XCTAssertEqual(st["c"], SyncEntry(v: nil, t: 1))
        let gone = SyncMerge.stamp(current: [:], ledger: ledger, now: 100)
        XCTAssertEqual(gone["a"], SyncEntry(v: nil, t: 100))
    }

    func testFirstSyncRemoteWins() {
        let remote: SyncDomain = ["a": SyncEntry(v: "cloud", t: 5), "gone": SyncEntry(v: nil, t: 5)]
        let st = SyncMerge.stamp(current: ["a": "local", "gone": "x", "new": "n"], ledger: nil, remote: remote, now: 100)
        XCTAssertEqual(SyncMerge.live(SyncMerge.merge(st, remote)), ["a": "cloud", "new": "n"])
    }

    func testTombstonePruning() {
        let d: SyncDomain = ["old": SyncEntry(v: nil, t: 0), "new": SyncEntry(v: nil, t: SyncMerge.tombstoneTTL), "v": SyncEntry(v: "1", t: 0)]
        XCTAssertEqual(Set(SyncMerge.pruned(d, now: SyncMerge.tombstoneTTL + 1).keys), ["new", "v"])
    }

    func testDomainCodecRoundTrip() {
        let d: SyncDomain = ["a": SyncEntry(v: "1", t: 1_727_000_000_000), "b": SyncEntry(v: nil, t: 3), "ư\u{1}": SyncEntry(v: "", t: 0)]
        XCTAssertEqual(SyncMerge.decode(SyncMerge.encode(d)), d)
        XCTAssertNil(SyncMerge.decode(Data("nope".utf8)))
    }

    func testTemplatesDomainKeepsOrderAndLabels() {
        let items = [BackupTemplate(label: "b", text: "zz"), BackupTemplate(label: "", text: "aa"),
                     BackupTemplate(label: "x\u{1}y", text: "mm")]
        XCTAssertEqual(SyncMerge.templatesFromDomain(SyncMerge.templatesToDomain(items)), items)
    }

    // MARK: mô phỏng 2 máy + iCloud

    final class FakeCloud: SyncCloud {
        var store: [String: Data] = [:]
        func data(forKey key: String) -> Data? { store[key] }
        func set(_ data: Data, forKey key: String) { store[key] = data }
    }

    func testTwoDeviceSync() {
        let cloud = FakeCloud()
        let (a, _) = makeStore(); let (b, _) = makeStore()
        // A có dữ liệu, bật đồng bộ trước.
        a.defaults.set(true, forKey: "quickTelex")
        a.setShortcuts(["ko": "không"])
        a.setTemplates([BackupTemplate(label: "1", text: "một")])
        SyncEngine.run(local: a, cloud: cloud, now: 1000)
        // B máy mới (mặc định): lần đầu ⇒ nhận của A, không đè mặc định lên.
        b.setShortcuts(["mn": "mọi người"])
        SyncEngine.run(local: b, cloud: cloud, now: 2000)
        XCTAssertEqual(b.defaults.object(forKey: "quickTelex") as? Bool, true)
        XCTAssertEqual(b.shortcuts(), ["ko": "không", "mn": "mọi người"])
        XCTAssertEqual(b.templates().map(\.text), ["một"])
        // A kéo về phần B thêm.
        SyncEngine.run(local: a, cloud: cloud, now: 3000)
        XCTAssertEqual(a.shortcuts(), ["ko": "không", "mn": "mọi người"])

        // Sửa đồng thời mục KHÁC nhau ⇒ giữ cả hai; CÙNG mục ⇒ bản sau thắng; xoá lan truyền.
        a.defaults.set(false, forKey: "simpleTelex")
        a.setShortcuts(["ko": "hông", "mn": "mọi người"])
        b.defaults.set(true, forKey: "teencode")
        b.setShortcuts(["ko": "khum"])                   // xoá "mn", sửa "ko"
        SyncEngine.run(local: a, cloud: cloud, now: 4000)
        SyncEngine.run(local: b, cloud: cloud, now: 5000)
        SyncEngine.run(local: a, cloud: cloud, now: 6000)
        for s in [a, b] {
            XCTAssertEqual(s.defaults.object(forKey: "simpleTelex") as? Bool, false)
            XCTAssertEqual(s.defaults.object(forKey: "teencode") as? Bool, true)
            XCTAssertEqual(s.shortcuts(), ["ko": "khum"])
        }
        // Lượt lặp không đổi gì.
        XCTAssertEqual(SyncEngine.run(local: a, cloud: cloud, now: 7000), SyncEngine.Result())
    }

    func testChangesWhileSyncOffWinAfterReenable() {
        let cloud = FakeCloud()
        let (a, _) = makeStore(); let (b, _) = makeStore()
        SyncEngine.run(local: a, cloud: cloud, now: 1000)
        SyncEngine.run(local: b, cloud: cloud, now: 1100)
        // B tắt đồng bộ, đổi cài đặt; A đổi mục khác cùng lúc.
        b.defaults.set(true, forKey: "modernTone")
        a.defaults.set(true, forKey: "hapticFeedback")
        SyncEngine.run(local: a, cloud: cloud, now: 2000)
        // B bật lại (sổ vẫn còn) ⇒ thay đổi của B đóng dấu mới, không mất.
        SyncEngine.run(local: b, cloud: cloud, now: 3000)
        XCTAssertEqual(b.defaults.object(forKey: "modernTone") as? Bool, true)
        XCTAssertEqual(b.defaults.object(forKey: "hapticFeedback") as? Bool, true)
    }
}
