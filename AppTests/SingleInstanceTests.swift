import XCTest
@testable import VietTelex

/// PR #92 (23/09/2026): bản Debug cũ trong DerivedData chiếm IMK connection của bản
/// Release đã cài. Chỉ bản trong "Input Methods" được làm IME; bản thừa tự nhường.
final class SingleInstanceTests: XCTestCase {
    let home = "/Users/u"
    let installed = "/Users/u/Library/Input Methods/VietTelex.app"
    let systemInstalled = "/Library/Input Methods/VietTelex.app"
    let stray = "/Users/u/Library/Developer/Xcode/DerivedData/x/Build/Products/Debug/VietTelex.app"

    func testInstalledLocations() {
        XCTAssertTrue(SingleInstance.isInstalledLocation(installed, home: home))
        XCTAssertTrue(SingleInstance.isInstalledLocation(systemInstalled, home: home))
        XCTAssertFalse(SingleInstance.isInstalledLocation(stray, home: home))
        XCTAssertFalse(SingleInstance.isInstalledLocation("/tmp/viettelex-derived/Build/Products/Release/VietTelex.app", home: home))
        // Không bị lừa bởi tên thư mục na ná
        XCTAssertFalse(SingleInstance.isInstalledLocation("/Users/u/Library/Input Methods Old/VietTelex.app", home: home))
    }

    func testStrayYieldsWhenAnyOtherInstanceRuns() {
        XCTAssertTrue(SingleInstance.shouldYieldAtLaunch(selfPath: stray, otherInstancePaths: [installed], home: home))
        XCTAssertTrue(SingleInstance.shouldYieldAtLaunch(selfPath: stray, otherInstancePaths: [stray + "2"], home: home))
        XCTAssertFalse(SingleInstance.shouldYieldAtLaunch(selfPath: stray, otherInstancePaths: [], home: home))
    }

    func testInstalledNeverYields() {
        XCTAssertFalse(SingleInstance.shouldYieldAtLaunch(selfPath: installed, otherInstancePaths: [stray], home: home))
        // …nhưng một bản đã cài CÙNG đường dẫn chạy trước thì bản mới nhường.
        XCTAssertTrue(SingleInstance.shouldYieldAtLaunch(selfPath: installed, otherInstancePaths: [installed], home: home))
        XCTAssertTrue(SingleInstance.shouldYieldAtLaunch(selfPath: installed, otherInstancePaths: [installed + "/"], home: home))
        XCTAssertFalse(SingleInstance.shouldYieldAtLaunch(selfPath: installed, otherInstancePaths: [systemInstalled], home: home))
        XCTAssertFalse(SingleInstance.shouldYieldOnInstalledAnnouncement(selfPath: installed, senderPID: 2, selfPID: 1, home: home))
    }

    func testStrayYieldsOnAnnouncementButNotItsOwn() {
        XCTAssertTrue(SingleInstance.shouldYieldOnInstalledAnnouncement(selfPath: stray, senderPID: 2, selfPID: 1, home: home))
        XCTAssertFalse(SingleInstance.shouldYieldOnInstalledAnnouncement(selfPath: stray, senderPID: 1, selfPID: 1, home: home))
    }

    func testNotificationIsPerIdentity() {
        XCTAssertNotEqual(SingleInstance.notificationName(bundleID: "com.viettelex.inputmethod.telex"),
                          SingleInstance.notificationName(bundleID: "com.viettelex.inputmethod.telex.debug"))
    }
}
