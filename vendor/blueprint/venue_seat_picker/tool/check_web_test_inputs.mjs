import { existsSync } from 'node:fs';

const required = ['../web/dist/venue_layout_kernel.js', '../web/dist/manifest.json'];
if (required.some((file) => !existsSync(new URL(file, import.meta.url)))) {
  console.error('Web test kernel is missing. Run tool/build_web.sh before pnpm --dir web test.');
  process.exitCode = 1;
}
