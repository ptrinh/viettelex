import XCTest

/// Research 25/09/2026: space / dấu câu chốt lúc nhấc ngón, phím chữ lúc chạm —
/// gõ chồng ngón làm đảo thứ tự ("anh␣em" → "anhe m").
final class KeyCommitQueueTests: XCTestCase {
    private final class Key {}
    private var out = ""
    private let q = KeyCommitQueue()
    private let space = Key(), comma = Key(), ret = Key()
    private func id(_ k: Key) -> ObjectIdentifier { ObjectIdentifier(k) }

    /// Letter keys insert at touch-down; they flush the queue first (baseButton hook).
    private func letterDown(_ c: String) { q.flush(); out += c }

    func testRolloverKeepsPressOrder() {
        out = "anh"
        q.arm(id(space)) { self.out += " " }   // thumb 1 on space, still down
        letterDown("e")                        // thumb 2 hits "e" before thumb 1 lifts
        q.release(id(space))                   // thumb 1 lifts: already committed
        letterDown("m")
        XCTAssertEqual(out, "anh em")
    }

    func testCancelledTouchStillCommits() {
        q.arm(id(ret)) { self.out += "\n" }
        q.release(id(ret))                     // touchCancel routes to release
        XCTAssertEqual(out, "\n")
    }

    func testTrackpadDisarmsSpace() {
        out = "ab"
        q.arm(id(space)) { self.out += " " }
        q.disarm(id(space))                    // long-press → trackpad
        q.release(id(space))                   // finger lifts
        XCTAssertEqual(out, "ab")
    }

    func testSeveralPendingFireInPressOrderAndNotTwice() {
        q.arm(id(comma)) { self.out += "," }
        q.arm(id(space)) { self.out += " " }
        letterDown("x")
        q.release(id(comma)); q.release(id(space))
        XCTAssertEqual(out, ", x")
        XCTAssertTrue(q.isEmpty)
    }

    func testSameKeyPressedTwiceWhileHeldCommitsBoth() {
        q.arm(id(space)) { self.out += "1" }   // thumb 1 on space
        q.flush(except: id(space))
        q.arm(id(space)) { self.out += "2" }   // thumb 2 on space before thumb 1 lifts
        q.release(id(space))
        XCTAssertEqual(out, "12")
    }

    func testFlushExceptTheKeyBeingPressed() {
        q.arm(id(space)) { self.out += " " }
        q.flush(except: id(space))             // the space's OWN touchDown hook
        XCTAssertEqual(out, "")
        q.release(id(space))
        XCTAssertEqual(out, " ")
    }
}
