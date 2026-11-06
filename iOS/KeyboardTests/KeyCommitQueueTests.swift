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

    // MARK: chốt phím đang đè đổi plane ⇒ chạm mới phải tra lại (KeyboardView.flushBeforeButtonDown)

    private enum P { case letters, numbers }
    private var plane = P.numbers
    private var typedInPlane = false
    private let n123Key = Key()                 // nút 123 dưới chỗ chữ "n" của ABC

    private func symbol(_ s: String) {
        let before = out.last
        out += s
        typedInPlane = true
        if PlanePolicy.returnToLettersAfterSymbol(s, mode: .auto, inSymbolPlane: plane == .numbers,
                                                  numericField: false, before: before) { plane = .letters }
    }
    private func spaceFire() {
        out += " "
        if PlanePolicy.returnToLettersOnSpace(inSymbolPlane: plane == .numbers,
                                              typedInPlane: typedInPlane, numericField: false) { plane = .letters }
    }
    /// Ngón mới chạm nút 123 (UIKit đã gán) — true ⇒ tra lại ở plane mới, gõ "n" thay vì nút 123.
    private func fastTapAtN() {
        if q.flush(except: id(n123Key), changes: { plane }) { out += "n" }
        else { q.arm(id(n123Key)) { self.out += "?" } }
    }

    func testHeldSpaceOn123ReturnsToLettersBeforeNextTouchResolves() {
        symbol("2")
        q.arm(id(space)) { self.spaceFire() }  // giữ space
        fastTapAtN()                           // chạm chỗ "n" trước khi nhấc space
        q.release(id(space))
        XCTAssertEqual(out, "2 n")
        XCTAssertEqual(plane, .letters)
        XCTAssertTrue(q.isEmpty)               // nút 123 cũ không được arm
    }

    func testHeldCommaOn123ReturnsToLettersInAutoMode() {
        q.arm(id(comma)) { self.symbol(",") }
        fastTapAtN()
        q.release(id(comma))
        XCTAssertEqual(out, ",n")
        XCTAssertEqual(plane, .letters)
    }

    func testFlushWithoutPlaneChangeKeepsBoundKey() {
        q.arm(id(comma)) { self.symbol("2") }  // chữ số: ở lại 123
        fastTapAtN()
        q.release(id(n123Key))
        XCTAssertEqual(out, "2?")
        XCTAssertEqual(plane, .numbers)
        // Không có gì chờ ⇒ không đổi
        XCTAssertFalse(q.flush(except: nil, changes: { plane }))
    }
}
