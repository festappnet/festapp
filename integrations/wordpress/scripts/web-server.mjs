import {spawn} from 'node:child_process';
import path from 'node:path';
const child=spawn('pnpm',['exec','vite','--config','tests/fixtures/embedded-checkout/vite.config.mjs'],{cwd:'../../web_client',stdio:'inherit',env:{...process.env,FESTAPP_EMBED_LOCAL_STATUS:path.resolve('.private/backend-status.json')}});
for(const sig of ['SIGTERM','SIGINT'])process.on(sig,()=>child.kill(sig));
child.on('exit',code=>process.exit(code??1));
