// Ô xem thử trang "Hiệu ứng khi bấm phím" (Keyboard/KeyEffectPreview.swift): MỌI kiểu (KeyEffect.allCases — kiểu mới
// tự vào) chạm ô phải vẽ ra thứ gì đó NHÌN THẤY ĐƯỢC trong ô. Lỗi 08/11/2026: SwiftUI gọi update trước khi ô có cỡ ⇒
// overlay 0×0 + cắt theo khung ⇒ Laser / Glitch / Từ khoá / Chữ bay / Hạt cát / Biển / Token AI / Sàn nhảy LED trống
// trơn. Android: KeyEffectPreviewTest.
import XCTest
import UIKit

@MainActor
final class KeyEffectPreviewTests: XCTestCase {
    private let tile = CGRect(x: 0, y: 0, width: 110, height: 84)
    private var palette: KeyboardPalette { ThemeSettings.load(nil).palette(systemDark: false, wallpaperActive: false) }

    override func setUp() {
        super.setUp()
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = true
        #endif
    }

    override func tearDown() {
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = false
        #endif
        super.tearDown()
    }

    /// Như SwiftUI: makeUIView ⇒ updateUIView (ô còn 0×0) ⇒ có cỡ ⇒ layout.
    private func makeTile(_ e: KeyEffect) -> KeyEffectPreviewView {
        let v = KeyEffectPreviewView(frame: .zero)
        v.update(effect: e, palette: palette, play: 0)
        v.frame = tile
        v.layoutIfNeeded()
        return v
    }

    private struct Sig: Equatable { var hidden: Bool; var begin: CFTimeInterval; var anims: [String]; var pos: CGPoint }

    private func signatures(_ root: CALayer) -> [ObjectIdentifier: Sig] {
        var out: [ObjectIdentifier: Sig] = [:]
        func walk(_ l: CALayer) {
            out[ObjectIdentifier(l)] = Sig(hidden: l.isHidden, begin: l.beginTime, anims: (l.animationKeys() ?? []).sorted(),
                                           pos: l.position)
            l.sublayers?.forEach(walk)
        }
        walk(root)
        return out
    }

    /// Số layer vừa đổi (bắn / dựng mới, hoặc nằm dưới gốc vừa bắn), không ẩn, có độ đục (hoặc animation), phần nhìn thấy
    /// sau khi cắt theo mọi tổ tiên masksToBounds nằm TRONG ô.
    private func visibleFired(_ v: UIView, since before: [ObjectIdentifier: Sig]) -> Int {
        var n = 0
        func walk(_ l: CALayer, changedAbove: Bool, clip: CGRect?) {
            guard !l.isHidden else { return }
            let sig = Sig(hidden: l.isHidden, begin: l.beginTime, anims: (l.animationKeys() ?? []).sorted(), pos: l.position)
            let changed = changedAbove || before[ObjectIdentifier(l)] != sig
            var clip = clip
            if l.masksToBounds {
                let b = v.layer.convert(l.bounds, from: l)
                clip = clip.map { $0.intersection(b) } ?? b
            }
            if changed, l !== v.layer, l.opacity > 0 || !(l.animationKeys() ?? []).isEmpty {
                var r: CGRect = .null
                if let s = l as? CAShapeLayer, let p = s.path, !p.isEmpty {
                    r = v.layer.convert(p.boundingBoxOfPath, from: l)
                } else if l.bounds.width > 0, l.bounds.height > 0 {
                    r = v.layer.convert(l.bounds, from: l)
                }
                if !r.isNull {
                    if let c = clip { r = r.intersection(c) }
                    r = r.intersection(v.bounds)
                    if !r.isNull, r.width > 0 || r.height > 0 { n += 1 }
                }
            }
            l.sublayers?.forEach { walk($0, changedAbove: changed, clip: clip) }
        }
        walk(v.layer, changedAbove: false, clip: nil)
        return n
    }

    func testEveryEffectPreviewDrawsInsideTile() {
        var blank: [String] = []
        for e in KeyEffect.allCases where e != .none {
            let v = makeTile(e)
            let before = signatures(v.layer)
            v.update(effect: e, palette: palette, play: 1)
            if visibleFired(v, since: before) == 0 { blank.append(e.rawValue) }
        }
        XCTAssertEqual(blank, [], "chạm ô xem thử mà không thấy gì")
    }

    /// Gốc lỗi: overlay phải phủ đúng ô sau khi ô có cỡ (không kẹt 0×0 từ lần update đầu).
    func testOverlayFollowsTileSize() throws {
        for e in KeyEffect.allCases where e != .none {
            let v = makeTile(e)
            let o = try XCTUnwrap(v.overlay, e.rawValue)
            XCTAssertEqual(o.frame, v.bounds, e.rawValue)
            v.frame = CGRect(x: 0, y: 0, width: 130, height: 90)
            v.layoutIfNeeded()
            XCTAssertEqual(o.frame, v.bounds, e.rawValue)
        }
    }

    func testScriptInputs() {
        XCTAssertEqual(KeyEffectPreviewScript.keyword(tap: 1), .tet)
        XCTAssertEqual(KeyEffectPreviewScript.keyword(tap: 2), .love)
        XCTAssertFalse(KeyEffectPreviewScript.beat(.dancefloor, tap: 1))
        XCTAssertTrue(KeyEffectPreviewScript.beat(.dancefloor, tap: 2))
        XCTAssertFalse(KeyEffectPreviewScript.beat(.heart, tap: 2))
        let space = KeyEffectPreviewScript.spaceBar(in: tile)
        XCTAssertTrue(tile.contains(space))
        XCTAssertTrue(tile.contains(KeyEffectPreviewScript.tokenTarget(in: tile)))
    }

    /// Sàn nhảy LED: lần chạm chẵn = nhịp phím cách ⇒ lớp flash nền chạy (qua cổng ≤ 3 lần / giây).
    func testDancefloorBeatOnEverySecondTap() {
        let v = makeTile(.dancefloor)
        v.update(effect: .dancefloor, palette: palette, play: 1)
        let flash = v.subviews.first { $0 is BeatFlashView }
        XCTAssertNotNil(flash)
        XCTAssertNil(flash?.layer.animation(forKey: BeatFlashView.animKey))
        v.update(effect: .dancefloor, palette: palette, play: 2)
        XCTAssertNotNil(flash?.layer.animation(forKey: BeatFlashView.animKey))
        // Đổi sang kiểu khác ⇒ gỡ lớp flash.
        v.update(effect: .heart, palette: palette, play: 2)
        XCTAssertFalse(v.subviews.contains { $0 is BeatFlashView })
    }
}
