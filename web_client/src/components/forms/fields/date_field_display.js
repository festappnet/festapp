import { Czech } from 'flatpickr/dist/l10n/cs.js';
import { Spanish } from 'flatpickr/dist/l10n/es.js';

const displays = {
    cs: { locale: Czech, altFormat: 'j. n. Y', hint: 'D. M. RRRR' },
    es: { locale: Spanish, altFormat: 'd/m/Y', hint: 'DD/MM/AAAA' },
};

export function dateFieldDisplay(language, fallbackHint) {
    return displays[language] ?? { locale: 'default', altFormat: 'F j, Y', hint: fallbackHint };
}
