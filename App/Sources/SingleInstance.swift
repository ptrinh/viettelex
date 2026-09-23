// SingleInstance.swift — chỉ bản ĐÃ CÀI được làm IME; bản thừa tự NHƯỜNG.
//
// IMK khởi động input method theo BUNDLE ID qua LaunchServices, không theo đường
// dẫn. Mỗi vòng xcodebuild đăng ký thêm một VietTelex.app cùng id (xoá thư mục
// không huỷ đăng ký), nên macOS có thể chạy một bản cũ trong DerivedData song song
// với bản đã cài. Process nào đăng ký `<id>_Connection` trước thì nhận phím IMK,
// nhưng tap của CẢ HAI đều chạy → hai kênh cùng sửa một từ (PR #92, 23/09/2026:
// chữ sai "ti đã đi", Enter xuống dòng thay vì gửi).
//
// Vì sao NHƯỜNG chứ không KILL: process sinh sau chưa chắc là bản đúng; kill bản
// IMK đang nối làm mọi app mất kết nối; và nếu LaunchServices vẫn trỏ bản thừa thì
// IMK khởi động lại nó → hai bên kill nhau liên tục. Ở đây chỉ bản thừa tự thoát:
//   1. lúc khởi động, bản NGOÀI "Input Methods" thấy instance khác cùng id → thoát
//      trước khi đăng ký IMKServer/tap;
//   2. bản đã cài khi khởi động phát distributed notification → bản thừa đang chạy
//      nghe thấy và tự thoát.
// Debug có bundle id riêng (…telex.debug) nên không bao giờ đụng bản Release.

import Cocoa

enum SingleInstance {
    /// Đường dẫn bundle nằm trong một thư mục "Input Methods" chuẩn (user hoặc máy).
    static func isInstalledLocation(_ bundlePath: String, home: String = NSHomeDirectory()) -> Bool {
        let p = (bundlePath as NSString).standardizingPath
        return p.hasPrefix((home as NSString).appendingPathComponent("Library/Input Methods") + "/")
            || p.hasPrefix("/Library/Input Methods/")
    }

    /// Bản này có phải nhường không. Pure — pinned by SingleInstanceTests.
    /// - Bản thừa (ngoài "Input Methods") nhường cho BẤT KỲ instance nào khác.
    /// - Bản đã cài chỉ nhường cho instance CÙNG đường dẫn chạy trước nó (bản cũ
    ///   đang giữ IMK connection — đo 24/09: exec tay trong lúc IMK vừa relaunch ra
    ///   hai process cùng bundle, cả hai đều chạy tap). Không nhường cho bản đã cài
    ///   ở thư mục KHÁC (user + máy): không đoán bản nào đúng.
    static func shouldYieldAtLaunch(selfPath: String, otherInstancePaths: [String],
                                    home: String = NSHomeDirectory()) -> Bool {
        if !isInstalledLocation(selfPath, home: home) { return !otherInstancePaths.isEmpty }
        let me = (selfPath as NSString).standardizingPath
        return otherInstancePaths.contains { ($0 as NSString).standardizingPath == me }
    }

    /// Bản thừa có phải thoát khi nhận thông báo "bản đã cài vừa khởi động" không.
    static func shouldYieldOnInstalledAnnouncement(selfPath: String, senderPID: pid_t,
                                                   selfPID: pid_t,
                                                   home: String = NSHomeDirectory()) -> Bool {
        senderPID != selfPID && !isInstalledLocation(selfPath, home: home)
    }

    static func notificationName(bundleID: String) -> Notification.Name {
        Notification.Name("\(bundleID).installedInstanceStarted")
    }

    private static var observer: NSObjectProtocol?

    /// Gọi ở đầu main, TRƯỚC IMKServer. Không trả về nếu phải nhường.
    static func enforce(bundleID: String) {
        let me = ProcessInfo.processInfo.processIdentifier
        let selfPath = Bundle.main.bundlePath
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me }
            .compactMap { $0.bundleURL?.path }
        if shouldYieldAtLaunch(selfPath: selfPath, otherInstancePaths: others) {
            NSLog("VietTelex: bản thừa \(selfPath) nhường cho \(others) — thoát")
            exit(0)
        }
        let name = notificationName(bundleID: bundleID)
        if isInstalledLocation(selfPath) {
            DistributedNotificationCenter.default().postNotificationName(
                name, object: String(me), userInfo: nil, deliverImmediately: true)
        } else {
            observer = DistributedNotificationCenter.default().addObserver(
                forName: name, object: nil, queue: .main) { note in
                let sender = pid_t((note.object as? String).flatMap(Int32.init) ?? -1)
                if shouldYieldOnInstalledAnnouncement(selfPath: selfPath, senderPID: sender, selfPID: me) {
                    NSLog("VietTelex: bản đã cài (pid \(sender)) vừa khởi động — bản thừa \(selfPath) thoát")
                    exit(0)
                }
            }
        }
    }
}
