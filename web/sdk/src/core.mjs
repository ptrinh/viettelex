// VietTelex Core — JavaScript SDK.
//
// The engine is the same C++ port the Windows build uses (windows/engine), compiled to
// WebAssembly; it matches the Swift TelexCore on the full golden corpus (see test/).
//
//   import { createEngine, attach } from '@viettelex/core';
//   const engine = await createEngine();              // macOS 1.7.12 defaults
//   const detach = await attach(document.querySelector('textarea'));
//
// No network, no storage: everything runs in the page.

import createVietTelexWasm from './viettelex-wasm.mjs';

/** Engine flags (bitmask, mirrors vtx_engine.h). */
export const Flags = Object.freeze({
  freeMarking: 1 << 0,
  modernTone: 1 << 1,
  liveSpellCheck: 1 << 2,
  simpleTelex: 1 << 3,
  teencode: 1 << 4,
  quickTelex: 1 << 5,
  bracketVowels: 1 << 6,
  vni: 1 << 7,
  contextualEnglish: 1 << 8,
  englishWordRestore: 1 << 9,
  collisionPrefersVietnamese: 1 << 10,
});

/** Defaults of the VietTelex apps (macOS 1.7.12 / iOS / Android). */
export const DEFAULT_OPTIONS = Object.freeze({
  inputMethod: 'telex',          // 'telex' | 'vni'
  freeMarking: true,
  modernTone: false,
  liveSpellCheck: true,
  simpleTelex: false,
  teencode: false,
  quickTelex: false,
  bracketVowels: false,
  contextualEnglish: true,
  englishWordRestore: true,
  collisionPrefersVietnamese: true,
  autoRestore: true,             // restore English words at a word boundary
});

export const PASSTHROUGH = 0, REPLACE = 1, NONE = 2;
const MAX_TEXT = 64;
const ACTION_BYTES = 12 + MAX_TEXT * 2;

let modulePromise = null;
/** Load the WebAssembly module once (it is inlined — no extra request). */
export function loadModule() {
  return (modulePromise ??= createVietTelexWasm());
}

export function flagsFromOptions(opts) {
  const o = { ...DEFAULT_OPTIONS, ...opts };
  let f = 0;
  for (const [k, bit] of Object.entries(Flags)) {
    if (k === 'vni') continue;
    if (o[k]) f |= bit;
  }
  if (o.inputMethod === 'vni') f |= Flags.vni;
  return f;
}

/**
 * One typing context (one per text field is typical). Methods return
 * `{ kind, backspaces, insert }`: for REPLACE, delete `backspaces` characters
 * before the caret and insert `insert`.
 */
export class VietTelexEngine {
  #m; #e; #act; #buf; #autoRestore;

