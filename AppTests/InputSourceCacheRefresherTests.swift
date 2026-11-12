import XCTest
@testable import VietTelex

// Issue #158: file đệm danh sách bộ gõ của app sandbox tạo trước khi cài VietTelex ⇒ app
// không thấy VietTelex và crash khi đổi bộ gõ. Phần quyết định phải dè dặt: chỉ xoá đúng
// file đệm, chỉ của app đã cài, không khi app đang chạy, không lặp lại liên tục.
final class InputSourceCacheRefresherTests: XCTestCase {

    private typealias R = InputSourceCacheRefresher
    private let marker = "com.viettelex.inputmethod.telex"

    func testStaleMeansOurInputSourceIsMissing() {
        let fresh = Data("xx com.apple.keylayout.ABC yy com.viettelex.inputmethod.telex.vi zz".utf8)
        let stale = Data("xx com.apple.keylayout.ABC yy com.apple.inputmethod.Kotoeri zz".utf8)
        XCTAssertFalse(R.cacheIsStale(fresh, marker: marker))
        XCTAssertTrue(R.cacheIsStale(stale, marker: marker))
        // Không đọc được gì thì không kết luận là cũ.
        XCTAssertFalse(R.cacheIsStale(Data(), marker: marker))
        XCTAssertFalse(R.cacheIsStale(stale, marker: ""))
    }

    func testOnlyTheKeyboardCacheFilesAreRemoved() {
        let names = ["com.apple.IntlDataCache.le.kbdx", "Cache.db", "com.apple.IntlDataCache.le",
                     "com.apple.metal", "fsCachedData", "com.apple.IntlDataCache.le.sbdl"]
        XCTAssertEqual(R.cacheFiles(in: names),
                       ["com.apple.IntlDataCache.le", "com.apple.IntlDataCache.le.kbdx",
                        "com.apple.IntlDataCache.le.sbdl"])
        XCTAssertEqual(R.cacheFiles(in: ["Cache.db"]), [])
    }

    private func decide(stale: Bool = true, app: Bool = true, own: Bool = false, running: Bool = false,
                        last: TimeInterval? = nil, now: TimeInterval = 1_000_000) -> R.Action {
        R.decide(stale: stale, isInstalledApp: app, isOwnBundle: own, running: running,
                 lastRefresh: last, now: now)
    }

    func testStaleCacheOfAQuitAppIsRemoved() {
        XCTAssertEqual(decide(), .deleteNow)
    }

    func testRunningAppWaitsUntilItQuits() {
        XCTAssertEqual(decide(running: true), .waitForQuit)
    }

    func testNothingTouchedWhenFreshOrNotAnAppOrOurs() {
        XCTAssertEqual(decide(stale: false), .none)
        XCTAssertEqual(decide(app: false), .none)       // dịch vụ nền của macOS
        XCTAssertEqual(decide(own: true), .none)
        XCTAssertEqual(decide(stale: false, running: true), .none)
    }

    func testAtMostOncePerWeekPerApp() {
        let now: TimeInterval = 1_000_000
        XCTAssertEqual(decide(last: now - 3600, now: now), .none)
        XCTAssertEqual(decide(running: true, last: now - 3600, now: now), .none)
        XCTAssertEqual(decide(last: now - R.retryInterval - 1, now: now), .deleteNow)
        // Đồng hồ lùi (mốc ở tương lai): không coi là "vừa xoá" mãi mãi.
        XCTAssertEqual(decide(last: now + 3600, now: now), .deleteNow)
    }

    func testCacheRootIsTheUserCacheDir() {
        let root = R.cacheRoot()
        XCTAssertNotNil(root)
        XCTAssertTrue(root?.path.hasSuffix("/C") == true || root?.path.hasSuffix("/C/") == true)
    }

    // Issue #160: phần chạy trên queue nền không được gọi TIS (HIToolbox macOS 26.5 assert
    // main queue ⇒ trap). Gọi từ queue nền phải chạy xong bình thường.
    func testBackgroundRefreshDoesNotTouchInputSourceAPI() {
        let done = expectation(description: "refresh off main")
        DispatchQueue.global(qos: .utility).async {
            R.refresh(bundleIDs: ["com.viettelex.test.no-such-app"], running: [])
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        let src = try? String(contentsOfFile: #filePath.replacingOccurrences(
            of: "AppTests/InputSourceCacheRefresherTests.swift",
            with: "App/Sources/InputSourceCacheRefresher.swift"), encoding: .utf8)
        if let src, let body = src.components(separatedBy: "static func refresh(").last {
            XCTAssertFalse(body.contains("vietTelexEnabled()"))
            XCTAssertFalse(body.contains("TISCreate"))
        }
    }
}
