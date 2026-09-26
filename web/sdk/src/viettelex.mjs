// @viettelex/core — full engine, WebAssembly inlined (single file, no extra request).
// Same API as every entry point; see core.mjs and README.md.
import factory from './viettelex-wasm.mjs';
import { bindWasm, Flags, DEFAULT_OPTIONS, VietTelexEngine, detectForeignIme, isForeignVietnameseInput } from './core.mjs';
export * from './core.mjs';

/** true when this build has no English dictionaries (contextualEnglish / collision options are ignored). */
export const LITE = false;
export const { loadModule, createEngine, attach } = bindWasm(factory, { lite: LITE });
export default { createEngine, attach, loadModule, Flags, DEFAULT_OPTIONS, VietTelexEngine, detectForeignIme, isForeignVietnameseInput, LITE };
