// ICloudSyncTests — đồng bộ iCloud phía macOS: cùng key/định dạng KVS với iOS, map tên
// setting chuẩn, KHÔNG đụng nhóm mẫu câu, KHÔNG xoá setting chỉ iPhone có, tắt/thiếu
// entitlement = no-op.
import XCTest
@testable import VietTelex

private final class FakeCloud: SyncCloud {
    var store: [String: Data] = [:]
    var writes = 0
    func data(forKey key: String) -> Data? { store[key] }
    func set(_ data: Data, forKey key: String) { store[key] = data; writes += 1 }
}

/// Máy Mac giả: setting theo key macOS + bảng gõ tắt, sổ cái trong suite riêng.
private final class FakeMac {
    var settings: [String: Bool] = [:]
    var shortcuts: [String: String] = [:]
    var translateTarget = "en"
    let defaults: UserDefaults
    let suite = "vt.test.sync.\(UUID().uuidString)"
    init() { defaults = UserDefaults(suiteName: suite)! }
    deinit { defaults.removePersistentDomain(forName: suite) }
    lazy var store = MacSyncStore(ledgerDefaults: defaults,
                                  getSetting: { [unowned self] in self.settings[$0] ?? false },
                                  setSetting: { [unowned self] in self.settings[$0] = $1 },
                                  getShortcuts: { [unowned self] in self.shortcuts },
                                  setShortcuts: { [unowned self] in self.shortcuts = $0 },
                                  getText: { [unowned self] in $0 == "translateTarget" ? self.translateTarget : nil },
                                  setText: { [unowned self] in if $0 == "translateTarget" { self.translateTarget = $1 } })
    func sync(_ cloud: FakeCloud, now: Int64) {
        SyncEngine.run(local: store, cloud: cloud, now: now, sections: ICloudSync.sections)
    }
}

final class ICloudSyncTests: XCTestCase {
    private func domain(_ cloud: FakeCloud, _ s: SyncSection) -> SyncDomain {
        SyncMerge.decode(cloud.store[s.cloudKey]) ?? [:]
    }

    func testPushesCanonicalKeysSameFormatAsIOS() {
        let cloud = FakeCloud(), mac = FakeMac()
        mac.settings = ["modernOrthography": true, "simpleTelex": false]
        mac.shortcuts = ["ko": "không"]
        mac.sync(cloud, now: 1000)
        XCTAssertEqual(Set(cloud.store.keys), ["vt.sync.settings", "vt.sync.shortcuts"])
        let s = domain(cloud, .settings)
        XCTAssertEqual(s["modernTone"], SyncEntry(v: "true", t: 1000))   // tên chuẩn, không phải modernOrthography
        XCTAssertNil(s["modernOrthography"])
        XCTAssertEqual(s["simpleTelex"]?.v, "false")
        XCTAssertEqual(Set(s.keys), MacSyncStore.managed.union(MacSyncStore.textSettings.map(\.canonical)))
        XCTAssertEqual(s["translateTarget"]?.v, "en")
        XCTAssertEqual(domain(cloud, .shortcuts)["ko"], SyncEntry(v: "không", t: 1000))
    }

    func testTemplatesAreNeverTouched() {
        let cloud = FakeCloud(), mac = FakeMac()
        let templates = SyncMerge.encode(["Chào": SyncEntry(v: "000000\u{1}👋", t: 5)])
        cloud.store[SyncSection.templates.cloudKey] = templates
        mac.sync(cloud, now: 1000)
        mac.sync(cloud, now: 2000)
        XCTAssertEqual(cloud.store[SyncSection.templates.cloudKey], templates)
        XCTAssertNil(mac.defaults.data(forKey: MacSyncStore.ledgerKey(.templates)))
    }

    /// Setting chỉ iPhone có (thanh gợi ý…) sống sót qua nhiều lượt đồng bộ từ Mac,
    /// không bị đóng dấu xoá và không bị đóng dấu lại (không ping-pong).
    func testForeignSettingsSurviveUnchanged() {
        let cloud = FakeCloud(), mac = FakeMac()
        cloud.store[SyncSection.settings.cloudKey] = SyncMerge.encode([
            "showSuggestions": SyncEntry(v: "false", t: 10),
            "simpleTelex": SyncEntry(v: "true", t: 10),
        ])
        mac.sync(cloud, now: 1000)
        mac.sync(cloud, now: 2000)
        mac.sync(cloud, now: 3000)
        let s = domain(cloud, .settings)
        XCTAssertEqual(s["showSuggestions"], SyncEntry(v: "false", t: 10))
        XCTAssertEqual(s["simpleTelex"], SyncEntry(v: "true", t: 10))
        let writes = cloud.writes
        mac.sync(cloud, now: 4000)
        XCTAssertEqual(cloud.writes, writes, "lượt không có thay đổi không được ghi iCloud")
    }

