// A dedicated current-schema backend. Never resets the older WordPress fixture.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';

const root = path.resolve(import.meta.dirname, '../../..');
const directory = path.join(root, 'integrations/wix/.private/backend');
const project = 'festapp-wix-qa-20261025';
const config = path.join(directory, 'supabase/config.toml');
const initialized = path.join(directory, '../backend-initialized.json');
function run(command, args, options = {}) {
  const result = spawnSync(command, args, {cwd: root, encoding: 'utf8', ...options});
  fs.appendFileSync(path.join(directory, '../backend-setup.log'),
    `${command}: ${result.status}\n${result.stdout || ''}${result.stderr || ''}`, {mode: 0o600});
  if (result.status !== 0) throw Error(`${command} failed; see protected .private/backend-setup.log`);
}
fs.mkdirSync(directory, {recursive: true, mode: 0o700});
if (!fs.existsSync(config)) {
  run('supabase', ['init', '--workdir', directory]);
  let value = fs.readFileSync(config, 'utf8')
    .replace(/^project_id = .*$/m, `project_id = "${project}"`)
    .replace('major_version = 17', 'major_version = 15');
  for (const suffix of ['20', '21', '22', '23', '24', '27', '29']) {
    value = value.replaceAll(`543${suffix}`, `599${suffix}`);
  }
  for (const section of ['db.seed', 'realtime', 'studio', 'inbucket', 'analytics', 'edge_runtime']) {
    value = value.replace(new RegExp(`(\\[${section.replaceAll('.', '\\.')}\\][\\s\\S]*?enabled = )true`), '$1false');
  }
  fs.writeFileSync(config, value);
}
const configuration = fs.readFileSync(config, 'utf8');
function section(name) { return configuration.split(`[${name}]`)[1]?.split(/^\[/m)[0] || ''; }
if (!new RegExp(`^project_id = "${project}"$`, 'm').test(configuration) ||
    !/^port = 59921$/m.test(section('api')) || !/^port = 59922$/m.test(section('db')) ||
    !/^major_version = 15$/m.test(section('db'))) throw Error('Foreign backend configuration or ports');
// Bootstrap is destructive, so permit it only before this project's DB exists.
const inspected = spawnSync('docker', ['inspect', '-f', '{{.State.Running}}', `supabase_db_${project}`], {encoding: 'utf8'});
const exists = inspected.status === 0 && inspected.stdout.trim() === 'true';
const volumeExists = spawnSync('docker', ['volume', 'inspect', `supabase_db_${project}`], {stdio: 'ignore'}).status === 0;
if (!exists && (volumeExists || fs.existsSync(initialized))) {
  if (!volumeExists || !fs.existsSync(initialized) || JSON.parse(fs.readFileSync(initialized)).project !== project) {
    throw Error('Existing database state requires inspection; refusing automatic bootstrap');
  }
  run('supabase', ['start', '--workdir', directory]);
} else if (!exists) {
  run('bash', ['automation/bootstrap_local_db.sh'], {env: {...process.env,
    FESTAPP_LOCAL_DB_WORKDIR: directory, FESTAPP_LOCAL_DB_PROJECT_ID: project, FESTAPP_LOCAL_DB_PORT: '59922'}});
}
const identity = spawnSync('docker', ['exec', `supabase_db_${project}`, 'psql', '-X', '-U', 'postgres',
  '-d', 'postgres', '-Atqc', 'select project from festapp_test_support.disposable_environment where singleton'], {encoding: 'utf8'});
if (identity.status !== 0 || identity.stdout.trim() !== project) throw Error('Incomplete or foreign backend; no automatic reset');
run('docker', ['exec', '-e', 'PGPASSWORD=postgres', `supabase_db_${project}`, 'psql', '-X', '-U', 'supabase_admin', '-d', 'postgres',
  '-v', 'ON_ERROR_STOP=1', '-qc', "ALTER DATABASE postgres SET festapp.email_wake = 'scheduled'; UPDATE public.email_capacity SET paused=true,worker_url=NULL WHERE singleton"]);
let status = spawnSync('supabase', ['status', '--workdir', directory, '--output', 'json'], {encoding: 'utf8'});
// db start is sufficient for the canonical bootstrap, but its running DB makes
// start skip the gateway. A normal stop preserves this project's database.
if (status.status !== 0 || !JSON.parse(status.stdout).API_URL) {
  run('supabase', ['stop', '--workdir', directory]);
  run('supabase', ['start', '--workdir', directory]);
}
status = spawnSync('supabase', ['status', '--workdir', directory, '--output', 'json'], {encoding: 'utf8'});
if (status.status !== 0) throw Error('Cannot read local backend status');
const data = JSON.parse(status.stdout);
if (data.API_URL !== 'http://127.0.0.1:59921') throw Error('Unexpected API target');
fs.writeFileSync(path.join(directory, '../backend-status.json'), JSON.stringify(data), {mode: 0o600});
fs.writeFileSync(initialized, JSON.stringify({project, api: data.API_URL}), {mode: 0o600});
const env = path.join(directory, '../edge.env');
if (!fs.existsSync(env)) fs.writeFileSync(env,
  `EMAIL_PAYLOAD_KEY=${randomBytes(32).toString('base64')}\nDEFAULT_EMAIL=wix-local@example.invalid\n`, {mode: 0o600});
fs.cpSync(path.join(root, 'supabase/functions'), path.join(directory, 'supabase/functions'), {recursive: true});
console.log('Wix canonical backend ready on loopback 59921; no external provider credentials.');
