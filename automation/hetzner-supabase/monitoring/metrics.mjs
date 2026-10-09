// Linux counters: exclude guest/guest_nice, already counted in user/nice.
export function cpuCounters(text) {
  const values = /^cpu\s+(.+)$/m.exec(text)?.[1].trim().split(/\s+/).slice(0, 8).map(Number);
  if (!values || values.length !== 8 || values.some(v => !Number.isFinite(v) || v < 0)) throw Error('cpu_unavailable');
  return { total: values.reduce((a, b) => a + b, 0), idle: values[3] + values[4] };
}
export function cpuPercent(previous, current) {
  const total = current.total - previous.total, idle = current.idle - previous.idle;
  if (![total, idle].every(Number.isFinite) || total <= 0 || idle < 0 || idle > total) throw Error('cpu_counter_reset');
  return 100 * (total - idle) / total;
}
export function memoryPercent(text) {
  const field = name => Number(new RegExp(`^${name}:\\s+(\\d+) kB$`, 'm').exec(text)?.[1]);
  const total = field('MemTotal'), available = field('MemAvailable');
  if (!(total > 0) || !Number.isFinite(available) || available < 0 || available > total) throw Error('memory_unavailable');
  return 100 * (total - available) / total;
}
export function diskMetrics(fs) {
  const { blocks, bfree, bavail, bsize, files, ffree } = fs;
  if (![blocks, bfree, bavail, bsize, files, ffree].every(Number.isFinite) || blocks <= 0 || bsize <= 0 || bavail < 0 || bavail > bfree || bfree > blocks || files <= 0 || ffree < 0 || ffree > files) throw Error('disk_unavailable');
  return { percent: 100 * (blocks - bfree) / (blocks - bfree + bavail), freeBytes: bavail * bsize, inodePercent: 100 * (files - ffree) / files };
}
export function diskFailure(value) {
  if (value.percent >= 90) return 'disk_space_percent';
  if (value.freeBytes < 2 * 1024 ** 3) return 'disk_space_headroom';
  if (value.inodePercent >= 90) return 'disk_inodes';
  return null;
}
