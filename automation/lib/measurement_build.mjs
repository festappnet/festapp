import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';

// Include build tooling and dependency resolution as well as executable sources.
export const buildInputs = [
  'workers/form-measurement/src/worker.mjs',
  'workers/form-measurement/src/bootstrap.js',
  'workers/form-measurement/src/runtime_source.mjs',
  'web_client/src/components/forms/form_measurement_contract.js',
  'web_client/src/components/forms/form_measurement_limits.js',
  'web_client/scripts/build_measurement_worker.mjs',
  'web_client/scripts/build_measurement_runtime.mjs',
  'web_client/pnpm-lock.yaml',
  'automation/lib/measurement_build.mjs',
];
export async function measurementBuildId(root = new URL('../../', import.meta.url)) {
  const hash = createHash('sha256');
  for (const path of buildInputs) {
    const bytes = await readFile(new URL(path, root));
    hash.update(path + '\0' + bytes.length + '\0').update(bytes);
  }
  return hash.digest('hex');
}
