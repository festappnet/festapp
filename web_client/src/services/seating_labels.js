import { LocalizationService } from './localization_service.js';

export function seatingGroupText(kind, title) {
    const name = typeof title === 'string' ? title.trim() : '';
    const key = kind === 'standing' ? 'standingPlace'
        : ['table', 'couch', 'row'].includes(kind) ? kind
        : /^\d+$/.test(name) ? 'group' : null;
    if (!key) return name;
    const label = LocalizationService.tr(`OrderOverview.${key}`);
    if (!name) return label;
    const normalized = name.toLocaleLowerCase();
    const prefix = label.toLocaleLowerCase();
    return normalized === prefix || normalized.startsWith(prefix + ' ') ||
        normalized.startsWith(prefix + ':') ? name : `${label} ${name}`;
}
