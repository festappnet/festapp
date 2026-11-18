import {readFileSync} from 'node:fs';
import {escape,publicUrl} from './html.mjs';
import {renderPressPage} from './press.mjs';
import {renderFaqItems, renderPricingFacts, renderTopicPage} from './topic_pages.mjs';
import {renderTopicLinks} from './site_shell.mjs';

export function renderLandingContent(content, manifest, page = {id: "home"}, pages = []) {
  const projection = content.publicProjection ?? {};
  const ui = projection.ui;
  const references = projection.references ?? [];
  const clips = new Map((manifest.clips ?? []).map(clip => [clip.id, clip]));
  function player(ids, hero = false, compact = false) {
    const variants = ids.map(id => clips.get(id)).filter(Boolean).map(clip => compact ? {...clip,src:clip.mobileSrc ?? clip.src,poster:clip.mobilePoster ?? clip.poster,width:clip.mobileWidth ?? clip.width,height:clip.mobileHeight ?? clip.height} : clip);
    if (!variants.length) return '';
    if (variants.some(clip=>clip.captureStatus === "pending")) return `<div class="media-stage"><p role="status">${escape(variants[0].description)} - ${escape(ui.pending)}</p></div>`;
    const clip = variants[0];
    const data = escape(JSON.stringify(variants.map(({id,label,src,poster,mobileSrc,mobilePoster,width,height,mobileWidth,mobileHeight,duration,description,boundary}) => ({id,label,src,poster,mobileSrc,mobilePoster,width,height,mobileWidth,mobileHeight,duration,description,boundary}))));
    return `<div class="media-stage" data-demo-player data-variants="${data}"${clip.height > clip.width ? ' data-portrait' : ''} ${hero ? 'data-hero="true"' : ''}><div class="media-viewport"><video muted playsinline preload="none" ${clip.poster ? `poster="${publicUrl(clip.poster)}"` : ''} width="${Number(clip.width)}" height="${Number(clip.height)}" aria-label="${escape(clip.description)}"></video><button class="media-surface" data-playback-surface type="button" aria-label="${escape(ui.play)}: ${escape(clip.description)}" aria-pressed="false"><span class="media-play-action"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 5 11 7-11 7Z"/></svg><span data-playback-label>${escape(ui.play)}</span></span></button></div><p class="media-fallback" hidden>${escape(ui.failed)} ${escape(clip.description)} <a data-media-download href="${clip.src ? publicUrl(clip.src) : '#'}">${escape(ui.download)}</a></p></div>`;
  }
  function gallery(section) {
    if (!section.showcase?.items?.length) return '';
    const card = item => `<figure class="output-card" style="--ticket-ratio:${Number(item.width || 960) / Number(item.height || 720)}"><img loading="lazy" src="${publicUrl(item.image)}" width="${Number(item.width || 960)}" height="${Number(item.height || 720)}" alt="${escape(item.alt)}"><figcaption><strong>${escape(item.title)}</strong><span>${escape(item.description)}</span></figcaption></figure>`;
    let items = section.showcase.items.map(card).join('');
    if (section.id === 'vstupenka' && section.showcase.items.length === 8) {
      const order = [[0,2,5,7],[1,3,4,6]];
      items = order.map(row => `<div class="ticket-row">${row.map(index => card(section.showcase.items[index])).join('')}</div>`).join('');
    }
    return `<div class="output-gallery wrap"><div class="output-heading"><h3>${escape(section.showcase.title)}</h3><p>${escape(section.showcase.description)}</p></div><div class="output-grid">${items}</div></div>`;
  }
  const sectionLinks = section => section.links?.length ? `<div class="product-links">${section.links.map(item=>`<a class="topic-text-link" href="${publicUrl(item.href)}">${escape(item.label)}<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12h15m-6-6 6 6-6 6"/></svg></a>`).join('')}</div>` : '';
  const sections = (manifest.sections ?? []).filter(section => page.id === "home" || (page.sections ?? []).includes(section.id)).map(section => {
    const copy=`<div class="feature-copy">${projection.locale === 'cs' ? '' : `<p class="eyebrow">${escape(section.eyebrow)}</p>`}<h2 id="${escape(section.id)}-title">${escape(section.title)}</h2><p>${escape(section.description)}</p>${section.features?.length ? `<ul class="feature-tools">${section.features.map(feature=>`<li>${escape(feature)}</li>`).join('')}</ul>` : ''}${section.detail ? `<p class="feature-detail">${escape(section.detail)}</p>` : ''}${sectionLinks(section)}</div>`;
    if (section.composition) {
      const companion=section.companion;
      const secondary=companion ? `<figure class="product-ticket"><img loading="lazy" src="${publicUrl(companion.image)}" width="${companion.width}" height="${companion.height}" alt="${escape(companion.alt)}"><figcaption>${escape(companion.caption)}</figcaption></figure>` : `<figure class="product-scanner">${player(section.secondaryClips,false,true)}<figcaption>${escape(section.secondaryLabel)}</figcaption></figure>`;
      return `<section class="feature product-pair product-pair-${escape(section.composition)}" id="${escape(section.id)}" aria-labelledby="${escape(section.id)}-title"><div class="wrap">${copy}<div class="product-pair-media"><figure class="product-primary">${player(section.clips)}${section.primaryLabel ? `<figcaption>${escape(section.primaryLabel)}</figcaption>` : ''}</figure>${secondary}</div></div></section>`;
    }
    return `<section class="feature reveal" id="${escape(section.id)}" aria-labelledby="${escape(section.id)}-title"><div class="feature-inner wrap">${copy}<div class="feature-media">${player(section.clips)}</div></div>${gallery(section)}</section>`;
  }).join('');
  const referenceStrip = `<div class="reference-carousel" data-reference-carousel><div class="reference-strip" id="reference-track" data-reference-track tabindex="0" role="group" aria-label="${escape(ui.referenceLabel)}">${references.map(ref => `<a class="reference-card" href="${publicUrl(ref.publicUrl)}">${ref.image ? `<div class="reference-image"><img loading="lazy" src="${publicUrl(ref.image)}" width="640" height="360" alt="${escape(ui.imagePrefix)} ${escape(ref.name)}"></div>` : ''}<div class="reference-body"><span class="reference-meta">${escape(ref.dateLabel)}${ref.statusLabel ? ` · ${escape(ref.statusLabel)}` : ''}</span><h3>${escape(ref.name)}</h3></div></a>`).join('')}</div><div class="reference-controls" data-reference-controls hidden><span class="reference-position sr-only" data-reference-position aria-live="polite"></span><div><button type="button" data-reference-previous aria-controls="reference-track" aria-label="${escape(ui.previous)}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m14 6-6 6 6 6"/></svg></button><button type="button" data-reference-next aria-controls="reference-track" aria-label="${escape(ui.next)}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m10 6 6 6-6 6"/></svg></button></div></div></div>`;

  const action = `<div class="actions"><a class="button primary" href="${publicUrl(projection.cta.href)}">${escape(projection.cta.label)}</a><a class="text-link" href="${publicUrl(projection.bookingUrl)}">${escape(ui.contactAction)}</a></div>`;
  const related = `<nav class="wrap topic-links" aria-label="${escape(ui.related)}">${pages.filter(other=>other.id !== page.id).map(other=>`<a href="${publicUrl(other.path)}">${escape(other.linkLabel ?? other.heading ?? ui.home)}</a>`).join('')}</nav>`;
  const footer = `<nav aria-label="${escape(ui.legalNav)}">${(projection.footerLinks ?? []).map(link=>`<a href="${publicUrl(link.href)}">${escape(link.label)}</a>`).join('')}</nav>`;
  const referencesSection = references.length ? `<section id="reference" class="references wrap" aria-labelledby="references-title"><h2 id="references-title">${escape(projection.referencesHeading)}</h2>${referenceStrip}<div class="catalog-action"><a class="button primary" href="/events">${escape(projection.catalogLabel)}</a></div></section>` : '';
  const topic = page.id === 'home' ? '' : page.id === 'press' ? renderPressPage(page, projection) : renderTopicPage(page,{projection,player,related,sections});
  const isCzechHome = projection.locale === 'cs' && page.id === 'home';
  return { TOPIC_LINKS: renderTopicLinks(pages), REFERENCE_STRIP: referenceStrip, REFERENCES_SECTION: referencesSection,
    GETTING_STARTED: isCzechHome ? renderGettingStarted(projection) : '',
    PRICING_FACTS: isCzechHome ? renderPricingFacts(projection.pricingFacts) : '',
    PRODUCT_PROOF: isCzechHome ? renderProductProof(projection.productProof, player) : '',
    PRODUCT_OVERVIEW: isCzechHome ? renderProductOverview(pages) : '',
    REFERENCE_CASE: isCzechHome ? renderReferenceCase(projection.referenceCase) : '',
    HERO_SECONDARY_HREF: publicUrl(projection.bookingUrl),
    HERO_SECONDARY_LABEL: escape(projection.templateTexts.PAGE_EXPLORE_THE_FEATURES),
    HERO_QUICK_LINKS: isCzechHome ? '<nav class="hero-demo-links" aria-label="Pro pořadatele"><a href="#ukazka-nakupu">Vyzkoušet výběr míst</a><a href="#funkce">Funkce</a><a href="#cena">Cena</a></nav>' : '',
    ORGANIZER_CONTACT: isCzechHome ? renderOrganizerContact() : '',
    HOME_FAQ: isCzechHome ? `<section class="faq wrap reveal" id="faq" aria-labelledby="faq-title"><h2 id="faq-title">Co řeší pořadatelé před prodejem</h2>${renderFaqItems(projection.homeFaq)}</section>` : '',
    DEMO_SECTIONS: sections, HERO_MEDIA: '', TOPIC_CONTENT: topic, RELATED_LINKS: related,
    FOOTER_LINKS: footer, DEMO_BOOKING_HREF: publicUrl(projection.bookingUrl),
  };
}

