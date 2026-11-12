// Báo lỗi Phil 12/11/2026: "gõ vuốt xong 1 từ xong ấn số 123 thì không có dấu space giữa từ đó và
// 123". Đi đúng đường thật của controller (chạm phím chữ đầu → vuốt → bấm 123 → chạm số), host
// báo lại textWillChange/textDidChange sau mỗi lệnh như iOS thật.
import XCTest
import UIKit

@MainActor
final class SwipeThenDigitTests: XCTestCase {

    private final class Rig {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let vc = KeyboardViewController()
        let host = HostDesyncTests.LagHost()
        let saved = UserDefaultsProvider.shared

        init() {
            let d = KeyboardBenchTests.makeDefaults("B")
            d.set(true, forKey: "swipeTyping")
            UserDefaultsProvider.shared = d
            win.isHidden = false
            vc.debugProxy = host
            vc.loadViewIfNeeded()
            vc.view.frame = CGRect(x: 0, y: 874 - 290, width: 402, height: 290)
            win.addSubview(vc.view)
            vc.beginAppearanceTransition(true, animated: false)
            vc.view.layoutIfNeeded()
            vc.endAppearanceTransition()
            vc.view.layoutIfNeeded()
            KeyboardBenchTests.spin(0.05)
        }

        func close() {
            vc.beginAppearanceTransition(false, animated: false)
            vc.endAppearanceTransition()
            vc.view.removeFromSuperview()
            win.isHidden = true
            UserDefaultsProvider.shared = saved
        }

        /// Host xử lý hết lệnh đang chờ rồi báo lại (như iOS sau mỗi lệnh sửa).
        func flush() {
            host.queue.append(host.batch); host.batch = []
            while !host.queue.isEmpty { host.process(vc) }
            KeyboardBenchTests.spin(0.02)
        }

        func swipe(_ word: String) throws {
            let l = try XCTUnwrap(vc.debugSwipeLayout, "chưa có bố cục vuốt")
            var sim = SwipeSim(seed: 3)
            vc.debugSwipe(first: word.first!, path: sim.path(word, l, sigma: 0, jitter: 0))
            flush()
        }
    }

    func testDigitAfterSwipeAndPlaneSwitchGetsSpace() throws {
        let rig = Rig()
        defer { rig.close() }
        try rig.swipe("mua")
        XCTAssertEqual(rig.host.real, "mua")
        rig.vc.debugCycleThroughNumbers()          // bấm 123 (đổi plane thật)
        rig.vc.debugHandle(.text("1"))
        rig.flush()
        rig.vc.debugHandle(.text("2"))
        rig.flush()
        rig.vc.debugHandle(.text("3"))
        rig.flush()
        XCTAssertEqual(rig.host.real, "mua 123")
    }

    func testDigitRightAfterSwipeGetsSpace() throws {
        let rig = Rig()
        defer { rig.close() }
        try rig.swipe("mua")
        rig.vc.debugHandle(.text("2"))
        rig.flush()
        XCTAssertEqual(rig.host.real, "mua 2")
    }
}
