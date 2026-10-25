# HarfBuzz for Edge workers

Vendored from the MIT-licensed `harfbuzzjs` npm package version 1.6.3.
The engine, JavaScript API and font shaping are unchanged. The declarations also
define the private Emscripten marker locally for standalone type checking. The initialization
patch supplies `wasmBinary` from a statically imported base64 JSON module; the upstream
Node loader calls `fs.readFileSync`, which Supabase Edge workers block. A static import also survives ESZIP path relocation,
which makes module-relative runtime file reads unsuitable.

Regenerate with `python3 automation/vendor_layout_harfbuzz.py /path/to/harfbuzzjs/1.6.3`.
The generator verifies the upstream version and recorded SHA-256 hashes before
copying. Keep the declarations, factory, WASM and license together in the shared
Function bundle. `layoutTextEdgeRuntime_test.ts` exercises real shaping while
blocking synchronous filesystem APIs.
