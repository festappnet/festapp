import test from 'node:test';
import assert from 'node:assert/strict';
import { TimeHelper } from '../../src/services/time_helper.js';
import { LocalizationService } from '../../src/services/localization_service.js';

test('elapsed hours retain fractional precision', () => {
    assert.equal(TimeHelper.differenceInHours(
        new Date('2025-12-13T10:00:00'), new Date('2025-12-13T12:30:00'),
    ), 2.5);
});

for (const [name, start, end, expected] of [
    ['same day', '2025-11-23T10:00:00', '2025-11-23T14:00:00', /Nov 23, 2025/],
    ['same month', '2025-11-23T10:00:00', '2025-11-25T14:00:00', /^23 - Nov 25/],
    ['same year', '2025-10-23T10:00:00', '2025-11-23T14:00:00', /^Oct 23 - Nov 23/],
    ['different years', '2024-11-23T10:00:00', '2025-11-23T14:00:00', /2024.*2025/],
]) {
    test(`minimal date range: ${name}`, () => {
        assert.match(TimeHelper.getMinimalisticDateRange(new Date(start), new Date(end), 'en-US'), expected);
    });
}

test('implicit date-range locale follows the interface language', t => {
    const previousLocale = LocalizationService.currentLocale;
    t.after(() => { LocalizationService.currentLocale = previousLocale; });
    const start = new Date('2025-11-23T10:00:00');
    const end = new Date('2025-11-23T14:00:00');
    for (const locale of ['cs', 'en', 'de', 'pl', 'sk', 'uk']) {
        LocalizationService.currentLocale = locale;
        const expected = new Intl.DateTimeFormat(locale, {
            year: 'numeric', month: 'short', day: 'numeric',
        }).format(start);
        assert.equal(TimeHelper.getMinimalisticDateRange(start, end), expected, locale);
    }
});
