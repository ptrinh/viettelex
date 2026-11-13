import XCTest

/// Chip tách số (STK/SĐT/OTP) — vector dùng chung với Android ClipDetectTests.
final class ClipDetectTests: XCTestCase {
    private func kinds(_ s: String) -> [String] {
        ClipDetect.detect(s).map { c in
            switch c.kind {
            case .otp: return "otp:\(c.value)"
            case .phone: return "phone:\(c.value)"
            case .account: return "stk:\(c.value)"
            }
        }
    }

    func testBankBalanceSMS() {
        XCTAssertEqual(kinds("Vietcombank: TK 1234567890 +500,000VND luc 12:30 27/09/2026. SD 1,234,567VND. ND: chuyen tien"),
                       ["stk:1234567890"])
    }
    func testBankSMSWithDiacritics() {
        XCTAssertEqual(kinds("TPBank: TK 0123 4567 890 giảm 150.000 VND lúc 08:15 26/09. Số dư 2.345.000 VND"),
                       ["stk:01234567890"])
    }
    func testOTPVietnamese() {
        XCTAssertEqual(kinds("Ma OTP cua quy khach la 482913. Khong chia se ma nay cho bat ky ai"), ["otp:482913"])
        XCTAssertEqual(kinds("Mã xác thực giao dịch của Quý khách là 739104, hiệu lực 3 phút."), ["otp:739104"])
        XCTAssertEqual(kinds("MB: Ma xac nhan 5521 de dang nhap. Het han sau 60s"), ["otp:5521"])
    }
    func testOTPEnglish() {
        XCTAssertEqual(kinds("Your verification code is 5821"), ["otp:5821"])
        XCTAssertEqual(kinds("G-438210 is your Google verification code."), ["otp:438210"])
        XCTAssertEqual(kinds("The temporary code you requested to sign-in is 651305. Please don't share this code with anyone."), ["otp:651305"])
        XCTAssertEqual(kinds("123123 là OTP là bạn"), ["otp:123123"])   // mã đứng TRƯỚC từ khoá
    }
    func testBareOTP() {
        XCTAssertEqual(kinds("123456"), ["otp:123456"])
        XCTAssertEqual(kinds(" 8812 "), ["otp:8812"])
    }
    func testPhones() {
        XCTAssertEqual(kinds("0912 345 678"), ["phone:0912345678"])
        XCTAssertEqual(kinds("+84 912 345 678"), ["phone:0912345678"])
        XCTAssertEqual(kinds("Liên hệ anh Nam 0987.654.321 nhé"), ["phone:0987654321"])
        XCTAssertEqual(kinds("SĐT: 090-123-4567"), ["phone:0901234567"])
        XCTAssertEqual(kinds("028 3823 4567"), ["phone:02838234567"])
        XCTAssertEqual(kinds("84912345678"), ["phone:0912345678"])
    }
    func testAccounts() {
        XCTAssertEqual(kinds("STK: 0071 0001 23456 Vietcombank"), ["stk:0071000123456"])
        XCTAssertEqual(kinds("Số tài khoản 19036789012345 Techcombank - Nguyen Van A"), ["stk:19036789012345"])
        XCTAssertEqual(kinds("0123456789"), ["stk:0123456789"])
        XCTAssertEqual(kinds("Chuyển khoản vào tk 123456 MB giúp em"), ["stk:123456"])
    }
    func testPhoneAndAccountTogether() {
        XCTAssertEqual(kinds("STK 1903 6789 0123 45, SĐT 0912345678 (chị Lan)"),
                       ["phone:0912345678", "stk:19036789012345"])
    }
    func testNoChip() {
        XCTAssertEqual(kinds("Chuyển 500000 đ"), [])
        XCTAssertEqual(kinds("hẹn 12:30 ngày 27/09"), [])
        XCTAssertEqual(kinds("abc"), [])
        XCTAssertEqual(kinds("Mã giao dịch: thanh toán 50000 VND thành công"), [])   // số tiền ≠ OTP
        XCTAssertEqual(kinds("Giá 1,250,000 VND"), [])
        XCTAssertEqual(kinds("Năm 2026 có 365 ngày"), [])
        XCTAssertEqual(kinds(String(repeating: "1234567890 ", count: 60)), [])   // quá dài
    }
    func testLabels() {
        let c = ClipDetect.detect("STK: 0071000123456")
        XCTAssertEqual(c.first?.label, "Dán STK 0071…")
        XCTAssertEqual(ClipDetect.detect("0912345678").first?.label, "Dán SĐT 0912…")
        XCTAssertEqual(ClipDetect.detect("482913").first?.label, "Dán OTP 482913")
    }
}

