// BackupStore — nối BackupFormat/SyncMerge vào dữ liệu thật của iOS: UserDefaults
// App Group "group.com.viettelex" (settings, userTemplates, shortcuts) + file
// store từ đã học trong container (userlm.bin, qua UserLangModel.readPlain/writePlain). Tests truyền UserDefaults/URL riêng.
import Foundation

final class BackupStore: SyncLocal {
    let defaults: UserDefaults
    let containerURL: URL?
    let defaultTemplates: () -> [BackupTemplate]

    /// Key cục bộ iOS khác tên chuẩn trong file.
    static let localKey: [String: String] = ["reEditWords": "reEditWord"]
    /// Setting iOS không có (bỏ qua khi nhập/đồng bộ, không xuất).
    static let unsupported: Set<String> = ["hardwareTelex"]
    static let templatesKey = "userTemplates"
    /// Gõ tắt: dict [khoá: nội dung] ở App Group — đúng chỗ bàn phím đọc (Keyboard/Shortcuts.swift).
    static let shortcutsKey = ShortcutFile.storeKey
    static let learnedFile = "userlm.plist"
    static func ledgerKey(_ s: SyncSection) -> String { "syncLedger.\(s.rawValue)" }

    init(defaults: UserDefaults, containerURL: URL?, defaultTemplates: @escaping () -> [BackupTemplate] = { [] }) {
        self.defaults = defaults
        self.containerURL = containerURL
        self.defaultTemplates = defaultTemplates
    }

    static var specs: [BackupSettings.Spec] { BackupSettings.all.filter { !unsupported.contains($0.key) } }

    // MARK: settings

    func settings() -> [String: SettingValue] {
        var out: [String: SettingValue] = [:]
        for spec in Self.specs {
            let raw = defaults.object(forKey: Self.localKey[spec.key] ?? spec.key)
            switch spec.kind {
            case .bool(let def): out[spec.key] = .bool((raw as? Bool) ?? def)
            case .int(let def, let r):
                let v = (raw as? Int) ?? def
                out[spec.key] = .int(min(max(v, r.lowerBound), r.upperBound))
            case .string(let def, let allowed):
                let v = raw as? String
                out[spec.key] = .string(v.map { allowed.contains($0) } == true ? v! : def)
            case .buddyName:
                out[spec.key] = .string(BuddyName.clean((raw as? String) ?? ""))
            case .styleMap:
                out[spec.key] = .string((raw as? String).flatMap(KeyStyleStore.normalize) ?? KeyStyleStore.empty)
            case .themeMap:
                out[spec.key] = .string((raw as? String).flatMap(CustomThemeStore.normalize) ?? "{}")
            }
        }
        return out
    }

    func setSettings(_ input: [String: SettingValue]) {
        // File / iCloud từ bản cũ: bộ "Tuỳ chỉnh nâng cao" chung ⇒ vào theme đang chọn trên máy này.
        // Bản lưu thô (chưa chuyển đổi trong bộ nhớ): bộ cũ trong file thắng bộ cũ còn trên máy.
        let s = BackupSettings.migrateLegacyStyle(input, theme: defaults.string(forKey: ThemeSettings.themeKey),
                                                  styles: KeyStyleStore.parse(defaults.string(forKey: KeyStyleStore.key)))
        for (k, v) in s where BackupSettings.byKey[k] != nil && !Self.unsupported.contains(k) {
            let lk = Self.localKey[k] ?? k
            switch v {
            case .bool(let b): defaults.set(b, forKey: lk)
            case .int(let i): defaults.set(i, forKey: lk)
            case .string(let t): defaults.set(t, forKey: lk)
            }
        }
    }

    // MARK: gõ tắt / mẫu câu

    func shortcuts() -> [String: String] {
        (defaults.dictionary(forKey: Self.shortcutsKey) as? [String: String]) ?? [:]
    }
    func setShortcuts(_ d: [String: String]) { defaults.set(d, forKey: Self.shortcutsKey) }
    /// Mốc thêm/sửa từng gõ tắt (ShortcutOrder — danh sách "mới nhất trước").
    func shortcutTimes() -> [String: Int64] { ShortcutOrder.times(from: defaults) }
    func setShortcutTimes(_ t: [String: Int64]) { ShortcutOrder.setTimes(t, in: defaults) }

    func templates() -> [BackupTemplate] {
        guard let raw = defaults.array(forKey: Self.templatesKey) as? [[String: String]] else {
            return defaultTemplates()
        }
        return raw.compactMap { e in
            guard let t = e["text"], !t.isEmpty else { return nil }
            return BackupTemplate(label: e["label"] ?? "", text: t)
        }
    }
    func setTemplates(_ items: [BackupTemplate]) {
        defaults.set(items.map { ["label": $0.label, "text": $0.text] }, forKey: Self.templatesKey)
    }

