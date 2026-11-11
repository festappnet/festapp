// Use the lane's pinned Node for every child, including pnpm scripts.
import { dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { emitTiming } from '../../web_client/scripts/test_timings.mjs';
emitTiming('toolchain.node', performance.now(), { version: process.version, platform: process.platform, arch: process.arch });
const result = spawnSync(process.argv[2], process.argv.slice(3), {
  stdio: 'inherit', env: { ...process.env, PATH: `${dirname(process.execPath)}:${process.env.PATH}` },
});
if (result.error) console.error(result.error.message);
process.exit(result.status ?? 1);
