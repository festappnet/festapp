// Enhance crawlable help documents without remounting the account or search UI.
export function initHelpNavigation(win = window) {
    const doc = win.document;
    if (!win.fetch || !doc.querySelector('.help-layout')) return;
    const runtime = doc.querySelector('script[data-help-runtime]')?.getAttribute('src');
    if (!runtime) return;
    let generation = 0;
    let renderedPath = win.location.pathname + win.location.search;
    const pages = new Map();
    const scrollPositions = new Map();
    const isHelp = url => url.origin === win.location.origin && /^\/napoveda\/(?:[a-z-]+\/)?$/.test(url.pathname);
    const destination = event => {
        const link = event.target.closest?.('a[href]');
        if (!link || link.hasAttribute('download') || (link.target && link.target !== '_self')) return;
        const url = new win.URL(link.href);
        return isHelp(url) ? url : undefined;
    };
    const load = url => {
        const key = url.pathname + url.search;
        if (!pages.has(key)) {
            const pending = win.fetch(key, {credentials: 'same-origin'}).then(async response => {
                if (!response.ok || !response.headers.get('content-type')?.includes('text/html')) throw Error('Help unavailable');
                const next = new win.DOMParser().parseFromString(await response.text(), 'text/html');
                // A release changes the executable/style graph atomically via normal navigation.
                if (!next.querySelector('.help-layout') || next.querySelector('script[data-help-runtime]')?.getAttribute('src') !== runtime ||
                    next.querySelector('link[href*="/assets/help."]')?.getAttribute('href') !==
                    doc.querySelector('link[href*="/assets/help."]')?.getAttribute('href')) throw Error('Help release changed');
                return next;
            }).catch(error => {pages.delete(key); throw error;});
            pages.set(key, pending);
            if (pages.size > 12) pages.delete(pages.keys().next().value);
        }
        return pages.get(key);
    };
    const rememberScroll = () => win.history.replaceState({...win.history.state,
        festappHelpScroll: [win.scrollX, win.scrollY]}, '');
    const scroll = (url, position) => {
        if (position) win.scrollTo({left:position[0], top:position[1], behavior:'instant'});
        else {
            let target;
            try {target = url.hash && doc.getElementById(decodeURIComponent(url.hash.slice(1)));} catch { /* Invalid fragment uses the page top. */ }
            if (target) target.scrollIntoView({block:'start', behavior:'instant'});
            else win.scrollTo({left:0, top:0, behavior:'instant'});
        }
    };
    async function navigate(url, {pop = false, position} = {}) {
        const current = ++generation;
        scrollPositions.set(renderedPath, [win.scrollX, win.scrollY]);
        if (pop) position = scrollPositions.get(url.pathname + url.search) || position;
        if (!pop) rememberScroll();
        doc.dispatchEvent(new win.CustomEvent('help:navigating'));
        doc.querySelector('.help-layout')?.setAttribute('aria-busy', 'true');
        try {
            const next = await load(url);
            if (current !== generation) return;
            const layout = doc.importNode(next.querySelector('.help-layout'), true);
            doc.querySelector('.help-layout').replaceWith(layout);
            doc.title = next.title;
            for (const selector of ['meta[name="description"]', 'link[rel="canonical"]',
                'meta[property^="og:"]', 'script[type="application/ld+json"]']) {
                doc.head.querySelectorAll(selector).forEach(node => node.remove());
                next.head.querySelectorAll(selector).forEach(node => doc.head.append(doc.importNode(node, true)));
            }
            if (!pop) win.history.pushState({festappHelpScroll:[0, 0]}, '', url.href);
            renderedPath = url.pathname + url.search;
            doc.dispatchEvent(new win.CustomEvent('help:navigated'));
            const heading = layout.querySelector('h1');
            heading?.setAttribute('tabindex', '-1');
            heading?.focus({preventScroll:true});
            scroll(url, position);
        } catch {
            if (current === generation) win.location.assign(url.href);
        }
    }
    win.history.scrollRestoration = 'manual';
    rememberScroll();
    doc.addEventListener('click', event => {
        if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        const url = destination(event);
        if (!url) return;
        if (url.pathname + url.search === renderedPath) {
            if (url.hash) doc.dispatchEvent(new win.CustomEvent('help:navigating'));
            return;
        }
        event.preventDefault();
        void navigate(url);
    });
    // A single hovered/focused guide is enough to hide most network latency.
    const prefetch = event => {
        const url = destination(event);
        if (url && url.pathname + url.search !== renderedPath && !win.navigator.connection?.saveData) void load(url).catch(() => {});
    };
    doc.addEventListener('pointerover', prefetch);
    doc.addEventListener('focusin', prefetch);
    win.addEventListener('popstate', event => {
        generation++;
        const url = new win.URL(win.location.href);
        if (isHelp(url) && url.pathname + url.search !== renderedPath) void navigate(url, {pop:true, position:event.state?.festappHelpScroll});
    });
}
