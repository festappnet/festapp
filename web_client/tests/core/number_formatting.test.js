import test from 'node:test';
import assert from 'node:assert/strict';
import { formatPrice } from '../../src/utils/formatters.js';

const normalized = text => text.replace(/[\u00a0\u202f]/g, ' ');
test('prices group only from absolute 10000, preserving decimals and currency spacing', () => {
    for (const [value, expected] of [[1350,'1350 Kč'],[9999,'9999 Kč'],[10000,'10 000 Kč'],[-1350,'-1350 Kč'],[-10000,'-10 000 Kč'],[1350.5,'1350,5 Kč']]) {
        assert.equal(normalized(formatPrice(value,'CZK',2,'cs-CZ')), expected);
    }
    assert.equal(formatPrice(1350,'USD',2,'en-US'), '$1350');
    assert.equal(formatPrice(10000,'USD',2,'en-US'), '$10,000');
});

test('web, email and PDF share the number policy', async () => {
    const { formatDisplayNumber } = await import('../../../supabase/functions/_shared/numberFormatting.ts');
    const { formatCurrency } = await import('../../../supabase/functions/_shared/utilities.ts');
    assert.equal(normalized(formatCurrency(1350)), '1350 Kč');
    assert.equal(normalized(formatCurrency(10000)), '10 000 Kč');
    assert.equal(formatDisplayNumber(1350, 'en-US'), '1350');
    assert.equal(formatDisplayNumber(10000, 'en-US'), '10,000');
    assert.equal(formatDisplayNumber(1350.5, 'de-DE'), '1350,5');
});
