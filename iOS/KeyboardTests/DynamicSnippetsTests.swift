// Mẫu động có sẵn (tỷ giá/vàng/BTC): migration một lần + phần thuần của đường fetch.
import XCTest

final class DynamicSnippetsTests: XCTestCase {
    private let urls = DynamicSnippets.builtins.map(\.text)

    private func makeDefaults() -> UserDefaults {
        let name = "DynamicSnippetsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // MARK: migration (thuần)

    func testFreshUserUntouched() {
        XCTAssertNil(DynamicSnippets.migrated(nil, alreadyRan: false), "chưa tự chỉnh ⇒ mặc định YAML đã có")
    }

    func testCustomizedUserGetsAllAppended() {
        let mine = [["label": "👋", "text": "Chào"]]
        let out = DynamicSnippets.migrated(mine, alreadyRan: false)
        XCTAssertEqual(out?.first, mine[0])
        XCTAssertEqual(out?.dropFirst().map { $0["text"]! }, urls)
        XCTAssertEqual(out?.dropFirst().map { $0["label"]! }, DynamicSnippets.builtins.map(\.label))
    }

    func testAlreadyHasOneNoDuplicate() {
        let mine = [["label": "vàng", "text": "https://viettelex.com/api/vang"]]
        let out = DynamicSnippets.migrated(mine, alreadyRan: false)!
        XCTAssertEqual(out.filter { $0["text"] == "https://viettelex.com/api/vang" }.count, 1)
        XCTAssertEqual(out[0]["label"], "vàng", "giữ nhãn người dùng đặt")
        XCTAssertEqual(Set(out.map { $0["text"]! }), Set(urls))
    }

    func testAlreadyHasAllNoChange() {
        let mine = DynamicSnippets.builtins.map { ["label": $0.label, "text": $0.text] }
        XCTAssertNil(DynamicSnippets.migrated(mine, alreadyRan: false))
    }

    func testAlreadyRanNoChange() {
        XCTAssertNil(DynamicSnippets.migrated([["label": "", "text": "x"]], alreadyRan: true))
    }

    // MARK: migration (UserDefaults)

    func testRunTwiceIdempotent() {
        let d = makeDefaults()
        d.set([["label": "👋", "text": "Chào"]], forKey: "userTemplates")
        DynamicSnippets.migrateIfNeeded(d)
        DynamicSnippets.migrateIfNeeded(d)
        let list = d.array(forKey: "userTemplates") as! [[String: String]]
        XCTAssertEqual(list.count, 1 + urls.count)
        XCTAssertTrue(d.bool(forKey: DynamicSnippets.migrationKey))
    }

    func testUserDeletedAfterMigrationStaysDeleted() {
        let d = makeDefaults()
        d.set([["label": "👋", "text": "Chào"]], forKey: "userTemplates")
        DynamicSnippets.migrateIfNeeded(d)
        d.set([["label": "👋", "text": "Chào"]], forKey: "userTemplates")   // người dùng xoá cả bốn
        DynamicSnippets.migrateIfNeeded(d)
        XCTAssertEqual((d.array(forKey: "userTemplates") as! [[String: String]]).count, 1)
    }

    func testFreshUserMarkedAndListNotWritten() {
        let d = makeDefaults()
        DynamicSnippets.migrateIfNeeded(d)
        XCTAssertNil(d.object(forKey: "userTemplates"), "không ghi list ⇒ vẫn theo mặc định YAML")
        XCTAssertTrue(d.bool(forKey: DynamicSnippets.migrationKey))
        // Về sau tự chỉnh rồi xoá mẫu động ⇒ không bị thêm lại.
        d.set([["label": "", "text": "x"]], forKey: "userTemplates")
        DynamicSnippets.migrateIfNeeded(d)
        XCTAssertEqual((d.array(forKey: "userTemplates") as! [[String: String]]).count, 1)
    }

    // MARK: fetch body

    func testNon200AndErrorsFallBackToURL() {
        let ok = Data("25.400".utf8)
        XCTAssertEqual(DynamicSnippets.body(data: ok, statusCode: 200), "25.400")
        XCTAssertNil(DynamicSnippets.body(data: ok, statusCode: 404))
        XCTAssertNil(DynamicSnippets.body(data: ok, statusCode: 500))
        XCTAssertNil(DynamicSnippets.body(data: ok, statusCode: nil), "timeout/không có response")
        XCTAssertNil(DynamicSnippets.body(data: nil, statusCode: 200))
        XCTAssertNil(DynamicSnippets.body(data: Data(" \n".utf8), statusCode: 200))
    }

    func testUTF8VietnameseAndDongSign() {
        let s = "USD/VND: 25.430 ₫ — giá vàng SJC: 84,5 triệu đồng/lượng"
        XCTAssertEqual(DynamicSnippets.body(data: Data(("\n" + s + "\n").utf8), statusCode: 200), s)
    }

    func testTruncatesAt1000BytesOnCharBoundary() {
        // 999 byte ASCII + "₫" (3 byte) ⇒ cắt 1000 byte rơi giữa "₫": bỏ hẳn, không "�".
        let s = String(repeating: "a", count: 999) + "₫" + "xyz"
        let out = DynamicSnippets.body(data: Data(s.utf8), statusCode: 200)!
        XCTAssertEqual(out, String(repeating: "a", count: 999))
        XCTAssertFalse(out.contains("\u{FFFD}"))
        // Đúng 1000 byte có dấu: giữ nguyên.
        let v = String(repeating: "đ", count: 500)   // "đ" = 2 byte
        XCTAssertEqual(DynamicSnippets.body(data: Data(v.utf8), statusCode: 200), v)
        // Dài hơn: 1000 byte = 500 chữ "đ".
        let v2 = String(repeating: "đ", count: 600)
        XCTAssertEqual(DynamicSnippets.body(data: Data(v2.utf8), statusCode: 200), v)
        // Ký tự 4 byte (emoji) bị cắt giữa.
        let e = String(repeating: "b", count: 998) + "🟡"
        XCTAssertEqual(DynamicSnippets.body(data: Data(e.utf8), statusCode: 200), String(repeating: "b", count: 998))
    }
}