  constructor(module, options = {}) {
    this.#m = module;
    this.#e = module._vtx_create();
    if (!this.#e) throw new Error('VietTelex: out of memory');
    this.#act = module._malloc(ACTION_BYTES);
    this.#buf = module._malloc(MAX_TEXT * 2 + 2);
    this.setOptions(options);
  }

  /** Change settings; safe in the middle of a word. */
  setOptions(options = {}) {
    this.options = { ...DEFAULT_OPTIONS, ...this.options, ...options };
    this.#autoRestore = !!this.options.autoRestore;
    this.#m._vtx_set_flags(this.#e, flagsFromOptions(this.options) >>> 0);
  }

  /** Advanced: set the raw `Flags` bitmask directly (bypasses named options). */
  setRawFlags(bitmask, { autoRestore = this.#autoRestore } = {}) {
    this.#autoRestore = !!autoRestore;
    this.#m._vtx_set_flags(this.#e, bitmask >>> 0);
  }

  #readAction() {
    const i32 = this.#act >> 2;
    const H32 = this.#m.HEAP32, H16 = this.#m.HEAPU16;
    const kind = H32[i32], backspaces = H32[i32 + 1], len = H32[i32 + 2];
    let insert = '';
    if (kind === REPLACE) {
      const o = (this.#act + 12) >> 1;
      insert = String.fromCharCode(...H16.subarray(o, o + len));
    }
    return { kind, backspaces: kind === REPLACE ? backspaces : 0, insert };
  }
  #readBuf(n) {
    if (n < 0) return null;
    const o = this.#buf >> 1;
    return String.fromCharCode(...this.#m.HEAPU16.subarray(o, o + n));
  }

  /** A typed character (case preserved). PASSTHROUGH = insert it yourself. */
  feed(ch) {
    const cp = typeof ch === 'number' ? ch : ch.codePointAt(0);
    this.#m._vtx_feed(this.#e, cp, this.#act);
    return this.#readAction();
  }
  /** Backspace. PASSTHROUGH = let the field delete one character. */
  backspace() { this.#m._vtx_backspace(this.#e, this.#act); return this.#readAction(); }
  /** Word boundary (space, punctuation…): applies auto-restore; insert the boundary char after. */
  commitBoundary() { this.#m._vtx_commit_boundary(this.#e, this.#autoRestore ? 1 : 0, this.#act); return this.#readAction(); }
  /** Composition-style commit: final text of the word, resets it. */
  commitText() { return this.#readBuf(this.#m._vtx_commit_text(this.#e, this.#autoRestore ? 1 : 0, this.#buf, MAX_TEXT + 1)); }
  /** What commitText() would return, without changing state. */
  peekCommitText() { return this.#readBuf(this.#m._vtx_peek_commit_text(this.#e, this.#autoRestore ? 1 : 0, this.#buf, MAX_TEXT + 1)); }
  get composed() { return this.#readBuf(this.#m._vtx_composed(this.#e, this.#buf, MAX_TEXT + 1)); }
  get rawKeystrokes() { return this.#readBuf(this.#m._vtx_raw_keystrokes(this.#e, this.#buf, MAX_TEXT + 1)); }
  get isEmpty() { return !!this.#m._vtx_is_empty(this.#e); }
  get isOverflowed() { return !!this.#m._vtx_is_overflowed(this.#e); }
  get previousWordEnglish() { return !!this.#m._vtx_previous_word_english(this.#e); }
  /** Drop the current word (caret moved, selection changed…). */
  reset() { this.#m._vtx_reset(this.#e); }
  /** Also forget the English context (focus change). */
  resetContext() { this.#m._vtx_reset_context(this.#e); }
  get canReopenLastCommit() { return !!this.#m._vtx_can_reopen_last_commit(this.#e); }
  /** ⌫ right after a boundary: returns the reopened word, or null. */
  reopenLastCommit() { return this.#readBuf(this.#m._vtx_reopen_last_commit(this.#e, this.#buf, MAX_TEXT + 1)); }
  forgetLastCommit() { this.#m._vtx_forget_last_commit(this.#e); }
  /** Rebuild state from a word already on screen; true if it round-trips. */
  seed(word) {
    const n = Math.min(word.length, MAX_TEXT);
    const o = this.#buf >> 1;
    for (let i = 0; i < n; i++) this.#m.HEAPU16[o + i] = word.charCodeAt(i);
    return !!this.#m._vtx_seed(this.#e, this.#buf, n);
  }
  /** Free the native memory. The engine is unusable afterwards. */
  destroy() {
    if (!this.#e) return;
    this.#m._vtx_destroy(this.#e); this.#m._free(this.#act); this.#m._free(this.#buf);
    this.#e = 0;
  }
}

/** Create an engine (loads the WebAssembly module on first call). */
export async function createEngine(options = {}) {
  return new VietTelexEngine(await loadModule(), options);
}

const COMPOSING = /^[A-Za-z]$/;

/** Chữ Việt có dấu (dựng sẵn) — một bộ gõ khác trên máy mới sinh ra được trong keydown/input. */
const VN_DIACRITIC = /[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]/i;

/**
 * Có dấu hiệu một bộ gõ tiếng Việt / IME khác của hệ điều hành đang xử lý phím không?
 * Trả lý do (string) hoặc null. Thuần — không đụng DOM, test được trên Node.
 *  - 'composition': IME có marked text (macOS Telex/VietTelex, Windows TSF, iOS/Android):
 *    keydown isComposing / keyCode 229 / key "Process".
 *  - 'injected': UniKey/EVKey/OpenKey kiểu backspace-rồi-gửi-ký-tự: keydown mang thẳng
 *    chữ có dấu (VK_PACKET / CGEvent unicode) mà người dùng không thể gõ bằng 1 phím Latin.
 */
export function detectForeignIme(ev) {
  if (ev.isComposing || ev.keyCode === 229 || ev.key === 'Process') return 'composition';
  if (typeof ev.key === 'string' && ev.key.length === 1 && VN_DIACRITIC.test(ev.key)) return 'injected';
  return null;
}

/** input event chèn chữ có dấu mà KHÔNG phải do SDK chèn ⇒ bộ gõ khác đang gõ. */
export function isForeignVietnameseInput(inputType, data) {
  return (inputType === 'insertText' || inputType === 'insertReplacementText'
    || inputType === 'insertCompositionText') && typeof data === 'string' && VN_DIACRITIC.test(data);
}

const FOREIGN_KEY = 'viettelex.foreignIme';

/**
 * Make an <input>, <textarea> or contenteditable element type Vietnamese.
 * Returns a `detach()` function. `options.enabled` (default true) can be toggled
 * later with `handle.setEnabled(bool)`; `options.toggleKey` (default 'ctrl+space' — pass
 * null to disable) switches Vietnamese/English.
 *
 * Nhường bộ gõ của máy (mặc định `yieldToSystemIme: true`): khi phát hiện một bộ gõ tiếng
 * Việt / IME khác đang gõ (xem detectForeignIme), SDK tự tắt cho ô này, gọi
 * `options.onForeignIme(reason)` và nhớ trong localStorage để lần sau khởi động ở trạng
 * thái tắt. Người dùng bật lại bằng Ctrl+Space (từ đó không tự nhường nữa trong phiên).
 */
export async function attach(el, options = {}) {
  const engine = await createEngine(options);
  let enabled = options.enabled ?? true;
  const toggleKey = options.toggleKey === undefined ? 'ctrl+space' : options.toggleKey;
  const isField = el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement;
  let expectedCaret = -1;       // caret we left after our own edit
  let composingIME = false;
  const yieldToSystem = options.yieldToSystemIme ?? true;
  let manualOverride = false;   // user bật lại bằng tay → thôi tự nhường
  let ownEdit = false;          // input event do chính SDK phát
  const store = (() => { try { return el.ownerDocument.defaultView.localStorage; } catch { return null; } })();
  if (yieldToSystem && options.enabled === undefined) {
    try { if (store?.getItem(FOREIGN_KEY) === '1') enabled = false; } catch {}
  }
  function yieldTo(reason) {
    if (!yieldToSystem || manualOverride || !enabled) return;
    enabled = false; engine.reset(); expectedCaret = -1;
    try { store?.setItem(FOREIGN_KEY, '1'); } catch {}
    options.onForeignIme?.(reason);
    options.onToggle?.(false);
  }

  const literalField = () => {
    if (!isField) return false;
    const t = (el.getAttribute('type') || 'text').toLowerCase();
    return ['password', 'email', 'number', 'tel'].includes(t);
  };

  const caret = () => {
    if (isField) return el.selectionStart === el.selectionEnd ? el.selectionEnd : -1;
    const s = el.ownerDocument.getSelection();
    return s && s.isCollapsed && el.contains(s.anchorNode) ? s.anchorOffset : -1;
  };

  function replace(backspaces, text) {
    if (isField) {
      const end = el.selectionEnd, start = Math.max(0, end - backspaces);
      el.setRangeText(text, start, end, 'end');
      ownEdit = true;
      try { el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text })); }
      finally { ownEdit = false; }
      expectedCaret = el.selectionEnd;
      return;
    }
    const sel = el.ownerDocument.getSelection();
    for (let i = 0; i < backspaces; i++) sel.modify('extend', 'backward', 'character');
    // execCommand keeps the browser's undo stack and fires input events.
    ownEdit = true;
    try {
      if (text) el.ownerDocument.execCommand('insertText', false, text);
      else if (backspaces) el.ownerDocument.execCommand('delete');
    } finally { ownEdit = false; }
    expectedCaret = caret();
  }

  function onKeyDown(ev) {
    if (toggleKey && ev.key === ' ' && ev.ctrlKey && toggleKey === 'ctrl+space') {
      ev.preventDefault(); manualOverride = true; handle.setEnabled(!enabled); return;
    }
    if (!enabled || composingIME || literalField()) return;
    const foreign = detectForeignIme(ev);
    if (foreign) { yieldTo(foreign); return; }   // để phím cho bộ gõ của máy, không đụng
    if (ev.metaKey || ev.ctrlKey || ev.altKey) { engine.reset(); return; }
    if (caret() < 0) { engine.reset(); return; }
    if (expectedCaret >= 0 && caret() !== expectedCaret) engine.reset();

    if (ev.key === 'Backspace') {
      if (engine.isEmpty && engine.canReopenLastCommit) {
        // Let the field delete the boundary char, then reopen the word.
        setTimeout(() => { if (engine.reopenLastCommit() != null) expectedCaret = caret(); }, 0);
        return;
      }
      const a = engine.backspace();
      ev.preventDefault();
      if (a.kind === REPLACE) replace(a.backspaces, a.insert);
      else if (a.kind === PASSTHROUGH) replace(1, '');
      return;
    }
    if (ev.key.length !== 1) { if (/^(Arrow|Home|End|Page|Enter|Tab|Escape)/.test(ev.key)) engine.reset(); return; }

    const ch = ev.key;
    const composes = COMPOSING.test(ch) || (engine.options.inputMethod === 'vni' && /\d/.test(ch))
      || (engine.options.bracketVowels && /[[\]{}]/.test(ch));
    if (composes) {
      const a = engine.feed(ch);
      // PASSTHROUGH: engine recorded the key but draws nothing — insert it ourselves so
      // the caret we track stays in sync (a native insert would look like a caret move).
      ev.preventDefault();
      if (a.kind === REPLACE) replace(a.backspaces, a.insert);
      else if (a.kind === PASSTHROUGH) replace(0, ch);
      return;
    }
    // Boundary: finish the word (auto-restore), then insert the char ourselves so the
    // restore and the char land in one edit.
    const a = engine.commitBoundary();
    ev.preventDefault();
    if (a.kind === REPLACE) replace(a.backspaces, a.insert + ch); else replace(0, ch);
  }

  const onReset = () => { engine.reset(); expectedCaret = -1; };
  const onBlur = () => { engine.resetContext(); expectedCaret = -1; };
  const onCompStart = () => { composingIME = true; engine.reset(); yieldTo('composition'); };
  const onInput = (ev) => {
    if (!ownEdit && enabled && isForeignVietnameseInput(ev.inputType, ev.data)) yieldTo('injected');
  };
  const onCompEnd = () => { composingIME = false; };

  el.addEventListener('keydown', onKeyDown);
  el.addEventListener('mousedown', onReset);
  el.addEventListener('blur', onBlur);
  el.addEventListener('compositionstart', onCompStart);
  el.addEventListener('compositionend', onCompEnd);
  el.addEventListener('input', onInput);

  const handle = () => {
    el.removeEventListener('keydown', onKeyDown);
    el.removeEventListener('mousedown', onReset);
    el.removeEventListener('blur', onBlur);
    el.removeEventListener('compositionstart', onCompStart);
    el.removeEventListener('compositionend', onCompEnd);
    el.removeEventListener('input', onInput);
    engine.destroy();
  };
  handle.engine = engine;
  handle.setEnabled = (on) => {
    enabled = !!on; engine.reset();
    if (enabled) { manualOverride = true; try { store?.removeItem(FOREIGN_KEY); } catch {} }
    options.onToggle?.(enabled);
  };
  handle.isEnabled = () => enabled;
  handle.setOptions = (o) => engine.setOptions(o);
  return handle;
}

export default { createEngine, attach, loadModule, Flags, DEFAULT_OPTIONS, VietTelexEngine, detectForeignIme, isForeignVietnameseInput };
