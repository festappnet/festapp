// Static typed-RPC seam and canonical-only adapter audit; no remote I/O.
import fs from 'node:fs';
import path from 'node:path';
import {REPOSITORY_ROOT} from './lib.mjs';
import {scanWriteSignals} from './write-authority-inventory.mjs';

const POLICY_PATH = path.join(
  REPOSITORY_ROOT,
  'automation/hetzner-supabase/merge/write-authority-policy.json',
);
const RPC_LITERAL = /['"]([a-z][a-z0-9_]+_client_sync_v1)['"]/g;

export function loadWriteAuthorityPolicy(filePath = POLICY_PATH) {
  const policy = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (policy.policy_version !== 1 || policy.source_project !== 'a') {
    throw new Error('unsupported write-authority policy');
  }
  if (!Array.isArray(policy.legacy_adapters) || policy.legacy_adapters.length === 0) {
    throw new Error('write-authority policy has no legacy adapters');
  }
  return policy;
}

export function auditLegacyAdapters(
  policy,
  root = REPOSITORY_ROOT,
) {
  const rpcNames = new Set();
  const entries = policy.legacy_adapters.map((entry) => {
    const adapterPath = path.join(root, entry.path);
    if (!fs.existsSync(adapterPath)) {
      return { ...entry, status: 'missing-adapter', rpc_names: [] };
    }
    const adapter = fs.readFileSync(adapterPath, 'utf8');
    const hasSelectionContract = adapter.includes(policy.selection_contract);
    const moduleProblems = [];
    const entryRpcNames = new Set();
    for (const relativeModule of entry.command_modules) {
      const modulePath = path.join(root, relativeModule);
      if (!fs.existsSync(modulePath)) {
        moduleProblems.push(`missing:${relativeModule}`);
        continue;
      }
      const module = fs.readFileSync(modulePath, 'utf8');
      for (const match of module.matchAll(RPC_LITERAL)) {
        entryRpcNames.add(match[1]);
        rpcNames.add(match[1]);
      }
      if (!module.includes('ClientCommandTransport')) {
        moduleProblems.push(`unbound-transport:${relativeModule}`);
      }
    }
    const selectionValid = entry.canonical_only === true
      ? !hasSelectionContract && !scanWriteSignals(adapter).includes('direct-dml')
      : hasSelectionContract;
    const status = selectionValid && moduleProblems.length === 0 && entryRpcNames.size > 0
      ? (entry.canonical_only === true ? 'rpc-seam-detected-canonical-only' : 'rpc-seam-detected-legacy-fallback-remains')
      : 'blocked';
    return {
      ...entry,
      selection_contract_present: hasSelectionContract,
      module_problems: moduleProblems,
      rpc_names: [...entryRpcNames].sort(),
      status,
    };
  });
  return {
    entries,
    rpc_names: [...rpcNames].sort(),
    seam_detected_adapters: entries.filter((entry) =>
      entry.status.startsWith('rpc-seam-detected-')).length,
    coverage_proof: 'partial-static-evidence-not-operation-completeness',
  };
}