final class ClipSensitivityTests: XCTestCase {
    func testSecrets() {
        XCTAssertTrue(ClipSensitivity.looksSecret("Xk9#mP2qL"))
        XCTAssertTrue(ClipSensitivity.looksSecret("sk_live_4eC39HqLyjWDarjtT1zdp7dc"))
        XCTAssertTrue(ClipSensitivity.looksSecret("482913"))
        XCTAssertTrue(ClipSensitivity.looksSecret("Ma OTP cua quy khach la 482913"))
    }
    func testNotSecrets() {
        XCTAssertFalse(ClipSensitivity.looksSecret("https://example.com/a1b2c3d4e5f6g7h8"))
        XCTAssertFalse(ClipSensitivity.looksSecret("xin chao ban"))
        XCTAssertFalse(ClipSensitivity.looksSecret("1234567890123"))
        XCTAssertFalse(ClipSensitivity.looksSecret("someone@example.com"))
        XCTAssertFalse(ClipSensitivity.looksSecret("Hôm nay trời đẹp quá"))
    }
}

final class ClipboardHistoryTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cliptest-\(UUID().uuidString).json")
    }

    func testTTLAndPin() {
        let h = ClipboardHistory(fileURL: nil)
        h.add("hello", now: 0)
        h.add("pinned me", now: 0)
        h.togglePin("pinned me")
        XCTAssertEqual(h.items(now: 3599).map(\.text), ["pinned me", "hello"])
        XCTAssertEqual(h.items(now: 3601).map(\.text), ["pinned me"])
        XCTAssertEqual(h.items(now: 1_000_000).map(\.text), ["pinned me"])   // ghim không hết hạn
    }

    func testSensitiveExpiresEarly() {
        let h = ClipboardHistory(fileURL: nil)
        h.add("Xk9#mP2qL", now: 0)
        h.add("bình thường", now: 0)
        XCTAssertEqual(h.items(now: 119).count, 2)
        XCTAssertEqual(h.items(now: 121).map(\.text), ["bình thường"])
    }

    func testDedupeMovesToTopKeepsPin() {
        let h = ClipboardHistory(fileURL: nil)
        h.add("a", now: 0); h.add("b", now: 1)
        h.togglePin("a")
        h.add("a", now: 2)
        XCTAssertEqual(h.raw.map(\.text), ["a", "b"])
        XCTAssertTrue(h.raw[0].pinned)
        XCTAssertEqual(h.raw[0].at, 2)
    }

    func testCapEvictsOldestUnpinned() {
        let h = ClipboardHistory(fileURL: nil)
        h.add("keep", now: 0); h.togglePin("keep")
        for i in 0..<25 { h.add("item \(i)", now: TimeInterval(i + 1)) }
        XCTAssertEqual(h.raw.count, 20)
        XCTAssertTrue(h.raw.contains { $0.text == "keep" })
        XCTAssertFalse(h.raw.contains { $0.text == "item 0" })
        XCTAssertTrue(h.raw.contains { $0.text == "item 24" })
    }

    func testRejectsEmptyAndHuge() {
        let h = ClipboardHistory(fileURL: nil)
        XCTAssertFalse(h.add("   \n", now: 0))
        XCTAssertFalse(h.add(String(repeating: "x", count: ClipboardHistory.maxTextLength + 1), now: 0))
        XCTAssertTrue(h.raw.isEmpty)
        // Văn bản nhiều đoạn cỡ vài nghìn ký tự (trước: > 4000 bị bỏ lặng lẽ) phải được lưu.
        let long = Array(repeating: String(repeating: "Đoạn văn khá dài. ", count: 30), count: 12)
            .joined(separator: "\n\n")
        XCTAssertGreaterThan(long.count, 4000)
        XCTAssertTrue(h.add(long, now: 0))
        XCTAssertEqual(h.raw.first?.text, long)
    }

    func testClearKeepsPinned() {
        let h = ClipboardHistory(fileURL: nil)
        h.add("a", now: 0); h.add("b", now: 0); h.togglePin("b")
        h.clearUnpinned()
        XCTAssertEqual(h.raw.map(\.text), ["b"])
        h.remove("b")
        XCTAssertTrue(h.raw.isEmpty)
    }

    func testPersistRoundTrip() {
        let u = tempURL()
        defer { try? FileManager.default.removeItem(at: u) }
        let h = ClipboardHistory(fileURL: u)
        h.add("dòng 1\ndòng 2\tcó tab", now: 10)
        h.add("ghim", now: 11); h.togglePin("ghim")
        h.save()
        let h2 = ClipboardHistory(fileURL: u)
        XCTAssertEqual(h2.raw, h.raw)
        h2.removeAll(); h2.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: u.path))   // rỗng → xoá file
    }

    func testLatestFresh() {
        let h = ClipboardHistory(fileURL: nil)
        XCTAssertNil(h.latestFresh(now: 0))
        h.add("x", now: 100)
        XCTAssertEqual(h.latestFresh(now: 280)?.text, "x")
        XCTAssertNil(h.latestFresh(now: 281))
    }
}

