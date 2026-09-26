// Lite build (@viettelex/core/lite, -DVTX_NO_ENGLISH_TABLES) vs the full engine.
//
// 1. Every golden input is replayed through BOTH engines with the dictionary flags
//    (contextualEnglish, englishWordRestore, collisionPrefersVietnamese) forced off — lite
//    ignores them anyway. Outputs must be identical, except for cases that touch an English
//    list word: the one lookup not gated by a flag (shouldRestoreRaw after a multi-key tone
//    cancel) still consults the lists in the full build. Such cases are detected by parsing
//    the lists from windows/engine/src/generated_tables.hpp and excluded (count printed).
// 2. Documented, expected differences with the default options (see README).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import * as full from '../dist/viettelex.mjs';
import * as lite from '../dist/viettelex-lite.mjs';

const { Flags, PASSTHROUGH, REPLACE, NONE, ENGLISH_TABLE_FLAGS } = full;
assert.equal(full.LITE, false);
assert.equal(lite.LITE, true);

const here = p => fileURLToPath(new URL(p, import.meta.url));
const lines = gunzipSync(readFileSync(here('../../../android/telexcore/src/test/resources/golden.tsv.gz'))).toString('utf8').split('\n');

// English lists = every quoted word in generated_tables.hpp after the tries.
const gen = readFileSync(here('../../../windows/engine/src/generated_tables.hpp'), 'utf8');
const english = new Set(gen.slice(gen.indexOf('kEnglishCollisions')).match(/"[a-z]+"/g).map(s => s.slice(1, -1)));
assert.ok(english.size > 1000, 'parsed English lists');
const touchesEnglish = (...texts) => texts.some(t => t.toLowerCase().split(/[^a-z]+/).some(w => english.has(w)));

const [mFull, mLite] = await Promise.all([full.loadModule(), lite.loadModule()]);

const LETTER = { F: 'freeMarking', M: 'modernTone', L: 'liveSpellCheck', S: 'simpleTelex', t: 'teencode', Q: 'quickTelex',
  B: 'bracketVowels', V: 'vni', C: 'contextualEnglish', e: 'englishWordRestore', P: 'collisionPrefersVietnamese' };
const tok = a => a.kind === PASSTHROUGH ? 'P' : a.kind === NONE ? 'N' : `R${a.backspaces},${a.insert}`;

// Same harness as golden.test.mjs, with ENGLISH_TABLE_FLAGS always cleared.
function replay(mod, flagsField, ops) {
  const E = new full.VietTelexEngine(mod);
  let f = Flags.teencode | Flags.englishWordRestore, auto = false;
  for (const c of flagsField === '-' ? '' : flagsField) {
    if (c === 'A') auto = true;
    else if (c === 't') f &= ~Flags.teencode;
    else if (c === 'e') f &= ~Flags.englishWordRestore;
    else if (LETTER[c]) f |= Flags[LETTER[c]];
  }
  const set = () => E.setRawFlags(f & ~ENGLISH_TABLE_FLAGS, { autoRestore: auto });
  set();
  const trace = [];
  let screen = [];
  const applyR = a => { screen.splice(Math.max(0, screen.length - a.backspaces)); screen.push(...a.insert); };
  const cps = [...ops];
  if (cps[0] === '@') { trace.push(E.seed(cps.slice(1).join('')) ? '1' : '0'); screen = [...E.composed]; }
  else for (let i = 0; i < cps.length; i++) {
    const c = cps[i];
    if (c === ' ' || c === '.' || c === ',') {
      const p = E.peekCommitText(); const a = E.commitBoundary();
      if (a.kind === REPLACE) applyR(a); screen.push(c); trace.push(`${p}=>${tok(a)}`);
    } else if (c === '<') { const a = E.backspace(); if (a.kind === REPLACE) applyR(a); else screen.pop(); trace.push(tok(a)); }
    else if (c === '^') { const w = E.reopenLastCommit(); if (w != null) { screen.pop(); trace.push('o:' + w); } else trace.push('o~'); }
    else if (c === '#') { E.reset(); trace.push('N'); }
    else if (c === '!') { E.resetContext(); trace.push('N'); }
    else if (c === '%') trace.push('c:' + E.commitText());
    else if (c === '`') {
      const x = cps[i + 1];
      if (x !== undefined) { if (x === 'A') auto = !auto; else if (LETTER[x]) f ^= Flags[LETTER[x]]; set(); i++; }
      trace.push('t');
    } else { const a = E.feed(c); if (a.kind === PASSTHROUGH) screen.push(c); else if (a.kind === REPLACE) applyR(a); trace.push(tok(a)); }
  }
  const out = [trace.join('|'), screen.join(''), E.composed, E.rawKeystrokes, E.previousWordEnglish ? '1' : '0'].join('\t');
  E.destroy();
  return { out, screen: screen.join('') };
}

