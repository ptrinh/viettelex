// Phần DUY NHẤT chạm Apple Intelligence (FoundationModels, iOS 26+) — "Sửa lỗi bằng Apple
// Intelligence" (Plus). Cùng mẫu với VTTranslate (14/10/2026): bàn phím KHÔNG link
// FoundationModels — link (kể cả weak) là dyld nạp nó + framework phụ thuộc lúc bàn phím khởi
// động, dù công tắc tắt. File này là framework nhỏ `VTIntelligence.framework` nhúng ở app chủ
// (VietTelex.app/Frameworks/); bàn phím `dlopen` nó lần đầu cần (công tắc BẬT + có vùng chọn —
// Keyboard/AIAssistLoader.swift) và gọi qua hàm C `vt_ai_*`. App chủ biên dịch thẳng file này
// (không có VT_AI_FRAMEWORK) để màn cài đặt hỏi trạng thái model.
//
// RIÊNG TƯ: chỉ SystemLanguageModel trên máy — không mạng, không server. Model chạy ở tiến
// trình hệ thống (không tính vào RAM của extension). Mỗi yêu cầu một session MỚI (không giữ
// lịch sử giữa các lần), lấy mẫu tham lam (greedy) cho kết quả ổn định, đầu ra có cấu trúc
// (@Generable). Prompt do bàn phím dựng (Keyboard/AIProofread.swift — hàm thuần, có test).
//
// Không phụ thuộc file nào khác: vào là chuỗi, ra là mã số + chuỗi.
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Mã kết quả — khớp `AIFailure.init?(engineCode:)` (Keyboard/AIProofread.swift).
enum IntelligenceCode {
    static let ok: Int32 = 0
    /// Model không dùng được (máy không hỗ trợ / chưa bật Apple Intelligence / chưa tải xong / OS cũ).
    static let unavailable: Int32 = 1
    static let guardrail: Int32 = 2
    static let tooLong: Int32 = 3
    static let unsupportedLanguage: Int32 = 4
    static let timeout: Int32 = 5
    static let failed: Int32 = 6
}

/// Trạng thái model — khớp `AIStatus` (Keyboard/AIProofread.swift).
enum IntelligenceStatus {
    static let available: Int32 = 0
    static let deviceNotEligible: Int32 = 1
    static let notEnabled: Int32 = 2
    static let notReady: Int32 = 3
    static let unsupportedOS: Int32 = 4
}

/// Loại yêu cầu.
enum IntelligenceKind {
    static let proofread: Int32 = 0
    static let alternatives: Int32 = 1
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "The proofread lines of the user's text")
struct VTProofreadOutput {
    @Guide(description: "One corrected line for each input line, same count and order, without the 'Line N:' label. Spelling, Vietnamese tone marks and grammar fixed; same meaning and languages.")
    var lines: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Replacement candidates for one selected word")
struct VTAlternativesOutput {
    @Guide(description: "Up to 3 alternatives that fit the sentence; each is one word or a very short phrase", .maximumCount(3))
    var alternatives: [String]
}
#endif

/// Trả kết quả đúng một lần (lượt sinh hoặc hạn giờ, cái nào tới trước).
private final class OneShot: @unchecked Sendable {
    typealias R = (code: Int32, text: String?)
    private let lock = NSLock()
    private var cont: CheckedContinuation<R, Never>?
    private var done: R?
    func attach(_ c: CheckedContinuation<R, Never>) {
        lock.lock()
        if let d = done { lock.unlock(); c.resume(returning: d); return }
        cont = c
        lock.unlock()
    }
    @discardableResult
    func resume(_ v: R) -> Bool {
        lock.lock()
        if done != nil { lock.unlock(); return false }
        done = v
        let c = cont; cont = nil
        lock.unlock()
        c?.resume(returning: v)
        return true
    }
}

enum IntelligenceEngine {
    /// Ngăn các mục danh sách trong chuỗi trả về (khớp `AIText.listSeparator`).
    static let listSeparator: Character = "\u{1E}"

    static func status() -> Int32 {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return IntelligenceStatus.unsupportedOS }
        switch SystemLanguageModel.default.availability {
        case .available: return IntelligenceStatus.available
        case .unavailable(.deviceNotEligible): return IntelligenceStatus.deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return IntelligenceStatus.notEnabled
        case .unavailable(.modelNotReady): return IntelligenceStatus.notReady
        case .unavailable: return IntelligenceStatus.notReady
        }
        #else
        return IntelligenceStatus.unsupportedOS
        #endif
    }

