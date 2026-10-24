import { LocalizationService } from './localization_service.js';

export class TimeHelper {
    /**
     * Calculates the difference in hours between two dates.
     * @param {Date} start 
     * @param {Date} end 
     * @returns {number} The difference in hours (can be fractional).
     */
    static differenceInHours(start, end) {
        const differenceInMillis = end - start;
        const hoursDifference = differenceInMillis / (1000 * 60 * 60);
        return hoursDifference;
    }

    /**
     * Returns a minimalistic date range string.
     * @param {Date} start 
     * @param {Date} end 
     * @param {string} [locale] - Optional locale code (e.g., 'en-US', 'cs-CZ')
     * @returns {string} Formatted range string
     */
    static getMinimalisticDateRange(start, end, locale) {
        // Default to the selected interface locale if not provided
        const loc = locale || LocalizationService.currentLocale;

        // Helper to formatting
        const fmt = (date, options) => new Intl.DateTimeFormat(loc, options).format(date);

        // Date match check (year, month, day)
        const isSameDate = (d1, d2) => 
            d1.getFullYear() === d2.getFullYear() &&
            d1.getMonth() === d2.getMonth() &&
            d1.getDate() === d2.getDate();

        // Full format: yMMMd roughly equivalent to medium date
        const fullOptions = { year: 'numeric', month: 'short', day: 'numeric' };
        
        if (isSameDate(start, end)) {
            return fmt(end, fullOptions);
        }

        const fullEnd = fmt(end, fullOptions);
        let minimalStart;

        if (start.getFullYear() === end.getFullYear()) {
            if (start.getMonth() === end.getMonth()) {
                // Same month: day only (d)
                minimalStart = fmt(start, { day: 'numeric' });
            } else {
                // Different month, same year: month + day (MMMd)
                minimalStart = fmt(start, { month: 'short', day: 'numeric' });
            }
        } else {
            // Different year: full format
            minimalStart = fmt(start, fullOptions);
        }

        return `${minimalStart} - ${fullEnd}`;
    }
}