let compared = 0, excluded = 0, failed = 0;
for (const raw of lines) {
  const line = raw.replace(/\r$/, '');
  if (!line) continue;
  const t1 = line.indexOf('\t'), t2 = line.indexOf('\t', t1 + 1);
  const flags = line.slice(0, t1), ops = line.slice(t1 + 1, t2);
  const a = replay(mFull, flags, ops), b = replay(mLite, flags, ops);
  if (a.out === b.out) { compared++; continue; }
  if (touchesEnglish(ops, a.screen, b.screen)) { excluded++; continue; }
  if (failed++ < 20) console.log('lite differs:', flags, JSON.stringify(ops), '\n  full:', a.out, '\n  lite:', b.out);
}
console.log(`lite: ${compared} identical to full (English flags off), ${excluded} differ only on English-list words, ${failed} unexpected`);
if (compared < 100000 || failed) process.exit(1);

// Documented differences with the default options (contextualEnglish/collision are no-ops in lite).
async function type(mod, text) {
  const e = await mod.createEngine();
  let s = '';
  const apply = (a, ch = '') => { if (a.kind === REPLACE) s = s.slice(0, s.length - a.backspaces) + a.insert; s += ch; };
  for (const ch of text) {
    if (/[a-z]/i.test(ch)) { const a = e.feed(ch); if (a.kind === PASSTHROUGH) s += ch; else apply(a); }
    else apply(e.commitBoundary(), ch);
  }
  apply(e.commitBoundary());
  e.destroy();
  return s;
}
const DIFFS = [   // [typed, full, lite]
  ['he is', 'he is', 'he í'],          // contextual English
  ['affect', 'affect', 'afect'],       // English collision list (ff = tone cancel)
  ['office', 'office', 'ofice'],
];
for (const [inp, f, l] of DIFFS) {
  assert.equal(await type(full, inp), f, `full: ${inp}`);
  assert.equal(await type(lite, inp), l, `lite: ${inp}`);
}
// Same in both: Telex/VNI, tones, validator-based auto-restore.
for (const [inp, want] of [['vieejt nam', 'việt nam'], ['tieengs vieejt', 'tiếng việt'], ['hoaf', 'hòa'], ['cuar', 'của']]) {
  assert.equal(await type(full, inp), want); assert.equal(await type(lite, inp), want);
}
const vni = async (m, t) => { const e = await m.createEngine({ inputMethod: 'vni' }); let s = '';
  for (const ch of t) { const a = e.feed(ch); if (a.kind === REPLACE) s = s.slice(0, s.length - a.backspaces) + a.insert; else s += ch; }
  e.destroy(); return s; };
assert.equal(await vni(full, 'vie65t'), 'việt'); assert.equal(await vni(lite, 'vie65t'), 'việt');
// lite accepts the dictionary options without error and reports them off.
const le = await lite.createEngine({ contextualEnglish: true, collisionPrefersVietnamese: true });
assert.equal(le.lite, true); le.destroy();
console.log('lite: documented differences ok');
