import '../../theme_config.css';
import './occasion_card_preview.css';
import { createOccasionCardView } from './occasion_card_view.js';
import { OccasionModel } from './occasion_model.js';

// Only the embedding settings window supplies draft data. No auth or DB calls.
export function renderOccasionCardPreview(container, payload) {
    const card = createOccasionCardView(OccasionModel.fromJson(payload.occasion), { locale: payload.locale });
    card.inert = true;
    card.tabIndex = -1;
    container.replaceChildren(card);
}

export function mountOccasionCardPreview(host = window) {
    const container = host.document.getElementById('preview');
    const reportHeight = () => host.parent.postMessage({
        type: 'festapp-occasion-card-height', height: container.getBoundingClientRect().height,
    }, host.location.origin);
    host.addEventListener('message', event => {
        if (event.source !== host.parent || event.origin !== host.location.origin ||
            event.data?.type !== 'festapp-occasion-card-draft') return;
        const payload = event.data;
        const dark = payload.dark === true;
        const root = host.document.documentElement;
        root.lang = payload.locale;
        root.style.colorScheme = dark ? 'dark' : 'light';
        host.document.body.classList.toggle('dark-mode', dark);
        renderOccasionCardPreview(container, payload);
        reportHeight();
    });
    new host.ResizeObserver(reportHeight).observe(container);
    host.parent.postMessage({ type: 'festapp-occasion-card-ready' }, host.location.origin);
}

if (typeof window !== 'undefined' && window.parent !== window && document.getElementById('preview')) {
    mountOccasionCardPreview();
}
