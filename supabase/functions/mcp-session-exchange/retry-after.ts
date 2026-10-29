// Only forward bounded delta seconds, never arbitrary upstream header content.
export function boundedRetryAfter(value: string | null): number {
  return value && /^\d{1,6}$/.test(value) ? Math.min(3600, Math.max(1, Number(value))) : 60;
}
