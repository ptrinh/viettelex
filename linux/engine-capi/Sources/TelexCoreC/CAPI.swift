// CAPI.swift — @_cdecl shim exporting TelexEngine through the C ABI in
// include/telexcore.h. Pure glue: every decision stays in TelexEngine.
//
// Handles are an Unmanaged box around the engine struct. `vt_action` is written
// through raw offsets that mirror the C layout (int32 kind @0, int32 backspaces @4,
// int32 insert_len @8, char insert[128] @12) — pinned by the golden replay test.

import TelexCoreEngine

final class EngineBox {
    var e = TelexEngine()
}

@inline(__always)
private func box(_ h: OpaquePointer) -> EngineBox {
    Unmanaged<EngineBox>.fromOpaque(UnsafeRawPointer(h)).takeUnretainedValue()
}

private let insertCap = 128
private let kindPassthrough: Int32 = 0
private let kindReplace: Int32 = 1
private let kindNone: Int32 = 2

@inline(__always)
private func write(_ a: TelexAction, _ out: UnsafeMutableRawPointer?) {
    guard let out else { return }
    switch a {
    case .passthrough:
        out.storeBytes(of: kindPassthrough, toByteOffset: 0, as: Int32.self)
        out.storeBytes(of: 0, toByteOffset: 4, as: Int32.self)
        out.storeBytes(of: 0, toByteOffset: 8, as: Int32.self)
        out.storeBytes(of: 0, toByteOffset: 12, as: UInt8.self)
    case .none:
        out.storeBytes(of: kindNone, toByteOffset: 0, as: Int32.self)
        out.storeBytes(of: 0, toByteOffset: 4, as: Int32.self)
        out.storeBytes(of: 0, toByteOffset: 8, as: Int32.self)
        out.storeBytes(of: 0, toByteOffset: 12, as: UInt8.self)
    case let .replace(bs, insert):
        out.storeBytes(of: kindReplace, toByteOffset: 0, as: Int32.self)
        out.storeBytes(of: Int32(bs), toByteOffset: 4, as: Int32.self)
        var n = 0
        for b in insert.utf8 {
            if n >= insertCap - 1 { break }
            out.storeBytes(of: b, toByteOffset: 12 + n, as: UInt8.self)
            n += 1
        }
        out.storeBytes(of: 0, toByteOffset: 12 + n, as: UInt8.self)
        out.storeBytes(of: Int32(n), toByteOffset: 8, as: Int32.self)
    }
}

/// snprintf-style copy: writes ≤ cap-1 bytes + NUL, returns the full byte length.
@inline(__always)
private func copyOut(_ s: String, _ buf: UnsafeMutablePointer<CChar>?, _ cap: Int) -> Int {
    var total = 0
    if let buf, cap > 0 {
        var n = 0
        for b in s.utf8 {
            if n < cap - 1 { buf[n] = CChar(bitPattern: b); n += 1 }
            total += 1
        }
        buf[n] = 0
    } else {
        total = s.utf8.count
    }
    return total
}

private func cString(_ p: UnsafePointer<CChar>) -> String {
    var len = 0
    while p[len] != 0 { len += 1 }
    return p.withMemoryRebound(to: UInt8.self, capacity: len) {
        String(decoding: UnsafeBufferPointer(start: $0, count: len), as: UTF8.self)
    }
}

// MARK: - Lifecycle

@_cdecl("vt_engine_new")
public func vt_engine_new() -> OpaquePointer {
    OpaquePointer(Unmanaged.passRetained(EngineBox()).toOpaque())
}

@_cdecl("vt_engine_free")
public func vt_engine_free(_ h: OpaquePointer?) {
    guard let h else { return }
    Unmanaged<EngineBox>.fromOpaque(UnsafeRawPointer(h)).release()
}

@_cdecl("vt_abi_version")
public func vt_abi_version() -> Int32 { 1 }

// MARK: - Flags

@_cdecl("vt_engine_set_flag")
public func vt_engine_set_flag(_ h: OpaquePointer, _ flag: Int32, _ on: Bool) {
    let b = box(h)
    switch flag {
    case 0: b.e.freeMarking = on
    case 1: b.e.modernTone = on
    case 2: b.e.liveSpellCheck = on
    case 3: b.e.simpleTelex = on
    case 4: b.e.teencode = on
    case 5: b.e.quickTelex = on
    case 6: b.e.bracketVowels = on
    case 7: b.e.vniMode = on
    case 8: b.e.contextualEnglish = on
    case 9: b.e.englishWordRestore = on
    case 10: b.e.collisionPrefersVietnamese = on
    default: break
    }
}