function renderReferenceCase(example) {
  if (!example) return '';
  return `<section id="priklad-salu" class="wrap reference-case" aria-labelledby="reference-case-title">
    <div><h2 id="reference-case-title">${escape(example.title)}</h2><p>${escape(example.text)}</p>
      <a class="topic-text-link" href="${publicUrl(example.href)}">${escape(example.label)}</a></div>
    <img loading="lazy" src="${publicUrl(example.image)}" width="${example.width}" height="${example.height}" alt="${escape(example.alt)}">
  </section>`;
}

function renderOrganizerContact() {
  return `
    <section class="organizer-contact wrap" id="kontakt" aria-labelledby="contact-title">
      <h2 id="contact-title">Napište nám</h2>
      <form data-organizer-contact method="post" action="https://api.festapp.net/functions/v1/organizer-contact" hidden>
        <label for="contact-email">Váš e-mail</label>
        <input id="contact-email" name="email" type="email" autocomplete="email" maxlength="254" required>
        <label for="contact-message">Vaše zpráva</label>
        <textarea id="contact-message" name="message" rows="4" maxlength="1000" required></textarea>
        <button class="button primary" type="submit">Odeslat zprávu</button>
        <p data-contact-status role="status" aria-live="polite"></p>
      </form>
      <noscript><p>Pro odeslání formuláře zapněte JavaScript.</p></noscript>
    </section>`;
}

