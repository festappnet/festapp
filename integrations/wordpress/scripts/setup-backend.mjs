import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
const project='festapp-vo-wordpress-20261023';
const workdir='.private/backend';
const run=(cmd,args,options={})=>{const r=spawnSync(cmd,args,{stdio:'inherit',...options});if(r.status)process.exit(r.status)};
fs.mkdirSync('.private',{recursive:true,mode:0o700});
const config=`${workdir}/supabase/config.toml`;
if(!fs.existsSync(config)){
 run('supabase',['init','--workdir',workdir]);
 let s=fs.readFileSync(config,'utf8').replace(/^project_id = .*$/m,`project_id = "${project}"`).replace('major_version = 17','major_version = 15');
 for(const [a,b] of [[54321,59821],[54322,59822],[54320,59820],[54323,59823],[54324,59824],[54327,59827],[54329,59829]])s=s.replaceAll(String(a),String(b));
 for(const section of ['db.seed','realtime','studio','inbucket','analytics','edge_runtime'])s=s.replace(new RegExp(`(\\[${section.replaceAll('.','\\.')}\\][\\s\\S]*?enabled = )true`),'$1false');
 s+='\n[functions.preview-ticket-layout]\nstatic_files = ["./functions/_shared/ticket-assets/*.ttf"]\n[functions.vo-local-capture]\nstatic_files = ["./functions/_shared/ticket-assets/*.ttf"]\n';
 fs.writeFileSync(config,s);
}
if(!fs.readFileSync(config,'utf8').includes(`project_id = "${project}"`))throw Error('Refusing foreign backend');
if(!fs.existsSync('.private/edge.env'))fs.writeFileSync('.private/edge.env',`EMAIL_PAYLOAD_KEY=${randomBytes(32).toString('base64')}\nVO_LOCAL_CAPTURE=1\nVO_CAPTURE_SECRET=${randomBytes(32).toString('hex')}\nDEFAULT_EMAIL=local@example.invalid\nFESTAPP_ALLOWED_WEB_ORIGINS=http://127.0.0.1:59801,http://127.0.0.1:59802,https://localhost:59803,http://127.0.0.1:59804\n`,{mode:0o600});
fs.cpSync('../../supabase/functions',`${workdir}/supabase/functions`,{recursive:true});
fs.mkdirSync(`${workdir}/supabase/functions/vo-local-capture`,{recursive:true});
fs.copyFileSync('tests/capture-email.ts',`${workdir}/supabase/functions/vo-local-capture/index.ts`);
console.log('Disposable backend configured; no external provider credentials.');

fs.mkdirSync(`${workdir}/supabase/functions/vo-onboarding-sink`,{recursive:true});
fs.copyFileSync('tests/onboarding-email-sink.ts',`${workdir}/supabase/functions/vo-onboarding-sink/index.ts`);
if(!fs.readFileSync(config,'utf8').includes('[functions.vo-onboarding-sink]'))fs.appendFileSync(config,'\n[functions.vo-onboarding-sink]\nstatic_files = ["./functions/_shared/ticket-assets/*.ttf"]\n');
console.log('Disposable backend configured; no external provider credentials');
