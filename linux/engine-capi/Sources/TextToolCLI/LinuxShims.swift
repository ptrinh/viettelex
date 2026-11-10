// LinuxShims.swift — phần riêng của viettelex-text-tool mà các file dùng chung (symlink
// iOS/Keyboard) cần: nơi đặt dữ liệu (thay Bundle, xem `#if VIETTELEX_CLI` trong
// VNLexicon2/SyllableLM/SwipeEnglish) và `L()` (nhãn TextTool — CLI không hiển thị nhãn).
//
// Trên Linux `import Foundation` = FoundationEssentials (-module-alias, xem Package.swift):
// không Bundle/NSString/folding; Foundation đầy đủ kéo CoreFoundation + ICU (~45 MB) vào
// file chạy tĩnh. Phần thiếu mà mã dùng chung cần nằm cuối file này.
import Foundation
#if os(Linux)
@_spi(_Unicode) import Swift   // String._nfd (chuẩn hoá NFD của stdlib)
import Glibc
#endif

enum VTDataFile {
    /// Thư mục dữ liệu theo thứ tự ưu tiên; file đầu tiên tồn tại thắng.
    static let dirs: [String] = {
        var d: [String] = []
        if let env = ProcessInfo.processInfo.environment["VIETTELEX_DATA_DIR"], !env.isEmpty { d.append(env) }
        // /usr/lib/<triplet>/viettelex/viettelex-text-tool → /usr/share/viettelex
        if let exe = executablePath() {
            var u = URL(fileURLWithPath: exe).deletingLastPathComponent()
            for _ in 0..<3 {
                u = u.deletingLastPathComponent()
                d.append(u.appendingPathComponent("share/viettelex").path)
            }
        }
        d.append("/usr/share/viettelex")
        d.append("/usr/local/share/viettelex")
        return d
    }()