    /// Lần đầu (sổ trống): giá trị iCloud đã có thắng mặc định của Mac; sau đó sửa trên
    /// Mac thắng bản cũ trên iCloud; iPhone sửa sau thì Mac nhận.
    func testFirstSyncCloudWinsThenLastWriterWins() {
        let cloud = FakeCloud(), mac = FakeMac()
        mac.settings = ["simpleTelex": false, "quickTelex": false]
        mac.shortcuts = ["mac": "chỉ Mac có"]
        cloud.store[SyncSection.settings.cloudKey] = SyncMerge.encode(["simpleTelex": SyncEntry(v: "true", t: 10)])
        cloud.store[SyncSection.shortcuts.cloudKey] = SyncMerge.encode(["ip": SyncEntry(v: "iPhone", t: 10)])
        mac.sync(cloud, now: 1000)
        XCTAssertEqual(mac.settings["simpleTelex"], true)
        XCTAssertEqual(mac.shortcuts, ["mac": "chỉ Mac có", "ip": "iPhone"])

        mac.settings["quickTelex"] = true
        mac.shortcuts["ip"] = nil
        mac.sync(cloud, now: 2000)
        XCTAssertEqual(domain(cloud, .settings)["quickTelex"], SyncEntry(v: "true", t: 2000))
        XCTAssertEqual(domain(cloud, .shortcuts)["ip"], SyncEntry(v: nil, t: 2000))   // tombstone

        var s = domain(cloud, .settings)
        s["quickTelex"] = SyncEntry(v: "false", t: 3000)          // iPhone sửa sau
        cloud.store[SyncSection.settings.cloudKey] = SyncMerge.encode(s)
        mac.sync(cloud, now: 3500)
        XCTAssertEqual(mac.settings["quickTelex"], false)
    }

    /// "Sửa dấu từ đã gõ": macOS nay có công tắc ⇒ đồng bộ cả hai chiều dưới tên chuẩn
    /// `reEditWords` (iOS BackupFormat / Android), key macOS là `reEditWord`.
    func testReEditWordsSyncsBothWays() {
        XCTAssertTrue(MacSyncStore.settings.contains { $0.canonical == "reEditWords" && $0.local == "reEditWord" })
        let cloud = FakeCloud(), mac = FakeMac()
        mac.settings = ["reEditWord": false]
        mac.sync(cloud, now: 1000)
        XCTAssertEqual(domain(cloud, .settings)["reEditWords"], SyncEntry(v: "false", t: 1000), "Mac → iCloud")
        XCTAssertNil(domain(cloud, .settings)["reEditWord"])

        var s = domain(cloud, .settings)
        s["reEditWords"] = SyncEntry(v: "true", t: 3000)          // iPhone bật lại sau
        cloud.store[SyncSection.settings.cloudKey] = SyncMerge.encode(s)
        mac.sync(cloud, now: 3500)
        XCTAssertEqual(mac.settings["reEditWord"], true, "iCloud → Mac")
    }

    func testMalformedCloudValueIgnored() {
        let cloud = FakeCloud(), mac = FakeMac()
        mac.settings = ["teencode": true]
        cloud.store[SyncSection.settings.cloudKey] = SyncMerge.encode(["teencode": SyncEntry(v: "maybe", t: 10)])
        mac.sync(cloud, now: 1000)
        XCTAssertEqual(mac.settings["teencode"], true)
    }

    /// Ngôn ngữ đích của Dịch: chuỗi, cùng key với iOS; giá trị lạ / tiếng Việt từ iCloud bị bỏ.
    func testTranslateTargetSyncsAsString() {
        let cloud = FakeCloud(), mac = FakeMac()
        mac.translateTarget = "ja"
        mac.sync(cloud, now: 1000)
        XCTAssertEqual(domain(cloud, .settings)["translateTarget"]?.v, "ja")

        cloud.store[SyncSection.settings.cloudKey] = SyncMerge.encode(["translateTarget": SyncEntry(v: "zh-TW", t: 5000)])
        mac.sync(cloud, now: 6000)
        XCTAssertEqual(mac.translateTarget, "zh-TW")

        for bad in ["vi", "xx"] {
            cloud.store[SyncSection.settings.cloudKey] = SyncMerge.encode(["translateTarget": SyncEntry(v: bad, t: 9000)])
            mac.sync(cloud, now: 10000)
            XCTAssertEqual(mac.translateTarget, "zh-TW", bad)
        }
    }

    /// AppState map đủ mọi key macOS trong bảng (thiếu một key = setting đó không bao giờ đồng bộ).
    func testAppStateMapsEverySyncedKey() {
        for m in MacSyncStore.settings {
            XCTAssertNotNil(AppState.shared.syncedSetting(m.local), m.local)
        }
        XCTAssertNil(AppState.shared.syncedSetting("vniMode"))
    }

    /// Bản test (ký ad-hoc, không entitlement): bật công tắc vẫn là no-op, không chạm KVS.
    func testWithoutEntitlementEverythingIsNoOp() {
        XCTAssertFalse(ICloudSync.hasEntitlement)
        let suite = "vt.test.icloud.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let sync = ICloudSync(defaults: d)
        sync.setEnabled(true)
        XCTAssertFalse(sync.isEnabled)
        sync.syncNow()
        XCTAssertNil(sync.lastSync)
    }
}
