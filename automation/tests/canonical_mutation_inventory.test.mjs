import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {verifyRegistrySlice} from '../client-sync/check_canonical_inventory.mjs';
const inventory=JSON.parse(fs.readFileSync(new URL('../client-sync/canonical-mutation-inventory.json',import.meta.url)));
const sql=fs.readFileSync(new URL('../../supabase/migrations/20261007130000_canonical_mutation_registry.sql',import.meta.url),'utf8');
test('current registry validates the forward state, including the new places dependency',()=>assert.deepEqual(verifyRegistrySlice(inventory,sql),[]));
test('writer change after the historical expansion is detected',()=>assert.match(verifyRegistrySlice(inventory,sql.replace("'move_place_client_sync_v1'","'forgotten_place_writer'" )).join('\n'),/writer drift/));
test('additive mutation registry cannot activate global readiness',()=>assert.match(verifyRegistrySlice(inventory,sql+'\nUPDATE public.client_sync_component_sources SET cutover_ready=true;').join('\n'),/readiness/));
