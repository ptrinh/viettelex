// Nạp lười VTIntelligence.framework (nhúng ở app chủ, KHÔNG link vào bàn phím) rồi gọi
// `vt_ai_*` qua dlsym — cùng mẫu TranslateLoader (Keyboard/Translate.swift). Chỉ chạy khi
// công tắc "Sửa lỗi bằng Apple Intelligence" BẬT và có vùng chọn; tắt ⇒ không bao giờ dlopen.
// Không tìm thấy / không nạp được ⇒ coi như model không dùng được (không crash).
import Foundation

enum AIAssistLoader {
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void
    typealias StatusFn = @convention(c) () -> Int32
    typealias PrewarmFn = @convention(c) (UnsafePointer<CChar>) -> Void
    typealias RunFn = @convention(c) (Int32, UnsafePointer<CChar>, UnsafePointer<CChar>, Int32,
                                      UnsafeMutableRawPointer?, Callback) -> Void

    struct Entry {
        let status: StatusFn
        let prewarm: PrewarmFn
        let run: RunFn
    }

    static let frameworkName = "VTIntelligence"

    /// Bàn phím = VietTelex.app/PlugIns/X.appex ⇒ ../../Frameworks; app/test = Frameworks của bundle.
    static func candidatePaths(bundle: Bundle = .main) -> [String] {
        let rel = "\(frameworkName).framework/\(frameworkName)"
        var out: [String] = []
        if bundle.bundleURL.pathExtension == "appex" {
            out.append(bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Frameworks").appendingPathComponent(rel).path)
        }
        if let p = bundle.privateFrameworksURL { out.append(p.appendingPathComponent(rel).path) }
        return out
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: Entry??

    static var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return cached != nil }

    /// dlopen một lần (lần đầu cần) — nil nếu không có framework.
    static func entry(paths: [String] = candidatePaths()) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        var found: Entry?
        for p in paths where FileManager.default.fileExists(atPath: p) {
            guard let h = dlopen(p, RTLD_NOW | RTLD_LOCAL),
                  let s = dlsym(h, "vt_ai_status"), let w = dlsym(h, "vt_ai_prewarm"),
                  let r = dlsym(h, "vt_ai_run") else {
                TouchLog.write("ai: dlopen \(p) lỗi \(dlerror().map { String(cString: $0) } ?? "?")")
                continue
            }
            found = Entry(status: unsafeBitCast(s, to: StatusFn.self),
                          prewarm: unsafeBitCast(w, to: PrewarmFn.self),
                          run: unsafeBitCast(r, to: RunFn.self))
            break
        }
        cached = .some(found)
        return found
    }

    #if DEBUG
    static func debugReset() { lock.lock(); cached = nil; lock.unlock() }
    #endif

    static func status() -> AIModelState {
        guard let e = entry() else { return .unsupportedOS }
        return AIModelState(rawValue: e.status()) ?? .notReady
    }

    static func prewarm(instructions: String) {
        guard let e = entry() else { return }
        instructions.withCString { e.prewarm($0) }
    }

    private final class Box {
        let done: (Int32, String?) -> Void
        init(_ done: @escaping (Int32, String?) -> Void) { self.done = done }
    }

    /// `kind`: 0 sửa lỗi, 1 từ thay thế (IntelligenceKind). Hạn giờ ở cả hai phía: framework
    /// huỷ lượt sinh; ở đây AITimeout chặn thêm (+1 s) phòng framework treo.
    static func run(kind: Int32, instructions: String, prompt: String,
                    timeout: TimeInterval = AIText.timeout) async -> Result<String, AIFailure> {
        guard let e = entry() else { return .failure(.unavailable) }
        let r = await AITimeout.race(seconds: timeout + 1) { () async -> (Int32, String?) in
            await withCheckedContinuation { cont in
                let box = Box { code, out in cont.resume(returning: (code, out)) }
                let ctx = Unmanaged.passRetained(box).toOpaque()
                instructions.withCString { i in prompt.withCString { p in
                    e.run(kind, i, p, Int32(timeout * 1000), ctx) { ctx, code, out in
                        guard let ctx else { return }
                        let b = Unmanaged<Box>.fromOpaque(ctx).takeRetainedValue()
                        b.done(code, out.map { String(cString: $0) })
                    }
                } }
            }
        }
        guard let (code, text) = r else { return .failure(.timeout) }
        if let f = AIFailure(engineCode: code) {
            if f == .failed { TouchLog.write("ai failed: \(text ?? "?")") }
            return .failure(f)
        }
        return .success(text ?? "")
    }
}

/// RAM thực của extension (phys_footprint — con số jetsam dùng), MB. Ghi vào Debug log trước/sau
/// mỗi yêu cầu để theo dõi giới hạn bộ nhớ của bàn phím.
enum AIMemory {
    static func footprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<Int32>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }

    static func describe(_ mb: Double?) -> String { mb.map { String(format: "%.1fMB", $0) } ?? "?" }
}