    // MARK: từ đã học (store của UserLangModel — nhị phân VTL2; plist cũ đọc được tới khi chuyển)

    /// Đường dẫn gốc (tên cũ) — UserLangModel suy ra file thật (userlm.bin).
    private var learnedURL: URL? { containerURL?.appendingPathComponent(Self.learnedFile) }

    func learnedWords() -> LearnedWords? {
        guard let url = learnedURL, let p = UserLangModel.readPlain(at: url) else { return nil }
        return LearnedWords(uni: p.uni, bi: p.bi, tri: p.tri, manual: p.manual)
    }

    /// Gộp vào file hiện có (count lớn hơn). Bàn phím nạp lại file lần hiện kế tiếp.
    func mergeLearnedWords(_ lw: LearnedWords) {
        guard let url = learnedURL, !lw.isEmpty else { return }
        let lastDecay = UserLangModel.readPlain(at: url)?.lastDecay ?? Date()
        let merged = (learnedWords() ?? LearnedWords()).merged(with: lw)
        // Từ thêm tay luôn có mặt trong uni (như keepManual của UserLangModel).
        var uni = merged.uni
        for m in merged.manual where uni[m.lowercased()] == nil { uni[m.lowercased()] = 1 }
        let p = UserLangModel.Plain(uni: uni, bi: merged.bi, tri: merged.tri,
                                    manual: merged.manual, lastDecay: lastDecay)
        if UserLangModel.writePlain(p, to: url) {
            // Bàn phím thấy mốc đổi ⇒ bỏ bảng trong RAM, nạp file vừa gộp (không ghi đè nó).
            defaults.set(Date().timeIntervalSince1970, forKey: "userlmResetAt")
        }
    }

    // MARK: file sao lưu

    func snapshot(includeLearned: Bool, now: Date = Date()) -> BackupPayload {
        let sc = shortcuts()
        return BackupPayload(createdAt: now, platform: "ios", settings: settings(), shortcuts: sc,
                             templates: templates(), learnedWords: includeLearned ? (learnedWords() ?? LearnedWords()) : nil,
                             shortcutsAdded: shortcutTimes().filter { sc[$0.key] != nil })
    }

    /// Nhập theo chính sách BackupMerge; trả câu tóm tắt cho người dùng.
    @discardableResult
    func apply(_ p: BackupPayload) -> String {
        if let s = p.settings { setSettings(s) }
        var changed = 0
        if let sc = p.shortcuts {
            let cur = shortcuts()
            changed = sc.filter { cur[$0.key] != $0.value }.count
            let merged = BackupMerge.shortcuts(current: cur, imported: sc)
            setShortcuts(merged)
            setShortcutTimes(ShortcutOrder.imported(shortcutTimes(), fileTimes: p.shortcutsAdded, old: cur,
                                                    file: sc, table: merged, now: ShortcutOrder.nowMs()))
        }
        var added = 0
        if let t = p.templates {
            let cur = templates()
            let merged = BackupMerge.templates(current: cur, imported: t)
            added = merged.count - cur.count
            setTemplates(merged)
        }
        if let lw = p.learnedWords { mergeLearnedWords(lw) }
        return BackupMerge.summary(p, templatesAdded: added, shortcutsChanged: changed)
    }

    // MARK: SyncLocal (iCloud) — không đồng bộ từ đã học

    func current(_ s: SyncSection) -> [String: String] {
        switch s {
        case .settings: return SyncMerge.settingsToDomain(settings())
        case .shortcuts: return shortcuts()
        case .templates: return SyncMerge.templatesToDomain(templates())
        }
    }

    func apply(_ s: SyncSection, _ values: [String: String]) {
        switch s {
        case .settings: setSettings(SyncMerge.settingsFromDomain(values))
        case .shortcuts:
            // mục kéo về (mới / đổi nội dung) lên đầu danh sách; mục bị xoá bỏ mốc
            setShortcutTimes(ShortcutOrder.updated(shortcutTimes(), from: shortcuts(), to: values,
                                                   now: ShortcutOrder.nowMs()))
            setShortcuts(values)
        case .templates: setTemplates(SyncMerge.templatesFromDomain(values))
        }
    }

    func isUntouched(_ s: SyncSection) -> Bool {
        s == .templates && defaults.object(forKey: Self.templatesKey) == nil
    }

    func ledger(_ s: SyncSection) -> SyncDomain? { SyncMerge.decode(defaults.data(forKey: Self.ledgerKey(s))) }
    func setLedger(_ s: SyncSection, _ d: SyncDomain) { defaults.set(SyncMerge.encode(d), forKey: Self.ledgerKey(s)) }
    // Tắt đồng bộ KHÔNG xoá sổ: bật lại thì thay đổi làm trong lúc tắt được đóng dấu
    // "now" và thắng bản cũ trên iCloud (không mất sửa đổi cục bộ).
}
