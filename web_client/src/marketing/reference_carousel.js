// Native scrolling keeps the published event links usable without JavaScript.
export function initReferenceCarousels(root = document) {
    const win = root.defaultView ?? window;
    const cleanups = [];
    for (const carousel of root.querySelectorAll('[data-reference-carousel]')) {
        const track = carousel.querySelector('[data-reference-track]');
        const controls = carousel.querySelector('[data-reference-controls]');
        const previous = carousel.querySelector('[data-reference-previous]');
        const next = carousel.querySelector('[data-reference-next]');
        const position = carousel.querySelector('[data-reference-position]');
        const cards = [...track.querySelectorAll('.reference-card')];
        if (!cards.length) continue;
        const reduced = win.matchMedia('(prefers-reduced-motion: reduce)');
        let timer;
        const update = () => {
            const box = track.getBoundingClientRect();
            const visible = cards.map((card, index) => ({box: card.getBoundingClientRect(), index}))
                .filter(card => card.box.left < box.right - 8 && card.box.right > box.left + 8);
            previous.disabled = track.scrollLeft <= 2;
            next.disabled = track.scrollLeft + track.clientWidth >= track.scrollWidth - 2;
            previous.hidden = previous.disabled;
            next.hidden = next.disabled;
            position.textContent = visible.length
                ? `${visible[0].index + 1}-${visible.at(-1).index + 1} z ${cards.length} plesů`
                : `${cards.length} plesů`;
            controls.hidden = track.scrollWidth <= track.clientWidth + 2;
        };
        const scroll = direction => {
            const first = cards[0].getBoundingClientRect();
            const step = cards[1] ? cards[1].getBoundingClientRect().left - first.left : first.width;
            const count = Math.max(1, Math.floor(track.clientWidth / step));
            track.scrollBy({left: direction * step * count, behavior: reduced.matches ? 'instant' : 'smooth'});
        };
        const back = () => scroll(-1);
        const forward = () => scroll(1);
        const onScroll = () => {
            win.clearTimeout(timer);
            timer = win.setTimeout(update, 160);
        };
        const onKey = event => {
            if (event.target !== track) return;
            if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
                event.preventDefault();
                scroll(event.key === 'ArrowLeft' ? -1 : 1);
            } else if (event.key === 'Home' || event.key === 'End') {
                event.preventDefault();
                track.scrollTo({left: event.key === 'Home' ? 0 : track.scrollWidth, behavior: reduced.matches ? 'instant' : 'smooth'});
            }
        };
        previous.addEventListener('click', back);
        next.addEventListener('click', forward);
        track.addEventListener('scroll', onScroll, {passive: true});
        track.addEventListener('keydown', onKey);
        win.addEventListener('resize', update);
        update();
        cleanups.push(() => {
            win.clearTimeout(timer);
            previous.removeEventListener('click', back);
            next.removeEventListener('click', forward);
            track.removeEventListener('scroll', onScroll);
            track.removeEventListener('keydown', onKey);
            win.removeEventListener('resize', update);
        });
    }
    return () => cleanups.forEach(cleanup => cleanup());
}
