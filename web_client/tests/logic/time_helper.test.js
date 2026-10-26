
import { TimeHelper } from '../../src/services/time_helper.js';

const start = new Date('2025-12-13T10:00:00');
const end = new Date('2025-12-13T12:30:00');

console.log('Start:', start.toISOString());
console.log('End:', end.toISOString());
const diff = TimeHelper.differenceInHours(start, end);
console.log('Difference in hours:', diff);

if (diff === 2.5) {
    console.log('VERIFICATION PASSED');
    // Continue testing minimalistic date range
} else {
    console.error('VERIFICATION FAILED: Expected 2.5, got ' + diff);
    process.exit(1);
}

// Test cases for getMinimalisticDateRange
const locale = 'en-US';

// Case 1: Same day
const d1 = new Date('2025-11-23T10:00:00');
const d2 = new Date('2025-11-23T14:00:00');
const sameDay = TimeHelper.getMinimalisticDateRange(d1, d2, locale);
console.log(`Same Day: ${sameDay}`);
if (!sameDay.includes('Nov 23, 2025')) {
    console.error('FAILED: Same day should show full date once');
    process.exit(1);
}

// Case 2: Same month
const d3 = new Date('2025-11-23T10:00:00');
const d4 = new Date('2025-11-25T14:00:00');
const sameMonth = TimeHelper.getMinimalisticDateRange(d3, d4, locale);
console.log(`Same Month: ${sameMonth}`);
// Expected: "23 - Nov 25, 2025"
if (!sameMonth.startsWith('23 - Nov 25')) {
     console.error('FAILED: Same month should show day only for start');
     process.exit(1);
}

// Case 3: Same year, different month
const d5 = new Date('2025-10-23T10:00:00');
const d6 = new Date('2025-11-23T14:00:00');
const sameYear = TimeHelper.getMinimalisticDateRange(d5, d6, locale);
console.log(`Same Year: ${sameYear}`);
// Expected: "Oct 23 - Nov 23, 2025"
if (!sameYear.startsWith('Oct 23 - Nov 23')) {
    console.error('FAILED: Same year should show month+day for start');
    process.exit(1);
}

// Case 4: Different year
const d7 = new Date('2024-11-23T10:00:00');
const d8 = new Date('2025-11-23T14:00:00');
const diffYear = TimeHelper.getMinimalisticDateRange(d7, d8, locale);
console.log(`Diff Year: ${diffYear}`);
// Expected: "Nov 23, 2024 - Nov 23, 2025"
if (!diffYear.includes('2024') || !diffYear.includes('2025')) {
    console.error('FAILED: Different year should show full dates with years');
    process.exit(1);
}

console.log('ALL TESTS PASSED');
process.exit(0);

// An implicit locale must follow the interface rather than the host browser.
const { LocalizationService } = await import('../../src/services/localization_service.js');
const previousLocale = LocalizationService.currentLocale;
try {
    for (const uiLocale of ['cs', 'en', 'de', 'pl', 'sk', 'uk']) {
        LocalizationService.currentLocale = uiLocale;
        const expected = new Intl.DateTimeFormat(uiLocale, {
            year: 'numeric', month: 'short', day: 'numeric',
        }).format(d1);
        if (TimeHelper.getMinimalisticDateRange(d1, d2) !== expected) {
            throw new Error(`Date range ignored interface locale ${uiLocale}`);
        }
    }
} finally {
    LocalizationService.currentLocale = previousLocale;
}
