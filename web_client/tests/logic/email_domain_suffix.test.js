import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classifyEmailDomainSuffix } from '../../src/logic/email_domain_suffix.js';
import { emailTlds } from '../../src/logic/email_tlds.g.js';
const cases = JSON.parse(readFileSync(new URL('../../../shared/email/domain-suffix-cases.json', import.meta.url)));
for (const {email, ...expected} of cases) test(email, () => assert.deepEqual(classifyEmailDomainSuffix(email), expected));
test('every snapshot suffix is included, with no local additions', () => {
    const snapshot = readFileSync(new URL('../../../shared/email/iana-tlds.txt', import.meta.url), 'utf8').trim().split('\n').slice(1).map(tld => tld.toLowerCase());
    assert.deepEqual([...emailTlds], snapshot);
});

test('offline generator rejects damaged input before writing either output', async () => {
    const { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync } = await import('node:fs');
    const { tmpdir } = await import('node:os');
    const { join } = await import('node:path');
    const { spawnSync } = await import('node:child_process');
    const root = mkdtempSync(join(tmpdir(), 'festapp-email-generator-'));
    try {
        mkdirSync(join(root, 'automation'));
        mkdirSync(join(root, 'shared/email'), { recursive: true });
        mkdirSync(join(root, 'web_client/src/logic'), { recursive: true });
        mkdirSync(join(root, 'packages/festapp_core/lib/src/forms'), { recursive: true });
        copyFileSync(new URL('../../../automation/generate_email_tlds.mjs', import.meta.url), join(root, 'automation/generate_email_tlds.mjs'));
        const good = readFileSync(new URL('../../../shared/email/iana-tlds.txt', import.meta.url), 'utf8');
        const js = join(root, 'web_client/src/logic/email_tlds.g.js');
        const dart = join(root, 'packages/festapp_core/lib/src/forms/email_tlds.g.dart');
        for (const damaged of ['', good.split('\n')[0] + '\nCOM\n', good.replace('\nCOM\n', '\nINVALID!\n'), good.replace('\nCOM\n', '\nCZ\n')]) {
            writeFileSync(join(root, 'shared/email/iana-tlds.txt'), damaged);
            writeFileSync(js, 'last good JS'); writeFileSync(dart, 'last good Dart');
            assert.notEqual(spawnSync(process.execPath, [join(root, 'automation/generate_email_tlds.mjs')]).status, 0);
            assert.equal(readFileSync(js, 'utf8'), 'last good JS');
            assert.equal(readFileSync(dart, 'utf8'), 'last good Dart');
        }
        writeFileSync(join(root, 'shared/email/iana-tlds.txt'), good);
        assert.notEqual(spawnSync(process.execPath, [join(root, 'automation/generate_email_tlds.mjs'), '--check']).status, 0, 'check detects stale outputs offline');
        assert.equal(spawnSync(process.execPath, [join(root, 'automation/generate_email_tlds.mjs')]).status, 0);
        assert.equal(spawnSync(process.execPath, [join(root, 'automation/generate_email_tlds.mjs'), '--check']).status, 0);
    } finally { rmSync(root, { recursive: true, force: true }); }
});
