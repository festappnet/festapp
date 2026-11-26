import { LocalizationService } from './localization_service.js';
import { getMinimalisticDateRange } from '../../../supabase/functions/_shared/ticketDate.ts';

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
        return getMinimalisticDateRange(start, end, locale || LocalizationService.currentLocale);
    }
}
