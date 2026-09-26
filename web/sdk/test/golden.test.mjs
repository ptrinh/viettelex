// Replays the golden corpus (TelexCore Swift, `swift run gen-golden`) through the WASM
// engine; must match 100%. Same harness as windows/engine/tests/golden_test.cpp.
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { loadModule, VietTelexEngine, Flags, PASSTHROUGH, REPLACE, NONE } from '../dist/viettelex.mjs';

const golden = fileURLToPath(new URL('../../../android/telexcore/src/test/resources/golden.tsv.gz', import.meta.url));
const lines = gunzipSync(readFileSync(golden)).toString('utf8').split('\n');
const mod = await loadModule();

// GenGolden: configure() SETS letters on a fresh engine (engine defaults = teencode + englishWordRestore).
const LETTER = { F: 'freeMarking', M: 'modernTone', L: 'liveSpellCheck', S: 'simpleTelex', t: 'teencode', Q: 'quickTelex',
  B: 'bracketVowels', V: 'vni', C: 'contextualEnglish', e: 'englishWordRestore', P: 'collisionPrefersVietnamese' };
const ENGINE_DEFAULT = Flags.teencode | Flags.englishWordRestore;

function makeEngine(flagsField) {
  const e = new VietTelexEngine(mod);
  let f = ENGINE_DEFAULT, auto = false;
  for (const c of flagsField === '-' ? '' : flagsField) {
    if (c === 'A') auto = true;
    else if (c === 't') f &= ~Flags.teencode;
    else if (c === 'e') f &= ~Flags.englishWordRestore;
    else if (LETTER[c]) f |= Flags[LETTER[c]];
  }
  return { e, f, auto };
}
const tok = a => a.kind === PASSTHROUGH ? 'P' : a.kind === NONE ? 'N' : `R${a.backspaces},${a.insert}`;

function replay(flagsField, ops) {
  let { e: E, f, auto } = makeEngine(flagsField);
  const trace = [];
  let screen = [];
  forceFlags(E, f, auto);
  const applyR = a => { screen.splice(Math.max(0, screen.length - a.backspaces)); screen.push(...a.insert); };
  const cps = [...ops];
  if (cps[0] === '@') {
    trace.push(E.seed(cps.slice(1).join('')) ? '1' : '0');
    screen = [...E.composed];
  } else {
    for (let i = 0; i < cps.length; i++) {
      const c = cps[i];
      if (c === ' ' || c === '.' || c === ',') {
        const p = E.peekCommitText(); const a = E.commitBoundary();
        if (a.kind === REPLACE) applyR(a); screen.push(c); trace.push(`${p}=>${tok(a)}`);
      } else if (c === '<') {
        const a = E.backspace(); if (a.kind === REPLACE) applyR(a); else screen.pop(); trace.push(tok(a));
      } else if (c === '^') {
        const w = E.reopenLastCommit(); if (w != null) { screen.pop(); trace.push('o:' + w); } else trace.push('o~');
      } else if (c === '#') { E.reset(); trace.push('N'); }
      else if (c === '!') { E.resetContext(); trace.push('N'); }
      else if (c === '%') trace.push('c:' + E.commitText());
      else if (c === '`') {
        const x = cps[i + 1];
        if (x !== undefined) {
          if (x === 'A') auto = !auto;
          else if (LETTER[x]) f ^= Flags[LETTER[x]];
          forceFlags(E, f, auto); i++;
        }
        trace.push('t');
      } else {
        const a = E.feed(c);
        if (a.kind === PASSTHROUGH) screen.push(c); else if (a.kind === REPLACE) applyR(a);
        trace.push(tok(a));
      }
    }
  }
  const out = [flagsField, ops, trace.join('|'), screen.join(''), E.composed, E.rawKeystrokes, E.previousWordEnglish ? '1' : '0'].join('\t');
  E.destroy();
  return out;
}
function forceFlags(E, f, auto) { E.setRawFlags(f, { autoRestore: auto }); }

let total = 0, failed = 0;
for (const raw of lines) {
  const line = raw.replace(/\r$/, '');
  if (!line) continue;
  total++;
  const t1 = line.indexOf('\t'), t2 = line.indexOf('\t', t1 + 1);
  const actual = replay(line.slice(0, t1), line.slice(t1 + 1, t2));
  if (actual !== line) { if (failed < 20) console.log('expected:', line, '\n  actual:', actual); failed++; }
}
console.log(`golden: ${total - failed}/${total} match (${(100 * (total - failed) / total).toFixed(4)}%)`);
if (total < 10000 || failed) process.exit(1);
