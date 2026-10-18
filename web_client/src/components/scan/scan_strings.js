import { LocalizationService } from '../../services/localization_service.js';
export const tr = (key, args = {}) => LocalizationService.tr(`Scanner.${key}`, args, key);
export const reasonText = reason => tr(`reason_${reason}`);
export const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
