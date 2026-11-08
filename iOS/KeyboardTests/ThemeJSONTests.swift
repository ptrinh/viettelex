// "Giao diện JSON": theme có sẵn từ JSON = palette cũ, đọc chặt + lỗi, ca chung với Android
// (Fixtures/theme-json-cases.txt), fuzz không crash, giới hạn thời gian/bộ nhớ, dán (trùng id, giới hạn),
// sửa = bản vá + đặt lại, xoá, cổng Plus (giữ dữ liệu), sao lưu khứ hồi. Android: ThemeSpecTests.kt.
import XCTest

final class ThemeJSONTests: XCTestCase {
    private var savedDefaults: UserDefaults!
    private var savedPaywall = false
    private var suite = ""
    private var store = ""
    private var d: UserDefaults!

    override func setUp() {
        super.setUp()
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        suite = "themejson-\(UUID().uuidString)"
        PlusGate.defaults = UserDefaults(suiteName: suite)!
        store = "themejson-store-\(UUID().uuidString)"
        d = UserDefaults(suiteName: store)!
    }

    override func tearDown() {
        PlusGate.defaults.removePersistentDomain(forName: suite)
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        d.removePersistentDomain(forName: store)
        super.tearDown()
    }

    private func lockPlus() {
        PlusGate.paywallEnabled = true
        PlusGate.setPurchased(false)
        PlusGate.debugOverride = false
    }

    private static let caseA = ##"{"v":1,"name":{"vi":"Thử"},"light":{"key":"#ffffff","special":"#DDDDDD","ink":"#000000","accent":"#0a84ff","bg":"#EEEEEE"}}"##
    private static func spec(_ text: String) throws -> ThemeSpec {
        let o = ThemeSpecParser.parse(text)
        return try XCTUnwrap(o.spec, "\(o.issues)")
    }

    // MARK: theme có sẵn

