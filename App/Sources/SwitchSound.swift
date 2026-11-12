// SwitchSound.swift
// "Phát tiếng khi đổi Việt/Anh" (mặc định TẮT): hai nốt ngắn, đi LÊN = VietTelex, đi XUỐNG =
// bộ gõ khác. Chỉ khi NGƯỜI DÙNG tự đổi (phím tắt, menu bàn phím, phím 🌐) — macOS tự đổi
// theo app/tài liệu thì im lặng, không thì mỗi lần chuyển cửa sổ lại kêu.
//
// Mọi lần đổi VietTelex ↔ bộ gõ khác đều kêu, trừ lần đổi tự động: app vừa chuyển (bộ nhớ
// theo app của macOS), VietTelex tự chọn lại, ô mật khẩu. Có dấu vết gesture của
// StickyInputSource (cần quyền Trợ năng) thì kêu cả khi vừa chuyển app.
// Âm tự tổng hợp (không cần file): cùng nốt với Windows/Linux (switch_sound.cpp).

import AppKit

enum SwitchSound {
    static let sampleRate = 22050
    static let leadMs = 30       // lặng đầu: thiết bị âm thanh có thể cắt mất phần mở đầu
    static let noteMs = 90
    static let gapMs = 20        // nghỉ giữa hai nốt để nghe ra hai nốt
    // Tiếng gõ gỗ ("tóc"): mỗi nốt gõ một cái rồi tắt ngay trong nốt, không ngân.
    static let lowHz = 250.0
    static let highHz = 375.0    // cao hơn một quãng năm

    // MARK: - Phần thuần (có test)

    /// Phát khi VietTelex ↔ bộ gõ khác, TRỪ các lần đổi tự động: VietTelex tự chọn lại
    /// (`programmatic`), macOS đổi theo app vừa chuyển (`appChangedRecently`) hoặc ô mật khẩu
    /// (`secure`). Có dấu vết gesture của người dùng thì luôn phát. Bản đầu CHỈ phát khi có
    /// gesture ⇒ lúc kêu lúc không (giữ ⌃Space chọn trong bảng, phím tắt không qua tap…).
    static func shouldPlay(enabled: Bool, wasVietTelex: Bool, isVietTelex: Bool, userGesture: Bool,
                           appChangedRecently: Bool = false, programmatic: Bool = false,
                           secure: Bool = false) -> Bool {
        guard enabled, wasVietTelex != isVietTelex, !programmatic else { return false }
        return userGesture || (!appChangedRecently && !secure)
    }

    /// File WAV hoàn chỉnh (PCM 16-bit mono) trong bộ nhớ.
    static func wav(vietnamese: Bool) -> Data {
        let perNote = sampleRate * noteMs / 1000
        let lead = sampleRate * leadMs / 1000, gap = sampleRate * gapMs / 1000
        let notes = vietnamese ? [lowHz, highHz] : [highHz, lowHz]
        let dataBytes = UInt32((lead + perNote + gap + perNote) * 2)
        var d = Data(capacity: 44 + Int(dataBytes))
        func u16(_ v: UInt16) { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8)) }
        func u32(_ v: UInt32) { u16(UInt16(v & 0xFFFF)); u16(UInt16(v >> 16)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        for _ in 0..<lead { u16(0) }
        for (n, hz) in notes.enumerated() {
            for i in 0..<perNote {
                // Mõ gỗ: âm cơ bản gõ rồi tắt nhanh, thêm hai bội âm lệch tắt còn nhanh hơn.
                let t = Double(i) / Double(sampleRate)
                let attack = t < 0.002 ? t / 0.002 : 1.0
                let w0 = 2 * Double.pi * hz * t
                let v = attack * (0.15 * exp(-t / 0.022) * sin(w0)
                                  + 0.035 * exp(-t / 0.008) * sin(2.7 * w0)
                                  + 0.012 * exp(-t / 0.004) * sin(5.2 * w0))
                u16(UInt16(bitPattern: Int16((v * 32767).rounded())))
            }
            if n == 0 { for _ in 0..<gap { u16(0) } }
        }
        return d
    }

    // MARK: - Chạy thật (MAIN thread)

    private static var wasVietTelex: Bool?
    private static var sounds: [Bool: NSSound] = [:]
    /// Một lần đổi có thể bắn NHIỀU notification liền nhau (macOS đi qua trạng thái trung
    /// gian): gom lại, chỉ phát MỘT tiếng cho trạng thái cuối so với trước cả loạt.
    /// 150 ms như StickyInputSource: notification đổi app có thể tới SAU notification TIS.
    static let settleMs = 150
    static let programmaticWindowNs: UInt64 = 700_000_000
    private static var lastProgrammaticNs: UInt64 = 0

    /// VietTelex sắp TỰ chọn lại bộ gõ (giành lại, hết ô mật khẩu): lần đổi đó im lặng.
    static func noteProgrammaticSwitch() { lastProgrammaticNs = DispatchTime.now().uptimeNanoseconds }
    private static var pending: DispatchWorkItem?
    private static var burstStart = false
    private static var burstGesture = false

    /// Từ observer kTISNotifySelectedKeyboardInputSourceChanged.
    static func selectionChanged(isVietTelex: Bool) {
        let was = wasVietTelex ?? isVietTelex
        wasVietTelex = isVietTelex
        if pending == nil { burstStart = was; burstGesture = false }
        if StickyInputSource.shared.userGestureRecently(nowNs: DispatchTime.now().uptimeNanoseconds) {
            burstGesture = true
        }
        pending?.cancel()
        let item = DispatchWorkItem {
            pending = nil
            let now = wasVietTelex ?? isVietTelex
            let t = DispatchTime.now().uptimeNanoseconds
            guard shouldPlay(enabled: AppState.shared.switchSound, wasVietTelex: burstStart,
                             isVietTelex: now, userGesture: burstGesture,
                             appChangedRecently: StickyInputSource.shared.appChangedRecently(nowNs: t),
                             programmatic: lastProgrammaticNs != 0 && t &- lastProgrammaticNs <= programmaticWindowNs,
                             secure: SecureInputMonitor.shared.activeHolder != nil || SecureFieldDetector.isSecure)
            else { return }
            play(vietnamese: now)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(settleMs), execute: item)
    }

    private static func play(vietnamese: Bool) {
        if sounds[vietnamese] == nil { sounds[vietnamese] = NSSound(data: wav(vietnamese: vietnamese)) }
        sounds[!vietnamese]?.stop()
        guard let s = sounds[vietnamese] else { return }
        s.stop()
        s.play()
        DebugLog.log("switch-sound: \(vietnamese ? "vi" : "en")")
    }

    /// Lúc khởi động: nhớ trạng thái hiện tại để lần đổi đầu tiên so đúng.
    static func start() { wasVietTelex = TelexInputController.isVietTelexSelected() }
}
