import XCTest
import UIKit

/// Issue #119 (iPhone 16 Pro Max, iOS 27): phím/bàn phím lệch bàn phím gốc ⇒ gõ nhầm; "+4 mỗi
/// hàng vẫn lệch". Số đo bàn phím gốc (KeyGeometry.StockSize) = mức 0 của "Chiều cao hàng phím"
/// trên iPhone (bỏ công tắc riêng, chuyển đổi giá trị cũ — KeyGeometry.RowAdjust), "Nâng bàn
/// phím", và dải trống phía trên phím khi đã tắt gợi ý và các phụ trợ.
///
/// Số đo stock (simulator iOS 27.0, 12/10/2026, XCUITest + ảnh @3x): dọc máy < 420pt bước hàng
/// 54 phím 43; máy ≥ 420 (Air/Plus/Pro Max) bước 56 phím 45; ngang bước 40 phím 32, lề 4.33,
/// khe ngang 6.67; thanh dự đoán: mép kính → đỉnh phím 40 (dọc).
final class StockSizeTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    /// "Chiều cao thanh gợi ý" mặc định (Vừa) cộng vào strip mở dọc (18/10/2026).
    private static let bar = SuggestionBarHeight.defaultValue.delta(landscape: false)
    typealias SS = KeyGeometry.StockSize

    // MARK: thuần

    func testStockMetricsByWidth() {
        for w: CGFloat in [375, 390, 393, 402] {
            let m = SS.metrics(width: w, landscape: false)
            XCTAssertEqual(m?.pitch, 54, "\(w)"); XCTAssertEqual(m?.keyHeight, 43, "\(w)")
        }
        for w: CGFloat in [420, 430, 440] {
            let m = SS.metrics(width: w, landscape: false)
            XCTAssertEqual(m?.pitch, 56, "\(w)"); XCTAssertEqual(m?.keyHeight, 45, "\(w)")
        }
        for w: CGFloat in [694, 722, 874] {
            let m = SS.metrics(width: w, landscape: true)
            XCTAssertEqual(m?.pitch, 40); XCTAssertEqual(m?.keyHeight, 32)
            XCTAssertEqual(m?.sideMargin, 4.33); XCTAssertEqual(m?.keyGap, 6.67)
        }
        // SE (nút Home): phím 42, bàn phím sát đáy màn hình ⇒ đệm dưới 4.
        let se = SS.metrics(width: 375, landscape: false, homeButton: true)
        XCTAssertEqual(se?.keyHeight, 42); XCTAssertEqual(se?.pitch, 54); XCTAssertEqual(se?.bottomTrim, -4)
        // Đáy view extension (đo VietTelex trên simulator): dọc 75, ngang 20 trên đáy màn hình.
        XCTAssertEqual(SS.standardPortrait.bottomTrim, 75 - 71)
        XCTAssertEqual(SS.largePortrait.bottomTrim, 75 - 82)
        XCTAssertEqual(SS.landscape.bottomTrim, 20 - 22)
        // Chưa layout (0): đoán dọc máy thường — cùng khe/lề với máy lớn (không phải dựng lại).
        let g = SS.metrics(width: 0, landscape: false)
        XCTAssertEqual(g?.rowGap, SS.largePortrait.rowGap)
        XCTAssertEqual(g?.keyGap, SS.largePortrait.keyGap)
        XCTAssertEqual(g?.sideMargin, SS.largePortrait.sideMargin)
    }

    /// iPad / máy gập mở: chưa có số đo stock ⇒ giữ bố cục cũ (base + chỉnh tay × 4).
    func testPadAndUnfoldedKeepOldBase() {
        let pad = KeyGeometry.rowSpec(pad: true, landscape: false, unfolded: false, width: 834,
                                      base: 240, adjust: 0)
        XCTAssertFalse(pad.stock, "iPad không theo số đo iPhone")
        XCTAssertEqual(pad.unit, 60); XCTAssertEqual(pad.sideMargin, 3); XCTAssertEqual(pad.keyGap, 10)
        XCTAssertEqual(pad.gap, 10); XCTAssertEqual(pad.bottomTrim, 0)
        XCTAssertEqual(KeyGeometry.rowSpec(pad: true, landscape: false, unfolded: false, width: 834,
                                           base: 240, adjust: 4).unit, 64)
        let padL = KeyGeometry.rowSpec(pad: true, landscape: true, unfolded: false, width: 1194,
                                       base: 300, adjust: -2)
        XCTAssertEqual(padL.unit, 73)
        let duo = KeyGeometry.rowSpec(pad: false, landscape: true, unfolded: true, width: 801,
                                      base: 208, adjust: 0)
        XCTAssertFalse(duo.stock, "máy gập mở: chưa có số đo stock ⇒ giữ bố cục đã đo (208)")
        XCTAssertEqual(duo.unit, 52)
        XCTAssertEqual(KeyGeometry.rowSpec(pad: false, landscape: true, unfolded: true, width: 801,
                                           base: 208, adjust: 3).unit, 55)
    }

    /// iPhone: mức 0 = đúng số đo bàn phím gốc; ±a = bước hàng và phím (cả phím đáy) cùng ±a,
    /// khe giữa hàng, lề, phần cắt / đệm dưới hàng đáy giữ như stock.
    func testStockIsBaselineOfAdjust() {
        for (w, pitch, key): (CGFloat, CGFloat, CGFloat) in [(390, 54, 43), (402, 54, 43), (440, 56, 45), (430, 56, 45)] {
            let m = SS.metrics(width: w, landscape: false)!
            let zero = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: w,
                                           base: 216, adjust: 0)
            XCTAssertTrue(zero.stock)
            XCTAssertEqual(zero.unit, pitch, "\(w)")
            XCTAssertEqual(zero.letterKeyHeight, key, "\(w)")
            XCTAssertEqual(zero.bottomKeyHeight, key, "\(w): phím đáy cao như phím chữ (stock)")
            XCTAssertEqual(zero.sideMargin, 6.67); XCTAssertEqual(zero.keyGap, 6)
            XCTAssertEqual(zero.keyArea(numberRow: false), 4 * pitch - m.bottomTrim, "\(w)")
            for a: CGFloat in [-10, -4, 1, 4, 10] {
                let s = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: w,
                                            base: 216, adjust: a)
                let what = "\(w) a=\(a)"
                XCTAssertTrue(s.stock, what)
                XCTAssertEqual(s.unit, pitch + a, what)
                XCTAssertEqual(s.gap, zero.gap, what)
                XCTAssertEqual(s.letterKeyHeight, key + a, what)
                XCTAssertEqual(s.bottomKeyHeight, key + a, what)
                XCTAssertEqual(s.bottomTrim, zero.bottomTrim, what)
                XCTAssertEqual(s.bottomTop, zero.bottomTop, what)
                XCTAssertEqual(s.bottomPad, zero.bottomPad, what)
                XCTAssertEqual(s.bottomTop + s.bottomKeyHeight + s.bottomPad, s.bottomRowHeight, what)
                XCTAssertEqual(s.keyArea(numberRow: false), zero.keyArea(numberRow: false) + 4 * a, what)
            }
            // Ngoài phạm vi ±10 bị kẹp.
            XCTAssertEqual(KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: w,
                                               base: 216, adjust: 25).unit, pitch + 10)
            XCTAssertEqual(KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: w,
                                               base: 216, adjust: -25).unit, pitch - 10)
        }
        let l = KeyGeometry.rowSpec(pad: false, landscape: true, unfolded: false, width: 722,
                                    base: 162, adjust: 0)
        XCTAssertEqual(l.unit, 40); XCTAssertEqual(l.letterKeyHeight, 32); XCTAssertEqual(l.bottomKeyHeight, 32)
        XCTAssertEqual(l.keyArea(numberRow: false), 162, "4 × 40 + đệm dưới 2")
        XCTAssertEqual(l.bottomPad, 2)
        let l3 = KeyGeometry.rowSpec(pad: false, landscape: true, unfolded: false, width: 722,
                                     base: 162, adjust: 3)
        XCTAssertEqual(l3.unit, 43); XCTAssertEqual(l3.letterKeyHeight, 35); XCTAssertEqual(l3.bottomKeyHeight, 35)
        XCTAssertEqual(l3.bottomPad, 2)
        // SE: phím 42, đệm dưới 4; +2 ⇒ phím 44.
        let se = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: 375,
                                     base: 216, adjust: 2, homeButton: true)
        XCTAssertEqual(se.letterKeyHeight, 44); XCTAssertEqual(se.bottomKeyHeight, 44); XCTAssertEqual(se.bottomPad, 4)
        // Hàng số: phím số = 0.8 × phím chữ (không tính khe) — cả khi chỉnh tay.
        for a: CGFloat in [0, 5] {
            let p = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: 440,
                                        base: 216, adjust: a)
            XCTAssertEqual(KeyGeometry.numberRowHeight(unit: p.unit, gap: p.gap) - p.gap, 0.8 * (45 + a), accuracy: 0.001)
        }
    }

    /// Strip gợi ý preset = mép trên → đỉnh phím như thanh dự đoán stock (≈ 40 dọc).
    func testStockOpenStrip() {
        for w: CGFloat in [390, 402, 440] {
            let strip = SS.openStrip(width: w, landscape: false)!
            let m = SS.metrics(width: w, landscape: false)!
            XCTAssertEqual(strip, 29, "\(w)")
            XCTAssertEqual(strip + m.rowGap, m.predictiveTopPad, accuracy: 1, "\(w)")
        }
        XCTAssertEqual(SS.openStrip(width: 722, landscape: true), SS.defaultOpenStrip, "ngang không cao thêm")
    }

    // MARK: Chuyển đổi từ bản có công tắc "Kích thước như bàn phím iPhone"

    typealias RA = KeyGeometry.RowAdjust

    /// Bố cục mặc định CŨ (công tắc tắt) trên iPhone dọc: bước (216 + A·4)/4, khe 10, cắt 4.
    private func oldDefault(_ a: CGFloat) -> KeyGeometry.RowSpec {
        KeyGeometry.RowSpec(unit: 54 + a, gap: 10, bottomTrim: 4, bottomTop: 7, sideMargin: 6.5, keyGap: 6)
    }

    func testMigrationPure() {
        for a in -10...10 {
            for w: CGFloat in [375, 390, 402, 420, 440] {
                // Công tắc bật ⇒ đúng stock ⇒ 0.
                XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: true, fresh: false, pad: false, portraitWidth: w), 0)
                // Cài mới (chưa có khoá, App Group trống) ⇒ 0.
                XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: nil, fresh: true, pad: false, portraitWidth: w), 0)
            }
            // Công tắc tắt: giữ bước hàng cũ 54 + A.
            XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: false, fresh: false, pad: false, portraitWidth: 402), a)
            XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: false, fresh: false, pad: false, portraitWidth: 375), a)
            XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: false, fresh: false, pad: false, portraitWidth: 440),
                           max(a - 2, -10))
            XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: false, fresh: false, pad: false, portraitWidth: 420),
                           max(a - 2, -10))
            // Người dùng từ bản trước #119 (chưa có khoá công tắc, không phải cài mới) = tắt.
            XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: nil, fresh: false, pad: false, portraitWidth: 430),
                           max(a - 2, -10))
            // iPad: ngữ nghĩa không đổi ⇒ giữ nguyên (kể cả công tắc bật — iPad không áp).
            XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: false, fresh: false, pad: true, portraitWidth: 834), a)
            XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: true, fresh: false, pad: true, portraitWidth: 834), a)
            // Màn hình mở máy gập / chưa biết bề ngang: giữ nguyên.
            XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: false, fresh: false, pad: false, portraitWidth: 700), a)
            XCTAssertEqual(RA.migrated(oldAdjust: a, legacyStock: false, fresh: false, pad: false, portraitWidth: 0), a)
        }
        // Giá trị cũ ngoài phạm vi bị kẹp trước.
        XCTAssertEqual(RA.migrated(oldAdjust: 30, legacyStock: false, fresh: false, pad: false, portraitWidth: 402), 10)
        XCTAssertEqual(RA.migrated(oldAdjust: 30, legacyStock: false, fresh: false, pad: true, portraitWidth: 834), 10)
    }

    /// Sai số còn lại sau chuyển đổi (công tắc tắt): bước hàng giữ nguyên mọi máy. Máy thường:
    /// vùng phím, phím đáy và đáy từng hàng trùng; phím chữ thấp hơn 1 (khe stock 11).
    /// Máy lớn: cả khối phím nằm cao hơn 11 (đệm stock 7 + khe trên hàng đáy 11 thay 7).
    func testMigrationResidual() {
        for a in -8...10 {
            let old = oldDefault(CGFloat(a))
            let std = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: 402, base: 216,
                adjust: CGFloat(RA.migrated(oldAdjust: a, legacyStock: false, fresh: false, pad: false, portraitWidth: 402)))
            XCTAssertEqual(std.unit, old.unit, "\(a)")
            XCTAssertEqual(std.keyArea(numberRow: false), old.keyArea(numberRow: false), "\(a)")
            XCTAssertEqual(std.bottomKeyHeight, old.bottomKeyHeight, "\(a)")
            XCTAssertEqual(std.bottomRowHeight, old.bottomRowHeight, "\(a)")
            XCTAssertEqual(old.letterKeyHeight - std.letterKeyHeight, 1, "\(a)")
            let big = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: 440, base: 216,
                adjust: CGFloat(RA.migrated(oldAdjust: a, legacyStock: false, fresh: false, pad: false, portraitWidth: 440)))
            XCTAssertEqual(big.unit, old.unit, "\(a)")
            XCTAssertEqual(big.bottomKeyHeight, old.bottomKeyHeight, "\(a)")
            XCTAssertEqual(big.keyArea(numberRow: false) - old.keyArea(numberRow: false), 11, "\(a)")
        }
    }

    private func suite() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "vt.rowadj.\(UUID().uuidString)"))
    }

    // MARK: Mặc định = bàn phím iPhone cho người chưa từng chỉnh (tester 03/11/2026)

    /// Chuyển đổi 12/10 (thuần): không có khoá chiều cao hàng + không có công tắc ⇒ 0 mọi máy.
    /// Công tắc stock đã TẮT tường minh hoặc đã có giá trị ⇒ giữ bước hàng cũ như trước.
    func testUntouchedOldUserMigratesToStock() {
        for w: CGFloat in [375, 390, 402, 420, 430, 440] {
            XCTAssertEqual(RA.migrated(oldAdjust: nil, legacyStock: nil, fresh: false, pad: false, portraitWidth: w), 0, "\(w)")
        }
        XCTAssertEqual(RA.migrated(oldAdjust: nil, legacyStock: false, fresh: false, pad: false, portraitWidth: 440), -2,
                       "tắt công tắc stock = chọn bố cục cũ")
        XCTAssertEqual(RA.migrated(oldAdjust: 0, legacyStock: nil, fresh: false, pad: false, portraitWidth: 440), -2,
                       "đã có khoá (chỉnh rồi về 0) = chọn bố cục cũ")
        XCTAssertEqual(RA.migrated(oldAdjust: nil, legacyStock: nil, fresh: false, pad: true, portraitWidth: 834), 0)
    }

    /// Sửa một lần (thuần): chỉ đúng giá trị chuyển đổi của bố cục mặc định cũ (máy lớn −2) về 0.
    func testDefaultFixedPure() {
        for w: CGFloat in [420, 430, 440] {
            XCTAssertEqual(RA.defaultFixed(-2, pad: false, portraitWidth: w), 0, "\(w)")
            for v in [-10, -5, -3, -1, 0, 1, 2, 4, 10] {
                XCTAssertEqual(RA.defaultFixed(v, pad: false, portraitWidth: w), v, "\(w) \(v)")
            }
        }
        for v in -10...10 {
            // Máy thường: chuyển đổi cũ cho 0 sẵn ⇒ không có gì để sửa.
            for w: CGFloat in [375, 390, 402] {
                XCTAssertEqual(RA.defaultFixed(v, pad: false, portraitWidth: w), v, "\(w) \(v)")
            }
            XCTAssertEqual(RA.defaultFixed(v, pad: true, portraitWidth: 834), v, "iPad \(v)")
            XCTAssertEqual(RA.defaultFixed(v, pad: false, portraitWidth: 700), v, "máy gập mở \(v)")
            XCTAssertEqual(RA.defaultFixed(v, pad: false, portraitWidth: 0), v, "chưa biết bề ngang \(v)")
        }
    }

    /// Máy lớn đã qua chuyển đổi 12/10 với −2: bàn phím (chỉ đọc) vẽ 0 ngay; app ghi 0 + cờ một
    /// lần; sau đó người dùng tự chọn −2 thì giữ.
    func testAlreadyMigratedLargeDefaultFixedOnce() throws {
        let d = try suite()
        d.set(true, forKey: RA.migratedKey); d.set(-2, forKey: RA.key)
        XCTAssertEqual(RA.effectiveAdjust(d, pad: false, portraitWidth: 440), 0)
        XCTAssertEqual(d.object(forKey: RA.key) as? Int, -2, "bàn phím không ghi")
        XCTAssertEqual(RA.migrateIfNeeded(d, pad: false, portraitWidth: 440), 0)
        XCTAssertEqual(d.object(forKey: RA.key) as? Int, 0)
        XCTAssertTrue(d.bool(forKey: RA.defaultFixKey))
        XCTAssertEqual(RA.effectiveAdjust(d, pad: false, portraitWidth: 440), 0)
        // Tự chọn −2 sau khi sửa ⇒ giữ (cả app lẫn bàn phím).
        d.set(-2, forKey: RA.key)
        XCTAssertEqual(RA.migrateIfNeeded(d, pad: false, portraitWidth: 440), -2)
        XCTAssertEqual(RA.effectiveAdjust(d, pad: false, portraitWidth: 440), -2)
    }

    /// Đã qua chuyển đổi với giá trị khác (tự chọn) / máy thường / iPad: không đổi, chỉ ghi cờ.
    func testAlreadyMigratedExplicitValuesKept() throws {
        for (v, w, pad): (Int, CGFloat, Bool) in [(3, 440, false), (-5, 430, false), (-2, 402, false),
                                                  (-2, 375, false), (-2, 834, true), (4, 402, false)] {
            let d = try suite()
            d.set(true, forKey: RA.migratedKey); d.set(v, forKey: RA.key)
            XCTAssertEqual(RA.effectiveAdjust(d, pad: pad, portraitWidth: w), v, "\(v) \(w)")
            XCTAssertEqual(RA.migrateIfNeeded(d, pad: pad, portraitWidth: w), v, "\(v) \(w)")
            XCTAssertEqual(d.object(forKey: RA.key) as? Int, v)
            XCTAssertTrue(d.bool(forKey: RA.defaultFixKey))
        }
        // Đã chuyển đổi, chưa từng chỉnh (không khoá): vẫn 0, không ghi giá trị.
        let none = try suite()
        none.set(true, forKey: RA.migratedKey)
        XCTAssertEqual(RA.migrateIfNeeded(none, pad: false, portraitWidth: 440), 0)
        XCTAssertNil(none.object(forKey: RA.key))
    }

    /// Hình học người dùng cũ chưa từng chỉnh, máy lớn (Air / Plus / Pro Max), trước / sau sửa:
    /// trước bước 54 phím 43 (stock 56 / 45), vùng phím thấp hơn stock 8pt; sau = đúng stock.
    func testUntouchedLargePhoneMatchesStockAfterFix() throws {
        let d = try suite()
        d.set(true, forKey: "numberRow")    // người dùng cũ, chưa từng chỉnh chiều cao hàng
        let a = CGFloat(RA.migrateIfNeeded(d, pad: false, portraitWidth: 440))
        let s = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: 440, base: 216, adjust: a)
        let m = SS.largePortrait
        XCTAssertEqual(s.unit, m.pitch); XCTAssertEqual(s.letterKeyHeight, m.keyHeight)
        XCTAssertEqual(s.bottomKeyHeight, m.keyHeight)
        XCTAssertEqual(s.keyArea(numberRow: false), 4 * 56 + 7)
        let before = KeyGeometry.rowSpec(pad: false, landscape: false, unfolded: false, width: 440, base: 216, adjust: -2)
        XCTAssertEqual(before.letterKeyHeight, 43)
        XCTAssertEqual(s.keyArea(numberRow: false) - before.keyArea(numberRow: false), 8)
    }

    func testMigrateIfNeededFreshInstall() throws {
        let d = try suite()
        XCTAssertEqual(RA.effectiveAdjust(d, pad: false, portraitWidth: 440), 0)
        XCTAssertEqual(RA.migrateIfNeeded(d, pad: false, portraitWidth: 440), 0)
        XCTAssertTrue(d.bool(forKey: RA.migratedKey))
        XCTAssertNil(d.object(forKey: RA.key), "cài mới: không ghi gì ngoài cờ")
        XCTAssertEqual(RA.raise(d), 0)
    }

    func testMigrateIfNeededStockOn() throws {
        let d = try suite()
        d.set(true, forKey: RA.legacyStockKey); d.set(4, forKey: RA.key)
        XCTAssertEqual(RA.migrateIfNeeded(d, pad: false, portraitWidth: 440), 0)
        XCTAssertEqual(d.object(forKey: RA.key) as? Int, 0)
        XCTAssertNil(d.object(forKey: RA.legacyStockKey), "khoá công tắc cũ được dọn")
    }

    func testMigrateIfNeededStockOffLargeIdempotent() throws {
        let d = try suite()
        d.set(false, forKey: RA.legacyStockKey); d.set(4, forKey: RA.key)
        // Bàn phím chạy trước app: tính trong bộ nhớ, KHÔNG ghi.
        XCTAssertEqual(RA.effectiveAdjust(d, pad: false, portraitWidth: 440), 2)
        XCTAssertEqual(d.object(forKey: RA.key) as? Int, 4)
        XCTAssertFalse(d.bool(forKey: RA.migratedKey))
        // App chuyển đổi: cùng kết quả.
        XCTAssertEqual(RA.migrateIfNeeded(d, pad: false, portraitWidth: 440), 2)
        XCTAssertEqual(d.object(forKey: RA.key) as? Int, 2)
        XCTAssertEqual(RA.effectiveAdjust(d, pad: false, portraitWidth: 440), 2)
        // Chạy lại: không chuyển lần hai (kể cả sau khi người dùng chỉnh).
        XCTAssertEqual(RA.migrateIfNeeded(d, pad: false, portraitWidth: 440), 2)
        d.set(-3, forKey: RA.key)
        XCTAssertEqual(RA.migrateIfNeeded(d, pad: false, portraitWidth: 440), -3)
        XCTAssertEqual(RA.effectiveAdjust(d, pad: false, portraitWidth: 440), -3)
    }

    func testMigrateIfNeededStockOffStandardAndPreSeedUsers() throws {
        let std = try suite()
        std.set(false, forKey: RA.legacyStockKey); std.set(-3, forKey: RA.key)
        XCTAssertEqual(RA.migrateIfNeeded(std, pad: false, portraitWidth: 402), -3)
        // Người dùng từ bản trước #119 chưa mở app (không có khoá công tắc) + có cài đặt.
        // Chưa từng chỉnh chiều cao hàng ⇒ mặc định mới = bàn phím iPhone (0), kể cả máy lớn
        // (03/11/2026 — trước đó −2: nhỏ hơn stock).
        let pre = try suite()
        pre.set(true, forKey: "numberRow")
        XCTAssertEqual(RA.migrateIfNeeded(pre, pad: false, portraitWidth: 440), 0,
                       "chưa từng chỉnh ⇒ như bàn phím iPhone")
        XCTAssertNil(pre.object(forKey: RA.key))
        // Đã chỉnh (có khoá) ⇒ giữ bước hàng cũ như trước.
        let preSet = try suite()
        preSet.set(3, forKey: RA.key)
        XCTAssertEqual(RA.migrateIfNeeded(preSet, pad: false, portraitWidth: 440), 1)
        // Khoá chỉ có trong bản sao lưu (app truyền thêm) cũng tính là người dùng cũ.
        let extra = try suite()
        extra.set(true, forKey: "autoCorrect"); extra.set(2, forKey: RA.key)
        XCTAssertEqual(RA.migrateIfNeeded(extra, pad: false, portraitWidth: 440, extraStateKeys: ["autoCorrect"]), 0)
        // iPad: không đổi.
        let pad = try suite()
        pad.set(false, forKey: RA.legacyStockKey); pad.set(5, forKey: RA.key)
        XCTAssertEqual(RA.migrateIfNeeded(pad, pad: true, portraitWidth: 834), 5)
        XCTAssertEqual(pad.object(forKey: RA.key) as? Int, 5)
    }

    func testRaiseSetting() throws {
        XCTAssertEqual(RA.clampRaise(-4), 0); XCTAssertEqual(RA.clampRaise(24), 24); XCTAssertEqual(RA.clampRaise(60), 48)
        let d = try suite()
        XCTAssertEqual(RA.raise(d), 0)
        d.set(16, forKey: RA.raiseKey); XCTAssertEqual(RA.raise(d), 16)
        d.set(99, forKey: RA.raiseKey); XCTAssertEqual(RA.raise(d), 48)
        XCTAssertEqual(RA.raise(nil), 0)
    }

    /// Ảnh nền (app) cắt đúng tỉ lệ bàn phím: bước stock + chỉnh tay + strip stock + nâng.
    func testWallpaperSizeFollowsStockAndRaise() {
        let screen = CGSize(width: 440, height: 956)
        let s = Wallpaper.keyboardSize(screenSize: screen, pad: false, landscape: false, rowHeightAdjust: 0,
                                       numberRow: false, suggestions: true)
        XCTAssertEqual(s.height, 56 * 4 + 7 + 29 + 6)   // + thanh gợi ý Vừa (mặc định 18/10/2026)
        let a = Wallpaper.keyboardSize(screenSize: screen, pad: false, landscape: false, rowHeightAdjust: 4,
                                       numberRow: false, suggestions: true)
        XCTAssertEqual(a.height, 60 * 4 + 7 + 29 + 6)
        let r = Wallpaper.keyboardSize(screenSize: screen, pad: false, landscape: false, rowHeightAdjust: 4,
                                       numberRow: false, suggestions: true, raise: 12)
        XCTAssertEqual(r.height, a.height + 12)
        let big = Wallpaper.keyboardSize(screenSize: screen, pad: false, landscape: false, rowHeightAdjust: 0,
                                         numberRow: false, suggestions: false, raise: 400)
        XCTAssertEqual(big.height, 56 * 4 + 7 + 48, "nâng kẹp 48")
        let std = Wallpaper.keyboardSize(screenSize: CGSize(width: 402, height: 874), pad: false, landscape: false,
                                         rowHeightAdjust: -2, numberRow: false, suggestions: true)
        XCTAssertEqual(std.height, 52 * 4 - 4 + 29 + 6)
    }

    // MARK: Dải trống phía trên phím (#119 "thừa khoảng trắng khi đã tắt hết phụ trợ")

    func testHeadroomOnlyWhenSomethingDrawsAboveKeys() {
        XCTAssertEqual(KeyLayout.headroom(needsBalloon: true), KeyLayout.balloonHeadroom)
        XCTAssertEqual(KeyLayout.headroom(needsBalloon: false), KeyLayout.minimalHeadroom)
        let off = KeyLayout.chrome(keyArea: 212, strip: 0, mode: .keys, headroom: KeyLayout.minimalHeadroom)
        XCTAssertEqual(off.rowsTop, 2); XCTAssertEqual(off.total, 214); XCTAssertEqual(off.minTop, 2)
        // Strip mở không bị headroom ảnh hưởng.
        XCTAssertEqual(KeyLayout.chrome(keyArea: 212, strip: 34, mode: .keys, headroom: 2).rowsTop, 34)
        // Mặc định (headroom balloon) giữ như cũ.
        XCTAssertEqual(KeyLayout.chrome(keyArea: 212, strip: 0, mode: .keys).rowsTop, KeyLayout.balloonHeadroom)
    }

    // MARK: View thật

    @MainActor private func make(width: CGFloat, adjust: Int = 0, raise: Int = 0, suggestions: Bool = true,
                                 numberRow: Bool = false, needsGlobe: Bool = false) -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: needsGlobe, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 500))
        host.addSubview(kb)
        kb.frame = CGRect(x: 0, y: 0, width: width, height: 320)
        kb.configureInputKind(.normal)
        kb.numberRowEnabled = numberRow
        kb.setSuggestionsEnabled(suggestions)
        kb.layoutIfNeeded()
        kb.debugSetRowAdjust(adjust)
        kb.debugSetRaise(raise)
        settle(kb)
        return (kb, host)
    }
    /// Host cấp đúng mức xin.
    @MainActor private func settle(_ kb: KeyboardView) {
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        kb.frame.size.height = kb.debugRequestedHeight
        kb.setNeedsLayout(); kb.layoutIfNeeded()
    }
    private func frame(_ kb: KeyboardView, _ v: UIView) -> CGRect { kb.convert(v.bounds, from: v) }

    @MainActor func testPortraitMatchesStockPerWidth() throws {
        try XCTSkipIf(isPad)
        for (w, pitch, key): (CGFloat, CGFloat, CGFloat) in [(390, 54, 43), (402, 54, 43),
                                                              (420, 56, 45), (430, 56, 45), (440, 56, 45)] {
            let (kb, host) = make(width: w)
            let q = try XCTUnwrap(kb.debugLetterFrame("q")), a = try XCTUnwrap(kb.debugLetterFrame("a"))
            let z = try XCTUnwrap(kb.debugLetterFrame("z")), p = try XCTUnwrap(kb.debugLetterFrame("p"))
            XCTAssertEqual(q.height, key, accuracy: 0.5, "\(w) phím chữ")
            XCTAssertEqual(a.minY - q.minY, pitch, accuracy: 0.5, "\(w) bước hàng")
            XCTAssertEqual(z.minY - a.minY, pitch, accuracy: 0.5, "\(w) bước hàng")
            // Ngang như stock: lề 6.67, khe 6.
            XCTAssertEqual(q.minX, 6.67, accuracy: 0.5, "\(w)")
            XCTAssertEqual(p.maxX, w - 6.67, accuracy: 0.5, "\(w)")
            XCTAssertEqual(q.width, (w - 2 * 6.67 - 9 * 6) / 10, accuracy: 0.5, "\(w)")
            let m = try XCTUnwrap(SS.metrics(width: w, landscape: false))
            let num = frame(kb, try XCTUnwrap(kb.debugControl("Số")))
            XCTAssertEqual(num.height, key, accuracy: 0.5, "\(w) phím đáy")
            // Hàng đáy cùng bước stock; máy thường phím đáy stock nằm thấp hơn đáy view 4pt (vùng
            // 🌐/mic hệ thống) ⇒ phím đáy mình cao hơn stock đúng phần đó, 3 hàng chữ vẫn trùng.
            XCTAssertEqual(num.minY - z.minY, pitch - max(m.bottomTrim, 0), accuracy: 0.5, "\(w) hàng đáy")
            // Đỉnh phím hàng 1 cách mép trên như thanh dự đoán stock (~40) + "Chiều cao thanh gợi ý"
            // mặc định Vừa (+6, 18/10/2026); mức Thấp = đúng stock (kiểm cuối vòng).
            XCTAssertEqual(q.minY, m.predictiveTopPad + Self.bar, accuracy: 1, "\(w) mép trên → phím")
            XCTAssertEqual(kb.debugRequestedHeight, 29 + Self.bar + 4 * pitch - m.bottomTrim, accuracy: 0.5, "\(w) tổng")
            // Vị trí tính từ ĐÁY view (= 75pt trên đáy màn hình): hàng Q trùng stock. 440: stock
            // đỉnh Q cách đáy màn hình 295 ⇒ cách đáy view 220; 402: 276 ⇒ 201.
            let h = kb.bounds.height
            XCTAssertEqual(h - q.minY, 4 * pitch - m.rowGap - m.bottomTrim, accuracy: 0.5, "\(w) Q từ đáy")
            XCTAssertEqual(h - q.minY, w >= 420 ? 220 : 201, accuracy: 0.5, "\(w)")
            XCTAssertEqual(h - num.maxY, max(-m.bottomTrim, 0), accuracy: 0.5, "\(w) đệm dưới phím đáy")
            kb.debugSetBarHeight(.low); settle(kb)
            XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame("q")).minY, m.predictiveTopPad, accuracy: 1,
                           "\(w) Thấp: mép trên → phím như stock")
            XCTAssertEqual(kb.debugRequestedHeight, 29 + 4 * pitch - m.bottomTrim, accuracy: 0.5, "\(w) Thấp tổng")
            withExtendedLifetime(host) {}
        }
    }

    /// SE (nút Home — bàn phím có 🌐 riêng): phím 42, đệm dưới 4 như stock sát đáy màn hình.
    @MainActor func testHomeButtonPhone() throws {
        try XCTSkipIf(isPad)
        let (kb, host) = make(width: 375, needsGlobe: true)
        let q = try XCTUnwrap(kb.debugLetterFrame("q")), a = try XCTUnwrap(kb.debugLetterFrame("a"))
        XCTAssertEqual(q.height, 42, accuracy: 0.5)
        XCTAssertEqual(a.minY - q.minY, 54, accuracy: 0.5)
        let num = frame(kb, try XCTUnwrap(kb.debugControl("Số")))
        XCTAssertEqual(num.height, 42, accuracy: 0.5)
        XCTAssertEqual(kb.bounds.height - num.maxY, 4, accuracy: 0.5)
        XCTAssertEqual(q.minX, 6.5, accuracy: 0.5)
        withExtendedLifetime(host) {}
    }

    /// Chỉnh tay trên nền stock: phím chữ và phím đáy cùng ±a, khe/đệm stock giữ nguyên; về 0
    /// là đúng stock lại.
    @MainActor func testAdjustOnStockBaseline() throws {
        try XCTSkipIf(isPad)
        for (w, a): (CGFloat, Int) in [(440, 3), (440, -5), (402, 4), (402, -10)] {
            let (kb, host) = make(width: w, adjust: a)
            let m = try XCTUnwrap(SS.metrics(width: w, landscape: false))
            let q = try XCTUnwrap(kb.debugLetterFrame("q")), z = try XCTUnwrap(kb.debugLetterFrame("z"))
            let aa = try XCTUnwrap(kb.debugLetterFrame("a"))
            let num = frame(kb, try XCTUnwrap(kb.debugControl("Số")))
            let what = "\(w) a=\(a)"
            XCTAssertEqual(q.height, m.keyHeight + CGFloat(a), accuracy: 0.5, what)
            XCTAssertEqual(aa.minY - q.minY, m.pitch + CGFloat(a), accuracy: 0.5, what)
            XCTAssertEqual(num.height, m.keyHeight + CGFloat(a), accuracy: 0.5, what)
            // Khe trên hàng đáy như stock (máy thường 54 − 4 − 43 = 7; máy lớn 56 − 45 = 11).
            XCTAssertEqual(num.minY - z.maxY, m.bottomTrim >= 0 ? m.pitch - m.bottomTrim - m.keyHeight
                                                                : m.rowGap, accuracy: 0.5, what)
            XCTAssertEqual(kb.bounds.height - num.maxY, max(-m.bottomTrim, 0), accuracy: 0.5, what)
            XCTAssertEqual(kb.debugRequestedHeight, 29 + Self.bar + 4 * (m.pitch + CGFloat(a)) - m.bottomTrim, accuracy: 0.5, what)
            kb.debugSetRowAdjust(0); settle(kb)
            XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame("q")).height, m.keyHeight, accuracy: 0.5, what)
            XCTAssertEqual(kb.debugRequestedHeight, 29 + Self.bar + 4 * m.pitch - m.bottomTrim, accuracy: 0.5, what)
            withExtendedLifetime(host) {}
        }
    }

    @MainActor func testLandscapeMatchesStock() throws {
        try XCTSkipIf(isPad)
        for w: CGFloat in [694, 722] {
            let (kb, host) = make(width: w)
            let q = try XCTUnwrap(kb.debugLetterFrame("q")), a = try XCTUnwrap(kb.debugLetterFrame("a"))
            let p = try XCTUnwrap(kb.debugLetterFrame("p")), w2 = try XCTUnwrap(kb.debugLetterFrame("w"))
            XCTAssertEqual(q.height, 32, accuracy: 0.5)
            XCTAssertEqual(a.minY - q.minY, 40, accuracy: 0.5)
            XCTAssertEqual(q.minX, 4.33, accuracy: 0.5)
            XCTAssertEqual(p.maxX, w - 4.33, accuracy: 0.5)
            XCTAssertEqual(w2.minX - q.maxX, 6.67, accuracy: 0.5, "khe ngang stock")
            XCTAssertEqual(frame(kb, try XCTUnwrap(kb.debugControl("Số"))).height, 32, accuracy: 0.5)
            withExtendedLifetime(host) {}
        }
    }

    /// Xoay khi preset bật: khe/lề dọc ↔ ngang khác nhau ⇒ dựng lại, không giữ khe cũ.
    @MainActor func testRotationRebuildsStockGeometry() throws {
        try XCTSkipIf(isPad)
        let (kb, host) = make(width: 440)
        XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame("q")).minX, 6.67, accuracy: 0.5)
        host.frame.size.width = 722; kb.frame.size.width = 722
        settle(kb)
        let q = try XCTUnwrap(kb.debugLetterFrame("q")), w2 = try XCTUnwrap(kb.debugLetterFrame("w"))
        XCTAssertEqual(q.minX, 4.33, accuracy: 0.5)
        XCTAssertEqual(w2.minX - q.maxX, 6.67, accuracy: 0.5)
        XCTAssertEqual(q.height, 32, accuracy: 0.5)
        host.frame.size.width = 440; kb.frame.size.width = 440
        settle(kb)
        let q2 = try XCTUnwrap(kb.debugLetterFrame("q"))
        XCTAssertEqual(q2.minX, 6.67, accuracy: 0.5)
        XCTAssertEqual(q2.height, 45, accuracy: 0.5)
        withExtendedLifetime(host) {}
    }

    /// Hàng số + preset: phím số 0.8× phím chữ, hàng chữ vẫn bước stock.
    @MainActor func testNumberRowWithPreset() throws {
        try XCTSkipIf(isPad)
        let (kb, host) = make(width: 440, numberRow: true)
        let q = try XCTUnwrap(kb.debugLetterFrame("q")), a = try XCTUnwrap(kb.debugLetterFrame("a"))
        let one = frame(kb, try XCTUnwrap(kb.debugKeyButton("1")))
        XCTAssertEqual(q.height, 45, accuracy: 0.5)
        XCTAssertEqual(a.minY - q.minY, 56, accuracy: 0.5)
        XCTAssertEqual(one.height, 0.8 * 45, accuracy: 0.75)
        XCTAssertEqual(q.minY - one.maxY, 11, accuracy: 0.5, "khe stock giữa hàng số và hàng chữ")
        withExtendedLifetime(host) {}
    }

    /// Một tay + preset: thu hẹp như cũ, chiều cao phím theo preset.
    @MainActor func testOneHandWithPreset() throws {
        try XCTSkipIf(isPad)
        let (kb, host) = make(width: 440)
        kb.configureOneHand(.right)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let i = OneHand.insets(width: 440, side: .right)
        let q = try XCTUnwrap(kb.debugLetterFrame("q")), p = try XCTUnwrap(kb.debugLetterFrame("p"))
        XCTAssertEqual(q.minX, i.left + 6.67, accuracy: 0.5)
        XCTAssertEqual(p.maxX, 440 - i.right - 6.67, accuracy: 0.5)
        XCTAssertEqual(q.height, 45, accuracy: 0.5)
        withExtendedLifetime(host) {}
    }

    /// Tách đôi (ngang) + preset: vẫn tách, phím cao 32 như stock ngang.
    @MainActor func testSplitWithPreset() throws {
        try XCTSkipIf(isPad)
        let (kb, host) = make(width: 874)
        kb.debugSetSplit(true); settle(kb)
        XCTAssertTrue(kb.debugIsSplit)
        XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame("q")).height, 32, accuracy: 0.5)
        let rows = kb.debugRowFrames()
        for r in rows.dropLast() { XCTAssertEqual(r.height, 40, accuracy: 0.5) }
        XCTAssertEqual(rows.last?.height ?? 0, 42, accuracy: 0.5, "hàng đáy + đệm dưới 2 (stock ngang)")
        withExtendedLifetime(host) {}
    }

    /// Mọi tổ hợp phụ trợ: gợi ý (tắt / bật / thu gọn không áp ở đây), ô phóng to, giữ phím ra
    /// ký tự phụ. Dải trên phím = strip khi gợi ý bật; tắt gợi ý thì chỉ
    /// headroom balloon khi CÓ thứ vẽ lên trên phím, còn không thì 2pt (khe + 2 ≈ stock 12–13).
    @MainActor func testBlankBandAllHelperCombos() throws {
        try XCTSkipIf(isPad)
        do {
            for suggestions in [false, true] {
                for preview in [false, true] {
                    for alts in [false, true] {
                        let (kb, host) = make(width: 440, suggestions: suggestions)
                        kb.debugSetKeyPreview(preview)
                        kb.configureKeyAlternates(numbers: alts, symbols: false)
                        kb.debugRefreshChrome(); settle(kb)
                        let what = "gợi ý \(suggestions) phóng to \(preview) ký tự phụ \(alts)"
                        let strip: CGFloat = suggestions ? 29 + Self.bar : 0
                        let head: CGFloat = (preview || alts) ? KeyLayout.balloonHeadroom : KeyLayout.minimalHeadroom
                        XCTAssertEqual(kb.debugRowsTop, max(strip, head), what)
                        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
                        XCTAssertEqual(q.minY, max(strip, head) + 11, accuracy: 0.5, what)
                        if !suggestions && !preview && !alts {
                            // Tắt hết: đỉnh phím cách mép trên ≈ stock không thanh dự đoán (12–13).
                            XCTAssertLessThanOrEqual(q.minY, 13.5, what)
                        }
                        if preview || alts {
                            // Balloon hàng đầu vẫn nằm trọn trong view.
                            let b = try XCTUnwrap(kb.debugBalloon(letter: "e", text: "3"), what)
                            XCTAssertGreaterThanOrEqual(b.frame.minY, -0.5, what)
                            XCTAssertGreaterThanOrEqual(b.label.minY, -0.5, what)
                        }
                        withExtendedLifetime(host) {}
                    }
                }
            }
        }
    }

    // MARK: Nâng bàn phím

    /// Bản chụp hình học để so: chiều cao xin, đỉnh q, đáy hàng đáy (tính từ ĐỈNH view).
    @MainActor private func snapshot(_ kb: KeyboardView) throws -> (h: CGFloat, q: CGRect, lastRow: CGRect) {
        (kb.debugRequestedHeight, try XCTUnwrap(kb.debugLetterFrame("q")), try XCTUnwrap(kb.debugRowFrames().last))
    }

    /// Nâng R: view cao thêm R, phím giữ nguyên cỡ và vị trí tính từ ĐỈNH (tức là dời lên R so
    /// với đáy), dưới hàng đáy là đệm trống R (+ đệm stock). 0 = y hệt không nâng.
    @MainActor func testRaiseAddsBottomPadding() throws {
        try XCTSkipIf(isPad)
        typealias Case = (w: CGFloat, numberRow: Bool, suggestions: Bool, adjust: Int)
        let cases: [Case] = [(402, false, true, 0), (440, false, true, 0), (440, true, true, 2),
                             (440, false, false, -3), (722, false, true, 0), (874, true, false, 0)]
        for c in cases {
            let (base, h0) = make(width: c.w, adjust: c.adjust, suggestions: c.suggestions, numberRow: c.numberRow)
            let b = try snapshot(base)
            for r in [0, 4, 24, 48] {
                let (kb, host) = make(width: c.w, adjust: c.adjust, raise: r, suggestions: c.suggestions,
                                      numberRow: c.numberRow)
                let s = try snapshot(kb)
                let what = "\(c) nâng \(r)"
                XCTAssertEqual(s.h, b.h + CGFloat(r), accuracy: 0.5, what)
                XCTAssertEqual(s.q.minY, b.q.minY, accuracy: 0.5, what)
                XCTAssertEqual(s.q.height, b.q.height, accuracy: 0.5, what)
                XCTAssertEqual(s.q.minX, b.q.minX, accuracy: 0.5, what)
                XCTAssertEqual(s.lastRow.height, b.lastRow.height, accuracy: 0.5, what)
                XCTAssertEqual(kb.bounds.height - s.lastRow.maxY, CGFloat(r), accuracy: 0.5, what)
                XCTAssertEqual(kb.bounds.height - s.q.minY, base.bounds.height - b.q.minY + CGFloat(r),
                               accuracy: 0.5, what)
                withExtendedLifetime(host) {}
            }
            withExtendedLifetime(h0) {}
        }
    }

    @MainActor func testRaiseClampAndLiveChange() throws {
        try XCTSkipIf(isPad)
        let (kb, host) = make(width: 402)
        let b = try snapshot(kb)
        kb.debugSetRaise(200); settle(kb)
        XCTAssertEqual(kb.debugRequestedHeight, b.h + 48, accuracy: 0.5, "kẹp 48")
        kb.debugSetRaise(-8); settle(kb)
        XCTAssertEqual(kb.debugRequestedHeight, b.h, accuracy: 0.5, "âm ⇒ 0")
        kb.debugSetRaise(0); settle(kb)
        let s = try snapshot(kb)
        XCTAssertEqual(s.h, b.h, accuracy: 0.01); XCTAssertEqual(s.q, b.q); XCTAssertEqual(s.lastRow, b.lastRow)
        withExtendedLifetime(host) {}
    }

    /// Nâng + một tay / tách đôi: phím vẫn nằm trên đệm, cỡ không đổi.
    @MainActor func testRaiseWithOneHandAndSplit() throws {
        try XCTSkipIf(isPad)
        let (kb, host) = make(width: 440, raise: 20)
        kb.configureOneHand(.left); settle(kb)
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        XCTAssertEqual(q.height, 45, accuracy: 0.5)
        XCTAssertEqual(kb.bounds.height - (kb.debugRowFrames().last?.maxY ?? 0), 20, accuracy: 0.5)
        let (sp, host2) = make(width: 874, raise: 16)
        sp.debugSetSplit(true); settle(sp)
        XCTAssertTrue(sp.debugIsSplit)
        XCTAssertEqual(try XCTUnwrap(sp.debugLetterFrame("q")).height, 32, accuracy: 0.5)
        XCTAssertEqual(sp.bounds.height - (sp.debugRowFrames().last?.maxY ?? 0), 16, accuracy: 0.5)
        withExtendedLifetime(host) {}; withExtendedLifetime(host2) {}
    }
}