    /// Nguồn duy nhất themes/builtin-themes.json ⇒ chuỗi nhúng trùng từng ký tự (Android kiểm phía mình).
    func testBuiltinSourceMatchesEmbedded() throws {
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("themes/builtin-themes.json")
        let text = try String(contentsOf: src, encoding: .utf8)
        XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines),
                       BuiltinThemesData.json.trimmingCharacters(in: .whitespacesAndNewlines),
                       "chạy python3 Scripts/gen-builtin-themes.py")
    }

    func testEveryBuiltinParsesAndRoundTrips() throws {
        let native: Set<KeyboardTheme> = [.system, .glass]
        XCTAssertEqual(Set(BuiltinThemes.specs.keys), Set(KeyboardTheme.allCases.filter { !native.contains($0) }.map(\.rawValue)))
        for (id, s) in BuiltinThemes.specs {
            let t = try XCTUnwrap(KeyboardTheme(rawValue: id))
            if !L10n.isEnglish { XCTAssertEqual(s.nameVi, t.title, "tên vi = khoá L10n") }
            XCTAssertTrue(ThemeSpecParser.contrastIssues(s).filter(\.isError).isEmpty, id)
            // spec → palette → spec: y nguyên (chưa tuỳ chỉnh gì).
            var back = ThemeSpec.export(id: id, nameVi: s.nameVi, nameEn: s.nameEn,
                                        light: s.palette(dark: false), dark: s.palette(dark: true), style: s.typography)
            back.schedule = s.schedule   // lịch theo giờ (Theo giờ) không nằm trong palette — đi riêng
            XCTAssertEqual(back.canonical, s.canonical, id)
            // Chuỗi chuẩn đọc lại = chính nó.
            XCTAssertEqual(try Self.spec(s.canonical).canonical, s.canonical, id)
            // "Chép JSON" khi chưa chỉnh = theme gốc.
            XCTAssertEqual(ThemeSettings().exportSpec(for: t).canonical, s.canonical, id)
        }
    }

    // MARK: ca chung với Android

    private struct Case { let name, expect, canonical, input: String }

    static func generate(_ input: String) -> Data {
        if input.hasPrefix("b64:") { return Data(base64Encoded: String(input.dropFirst(4))) ?? Data() }
        guard input.hasPrefix("gen:") else { return Data(input.utf8) }
        let p = input.split(separator: ":").map(String.init)
        let n = p.count > 2 ? Int(p[2]) ?? 0 : 0
        let slots = ##""light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}"##
        switch p.count > 1 ? p[1] : "" {
        case "size":
            let a = caseA
            return Data((a + String(repeating: " ", count: max(0, n - a.utf8.count))).utf8)
        case "deep": return Data((String(repeating: "[", count: n) + "1" + String(repeating: "]", count: n)).utf8)
        case "deepobj": return Data((String(repeating: #"{"a":"#, count: n) + "1" + String(repeating: "}", count: n)).utf8)
        case "longname": return Data(#"{"v":1,"name":{"vi":"\#(String(repeating: "a", count: n))"},\#(slots)}"#.utf8)
        case "longkey": return Data(#"{"\#(String(repeating: "k", count: n))":1}"#.utf8)
        case "skins", "skinspressed":
            let letters = ThemeAssetSpec.letterKeys.prefix(n).enumerated().map { i, l in
                let pr = p[1] == "skinspressed" ? #","pressed":{"url":"https://example.com/p\#(i).png"}"# : ""
                return #""\#(l)":{"url":"https://example.com/k\#(i).png"\#(pr)}"#
            }
            return Data(#"{"v":1,"name":{"vi":"x"},\#(slots),"keys":{\#(letters.joined(separator: ","))}}"#.utf8)
        default: return Data()
        }
    }

    private func fixtureLines() throws -> [[String]] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "theme-json-cases", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }.map { $0.components(separatedBy: "\t") }
    }

    func testSharedCasesWithAndroid() throws {
        var specs: [String: ThemeSpec] = [:]
        var n = 0
        for c in try fixtureLines() where c.first == "CASE" {
            XCTAssertEqual(c.count, 5, c.joined(separator: "|"))
            guard c.count == 5 else { continue }
            let name = c[1], expect = c[2], canonical = c[3]
            let out = ThemeSpecParser.parse(Self.generate(c[4]))
            let codes = out.issues.map(\.code.rawValue)
            if expect.hasPrefix("err:") {
                XCTAssertNil(out.spec, name)
                XCTAssertTrue(codes.contains(String(expect.dropFirst(4))), "\(name): \(codes)")
            } else {
                let s = try XCTUnwrap(out.spec, "\(name): \(out.issues)")
                specs[name] = s
                if canonical != "-" { XCTAssertEqual(s.canonical, canonical, name) }
                if let w = expect.split(separator: "+").dropFirst().first {
                    XCTAssertTrue(codes.contains(String(w)), "\(name): \(codes)")
                } else {
                    XCTAssertTrue(out.issues.isEmpty, "\(name): \(codes)")
                }
            }
            n += 1
        }
        XCTAssertGreaterThan(n, 50)
        func hex(_ c: RGBA?) -> String { c.map { String(format: "%08X", ThemeColorCode.argb($0)) } ?? "-" }
        for c in try fixtureLines() where c.first == "PAL" {
            let s = try XCTUnwrap(specs[c[1]], c[1])
            let p = s.palette(dark: c[2] == "1")
            let deco = p.decoration.map { "\($0.motif.rawValue):\(hex($0.color))@\($0.density)" } ?? "-"
            let got = [hex(p.background), hex(p.keyFill), hex(p.specialFill), hex(p.ink), hex(p.accent), hex(p.accentInk),
                       hex(p.trail), hex(p.balloon), hex(p.keyBorder), deco].joined(separator: " ")
            XCTAssertEqual(got, c[3], "PAL \(c[1]) \(c[2])")
        }
        // Kế hoạch tệp tải về: cùng JSON ⇒ cùng chuỗi kế hoạch hai nền tảng.
        var plans = 0
        for c in try fixtureLines() where c.first == "PLAN" {
            let s = try XCTUnwrap(specs[c[1]], c[1])
            XCTAssertEqual(ThemeAssetPlan.make(s.typography.assets).description, c[2], "PLAN \(c[1])")
            plans += 1
        }
        XCTAssertGreaterThanOrEqual(plans, 6)
        // Theo giờ: mục lịch + màu chữ ở phút cho trước (cả nửa đêm / ngoài ngày) — chung Android.
        var scheds = 0
        for c in try fixtureLines() where c.first == "SCHED" {
            let s = try XCTUnwrap(specs[c[1]], c[1])
            let m = try XCTUnwrap(Int(c[2]))
            XCTAssertEqual(s.scheduleIndex(minute: m), Int(c[3]), "SCHED \(c[1]) \(m)")
            XCTAssertEqual(hex(ThemeSpec.palette(s.slots(dark: false, minute: m)).ink), c[4], "SCHED ink \(c[1]) \(m)")
            XCTAssertEqual(s.slots(dark: true, minute: m), s.slots(dark: false, minute: m), "lịch bỏ qua sáng/tối")
            scheds += 1
        }
        XCTAssertGreaterThanOrEqual(scheds, 6)
    }

    // MARK: fuzz — không crash, hoặc model hợp lệ hoặc lỗi

    private struct RNG { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 } }

    func testFuzzNeverCrashes() throws {
        let seeds = [Self.caseA, try Self.spec(Self.caseA).canonical] + BuiltinThemes.specs.values.map(\.canonical)
        var r = RNG(s: 0x5EED)
        let junk: [String] = ["{", "}", "[", "]", "\"", ":", ",", "null", "true", "-", "9", "1e9", "\\u", "\\", "#", "NaN",
                              "999999999999", "\u{0}", "\u{FEFF}", "💖", "\"name\"", "{\"a\":", "[[[[", "\"#FFFFFF\""]
        var oks = 0, errs = 0
        for i in 0..<4000 {
            var bytes = Array(Data(seeds[Int(r.next() % UInt64(seeds.count))].utf8))
            switch i % 6 {
            case 0: bytes = Array(bytes.prefix(Int(r.next() % UInt64(bytes.count + 1))))                 // cắt cụt
            case 1: for _ in 0...(r.next() % 4) where !bytes.isEmpty {                                       // lật byte
                        let k = Int(r.next() % UInt64(bytes.count)); bytes[k] ^= UInt8(1 << (r.next() % 8)) }
            case 2: let k = Int(r.next() % UInt64(bytes.count + 1))                                         // chèn rác
                    bytes.insert(contentsOf: Array(junk[Int(r.next() % UInt64(junk.count))].utf8), at: k)
            case 3: if let a = bytes.firstIndex(of: UInt8(ascii: "\"")) {                                    // đổi kiểu
                        bytes.replaceSubrange(a..<min(bytes.count, a + 8), with: Array("12345,".utf8)) }
            case 4: bytes += Array(String(repeating: "[", count: Int(r.next() % 2000)).utf8)                 // lồng sâu
            default: bytes = (0..<Int(r.next() % 300)).map { _ in UInt8(r.next() % 256) }                    // ngẫu nhiên
            }
            let out = ThemeSpecParser.parse(Data(bytes))
            if out.spec != nil { oks += 1; XCTAssertTrue(out.errors.isEmpty) } else { errs += 1; XCTAssertFalse(out.errors.isEmpty) }
            // Chuỗi chuẩn của model hợp lệ luôn đọc lại được và ổn định.
            if let s = out.spec { XCTAssertEqual(ThemeSpecParser.parse(s.canonical).spec?.canonical, s.canonical) }
            _ = KeyStyleStore.parse(String(decoding: bytes, as: UTF8.self))
            _ = CustomThemeStore.parse(String(decoding: bytes, as: UTF8.self))
        }
        XCTAssertGreaterThan(oks, 0); XCTAssertGreaterThan(errs, 1000)
        // Số / chuỗi khổng lồ.
        XCTAssertFalse(ThemeSpecParser.parse(Data(("{\"v\":" + String(repeating: "9", count: 10_000) + "}").utf8)).errors.isEmpty)
        XCTAssertEqual(ThemeSpecParser.parse(String(repeating: "a", count: 100_000)).errors.first?.code, .tooLarge)
        // Lỗi cú pháp báo "dòng:cột" (Android cùng giá trị).
        XCTAssertEqual(ThemeSpecParser.parse("{\n  \"v\": 1,,\n}").errors.first, ThemeIssue(code: .syntax, path: "2:10"))
    }

    // MARK: thời gian / bộ nhớ (bàn phím)

    func testParse16KBIsFastAndSmall() throws {
        let big = String(decoding: Self.generate("gen:size:16384"), as: UTF8.self)
        let nasty = "{\"v\":1,\"name\":{\"vi\":\"" + String(repeating: "\\u00e0", count: 2700) + "\"}}"   // ~16 KB, lỗi tooLong
        XCTAssertNotNil(ThemeSpecParser.parse(big).spec)
        let before = Self.footprint()
        let t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 { _ = ThemeSpecParser.parse(big); _ = ThemeSpecParser.parse(nasty) }
        let per = (CFAbsoluteTimeGetCurrent() - t0) / 200 * 1000
        XCTAssertLessThan(per, 5, "đọc 16 KB phải < 5 ms (đo \(per) ms)")
        let grew = Self.footprint() - before
        XCTAssertLessThan(grew, 8 << 20, "không phình bộ nhớ (\(grew) byte)")
    }

    private static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    // MARK: dán

    func testPasteCollisionAndLimits() throws {
        var store: [String: ThemeSpec] = [:]
        var s = try Self.spec(Self.caseA)
        s.id = "peach"                                                    // trùng theme có sẵn
        XCTAssertEqual(try ThemeJSONActions.commitPaste(s, store: &store).get(), "peach-2")
        XCTAssertEqual(try ThemeJSONActions.commitPaste(s, store: &store).get(), "peach-3")
        s.id = nil
        XCTAssertEqual(try ThemeJSONActions.commitPaste(s, store: &store).get(), "custom")
        XCTAssertEqual(try ThemeJSONActions.commitPaste(s, store: &store).get(), "custom-2")
        XCTAssertEqual(store["peach-2"]?.id, "peach-2")
        for _ in store.count..<CustomThemeStore.maxThemes { _ = ThemeJSONActions.commitPaste(s, store: &store) }
        XCTAssertEqual(store.count, CustomThemeStore.maxThemes)
        guard case .failure(let e) = ThemeJSONActions.commitPaste(s, store: &store) else { return XCTFail("phải chặn ở 50") }
        XCTAssertEqual(e.code, .tooMany)
        // Kho lưu / đọc lại y nguyên; mục hỏng bị bỏ, không crash.
        CustomThemeStore.save(store, d)
        XCTAssertEqual(CustomThemeStore.load(d), store)
        XCTAssertEqual(CustomThemeStore.parse(#"{"x":{"v":1},"peach":{"v":1}}"#), [:])
        XCTAssertEqual(CustomThemeStore.parse("rác"), [:])
        // Xem trước không ghi gì; văn bản sai ⇒ lỗi rõ ràng.
        XCTAssertNotNil(ThemeJSONActions.preview(Self.caseA).spec)
        XCTAssertEqual(ThemeJSONActions.preview("{oops").spec, nil)
        XCTAssertFalse(ThemeJSONActions.preview("{oops").issues.first?.message.isEmpty ?? true)
    }

    // MARK: sửa / đặt lại / xoá / chọn

    func testEditBuiltinIsOverrideAndResetRemovesIt() throws {
        var s = ThemeSettings(theme: .peach)
        var store: [String: ThemeSpec] = [:]
        // Chép rồi lưu nguyên ⇒ không tạo tuỳ chỉnh.
        let copied = try XCTUnwrap(ThemeJSONActions.copyText(.builtin(.peach), settings: s, store: store))
        XCTAssertTrue(ThemeJSONActions.save(copied, to: .builtin(.peach), settings: &s, store: &store).ok)
        XCTAssertNil(s.keyStyles["peach"])
        // Đổi màu phím chế độ sáng + bo góc ⇒ bản vá đúng chế độ đó.
        let edited = copied.replacingOccurrences(of: "\"#FFF8F7\"", with: "\"#102030\"")
            .replacingOccurrences(of: "\"#4A2226\"", with: "\"#FFFFFF\"")
            .replacingOccurrences(of: "\"v\": 1", with: "\"corner\": 0,\n  \"v\": 1")
        let r = ThemeJSONActions.save(edited, to: .builtin(.peach), settings: &s, store: &store)
        XCTAssertTrue(r.ok, "\(r.issues)")
        let st = try XCTUnwrap(s.keyStyles["peach"])
        XCTAssertEqual(st.light.key, 0xFF10_2030); XCTAssertEqual(st.light.ink, 0xFFFF_FFFF)
        XCTAssertTrue(st.dark.isEmpty)
        XCTAssertEqual(st.corner, 0)
        let p = s.palette(systemDark: false, wallpaperActive: false)
        XCTAssertEqual(ThemeColorCode.argb(p.keyFill), 0xFF10_2030)
        XCTAssertEqual(s.palette(systemDark: true, wallpaperActive: false), ThemeSettings(theme: .peach).palette(systemDark: true, wallpaperActive: false))
        // Chép lại = đúng thứ đã sửa.
        XCTAssertEqual(try Self.spec(try XCTUnwrap(ThemeJSONActions.copyText(.builtin(.peach), settings: s, store: store))).canonical,
                       try Self.spec(edited).canonical)
        // Điều khiển có cấu trúc sửa CÙNG bản vá (màu nhấn) — giữ bản vá JSON.
        s.keyStyle.accentColor = 0x00FF00
        XCTAssertEqual(s.keyStyles["peach"]?.light.key, 0xFF10_2030)
        XCTAssertEqual(ThemeColorCode.argb(s.palette(systemDark: false, wallpaperActive: false).accent), 0xFF00_FF00)
        // Lỗi ⇒ không đổi gì.
        let before = s
        XCTAssertFalse(ThemeJSONActions.save(#"{"v":1}"#, to: .builtin(.peach), settings: &s, store: &store).ok)
        XCTAssertEqual(s, before)
        // Đặt lại.
        ThemeJSONActions.reset(.peach, settings: &s)
        XCTAssertNil(s.keyStyles["peach"])
        XCTAssertEqual(s.palette(systemDark: false, wallpaperActive: false), ThemeSettings(theme: .peach).palette(systemDark: false, wallpaperActive: false))
        // Bỏ nền theme có nền ⇒ cảnh báo, giữ nền.
        let noBg = try Self.spec(copied)
        var nb = noBg; nb.light.bg = nil; nb.dark?.bg = nil
        let w = ThemeJSONActions.save(nb.json.pretty, to: .builtin(.peach), settings: &s, store: &store)
        XCTAssertTrue(w.ok); XCTAssertTrue(w.issues.contains { $0.code == .bgKept })
        XCTAssertNotNil(s.palette(systemDark: false, wallpaperActive: false).background)
        // Hệ thống / Kính (không có JSON gốc) vẫn sửa được.
        var g = ThemeSettings(theme: .glass)
        let gc = try XCTUnwrap(ThemeJSONActions.copyText(.builtin(.glass), settings: g, store: store))
        XCTAssertTrue(ThemeJSONActions.save(gc, to: .builtin(.glass), settings: &g, store: &store).ok)
        XCTAssertNil(g.keyStyles["glass"], "chép rồi lưu nguyên ⇒ không có bản vá")
    }

    func testCustomThemeSelectEditDeleteAndKeyboardLoad() throws {
        var s = ThemeSettings()
        var store: [String: ThemeSpec] = [:]
        let id = try ThemeJSONActions.commitPaste(try Self.spec(Self.caseA), store: &store).get()
        let spec = try XCTUnwrap(store[id])
        s = try XCTUnwrap(ThemePicker.select(custom: spec, in: s))
        CustomThemeStore.save(store, d)
        s.save(d)
        XCTAssertEqual(d.string(forKey: ThemeSettings.themeKey), id)
        // Bàn phím: chỉ đọc theme đang chọn (bản chuẩn hoá).
        let kb = ThemeSettings.load(d)
        XCTAssertEqual(kb.custom?.id, id)
        XCTAssertEqual(ThemeColorCode.argb(kb.palette(systemDark: false, wallpaperActive: false).background ?? .black), 0xFFEE_EEEE)
        // Dữ liệu hỏng ⇒ Hệ thống, không crash.
        d.set("{hỏng", forKey: CustomThemeStore.activeKey)
        XCTAssertNil(ThemeSettings.load(d).custom)
        XCTAssertEqual(ThemeSettings.load(d).palette(systemDark: false, wallpaperActive: false),
                       ThemeSettings().palette(systemDark: false, wallpaperActive: false))
        d.set(##"{"v":1,"id":"khac","name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}}"##,
              forKey: CustomThemeStore.activeKey)
        XCTAssertNil(ThemeSettings.load(d).custom, "id không khớp ⇒ bỏ")
        s.save(d)
        // Sửa theme tự tạo: thay đặc tả, theme đang chọn cập nhật.
        let text = try XCTUnwrap(ThemeJSONActions.copyText(.custom(id), settings: s, store: store))
            .replacingOccurrences(of: "\"#EEEEEE\"", with: "\"#123456\"")
        XCTAssertTrue(ThemeJSONActions.save(text, to: .custom(id), settings: &s, store: &store).ok)
        XCTAssertEqual(store[id]?.light.bg, 0xFF12_3456)
        XCTAssertEqual(s.custom?.light.bg, 0xFF12_3456)
        // Hết Plus ⇒ vẽ Hệ thống, dữ liệu giữ; mua lại ⇒ có lại.
        lockPlus()
        XCTAssertNil(s.effectiveCustom)
        XCTAssertEqual(s.palette(systemDark: false, wallpaperActive: false), ThemeSettings().palette(systemDark: false, wallpaperActive: false))
        XCTAssertNil(ThemePicker.select(custom: spec, in: s))
        XCTAssertNotNil(s.custom)
        PlusGate.paywallEnabled = false
        XCTAssertNotNil(s.effectiveCustom)
        // Xoá ⇒ về Hệ thống.
        ThemeJSONActions.delete(id, settings: &s, store: &store)
        XCTAssertNil(store[id]); XCTAssertNil(s.custom); XCTAssertEqual(s.theme, .system)
        s.save(d)
        XCTAssertNil(d.object(forKey: CustomThemeStore.activeKey))
    }

    /// Tuỳ chỉnh (bản vá) bị bỏ qua khi hết Plus, giữ nguyên dữ liệu.
    func testOverridesIgnoredWithoutPlusButKept() throws {
        var s = ThemeSettings(theme: .oled)
        var st = KeyStyle(); st.light.key = 0xFF33_3333; st.dark.key = 0xFF33_3333
        s.keyStyle = st
        let unlocked = s.palette(systemDark: true, wallpaperActive: false)
        XCTAssertEqual(ThemeColorCode.argb(unlocked.keyFill), 0xFF33_3333)
        lockPlus()
        XCTAssertEqual(s.palette(systemDark: true, wallpaperActive: false), ThemeSettings(theme: .oled).palette(systemDark: true, wallpaperActive: false))
        XCTAssertEqual(s.keyStyle, st)
    }

    /// Cùng bản vá ⇒ cùng chuỗi chuẩn hai nền tảng (Android ThemeSpecTests.patchCanonicalMatchesIOS).
    func testPatchCanonicalMatchesAndroid() {
        var st = KeyStyle(accentColor: 0xFF9500)
        st.dark.bg = 0xFF00_0000
        st.light.deco = ThemeDeco(motif: .hearts, color: 0x80FF_0000, density: 150)
        XCTAssertEqual(KeyStyleStore.serialize(["mint": st]),
                       ##"{"mint":{"accent":"#FF9500","dark":{"bg":"#000000"},"light":{"deco":{"color":"#80FF0000","density":150,"motif":"hearts"}}}}"##)
        XCTAssertEqual(KeyStyleStore.parse(KeyStyleStore.serialize(["mint": st]))["mint"], st)
        // Phông điểm ảnh + dáng phím điểm ảnh trong bản vá (Android y hệt).
        var px = KeyStyle(font: .pixel)
        px.keyShape = "pixel"
        XCTAssertEqual(KeyStyleStore.serialize(["mint": px]), #"{"mint":{"font":"pixel","keyShape":"pixel"}}"#)
        XCTAssertEqual(KeyStyleStore.parse(KeyStyleStore.serialize(["mint": px]))["mint"], px)
        XCTAssertTrue(KeyStyleStore.parse(#"{"mint":{"keyShape":"round"}}"#).isEmpty, "giá trị lạ ⇒ bỏ cả mục")
    }

    // MARK: sao lưu

    func testBackupRoundTripCustomThemesAndPatches() throws {
        var store: [String: ThemeSpec] = [:]
        _ = try ThemeJSONActions.commitPaste(try Self.spec(Self.caseA), store: &store).get()
        CustomThemeStore.save(store, d)
        var s = ThemeSettings(theme: .mint)
        var st = KeyStyle(accentColor: 0xFF9500); st.dark.bg = 0xFF00_0000; st.light.deco = ThemeDeco(motif: .hearts, color: 0x80FF_0000, density: 150)
        s.keyStyle = st
        s.save(d)
        let snap = BackupStore(defaults: d, containerURL: nil).settings()
        XCTAssertEqual(snap[CustomThemeStore.key], .string(CustomThemeStore.serialize(store)))
        let back = try BackupCodec.decode(BackupCodec.encode(BackupPayload(createdAt: nil, platform: "ios", settings: snap,
                                                                           shortcuts: nil, templates: nil, learnedWords: nil)))
        let o = "themejson-o-\(UUID().uuidString)"
        let other = try XCTUnwrap(UserDefaults(suiteName: o))
        defer { other.removePersistentDomain(forName: o) }
        BackupStore(defaults: other, containerURL: nil).setSettings(try XCTUnwrap(back.settings))
        XCTAssertEqual(CustomThemeStore.load(other), store)
        XCTAssertEqual(ThemeSettings.load(other).keyStyles["mint"], st)
        XCTAssertEqual(SettingValue.fromSyncString(CustomThemeStore.serialize(store), key: CustomThemeStore.key),
                       .string(CustomThemeStore.serialize(store)))
        XCTAssertNil(SettingValue.fromSyncString("[1]", key: CustomThemeStore.key))
    }
}