function renderProductProof(cards = [], player) {
  if (!cards.length) return '';
  return `
    <section id="ukazka-nakupu" class="wrap product-proof" aria-labelledby="product-proof-title">
      <h2 id="product-proof-title">Vyzkoušejte si výběr míst</h2>
      <div class="seat-demo" data-seat-demo>
        <div class="seat-demo-copy">
          <h3>Ples pod hvězdami</h3>
          <p>Zkuste si vybrat místa u jednoho stolu. V ukázce se místa nerezervují a nic se neplatí.</p>
          <button class="button primary" type="button" data-seat-start hidden>Otevřít plánek</button>
          <div class="seat-demo-controls" data-seat-controls role="group" aria-label="Měřítko plánku" hidden>
            <button type="button" data-seat-zoom-in aria-label="Přiblížit plánek">+</button>
            <button type="button" data-seat-zoom-out aria-label="Oddálit plánek">−</button>
            <button type="button" data-seat-fit>Celý sál</button>
          </div>
          <div class="seat-demo-summary" data-seat-summary hidden>
            <p class="seat-demo-legend"><span>Volná</span><span>Obsazená</span></p>
            <dl aria-live="polite" aria-atomic="true">
              <div><dt>Vybraná místa</dt><dd data-seat-labels>Zatím žádná</dd></div>
              <div><dt>Ukázková cena</dt><dd data-seat-total>0 Kč</dd></div>
            </dl>
            <button type="button" class="topic-text-link" data-seat-clear disabled>Vymazat výběr</button>
          </div>
          <p data-seat-load-status role="status"></p>
        </div>
        <div class="seat-demo-stage">
          <img data-seat-poster src="/organizers-media/scout-reference-plan.webp" width="688" height="688" alt="Plánek stolů kolem tanečního parketu" loading="lazy">
          <div class="seat-demo-map" data-seat-map hidden></div>
        </div>
      </div>
      <details class="product-proof-details">
      <summary>Jak vypadá výběr na telefonu a přehled platby</summary>
      <div class="product-proof-grid">${cards.map(card => {
        const media = player([card.clip], false, card.compact);
        const action = card.href ? `<a class="topic-text-link" href="${publicUrl(card.href)}">${escape(card.label)}</a>` : '';
        return `
          <figure>
            <figcaption>
              <h3>${escape(card.role)}</h3><p>${escape(card.caption)}</p>
              ${action}
            </figcaption>
            <div class="product-proof-media">${media}</div>
          </figure>`;
      }).join('')}</div>
      </details>
    </section>`;
}

