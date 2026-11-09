// keyprior.bin (trie chọn phím thông minh dựng sẵn, CHUNG Android) ≡ trie dựng trong RAM từ lexicon.
// Song sinh android/keyboard/src/test/kotlin/com/viettelex/keyboard/KeyPriorBlobTests.kt.
// Sinh lại asset (đổi vnlexicon / enlexicon / seed / TelexSpell): chạy lệnh trong docstring Kotlin rồi
// chép android/app/src/main/assets/keyprior.bin → iOS/Keyboard/Resources/keyprior.bin.
import XCTest
import TelexCore

final class KeyPriorBlobTests: XCTestCase {
    private static let ref = TelexKeyPrior.fromLexicon()

    private func assetData() throws -> NSData {
        let url = try XCTUnwrap(TelexKeyPrior.assetURL, "thiếu keyprior.bin trong bundle (project.yml)")
        return try NSData(contentsOf: url, options: .alwaysMapped)
    }

    /// Bản chép ở iOS trùng từng byte bản Android (nguồn sự thật — test parity Kotlin chốt bản đó ≡ dữ liệu).
    func testBundledAssetEqualsAndroidAsset() throws {
        let android = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../android/app/src/main/assets/keyprior.bin").standardized
        guard FileManager.default.fileExists(atPath: android.path) else { throw XCTSkip("không thấy repo Android") }
        XCTAssertEqual(try Data(contentsOf: android), try assetData() as Data,
                       "iOS/Keyboard/Resources/keyprior.bin lệch bản Android — chép lại")
    }

    /// Duyệt đủ mọi nút của hai trie cùng lúc: cùng con, cùng trọng số (sai số cộng float — thứ tự cộng
    /// từ chat của Swift sắp theo chữ, Kotlin theo tệp seed).
    func testMappedTrieMatchesLexiconBuild() throws {
        let m = try XCTUnwrap(KeyTrie.mapped(try assetData()))
        XCTAssertTrue(m.isMapped)
        let a = Self.ref.trie
        XCTAssertEqual(a.nodeCount, m.nodeCount)
        var stack = [(0, 0)], seen = 0, exact = 0
        while let top = stack.popLast() {
            let (na, nm) = top
            seen += 1
            let wa = a.weight(na), wm = m.weight(nm)
            if wa.bitPattern == wm.bitPattern { exact += 1 }
            XCTAssertEqual(wa, wm, accuracy: max(abs(wa), 1e-30) * 1e-5)
            for k in 0..<26 {
                let ca = a.child(na, k), cm = m.child(nm, k)
                XCTAssertEqual(ca < 0, cm < 0, "nút \(na) phím \(k)")
                if ca >= 0, cm >= 0 { stack.append((ca, cm)) }
            }
        }
        XCTAssertEqual(seen, a.nodeCount)
        print("KEYPRIOR iOS: \(seen) nút, trọng số trùng bit \(exact)/\(seen)")
    }

    func testAssetPriorsMatchAndWarmUpUsesAsset() throws {
        let asset = try XCTUnwrap(TelexKeyPrior.fromAsset(), "bàn phím phải mở asset (không dựng trong RAM)")
        XCTAssertTrue(asset.trie.isMapped)
        for raw in ["", "t", "th", "ng", "ngh", "tie", "dd", "hel", "k", "uwow", "truwowngf", "qqq",
                    String(repeating: "a", count: 13)] {
            let p = Self.ref.forRaw(raw), q = asset.forRaw(raw)
            XCTAssertEqual(p == nil, q == nil, raw)
            guard let p, let q else { continue }
            for c in "abcdefghijklmnopqrstuvwxyz.1" {
                let x = p(c), y = q(c)
                XCTAssertEqual(x == nil, y == nil, "\(raw)→\(c)")
                if let x, let y { XCTAssertEqual(x, y, accuracy: max(x, 1e-30) * 1e-4, "\(raw)→\(c)") }
            }
        }
        // Số chốt Kotlin (TouchTargetTests.testParityWithKotlin) qua đường asset.
        XCTAssertEqual(asset.trie.nodeCount, 63341)
        XCTAssertEqual(try XCTUnwrap(asset.forRaw("th")?("a")), 0.25838506, accuracy: 0.25838506 * 1e-3)
        XCTAssertTrue(TelexKeyPrior.warmUp().trie.isMapped, "warmUp mở asset mmap")
    }

    func testRejectsBadBlob() throws {
        XCTAssertNil(KeyTrie.mapped(NSData(data: Data(count: 64))))
        let good = try assetData() as Data
        var v = good; v[4] = 9
        XCTAssertNil(KeyTrie.mapped(NSData(data: v)), "sai phiên bản")
        XCTAssertNil(KeyTrie.mapped(NSData(data: good.prefix(1000))), "cụt")
        // Tham số khác mặc định ⇒ fromAsset từ chối (warmUp dựng từ lexicon).
        var lam = good; lam.replaceSubrange(20..<24, with: withUnsafeBytes(of: Float(0.07).bitPattern.littleEndian) { Data($0) })
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("keyprior-\(UUID()).bin")
        try lam.write(to: tmp); defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertNil(TelexKeyPrior.fromAsset(tmp))
        XCTAssertNil(TelexKeyPrior.fromAsset(nil))
    }

    /// RAM (heap giữ lại khi trie còn sống) + thời gian: dựng trong RAM (cũ) vs asset mmap (mới).
    /// In "KEYPRIOR RAM …". Asset: heap gần 0 (trang map sạch — jetsam không tính).
    func testRamAssetVsLexicon() throws {
        RamBreakdownTests.spin(0.2)
        var h0 = RamBreakdownTests.heapBytes(), f0 = KeyboardBenchTests.footprintMB()
        var t = CFAbsoluteTimeGetCurrent()
        var asset: TelexKeyPrior? = TelexKeyPrior.fromAsset()
        _ = asset?.forRaw("tie")?("e")
        let assetMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        let assetHeap = RamBreakdownTests.heapBytes() - h0, assetFoot = KeyboardBenchTests.footprintMB() - f0

        h0 = RamBreakdownTests.heapBytes(); f0 = KeyboardBenchTests.footprintMB()
        t = CFAbsoluteTimeGetCurrent()
        var built: TelexKeyPrior? = autoreleasepool { TelexKeyPrior.fromLexicon() }
        let builtMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        let builtHeap = RamBreakdownTests.heapBytes() - h0, builtFoot = KeyboardBenchTests.footprintMB() - f0
        print(String(format: "KEYPRIOR RAM iOS: asset mmap heap %+.1f KB foot %+.2f MB %.2f ms | dựng từ lexicon heap %+.1f KB foot %+.2f MB %.0f ms (%d nút)",
                     Double(assetHeap) / 1024, assetFoot, assetMs, Double(builtHeap) / 1024, builtFoot, builtMs,
                     built?.trie.nodeCount ?? 0))
        XCTAssertLessThan(assetHeap, 64 * 1024, "asset mmap không được chép vào heap")
        XCTAssertGreaterThan(builtHeap, assetHeap)
        asset = nil; built = nil
    }
}
