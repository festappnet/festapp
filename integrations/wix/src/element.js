import {DEFAULT_TITLE, HELP_URL, SERVICE_ORIGIN, TAG_NAME, formUrl} from './config.js';

const helperDocuments = new WeakSet();
function ensureHelper(document) {
  if (helperDocuments.has(document)) return;
  helperDocuments.add(document);
  if (document.defaultView.__festappEmbedV1 || [...document.scripts].some(script => script.src === `${SERVICE_ORIGIN}/embed.js`)) return;
  const script = document.createElement('script');
  script.src = `${SERVICE_ORIGIN}/embed.js`;
  script.async = true;
  document.head.append(script);
}

// Light DOM is intentional: canonical /embed.js discovers declared iframes
// in document, owns resize/scroll and isolates instances itself.
export function registerTicketElement(win, getViewMode) {
  if (win.customElements.get(TAG_NAME)) return;
  class TicketElement extends win.HTMLElement {
    static observedAttributes = ['form-url', 'form-title', 'inherit-style'];
    connectedCallback() {
      const generation = this.generation = (this.generation || 0) + 1;
      this.mode = null;
      this.render();
      Promise.resolve().then(getViewMode).then(mode => {
        if (!this.isConnected || generation !== this.generation) return;
        this.mode = mode;
        this.render();
      }).catch(() => {
        if (!this.isConnected || generation !== this.generation) return;
        this.mode = 'Unavailable';
        this.render();
      });
    }
    disconnectedCallback() {
      this.generation = (this.generation || 0) + 1;
      this.replaceChildren();
      this.frame = null;
    }
    attributeChangedCallback() { if (this.isConnected) this.render(); }
    placeholder(message) {
      this.frame = null;
      const section = this.ownerDocument.createElement('section');
      section.className = 'vstupenky-wix-placeholder';
      section.style.cssText = 'box-sizing:border-box;padding:24px;border:1px solid #c7cdd1;border-radius:4px;background:#fff;color:#162d3d;font:14px/1.5 Arial,sans-serif';
      const heading = this.ownerDocument.createElement('strong');
      heading.textContent = 'vstupenky.online';
      heading.style.fontSize = '18px';
      const detail = this.ownerDocument.createElement('p');
      detail.textContent = message;
      const help = this.ownerDocument.createElement('a');
      help.href = HELP_URL; help.target = '_blank'; help.rel = 'noopener noreferrer';
      help.textContent = 'Návod na vložení formuláře';
      help.style.color = '#0754bf';
      section.append(heading, detail, help);
      const url = formUrl(this.getAttribute('form-url'));
      if (this.mode === 'Unavailable' && url) {
        const paragraph = this.ownerDocument.createElement('p');
        const fallback = this.ownerDocument.createElement('a');
        fallback.href = url; fallback.target = '_blank'; fallback.rel = 'noopener noreferrer';
        fallback.textContent = 'Otevřít formulář v novém okně';
        paragraph.append(fallback); section.append(paragraph);
      }
      this.replaceChildren(section);
    }
    render() {
      this.style.display = 'block';
      const url = formUrl(this.getAttribute('form-url'));
      if (this.mode !== 'Site') {
        this.placeholder(this.mode === 'Unavailable'
          ? 'Formulář se nepodařilo načíst. Obnovte stránku nebo jej otevřete samostatně z veřejného odkazu.'
          : 'Prodejní formulář se zobrazí na zveřejněném webu. Odkaz nastavte v nastavení prvku.');
        return;
      }
      if (!url) {
        this.placeholder('Nejprve nastavte veřejný odkaz prodejního formuláře.');
        return;
      }
      if (!this.frame) {
        const host = this.ownerDocument.createElement('div');
        host.className = 'vstupenky-wix'; host.dataset.festappEmbedHost = '';
        const frame = this.ownerDocument.createElement('iframe');
        frame.dataset.festappEmbed = '';
        frame.loading = 'lazy'; frame.width = '100%'; frame.height = '800';
        frame.style.cssText = 'display:block;width:100%;max-width:100%;border:0';
        const paragraph = this.ownerDocument.createElement('p');
        paragraph.style.cssText = 'margin:12px 0 0;text-align:center;font-size:14px;line-height:1.5';
        const link = this.ownerDocument.createElement('a');
        link.target = '_blank'; link.rel = 'noopener noreferrer';
        link.style.cssText = 'display:inline-flex;align-items:center;min-height:44px;padding:0 8px;color:inherit;text-underline-offset:3px';
        link.textContent = 'Otevřít formulář v novém okně';
        paragraph.append(link); host.append(frame, paragraph);
        this.replaceChildren(host);
        this.frame = frame; this.fallback = link;
      }
      const source = `${url}?embed=1`;
      if (this.frame.getAttribute('src') !== source) this.frame.src = source;
      this.frame.title = this.getAttribute('form-title')?.trim().slice(0, 200) || DEFAULT_TITLE;
      this.fallback.href = url;
      if (this.getAttribute('inherit-style') === 'false') delete this.frame.dataset.festappStyle;
      else this.frame.dataset.festappStyle = 'inherit';
      ensureHelper(this.ownerDocument);
    }
  }
  win.customElements.define(TAG_NAME, TicketElement);
}
