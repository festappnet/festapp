// Local full-app capture adapter. Shares the production HTML, router and modules.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import base from '../../web_client/vite.config.js';
const input = process.env.FESTAPP_EN_CAPTURE_BACKEND;
if (!input) throw new Error('Explicit disposable backend defines are required');
const backend = JSON.parse(fs.readFileSync(input, 'utf8'));
if (backend.FESTAPP_SUPABASE_URL !== 'http://127.0.0.1:57321') throw new Error('Disposable EN backend required');
const tls = process.env.FESTAPP_EN_CAPTURE_TLS;
if (!tls) throw new Error('Explicit local TLS directory required');
export default {
  ...base,
  root: fileURLToPath(new URL('../../web_client', import.meta.url)),
  server: {...base.server,host:'127.0.0.1',port:57381,strictPort:true,
    https:{key:fs.readFileSync(path.join(tls,'key.pem')),cert:fs.readFileSync(path.join(tls,'cert.pem'))}},
  plugins:[...(base.plugins||[]),{
    name:'disposable-english-runtime',
    transformIndexHtml(html) {
      return html.replace(/<script type="module" src="\/src\/main\.js(?:\?[^"]*)?"><\/script>/,
        `<script type="module">
import {AppConfig} from '/src/app_config.js';
if (location.hostname !== '127.0.0.1' || location.port !== '57381') throw Error('Local capture origin required');
Object.assign(AppConfig, ${JSON.stringify({supabaseUrl:backend.FESTAPP_SUPABASE_URL,anonKey:backend.FESTAPP_SUPABASE_ANON_KEY,organization:900001,backendActivationManifestUrl:'',backendActivationCanonicalManifestSha256:'',supportedLanguages:['en'],defaultLanguage:'en'})});
AppConfig.webLink=location.origin;
await import('/src/main.js');
</script>`);
    },
  }],
};
