import fs from 'node:fs';
import path from 'node:path';

export function parseKeyValueFile(filePath) {
  const values = new Map();
  if (!fs.existsSync(filePath)) return values;

  for (const rawLine of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    values.set(key, value);
  }
  return values;
}

export function loadCanonicalSupabaseTarget(root, { requireAccessToken = true } = {}) {
  const config = parseKeyValueFile(path.join(root, 'automation/project.conf'));
  const local = parseKeyValueFile(path.join(root, '.env.local'));
  const supabaseUrl = config.get('SUPABASE_URL');
  const projectRef = supabaseUrl?.match(/^https:\/\/([a-z0-9]+)\.supabase\.co$/)?.[1];
  const organization = Number(config.get('ORGANIZATION_ID'));
  const occasionLink = config.get('FORCE_OCCASION_LINK');
  const accessToken = process.env.SUPABASE_ACCESS_TOKEN || local.get('SUPABASE_ACCESS_TOKEN');
  if (!projectRef || !Number.isSafeInteger(organization) || !occasionLink ||
      (requireAccessToken && !accessToken)) {
    throw new Error('valid canonical project config and SUPABASE_ACCESS_TOKEN are required');
  }
  return { projectRef, organization, occasionLink, accessToken };
}

export async function managementQuery({ projectRef, accessToken, query }) {
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${projectRef}/database/query`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query }),
    },
  );
  if (!response.ok) {
    throw new Error(`Supabase management query failed: HTTP ${response.status}`);
  }
  return response.json();
}
