import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {verifyRegistrySlice,readCanonicalRegistry} from '../client-sync/check_canonical_inventory.mjs';
const inventory=JSON.parse(fs.readFileSync(new URL('../client-sync/canonical-mutation-inventory.json',import.meta.url)));
const sql=readCanonicalRegistry(new URL('../../',import.meta.url).pathname,inventory);
test('current registry validates the forward state, including the new places dependency',()=>assert.deepEqual(verifyRegistrySlice(inventory,sql),[]));
test('writer change after the historical expansion is detected',()=>assert.match(verifyRegistrySlice(inventory,sql.replace("'move_place_client_sync_v1'","'forgotten_place_writer'" )).join('\n'),/writer drift/));
test('additive mutation registry cannot activate global readiness',()=>assert.match(verifyRegistrySlice(inventory,sql+'\nUPDATE public.client_sync_component_sources SET cutover_ready=true;').join('\n'),/readiness/));

test('predicate references cannot masquerade as scoped registry INSERT rows',()=>assert.deepEqual(verifyRegistrySlice(inventory,sql),[]));

test('seating registry writer drift is checked across the current source owners',()=>assert.match(verifyRegistrySlice(inventory,sql.replace("'set_ticket_seat_assignments'","'forgotten_seating_writer'")).join('\n'),/writer drift/));
