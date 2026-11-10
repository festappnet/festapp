import {build} from 'esbuild';
import {measurementBuildId} from '../../automation/lib/measurement_build.mjs';
import {mkdir, rm, writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = new URL('../../', import.meta.url);
// Never silently regenerate a stale receiver during a production build.
execFileSync(process.execPath, [fileURLToPath(new URL('build_measurement_runtime.mjs', import.meta.url)), '--check'], {stdio: 'inherit'});
const directory = new URL('workers/form-measurement/dist/', root);
const result = await build({
  absWorkingDir: fileURLToPath(new URL('web_client/', root)),
  entryPoints: [fileURLToPath(new URL('workers/form-measurement/src/worker.mjs', root))],
  define: {BUILD_ID: JSON.stringify(await measurementBuildId())},
  bundle: true, format: 'esm', write: false, legalComments: 'none', target: 'es2022',
});
// Only deploy this build's artifacts, never leftover files from a manual build.
await rm(directory, {recursive: true, force: true});
await mkdir(directory, {recursive: true});
await writeFile(new URL('_worker.js', directory), result.outputFiles[0].contents);
await writeFile(new URL('_routes.json', directory), JSON.stringify({version: 1, include: ['/*'], exclude: []}) + '\n');