@_cdecl("vt_engine_get_flag")
public func vt_engine_get_flag(_ h: OpaquePointer, _ flag: Int32) -> Bool {
    let e = box(h).e
    switch flag {
    case 0: return e.freeMarking
    case 1: return e.modernTone
    case 2: return e.liveSpellCheck
    case 3: return e.simpleTelex
    case 4: return e.teencode
    case 5: return e.quickTelex
    case 6: return e.bracketVowels
    case 7: return e.vniMode
    case 8: return e.contextualEnglish
    case 9: return e.englishWordRestore
    case 10: return e.collisionPrefersVietnamese
    default: return false
    }
}

// MARK: - Editing

@_cdecl("vt_feed")
public func vt_feed(_ h: OpaquePointer, _ ch: UInt32, _ out: UnsafeMutableRawPointer?) {
    guard let scalar = Unicode.Scalar(ch) else { write(.passthrough, out); return }
    let b = box(h)
    write(b.e.feed(Character(scalar)), out)
}

@_cdecl("vt_backspace")
public func vt_backspace(_ h: OpaquePointer, _ out: UnsafeMutableRawPointer?) {
    let b = box(h)
    write(b.e.backspace(), out)
}

@_cdecl("vt_commit")
public func vt_commit(_ h: OpaquePointer, _ autoRestore: Bool, _ out: UnsafeMutableRawPointer?) {
    let b = box(h)
    write(b.e.commitBoundary(autoRestore: autoRestore), out)
}

@_cdecl("vt_commit_text")
public func vt_commit_text(_ h: OpaquePointer, _ autoRestore: Bool,
                           _ buf: UnsafeMutablePointer<CChar>?, _ cap: Int) -> Int {
    let b = box(h)
    return copyOut(b.e.commitText(autoRestore: autoRestore), buf, cap)
}

@_cdecl("vt_peek")
public func vt_peek(_ h: OpaquePointer, _ autoRestore: Bool,
                    _ buf: UnsafeMutablePointer<CChar>?, _ cap: Int) -> Int {
    copyOut(box(h).e.peekCommitText(autoRestore: autoRestore), buf, cap)
}

@_cdecl("vt_composed")
public func vt_composed(_ h: OpaquePointer, _ buf: UnsafeMutablePointer<CChar>?, _ cap: Int) -> Int {
    copyOut(box(h).e.composed, buf, cap)
}

@_cdecl("vt_raw")
public func vt_raw(_ h: OpaquePointer, _ buf: UnsafeMutablePointer<CChar>?, _ cap: Int) -> Int {
    copyOut(box(h).e.rawKeystrokes, buf, cap)
}

@_cdecl("vt_reset")
public func vt_reset(_ h: OpaquePointer) { box(h).e.reset() }

@_cdecl("vt_reset_context")
public func vt_reset_context(_ h: OpaquePointer) { box(h).e.resetContext() }

@_cdecl("vt_forget_last_commit")
public func vt_forget_last_commit(_ h: OpaquePointer) { box(h).e.forgetLastCommit() }

@_cdecl("vt_seed")
public func vt_seed(_ h: OpaquePointer, _ word: UnsafePointer<CChar>?) -> Bool {
    guard let word else { return false }
    return box(h).e.seed(cString(word))
}

@_cdecl("vt_reopen")
public func vt_reopen(_ h: OpaquePointer, _ buf: UnsafeMutablePointer<CChar>?, _ cap: Int) -> Int {
    guard let w = box(h).e.reopenLastCommit() else { return -1 }
    return copyOut(w, buf, cap)
}

// MARK: - State

@_cdecl("vt_is_empty")
public func vt_is_empty(_ h: OpaquePointer) -> Bool { box(h).e.isEmpty }

@_cdecl("vt_is_overflowed")
public func vt_is_overflowed(_ h: OpaquePointer) -> Bool { box(h).e.isOverflowed }

@_cdecl("vt_can_reopen")
public func vt_can_reopen(_ h: OpaquePointer) -> Bool { box(h).e.canReopenLastCommit }

@_cdecl("vt_previous_word_english")
public func vt_previous_word_english(_ h: OpaquePointer) -> Bool { box(h).e.previousWordEnglish }
