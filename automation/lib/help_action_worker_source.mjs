import { readFileSync } from 'node:fs';

// The hosting worker embeds the same pure route policy as the web client.
export const helpActionWorkerSource = readFileSync(
    new URL('../../web_client/src/services/help_action_routes.js', import.meta.url), 'utf8',
).replaceAll('export function ', 'function ');
