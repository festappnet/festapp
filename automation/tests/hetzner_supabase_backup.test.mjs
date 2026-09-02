import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const backup = path.join(root, 'automation/hetzner-supabase/backup');

test('scheduled backup is encrypted, bounded, off-host and never authorizes cutover', () => {
  const create = fs.readFileSync(path.join(backup, 'create-online-encrypted-backup.sh'), 'utf8');
  assert.match(create, /plaintext_artifacts_written:false/);
  assert.match(create, /online-operational-backup-not-promotion-rpo0/);
  assert.match(create, /production_cutover_authorized:false/);
  assert.match(create, /festapp-supabase-backups/);
  assert.match(create, /rclone.+--immutable/);
  assert.match(create, /rclone.+check/);
  assert.match(create, /no_check_bucket = true/);
  assert.match(create, /--min-age/);
  assert.match(create, /"\$BACKUP_ROOT\/\.lock"/);
  assert.doesNotMatch(create, /docker compose (?:stop|down|restart|up)/);
  assert.doesNotMatch(create, /ALTER |DELETE FROM|DROP DATABASE/);
});

test('backup shell and systemd contracts are syntactically valid', () => {
  for (const name of [
    'create-online-encrypted-backup.sh', 'upload-encrypted-runtime-logs.sh',
    'install-online-backup.sh',
  ]) {
    const result = spawnSync('bash', ['-n', path.join(backup, name)], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
  }
  const service = fs.readFileSync(path.join(backup, 'festapp-supabase-backup.service'), 'utf8');
  const timer = fs.readFileSync(path.join(backup, 'festapp-supabase-backup.timer'), 'utf8');
  assert.match(service, /ProtectSystem=strict/);
  assert.match(service, /ReadWritePaths=\/var\/backups\/festapp-supabase/);
  assert.match(timer, /Persistent=true/);
  const installer = fs.readFileSync(path.join(backup, 'install-online-backup.sh'), 'utf8');
  assert.match(installer, /\/var\/backups\/festapp-supabase-logs/);
});

test('runtime logs are encrypted before leaving the host and retained off-host', () => {
  const upload = fs.readFileSync(path.join(backup, 'upload-encrypted-runtime-logs.sh'), 'utf8');
  assert.match(upload, /docker logs --timestamps --since 70m/);
  assert.match(upload, /\| age -r "\$AGE_RECIPIENT"/);
  assert.match(upload, /logs\/\$EXPECTED_HOSTNAME/);
  assert.match(upload, /off_host_verified:true/);
  assert.match(upload, /no_check_bucket = true/);
  assert.match(upload, /production_cutover_authorized:false/);
  assert.doesNotMatch(upload, /docker compose (?:stop|down|restart|up)/);
});
