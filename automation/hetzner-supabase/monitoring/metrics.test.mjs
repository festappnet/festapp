import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpuCounters, cpuPercent, memoryPercent, diskMetrics, diskFailure } from './metrics.mjs';
test('CPU excludes double-counted guests and treats iowait as idle', () => {
  assert.deepEqual(cpuCounters('cpu 20 0 10 60 10 0 0 0 20 0\ncpu0 1'), { total: 100, idle: 70 });
  assert.equal(cpuPercent({ total: 100, idle: 70 }, { total: 200, idle: 90 }), 80);
  assert.throws(() => cpuPercent({ total: 200, idle: 90 }, { total: 100, idle: 70 }));
});
test('memory uses available including reclaimable caches and rejects absent counters', () => {
  assert.equal(memoryPercent('MemTotal: 1000 kB\nMemFree: 5 kB\nMemAvailable: 400 kB'), 60);
  assert.throws(() => memoryPercent('MemTotal: 1000 kB'));
});
test('disk detects reserved-space headroom and inode exhaustion', () => {
  const value = diskMetrics({ blocks: 100, bfree: 20, bavail: 15, bsize: 1024 ** 3, files: 100, ffree: 10 });
  assert.equal(diskFailure(value), 'disk_inodes');
  assert.equal(diskFailure({ ...value, freeBytes: 1024 ** 3 }), 'disk_space_headroom');
  assert.equal(diskFailure({ ...value, percent: 90 }), 'disk_space_percent');
  assert.equal(diskFailure({ ...value, inodePercent: 20 }), null);
  assert.throws(() => diskMetrics({ blocks: 0 }));
});
