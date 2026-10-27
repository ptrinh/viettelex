import XCTest

/// VietTelex (AppFlavor mặc định) giữ nguyên hành vi Bạn đồng hành sau khi danh sách / da nhân vật đi qua AppFlavor.
final class BuddyFlavorTests: XCTestCase {
    func testVietTelexOffersEveryCharacterAndDefaultsOff() {
        XCTAssertEqual(BuddyCharacter.offered, BuddyCharacter.allCases)
        XCTAssertEqual(BuddyCharacter.defaultValue, .off)
        XCTAssertEqual(BuddyCharacter.parse("không có"), .off)
    }

    func testOnlyCatIsFree() {
        XCTAssertEqual(BuddyCharacter.allCases.filter { $0 != .off && !$0.isPlus }, [.cat])
    }

    func testNoSkinsSoBuiltInArtAndStyleChoiceStay() {
        for c in BuddyCharacter.allCases { XCTAssertNil(c.skin, c.rawValue) }
        XCTAssertEqual(BuddyCharacter.girl.title, L("Cô gái"))
        XCTAssertTrue(BuddyStyle.isChoosable(.girl))
        XCTAssertFalse(BuddyStyle.isChoosable(.robot))
        XCTAssertEqual(BuddyStyle.vector.resolved(for: .girl), .vector)
        XCTAssertEqual(BuddyStyle.sprite.resolved(for: .robot), .vector)
        XCTAssertEqual(BuddySprites.turnOrder(.girl), [6, 3, 4, 2, 5])
    }
}