    /// Model có hiểu tiếng Việt không (app hiện ghi chú khi chưa).
    static func supportsVietnamese() -> Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return false }
        return SystemLanguageModel.default.supportedLanguages.contains {
            $0.languageCode?.identifier == "vi"
        }
        #else
        return false
        #endif
    }

    /// Nạp sẵn model (hệ thống giữ tài nguyên; session tạm bỏ ngay — mỗi yêu cầu vẫn session mới).
    static func prewarm(instructions: String) {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *), SystemLanguageModel.default.isAvailable else { return }
        LanguageModelSession(instructions: instructions).prewarm()
        #endif
    }

    /// Chạy một yêu cầu với hạn giờ (huỷ khi quá hạn). Trả (mã, chuỗi kết quả khi ok / tên lỗi khi failed).
    static func run(kind: Int32, instructions: String, prompt: String,
                    timeout: TimeInterval) async -> (code: Int32, text: String?) {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return (IntelligenceCode.unavailable, nil) }
        guard SystemLanguageModel.default.isAvailable else { return (IntelligenceCode.unavailable, nil) }
        // Đua với hạn giờ: quá hạn ⇒ huỷ lượt sinh, trả timeout NGAY (không chờ lượt sinh dừng).
        let box = OneShot()
        let work = Task { box.resume(await respond(kind: kind, instructions: instructions, prompt: prompt)) }
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, timeout) * 1_000_000_000))
            if !Task.isCancelled, box.resume((IntelligenceCode.timeout, nil)) { work.cancel() }
        }
        let r = await withCheckedContinuation { box.attach($0) }
        timer.cancel()
        return r
        #else
        return (IntelligenceCode.unavailable, nil)
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func respond(kind: Int32, instructions: String, prompt: String) async -> (code: Int32, text: String?) {
        // Session MỚI mỗi yêu cầu (không mang ngữ cảnh lần trước), greedy = ổn định.
        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(samplingMode: .greedy)
        do {
            if kind == IntelligenceKind.alternatives {
                let r = try await session.respond(to: prompt, generating: VTAlternativesOutput.self, options: options)
                return (IntelligenceCode.ok, r.content.alternatives.joined(separator: String(listSeparator)))
            }
            let r = try await session.respond(to: prompt, generating: VTProofreadOutput.self, options: options)
            return (IntelligenceCode.ok, r.content.lines.joined(separator: String(listSeparator)))
        } catch is CancellationError {
            return (IntelligenceCode.timeout, nil)
        } catch let e as LanguageModelSession.GenerationError {
            switch e {
            case .guardrailViolation: return (IntelligenceCode.guardrail, nil)
            case .exceededContextWindowSize: return (IntelligenceCode.tooLong, nil)
            case .unsupportedLanguageOrLocale: return (IntelligenceCode.unsupportedLanguage, nil)
            case .assetsUnavailable: return (IntelligenceCode.unavailable, nil)
            default: return (IntelligenceCode.failed, "\(e)")
            }
        } catch {
            // iOS 27+: lỗi mới (LanguageModelError) thay GenerationError (deprecated).
            if #available(iOS 27.0, macOS 27.0, *), let e = error as? LanguageModelError {
                switch e {
                case .guardrailViolation, .refusal: return (IntelligenceCode.guardrail, nil)
                case .contextSizeExceeded: return (IntelligenceCode.tooLong, nil)
                case .unsupportedLanguageOrLocale: return (IntelligenceCode.unsupportedLanguage, nil)
                case .timeout: return (IntelligenceCode.timeout, nil)
                default: return (IntelligenceCode.failed, "\(e)")
                }
            }
            return (IntelligenceCode.failed, "\(type(of: error))")
        }
    }
    #endif
}

#if VT_AI_FRAMEWORK
/// Callback C: (ctx, mã, chuỗi UTF-8 — kết quả hoặc tên lỗi, có thể nil). Gọi đúng MỘT lần,
/// từ luồng bất kỳ; chuỗi chỉ sống trong lúc gọi.
public typealias VTAICallback = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void

/// Trạng thái model (IntelligenceStatus) — đồng bộ, rẻ.
@_cdecl("vt_ai_status")
public func vt_ai_status() -> Int32 { IntelligenceEngine.status() }

/// Nạp sẵn model (không chờ).
@_cdecl("vt_ai_prewarm")
public func vt_ai_prewarm(_ instructions: UnsafePointer<CChar>) {
    let ins = String(cString: instructions)
    Task.detached(priority: .utility) { IntelligenceEngine.prewarm(instructions: ins) }
}

/// Chạy một yêu cầu (`kind`: IntelligenceKind). Chép chuỗi vào ngay trước khi trả về.
@_cdecl("vt_ai_run")
public func vt_ai_run(_ kind: Int32, _ instructions: UnsafePointer<CChar>, _ prompt: UnsafePointer<CChar>,
                      _ timeoutMs: Int32, _ ctx: UnsafeMutableRawPointer?, _ callback: VTAICallback) {
    let ins = String(cString: instructions), p = String(cString: prompt)
    let timeout = TimeInterval(timeoutMs) / 1000
    Task.detached(priority: .userInitiated) {
        let r = await IntelligenceEngine.run(kind: kind, instructions: ins, prompt: p, timeout: timeout)
        if let out = r.text {
            out.withCString { callback(ctx, r.code, $0) }
        } else {
            callback(ctx, r.code, nil)
        }
    }
}
#endif
