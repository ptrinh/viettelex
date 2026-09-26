// Nhường bộ gõ của máy: phát hiện IME/bộ gõ Việt khác (thuần, không cần DOM).
import assert from 'node:assert/strict';
import { detectForeignIme, isForeignVietnameseInput } from '../dist/viettelex.mjs';

// IME có marked text (macOS Telex, Windows TSF, iOS/Android)
assert.equal(detectForeignIme({ key: 'a', isComposing: true }), 'composition');
assert.equal(detectForeignIme({ key: 'Unidentified', keyCode: 229 }), 'composition');
assert.equal(detectForeignIme({ key: 'Process', keyCode: 229 }), 'composition');
// UniKey/EVKey: backspace rồi gửi thẳng chữ có dấu
assert.equal(detectForeignIme({ key: 'â', keyCode: 0 }), 'injected');
assert.equal(detectForeignIme({ key: 'Đ' }), 'injected');
assert.equal(detectForeignIme({ key: 'ế' }), 'injected');
// Gõ bình thường: không phải bộ gõ khác
for (const k of ['a', 'Z', 's', '1', ' ', ',', 'Backspace', 'ArrowLeft', 'é'.normalize('NFD').at(0)])
  assert.equal(detectForeignIme({ key: k, keyCode: 65 }), null, k);
// input event
assert.equal(isForeignVietnameseInput('insertText', 'ệ'), true);
assert.equal(isForeignVietnameseInput('insertReplacementText', 'tiếng'), true);
assert.equal(isForeignVietnameseInput('insertText', 'a'), false);
assert.equal(isForeignVietnameseInput('deleteContentBackward', null), false);
console.log('foreign-ime: ok');
