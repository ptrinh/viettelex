# VietTelex Core — JavaScript SDK

Nhúng bộ gõ tiếng Việt VietTelex (Telex / VNI) vào website hoặc web app. Engine là bản
C++ của TelexCore biên dịch sang WebAssembly, **khớp 100%** với engine của app macOS/iOS/Android
trên toàn bộ golden corpus (358.017 ca). Một file ES module ~170 KB (WASM nằm sẵn bên trong,
không tải thêm gì), không mạng, không lưu dữ liệu.

## Dùng nhanh — gắn vào ô nhập

```html
<textarea id="note"></textarea>
<script type="module">
  import { attach } from './viettelex.mjs';          // dist/viettelex.mjs + dist/viettelex-wasm.mjs
  const vt = await attach(document.getElementById('note'));
  // vt.setEnabled(false) · vt.setOptions({ inputMethod: 'vni' }) · vt()  // gỡ
</script>
```

`attach(el, options)` hỗ trợ `<input>`, `<textarea>` và `contenteditable`. `Ctrl+Space` chuyển
Việt/Anh (`toggleKey: null` để tắt). Ô `password`, `email`, `number`, `tel` luôn gõ thường.

### Máy đã có bộ gõ tiếng Việt (UniKey, EVKey, OpenKey, bộ gõ của macOS/Windows, bàn phím điện thoại)

Mặc định `yieldToSystemIme: true`: SDK **tự nhường** ngay khi thấy dấu hiệu bộ gõ khác đang gõ —
IME có chữ gạch chân (sự kiện composition, keyCode 229) hoặc kiểu UniKey xoá-rồi-gửi chữ có dấu
(keydown/input mang thẳng `â`, `ệ`, `đ`…). Khi đó SDK tắt cho ô đó, gọi `onForeignIme(reason)`
và nhớ trong `localStorage` (`viettelex.foreignIme`) để lần sau mở trang đã tắt sẵn. Người dùng
bật lại bằng `Ctrl+Space` — từ đó SDK không tự nhường nữa. Hạn chế: bộ gõ kiểu UniKey chỉ bị
phát hiện ở phím đầu tiên nó sinh chữ có dấu, nên từ đầu tiên có thể đã do SDK xử lý.

## Dùng engine trực tiếp (editor riêng, canvas, game…)

```js
import { createEngine, REPLACE, PASSTHROUGH } from '@viettelex/core';
const engine = await createEngine({ inputMethod: 'telex' });

let a = engine.feed('a');          // { kind, backspaces, insert }
a = engine.feed('s');              // REPLACE: xoá 1, chèn "á"
a = engine.commitBoundary();       // ranh giới từ (space, dấu câu): tự khôi phục tiếng Anh
engine.backspace();                // PASSTHROUGH = để ô nhập tự xoá 1 ký tự
engine.reset();                    // con trỏ di chuyển / đổi selection
engine.destroy();
```

Quy ước giống hệt các app VietTelex: với `REPLACE` xoá `backspaces` ký tự trước con trỏ rồi chèn
`insert`; với `PASSTHROUGH` tự chèn ký tự vừa gõ. Ký tự không phải chữ cái (space, dấu câu…) là
ranh giới từ — gọi `commitBoundary()` trước rồi chèn ký tự đó.

## Tuỳ chọn (mặc định = app VietTelex)

| Tuỳ chọn | Mặc định | |
|---|---|---|
| `inputMethod` | `'telex'` | `'telex'` hoặc `'vni'` |
| `freeMarking` | `true` | Bỏ dấu tự do |
| `modernTone` | `false` | Bỏ dấu kiểu mới (hoà, thuý) |
| `liveSpellCheck` | `true` | Ngừng bỏ dấu khi từ không thể là tiếng Việt |
| `simpleTelex` | `false` | `w` đứng lẻ giữ nguyên |
| `quickTelex` | `false` | `cc`→ch, `nn`→ng… |
| `teencode` | `false` | Chính tả teencode |
| `contextualEnglish` | `true` | Quyết định theo ngữ cảnh ("he is" → he is) |
| `autoRestore` | `true` | Tự khôi phục từ tiếng Anh |
| `bracketVowels` | `false` | `[ ]` → ơ ư |

## Build & test

```bash
npm run build   # cần Docker (emscripten chạy trong container) → dist/
npm test        # golden corpus qua WASM trên Node, phải 100%
```

Mở `demo/index.html` qua một web server local để thử.

---

## English

Embed the VietTelex Vietnamese input engine (Telex/VNI) in any web page. The engine is the C++
port of TelexCore compiled to WebAssembly and matches the VietTelex apps on the full golden corpus
(358,017 cases). One ~170 KB ES module with the WASM inlined; no network, no storage.

`attach(element, options)` turns an `<input>`, `<textarea>` or `contenteditable` into a Vietnamese
field (Ctrl+Space toggles Vietnamese/English). For custom editors use `createEngine()` and apply
each `{ kind, backspaces, insert }` action yourself. Options and defaults are listed in the table above.
MIT licensed.

### When the device already has a Vietnamese input method

By default (`yieldToSystemIme: true`) the SDK steps aside as soon as another input method is
detected — an IME with marked text (composition events / keyCode 229) or a UniKey-style
backspace-and-send IME (keydown/input carrying precomposed `â`, `ệ`, `đ`…). It then disables
itself for that field, calls `onForeignIme(reason)` and remembers it in `localStorage`
(`viettelex.foreignIme`). Ctrl+Space turns it back on and stops auto-yielding for the session.
`detectForeignIme(ev)` and `isForeignVietnameseInput(type, data)` are exported for custom editors.
