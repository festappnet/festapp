import {readFile} from 'node:fs/promises';

export const registryUrl = new URL('../../workers/form-measurement/runtimes.json', import.meta.url);

export function validateRuntimes(value) {
  if (!Array.isArray(value) || value.length === 0) throw Error('Runtime registry must be a nonempty array');
  const projects = new Set(), units = new Set();
  for (const entry of value) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry) ||
        !['organization,project,unit', 'organization,probe,project,unit'].includes(Object.keys(entry).sort().join(',')) ||
        typeof entry.project !== 'string' || !/^festapp-measurement-unit-[1-9][0-9]*$/.test(entry.project) ||
        !Number.isSafeInteger(entry.organization) || entry.organization < 1 ||
        !Number.isSafeInteger(entry.unit) || entry.unit < 1 ||
        entry.project !== `festapp-measurement-unit-${entry.unit}`) throw Error('Invalid runtime registry entry');
    if (entry.probe !== undefined) {
      const probe = entry.probe;
      if (!probe || typeof probe !== 'object' || Array.isArray(probe) ||
          Object.keys(probe).sort().join(',') !== 'form,parent' ||
          typeof probe.form !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(probe.form)) throw Error('Invalid runtime probe');
      try {
        const parent = new URL(probe.parent);
        if (parent.protocol !== 'https:' || parent.origin !== probe.parent || parent.username || parent.password ||
            parent.origin === `https://${entry.project}.pages.dev`) throw Error();
      } catch { throw Error('Invalid runtime probe parent'); }
    }
    if (projects.has(entry.project) || units.has(entry.unit)) throw Error('Duplicate runtime project or unit');
    projects.add(entry.project);
    units.add(entry.unit);
  }
  return value;
}

export async function readRuntimes(only, organization) {
  const entries = validateRuntimes(JSON.parse(await readFile(registryUrl, 'utf8')));
  if (organization !== undefined) {
    if (!Number.isSafeInteger(organization) || organization < 1) throw Error('Invalid runtime organization');
    return entries.filter(entry => entry.organization === organization);
  }
  if (only === undefined) return entries;
  const selected = entries.filter(entry => entry.project === only);
  if (!selected.length) throw Error('Unknown runtime project');
  return selected;
}
