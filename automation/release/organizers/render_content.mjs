const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const publicUrl = value => { const url = new URL(value, 'https://marketing.invalid'); if (!['https:','mailto:'].includes(url.protocol)) throw new Error('Unsafe landing URL'); return escape(value); };
export function renderLandingContent(content, manifest, page = {id: "home"}, pages = []) {
  const projection = content.publicProjection ?? {};
  const ui = projection.ui;
  const references = projection.references ?? [];
  const clips = new Map((manifest.clips ?? []).map(clip => [clip.id, clip]));
  function player(ids, hero = false) {
    const variants = ids.map(id => clips.get(id)).filter(Boolean);
    if (!variants.length) return '';
    if (variants.some(clip=>clip.captureStatus === "pending")) return `<div class="media-stage"><p role="status">${escape(variants[0].description)} - ${escape(ui.pending)}</p></div>`;
    const clip = variants[0];
    const data = escape(JSON.stringify(variants.map(({id,label,src,poster,mobileSrc,mobilePoster,width,height,duration,description,boundary}) => ({id,label,src,poster,mobileSrc,mobilePoster,width,height,duration,description,boundary}))));
    return `<div class="media-stage" data-demo-player data-variants="${data}" ${hero ? 'data-hero="true"' : ''}><div class="media-viewport"><video muted playsinline preload="none" ${clip.poster ? `poster="${publicUrl(clip.poster)}"` : ''} width="${Number(clip.width)}" height="${Number(clip.height)}" aria-label="${escape(clip.description)}"></video><button class="media-surface" data-playback-surface type="button" aria-label="${escape(ui.play)}: ${escape(clip.description)}" aria-pressed="false"></button></div><p class="media-fallback" hidden>${escape(ui.failed)} ${escape(clip.description)} <a data-media-download href="${clip.src ? publicUrl(clip.src) : '#'}">${escape(ui.download)}</a></p></div>`;
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
  const sections = (manifest.sections ?? []).filter(section => page.id === "home" || page.sections.includes(section.id)).map(section => `<section class="feature reveal" id="${escape(section.id)}" aria-labelledby="${escape(section.id)}-title"><div class="feature-inner wrap"><div class="feature-copy"><p class="eyebrow">${escape(section.eyebrow)}</p><h2 id="${escape(section.id)}-title">${escape(section.title)}</h2><p>${escape(section.description)}</p>${section.features?.length ? `<ul class="feature-tools">${section.features.map(feature => `<li>${escape(feature)}</li>`).join('')}</ul>` : ''}<p class="feature-detail">${escape(section.detail)}</p></div><div class="feature-media">${player(section.clips)}</div></div>${gallery(section)}</section>`).join('');
  const referenceStrip = `<div class="reference-carousel" data-reference-carousel><div class="reference-strip" id="reference-track" data-reference-track tabindex="0" role="group" aria-label="${escape(ui.referenceLabel)}">${references.map(ref => `<a class="reference-card" href="${publicUrl(ref.publicUrl)}">${ref.image ? `<div class="reference-image"><img loading="lazy" src="${publicUrl(ref.image)}" width="640" height="360" alt="${escape(ui.imagePrefix)} ${escape(ref.name)}"></div>` : ''}<div class="reference-body"><span class="reference-meta">${escape(ref.dateLabel)}${ref.statusLabel ? ` · ${escape(ref.statusLabel)}` : ''}</span><h3>${escape(ref.name)}</h3></div></a>`).join('')}</div><div class="reference-controls" data-reference-controls hidden><span class="reference-position sr-only" data-reference-position aria-live="polite"></span><div><button type="button" data-reference-previous aria-controls="reference-track" aria-label="${escape(ui.previous)}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m14 6-6 6 6 6"/></svg></button><button type="button" data-reference-next aria-controls="reference-track" aria-label="${escape(ui.next)}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m10 6 6 6-6 6"/></svg></button></div></div></div>`;

  const action = `<div class="actions"><a class="button primary" href="${publicUrl(projection.cta.href)}">${escape(projection.cta.label)}</a><a class="text-link" href="${publicUrl(projection.bookingUrl)}">${escape(ui.contactAction)}</a></div>`;
  const related = `<nav class="wrap topic-links" aria-label="${escape(ui.related)}">${pages.filter(other=>other.id !== page.id).map(other=>`<a href="${publicUrl(other.path)}">${escape(other.heading ?? ui.home)}</a>`).join('')}</nav>`;
  const footer = `<nav aria-label="${escape(ui.legalNav)}">${(projection.footerLinks ?? []).map(link=>`<a href="${publicUrl(link.href)}">${escape(link.label)}</a>`).join('')}</nav>`;
  const referencesSection = references.length ? `<section id="reference" class="references wrap" aria-labelledby="references-title"><h2 id="references-title">${escape(projection.referencesHeading)}</h2>${referenceStrip}<div class="catalog-action"><a class="button primary" href="/events">${escape(projection.catalogLabel)}</a></div></section>` : '';
  const topic = page.id === 'home' ? '' : `<section class="hero wrap topic-hero"><div class="hero-copy"><h1>${escape(page.heading)}</h1><p class="lead">${escape(page.intro)}</p>${action}<p class="small-note">${escape(projection.cta.note)}</p></div></section>${sections}<section class="steps wrap"><h2>${escape(page.stepsHeading)}</h2><ol>${page.steps.map((step,index)=>`<li><span>0${index+1}</span><p>${escape(step)}</p></li>`).join('')}</ol></section><section class="faq wrap"><h2>${escape(page.faqHeading)}</h2><div class="faq-items">${page.faq.map(item=>`<details><summary>${escape(item.question)}</summary><p>${escape(item.answer)}</p></details>`).join('')}</div></section>${related}<section class="pricing wrap"><h2>${escape(ui.closing)}</h2>${action}<p>${escape(ui.priceNote)}</p></section>`;
  return { REFERENCE_STRIP: referenceStrip, REFERENCES_SECTION: referencesSection,
    DEMO_SECTIONS: sections, HERO_MEDIA: '', TOPIC_CONTENT: topic, RELATED_LINKS: related,
    FOOTER_LINKS: footer, DEMO_BOOKING_HREF: publicUrl(projection.bookingUrl),
  };
}
