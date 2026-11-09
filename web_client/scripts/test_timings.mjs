import fs from 'node:fs';

export function emitTiming(name, started, fields = {}) {
  if (!process.env.FESTAPP_TIMINGS) return;
  fs.appendFileSync(process.env.FESTAPP_TIMINGS, JSON.stringify({
    name, pid: process.pid, clock: 'process-performance',
    wallStartedAt: new Date(performance.timeOrigin + started).toISOString(),
    monotonicStart: started / 1000,
    seconds: (performance.now() - started) / 1000, ...fields,
  }) + '\n', { mode: 0o600 });
}

export async function timed(name, operation, fields = {}) {
  const started = performance.now();
  try {
    const result = await operation();
    emitTiming(name, started, { success: true, ...fields });
    return result;
  } catch (error) {
    emitTiming(name, started, { success: false, ...fields });
    throw error;
  }
}
