// ICloudSync — đồng bộ settings + gõ tắt + mẫu câu giữa các máy Apple của cùng tài
// khoản iCloud qua NSUbiquitousKeyValueStore (≤ 1 MB, không cần server/container).
// KHÔNG đồng bộ từ đã học (riêng tư + dung lượng). Mặc định TẮT.
//
// Chỉ app đồng bộ (bàn phím không có entitlement iCloud): bàn phím ghi App Group,
// app gộp lên iCloud mỗi lần mở/ra nền và khi iCloud báo có thay đổi từ máy khác.
//
// Entitlement com.apple.developer.ubiquity-kvstore-identifier trong App.entitlements
// — App ID com.viettelex.ios phải bật capability iCloud (Key-value storage) trên
// developer portal thì bản ký thiết bị/App Store mới chạy (simulator không cần).
import Foundation
import Combine

/// Bọc NSUbiquitousKeyValueStore cho SyncEngine.
final class KVSCloud: SyncCloud {
    let kvs: NSUbiquitousKeyValueStore
    init(_ kvs: NSUbiquitousKeyValueStore = .default) { self.kvs = kvs }
    func data(forKey key: String) -> Data? { kvs.data(forKey: key) }
    func set(_ data: Data, forKey key: String) { kvs.set(data, forKey: key) }
}

final class ICloudSync: ObservableObject {
    static let shared = ICloudSync()
    static let enabledKey = "icloudSyncEnabled"
    static let lastSyncKey = "icloudLastSync"
    /// Tính năng Plus (PlusConfig: paywall tắt ⇒ mở cho mọi người).
    static var isUnlocked: () -> Bool = { PlusGate.isUnlocked(.iCloudSync) }

    let store: BackupStore
    private let cloud = KVSCloud()
    private var observer: NSObjectProtocol?
    @Published private(set) var lastSync: Date?

    init(store: BackupStore = .appGroup) {
        self.store = store
        let t = store.defaults.double(forKey: Self.lastSyncKey)
        lastSync = t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    var isEnabled: Bool { store.defaults.bool(forKey: Self.enabledKey) && Self.isUnlocked() }
    /// false = máy chưa đăng nhập iCloud (KVS khi đó chỉ lưu cục bộ, không lỗi).
    var iCloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    func setEnabled(_ on: Bool) {
        store.defaults.set(on, forKey: Self.enabledKey)
        if on { start() } else { stop() }
    }

    /// Gọi khi app active (và lúc bật công tắc). Không bật ⇒ không làm gì.
    func start() {
        guard isEnabled else { return }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default, queue: .main) { [weak self] _ in
                self?.syncNow()
            }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
        syncNow()
    }

    func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
    }

    func syncNow() {
        guard isEnabled else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let r = SyncEngine.run(local: store, cloud: cloud, now: now)
        if !r.pushed.isEmpty { NSUbiquitousKeyValueStore.default.synchronize() }
        let d = Date()
        store.defaults.set(d.timeIntervalSince1970, forKey: Self.lastSyncKey)
        lastSync = d
    }
}

extension BackupStore {
    static let appGroupID = AppFlavor.appGroup
    static let appGroup = BackupStore(
        defaults: UserDefaults(suiteName: appGroupID) ?? .standard,
        containerURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
        defaultTemplates: { MauCauSections.bundledDefaults.map { BackupTemplate(label: $0.label, text: $0.text) } })
}
