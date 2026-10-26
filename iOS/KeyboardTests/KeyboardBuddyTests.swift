// "Bạn đồng hành" (Keyboard/KeyboardBuddy*.swift): máy trạng thái theo dấu giờ, bậc tốc độ, dáng nhảy, cổng
// Plus, 0 view khi tắt, 0 hoạt ảnh khi ngủ, ô không đè gợi ý / phím, 500 phím không rò, chi phí mỗi phím.
// Số tham chiếu (bậc, mốc giờ, checksum bảng hình) GIỐNG HỆT android KeyboardBuddyTests.
import XCTest
import UIKit

final class KeyboardBuddyTests: XCTestCase {
    private let suite = "vt-buddy-tests"
    private let plusSuite = "vt-buddy-plus"
    private var savedPaywall = false
    private var savedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedPaywall = PlusGate.paywallEnabled
        savedDefaults = PlusGate.defaults
        UserDefaults(suiteName: plusSuite)!.removePersistentDomain(forName: plusSuite)
        PlusGate.defaults = UserDefaults(suiteName: plusSuite)!
    }

    override func tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.defaults = savedDefaults
        UserDefaults(suiteName: plusSuite)!.removePersistentDomain(forName: plusSuite)
        super.tearDown()
    }

    // MARK: Cài đặt

    func testIdsMatchAndroidAndDefaultIsOff() {
        XCTAssertEqual(BuddyCharacter.allCases.map(\.rawValue), ["off", "girl", "boy", "cat", "chick"])
        XCTAssertEqual(BuddyCharacter.key, "keyboardBuddy")
        XCTAssertEqual(BuddyCharacter.defaultValue, .off)
        XCTAssertEqual(BuddyCharacter.parse("lạ"), .off)
        XCTAssertEqual(BuddyCharacter.parse(nil), .off)
        XCTAssertEqual(BuddyCharacter.parse("chick"), .chick)
    }

    /// Kiểu vẽ riêng từng nhân vật: mặc định Hoạt hình, khoá `buddyStyle.<id>` (= Android), lạ ⇒ mặc định.
    func testStyleKeysAndDefault() {
        XCTAssertEqual(BuddyStyle.allCases.map(\.rawValue), ["sprite", "vector"])
        XCTAssertEqual(BuddyStyle.defaultValue, .sprite)
        XCTAssertEqual(BuddyStyle.key(.girl), "buddyStyle.girl")
        XCTAssertEqual(BuddyStyle.key(.chick), "buddyStyle.chick")
        XCTAssertEqual(BuddyStyle.parse(nil), .sprite)
        XCTAssertEqual(BuddyStyle.parse("lạ"), .sprite)
        XCTAssertEqual(BuddyStyle.parse("vector"), .vector)
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(BuddyStyle.load(d, .cat), .sprite, "chưa chọn ⇒ Hoạt hình")
        d.set("vector", forKey: BuddyStyle.key(.cat))
        XCTAssertEqual(BuddyStyle.load(d, .cat), .vector)
        XCTAssertEqual(BuddyStyle.load(d, .boy), .sprite, "riêng từng nhân vật")
        for c in BuddyCharacter.allCases where c != .off {
            XCTAssertNotNil(BackupSettings.all.first { $0.key == BuddyStyle.key(c) }, "sao lưu kiểu vẽ \(c)")
        }
    }

    /// Hoạt hình + mùa lễ ⇒ không trang phục; Vẽ nét + mùa lễ ⇒ trang phục; ngoài mùa ⇒ không.
    func testStyleSeasonResolution() {
        XCTAssertNil(BuddyStyle.sprite.season(.tet))
        XCTAssertNil(BuddyStyle.sprite.season(nil))
        XCTAssertEqual(BuddyStyle.vector.season(.christmas), .christmas)
        XCTAssertNil(BuddyStyle.vector.season(nil))
        XCTAssertTrue(BuddyOutfit.make(BuddyStyle.sprite.season(.christmas), .girl).pieces.isEmpty)
        XCTAssertFalse(BuddyOutfit.make(BuddyStyle.vector.season(.christmas), .girl).pieces.isEmpty)
    }

    func testStyleTitlesBilingual() {
        defer { L10n.apply("vi") }
        L10n.apply("vi")
        XCTAssertEqual(BuddyStyle.allCases.map(\.title), ["Hoạt hình", "Vẽ nét"])
        L10n.apply("en")
        XCTAssertEqual(BuddyStyle.allCases.map(\.title), ["Cartoon", "Vector"])
    }

    /// View: Hoạt hình (mặc định) dùng atlas dù đang mùa lễ, không trang phục; Vẽ nét không nạp atlas.
    @MainActor func testViewFollowsStyle() throws {
        let sprite = BuddyView(character: .girl, bar: 0x222222, lowPower: false, season: .tet)
        XCTAssertEqual(sprite.artStyle, .sprite)
        sprite.frame = CGRect(x: 0, y: 0, width: 50, height: 44)
        sprite.layoutIfNeeded()
        XCTAssertNotNil(try XCTUnwrap(sprite.layer.sublayers?.first).contents, "mùa lễ vẫn là ảnh atlas")
        XCTAssertEqual(sprite.outfitPieceCount, 0)
        let vector = BuddyView(character: .girl, bar: 0x222222, lowPower: false, season: .tet, artStyle: .vector)
        vector.frame = sprite.frame
        vector.layoutIfNeeded()
        XCTAssertNil(vector.layer.sublayers?.first?.contents, "Vẽ nét: không ảnh atlas")
        XCTAssertGreaterThan(vector.outfitPieceCount, 0)
        sprite.halt(); vector.halt()
    }

    /// Vị trí & cỡ: cỡ 5 = khung y như cũ; hệ số 0,68…1,40; neo đáy-phải; to hơn thì lớn xuống; lề dời đúng chiều.
    func testPlacementMath() {
        XCTAssertEqual(BuddyPlacement.standard.scale(full: 4), 1, accuracy: 1e-9)
        XCTAssertEqual(BuddyPlacement(size: 1).scale(full: 4), 0.68, accuracy: 1e-9)
        XCTAssertEqual(BuddyPlacement(size: 20).scale(full: 4), 4, accuracy: 1e-9, "cỡ 20 = cao trọn bàn phím")
        XCTAssertEqual(BuddyPlacement(size: 10).scale(full: 4), pow(4, 1.0 / 3), accuracy: 1e-9, "5…20 nhân đều")
        XCTAssertEqual(BuddyPlacement(size: 20).scale(full: 0.5), 1, accuracy: 1e-9, "bàn phím thấp ⇒ không nhỏ hơn gốc")
        let base = BuddyRect(x: 324, y: 0, w: 66, h: 66)
        XCTAssertEqual(BuddyPlacement.standard.frame(standard: base, minWidth: 34), base)
        XCTAssertEqual(BuddyPlacement(size: 1).frame(standard: base, minWidth: 34), BuddyRect(x: 345, y: 21, w: 45, h: 45),
                       "nhỏ: neo đáy-phải")
        XCTAssertEqual(BuddyPlacement(size: 10).frame(standard: base, minWidth: 34), BuddyRect(x: 304, y: 0, w: 86, h: 86),
                       "to: đỉnh giữ ở trần, lớn xuống phím")
        XCTAssertEqual(BuddyPlacement(size: 20).frame(standard: base, minWidth: 34, fullHeight: 264),
                       BuddyRect(x: 126, y: 0, w: 264, h: 264), "cỡ 20 phủ trọn chiều cao bàn phím")
        XCTAssertEqual(BuddyPlacement(padRight: 10, padTop: -4).frame(standard: base, minWidth: 34),
                       BuddyRect(x: 314, y: -4, w: 66, h: 66))
        XCTAssertEqual(BuddyPlacement(padRight: -10).frame(standard: base, minWidth: 34).x, 334, "âm ⇒ dời phải")
        XCTAssertEqual(BuddyPlacement(padTop: 3).frame(standard: base, minWidth: 34, unit: 2).y, 6, "Android: dp × mật độ")
        XCTAssertEqual(BuddyPlacement.standard.zoneWidth(34), 34)
        XCTAssertEqual(BuddyPlacement(size: 10).zoneWidth(34), 48)
        XCTAssertEqual(BuddyPlacement(size: 1, padRight: 6).zoneWidth(34), 23 + 6)
        XCTAssertEqual(BuddyPlacement(padRight: -6).zoneWidth(34), 34)
        // Cỡ mặc định: khung bàn phím y như trước khi có cài đặt.
        XCTAssertEqual(KeyboardView.buddyFrame(width: 390, strip: 40, placement: .standard),
                       KeyboardView.buddyFrame(width: 390, strip: 40))
        // Đọc App Group: thiếu ⇒ mặc định, ngoài miền ⇒ kẹp; có trong sao lưu.
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(BuddyPlacement.load(d), .standard)
        d.set(42, forKey: BuddyPlacement.sizeKey); d.set(-300, forKey: BuddyPlacement.padRightKey); d.set(7, forKey: BuddyPlacement.padTopKey)
        XCTAssertEqual(BuddyPlacement.load(d), BuddyPlacement(size: 20, padRight: -100, padTop: 7))
        XCTAssertEqual(BuddyPlacement(padRight: 100).zoneWidth(34), 34 + 10, "lề lớn không bóp thanh gợi ý")
        for k in [BuddyPlacement.sizeKey, BuddyPlacement.padRightKey, BuddyPlacement.padTopKey] {
            XCTAssertNotNil(BackupSettings.all.first { $0.key == k }, "sao lưu \(k)")
        }
    }

    func testBackupSpecWhitelistsIds() {
        let spec = BackupSettings.all.first { $0.key == BuddyCharacter.key }
        XCTAssertNotNil(spec, "sao lưu cùng khoá với Android")
    }

    func testTitlesBilingual() {
        defer { L10n.apply("vi") }
        L10n.apply("vi")
        XCTAssertEqual(BuddyCharacter.girl.title, "Cô gái")
        XCTAssertEqual(BuddyCharacter.off.title, "Tắt")
        L10n.apply("en")
        XCTAssertEqual(BuddyCharacter.allCases.map(\.title), ["Off", "Girl", "Boy", "Cat", "Chick"])
        XCTAssertEqual(L("Bạn đồng hành"), "Keyboard buddy")
    }

    /// Plus: hết Plus ⇒ Tắt (không tạo view) nhưng GIỮ cài đặt (mua lại là có ngay).
    func testPlusFallback() {
        XCTAssertEqual(BuddyPolicy.active(setting: .cat, plus: false), .off)
        XCTAssertEqual(BuddyPolicy.active(setting: .cat, plus: true), .cat)
        XCTAssertEqual(BuddyPolicy.active(setting: .off, plus: true), .off)
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        d.set("girl", forKey: BuddyCharacter.key)
        PlusGate.paywallEnabled = true
        PlusGate.defaults.set(false, forKey: PlusConfig.unlockedKey)
        XCTAssertEqual(BuddyPolicy.current(d), .off)
        XCTAssertEqual(d.string(forKey: BuddyCharacter.key), "girl", "không xoá lựa chọn")
        PlusGate.defaults.set(true, forKey: PlusConfig.unlockedKey)
        XCTAssertEqual(BuddyPolicy.current(d), .girl)
        XCTAssertFalse(BuddyCharacter.off.isPlus)
        XCTAssertTrue(BuddyCharacter.allCases.filter { $0 != .off }.allSatisfy(\.isPlus))
    }

    // MARK: Bậc tốc độ

    func testTierFunction() {
        // Số phím trong 2 s → bậc (cùng ngưỡng Lửa combo 6/10/14).
        XCTAssertEqual((0...16).map { BuddyTempo.tier(count: $0, previous: 0) },
                       [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3])
        // Trễ xuống: đang bậc 3, tụt về 12–13 vẫn giữ 3; 11 ⇒ 2; 4 ⇒ 0.
        XCTAssertEqual(BuddyTempo.tier(count: 13, previous: 3), 3)
        XCTAssertEqual(BuddyTempo.tier(count: 12, previous: 3), 3)
        XCTAssertEqual(BuddyTempo.tier(count: 11, previous: 3), 2)
        XCTAssertEqual(BuddyTempo.tier(count: 8, previous: 2), 2)
        XCTAssertEqual(BuddyTempo.tier(count: 7, previous: 2), 1)
        XCTAssertEqual(BuddyTempo.tier(count: 4, previous: 1), 1)
        XCTAssertEqual(BuddyTempo.tier(count: 3, previous: 1), 0)
        // Không bao giờ vượt bậc thô khi đi lên.
        for n in 0...20 { for p in 0...3 { XCTAssertGreaterThanOrEqual(BuddyTempo.tier(count: n, previous: p), BuddyTempo.raw(n)) } }
    }

    /// Gõ đều với khoảng cách `dt` giây: bậc sau ~2 s.
    func testTierFromInterKeyInterval() {
        func tierAfter(interval dt: Double) -> Int {
            var b = BuddyBrain()
            var t = 0.0
            for _ in 0..<40 { b.press(at: t); t += dt }
            return b.tier
        }
        XCTAssertEqual(tierAfter(interval: 0.5), 0)    // 2 phím/s
        XCTAssertEqual(tierAfter(interval: 0.3), 1)    // ~3,3 phím/s
        XCTAssertEqual(tierAfter(interval: 0.18), 2)   // ~5,5 phím/s
        XCTAssertEqual(tierAfter(interval: 0.11), 3)   // ~9 phím/s
    }

    // MARK: Máy trạng thái

    /// Ngủ → thức → nhảy (lên bậc) → lắc nhẹ 8 s → ngủ ("z z" 2 s) → ngủ yên; mốc hẹn giờ đúng từng chặng.
    func testStateMachineTimeline() {
        var b = BuddyBrain()
        XCTAssertEqual(b.phase(at: 0), .asleep(zzz: false), "mới mở bàn phím: ngủ yên, không hoạt ảnh")
        XCTAssertNil(b.nextDeadline(after: 0))
        // Gõ nhanh 9 phím/s từ t=10.
        var t = 10.0
        b.press(at: t)
        XCTAssertEqual(b.phase(at: t), .dancing(0))
        XCTAssertEqual(b.nextDeadline(after: t), t + BuddyBrain.tail)
        var seen: [Int] = []
        for _ in 0..<30 {
            t += 0.11
            b.press(at: t)
            if case .dancing(let k) = b.phase(at: t), seen.last != k { seen.append(k) }
        }
        XCTAssertEqual(seen, [0, 1, 2, 3], "lên bậc dần, không nhảy cóc / lùi")
        let last = t
        XCTAssertEqual(b.phase(at: last + 0.59), .dancing(3), "đuôi nhảy 0,6 s")
        XCTAssertEqual(BuddyBrain.sleepAfter, 8.6, accuracy: 1e-9)
        XCTAssertEqual(b.phase(at: last + 0.61), .idle, "hết đuôi nhảy ⇒ lắc nhẹ")
        XCTAssertEqual(b.nextDeadline(after: last + 0.61)!, last + 8.6, accuracy: 1e-9)
        XCTAssertEqual(b.phase(at: last + 8.59), .idle)
        XCTAssertEqual(b.phase(at: last + 8.61), .asleep(zzz: true), "≥ 8,6 s không gõ ⇒ ngủ, z z")
        XCTAssertEqual(b.nextDeadline(after: last + 8.61)!, last + 10.6, accuracy: 1e-9)
        XCTAssertEqual(b.phase(at: last + 10.61), .asleep(zzz: false), "z z chỉ ~2 s rồi dừng hẳn")
        XCTAssertNil(b.nextDeadline(after: last + 10.61), "ngủ yên ⇒ không hẹn giờ nào")
        // Gõ lại sau giấc ngủ: bậc tính lại từ 0.
        b.press(at: last + 20)
        XCTAssertEqual(b.phase(at: last + 20), .dancing(0))
    }

    func testCheerWakesThenSettles() {
        var b = BuddyBrain()
        b.cheer(at: 5)
        XCTAssertEqual(b.phase(at: 5.1), .cheering)
        XCTAssertEqual(b.phase(at: 5.0 + BuddyBrain.cheer + 0.01), .idle)
        XCTAssertEqual(b.phase(at: 13.7), .asleep(zzz: true))
    }

    /// Ngừng gõ: + 5 s vẫn lắc nhẹ, + 9 s đã ngủ.
    func testIdleSwayBeforeSleep() {
        var b = BuddyBrain()
        b.press(at: 10)
        XCTAssertEqual(b.phase(at: 15), .idle)
        XCTAssertEqual(b.phase(at: 19), .asleep(zzz: true))
        XCTAssertEqual(BuddyPolicy.visual(.idle, lowPower: true), .awake, "nguồn điện thấp: dáng nghỉ")
        XCTAssertTrue(BuddyPolicy.animates(.idle))
        // Lắc hông bậc 0 (nhẹ nhất), bắt đầu/kết thúc ở dáng nghỉ ⇒ nối mượt với nhảy và ngủ.
        let s = BuddyRig.girl.style
        XCTAssertEqual(BuddyDance.idle(s, p: 0), .rest)
        XCTAssertEqual(BuddyDance.idle(s, p: 0.375), BuddyDance.pose(s, tier: 0, p: 0.375, move: .hipSway))
        XCTAssertGreaterThan(BuddyDance.idleLoop, BuddyDance.loopLength(0), "chậm hơn bậc nhảy chậm nhất")
        XCTAssertEqual(BuddySprites.idle, [5, 6])
    }

    func testLowPowerShowsStaticPosesOnly() {
        for p: BuddyPhase in [.dancing(3), .idle, .cheering, .awake] {
            XCTAssertEqual(BuddyPolicy.visual(p, lowPower: true), .awake)
        }
        XCTAssertEqual(BuddyPolicy.visual(.asleep(zzz: true), lowPower: true), .asleep(zzz: false))
        XCTAssertEqual(BuddyPolicy.visual(.dancing(2), lowPower: false), .dancing(2))
        XCTAssertFalse(BuddyPolicy.animates(.awake))
        XCTAssertFalse(BuddyPolicy.animates(.asleep(zzz: false)))
        XCTAssertTrue(BuddyPolicy.animates(.dancing(0)))
    }

    // MARK: Dáng nhảy

    func testDancePoseLoopsAndEnergyRisesWithTier() {
        for c in BuddyCharacter.allCases where c != .off {
            let s = BuddyRig.rig(c)!.style
            var peaks: [Double] = []
            for t in 0..<4 {
                XCTAssertEqual(BuddyDance.pose(s, tier: t, p: 0), BuddyDance.pose(s, tier: t, p: 1), "vòng khép kín")
                var bounce = 0.0
                for i in 0..<200 { bounce = max(bounce, -BuddyDance.pose(s, tier: t, p: Double(i) / 200).dy) }
                peaks.append(bounce)
            }
            XCTAssertEqual(peaks, peaks.sorted(), "\(c): gõ nhanh hơn ⇒ nhún cao hơn")
            XCTAssertLessThan(peaks[0], peaks[3])
            // Xoay vòng chỉ ở bậc cao nhất.
            XCTAssertTrue((0..<100).allSatisfy { BuddyDance.pose(s, tier: 2, p: Double($0) / 100).sx == 1 })
            XCTAssertTrue((0..<100).contains { BuddyDance.pose(s, tier: 3, p: Double($0) / 100, move: .spin).sx < 0 })
            XCTAssertEqual(BuddyDance.cheer(s, f: 0), .rest)
            XCTAssertEqual(BuddyDance.cheer(s, f: 1).dy, 0, accuracy: 1e-9)
        }
        XCTAssertEqual(BuddyDance.loopLength(0), 2.48, accuracy: 1e-9)
        XCTAssertEqual(BuddyDance.loopLength(3), 1.44, accuracy: 1e-9)
    }

    /// Số chung với Android: pose cô gái bậc 2 tại p = 0,3.
    func testPoseParityNumbers() {
        let p = BuddyDance.pose(BuddyRig.girl.style, tier: 2, p: 0.3)
        XCTAssertEqual(p.dy, -4.4966, accuracy: 1e-3)
        XCTAssertEqual(p.dx, 6.4672, accuracy: 1e-3)
        XCTAssertEqual(p.armL, 1.8051, accuracy: 1e-3)
        XCTAssertEqual(p.armR, -2.1049, accuracy: 1e-3)
        XCTAssertEqual(p.tail, 0.2829, accuracy: 1e-3)
    }

    // MARK: Hình (dữ liệu)

    /// Phil 20/10: lật gương khung có sẵn để gấp đôi dáng (nhấc chân trái → chân phải).
    func testMirroredFramesDoublePoses() {
        let turn = BuddySprites.dance(.boy, 2)
        XCTAssertTrue(turn.contains(1) && turn.contains(1 + BuddySprites.mirror), "bước trái + bước phải")
        for f in 2...6 { XCTAssertTrue(turn.contains(f + BuddySprites.mirror), "khung \(f) có bản lật") }
        XCTAssertTrue(BuddySprites.dance(.girl, 0).contains(where: BuddySprites.isMirrored))
        XCTAssertTrue(BuddySprites.cheer.contains(where: BuddySprites.isMirrored))
        for seq in [turn, BuddySprites.dance(.boy, 0), BuddySprites.cheer, BuddySprites.react] {
            for f in seq { XCTAssertLessThan(BuddySprites.cell(f), 7, "không lật / dùng khung ngủ khi nhảy") }
        }
        XCTAssertEqual(BuddySprites.cell(103), 3)
        // Xoay trọn vòng trái rồi phải bằng ảnh (không rotate): đủ 5 dáng quay + bản lật, cô gái theo thứ tự riêng.
        for c in BuddyCharacter.allCases where c != .off {
            let d = BuddySprites.dance(c, 3), o = BuddySprites.turnOrder(c)
            XCTAssertEqual(Set(o), [2, 3, 4, 5, 6])
            let s = d.firstIndex(of: o[0])!
            XCTAssertEqual(Array(d[s..<s + 5]), o, "\(c) vòng trái")
            XCTAssertEqual(Array(d[s + 6..<s + 11]), o.map { $0 + BuddySprites.mirror }, "\(c) vòng phải")
        }
        XCTAssertEqual(BuddySprites.turnOrder(.girl), [6, 3, 4, 2, 5])
        // Lắc hông: 5 ↔ 6 liền nhau ít nhất hai lượt (gõ vừa và nhanh).
        for tier in [1, 2, 3] {
            let d = BuddySprites.dance(.cat, tier).map(BuddySprites.cell)
            let swings = zip(d, d.dropFirst()).filter { Set([$0, $1]) == [5, 6] }.count
            XCTAssertGreaterThanOrEqual(swings, 3, "bậc \(tier)")
        }
        XCTAssertFalse(BuddySprites.isMirrored(6))
        // Nhịp mỗi khung giữ như bộ 10 khung cũ.
        XCTAssertEqual(BuddySprites.duration(.boy, 2) / Double(turn.count),
                       BuddyDance.loopLength(2) / 10, accuracy: 1e-9)
    }

    func testGirlUsesSameEightFramesAsBoy() {
        for tier in 0..<BuddyTempo.tiers {
            XCTAssertEqual(BuddySprites.dance(.girl, tier).count, BuddySprites.dance(.boy, tier).count)
            XCTAssertEqual(BuddySprites.duration(.girl, tier), BuddySprites.duration(.boy, tier))
        }
        XCTAssertEqual(BuddySprites.columns(.girl), 4)
        XCTAssertEqual(BuddySprites.rows(.girl), 2)
        XCTAssertEqual(BuddySprites.rest(.girl), 0)
        XCTAssertEqual(BuddySprites.sleep(.girl), 7)
    }

    @MainActor func testSpriteLifecycle() throws {
      for character in BuddyCharacter.allCases where character != .off {
        let v = BuddyView(character: character, bar: 0x222222, lowPower: false)
        v.frame = CGRect(x: 0, y: 0, width: 50, height: 44)
        v.layoutIfNeeded()
        let sprite = try XCTUnwrap(v.layer.sublayers?.first)
        XCTAssertNotNil(sprite.contents, "Sprite atlas must be bundled in app, extension and tests")
        XCTAssertTrue(v.bounds.contains(sprite.frame))
        v.apply(.dancing(3), now: 0)
        XCTAssertNotNil(sprite.animation(forKey: "sprite"))
        v.apply(.asleep(zzz: false), now: 4)
        XCTAssertNil(sprite.animationKeys())
        XCTAssertEqual(sprite.contentsRect, CGRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5))
        v.lowPower = true
        v.apply(.dancing(3), now: 5)
        XCTAssertNil(sprite.animationKeys())
        v.halt()
      }
    }

    @MainActor func testGirlSleepsImmediatelyLikeBoy() throws {
        let v = BuddyView(character: .girl, bar: 0x222222, lowPower: false)
        v.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        v.layoutIfNeeded()
        let sprite = try XCTUnwrap(v.layer.sublayers?.first)
        v.apply(.awake, now: 0)
        v.apply(.asleep(zzz: true), now: 3)
        XCTAssertNil(sprite.animationKeys())
        XCTAssertEqual(sprite.contentsRect, CGRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5))
        v.apply(.dancing(0), now: 3.2)
        XCTAssertEqual(sprite.animation(forKey: "sprite")?.repeatCount, .infinity)
        v.lowPower = true
        v.apply(.awake, now: 4)
        v.apply(.asleep(zzz: true), now: 7)
        XCTAssertNil(sprite.animationKeys())
        v.halt()
    }

    func testSVGParse() {
        XCTAssertEqual(BuddySVG.parse("M1 2 l3 4 h5 V-6 q1 1 2 2 Z"),
                       [.move(1, 2), .line(4, 6), .line(9, 6), .line(9, -6), .quad(10, -5, 11, -4), .close])
        XCTAssertEqual(BuddySVG.numbers("M-8 72 L-10 140"), [-8, 72, -10, 140])
        XCTAssertEqual(BuddySVG.numbers("h1.5-2"), [1.5, -2])
    }

    /// Bảng hình giống hệt Android (KeyboardBuddyTests.rigChecksumParity).
    func testRigChecksumParity() {
        let sums = BuddyCharacter.allCases.map { String(format: "%.4f", BuddyRig.checksum($0)) }
        print("BUDDY checksum \(sums)")
        XCTAssertEqual(sums, Self.checksums)
    }
    static let checksums = ["0.0000", "29155.8356", "19939.9990", "28728.3206", "20913.1220"]

    func testEveryRigHasAllPartsAndSleepPose() {
        for c in BuddyCharacter.allCases where c != .off {
            let r = BuddyRig.rig(c)!
            for p in [BuddyPart.legL, .legR, .body, .armL, .armR, .head, .sleep] {
                XCTAssertTrue(r.pieces.contains { $0.part == p }, "\(c) thiếu \(p)")
            }
            for p in r.pieces where p.part != .sleep { XCTAssertNotNil(r.pivots[p.part], "\(c) \(p.part) thiếu điểm xoay") }
            XCTAssertTrue(r.pieces.contains { $0.show == .rest } == r.pieces.contains { $0.show == .dance })
        }
        XCTAssertTrue(BuddyRig.girl.hasTail && BuddyRig.cat.hasTail)
        XCTAssertFalse(BuddyRig.boy.hasTail || BuddyRig.chick.hasTail)
        XCTAssertEqual(BuddySprites.frameIndex(p: 0.99, count: 8), 7)
        XCTAssertEqual(BuddySprites.frameIndex(p: 1.0, count: 8), 0)
    }

    // MARK: View

    private final class Clock { var t = 100.0 }

    @MainActor private func makeView(_ c: BuddyCharacter, low: Bool = false, clock: Clock) -> BuddyView {
        // Kiểu Vẽ nét + mùa lễ (khung vector); vòng đời atlas Hoạt hình test riêng ở trên.
        let v = BuddyView(character: c, bar: BuddyHalo.systemLight, lowPower: low, season: .christmas, artStyle: .vector)
        v.clock = { clock.t }
        v.frame = CGRect(x: 0, y: 0, width: KeyboardView.buddyZoneWidth, height: 40)
        v.layoutIfNeeded()
        return v
    }

    /// Ngủ ⇒ 0 hoạt ảnh (kể cả lúc mới hiện); "z z" có hạn rồi gỡ; đứng yên cũng 0 (sau lượt nối).
    @MainActor func testZeroAnimationsWhenAsleep() {
        let clock = Clock()
        for c in BuddyCharacter.allCases where c != .off {
            let v = makeView(c, clock: clock)
            XCTAssertEqual(v.shown, .asleep(zzz: false))
            XCTAssertEqual(v.runningAnimationCount, 0, "\(c): mới hiện — ngủ yên")
            XCTAssertFalse(v.hasPendingTimer)
            for _ in 0..<20 { clock.t += 0.1; v.keyPressed() }
            v.tick()
            guard case .dancing = v.shown else { return XCTFail("\(c): gõ ⇒ nhảy") }
            XCTAssertGreaterThan(v.runningAnimationCount, 3)
            XCTAssertTrue(v.hasPendingTimer)
            clock.t += 1; v.tick()
            XCTAssertEqual(v.shown, .idle)
            XCTAssertGreaterThan(v.runningAnimationCount, 0, "\(c): lắc nhẹ")
            clock.t += 8; v.tick()
            XCTAssertEqual(v.shown, .asleep(zzz: true))
            XCTAssertEqual(v.runningAnimationCount, 3, "\(c): chỉ ba chữ z")
            clock.t += 2.1; v.tick()
            XCTAssertEqual(v.shown, .asleep(zzz: false))
            XCTAssertEqual(v.runningAnimationCount, 0, "\(c): ngủ yên ⇒ 0 hoạt ảnh")
            XCTAssertFalse(v.hasPendingTimer, "\(c): ngủ yên ⇒ không hẹn giờ")
            v.halt()
        }
    }

    @MainActor func testLowPowerNeverAnimates() {
        let clock = Clock()
        let v = makeView(.girl, low: true, clock: clock)
        for _ in 0..<30 { clock.t += 0.08; v.keyPressed(); v.tick() }
        XCTAssertEqual(v.shown, .awake)
        XCTAssertEqual(v.runningAnimationCount, 0)
        v.cheer(); v.tick()
        XCTAssertEqual(v.runningAnimationCount, 0)
        clock.t += 9; v.tick()
        XCTAssertEqual(v.shown, .asleep(zzz: false))
        XCTAssertEqual(v.runningAnimationCount, 0)
        v.halt()
    }

    /// Đổi bậc: vòng mới + hoạt ảnh nối (không nhảy dáng); key per-layer giữ ≤ 2 (loop + blend).
    @MainActor func testTierChangeBlendsAndStaysBounded() {
        let clock = Clock()
        let v = makeView(.cat, clock: clock)
        var tiers: [Int] = []
        for _ in 0..<40 {
            clock.t += 0.1; v.keyPressed(); v.tick()
            if case .dancing(let k) = v.shown, tiers.last != k { tiers.append(k) }
            XCTAssertLessThanOrEqual(v.runningAnimationCount, 2 * 20)   // vòng + nối mỗi kênh; bộ phận có bản quầng xoay cùng
        }
        XCTAssertEqual(tiers, [0, 1, 2, 3])
        v.halt()
        XCTAssertEqual(v.runningAnimationCount, 0)
    }

    /// 500 phím: không thêm layer, hoạt ảnh có trần, view giải phóng được (không vòng giữ qua timer).
    @MainActor func testBurstOf500KeysNoLeak() {
        let clock = Clock()
        weak var weakView: BuddyView?
        autoreleasepool {
            let v = makeView(.boy, clock: clock)
            weakView = v
            let layers = v.layerCount
            for i in 0..<500 {
                clock.t += i % 50 < 40 ? 0.07 : 0.35   // nhanh / chậm xen kẽ ⇒ đổi bậc nhiều lần
                v.keyPressed()
                if i % 5 == 0 { v.tick() }
                if i % 100 == 0 { v.cheer() }
            }
            v.tick()
            XCTAssertEqual(v.layerCount, layers, "không tạo thêm layer khi gõ")
            XCTAssertLessThanOrEqual(v.runningAnimationCount, 40)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))   // lượt apply hoãn
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(weakView, "BuddyView rò (timer / block giữ self)")
    }

    /// Chi phí main mỗi phím (đường đồng bộ `keyPressed`) — ngưỡng < 0,1 ms.
    @MainActor func testPerKeyCost() {
        let v = BuddyView(character: .girl, bar: BuddyHalo.systemLight, lowPower: false)
        v.frame = CGRect(x: 0, y: 0, width: 34, height: 40)
        v.layoutIfNeeded()
        var samples: [Double] = []
        for _ in 0..<600 {
            let t0 = CACurrentMediaTime()
            v.keyPressed()
            samples.append((CACurrentMediaTime() - t0) * 1000)
            if samples.count % 60 == 0 { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        }
        samples.removeFirst(100)
        samples.sort()
        let p50 = samples[samples.count / 2], p99 = samples[samples.count * 99 / 100]
        let mean = samples.reduce(0, +) / Double(samples.count)
        // Lượt áp trạng thái (hoãn, ngoài đường phím): đổi bậc ⇒ gắn lại vòng + nối.
        let clock = Clock()
        let w = makeView(.girl, clock: clock)
        var apply: [Double] = []
        for i in 0..<200 {
            clock.t += i % 40 < 20 ? 0.06 : 0.4
            w.keyPressed()
            let t0 = CACurrentMediaTime()
            w.tick()
            apply.append((CACurrentMediaTime() - t0) * 1000)
        }
        apply.sort()
        let line = String(format: "BUDDY cost keyPressed mean=%.4f p50=%.4f p99=%.4f ms | deferred apply p50=%.4f p95=%.4f max=%.4f ms",
                          mean, p50, p99, apply[100], apply[190], apply.last!)
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThan(p50, 0.1)
        XCTAssertLessThan(mean, 0.1)
        v.halt(); w.halt()
    }

    // MARK: KeyboardView

    @MainActor private func withKeyboard(buddy: String?, plus: Bool, width: CGFloat = 390, height: CGFloat = 300,
                                         emojiTop: Bool = false,
                                         _ body: (KeyboardView) throws -> Void) rethrows {
        PlusGate.paywallEnabled = true
        PlusGate.defaults.set(plus, forKey: PlusConfig.unlockedKey)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        if let buddy { d.set(buddy, forKey: BuddyCharacter.key) }
        if emojiTop { d.set("top", forKey: EmojiKeyPlacement.key) }
        d.set(false, forKey: KeyboardView.keyPreviewKey)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        win.isHidden = false
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = win.bounds
        win.addSubview(kb)
        kb.applyAppearance(.light, style: .light)
        kb.setSuggestionsEnabled(true)
        kb.layoutIfNeeded()
        try body(kb)
        win.isHidden = true
        kb.tearDown()
    }

    /// Tắt / hết Plus ⇒ không view, không layer; bật ⇒ một view; đổi về Tắt ⇒ gỡ sạch.
    @MainActor func testNoLayersWhenOff() throws {
        try withKeyboard(buddy: nil, plus: true) { kb in
            XCTAssertNil(kb.buddy)
            XCTAssertFalse(kb.subviews.contains { $0 is BuddyView })
        }
        try withKeyboard(buddy: "cat", plus: false) { kb in
            XCTAssertNil(kb.buddy, "chưa Plus ⇒ không tạo")
            XCTAssertFalse(kb.subviews.contains { $0 is BuddyView })
        }
        try withKeyboard(buddy: "cat", plus: true) { kb in
            let b = try XCTUnwrap(kb.buddy)
            XCTAssertTrue(b.superview === kb)
            XCTAssertFalse(b.isUserInteractionEnabled, "không nhận chạm")
            UserDefaultsProvider.shared?.set("off", forKey: BuddyCharacter.key)
            kb.applyAppearance(.light, style: .light)
            XCTAssertNil(kb.buddy)
            XCTAssertFalse(kb.subviews.contains { $0 is BuddyView })
        }
    }

    /// Ô nhân vật (sát mép phải) không bao giờ chồng chip gợi ý / 📋 / 😊, chỉ tràn xuống hàng phím đầu — điện thoại dọc,
    /// ngang, iPad.
    @MainActor func testLayoutNeverOverlapsChipsOrKeys() throws {
        let sizes: [(CGFloat, CGFloat)] = [(320, 260), (375, 260), (390, 300), (430, 300), (667, 200), (844, 200),
                                           (932, 210), (768, 320), (1024, 360), (1366, 400)]
        for (w, h) in sizes {
            for emojiTop in [false, true] {
                try withKeyboard(buddy: "girl", plus: true, width: w, height: h, emojiTop: emojiTop) { kb in
                    let b = try XCTUnwrap(kb.buddy)
                    let s = kb.debugStripLayout()
                    XCTAssertFalse(b.isHidden, "\(w)")
                    let f = b.frame
                    XCTAssertGreaterThan(f.width, 0)
                    XCTAssertTrue(f.contains(KeyboardView.buddyZoneFrame(width: kb.bounds.width, strip: f.height / (1 + KeyboardView.buddyOverlapRatio)).insetBy(dx: 0.5, dy: 0.5)))
                    XCTAssertGreaterThanOrEqual(b.layer.zPosition, 1000, "nhân vật trên cùng")
                    // Ô chừa (không phải khung vẽ) không chồng chip gợi ý / 📋 / 😊.
                    // Khung vẽ (rộng hơn ô) bị kẹp trong mép phải nên không canh giữa ô — lấy ô từ hàm thuần.
                    let zoneF = CGRect(x: kb.bounds.width - KeyboardView.buddyZoneWidth, y: 0,
                                       width: KeyboardView.buddyZoneWidth, height: s.bar.height)
                    XCTAssertFalse(zoneF.intersects(s.bar), "\(w)×\(h): đè thanh gợi ý \(f) vs \(s.bar)")
                    for c in s.cells { XCTAssertFalse(zoneF.intersects(c), "\(w): đè ô gợi ý") }
                    // Không còn ⌄: ô chừa nằm sát mép phải, khung vẽ không vượt mép phải bàn phím.
                    XCTAssertEqual(KeyboardView.buddyZoneFrame(width: kb.bounds.width, strip: 40).maxX,
                                   kb.bounds.width, accuracy: 0.5, "\(w)")
                    XCTAssertLessThanOrEqual(f.maxX, kb.bounds.width + 0.5, "\(w): vẽ tràn mép phải")
                    XCTAssertEqual(max(s.bar.maxX, s.clip?.maxX ?? 0, kb.debugEmojiBarButton?.frame.maxX ?? 0),
                                   kb.bounds.width - KeyboardView.buddyZoneWidth, accuracy: 0.5, "\(w): sát ô nhân vật")
                    if let c = s.clip { XCTAssertFalse(zoneF.intersects(c), "\(w): đè 📋") }
                    if let e = kb.debugEmojiBarButton { XCTAssertFalse(zoneF.intersects(e.frame), "\(w): đè 😊") }
                    // Được tràn xuống hàng phím đầu (không nhận chạm), nhưng không quá ~2/3 strip.
                    let strip = f.height / (1 + KeyboardView.buddyOverlapRatio)
                    XCTAssertLessThanOrEqual(f.maxY - kb.keyAreaFrame.minY, 0.7 * strip, "\(w)×\(h): tràn quá sâu")
                    XCTAssertTrue(b.clipsToBounds, "nhân vật không vẽ ra ngoài ô")
                    // Nhân vật cao gần bằng thanh (~30–44 pt), nằm trọn trong ô.
                    // Dọc nằm trọn trong ô (ngang: lề trong suốt của ô ảnh được cắt bởi clipsToBounds).
                    XCTAssertGreaterThanOrEqual(b.figureFrame.minY, -0.5, "\(w): \(b.figureFrame)")
                    XCTAssertLessThanOrEqual(b.figureFrame.maxY, b.bounds.maxY + 0.5, "\(w): \(b.figureFrame)")
                    XCTAssertEqual(b.figureFrame.midX, b.bounds.midX, accuracy: 0.5)
                    XCTAssertGreaterThanOrEqual(b.figureFrame.height, min(26, b.bounds.height - 2), "\(w): nhân vật quá nhỏ")
                }
            }
        }
        // Hàm thuần.
        // Ô chừa sát mép phải; khung vẽ 66 rộng hơn ô 34 ⇒ kẹp lại trong mép phải.
        XCTAssertEqual(KeyboardView.buddyZoneFrame(width: 390, strip: 40),
                       CGRect(x: 390 - 34, y: 0, width: 34, height: 40))
        XCTAssertEqual(KeyboardView.buddyFrame(width: 390, strip: 40),
                       CGRect(x: 390 - 66, y: 0, width: 66, height: 66))
        // Nhân vật to hơn strip: tràn xuống hàng phím (Phil 20/10: "bé quá", cho đè lên phím dưới).
        let tall = BuddyView(character: .boy, bar: BuddyHalo.systemLight, lowPower: true)
        tall.frame = KeyboardView.buddyFrame(width: 390, strip: 40)
        tall.layoutIfNeeded()
        XCTAssertGreaterThan(tall.figureFrame.height, 40, "nhân vật phải cao hơn thanh gợi ý")
        XCTAssertEqual(tall.figureFrame.minY, 0, accuracy: 0.5, "đầu chạm trần thanh gợi ý")
        XCTAssertFalse(tall.isUserInteractionEnabled, "phần tràn không được chặn chạm phím")
        XCTAssertEqual(KeyboardView.emojiBarFrame(width: 390, strip: 36, clip: false, buddy: 34).maxX, 390 - 34)
    }

    /// Tắt thanh / plane emoji ⇒ nhân vật ẩn (không chỗ, không đè lưới emoji).
    @MainActor func testHiddenWhenBarOffOrEmoji() throws {
        try withKeyboard(buddy: "chick", plus: true) { kb in
            let b = try XCTUnwrap(kb.buddy)
            kb.setSuggestionsEnabled(false); kb.layoutIfNeeded()
            XCTAssertTrue(b.isHidden)
            kb.setSuggestionsEnabled(true); kb.layoutIfNeeded()
            XCTAssertFalse(b.isHidden)
            kb.debugShowEmojiPlane(); kb.layoutIfNeeded()
            XCTAssertTrue(b.isHidden)
        }
    }

    /// Gõ phím thật trên KeyboardView: nhân vật thức dậy và nhảy (lượt sau); chữ vẫn chèn.
    @MainActor func testTypingWakesBuddy() throws {
        try withKeyboard(buddy: "boy", plus: true) { kb in
            let b = try XCTUnwrap(kb.buddy)
            XCTAssertEqual(b.shown, .asleep(zzz: false))
            let f = try XCTUnwrap(kb.debugLetterFrame("a"))
            kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: 1)
            XCTAssertEqual(b.shown, .asleep(zzz: false), "đường phím không đụng layer")
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(b.shown, .dancing(0))
        }
    }

    // MARK: Phản ứng theo từ (giận / thả tim / cười / ngạc nhiên / buồn) + hoảng khi xoá dồn

    func testReactionMatching() {
        let love = ["yêu", "Yêu", "YÊU", "yeu", "iu", "thương", "thuong", "love", "LOVE!", "luv", "miss", "thích",
                    "thich", "crush", "tim", "hun", "honey", "baby", "nhớ", "cưng", "thơm", "muah"]
        for w in love { XCTAssertEqual(BuddyWords.reaction(word: w, prev: nil), .love, w) }
        let laugh = ["haha", "hahaha", "HAHAHAHA", "hahah", "hihi", "hihihi", "hehe", "kkk", "kkkkkkk", "kaka", "lol",
                     "lmao", "=))", "=)))))", ":))", "😂", "hjhjhj"]
        for w in laugh { XCTAssertEqual(BuddyWords.reaction(word: w, prev: nil), .laugh, w) }
        let surprised = ["wow", "woooow", "WOW!", "ôi", "omg", "omggg", "ủa", "hả", "what", "ồ", "á"]
        for w in surprised { XCTAssertEqual(BuddyWords.reaction(word: w, prev: nil), .surprised, w) }
        XCTAssertEqual(BuddyWords.reaction(word: "ơi", prev: "trời"), .surprised, "cụm trời ơi")
        let sad = ["buồn", "buon", "khóc", "huhu", "huhuhu", "hic", "hichic", "hix", "sad", ":(", ":(((", "chán", "😭"]
        for w in sad { XCTAssertEqual(BuddyWords.reaction(word: w, prev: nil), .sad, w) }
        XCTAssertEqual(BuddyWords.reaction(word: "mỏi", prev: "mệt"), .sad)
        // strict: bỏ dấu thành từ khác ⇒ chỉ khớp đúng dấu; từ thường ⇒ không.
        for w in ["nho", "nhỏ", "cung", "thom", "chan", "a", "o", "ha", "an", "anh", "bàn", "trời", "k", "kk", "hah", ""] {
            XCTAssertNil(BuddyWords.reaction(word: w, prev: nil), w)
        }
        XCTAssertNil(BuddyWords.reaction(word: String(repeating: "a", count: 30), prev: nil))
    }

    /// Giận dùng ĐÚNG các bảng của bộ lọc gợi ý (từ / cặp / bộ ba) — không phụ thuộc công tắc lọc (không nhận tham số).
    func testAngryUsesSensitiveTables() throws {
        let bad = try XCTUnwrap(SensitiveWords.set.sorted().first)
        XCTAssertEqual(BuddyWords.reaction(word: bad, prev: nil), .angry)
        XCTAssertEqual(BuddyWords.reaction(word: bad.uppercased() + "!", prev: nil), .angry)
        // Cặp: tìm một cặp trong bảng.
        let pair = try XCTUnwrap(SensitiveWords.pairs.first(where: { !$0.value.isEmpty }))
        let w2 = try XCTUnwrap(pair.value.sorted().first)
        if !SensitiveWords.set.contains(w2) {
            XCTAssertEqual(BuddyWords.reaction(word: w2, prev: pair.key), .angry, "cặp \(pair.key) \(w2)")
            XCTAssertNotEqual(BuddyWords.reaction(word: w2, prev: "xyz"), .angry)
        }
        // "wtf" vừa tục vừa ngạc nhiên ⇒ giận thắng.
        XCTAssertEqual(BuddyWords.reaction(word: "wtf", prev: nil), .angry)
        // Từ yêu thương sau từ tục: cặp không tục ⇒ vẫn thả tim (giận chỉ theo từ VỪA chốt / cặp / bộ ba).
        XCTAssertEqual(BuddyWords.reaction(word: "yêu", prev: "anh"), .love)
    }

    func testReactionPriorityOrder() {
        XCTAssertEqual(BuddyReaction.allCases.prefix(5), [.angry, .love, .laugh, .surprised, .sad])
        for r in BuddyReaction.allCases { XCTAssertGreaterThanOrEqual(r.duration, 0.8); XCTAssertLessThanOrEqual(r.duration, 1.5) }
    }

    func testGrawlixDeterministicSymbolsOnly() {
        let a = BuddyWords.grawlix(seed: 7), b = BuddyWords.grawlix(seed: 7)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 4)
        var distinct = Set<String>()
        for s in 0..<50 {
            let g = BuddyWords.grawlix(seed: s)
            XCTAssertTrue(g.allSatisfy { BuddyWords.grawlixSymbols.contains($0) }, g)
            distinct.insert(g)
        }
        XCTAssertGreaterThan(distinct.count, 10)
        XCTAssertEqual(BuddyWords.grawlix(seed: 1), Self.grawlixSeed1, "số chung với Android")
    }
    static let grawlixSeed1 = "%&*#"

    func testReactionStateMachine() {
        // Đang ngủ ⇒ giật mình thức, diễn xong ngủ tiếp (mốc ngủ giữ nguyên, không z z lại).
        var b = BuddyBrain()
        b.press(at: -5)
        XCTAssertEqual(b.phase(at: 10), .asleep(zzz: false))
        b.react(.love, at: 10)
        XCTAssertEqual(b.phase(at: 10.5), .react(.love))
        XCTAssertEqual(b.nextDeadline(after: 10.5)!, 11.2, accuracy: 1e-9)
        XCTAssertEqual(b.phase(at: 11.21), .asleep(zzz: false))
        XCTAssertNil(b.nextDeadline(after: 11.21))
        // Đang nhảy ⇒ phản ứng rồi về nhảy.
        var t = 20.0
        for _ in 0..<12 { b.press(at: t); t += 0.15 }
        b.react(.angry, at: t)
        XCTAssertEqual(b.phase(at: t + 0.1), .react(.angry))
        for k in 0..<10 { b.press(at: t + 0.15 * Double(k + 1)) }
        XCTAssertEqual(b.phase(at: t + 1.21), .dancing(b.tier))
        // Liên tiếp ⇒ diễn lại từ đầu (không chồng); MỚI NHẤT thắng (giận rồi thả tim ⇒ thả tim).
        let s0 = b.reactSerial
        b.react(.love, at: 50); b.react(.love, at: 50.5)
        XCTAssertEqual(b.reactSerial, s0 + 2)
        XCTAssertEqual(b.phase(at: 51.6), .react(.love))
        b.react(.angry, at: 51.65)
        XCTAssertEqual(b.phase(at: 51.7), .react(.angry))
        b.react(.love, at: 51.8)
        XCTAssertEqual(b.phase(at: 51.9), .react(.love))
        XCTAssertNotEqual(b.phase(at: 53.01), .react(.love))
        // Mới mở bàn phím (chưa gõ) cũng phản ứng được, xong ngủ yên.
        var c = BuddyBrain()
        c.react(.sad, at: 1)
        XCTAssertEqual(c.phase(at: 1.1), .react(.sad))
        XCTAssertEqual(c.phase(at: 2.6), .asleep(zzz: false))
        XCTAssertEqual(BuddyPolicy.visual(.react(.laugh), lowPower: true), .awake)
        for r in BuddyReaction.allCases where r != .panic {
            for s in [BuddyRig.girl.style, BuddyRig.cat.style] {
                XCTAssertEqual(BuddyDance.react(r, s, f: 0), .rest, "\(r) bắt đầu ở dáng nghỉ")
                XCTAssertEqual(BuddyDance.react(r, s, f: 1).armL, 0, accuracy: 1e-9, "\(r) về dáng nghỉ")
            }
        }
        XCTAssertLessThan(BuddyDance.react(.love, BuddyRig.girl.style, f: 0.5).armL, 0, "tay khép ôm tim")
        XCTAssertGreaterThan(BuddyDance.react(.panic, BuddyRig.girl.style, f: 0.5).armL, 2, "ôm đầu")
    }

    /// Xoá dồn: > 8 phím ⌫ liên tiếp ⇒ hoảng, kéo dài tới 0,8 s sau phím cuối (không diễn lại mỗi phím);
    /// phím chữ / ngắt quãng ⇒ đếm lại.
    func testDeletePanicCounter() {
        var b = BuddyBrain()
        var t = 5.0
        for i in 1...8 { b.delete(at: t); XCTAssertNotEqual(b.phase(at: t), .react(.panic), "\(i)"); t += 0.09 }
        b.delete(at: t)
        XCTAssertEqual(b.phase(at: t), .react(.panic))
        let serial = b.reactSerial
        for _ in 0..<20 { t += 0.09; b.delete(at: t) }
        XCTAssertEqual(b.reactSerial, serial, "giữ ⌫ không diễn lại mỗi phím")
        XCTAssertEqual(b.phase(at: t + 0.79), .react(.panic))
        XCTAssertNotEqual(b.phase(at: t + 0.81), .react(.panic), "thôi xoá 0,8 s ⇒ hết hoảng")
        // Phím chữ xen giữa ⇒ đếm lại.
        t += 5
        for _ in 0..<6 { b.delete(at: t); t += 0.09 }
        b.press(at: t); t += 0.09
        for _ in 0..<6 { b.delete(at: t); t += 0.09 }
        XCTAssertNotEqual(b.phase(at: t - 0.09), .react(.panic))
        // Ngắt quãng > 0,5 s ⇒ đếm lại.
        t += 1
        for _ in 0..<6 { b.delete(at: t); t += 0.09 }
        t += 0.6
        for _ in 0..<6 { b.delete(at: t); t += 0.09 }
        XCTAssertNotEqual(b.phase(at: t - 0.09), .react(.panic))
    }

    func testFXParticlesCappedAndConfined() {
        let r = BuddyFX.particleSize / 2
        for re in BuddyReaction.allCases {
            XCTAssertLessThanOrEqual(BuddyFX.count(re), BuddyFX.maxParticles)
            for (w, h) in [(34.0, 30.0), (34.0, 40.0), (34.0, 46.0), (120.0, 96.0)] {
                for i in 0..<BuddyFX.count(re) {
                    let p = BuddyFX.particle(re, i, width: w, height: h)
                    for (x, y) in [(p.x0, p.y0), (p.x1, p.y1)] {
                        XCTAssertTrue(x - r >= 0 && x + r <= w && y - r >= 0 && y + r <= h, "\(re) \(w)×\(h) #\(i): \(p)")
                    }
                }
                if let b = BuddyFX.badge(re, width: w, height: h) {
                    XCTAssertTrue(b.x >= 0 && b.y >= 0 && b.x + b.w <= w && b.maxY <= h, "\(re) biển \(b)")
                }
            }
        }
        XCTAssertLessThanOrEqual(BuddyFX.maxParticles, 8)
        // Số chung với Android.
        let p = BuddyFX.particle(.love, 3, width: 34, height: 40)
        XCTAssertEqual(p.x1, 22.4, accuracy: 0.01)
        XCTAssertEqual(p.y1, 3.5, accuracy: 0.01)
    }

    @MainActor func testReactionViewRestartsWithoutStackingAndReturns() {
        let clock = Clock()
        let v = makeView(.cat, clock: clock)
        v.wordCommitted("bàn", prev: nil)
        v.tick()
        XCTAssertEqual(v.shown, .asleep(zzz: false), "từ thường: không gì")
        for w in ["yêu", "yêu", "haha", "buồn", "wow", "yêu"] {
            clock.t += 0.2
            v.wordCommitted(w, prev: nil)
            v.tick()
            guard case .react = v.shown else { return XCTFail(w) }
            XCTAssertLessThanOrEqual(v.fxParticles.count, BuddyFX.maxParticles)
            for h in v.fxParticles { XCTAssertLessThanOrEqual(h.animationKeys()?.count ?? 0, 1, "không chồng") }
        }
        XCTAssertTrue(v.heartPropVisible)
        let layers = v.layerCount
        clock.t += 1.3; v.tick()
        XCTAssertEqual(v.shown, .asleep(zzz: false), "ngủ tiếp")
        XCTAssertFalse(v.heartPropVisible)
        XCTAssertEqual(v.runningAnimationCount, 0)
        XCTAssertEqual(v.layerCount, layers)
        for h in v.fxParticles { XCTAssertTrue(v.bounds.contains(h.frame), "hạt trong ô: \(h.frame)") }
        // Giận: mặt đỏ + bong bóng ký hiệu trong ô.
        let bad = SensitiveWords.set.sorted().first!
        clock.t += 1; v.wordCommitted(bad, prev: nil); v.tick()
        XCTAssertEqual(v.shown, .react(.angry))
        XCTAssertTrue(v.angryFaceVisible)
        let bubble = try! XCTUnwrap(v.fxBadgeFrame)
        XCTAssertTrue(v.bounds.contains(bubble), "bong bóng trong ô")
        XCTAssertTrue((v.fxBadgeText ?? "").allSatisfy { BuddyWords.grawlixSymbols.contains($0) })
        clock.t += 1.3; v.tick()
        XCTAssertFalse(v.angryFaceVisible)
        XCTAssertNil(v.fxBadgeText)
        XCTAssertEqual(v.runningAnimationCount, 0)
        // Hoảng khi xoá dồn rồi hết sau 0,8 s.
        for _ in 0..<12 { clock.t += 0.09; v.deletePressed() }
        v.tick()
        XCTAssertEqual(v.shown, .react(.panic))
        XCTAssertLessThanOrEqual(v.fxParticles.count, BuddyFX.maxParticles)
        clock.t += 0.85; v.tick()
        XCTAssertNotEqual(v.shown, .react(.panic))
        v.halt()
    }

    // MARK: Trang phục theo mùa

    func testSeasonResolution() {
        // Ngày cố định theo bảng âm lịch nhúng.
        XCTAssertEqual(BuddySeason.of(year: 2026, month: 2, day: 17), .tet)       // mùng 1 Tết Bính Ngọ
        XCTAssertEqual(BuddySeason.of(year: 2026, month: 2, day: 7), .tet)        // −10
        XCTAssertNil(BuddySeason.of(year: 2026, month: 2, day: 6))                // −11
        XCTAssertEqual(BuddySeason.of(year: 2026, month: 2, day: 24), .tet)       // +7
        XCTAssertNil(BuddySeason.of(year: 2026, month: 2, day: 25))
        XCTAssertEqual(BuddySeason.of(year: 2028, month: 1, day: 16), .tet)       // Tết 26/1/2028 −10
        XCTAssertEqual(BuddySeason.of(year: 2026, month: 9, day: 25), .midAutumn) // Rằm tháng Tám
        XCTAssertEqual(BuddySeason.of(year: 2026, month: 9, day: 20), .midAutumn)
        XCTAssertNil(BuddySeason.of(year: 2026, month: 9, day: 19))
        XCTAssertEqual(BuddySeason.of(year: 2028, month: 10, day: 8), .midAutumn) // 3/10/2028 +5
        XCTAssertEqual(BuddySeason.of(year: 2026, month: 12, day: 15), .christmas)
        XCTAssertEqual(BuddySeason.of(year: 2026, month: 12, day: 26), .christmas)
        XCTAssertNil(BuddySeason.of(year: 2026, month: 12, day: 27))
        XCTAssertEqual(BuddySeason.of(year: 2026, month: 10, day: 25), .halloween)
        XCTAssertEqual(BuddySeason.of(year: 2026, month: 11, day: 1), .halloween)
        XCTAssertNil(BuddySeason.of(year: 2026, month: 11, day: 2))
        XCTAssertNil(BuddySeason.of(year: 2026, month: 7, day: 1))
        XCTAssertEqual(BuddySeason.lunarNewYear.count, 10)
        XCTAssertEqual(BuddySeason.midAutumnDay.count, 10)
        XCTAssertEqual(BuddySeason.dayNumber(1970, 1, 1), 0)
        XCTAssertEqual(BuddySeason.dayNumber(2026, 10, 19), 20745)
    }

    func testOutfitByThemeThenDate() {
        XCTAssertEqual(BuddySeason.resolve(themeID: "tetMai", year: 2026, month: 7, day: 1), .tet, "theme thắng ngày")
        XCTAssertEqual(BuddySeason.resolve(themeID: "xmasSnow", year: 2026, month: 2, day: 17), .christmas)
        XCTAssertEqual(BuddySeason.resolve(themeID: "halloween", year: 2026, month: 7, day: 1), .halloween)
        XCTAssertEqual(BuddySeason.resolve(themeID: "trungthu", year: 2026, month: 7, day: 1), .midAutumn)
        XCTAssertEqual(BuddySeason.resolve(themeID: "system", year: 2026, month: 12, day: 20), .christmas, "theme thường ⇒ theo ngày")
        XCTAssertNil(BuddySeason.resolve(themeID: "oled", year: 2026, month: 7, day: 1))
        for c in BuddyCharacter.allCases where c != .off {
            XCTAssertTrue(BuddyOutfit.make(nil, c).pieces.isEmpty)
            for s in BuddySeason.allCases {
                let o = BuddyOutfit.make(s, c)
                XCTAssertFalse(o.pieces.isEmpty && o.recolor.isEmpty, "\(c) \(s) có trang phục")
            }
        }
        XCTAssertEqual(BuddyOutfit.make(.tet, .girl).recolor[0xFFB3C7], BuddyOutfit.red, "áo dài đỏ")
        XCTAssertTrue(BuddyOutfit.make(.midAutumn, .boy).pieces.filter { $0.part != .sleep }.allSatisfy { $0.part == .armR }, "lồng đèn theo tay")
    }

    @MainActor func testOutfitViewIsStaticNoExtraAnimations() {
        let clock = Clock()
        let plain = makeView(.girl, clock: clock)
        let v = BuddyView(character: .girl, bar: BuddyHalo.systemLight, lowPower: false, season: .christmas, artStyle: .vector)
        v.clock = { clock.t }
        v.frame = plain.frame
        v.layoutIfNeeded()
        XCTAssertGreaterThan(v.outfitPieceCount, 0)
        // Both are seasonal vector views; neither adds animation for its costume.
        XCTAssertEqual(v.layerCount, plain.layerCount)
        XCTAssertEqual(v.runningAnimationCount, 0)
    }

    // MARK: Ảnh xem trước (chỉ khi đặt VT_BUDDY_SHOTS=<thư mục>)

    @MainActor func testSavePreviewShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["VT_BUDDY_SHOTS"], !dir.isEmpty else {
            throw XCTSkip("đặt TEST_RUNNER_VT_BUDDY_SHOTS để lưu ảnh")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Nền thanh thật: tối (OLED, Kính tối, Neon) + sáng (Hệ thống sáng, Đào/pastel).
        let bars: [(String, KeyboardTheme, Bool)] = [("oled", .oled, true), ("glass-dark", .glass, true), ("neon", .neon, true),
                                                      ("system-light", .system, false), ("peach", .peach, false)]
        for (tag, theme, sysDark) in bars {
            let pal = theme.palette(systemDark: sysDark)
            let bar = pal.buddyBar
            for c in BuddyCharacter.allCases where c != .off {
                let style = BuddyRig.rig(c)!.style
                for (name, pose) in [("asleep", nil), ("dance", BuddyDance.pose(style, tier: 3, p: 0.125)),
                                     ("love", BuddyDance.react(.love, style, f: 0.5)),
                                     ("angry", BuddyDance.react(.angry, style, f: 0.3)),
                                     ("bar", BuddyDance.pose(style, tier: 2, p: 0.3))] as [(String, BuddyPose?)] {
                    let big = name != "bar"
                    let size = big ? CGSize(width: 200, height: 220) : CGSize(width: 34, height: 40)
                    let host = UIView(frame: CGRect(origin: .zero, size: size))
                    host.backgroundColor = UIColor(red: CGFloat((bar >> 16) & 0xFF) / 255, green: CGFloat((bar >> 8) & 0xFF) / 255,
                                                   blue: CGFloat(bar & 0xFF) / 255, alpha: 1)
                    let v = BuddyView(character: c, bar: bar, lowPower: false, framing: .full)
                    v.maxFigureHeight = big ? 200 : 44
                    v.frame = host.bounds
                    host.addSubview(v)
                    v.debugPose(pose, dance: name != "angry", heart: name == "love", angry: name == "angry")
                    let img = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 3; return f }())
                        .image { ctx in host.layer.render(in: ctx.cgContext) }
                    try img.pngData()!.write(to: URL(fileURLWithPath: "\(dir)/\(tag)-\(c.rawValue)-\(name).png"))
                }
            }
        }
    }

    // MARK: Tương phản (Phil: chân mảnh lẫn vào nền tối)

    /// Mọi theme dựng sẵn (sáng + tối): quầng nhân vật tương phản ≥ 3:1 với nền thanh.
    func testHaloContrastOnEveryTheme() {
        for t in KeyboardTheme.allCases {
            for sysDark in [false, true] {
                let bar = t.palette(systemDark: sysDark).buddyBar
                let tones = BuddyHalo.colors(bar: bar)
                let c = BuddyHalo.contrast(tones.halo, bar)
                XCTAssertGreaterThanOrEqual(c, 3, "\(t.rawValue) \(sysDark ? "tối" : "sáng"): quầng \(String(tones.halo, radix: 16)) / nền \(String(bar, radix: 16)) = \(c)")
            }
        }
        XCTAssertTrue(BuddyHalo.colors(bar: 0x000000).darkBar)
        XCTAssertEqual(BuddyHalo.colors(bar: 0x000000).halo, BuddyHalo.light)
        XCTAssertEqual(BuddyHalo.colors(bar: 0xFFFFFF).halo, BuddyHalo.dark)
        XCTAssertEqual(BuddyHalo.colors(bar: 0xFFFFFF).outline, 0x3A2A2A)
    }

    /// Chân / tay là hình TÔ (không phải nét đậm trơn) và đủ dày ở cỡ thanh (~38 pt cao): ≥ 2,5 pt.
    func testLimbsAreFilledAndThickEnough() {
        for c in BuddyCharacter.allCases where c != .off {
            let r = BuddyRig.rig(c)!
            let pt = 38 / r.full.h
            for part in [BuddyPart.legL, .legR, .armL, .armR] {
                let ps = r.pieces.filter { $0.part == part }
                // Nét viền trơn phải đi cặp với nét màu cùng đường (chi = viền + ruột màu).
                for p in ps where p.fill == nil && p.stroke == .outline {
                    guard case .path(let d) = p.shape else { continue }
                    XCTAssertTrue(ps.contains { q in
                        if case .path(let e) = q.shape, e == d, case .color = q.stroke { return true }
                        return false
                    }, "\(c) \(part): nét đậm trơn \(d)")
                }
                var thick = 0.0
                for p in ps {
                    if p.fill == nil { thick = max(thick, p.width) }
                    else if case .path(let d) = p.shape {
                        let n = BuddySVG.numbers(d)
                        let xs = stride(from: 0, to: n.count - 1, by: 2).map { n[$0] }, ys = stride(from: 1, to: n.count, by: 2).map { n[$0] }
                        if let a = xs.min(), let b = xs.max(), let y0 = ys.min(), let y1 = ys.max(), y1 - y0 > 30 {
                            thick = max(thick, min(b - a, y1 - y0) * 0.6)   // ống quần: bề ngang trung bình ≈ 0,6 hộp
                        }
                    }
                }
                XCTAssertGreaterThanOrEqual(thick * pt, 2.5, "\(c) \(part): \(thick * pt) pt")
            }
        }
    }

    // Shared holiday cases and move fixtures below are identical to Android. Intentionally not run here.
    func testHolidayNamesWorkYearRoundAndFold() {
        let cases: [(String, BuddyReaction)] = [
            ("lì xì", .luckyMoney),
            ("mừng tuổi", .luckyMoney),
            ("tết", .luckyMoney),
            ("năm mới", .luckyMoney),
            ("chúc mừng năm mới", .luckyMoney),
            ("vạn sự như ý", .luckyMoney),
            ("happy new year", .luckyMoney),
            ("giáng sinh", .gift),
            ("noel", .gift),
            ("merry christmas", .gift),
            ("xmas", .gift),
            ("ông già noel", .gift),
            ("halloween", .candy),
            ("trick or treat", .candy),
            ("trung thu", .mooncake),
            ("bánh trung thu", .mooncake),
            ("rước đèn", .mooncake),
            ("đèn ông sao", .mooncake),
            ("chị hằng", .mooncake),
        ]
        for (phrase, reaction) in cases {
            for text in [phrase, BuddyWords.fold(phrase).uppercased()] {
                let tokens = text.split(separator: " ").map(String.init).reversed().map { $0 }
                XCTAssertEqual(BuddyWords.reaction(word: tokens[0] + "!", prev: tokens.count > 1 ? tokens[1] : nil,
                    prev2: tokens.count > 2 ? tokens[2] : nil, prev3: tokens.count > 3 ? tokens[3] : nil), reaction, text)
            }
        }
        XCTAssertNil(BuddyWords.holiday(word: "ý", prev: "như", prev2: "sự"))
        XCTAssertNil(BuddyWords.holiday(word: "christmas", prev: nil))
        XCTAssertNil(BuddyWords.holiday(word: "noelish", prev: nil))
        XCTAssertNil(BuddyWords.holiday(word: "", prev: "noel"))
    }

    func testHolidayGenericSeasonGatesAndAccents() {
        let cases: [(String, BuddySeason, BuddyReaction, Bool)] = [
            ("quà", .christmas, .gift, true),
            ("kẹo", .halloween, .candy, true),
            ("bí ngô", .halloween, .candy, false),
            ("cuội", .midAutumn, .mooncake, true),
            ("an khang", .tet, .luckyMoney, false),
            ("phát tài", .tet, .luckyMoney, false),
        ]
        for (phrase, active, reaction, strict) in cases {
            let tokens = phrase.split(separator: " ").map(String.init).reversed().map { $0 }
            let word = tokens[0], prev = tokens.count > 1 ? tokens[1] : nil
            XCTAssertNil(BuddyWords.holiday(word: word, prev: prev))
            for season in BuddySeason.allCases {
                XCTAssertEqual(BuddyWords.holiday(word: word, prev: prev, season: season), season == active ? reaction : nil)
            }
            XCTAssertEqual(BuddyWords.holiday(word: BuddyWords.fold(word), prev: prev.map(BuddyWords.fold), season: active), strict ? nil : reaction)
        }
        XCTAssertNil(BuddyWords.reaction(word: "qua", prev: nil, season: .christmas))
        XCTAssertNil(BuddyWords.reaction(word: "keo", prev: nil, season: .halloween))
        XCTAssertEqual(BuddyWords.reaction(word: "noelll", prev: nil), .gift)
    }

    func testAccessoriesHaveSmallBudgetsAndBothPoses() {
        for c in BuddyCharacter.allCases where c != .off {
            for season in BuddySeason.allCases {
                let outfit = BuddyOutfit.make(season, c)
                for sleeping in [false, true] {
                    let pieces = outfit.pieces.filter { ($0.part == .sleep) == sleeping }
                    XCTAssertFalse(pieces.isEmpty)
                    XCTAssertLessThanOrEqual(pieces.count, 8)
                    XCTAssertTrue(pieces.allSatisfy { $0.width <= 3.2 })
                }
            }
            for reaction in BuddyReaction.allCases where reaction.isHoliday {
                let pieces = BuddyProp.make(reaction, BuddyRig.rig(c)!)
                XCTAssertFalse(pieces.isEmpty)
                XCTAssertLessThanOrEqual(pieces.count, 8)
                XCTAssertTrue(pieces.allSatisfy { $0.part == .body && $0.width <= 3.2 })
                XCTAssertEqual(reaction.duration, 1.5)
                XCTAssertEqual(BuddyFX.count(reaction), 0)
            }
            XCTAssertTrue(BuddyProp.make(.love, BuddyRig.rig(c)!).isEmpty)
        }
    }

    func testNamedMovesNeutralAndSelection() {
        for c in BuddyCharacter.allCases where c != .off {
            let style = BuddyRig.rig(c)!.style
            for tier in 0...3 {
                for move in BuddyDance.Move.allCases {
                    XCTAssertEqual(BuddyDance.pose(style, tier: tier, p: 0, move: move), .rest)
                    XCTAssertEqual(BuddyDance.pose(style, tier: tier, p: 1, move: move), .rest)
                    if tier < 3 || move != .spin {
                        XCTAssertTrue((0..<48).allSatisfy { BuddyDance.pose(style, tier: tier, p: Double($0)/48, move: move).sx == 1 })
                    }
                }
                let pool = BuddyDance.moves(tier)
                XCTAssertEqual(pool.count, tier == 3 ? 5 : 4)
                XCTAssertEqual(pool.contains(.spin), tier == 3)
                XCTAssertEqual(pool.contains(.skip), tier >= 2)
                XCTAssertEqual(pool.contains(.bounce), tier < 2)
                for seed in [0, 1, 42, -7, Int.max] {
                    for group in 0..<100 {
                        let a = BuddyDance.move(c, tier: tier, loopIndex: group * 2, seed: seed)
                        XCTAssertTrue(pool.contains(a))
                        XCTAssertEqual(a, BuddyDance.move(c, tier: tier, loopIndex: group * 2 + 1, seed: seed))
                        XCTAssertNotEqual(a, BuddyDance.move(c, tier: tier, loopIndex: (group + 1) * 2, seed: seed))
                    }
                }
            }
        }
        XCTAssertEqual((0..<10).map { BuddyDance.move(.girl, tier: 3, loopIndex: $0, seed: 42) },
                       [.spin, .spin, .chicken, .chicken, .dab, .dab, .flossLite, .flossLite, .skip, .skip])
    }

    func testNamedMovePoseParity() {
        let expected: [[Double]] = [
            [5.656854, -9.000000, -0.100000, -0.120000, 2.000000, -2.600000, 0.000000, -0.600000, 0.000000, 1.000000], // bounce p=0.375
            [-5.656854, -9.000000, -0.100000, -0.120000, 2.000000, -2.600000, 0.000000, -0.600000, 0.000000, 1.000000], // bounce p=0.875
            [5.656854, 0.000000, 0.127279, -0.070711, -0.450000, 0.450000, 0.000000, 0.000000, 0.000000, 1.000000], // hipSway p=0.375
            [-5.656854, 0.000000, -0.127279, 0.070711, -0.450000, 0.450000, 0.000000, 0.000000, 0.000000, 1.000000], // hipSway p=0.875
            [0.000000, -3.150000, 0.000000, 0.084853, 0.250000, -2.100000, 0.000000, 0.000000, 0.000000, 1.000000], // wave p=0.375
            [0.000000, -3.150000, 0.000000, -0.084853, 0.250000, -2.100000, 0.000000, 0.000000, 0.000000, 1.000000], // wave p=0.875
            [0.000000, -2.250000, 0.000000, 0.080000, -1.050000, 1.050000, 0.000000, 0.000000, 0.000000, 1.000000], // clap p=0.375
            [0.000000, -2.250000, 0.000000, 0.080000, -1.050000, 1.050000, 0.000000, 0.000000, 0.000000, 1.000000], // clap p=0.875
            [0.000000, -2.700000, -0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000000, 1.000000], // dab p=0.375
            [0.000000, -2.700000, -0.180000, 0.650000, 2.500000, 0.900000, 0.000000, 0.000000, 0.000000, 1.000000], // dab p=0.875
            [3.394113, -13.500000, 0.056569, 0.000000, 0.424264, 0.424264, 0.636396, -0.000000, 0.000000, 1.000000], // skip p=0.375
            [-3.394113, -13.500000, -0.056569, 0.000000, -0.424264, -0.424264, 0.000000, -0.636396, 0.000000, 1.000000], // skip p=0.875
            [-5.656854, 0.000000, -0.098995, 0.084853, 0.601041, 0.601041, 0.000000, 0.000000, 0.000000, 1.000000], // flossLite p=0.375
            [5.656854, 0.000000, 0.098995, -0.084853, -0.601041, -0.601041, 0.000000, 0.000000, 0.000000, 1.000000], // flossLite p=0.875
            [5.656854, -9.000000, -0.100000, -0.120000, 2.000000, -2.600000, 0.000000, -0.600000, 0.000000, 1.000000], // spin p=0.375
            [-5.656854, -9.000000, -0.100000, -0.120000, 2.000000, -2.600000, 0.000000, -0.600000, 0.000000, -1.000000], // spin p=0.875
            [0.000000, -5.850000, 0.000000, 0.250000, 0.900000, -0.900000, 0.000000, 0.000000, 0.000000, 1.000000], // chicken p=0.375
            [0.000000, -5.850000, 0.000000, 0.250000, 0.900000, -0.900000, 0.000000, 0.000000, 0.000000, 1.000000], // chicken p=0.875
        ]
        for (i, move) in BuddyDance.Move.allCases.enumerated() {
            for (j, phase) in [0.375, 0.875].enumerated() {
                let p = BuddyDance.pose(BuddyRig.girl.style, tier: 3, p: phase, move: move)
                let values = [p.dx, p.dy, p.rot, p.head, p.armL, p.armR, p.legL, p.legR, p.tail, p.sx]
                for (a, b) in zip(values, expected[i * 2 + j]) { XCTAssertEqual(a, b, accuracy: 1e-6) }
            }
        }
    }
}