    static func url(_ name: String) -> URL? {
        for dir in dirs {
            let p = dir.hasSuffix("/") ? dir + name : dir + "/" + name
            if FileManager.default.isReadableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    /// Đường dẫn thật (đã giải symlink) của file chạy.
    private static func executablePath() -> String? {
        #if os(Linux)
        guard let p = realpath("/proc/self/exe", nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
        #else
        return Bundle.main.executableURL?.resolvingSymlinksInPath().path
        #endif
    }
}

/// = L10n.t với ngôn ngữ mặc định (TextTool.label — không dùng trong CLI).
func L(_ vi: String) -> String { vi }

#if os(Linux)
/// Foundation đầy đủ re-export Glibc; FoundationEssentials thì không (AddTones dùng `log`).
func log(_ x: Double) -> Double { Glibc.log(x) }

// Ba API NSString mà các file dùng chung cần, FoundationEssentials không có. Chuẩn hoá
// Unicode lấy từ stdlib Swift (cùng dữ liệu Unicode mà String dùng để so sánh);
// replacingOccurrences so khớp theo unicode scalar như NSString (.literal).
// Fixture chung (ctest text_tool_fixtures) canh hành vi.
extension StringProtocol {
    var precomposedStringWithCanonicalMapping: String {
        String(decoding: String(self)._nfcCodeUnits, as: UTF8.self)
    }

    var decomposedStringWithCanonicalMapping: String {
        var v = String.UnicodeScalarView()
        for u in String(self)._nfd { v.append(u) }
        return String(v)
    }

    func replacingOccurrences(of target: String, with replacement: String) -> String {
        String(String(self).unicodeScalars.replacing(target.unicodeScalars, with: replacement.unicodeScalars))
    }
}

// Gợi ý cạnh con trỏ (MathResults, NumberChips, AutoCorrect, AdjacentKeyFixer — symlink
// iOS/Keyboard) cần thêm vài API Foundation đầy đủ mà FoundationEssentials không có.
// self-test caret_suggest (fixture math-results / number-chips) canh hành vi.

/// Foundation đầy đủ re-export Glibc: MathResults dùng `pow` cho Double (không thì chỉ còn
/// pow(Decimal, Int) của FoundationEssentials).
func pow(_ x: Double, _ y: Double) -> Double { Glibc.pow(x, y) }

extension String {
    /// String(format:) kiểu printf (MathResults: "%.0f", "%.6f").
    init(format: String, _ args: CVarArg...) {
        let n = withVaList(args) { vsnprintf(nil, 0, format, $0) }
        guard n > 0 else { self = ""; return }
        var buf = [CChar](repeating: 0, count: Int(n) + 1)
        _ = withVaList(args) { vsnprintf(&buf, buf.count, format, $0) }
        self = String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Chỉ tập `.whitespaces` (khoảng trắng ngang — Unicode Zs + tab), đủ cho mã dùng chung.
struct CharacterSet {
    let contains: (Unicode.Scalar) -> Bool
    static let whitespaces = CharacterSet { $0 == "\t" || $0.properties.generalCategory == .spaceSeparator }
}

extension StringProtocol {
    func trimmingCharacters(in set: CharacterSet) -> String {
        let u = Array(unicodeScalars)
        var a = 0, b = u.count
        while a < b, set.contains(u[a]) { a += 1 }
        while b > a, set.contains(u[b - 1]) { b -= 1 }
        var v = String.UnicodeScalarView()
        v.append(contentsOf: u[a..<b])
        return String(v)
    }
}

/// AdjacentKeyFixer.Cache, SwipeEnglish (nạp lexicon / bảng phím vuốt).
final class NSLock {
    private var m = pthread_mutex_t()
    init() { pthread_mutex_init(&m, nil) }
    deinit { pthread_mutex_destroy(&m) }
    func lock() { pthread_mutex_lock(&m) }
    func unlock() { pthread_mutex_unlock(&m) }
    /// Không chặn: true = đã giữ khoá (phải unlock).
    func `try`() -> Bool { pthread_mutex_trylock(&m) == 0 }
}

/// SwipeEnglish.Lexicon đọc enlexicon.bin TẠI CHỖ qua `bytes` (con trỏ ổn định suốt đời
/// đối tượng) — FoundationEssentials không có NSData. File: mmap chỉ đọc (như
/// `.alwaysMapped` trên Apple: trang sạch, heap không chứa file); `init(data:)` (test,
/// bảng dựng tay): chép vào bộ nhớ riêng. Chỉ phần API SwipeEnglish dùng.
final class NSData {
    typealias ReadingOptions = Data.ReadingOptions
    struct ReadError: Error { let errno: Int32 }

    let bytes: UnsafeRawPointer
    let length: Int
    private let mapped: Bool

    init() {
        bytes = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
        length = 0
        mapped = false
    }

    init(data: Data) {
        let p = UnsafeMutableRawPointer.allocate(byteCount: max(data.count, 1), alignment: 1)
        data.withUnsafeBytes { if let b = $0.baseAddress { p.copyMemory(from: b, byteCount: $0.count) } }
        bytes = UnsafeRawPointer(p)
        length = data.count
        mapped = false
    }

    /// Luôn mmap (bỏ qua `options` — chỉ `.alwaysMapped` được dùng). File rỗng ⇒ NSData rỗng.
    init(contentsOf url: URL, options: ReadingOptions = []) throws {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw ReadError(errno: errno) }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw ReadError(errno: errno) }
        let n = Int(st.st_size)
        if n == 0 {
            bytes = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
            length = 0
            mapped = false
            return
        }
        guard let p = mmap(nil, n, PROT_READ, MAP_PRIVATE, fd, 0), p != MAP_FAILED else {
            throw ReadError(errno: errno)
        }
        bytes = UnsafeRawPointer(p)
        length = n
        mapped = true
    }

    deinit {
        if mapped { munmap(UnsafeMutableRawPointer(mutating: bytes), length) }
        else { UnsafeMutableRawPointer(mutating: bytes).deallocate() }
    }
}
#endif
