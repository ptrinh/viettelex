// Trackpad (giữ phím cách) — logic THUẦN (không UIKit), pinned by TrackpadTests.
// Cùng thuật toán/ngưỡng với Android (android/.../ime/Trackpad.kt).
//
// • Ngang: mỗi 9pt = 1 ký tự (cảm giác stock). Dọc: mỗi 24pt = 1 dòng.
// • Trục chính quyết định MỖI BƯỚC, có hysteresis: đang ngang chỉ sang dọc khi dy đủ
//   một dòng VÀ gấp 2 lần dx; mỗi bước ngang xoá dy tích luỹ ⇒ kéo ngang hơi chéo không
//   bao giờ nhảy dòng. Đang dọc cần dx ≥ 18pt (2 ký tự) và gấp 2 lần dy mới về ngang.
// • Tăng tốc: tốc độ (EMA, pt/s) theo trục; ≤ slow ⇒ ×1 (chính xác từng ký tự/dòng),
//   ≥ fast ⇒ ×max, giữa nội suy tuyến tính. Ngang 300→1500 pt/s, ×5; dọc 200→1000, ×3.
import Foundation

struct TrackpadGesture {
    enum Axis { case horizontal, vertical }
    /// `count` có dấu: ngang âm = trái; dọc âm = lên.
    struct Step: Equatable { let axis: Axis; let count: Int }

    static let hStep = 9.0, vStep = 24.0, hSwitch = 18.0, dominance = 2.0
    static let hSlow = 300.0, hFast = 1500.0, hMax = 5.0
    static let vSlow = 200.0, vFast = 1000.0, vMax = 3.0
    static let ema = 0.5, minDt = 1.0 / 240, pause = 0.1

    private(set) var axis: Axis = .horizontal
    private var accX = 0.0, accY = 0.0
    private var lastX = 0.0, lastY = 0.0, lastT = 0.0
    private var speedX = 0.0, speedY = 0.0

    mutating func begin(x: Double, y: Double, t: Double) {
        axis = .horizontal; accX = 0; accY = 0
        lastX = x; lastY = y; lastT = t
        speedX = 0; speedY = 0
    }

    mutating func move(x: Double, y: Double, t: Double) -> Step? {
        let dx = x - lastX, dy = y - lastY, dtRaw = t - lastT
        lastX = x; lastY = y; lastT = t
        if dx == 0 && dy == 0 { return nil }
        let dt = max(dtRaw, Self.minDt)
        let ix = abs(dx) / dt, iy = abs(dy) / dt
        if dtRaw > Self.pause { speedX = ix; speedY = iy }   // nghỉ lâu: không mang đà cũ
        else {
            speedX = Self.ema * ix + (1 - Self.ema) * speedX
            speedY = Self.ema * iy + (1 - Self.ema) * speedY
        }
        accX += dx; accY += dy
        let ax = abs(accX), ay = abs(accY)
        switch axis {
        case .horizontal:
            if ay >= Self.vStep && ay > Self.dominance * ax { axis = .vertical; return emitV() }
            if ax >= Self.hStep { return emitH() }
        case .vertical:
            if ax >= Self.hSwitch && ax > Self.dominance * ay { axis = .horizontal; return emitH() }
            if ay >= Self.vStep { return emitV() }
        }
        return nil
    }

    private mutating func emitH() -> Step {
        let units = Int(accX / Self.hStep)
        accX -= Double(units) * Self.hStep
        accY = 0
        return Step(axis: .horizontal,
                    count: Self.accelerate(units, speed: speedX, slow: Self.hSlow, fast: Self.hFast, max: Self.hMax))
    }

    private mutating func emitV() -> Step {
        let lines = Int(accY / Self.vStep)
        accY -= Double(lines) * Self.vStep
        accX = 0
        return Step(axis: .vertical,
                    count: Self.accelerate(lines, speed: speedY, slow: Self.vSlow, fast: Self.vFast, max: Self.vMax))
    }

    /// `units` bước thô ⇒ bước đã tăng tốc theo `speed`. Chậm ⇒ nguyên `units`.
    static func accelerate(_ units: Int, speed: Double, slow: Double, fast: Double, max m: Double) -> Int {
        guard units != 0 else { return 0 }
        let f: Double
        if speed <= slow { f = 1 }
        else if speed >= fast { f = m }
        else { f = 1 + (m - 1) * (speed - slow) / (fast - slow) }
        let n = Swift.max(1, Int((Double(abs(units)) * f).rounded()))
        return units < 0 ? -n : n
    }
}

enum VerticalMove {
    /// Dời (UTF-16 — đơn vị NSString mà UITextInput/adjustTextPosition dùng) để lên
    /// (`lines` < 0) / xuống `lines` dòng LOGIC (ký tự xuống dòng), giữ cột tính theo
    /// grapheme (dòng đích ngắn hơn ⇒ cuối dòng). Chỉ đi trong context host cho: ít ngắt
    /// dòng hơn yêu cầu ⇒ đi hết số có; không có ngắt ⇒ nil (dòng đầu/cuối, hoặc dòng tự
    /// ngắt — không biết dòng hiển thị). Đầu dòng đích không thấy (context trước bị cắt)
    /// ⇒ coi đầu `before` là đầu dòng: vẫn đúng dòng, cột có thể lệch.
    static func offset(before: String, after: String, lines: Int) -> Int? {
        guard lines != 0 else { return 0 }
        let bSegs = segments(before)
        let col = bSegs.last!.count
        if lines < 0 {
            let breaks = bSegs.count - 1
            guard breaks > 0 else { return nil }
            let k = min(-lines, breaks)
            let ti = bSegs.count - 1 - k
            let target = bSegs[ti]
            // Vị trí = đầu dòng đích + col grapheme của nó; tính lùi từ cuối before.
            let targetStartU16 = before.utf16.distance(from: before.startIndex, to: target.startIndex)
            let pos = targetStartU16 + prefixUTF16(target, col)
            return pos - before.utf16.count
        } else {
            let aSegs = segments(after)
            let breaks = aSegs.count - 1
            guard breaks > 0 else { return nil }
            let k = min(lines, breaks)
            let target = aSegs[k]
            let targetStartU16 = after.utf16.distance(from: after.startIndex, to: target.startIndex)
            return targetStartU16 + prefixUTF16(target, col)
        }
    }

    /// Tách theo Character.isNewline (\n, \r, \r\n một ký tự, U+2028/2029…).
    private static func segments(_ s: String) -> [Substring] {
        s.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
    }

    private static func prefixUTF16(_ s: Substring, _ n: Int) -> Int {
        s.prefix(n).utf16.count
    }
}
