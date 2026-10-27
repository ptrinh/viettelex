// Bạn đồng hành: quy tắc nhỏ dùng chung iOS / Android. Chỉ viết; không chạy suite trong vòng này.
import XCTest
import UIKit

final class KeyboardBuddyExtrasTests: XCTestCase {
    func testClockBoundaries() {
        XCTAssertEqual(BuddyClock.part(hour: 4, minute: 59), .night)
        XCTAssertEqual(BuddyClock.part(hour: 5, minute: 0), .morning)
        XCTAssertEqual(BuddyClock.part(hour: 8, minute: 59), .morning)
        XCTAssertEqual(BuddyClock.part(hour: 9, minute: 0), .day)
        XCTAssertEqual(BuddyClock.part(hour: 22, minute: 59), .day)
        XCTAssertEqual(BuddyClock.part(hour: 23, minute: 0), .night)
        XCTAssertEqual(BuddyClock.part(hour: 0, minute: 0), .night)
    }

    func testBirthdayRulesAndTriggers() {
        XCTAssertFalse(BuddyBirthday.valid(month: 0, day: 1))
        XCTAssertTrue(BuddyBirthday.valid(month: 2, day: 29))
        XCTAssertTrue(BuddyBirthday.matches(month: 2, day: 29, year: 2024, todayMonth: 2, todayDay: 29))
        XCTAssertTrue(BuddyBirthday.matches(month: 2, day: 29, year: 2025, todayMonth: 2, todayDay: 28))
        XCTAssertFalse(BuddyBirthday.matches(month: 2, day: 29, year: 2024, todayMonth: 2, todayDay: 28))
        XCTAssertFalse(BuddyBirthday.matches(month: 2, day: 29, year: 2100, todayMonth: 2, todayDay: 29))
        for word in ["hpbd", "hbd", "sinh nhật", "happy birthday", "🎂", "🎉", "🥳", "🎈"] {
            XCTAssertTrue(BuddyBirthday.trigger(word: word, prev: nil), word)
            XCTAssertEqual(BuddyWords.reaction(word: word, prev: nil), .cake, word)
        }
        XCTAssertTrue(BuddyBirthday.trigger(word: "nhật", prev: "sinh"))
        XCTAssertTrue(BuddyBirthday.trigger(word: "birthday", prev: "happy"))
        XCTAssertFalse(BuddyBirthday.trigger(word: "happy", prev: nil))
        XCTAssertEqual(BuddyFX.count(.cake), 8)
        XCTAssertEqual(BuddyFX.count(.tickle), 3)
        XCTAssertFalse(BuddyOutfit.make(nil, .cat, night: true).pieces.isEmpty)
        XCTAssertEqual(BuddyOutfit.make(.christmas, .cat, night: true).pieces.count,
                       BuddyOutfit.make(.christmas, .cat).pieces.count, "mũ lễ thắng mũ ngủ")
        XCTAssertEqual(BuddyProp.make(.cake, BuddyRig.cat).count, 4)
    }

    func testNamesAndBackupKeys() {
        XCTAssertEqual(BuddyName.clean("  Mướp\n"), "Mướp")
        XCTAssertEqual(BuddyName.clean(String(repeating: "a", count: 30)), String(repeating: "a", count: 20))
        XCTAssertEqual(BuddyName.clean(String(repeating: "🐱", count: 21)), String(repeating: "🐱", count: 20))
        XCTAssertEqual(BuddyName.key(.cat), "buddyName.cat")
        XCTAssertEqual(BuddyName.bubble("Mướp", english: false, maxCharacters: 30), "Mướp chào bạn!")
        XCTAssertEqual(BuddyName.bubble("Mướp", english: true, maxCharacters: 30), "Mướp says hi!")
        XCTAssertEqual(BuddyName.bubble("Mướp", english: true, maxCharacters: 8), "Mướp sa…")
        XCTAssertNil(BuddyName.bubble("", english: false, maxCharacters: 30))
        for c in BuddyCharacter.allCases where c != .off {
            XCTAssertTrue(BackupSettings.all.contains { $0.key == BuddyName.key(c) })
        }
        XCTAssertTrue(BackupSettings.all.contains { $0.key == BuddyBirthday.monthKey })
        XCTAssertTrue(BackupSettings.all.contains { $0.key == BuddyBirthday.dayKey })
    }

    func testTickleOnlyAtFigureInsideReservedStrip() {
        let strip: CGFloat = 40
        for size in [1, 5, 20] {
            for right in [-100, 0, 100] {
                for top in [-100, 0, 100] {
                    let placement = BuddyPlacement(size: size, padRight: right, padTop: top)
                    let z = KeyboardView.buddyZoneFrame(width: 390, strip: strip, placement: placement)
                    let f = KeyboardView.buddyFrame(width: 390, strip: strip, placement: placement, height: 260)
                    let zone = BuddyRect(x: Double(z.minX), y: 0, w: Double(z.width), h: Double(z.height))
                    let figure = BuddyRect(x: Double(f.minX), y: Double(f.minY), w: Double(f.width), h: Double(f.height))
                    let overlap = z.intersection(f).intersection(CGRect(x: 0, y: 0, width: 390, height: strip))
                    if !overlap.isNull && overlap.width > 0 && overlap.height > 0 {
                        XCTAssertTrue(BuddyTap.tickles(x: Double(overlap.midX), y: Double(overlap.midY), zone: zone, stripHeight: Double(strip), figure: figure))
                    }
                    XCTAssertFalse(BuddyTap.tickles(x: Double(f.midX), y: 55, zone: zone, stripHeight: Double(strip), figure: figure), "phím luôn thắng: \(size), \(right), \(top)")
                    XCTAssertFalse(BuddyTap.tickles(x: Double(z.minX - 1), y: 10, zone: zone, stripHeight: Double(strip), figure: figure))
                }
            }
        }
    }
}