function renderProductOverview(pages) {
  const products = pages.filter(page => page.overview);
  if (!products.length) return '';
  return `
    <section class="wrap product-overview" id="funkce" aria-labelledby="product-overview-title">
      <h2 id="product-overview-title">Funkce pro pořadatele</h2>
      <ul class="product-directory">${products.map(({overview, path, linkLabel}) => `
        <li><a href="${publicUrl(path)}">
          <span class="product-directory-title">${escape(linkLabel)}</span>
          <span class="product-directory-detail">${overview.points.map(escape).join(' · ')}</span>
        </a></li>`).join('')}</ul>
    </section>`;
}

function renderGettingStarted(projection) {
  const guide = projection.gettingStarted;
  if (!guide) return '';
  return `
    <section class="wrap getting-started" id="prvni-akce" aria-labelledby="getting-started-title">
      <h2 id="getting-started-title">Jak založit první akci</h2>
      <div class="getting-started-body">
        <ol>${guide.steps.map(step => `
          <li><h3>${escape(step.title)}</h3><p>${escape(step.text)}</p></li>`).join('')}</ol>
        <figure>
          <img loading="lazy" src="${publicUrl(guide.image)}" width="${Number(guide.imageWidth)}" height="${Number(guide.imageHeight)}" alt="${escape(guide.imageAlt)}">
          <figcaption>Výběr šablony vstupenky při přípravě akce</figcaption>
        </figure>
      </div>
      <div class="actions">
        <a class="topic-text-link" href="/napoveda/zaciname/">Prohlédnout celý postup</a>
      </div>
    </section>`;
}
