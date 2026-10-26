import test from 'node:test';
import assert from 'node:assert/strict';
import {organizerCreatePath, organizerCreateFlutterPath, ORGANIZER_CREATE_ACTION} from '../../src/services/organizer_entry.js';

test('organizer continuation accepts only the known creation workflow', () => {
    for (const path of ['/login?create=1', '/events?create=1', '/?create=1&utm_source=plesy',
        '/login?redirect=' + encodeURIComponent(ORGANIZER_CREATE_ACTION)]) {
        assert.equal(organizerCreatePath(path), '/login?create=1', path);
    }
    for (const path of ['/login', '/form/test?create=1', '/login?create=0', '/login?create=1&create=1',
        '/login?create=1&token=private', '/login?create=1&next=https://evil.invalid',
        '//evil.invalid/login?create=1', 'https://evil.invalid/login?create=1',
        '/login?create=1#order?secret', '/login?redirect=/unit/99/edit']) {
        assert.equal(organizerCreatePath(path), null, path);
    }
});

test('authenticated handoff restores exactly the creation intent', () => {
    const shell = new URL(organizerCreateFlutterPath(), 'https://vstupenky.online');
    assert.equal(shell.pathname, '/flutter');
    const login = new URL(shell.searchParams.get('redirect'), shell.origin);
    assert.equal(login.pathname, '/login');
    assert.equal(login.searchParams.get('redirect'), ORGANIZER_CREATE_ACTION);
    assert.equal(organizerCreatePath(login.pathname + login.search), '/login?create=1');
});
