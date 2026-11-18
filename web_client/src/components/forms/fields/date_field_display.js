import { Czech } from 'flatpickr/dist/l10n/cs.js';
import { German } from 'flatpickr/dist/l10n/de.js';
import { Spanish } from 'flatpickr/dist/l10n/es.js';
import { Polish } from 'flatpickr/dist/l10n/pl.js';
import { Slovak } from 'flatpickr/dist/l10n/sk.js';
import { Ukrainian } from 'flatpickr/dist/l10n/uk.js';

const displays = {
    cs: { locale: Czech, altFormat: 'j. n. Y', hint: 'D. M. RRRR' },
    de: { locale: German, altFormat: 'd.m.Y', hint: 'TT.MM.JJJJ' },
    es: { locale: Spanish, altFormat: 'd/m/Y', hint: 'DD/MM/AAAA' },
    pl: { locale: Polish, altFormat: 'd.m.Y', hint: 'DD.MM.RRRR' },
    sk: { locale: Slovak, altFormat: 'j. n. Y', hint: 'D. M. RRRR' },
    uk: { locale: Ukrainian, altFormat: 'd.m.Y', hint: 'ДД.ММ.РРРР' },
};

export function dateFieldDisplay(language, fallbackHint) {
    return displays[language] ?? { locale: 'default', altFormat: 'F j, Y', hint: fallbackHint };
}
