// DebugLog.swift
// Opt-in, in-memory ring buffer for field-diagnosing the terminal tap — above all
// the keyboard-hang class (synthetic-event cascade / tap wedge). OFF by default
// (AppState.debugLogging); while off, log() is a cheap early return, so call sites
// are safe to leave on the hot path. While on it keeps the last N timestamped lines
// in memory only (no file I/O) that the user copies from Settings → Thử Nghiệm and
// pastes to the developer.
//
// PRIVACY: records ONLY lifecycle / health events (tap create/teardown, breaker
// trips, active-state, emit bursts as COUNTS) — never the characters typed. Keep it
// that way: this buffer is meant to be shared.

import Foundation

enum DebugLog {
    // 2000, not 400: with debugLogging on, dedupe is off and every keystroke burns
    // ~2 lines — a 400-line ring held only ~35s of typing, so testers copying the log
    // minutes after an incident sent us a window that no longer contained it
    // (field report 2026-07-30). 2000 lines ≈ 3 min of continuous typing, ~160KB
    // worst case, only while debug logging is enabled.
    private static let capacity = 2000
    /// True ring: `head` = next slot to overwrite once full. The old Array +
    /// `removeFirst` shifted all 2000 entries on EVERY line at capacity (~2 per
    /// keystroke while logging is on) — a memmove + retain churn on the tap thread.
    private static var lines: [String] = []
    private static var head = 0
    private static let lock = NSLock()          // tap callback is main; Spotlight scan is off-main
    private static let startNs = DispatchTime.now().uptimeNanoseconds

    /// Append a health event. The message is an @autoclosure so nothing is built when
    /// logging is off (the common case). Never pass user-typed text.
    static func log(_ message: @autoclosure () -> String) {
        guard AppState.shared.debugLogging else { return }
        let ms = Double(DispatchTime.now().uptimeNanoseconds &- startNs) / 1_000_000
        let text = message()
        let line = String(format: "%10.1f  %@", ms, text)
        lock.lock()
        if lines.count < capacity {
            if lines.isEmpty { lines.reserveCapacity(capacity) }
            lines.append(line)
        } else {
            lines[head] = line
            head = (head + 1) % capacity
        }
        lock.unlock()
        // Mirror to the unified log: the in-memory ring DIES with the process, which
        // is exactly when it is needed most (hang → reboot / relaunch wiped the
        // evidence of the build-7 revoke wedge). Structural events only, never typed
        // text — same privacy contract as the ring buffer.
        Signposts.log.notice("\(text, privacy: .public)")
    }

    static func clear() { lock.lock(); lines = []; head = 0; lock.unlock() }

    // "⌫ undo after English restore" counters — local, in memory, this app session only;
    // counts, never text. Always on (two integer bumps per event, not per keystroke).
    private static var restoreUndoOffered = 0
    private static var restoreUndoUsed = 0
    /// A boundary restored a real Vietnamese syllable to raw keys and armed the ⌫ undo.
    static func noteRestoreUndoOffered() { lock.lock(); restoreUndoOffered += 1; lock.unlock() }
    /// The ⌫ undo put the Vietnamese word back.
    static func noteRestoreUndoUsed() { lock.lock(); restoreUndoUsed += 1; lock.unlock() }
    static var restoreUndoStats: (offered: Int, used: Int) {
        lock.lock(); defer { lock.unlock() }
        return (restoreUndoOffered, restoreUndoUsed)
    }

    /// `header` (current runtime state) followed by the ring buffer, ready to copy.
    static func snapshot(header: [String]) -> String {
        lock.lock(); let ring = lines, h = head; lock.unlock()
        let body = Array(ring[h...] + ring[..<h])      // oldest first
        // Log payload strings are ENGLISH on purpose (not VTLocalized): they end up
        // pasted into bug reports, where greppability beats localization.
        let tail = body.isEmpty
            ? ["(log empty — enable debug logging, then reproduce the problem)"]
            : body
        return (header + ["", "— log (\(body.count)/\(capacity) lines, ms since app start) —"] + tail)
            .joined(separator: "\n")
    }
}
