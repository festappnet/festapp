#!/usr/bin/env node
// Source inventory only. This tool never loads credentials or contacts a backend.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = 'docs/architecture/operations/inventory.json';
const sourceRoots = ['lib', 'web_client/src', 'supabase/functions', 'workers', 'packages/festapp_core/lib'];
const excluded = new Set(['node_modules', 'dist', 'build', 'test', 'tests', 'fixtures', '.dart_tool']);
const rpcHelpers = new Set(['_invoke', '_configurationCommand', '_adminCommand', 'emailRpc', '_legacyRpc']);
const namePattern = /^[a-z][a-z0-9_]*$/;

function files(directory, extensions) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name, 'en')).flatMap(entry => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) return excluded.has(entry.name) ? [] : files(absolute, extensions);
    return extensions.has(path.extname(entry.name)) && !/(?:[._]test|[._]spec)\./.test(entry.name) ? [absolute] : [];
  });
}

// A lexical inventory, not a Dart/JS/SQL compiler. Preserve line positions while
// removing comments; keep strings so literal endpoint arguments remain visible.
export function tokens(source) {
  const pattern = /\/\/[^\n]*|\/\*[\s\S]*?\*\/|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|`(?:\\[\s\S]|[^`\\])*`|[A-Za-z_$][\w$]*|[^\s]/g;
  const result = [];
  for (const match of source.matchAll(pattern)) {
    const value = match[0];
    if (value.startsWith('//') || value.startsWith('/*')) continue;
    result.push({ value, index: match.index, string: ['"', "'", '`'].includes(value[0]) });
  }
  return result;
}

