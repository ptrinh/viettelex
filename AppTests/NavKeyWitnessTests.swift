import XCTest
@testable import VietTelex

/// Word-table cell-jump (maintainer repro 23/08/2026): Word swallows Tab/arrow
/// cell-navigation without forwarding it to the IME, the controller keeps composing
/// the previous cell's word, and the next tone edit writes into the OLD cell. The
/// tap witnesses every physical key and stamps navigation keycodes; the controller
/// consumes at handle() entry and drops its composition when the stamped key was
/// never delivered.
final class NavKeyWitnessTests: XCTestCase {

    override func setUp() {
        super.setUp()
        NavKeyWitness.reset()
    }

    /// The bug: Tab swallowed by Word's table navigation — the next letter must
    /// report the swallow so the controller drops the previous cell's composition.
    func testSwallowedTabThenLetterDrops() {
        NavKeyWitness.stamp(keycode: 48)                       // Tab, never delivered
        XCTAssertTrue(NavKeyWitness.consume(keycode: 45))      // 'n' arrives → drop
        XCTAssertFalse(NavKeyWitness.consume(keycode: 45))     // one-shot: cleared
    }

    /// Normal apps deliver Tab to the IME: same keycode consumes the stamp with NO
    /// drop, so the Tab boundary path (auto-restore, forgetLastCommit) is untouched.
    func testDeliveredTabDoesNotDrop() {
        NavKeyWitness.stamp(keycode: 48)
        XCTAssertFalse(NavKeyWitness.consume(keycode: 48))     // the Tab itself
        XCTAssertFalse(NavKeyWitness.consume(keycode: 45))     // next letter: clean
    }

    /// The reporter's second trigger: → (right arrow) to the next cell.
    func testSwallowedRightArrowDrops() {
        NavKeyWitness.stamp(keycode: 124)
        XCTAssertTrue(NavKeyWitness.consume(keycode: 45))
    }

    /// Held arrow key (autorepeat) in a normal app: every delivery matches the
    /// latest stamp — never a drop.
    func testAutorepeatArrowNeverDrops() {
        for _ in 0..<3 {
            NavKeyWitness.stamp(keycode: 123)
            XCTAssertFalse(NavKeyWitness.consume(keycode: 123))
        }
    }

    /// Letter keycodes never stamp: plain typing leaves no pending state.
    func testLetterKeysNeverStamp() {
        NavKeyWitness.stamp(keycode: 9)                        // 'v'
        XCTAssertFalse(NavKeyWitness.consume(keycode: 48))
    }

    /// activateServer resets: a stamp from the previous client must not drop the
    /// first word typed in the next app.
    func testResetClearsPendingStamp() {
        NavKeyWitness.stamp(keycode: 48)
        NavKeyWitness.reset()
        XCTAssertFalse(NavKeyWitness.consume(keycode: 45))
    }

    /// The witness set is exactly the caret/focus movers: Tab, Home, PgUp, End,
    /// PgDn, ←, →, ↓, ↑.
    func testNavKeycodeSet() {
        XCTAssertEqual(NavKeyWitness.navKeycodes, [48, 115, 116, 119, 121, 123, 124, 125, 126])
    }
}
