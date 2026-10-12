import { readFile, writeFile, rename, statfs, stat } from 'node:fs/promises';
import { setTimeout as sleep } from 'node:timers/promises';
import { createMonitoring } from './sdk.mjs';
import { cpuCounters, cpuPercent, memoryPercent, diskMetrics, diskFailure } from './metrics.mjs';

const statePath = '/var/lib/festapp-host-monitor/cpu.json';
const paths = ['/', '/opt/festapp-supabase', '/var/lib/docker', '/var/backups'];
async function sample() {
  const boot = (await readFile('/proc/sys/kernel/random/boot_id', 'utf8')).trim();
  return { boot, at: Date.now(), ...cpuCounters(await readFile('/proc/stat', 'utf8')) };
}
async function run() {
  const token = (await readFile('/etc/festapp-host-monitor/token', 'utf8')).trim();
  const monitor = createMonitoring({ baseUrl: 'https://festapp-monitoring.festapp.workers.dev', token, service: 'festapp-host', release: 'host-v1' });
  const results = [];
  async function measure(id, collect, threshold) {
    try {
      const { percent, reason } = await collect();
      const failed = reason || percent >= threshold;
      results.push({ id, percent: Math.round(percent * 10) / 10, status: failed ? 'failed' : 'ok', reason: reason || (failed ? 'threshold_exceeded' : 'ok') });
    } catch { results.push({ id, status: 'failed', reason: 'measurement_unavailable' }); }
  }
  await measure('cpu', async () => {
    let previous;
    try { previous = JSON.parse(await readFile(statePath, 'utf8')); } catch {}
    let current = await sample();
    if (!previous || previous.boot !== current.boot || current.at - previous.at < 1000 || current.at - previous.at > 180000) {
      previous = current; await sleep(1000); current = await sample();
    }
    const percent = cpuPercent(previous, current);
    await writeFile(statePath + '.tmp', JSON.stringify(current), { mode: 0o600 });
    await rename(statePath + '.tmp', statePath);
    return { percent };
  }, 90);
  await measure('memory', async () => ({ percent: memoryPercent(await readFile('/proc/meminfo', 'utf8')) }), 90);
  await measure('disk', async () => {
    const devices = new Set(), values = [];
    for (const path of paths) {
      const device = (await stat(path)).dev;
      if (devices.has(device)) continue;
      devices.add(device); values.push(diskMetrics(await statfs(path)));
    }
    return { percent: Math.max(...values.map(v => v.percent)), reason: values.map(diskFailure).find(Boolean) };
  }, 90);
  for (const result of results) monitor.heartbeat(result.id, { status: result.status, code: `host_${result.id}`, context: { count: result.percent ?? 0, reason: result.reason } });
  monitor.heartbeat('agent', { status: results.some(r => r.reason === 'measurement_unavailable') ? 'failed' : 'ok', code: 'host_collection', context: { count: results.length } });
  const receipt = await monitor.close({ timeoutMs: 10000 });
  if (receipt.status !== 'flushed' || receipt.receipts.length !== 4 || receipt.dropped) throw Error('collection_failed');
  console.log(JSON.stringify({ event: 'host_monitor_received', results, receipts: receipt.receipts.length }));
}
run().catch(() => { console.error('Festapp host monitoring collection failed'); process.exitCode = 1; });
