// @viettelex/core/lite — lite engine (no English dictionaries), WebAssembly inlined.
// Same API as every entry point; see core.mjs and README.md.
import factory from './viettelex-lite-wasm.mjs';
import { bindWasm, Flags, DEFAULT_OPTIONS, VietTelexEngine, detectForeignIme, isForeignVietnameseInput } from './core.mjs';
export * from './core.mjs';

/** true when this build has no English dictionaries (contextualEnglish / collision options are ignored). */
export const LITE = true;
export const { loadModule, createEngine, attach } = bindWasm(factory, { lite: LITE });
export default { createEngine, attach, loadModule, Flags, DEFAULT_OPTIONS, VietTelexEngine, detectForeignIme, isForeignVietnameseInput, LITE };
