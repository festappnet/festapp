import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpuCounters, cpuPercent, memoryPercent, diskMetrics, diskFailure, runtimeFailure } from './metrics.mjs';
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

test('existing agent detects OOM/restarts, stale recovery evidence and long DB transactions', () => {
 const now=Date.now(); const good={at:now,ok:true,containers:[{name:'db',running:true,oom:false,restarts:0}],backupAt:now/1000,logUploadAt:now/1000,longTransactions:0};
 assert.equal(runtimeFailure(good,null,now),null);
 assert.equal(runtimeFailure({...good,at:now-180001},null,now),'runtime_collection_unavailable');
 assert.equal(runtimeFailure({...good,containers:[{name:'db',running:true,oom:true}]},null,now),'container_oom');
 assert.equal(runtimeFailure({...good,containers:[{name:'db',running:true,restarts:1}]},good,now),'container_restarted');
 assert.equal(runtimeFailure({...good,backupAt:now/1000-27*3600},good,now),'backup_stale');
 assert.equal(runtimeFailure({...good,logUploadAt:now/1000-3*3600},good,now),'log_upload_stale');
 assert.equal(runtimeFailure({...good,longTransactions:1},good,now),'database_long_transaction');
});

test('existing agent detects PITR archive failure, pending WAL lag and missing base backup', () => {
 const now=Date.now(); const good={at:now,ok:true,containers:[{name:'db',running:true,oom:false,restarts:0}],backupAt:now/1000,logUploadAt:now/1000,longTransactions:0,pitr:{enabled:true,failed:false,oldestPendingSeconds:0,backupAt:now/1000}};
 assert.equal(runtimeFailure(good,null,now),null);
 for (const [change,reason] of [[{enabled:false},'pitr_archiving_disabled'],[{failed:true},'pitr_archive_failed'],[{oldestPendingSeconds:601},'pitr_archive_lag'],[{oldestPendingSeconds:null},'pitr_archive_lag'],[{backupAt:null},'pitr_backup_stale'],[{backupAt:now/1000-27*3600},'pitr_backup_stale']]) {
  assert.equal(runtimeFailure({...good,pitr:{...good.pitr,...change}},good,now),reason);
 }
});