/// Luồng: công tắc lịch sử / ẩn danh / ô mật khẩu / tự đọc / chip.
final class ClipboardFeatureTests: XCTestCase {
    private var url: URL!
    private var savedPaywall = false
    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("clipfeat-\(UUID().uuidString).json")
        // Test luồng tính năng (chip STK/OTP là Plus) — mở paywall; gating test ở PlusTests.
        savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        PlusGate.paywallEnabled = savedPaywall
    }

    func testDefaultOffRecordsNothing() {
        let f = ClipboardFeature(fileURL: url)
        f.load(from: UserDefaults(suiteName: "cliptest-\(UUID().uuidString)"))
        XCTAssertFalse(f.historyEnabled)
        XCTAssertFalse(f.incognito)
        XCTAssertNil(f.history)                         // 0 RAM khi tắt
        f.captured("0912345678", change: 1, now: 0, secureField: false, concealed: false)
        XCTAssertTrue(f.items(now: 0).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecordsAndPersistsWhenOn() {
        let f = ClipboardFeature(fileURL: url)
        f.load(historyEnabled: true, incognito: false)
        f.captured("xin chào", change: 1, now: 0, secureField: false, concealed: false)
        XCTAssertEqual(f.items(now: 1).map(\.text), ["xin chào"])
        let f2 = ClipboardFeature(fileURL: url)
        f2.load(historyEnabled: true, incognito: false)
        XCTAssertEqual(f2.items(now: 1).map(\.text), ["xin chào"])
    }

    func testTurningOffWipesFile() {
        let f = ClipboardFeature(fileURL: url)
        f.load(historyEnabled: true, incognito: false)
        f.captured("abc", change: 1, now: 0, secureField: false, concealed: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        f.load(historyEnabled: false, incognito: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(f.history)
    }

    func testIncognitoSecureConcealedSkip() {
        let f = ClipboardFeature(fileURL: url)
        f.load(historyEnabled: true, incognito: true)
        f.captured("a", change: 1, now: 0, secureField: false, concealed: false)
        f.load(historyEnabled: true, incognito: false)
        f.captured("b", change: 2, now: 0, secureField: true, concealed: false)
        f.captured("c", change: 3, now: 0, secureField: false, concealed: true)
        XCTAssertTrue(f.items(now: 0).isEmpty)
        XCTAssertEqual(f.chips(currentChange: 3, usedChange: -1), [])
    }

    func testAutoReadNeedsNoPromptAndFullAccess() {
        let f = ClipboardFeature(fileURL: url)
        f.load(historyEnabled: true, incognito: false, autoSave: true)
        XCTAssertTrue(f.shouldAutoRead(fullAccess: true, noPrompt: true, secureField: false, concealed: false))
        XCTAssertFalse(f.shouldAutoRead(fullAccess: true, noPrompt: false, secureField: false, concealed: false))
        XCTAssertFalse(f.shouldAutoRead(fullAccess: false, noPrompt: true, secureField: false, concealed: false))
        f.load(historyEnabled: false, incognito: false)
        XCTAssertFalse(f.shouldAutoRead(fullAccess: true, noPrompt: true, secureField: false, concealed: false))
    }

    /// "Tự lưu khi sao chép" mặc định TẮT: mỗi lần đọc `string` iOS hiện banner "VietTelex
    /// đã dán từ…" ⇒ không tự đọc kể cả khi đã Cho phép dán (noPrompt) + Toàn quyền.
    func testAutoReadOffByDefault() {
        XCTAssertEqual(ClipboardFeature.autoSaveKey, "clipboardAutoSave")
        let d = UserDefaults(suiteName: "clipauto-\(UUID().uuidString)")!
        d.set(true, forKey: ClipboardFeature.historyKey)
        let f = ClipboardFeature(fileURL: url)
        f.load(from: d)
        XCTAssertTrue(f.historyEnabled)
        XCTAssertFalse(f.autoSave)
        XCTAssertFalse(f.shouldAutoRead(fullAccess: true, noPrompt: true, secureField: false, concealed: false))
        // Đọc chủ động (mở bảng / Dán) vẫn ghi được.
        XCTAssertTrue(f.canRecord(secureField: false, concealed: false))
        d.set(true, forKey: ClipboardFeature.autoSaveKey)
        f.load(from: d)
        XCTAssertTrue(f.shouldAutoRead(fullAccess: true, noPrompt: true, secureField: false, concealed: false))
        // Bật tự lưu nhưng tắt lịch sử / ẩn danh ⇒ vẫn không đọc.
        f.load(historyEnabled: false, incognito: false, autoSave: true)
        XCTAssertFalse(f.shouldAutoRead(fullAccess: true, noPrompt: true, secureField: false, concealed: false))
        f.load(historyEnabled: true, incognito: true, autoSave: true)
        XCTAssertFalse(f.shouldAutoRead(fullAccess: true, noPrompt: true, secureField: false, concealed: false))
    }

    /// Như "Lịch sử clipboard": công tắc riêng từng máy, không đi theo file sao lưu / iCloud.
    func testAutoSaveNotInBackupLikeHistory() {
        XCTAssertNil(BackupSettings.byKey[ClipboardFeature.historyKey])
        XCTAssertNil(BackupSettings.byKey[ClipboardFeature.autoSaveKey])
    }

    func testPinLimitFromPlus() {
        let f = ClipboardFeature(fileURL: url)
        f.load(historyEnabled: true, incognito: false)
        f.pinLimit = { 5 }
        for i in 1...7 { f.captured("mục \(i)", change: i, now: 0, secureField: false, concealed: false) }
        for i in 1...5 { XCTAssertTrue(f.togglePin("mục \(i)")) }
        XCTAssertFalse(f.togglePin("mục 6"))            // miễn phí tối đa 5
        XCTAssertTrue(f.togglePin("mục 1"))             // bỏ ghim luôn được
        XCTAssertTrue(f.togglePin("mục 6"))
        f.pinLimit = { nil }                            // Plus: không giới hạn
        XCTAssertTrue(f.togglePin("mục 7"))
        XCTAssertEqual(f.history?.pinnedCount, 6)
    }

    func testChipsNeedAdvancedClipboard() {
        let f = ClipboardFeature(fileURL: url)
        f.load(historyEnabled: true, incognito: false)
        f.chipsUnlocked = { false }
        f.captured("0912345678", change: 1, now: 0, secureField: false, concealed: false)
        XCTAssertEqual(f.chips(currentChange: 1, usedChange: -1), [])
        f.chipsUnlocked = { true }
        XCTAssertEqual(f.chips(currentChange: 1, usedChange: -1).map(\.value), ["0912345678"])
    }

    func testDefaultGateFollowsPlusGate() {
        let f = ClipboardFeature(fileURL: url)
        XCTAssertEqual(f.pinLimit(), PlusGate.pinnedClipLimit)
        XCTAssertEqual(f.chipsUnlocked(), PlusGate.isUnlocked(.advancedClipboard))
    }

    func testChipsFollowChangeCountAndUse() {
        let f = ClipboardFeature(fileURL: url)
        f.load(historyEnabled: true, incognito: false)
        f.captured("Ma OTP cua ban la 482913", change: 7, now: 0, secureField: false, concealed: false)
        XCTAssertEqual(f.chips(currentChange: 7, usedChange: -1).map(\.value), ["482913"])
        XCTAssertEqual(f.chips(currentChange: 8, usedChange: -1), [])   // clipboard đã đổi
        XCTAssertEqual(f.chips(currentChange: 7, usedChange: 7), [])    // đã dán
        // OTP = giống bí mật → hết hạn sau 2 phút trong lịch sử
        XCTAssertEqual(f.items(now: 60).count, 1)
        XCTAssertEqual(f.items(now: 121).count, 0)
    }
}

/// "Giữ lịch sử clipboard" 1 giờ / 24 giờ / 7 ngày (cùng khoá + id Android ClipboardTTLTest).
final class ClipboardTTLTests: XCTestCase {
    private let hour: TimeInterval = 3600

    func testParse() {
        XCTAssertEqual(ClipboardTTL.key, "clipboardTTL")
        XCTAssertEqual(ClipboardTTL.parse("1h").seconds, 3600)
        XCTAssertEqual(ClipboardTTL.parse("24h").seconds, 24 * 3600)
        XCTAssertEqual(ClipboardTTL.parse("7d").seconds, 7 * 24 * 3600)
        XCTAssertEqual(ClipboardTTL.parse(nil), .hour1)        // chưa đặt → 1 giờ
        XCTAssertEqual(ClipboardTTL.parse("30d"), .hour1)      // lạ → 1 giờ
        XCTAssertEqual(ClipboardTTL.parse(""), .hour1)
        XCTAssertEqual(ClipboardTTL.ids, ["1h", "24h", "7d"])
    }

    func testPrune24hAnd1h() {
        let h = ClipboardHistory(fileURL: nil, ttl: ClipboardTTL.hours24.seconds)
        h.add("hai giờ trước", now: 0)
        XCTAssertEqual(h.items(now: 2 * hour).map(\.text), ["hai giờ trước"])   // 24h: giữ
        h.ttl = ClipboardTTL.hour1.seconds                                       // rút ngắn → prune kế tiếp xoá
        XCTAssertEqual(h.items(now: 2 * hour).map(\.text), [])
    }

    func testPrune7dSensitivePinned() {
        let h = ClipboardHistory(fileURL: nil, ttl: ClipboardTTL.days7.seconds)
        h.add("tám ngày", now: 0)
        h.add("ghim", now: 0); h.togglePin("ghim")
        h.add("sáu ngày", now: 2 * 24 * hour)
        h.add("Xk9#mP2qL", now: 8 * 24 * hour - 200)    // giống mật khẩu
        // 8 ngày → xoá; bí mật quá 2 phút → xoá dù 7 ngày; ghim giữ.
        XCTAssertEqual(h.items(now: 8 * 24 * hour).map(\.text), ["ghim", "sáu ngày"])
    }

    func testFeatureReadsSettingOnLoad() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipttl-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let d = UserDefaults(suiteName: "clipttl-\(UUID().uuidString)")!
        d.set(true, forKey: ClipboardFeature.historyKey)
        d.set("7d", forKey: ClipboardFeature.ttlKey)
        let f = ClipboardFeature(fileURL: url)
        f.load(from: d)
        XCTAssertEqual(f.history?.ttl, 7 * 24 * 3600)
        f.captured("xin chào", change: 1, now: 0, secureField: false, concealed: false)
        XCTAssertEqual(f.items(now: 3 * 24 * hour).map(\.text), ["xin chào"])
        d.set("1h", forKey: ClipboardFeature.ttlKey)      // đổi trong app → lần hiện kế tiếp
        f.load(from: d)
        XCTAssertEqual(f.history?.ttl, 3600)
        XCTAssertEqual(f.items(now: 3 * 24 * hour).map(\.text), [])
    }

    func testBackupSpecIncludesKey() {
        guard case .string(let def, let allowed)? = BackupSettings.byKey[ClipboardTTL.key]?.kind else {
            return XCTFail("clipboardTTL phải có trong BackupSettings (.string)")
        }
        XCTAssertEqual(def, ClipboardTTL.default.rawValue)
        XCTAssertEqual(allowed, ClipboardTTL.ids)
    }
}

/// Khởi động lạnh: tạo ClipboardHistory (mỗi lần hiện) KHÔNG đọc / giải file JSON; lần dùng đầu
/// mới đọc — lịch sử vẫn đầy đủ.
final class ClipboardLazyLoadTests: XCTestCase {
    func testHistoryLoadsLazilyOnFirstUse() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-lazy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date().timeIntervalSince1970
        let w = ClipboardHistory(fileURL: url)
        w.add("mot", now: now - 10)
        w.add("hai", now: now - 5)
        XCTAssertTrue(w.togglePin("mot"))
        w.save()

        let h = ClipboardHistory(fileURL: url)
        XCTAssertFalse(h.debugLoaded, "init không đọc file")
        XCTAssertEqual(h.items(now: now).map(\.text), ["mot", "hai"], "ghim trước, rồi mới nhất")
        XCTAssertTrue(h.debugLoaded)
        // Thêm mục trước khi từng đọc: vẫn giữ lịch sử cũ (đọc lười rồi mới chèn).
        let h2 = ClipboardHistory(fileURL: url)
        h2.add("ba", now: now)
        XCTAssertEqual(h2.items(now: now).map(\.text), ["mot", "ba", "hai"])
    }

    func testFeatureLoadDoesNotReadFile() {
        let f = ClipboardFeature(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-lazy-\(UUID().uuidString).json"))
        f.load(historyEnabled: true, incognito: false)
        XCTAssertEqual(f.history?.debugLoaded, false, "công tắc bật: chỉ tạo object, chưa đọc file")
    }
}
