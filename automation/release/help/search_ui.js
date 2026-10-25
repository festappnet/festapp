(() => {
 function init() {
  const form = document.querySelector('[data-help-search]');
  const dialog = document.querySelector('#help-search-dialog');
  const data = globalThis.FestappHelpSearchData;
  const engine = globalThis.FestappHelpSearchEngine;
  if (!form || !dialog || !data || !engine || !dialog.showModal) return;
  const index = engine.prepare(data.entries);
  const input = form.querySelector('[name=q]');
  const filter = form.querySelector('[name=category]');
  const clear = form.querySelector('[data-search-clear]');
  const region = dialog.querySelector('[data-search-results]');
  const status = region.querySelector('[role=status]');
  const list = region.querySelector('ol');
  const intro = dialog.querySelector('[data-search-intro]');
  const trigger = document.querySelector('[data-search-open]');
  const ui = data.ui;
  let timer, previousFocus, previousOverflow;
  const node = (tag, text, className) => {
    const element = document.createElement(tag);
    if (text) element.textContent = text;
    if (className) element.className = className;
    return element;
  };
  function highlight(element, text, query) {
    const queryTerms = engine.terms(query);
    let start = 0;
    for (const match of text.matchAll(/[\p{L}\p{N}]+/gu)) {
      if (!queryTerms.some(term => engine.wordScore(engine.normalize(match[0]), term) >= .8)) continue;
      element.append(document.createTextNode(text.slice(start, match.index)), node('mark', match[0]));
      start = match.index + match[0].length;
    }
    element.append(document.createTextNode(text.slice(start)));
  }
  function resultUrl(path) {
    if (location.protocol !== 'file:') return path;
    const base = document.querySelector('[data-help-base]').href;
    const [pathname, hash] = path.slice(data.helpRoot.length).split('#');
    return new URL((pathname.endsWith('/') ? pathname + 'index.html' : pathname) + (hash ? '#' + hash : ''), base).href;
  }
  function render() {
    clearTimeout(timer);
    const query = input.value.trim();
    const category = filter.value;
    const active = !!query || !!category;
    clear.hidden = !active;
    intro.hidden = active;
    list.replaceChildren();
    status.textContent = '';
    if (!active) return;
    const {results, relaxed} = engine.search(index, query, category);
    if (!results.length) {
      status.textContent = engine.normalize(query).length < 2 && query ? ui.searchShort : ui.searchEmpty;
      const item = node('li', '', 'help-search-empty');
      item.append(node('p', ui.searchEmptyHint));
      const support = node('a', ui.support); support.href = data.supportUrl;
      item.append(support); list.append(item);
    } else {
      const plural = new Intl.PluralRules(data.locale).select(results.length);
      const word = ui.searchCounts[plural === 'one' ? 0 : plural === 'few' ? 1 : 2];
      status.textContent = (relaxed ? ui.searchPartial + ' ' : '') + results.length + ' ' + word;
      for (const result of results) {
        const item = node('li', '', 'help-search-hit');
        const link = node('a'); link.href = resultUrl(result.href);
        link.append(node('span', result.categoryLabel, 'help-search-hit-category'));
        const title = node('span', '', 'help-search-hit-title'); highlight(title, result.title, query); link.append(title);
        const anchor = result.href.split('#')[1];
        const section = result.sections.find(section => section.anchor === anchor);
        if (section?.heading) link.append(node('span', section.heading, 'help-search-hit-section'));
        const excerpt = node('span', '', 'help-search-hit-excerpt'); highlight(excerpt, result.snippet, query); link.append(excerpt);
        item.append(link); list.append(item);
      }
    }
  }
  function open() {
    if (dialog.open) {input.focus(); return;}
    previousFocus = document.activeElement;
    previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    dialog.showModal(); render(); input.focus();
  }
  function close() {if (dialog.open) dialog.close();}
  dialog.addEventListener('close', () => {
    clearTimeout(timer);
    document.body.style.overflow = previousOverflow;
    if (previousFocus?.isConnected) previousFocus.focus({preventScroll: true});
  });
  trigger.hidden = false;
  const shortcut = trigger.querySelector('[data-search-shortcut]');
  if (/Mac|iPhone|iPad/.test(navigator.platform)) shortcut.textContent = '⌘ K';
  trigger.addEventListener('click', open);
  dialog.querySelector('[data-search-close]').addEventListener('click', close);
  dialog.addEventListener('click', event => {if (event.target === dialog) {
    const rect = dialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) close();
  }});
  document.addEventListener('keydown', event => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {event.preventDefault(); open();}
  });
  dialog.addEventListener('keydown', event => {
    if (event.key === 'Escape') {event.preventDefault(); close(); return;}
    if (event.key === 'Tab') {
      const targets = [...dialog.querySelectorAll('button,input,select,a[href]')].filter(el => !el.hidden && !el.disabled);
      const first = targets[0], last = targets.at(-1);
      if (event.shiftKey && document.activeElement === first) {event.preventDefault(); last.focus();}
      else if (!event.shiftKey && document.activeElement === last) {event.preventDefault(); first.focus();}
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      const links = [...list.querySelectorAll('a')];
      const current = links.indexOf(document.activeElement);
      if (document.activeElement === input && event.key === 'ArrowDown') {
        render(); const first = list.querySelector('a'); if (first) {event.preventDefault(); first.focus();}
      } else if (current >= 0) {
        event.preventDefault(); const next = current + (event.key === 'ArrowDown' ? 1 : -1);
        if (next < 0) input.focus(); else links[Math.min(next, links.length - 1)].focus();
      }
    }
  });
  input.addEventListener('input', () => {clearTimeout(timer); timer = setTimeout(render, 120);});
  filter.addEventListener('change', render);
  form.addEventListener('submit', event => {event.preventDefault(); render(); list.querySelector('a')?.focus();});
  clear.addEventListener('click', () => {input.value = ''; filter.value = ''; render(); input.focus();});
  const params = new URLSearchParams(location.search);
  input.value = (params.get('q') || '').slice(0, 200);
  const category = params.get('category');
  if ([...filter.options].some(option => option.value === category)) filter.value = category;
  if (input.value || filter.value) open();
 }
 if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, {once: true});
 else init();
})();
