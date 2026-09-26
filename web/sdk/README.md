# VietTelex Core — JavaScript SDK

[![npm](https://img.shields.io/npm/v/@viettelex/core)](https://www.npmjs.com/package/@viettelex/core)

Nhúng bộ gõ tiếng Việt VietTelex (Telex / VNI) vào website hoặc web app. Engine là bản
C++ của TelexCore biên dịch sang WebAssembly, **khớp 100%** với engine của app macOS/iOS/Android
trên toàn bộ golden corpus (358.017 ca). Mặc định WASM nằm sẵn trong file JS (không tải thêm gì);
có bản **lite** nhỏ hơn và bản **.wasm tách riêng** để cache — xem [Dung lượng file](#dung-lượng-file--file-size).
Không mạng, không lưu dữ liệu.

## Cài đặt

Có trên npm: [`@viettelex/core`](https://www.npmjs.com/package/@viettelex/core)

```sh
npm i @viettelex/core
```

```js
import { attach } from '@viettelex/core';          // bản đầy đủ, WASM nằm sẵn trong JS
// '@viettelex/core/lite' · '@viettelex/core/external' · '@viettelex/core/lite/external'
```

Không dùng bundler? Nạp thẳng từ CDN:

```html
<script type="module">
  import { attach } from 'https://cdn.jsdelivr.net/npm/@viettelex/core@1/dist/viettelex.mjs';
</script>
```

## Dùng nhanh — gắn vào ô nhập

```html
<textarea id="note"></textarea>
<script type="module">
  import { attach } from '@viettelex/core';   // hoặc './viettelex.mjs' từ dist/
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

Bản lite bỏ qua (không báo lỗi) `contextualEnglish`, `englishWordRestore` và
`collisionPrefersVietnamese` vì không có từ điển; `engine.lite` / export `LITE` cho biết đang dùng bản nào.

## Dung lượng file / File size

| Bản | `import` | File chứa WASM | Raw (byte) | gzip -9 (byte) |
|---|---|---|---:|---:|
| full, inline (mặc định) | `@viettelex/core` | `viettelex-wasm.mjs` | 124.647 | 28.110 |
| lite, inline | `@viettelex/core/lite` | `viettelex-lite-wasm.mjs` | 97.763 | 16.962 |
| full, .wasm riêng | `@viettelex/core/external` | `viettelex-core.mjs` + `viettelex-core.wasm` | 3.618 + 90.908 | 1.759 + 20.257 |
| lite, .wasm riêng | `@viettelex/core/lite/external` | `viettelex-lite-core.mjs` + `viettelex-lite-core.wasm` | 3.633 + 70.744 | 1.770 + 11.210 |

Mọi bản cộng thêm phần JS của SDK (`core.mjs` 16.072 / 5.861 gzip, entry ~0,7 KB / 0,4 KB) — `attach()`,
phát hiện bộ gõ khác… Bản cũ (−O3) là 170.378 / 29.730: build `-Oz` + closure + emmalloc hiện tại nhỏ hơn
27% raw mà hành vi không đổi (golden vẫn 100%).

**Vì sao WASM lại cỡ này?** Đo từng phần của file `.wasm` bản full (~91 KB):
- **~49 KB — bảng kiểm tra âm tiết** (trie phụ âm đầu / vần, có và không teencode). Đây là phần lớn nhất,
  phần lớn là ô trống nên gzip nén rất tốt. Nó cho engine biết từ nào *có thể* là tiếng Việt: chặn bỏ dấu
  sai, ngừng bỏ dấu khi gõ tiếng Anh, và tự khôi phục theo luật.
- **~20 KB — mã máy**: toàn bộ logic Telex/VNI, đặt dấu, sửa từ, API.
- **~19 KB — từ điển tiếng Anh** (va chạm Anh/Việt ~770 từ, từ ngữ cảnh ~400, restore-only, loanword).
  Bản lite bỏ đúng phần này. (Trước đây tưởng phần này chiếm đa số; đo thực tế thì bảng âm tiết mới lớn nhất.)
- **Inline base64 thêm 33%** so với file .wasm, và base64 nén gzip kém hơn nhị phân. Base64 được giữ vì chạy
  đúng ở mọi server/bundler (cách mã hoá UTF-8 của emscripten nhỏ hơn nhưng hỏng nếu JS không được phục vụ dạng UTF-8).

Các bộ gõ JS ~10 KB chỉ làm Telex theo luật (bảng thay ký tự). Chúng nhỏ hơn nhưng không có kiểm tra âm tiết,
tự khôi phục tiếng Anh hay xử lý ngữ cảnh — xem mục dưới.

**Chọn bản nào?**
- Mặc định `@viettelex/core`: một file, không cấu hình, giống app 100%.
- Trang cần nhẹ: **`@viettelex/core/lite/external`** (11,2 + 1,8 KB gzip, .wasm cache được lâu dài). Nếu cần
  một file duy nhất: `@viettelex/core/lite`.
- Đã có CDN/bundler và muốn cache: `@viettelex/core/external`. File `.wasm` mặc định tải cạnh file JS
  (`new URL(..., import.meta.url)`, Vite/webpack tự copy); đổi chỗ bằng `createEngine({ wasmUrl })`
  hoặc truyền sẵn bytes `createEngine({ wasmBinary })`.

Bản lite vẫn đủ Telex/VNI, dấu, bỏ dấu tự do, kiểu cũ/mới, kiểm tra âm tiết và tự khôi phục theo luật
(`google`, `github`, `facebook` vẫn khôi phục). Khác bản full ở các từ cần từ điển, ví dụ:

| Gõ | full | lite |
|---|---|---|
| `he is` | he is | he í |
| `affect` | affect | afect |
| `office` | office | ofice |

`test/lite.test.mjs` chạy lại toàn bộ 358.017 ca golden qua cả hai engine (tắt cờ từ điển): 358.004 ca giống hệt,
13 ca khác chỉ vì từ nằm trong từ điển tiếng Anh, 0 ca bất thường.

## Ưu điểm so với bộ gõ thuần JS / Advantages over pure-JS IMEs

- **Cùng một engine với app VietTelex** macOS/iOS/Android/Windows/Linux: 358.017 ca golden khớp 100% với
  engine Swift, nên gõ ở web giống hệt gõ trong app.
- **Tự khôi phục tiếng Anh** (`google`, `github`), **quyết định theo ngữ cảnh** ("he is"), xử lý **va chạm
  Anh/Việt** (bản full).
- **Kiểm tra âm tiết + ngừng bỏ dấu khi từ không thể là tiếng Việt**: không đặt dấu sai chỗ.
- Bỏ dấu tự do, kiểu cũ/mới (hoà/hòa), Quick Telex, VNI, teencode, Simple Telex.
- ⌫ và sửa lại từ vừa gõ (mở lại từ trước), reset khi con trỏ di chuyển.
- **Tự nhường** khi máy đã có bộ gõ tiếng Việt / IME khác.
- `input`, `textarea`, `contenteditable`; ô password/email/number/tel gõ thường; `Ctrl+Space` bật/tắt.
- Đường nóng chạy WebAssembly: ~70 ns mỗi phím tính cả lớp JS (đo trên Node, Apple Silicon); không phụ thuộc
  thư viện nào, không mạng, không gửi dữ liệu đi đâu.
- Có bản lite cho trang nhạy dung lượng.

Đánh đổi: lớn hơn một script ~10 KB chỉ thay ký tự theo luật — vì vậy mới có bản lite và bản .wasm riêng.

## Build & test

```bash
npm run build   # cần Docker (emscripten chạy trong container) → dist/
npm test        # golden corpus qua WASM trên Node (phải 100%) + so sánh lite/full + foreign-IME
```

Mở `demo/index.html` qua một web server local để thử.

---

## English

Embed the VietTelex Vietnamese input engine (Telex/VNI) in any web page. The engine is the C++
port of TelexCore compiled to WebAssembly and matches the VietTelex apps on the full golden corpus
(358,017 cases). By default the WASM is inlined in one ES module; a smaller **lite** build and
**separate-.wasm** builds are also provided. No network, no storage.

`attach(element, options)` turns an `<input>`, `<textarea>` or `contenteditable` into a Vietnamese
field (Ctrl+Space toggles Vietnamese/English). For custom editors use `createEngine()` and apply
each `{ kind, backspaces, insert }` action yourself. Options and defaults are listed in the table above.
MIT licensed.

Install from npm: [`@viettelex/core`](https://www.npmjs.com/package/@viettelex/core) —
`npm i @viettelex/core`, then `import { attach } from '@viettelex/core'` (also `/lite`, `/external`,
`/lite/external`). Without a bundler: `import { attach } from 'https://cdn.jsdelivr.net/npm/@viettelex/core@1/dist/viettelex.mjs'`.

### When the device already has a Vietnamese input method

By default (`yieldToSystemIme: true`) the SDK steps aside as soon as another input method is
detected — an IME with marked text (composition events / keyCode 229) or a UniKey-style
backspace-and-send IME (keydown/input carrying precomposed `â`, `ệ`, `đ`…). It then disables
itself for that field, calls `onForeignIme(reason)` and remembers it in `localStorage`
(`viettelex.foreignIme`). Ctrl+Space turns it back on and stops auto-yielding for the session.
`detectForeignIme(ev)` and `isForeignVietnameseInput(type, data)` are exported for custom editors.

### Builds and file size

| Build | `import` | Raw | gzip -9 |
|---|---|---:|---:|
| full, inline (default) | `@viettelex/core` | 124,647 | 28,110 |
| lite, inline | `@viettelex/core/lite` | 97,763 | 16,962 |
| full, separate .wasm | `@viettelex/core/external` | 3,618 + 90,908 | 1,759 + 20,257 |
| lite, separate .wasm | `@viettelex/core/lite/external` | 3,633 + 70,744 | 1,770 + 11,210 |

Plus the SDK's JS (`core.mjs`, 16,072 / 5,861 gzip) in every build. The old -O3 build was 170,378 / 29,730; the
current `-Oz` + closure + emmalloc build is 27% smaller raw with identical behaviour (golden still 100%).

Why the WASM is this big (full `.wasm`, ~91 KB): **~49 KB syllable-validator tables** (onset/rime tries, mostly
empty cells that gzip well; they tell the engine what can be Vietnamese — no misplaced tones, stop marking on
English, rule-based auto-restore), **~20 KB code** (all of the Telex/VNI logic and API), **~19 KB English
dictionaries** (~770 collisions, ~400 context words, restore-only, loanwords), which power auto-restore of
dictionary words, contextual English and collision handling. The lite build drops exactly those dictionaries.
(The dictionaries were initially assumed to be most of the size; measured, the syllable tables are the largest
part.) Base64 inlining adds 33% and compresses worse than binary; it is kept because it works with any server or
bundler. Rule-based JS IMEs of ~10 KB only do character substitution, without validation, auto-restore or context.

Which build: the default for simplicity; **`@viettelex/core/lite/external`** (11.2 + 1.8 KB gzip, cacheable) for
size-sensitive sites, or `@viettelex/core/lite` for a single file; `@viettelex/core/external` to cache the full
engine. The `.wasm` loads next to the JS (`new URL(..., import.meta.url)`, picked up by Vite/webpack); override with
`createEngine({ wasmUrl })` or pass bytes with `createEngine({ wasmBinary })`.

Lite keeps Telex/VNI, tones, free marking, old/new tone style, the syllable validator and rule-based auto-restore
(`google`, `github` still restore). It silently ignores `contextualEnglish`, `englishWordRestore` and
`collisionPrefersVietnamese` (check `engine.lite` or the `LITE` export). Expected differences: `he is` → "he í",
`affect` → "afect", `office` → "ofice". `test/lite.test.mjs` replays all 358,017 golden inputs through both
engines with the dictionary flags off: 358,004 identical, 13 differ only on English-list words, 0 unexpected.

### Advantages over pure-JS IMEs

- The same engine as the VietTelex macOS/iOS/Android/Windows/Linux apps: 358,017 golden cases match the Swift
  engine 100%, so behaviour is identical everywhere.
- Auto-restore of English words (google, github), contextual English ("he is") and English/Vietnamese collision
  handling (full build).
- Syllable validator and spell-check while typing: no invalid tone placement.
- Free tone placement, modern/traditional tone style, Quick Telex, VNI, teencode, simple Telex.
- Backspace and re-editing a word (reopen the last word); reset on caret moves.
- Yields automatically to the OS or another Vietnamese IME.
- `input`, `textarea`, `contenteditable`; password/email/number/tel fields stay literal; Ctrl+Space toggle.
- WebAssembly hot path: ~70 ns per keystroke including the JS wrapper (Node, Apple Silicon); zero dependencies,
  no network, nothing leaves the page.
- A lite build for size-sensitive sites.

Trade-off: it is bigger than a ~10 KB rule-based script, which is why the lite and separate-.wasm builds exist.
