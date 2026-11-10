// LearnStore.swift — "Học từ bạn gõ" cho Linux ([general] learn_words, mặc định bật; chỉ có tác
// dụng khi word_prediction bật). Mô hình = LearnedModel.swift (symlink App/Sources — đúng mã
// macOS, bảng/codec VTL2 của iOS qua UserLMTables.swift).
//
// VÌ SAO Ở PROCESS CON (`--serve`), KHÔNG Ở PROCESS IME: xếp hạng gợi ý đã chạy ở đây (dữ liệu
// học phải ở cạnh nó); process IME (fcitx5 / ibus-daemon con) giữ nguyên "không IO file, không
// dữ liệu lớn" — process con chết / treo thì bộ gõ vẫn gõ bình thường (HintService giết + mở lại).
// Session (linux/common) chỉ gửi lượt học ĐÃ QUA CỔNG ("learn" — không bao giờ bị lượt yêu cầu
// mới đè, HintRequest::oneway).
//
// LƯU: hẹn `saveDelay` giây sau lượt học cuối (vòng poll của serve), ghi nguyên tử (file tạm +
// rename); thoát (rảnh lâu / bộ gõ đóng ống) ⇒ ghi nốt. File:
// $XDG_DATA_HOME/viettelex/learned-words.bin (mặc định ~/.local/share/viettelex/…); không mạng.
// "Xoá từ đã học" của app Cài đặt ghi đè file bằng kho RỖNG hợp lệ ⇒ mọi process con đang chạy
// thấy file đổi (cỡ / mtime khác lần mình đọc/ghi) ⇒ nạp lại (rỗng), không ghi đè lại dữ liệu cũ.
// Hai process con (fcitx5 + ibus cùng chạy — hiếm) cũng thấy nhau qua cách đó (mất tối đa vài
// giây học chưa lưu của một bên).
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// POSIX write(2) — ngoài class để không đụng tên với LearnStore.write(_:).
private func posixWrite(_ fd: Int32, _ p: UnsafeRawPointer, _ n: Int) -> Int { write(fd, p, n) }

final class LearnStore {
    static let shared = LearnStore()
    /// Gộp lượt lưu (giây sau lượt học cuối).
    static let saveDelay = 3.0
    /// Kiểm file bị sửa từ ngoài tối đa một lần mỗi chừng này giây.
    static let statInterval = 1.0

    let url: URL
    private var model: LearnedModel?
    private var lastChange = 0.0
    /// (cỡ, mtime) của file sau lần mình đọc / ghi; nil = file không có.
    private var seen: [Double]?
    private var lastStat = 0.0

    init(url: URL = LearnStore.defaultURL()) { self.url = url }

    static func defaultURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let f = env["VIETTELEX_LEARN_FILE"], !f.isEmpty { return URL(fileURLWithPath: f) }
        let base = env["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? ((env["HOME"] ?? "/tmp") + "/.local/share")
        return URL(fileURLWithPath: base).appendingPathComponent("viettelex")
            .appendingPathComponent(LearnedModel.fileName)
    }

    static func now() -> Double { Date().timeIntervalSince1970 }

    /// (cỡ, mtime ns) của file — POSIX stat (FoundationEssentials không có NSNumber cho thuộc tính).
    private func fileStat() -> [Double]? {
        #if os(Linux)
        var st = Glibc.stat()
        #else
        var st = Darwin.stat()
        #endif
        guard lstat(url.path, &st) == 0 else { return nil }
        #if os(Linux)
        let ns = Double(st.st_mtim.tv_sec) * 1e9 + Double(st.st_mtim.tv_nsec)
        #else
        let ns = Double(st.st_mtimespec.tv_sec) * 1e9 + Double(st.st_mtimespec.tv_nsec)
        #endif
        return [Double(st.st_size), ns, Double(st.st_ino)]
    }

    var isLoaded: Bool { model != nil }

    /// Mô hình (nạp lười; file bị đổi từ ngoài ⇒ nạp lại).
    func current() -> LearnedModel {
        let t = Self.now()
        if let m = model {
            guard t - lastStat >= Self.statInterval else { return m }
            lastStat = t
            if fileStat() == seen { return m }
        }
        let m = LearnedModel.load(from: url, isKnownWord: { VNSuggest.contains($0) }).model
        model = m
        seen = fileStat()
        lastStat = t
        if m.changes > 0 { lastChange = t }   // decay vừa áp: lưu ở lượt kế
        return m
    }

    /// `word` = đúng hoa/thường đã gõ (frontend gửi dạng gốc từ 10/2026; bản cũ gửi chữ thường ⇒
    /// không có bằng chứng hoa/thường). Bằng chứng = giữa câu (có prev1) và không do chuỗi tên riêng.
    func record(word: String, prev1: String?, prev2: String?, weight: Int) {
        current().record(word: word, after: prev1, prev2: prev2, weight: weight,
                         caseEvidence: DisplayCase.casingEvidence(word, prev: prev1))
        lastChange = Self.now()
    }

    /// Xoá (yêu cầu `learnclear`): RAM rỗng + file rỗng hợp lệ (process con khác thấy file đổi).
    func clear() {
        let m = LearnedModel(isKnownWord: { VNSuggest.contains($0) })
        model = m
        write(m)
    }

    /// Mili-giây tới lượt lưu đang hẹn (nil = không có gì chờ).
    func msUntilSave(now t: Double = LearnStore.now()) -> Int32? {
        guard let m = model, m.changes > 0 else { return nil }
        let left = lastChange + Self.saveDelay - t
        return left <= 0 ? 0 : Int32(left * 1000) + 1
    }

    /// Ghi nếu tới hẹn (`force` = thoát: ghi mọi thay đổi chờ).
    func saveIfDue(force: Bool = false, now t: Double = LearnStore.now()) {
        guard let m = model, m.changes > 0 else { return }
        if !force, lastChange + Self.saveDelay > t { return }
        if fileStat() != seen {
            // File bị đổi từ ngoài (Xoá từ đã học / process con khác): bỏ RAM, nạp lại lần sau.
            model = nil
            return
        }
        write(m)
    }

    /// Công tắc tắt (predict với learn = 0): ghi nốt rồi bỏ khỏi RAM.
    func unload() {
        saveIfDue(force: true)
        model = nil
    }

    private func write(_ m: LearnedModel) {
        let data = m.snapshot().encoded()
        m.markSaved()
        _ = Self.writePrivate(data, to: url)
        seen = fileStat()
        lastStat = Self.now()
    }

    /// Ghi nguyên tử, CHỈ chủ đọc được (0600; thư mục mới 0700): file là từ / cặp từ người dùng
    /// hay gõ. Data.write(.atomic) để quyền theo umask (thường 0644, người khác trên máy đọc
    /// được). File tạm mở O_EXCL 0600 ngay từ đầu — không có lúc nào lộ quyền rộng hơn.
    @discardableResult
    static func writePrivate(_ data: Data, to url: URL) -> Bool {
        let dir = url.deletingLastPathComponent().path
        if access(dir, F_OK) != 0 {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        let tmp = url.path + ".tmp\(getpid())"
        unlink(tmp)
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        var ok = data.withUnsafeBytes { raw -> Bool in
            var off = 0
            while off < raw.count {
                let w = posixWrite(fd, raw.baseAddress! + off, raw.count - off)
                if w < 0 { if errno == EINTR { continue }; return false }
                off += w
            }
            return true
        }
        if ok && fsync(fd) != 0 { ok = false }
        if close(fd) != 0 { ok = false }
        if ok && rename(tmp, url.path) == 0 { return true }
        unlink(tmp)
        return false
    }
}
