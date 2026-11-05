import XCTest
@testable import VietTelex

final class ShortcutImporterTests: XCTestCase {

    private func parse(_ s: String) -> [String: String]? {
        ShortcutImporter.parse(Data(s.utf8))
    }

    func testSemicolonCommentTxtFormat() {
        let txt = """
        ;Bảng gõ tắt xuất từ bộ gõ khác
        vn:Việt Nam
        tphcm:Thành phố Hồ Chí Minh
        đc:được
        camp:campaign
        """
        let d = parse(txt)
        XCTAssertEqual(d?["vn"], "Việt Nam")
        XCTAssertEqual(d?["tphcm"], "Thành phố Hồ Chí Minh")
        XCTAssertEqual(d?["đc"], "được")     // Unicode keys survive
        XCTAssertEqual(d?.count, 4)          // comment line skipped
    }

    func testFlatYaml() {
        let yaml = """
        # bảng gõ tắt
        vn: Việt Nam
        hn: 'Hà Nội'
        hcm: "Hồ Chí Minh"
        """
        let d = parse(yaml)
        XCTAssertEqual(d?["vn"], "Việt Nam")
        XCTAssertEqual(d?["hn"], "Hà Nội")   // quotes stripped
        XCTAssertEqual(d?["hcm"], "Hồ Chí Minh")
    }

    func testJsonParsesAndPlistIsRejected() {
        XCTAssertEqual(parse(#"{"vn": "Việt Nam"}"#)?["vn"], "Việt Nam")
        // plist support was dropped (2026-07-22) — an XML plist has no
        // "key: value" lines, so the line-based pass yields nothing.
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>vn</key><string>Việt Nam</string></dict></plist>
        """
        XCTAssertNil(parse(plist))
    }

    func testValueWithColonsAndJunk() {
        // only the FIRST colon splits — URLs in values survive
        let d = parse("web:https://ptrinh.github.io/viettelex\n:no-key\nnovalue:\nplain line")
        XCTAssertEqual(d?["web"], "https://ptrinh.github.io/viettelex")
        XCTAssertEqual(d?.count, 1)
    }

    func testYamlExportRoundTrips() {
        let table = ["vn": "Việt Nam", "đc": "được", "web": "https://x.vn",
                     "q": "\"quoted\" start", "sp": " lead space"]
        let yaml = ShortcutImporter.exportYAML(table)
        XCTAssertTrue(yaml.hasPrefix("#"))                       // comment header
        let back = ShortcutImporter.parse(Data(yaml.utf8))
        XCTAssertEqual(back?["vn"], "Việt Nam")
        XCTAssertEqual(back?["đc"], "được")
        XCTAssertEqual(back?["web"], "https://x.vn")
        XCTAssertEqual(back?.count, table.count)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("just some prose without any pairs"))
    }

    // Comment cùng dòng KHÔNG bị cắt — đây là chủ đích, không phải bug: giá trị gõ
    // tắt có thể chứa "#" (hashtag, mã màu), nên parser chỉ bỏ dòng BẮT ĐẦU bằng
    // "#"/";"/"//"..  Hệ quả là `id: tap  # chú thích` trong typing-modes.yml cho ra
    // mode "tap  # chú thích" → AppMode(rawValue:) nil → rule bị bỏ im lặng; đúng
    // cách 2 rule Warp mới chết ngày 30/07/2026 (xem header typing-modes.yml, và
    // BundledTypingModesTests khoá phía dữ liệu).
    func testInlineCommentIsNotStripped() {
        let d = parse("""
        # comment riêng dòng: bỏ cả dòng
        vn: Việt Nam  # hashtag phía sau ĐƯỢC giữ
        tag: #hashtag
        """)
        XCTAssertEqual(d?["vn"], "Việt Nam  # hashtag phía sau ĐƯỢC giữ")
        // Giá trị mở đầu bằng "#" vẫn sống (dòng có key nên không bị coi là comment).
        XCTAssertEqual(d?["tag"], "#hashtag")
        XCTAssertEqual(d?.count, 2)
        // Cùng lý do: một rule typing-mode có comment cùng dòng KHÔNG parse ra mode.
        let raw = parse("dev.warp.Warp: tap  # kênh dev")?["dev.warp.Warp"]
        XCTAssertEqual(raw, "tap  # kênh dev")
        XCTAssertNil(AppState.AppMode(rawValue: raw ?? ""))
    }
}
