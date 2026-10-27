import XCTest

final class KeystrokeCounterTests: XCTestCase {
    private var d: UserDefaults!
    private let suite = "KeystrokeCounterTests"

    override func setUp() {
        d = UserDefaults(suiteName: suite)
        d.removePersistentDomain(forName: suite)
        KeystrokeCounter.debugReset()
    }

    override func tearDown() { d.removePersistentDomain(forName: suite) }

    private func date(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }

    func testOffByDefaultInVietTelex() {
        XCTAssertFalse(AppFlavor.countsKeystrokes)
        let before = KeystrokeCounter.debugPending
        KeystrokeCounter.tick()
        XCTAssertEqual(KeystrokeCounter.debugPending, before)
    }

    func testFlushAddsToTotalAndToday() {
        let day = date(2026, 10, 27)
        KeystrokeCounter.debugAdd(5)
        KeystrokeCounter.flush(d, now: day)
        KeystrokeCounter.debugAdd(3)
        KeystrokeCounter.flush(d, now: day)
        XCTAssertEqual(KeystrokeCounter.total(d), 8)
        XCTAssertEqual(KeystrokeCounter.today(d, now: day), 8)
        XCTAssertEqual(KeystrokeCounter.debugPending, 0)
    }

    func testTodayRestartsOnANewDay() {
        KeystrokeCounter.debugAdd(10)
        KeystrokeCounter.flush(d, now: date(2026, 10, 27, 23))
        XCTAssertEqual(KeystrokeCounter.today(d, now: date(2026, 10, 28, 1)), 0)
        KeystrokeCounter.debugAdd(4)
        KeystrokeCounter.flush(d, now: date(2026, 10, 28, 1))
        XCTAssertEqual(KeystrokeCounter.total(d), 14)
        XCTAssertEqual(KeystrokeCounter.today(d, now: date(2026, 10, 28, 9)), 4)
    }

    func testFlushWithNothingPendingWritesNothing() {
        KeystrokeCounter.flush(d)
        XCTAssertNil(d.object(forKey: KeystrokeCounter.totalKey))
    }
}
