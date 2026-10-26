import test from 'node:test';
import assert from 'node:assert/strict';
import { extractFunctionBody } from '../lib/sql_function_body.mjs';

test('SQL body comparison handles anonymous and named dollar quotes without reading following ACLs', () => {
  for (const tag of ['$$', '$function$', '$body_2$']) {
    assert.equal(extractFunctionBody(`CREATE FUNCTION f() RETURNS void AS ${tag} BEGIN PERFORM 1; END; ${tag} LANGUAGE plpgsql; GRANT EXECUTE ON FUNCTION f() TO service_role;`), 'BEGINPERFORM1;END;');
  }
});
test('an incomplete function body is rejected instead of reporting parity', () => {
  assert.throws(() => extractFunctionBody('AS $body$ BEGIN; $$'), /no complete/);
});
