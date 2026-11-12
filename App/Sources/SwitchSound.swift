// SwitchSound.swift
// "Phát tiếng khi đổi Việt/Anh" (mặc định TẮT): hai nốt ngắn, đi LÊN = VietTelex, đi XUỐNG =
// bộ gõ khác. Chỉ khi NGƯỜI DÙNG tự đổi (phím tắt, menu bàn phím, phím 🌐) — macOS tự đổi
// theo app/tài liệu thì im lặng, không thì mỗi lần chuyển cửa sổ lại kêu.
//
// "Tự đổi" nhận qua dấu vết gesture của StickyInputSource (chord phím-kèm-modifier ≤1s,
// click dải menu bar ≤5s), nên cần quyền Trợ năng như phím tắt đổi bộ gõ.
// Âm tự tổng hợp (không cần file): cùng nốt với Windows/Linux (switch_sound.cpp).

import AppKit

enum SwitchSound {
    static let sampleRate = 22050
    static let leadMs = 30       // lặng đầu: thiết bị âm thanh có thể cắt mất phần mở đầu
    static let noteMs = 90
    static let gapMs = 20        // nghỉ giữa hai nốt để nghe ra hai nốt
    static let lowHz = 523.25    // C5
    static let highHz = 1046.50  // C6: cách một quãng tám, không lẫn được

    // MARK: - Phần thuần (có test)

    static func shouldPlay(enabled: Bool, wasVietTelex: Bool, isVietTelex: Bool, userGesture: Bool) -> Bool {
        enabled && userGesture && wasVietTelex != isVietTelex
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
        let fade = perNote / 5   // không "tạch" ở hai đầu nốt
        for _ in 0..<lead { u16(0) }
        for (n, hz) in notes.enumerated() {
            for i in 0..<perNote {
                var env = 1.0
                if i < fade { env = Double(i) / Double(fade) }
                else if i >= perNote - fade { env = Double(perNote - 1 - i) / Double(fade) }
                let v = sin(2 * Double.pi * hz * Double(i) / Double(sampleRate)) * env * 0.28
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
    static let settleMs = 60
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
            guard shouldPlay(enabled: AppState.shared.switchSound, wasVietTelex: burstStart,
                             isVietTelex: now, userGesture: burstGesture) else { return }
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
