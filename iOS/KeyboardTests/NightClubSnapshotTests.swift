// Ảnh theme Neon Night Club — chỉ chạy khi có VT_THEME_SNAPSHOT_DIR (xcodebuild: TEST_RUNNER_VT_THEME_SNAPSHOT_DIR=…).
// layer.render bỏ qua mask / animation ⇒ đèn rọi + sàn nhảy vẽ lại bằng Core Graphics theo CÙNG hàm thuần
// (SpotlightView.debugRender, DanceFloor), phím + thanh gợi ý vẽ từ cây layer thật.
import XCTest
import UIKit

final class NightClubSnapshotTests: XCTestCase {
    private static let bg = UIColor(red: 7 / 255.0, green: 2 / 255.0, blue: 13 / 255.0, alpha: 1)

    @MainActor func testWriteNightClubSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["VT_THEME_SNAPSHOT_DIR"] else {
            throw XCTSkip("đặt VT_THEME_SNAPSHOT_DIR để xuất ảnh theme")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let out = URL(fileURLWithPath: dir)
        // Bóng cô gái nhảy: 3 tư thế dưới 3 quầng đèn (không có ảnh nền).
        let size = CGSize(width: 402, height: 270)
        for (n, pose) in [(0, 0), (1, 2), (2, 6)] {
            let lights: [(center: CGPoint, keyWidth: Double, level: Int, dt: Double, color: Int)] = [
                (CGPoint(x: 150, y: 190), 34, 1, 0.35, n), (CGPoint(x: 250, y: 80), 34, 2, 0.2, n + 1),
                (CGPoint(x: 200, y: 150), 34, 3, 0.07, n + 2)]
            let img = UIGraphicsImageRenderer(size: size).image { c in
                Self.bg.setFill(); c.fill(CGRect(origin: .zero, size: size))
                SpotlightView.debugRender(in: c.cgContext, size: size, photo: nil, pose: pose, lights: lights)
            }
            try XCTUnwrap(img.pngData()).write(to: out.appendingPathComponent("nightclub-dancer-\(DancerFigure.poses[pose].id).png"))
        }
        // Bàn phím thật giữa hiệu ứng: đèn rọi (không ảnh + có ảnh) + Sàn nhảy LED.
        let d = UserDefaultsProvider.shared
        let saved = d?.object(forKey: ThemeSettings.themeKey), savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        defer { d?.set(saved, forKey: ThemeSettings.themeKey); PlusGate.paywallEnabled = savedPaywall }
        d?.set(KeyboardTheme.nightclub.rawValue, forKey: ThemeSettings.themeKey)
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 140)).image { c in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [UIColor.systemOrange.cgColor, UIColor.systemPink.cgColor, UIColor.systemTeal.cgColor] as CFArray,
                               locations: nil)!
            c.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 200, y: 140), options: [])
            UIColor.white.withAlphaComponent(0.8).setFill()
            for i in 0..<12 { c.cgContext.fillEllipse(in: CGRect(x: i * 17, y: 30 + (i % 3) * 30, width: 10, height: 10)) }
        }.cgImage
        for (name, img) in [("nightclub-theme-ios", nil as CGImage?), ("nightclub-theme-ios-photo", photo)] {
            let w: CGFloat = 402
            let win = UIWindow(frame: CGRect(x: 0, y: 0, width: w, height: 320))
            win.overrideUserInterfaceStyle = .dark
            win.isHidden = false
            defer { win.isHidden = true }
            let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
            win.addSubview(kb)
            kb.frame = win.bounds
            kb.applyAppearance(.dark, style: .dark)
            kb.setSuggestionsEnabled(true)
            kb.configureInputKind(.normal)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            kb.showSuggestions(.init(nextWords: ["Việt", "chào", "Tôi"]))
            let h = kb.systemLayoutSizeFitting(CGSize(width: w, height: 0)).height
            win.frame.size.height = max(h, 200); kb.frame = win.bounds
            win.layoutIfNeeded(); kb.layoutIfNeeded()
            let keys = ["g", "u", "n"].compactMap { kb.debugDomainKeyFrame($0) ?? kb.debugDomainKeyFrame($0.uppercased()) }
            XCTAssertEqual(keys.count, 3)
            let hidden = kb.debugBackdropViews.map(\.isHidden) + [kb.spotlight?.isHidden ?? true]
            for v in kb.debugBackdropViews { v.isHidden = true }
            kb.spotlight?.isHidden = true
            let lights = keys.enumerated().map { i, f in
                (center: CGPoint(x: f.midX, y: f.midY), keyWidth: Double(f.width), level: 2, dt: [0.45, 0.22, 0.06][i], color: i)
            }
            let shot = UIGraphicsImageRenderer(bounds: kb.bounds).image { c in
                Self.bg.setFill(); c.fill(kb.bounds)
                SpotlightView.debugRender(in: c.cgContext, size: kb.bounds.size, photo: img, pose: 3, lights: lights)
                kb.layer.render(in: c.cgContext)
                // Sàn nhảy LED ở phím vừa bấm (n), 70 ms sau khi bấm.
                let k = keys[2]
                for t in DanceFloor.tiles(cx: Double(k.midX), cy: Double(k.midY), w: Double(k.width), h: Double(k.height), seed: 1) {
                    let a = DanceFloor.alpha(0.07, ring: t.ring)
                    guard a > 0 else { continue }
                    let r = CGRect(x: t.x - t.w / 2, y: t.y - t.h / 2, width: t.w, height: t.h)
                    let rad = CGFloat(DanceFloor.cornerFactor) * min(r.width, r.height)
                    let col = DanceFloor.colors[t.color]
                    let ui = UIColor(red: CGFloat(col >> 16 & 0xFF) / 255, green: CGFloat(col >> 8 & 0xFF) / 255, blue: CGFloat(col & 0xFF) / 255,
                                     alpha: CGFloat(a))
                    ui.setFill(); UIBezierPath(roundedRect: r, cornerRadius: rad).fill()
                }
            }
            for (v, h) in zip(kb.debugBackdropViews + [kb.spotlight].compactMap { $0 }, hidden) { v.isHidden = h }
            try XCTUnwrap(shot.pngData()).write(to: out.appendingPathComponent(name + ".png"))
            kb.tearDown()
        }
    }
}
