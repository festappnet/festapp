import {readFile} from 'node:fs/promises';

export const registryUrl = new URL('../../workers/form-measurement/runtimes.json', import.meta.url);

export function validateRuntimes(value) {
  if (!Array.isArray(value) || value.length === 0) throw Error('Runtime registry must be a nonempty array');
  const projects = new Set(), units = new Set();
  for (const entry of value) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join(',') !== 'organization,project,unit' ||
        typeof entry.project !== 'string' || !/^festapp-measurement-unit-[1-9][0-9]*$/.test(entry.project) ||
        !Number.isSafeInteger(entry.organization) || entry.organization < 1 ||
        !Number.isSafeInteger(entry.unit) || entry.unit < 1 ||
        entry.project !== `festapp-measurement-unit-${entry.unit}`) throw Error('Invalid runtime registry entry');
    if (projects.has(entry.project) || units.has(entry.unit)) throw Error('Duplicate runtime project or unit');
    projects.add(entry.project);
    units.add(entry.unit);
  }
  return value;
}

export async function readRuntimes(only) {
  const entries = validateRuntimes(JSON.parse(await readFile(registryUrl, 'utf8')));
  if (only === undefined) return entries;
  const selected = entries.filter(entry => entry.project === only);
  if (!selected.length) throw Error('Unknown runtime project');
  return selected;
}