export function extractCalls(source, file) {
  const ts = tokens(source);
  const found = [];
  const dynamic = [];
  const add = (kind, name, token, via) => found.push({ kind, name, file,
    line: source.slice(0, token.index).split('\n').length, via });
  for (let i = 0; i < ts.length; i++) {
    const token = ts[i];
    const method = token.value;
    const prefix = ts.slice(Math.max(0, i - 6), i).map(t => t.value).join('');
    let kind;
    if (method === 'rpc' && ts[i - 1]?.value === '.') kind = 'rpc';
    else if (method === 'rpc' && file === 'supabase/functions/_shared/bankSyncOperation.ts') kind = 'rpc';
    else if (rpcHelpers.has(method)) kind = 'rpc';
    else if (method === '_rpc' && /(?:reception_service|db_unit_verification)\.dart$/.test(file)) kind = 'rpc';
    else if (method === '_call' && /db_unit_verification\.dart$/.test(file)) kind = 'rpc';
    else if (['_read', 'read'].includes(method) && file.includes('/email_delivery/')) kind = 'rpc';
    else if (method === 'invoke' && ts[i - 1]?.value === '.') kind = /functions\.$/i.test(prefix) ? 'edge' : 'rpc';
    else if (method === 'invoke' && ts[i - 1]?.value !== '.') kind = 'rpc';
    else if (method === 'call' && file === 'web_client/src/services/scanner_api.js') kind = 'rpc';
    else if (method === 'from' && ts[i - 1]?.value === '.') kind = 'table-candidate';
    if (!kind) continue;
    let open = i + 1;
    if (ts[open]?.value === '!') open++;
    // TypeScript generic method calls, e.g. this.rpc<DirtyKey[]>('...').
    if (ts[open]?.value === '<') {
      let depth = 0;
      do {
        if (ts[open]?.value === '<') depth++;
        if (ts[open]?.value === '>') depth--;
        open++;
      } while (open < ts.length && depth > 0);
    }
    if (ts[open]?.value !== '(') continue;
    const first = ts[open + 1];
    if (!first) continue;
    if (['String', ')'].includes(first.value) || ts[open + 2]?.value === ':') continue; // method declaration
    if (method === 'invoke' && ts[i - 1]?.value !== '.' && !first.string) continue;
    if (first.string && [',', ')'].includes(ts[open + 2]?.value)) {
      const value = first.value.slice(1, -1);
      if (value.includes('-') && /^(?:waitlist-commands|send-ticket-order)$/.test(value)) kind = 'edge';
      if ((kind === 'edge' && /^[a-z][a-z0-9-]*$/.test(value)) || namePattern.test(value)) {
        add(kind, value, token, method);
      } else if (kind !== 'table-candidate') {
        dynamic.push({ file, line: source.slice(0, token.index).split('\n').length, kind, expression: 'nonliteral-string', via: method });
      }
    } else if (kind !== 'table-candidate') {
      // Preserve literal branches of a computed argument without claiming dataflow resolution.
      let cursor = open + 1;
      let depth = 0;
      while (cursor < ts.length) {
        const part = ts[cursor];
        if (depth === 0 && [',', ')'].includes(part.value)) break;
        if (part.value === '(') depth++;
        if (part.value === ')') depth--;
        if (part.string && namePattern.test(part.value.slice(1, -1))) {
          add(kind, part.value.slice(1, -1), token, 'argument-branch-candidate');
        }
        cursor++;
      }
      // Finite local selector definitions such as const rpcName = condition ?
      // 'create_ticket_order_client_sync_v1' : 'replace_blueprint_order_client_sync_v1'.
      if (/^[A-Za-z_]\w*$/.test(first.value)) {
        const selector = ts.findIndex((part, index) => part.value === first.value && ts[index + 1]?.value === '=');
        if (selector >= 0) {
          for (let j = selector + 2; j < ts.length && ts[j].value !== ';'; j++) {
            if (ts[j].string && namePattern.test(ts[j].value.slice(1, -1))) {
              add(kind, ts[j].value.slice(1, -1), token, 'local-selector-candidate');
            }
          }
        }
      }
      dynamic.push({ file, line: source.slice(0, token.index).split('\n').length,
        kind, expression: first.string ? 'computed-string' : first.value, via: method });
    } else {
      // Dart uses Tb.<table>.table rather than literal collection names.
      const expression = ts.slice(open + 1, open + 7).map(t => t.value).join('');
      const table = expression.match(/^Tb\.(\w+)\.table[),]/)?.[1];
      if (table) add(kind, table, token, 'from-Tb');
    }
  }
  // REST RPC calls in fetch URLs; only retain the endpoint name, never the URL.
  for (const token of ts.filter(t => t.string)) {
    const name = token.value.match(/\/rest\/v1\/rpc\/([a-z][a-z0-9_]*)(?=[?/'"`]|$)/)?.[1];
    if (name) add('rpc', name, token, 'http-path-reference');
  }
  return { found, dynamic };
}

export function buildInventory(projectRoot) {
  const policyFile = 'automation/hetzner-supabase/merge/runtime-writer-policy.json';
  const policy = JSON.parse(fs.readFileSync(path.join(projectRoot, policyFile), 'utf8'));
  const definitions = new Map();
  for (const absolute of files(path.join(projectRoot, 'database/functions'), new Set(['.sql']))) {
    const source = fs.readFileSync(absolute, 'utf8');
    const pattern = /\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:(\w+)\.)?(\w+)\s*\(([\s\S]*?)\)\s*RETURNS\b/gi;
    for (const match of source.matchAll(pattern)) {
      const name = match[2].toLowerCase();
      const entries = definitions.get(name) ?? [];
      entries.push({ schema: match[1] ?? 'public', file: path.relative(projectRoot, absolute),
        line: source.slice(0, match.index).split('\n').length,
        arguments: match[3].replace(/\s+/g, ' ').trim() });
      definitions.set(name, entries);
    }
  }
  const calls = [];
  const dynamic = [];
  let scannedFiles = 0;
  for (const relative of sourceRoots) {
    for (const absolute of files(path.join(projectRoot, relative), new Set(['.dart', '.js', '.mjs', '.ts', '.tsx']))) {
      scannedFiles++;
      const extracted = extractCalls(fs.readFileSync(absolute, 'utf8'), path.relative(projectRoot, absolute));
      calls.push(...extracted.found);
      dynamic.push(...extracted.dynamic);
    }
  }
  function group(kind) {
    const map = new Map();
    for (const call of calls.filter(c => c.kind === kind)) {
      const refs = map.get(call.name) ?? [];
      const { name, kind: unused, ...reference } = call;
      refs.push(reference);
      map.set(name, refs);
    }
    return [...map].sort(([a], [b]) => a.localeCompare(b, 'en')).map(([name, references]) => ({ name, references,
      ...(kind === 'rpc' ? { definitions: definitions.get(name) ?? [] } : {}) }));
  }
  const rpc = group('rpc');
  // Several active commands are authored only in migrations. Record the latest
  // textual declaration as evidence, never as a claim about the deployed winner.
  const unresolved = new Set(rpc.filter(r => !r.definitions.length).map(r => r.name));
  const migrationReferences = new Map();
  for (const absolute of [...files(path.join(projectRoot, 'supabase/baseline'), new Set(['.sql'])),
    ...files(path.join(projectRoot, 'supabase/migrations'), new Set(['.sql']))].sort()) {
    const source = fs.readFileSync(absolute, 'utf8');
    for (const match of source.matchAll(/\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:\w+\.)?(\w+)\s*\(/gi)) {
      const name = match[1].toLowerCase();
      if (unresolved.has(name)) migrationReferences.set(name, { file: path.relative(projectRoot, absolute),
        line: source.slice(0, match.index).split('\n').length });
    }
  }
  for (const entry of rpc) {
    if (migrationReferences.has(entry.name)) entry.migrationReference = migrationReferences.get(entry.name);
  }
  const edgeMap = new Map(group('edge').map(e => [e.name, e]));
  for (const [name, contract] of Object.entries(policy.edge_functions)) {
    const entry = edgeMap.get(name) ?? { name, references: [] };
    edgeMap.set(name, { ...entry, runtimePolicy: contract });
  }
  for (const directory of fs.readdirSync(path.join(projectRoot, 'supabase/functions'), { withFileTypes: true })) {
    const source = `supabase/functions/${directory.name}/index.ts`;
    if (!directory.isDirectory() || directory.name.startsWith('_') || !fs.existsSync(path.join(projectRoot, source))) continue;
    const entry = edgeMap.get(directory.name) ?? { name: directory.name, references: [] };
    edgeMap.set(directory.name, { ...entry, source, policyStatus: entry.runtimePolicy ? 'in-runtime-policy' : 'source-only-not-in-policy' });
  }
  const sqlDefinitions = [...definitions].sort(([a], [b]) => a.localeCompare(b, 'en')).map(([name, locations]) => ({ name, locations }));
  return { schemaVersion: 1, scope: { sourceRoots, sqlRoot: 'database/functions', edgePolicy: policyFile,
    limitations: [
      'Lexical source evidence, not deployed state, reachability, grants, permissions or a count of business operations.',
      'Literal calls and known wrappers are collected; unresolved dynamic calls remain explicit. HTTP path references may be constants rather than invocations.',
      'Table candidates do not distinguish reads/writes or automatically prove a Supabase receiver. Auth SDK, arbitrary HTTP/Worker routes and SQL-internal calls require the semantic catalog.',
      'Migration/baseline lookup is a fallback for missing authored definitions, not runtime precedence proof. Tests and operator automation are excluded. SQL declarations include internal helpers and overloads, not just callable APIs.',
    ] }, scannedFiles, rpc, edge: [...edgeMap.values()].sort((a, b) => a.name.localeCompare(b.name, 'en')),
    tableCandidates: group('table-candidate'), dynamicCalls: dynamic, sqlDefinitions };
}

export function renderInventory(inventory) {
  const link = reference => `[${reference.file}:${reference.line}](../../../${reference.file}#L${reference.line})`;
  const lines = ['# Generated technical operation inventory', '',
    'Generated by `node automation/generate_operation_inventory.mjs`. Do not edit by hand.', '',
    'Read [the semantic catalog](README.md) first. Counts are source names, not business operations or deployed endpoints.', '',
    `Scanned ${inventory.scannedFiles} runtime source files; ${inventory.rpc.length} RPC names; ${inventory.edge.length} Edge entries; ${inventory.dynamicCalls.length} unresolved dynamic call sites.`, '',
    '## RPC entrypoint references', '', '| Name | SQL evidence | Caller sample |', '|---|---|---|'];
  for (const entry of inventory.rpc) {
    const definition = entry.definitions[0];
    const owner = definition ? `${link(definition)}${entry.definitions.length > 1 ? ` (${entry.definitions.length} declarations; inspect signatures)` : ''}`
      : entry.migrationReference ? `${link(entry.migrationReference)} (migration only)` : 'Not located; investigate';
    lines.push(`| \`${entry.name}\` | ${owner} | ${entry.references.slice(0, 2).map(link).join(', ')}${entry.references.length > 2 ? ` (+${entry.references.length - 2})` : ''} |`);
  }
  lines.push('', '## Edge surfaces', '', '| Name | Source / policy | Trigger and effects from policy |', '|---|---|---|');
  for (const entry of inventory.edge) {
    lines.push(`| \`${entry.name}\` | ${entry.source ? `[source](../../../${entry.source})` : 'No index.ts found'}; ${entry.policyStatus ?? 'caller-only'} | ${entry.runtimePolicy ? `${entry.runtimePolicy.trigger}: ${(entry.runtimePolicy.effects ?? []).join(', ')}` : 'No runtime policy entry; not deployment evidence'} |`);
  }
  lines.push('', '## Unresolved dynamic call sites', '',
    'Includes forwarding wrappers whose callers may already be listed. A dynamic-site count is not a missing-endpoint count. Literal branches/selectors are candidates, not compiler-proven dataflow.', '',
    '| Source | Transport | Expression / wrapper |', '|---|---|---|');
  for (const call of inventory.dynamicCalls) lines.push(`| ${link(call)} | ${call.kind} | \`${call.expression}\` via \`${call.via}\` |`);
  lines.push('', '## Direct table-access candidates', '',
    'Read/write classification and receiver identity require inspecting the caller. Dart Tb names are source identifiers, not a grant audit.', '',
    '| Collection | Caller sample |', '|---|---|');
  for (const entry of inventory.tableCandidates) lines.push(`| \`${entry.name}\` | ${entry.references.slice(0, 2).map(link).join(', ')} |`);
  lines.push('', '## Coverage limits', '', ...inventory.scope.limitations.map(limit => `- ${limit}`), '',
    'The companion [inventory.json](inventory.json) retains every collected reference and authored SQL declaration. SQL-only helpers are not automatically application operations.', '');
  return lines.join('\n');
}

function main() {
  const args = process.argv.slice(2);
  if (args.some(arg => arg !== '--check')) throw new Error('usage: node automation/generate_operation_inventory.mjs [--check]');
  const inventory = buildInventory(root);
  const content = `${JSON.stringify(inventory, null, 2)}\n`;
  for (const [relative, value] of [[output, content], ['docs/architecture/operations/inventory.md', renderInventory(inventory)]]) {
    const target = path.join(root, relative);
    if (args.includes('--check')) {
      if (!fs.existsSync(target) || fs.readFileSync(target, 'utf8') !== value) throw new Error('Operation inventory is stale; regenerate it.');
    } else {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, value);
    }
  }
  console.log(`Operation inventory: ${inventory.rpc.length} RPC names, ${inventory.edge.length} Edge entries, ${inventory.dynamicCalls.length} unresolved call sites.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
