import test from 'node:test';
import assert from 'node:assert/strict';
import {selectSqlTests} from '../../scripts/db_test_selection.mjs';

test('blueprint filter excludes unrelated SQL even when the worktree name matches', () => {
    const root = '/tmp/festapp-blueprint-fixes';
    const files = [`${root}/database/tests/blueprint/layout_test.sql`,
        `${root}/database/tests/emails/queue_test.sql`];
    assert.deepEqual(selectSqlTests(files, ['blueprint'], root), [files[0]]);
    assert.deepEqual(selectSqlTests(files, [files[1]], root), [files[1]]);
    assert.deepEqual(selectSqlTests(files, [], root), files);
});
