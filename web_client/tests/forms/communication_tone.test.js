import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FormModel } from '../../src/components/forms/form_models.js';
import { resolveCommunicationTone } from '../../../supabase/functions/_shared/communicationTone.ts';
import cases from '../../../packages/festapp_contracts/communication-tone-cases.json' with { type: 'json' };

test('public forms consume the shared effective communication tone', () => {
    for (const c of cases) {
        const resolved = resolveCommunicationTone(c.value, c.inherited);
        const form = new FormModel({ data: { communication_tone: resolved } });
        assert.equal(form.communicationTone, c.expected);
    }
    assert.equal(new FormModel({ data: { communication_tone: 'invalid' } }).communicationTone, 'formal');
});
