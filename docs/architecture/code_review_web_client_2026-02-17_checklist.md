# Code Review Checklist — Web Client — 2026-02-17

> Historical review snapshot. Checkboxes describe the February 2026 review,
> not current defects or deployment instructions. The obsolete remote SQL
> installer was removed on 2026-10-19. Use the [documentation map](../README.md)
> for active procedures.


Checklist vychází z review `web_client/src/`. Zaškrtnout po opravě.

---

## 1. KRITICKÉ

- [ ] **innerHTML XSS ve field builderech** — `field.description`, `field.title`, option labels vkládány přes `innerHTML` bez sanitizace:
  - [ ] `radio_field_builder.js` (ř. 14, 22, 85, 113)
  - [ ] `check_box_field_builder.js` (ř. 21, 29, 76, 104, 133, 144)
  - [ ] `date_field_builder.js` (ř. 30)
  - [ ] `id_document_field_builder.js` (ř. 45)
  - [ ] `ticket_field_builder.js` (ř. 207, 367)
- [ ] **innerHTML XSS v dialogech/stránkách** — uživatelská/backendová data bez escape:
  - [ ] `occasion_detail_dialog.js` (ř. 94, 100, 114) — `title`, `dateStr`, `description`
  - [ ] `blueprint_selector.js` (ř. 172) — `e.message`
  - [ ] `unit_page.js` (ř. 49) — `e.message`
  - [ ] `form_page.js` (ř. 224) — error `message`

## 2. VYSOKÁ ZÁVAŽNOST

- [ ] **SVG injection v blueprint rendereru** — `blueprint_renderer.js:114` vkládá SVG z backendu přes `innerHTML`
- [x] ~~**Auth tokeny v URL**~~ — tokeny nyní přes `sessionStorage._auth_handoff`; `window.location.replace()` místo `href`
- [ ] **Tiché spolknutí chyb** — `form_session.js:383` — `.catch(() => {})` na spot queue

## 3. STŘEDNÍ ZÁVAŽNOST

- [x] ~~**`console.log` v produkci**~~ — odstraněno 35+ výskytů včetně citlivých dat; ponechány `console.error`/`console.warn`
- [ ] **Chybějící CSP** — `index.html` nemá Content-Security-Policy
- [ ] **Memory leaks:**
  - [ ] `order_preview.js` — event listenery na `document` neodstraněny mimo `closePreview()`
  - [ ] `countdown_widget.js` — statický `timer` sdílený mezi instancemi
  - [ ] `text_field_builder.js` — input/focus/blur listenery nikdy neodstraněny
- [ ] **Race condition v `toggleSpot()`** — `form_session.js:322-386`

## 4. NIŽŠÍ ZÁVAŽNOST / BACKLOG

- [x] ~~**Hardcoded `+420`**~~ — doplněny komentáře; fallback default, organizace overridují přes config
- [ ] Chybějící SRI — Google Fonts CDN bez integrity atributů
- [ ] Duplicitní volání `_prepareScopedDef()` v `ticket_field_builder.js:89`
- [ ] Weak temporary IDs — `Date.now() + Math.random()` místo `crypto.randomUUID()`
- [ ] Accessibility — ARIA labely, focus trapping v modálech
- [ ] Session token v localStorage (standardní Supabase pattern)
- [ ] God files rozdělit (`form_session.js`, `ticket_field_builder.js`, `form_page.js`, `login_modal.js`)
- [ ] Duplikovaný kód ve `form_session.js`
