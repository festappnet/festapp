const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const publicUrl = value => { const url = new URL(value, 'https://vstupenky.online'); if (!['https:','http:'].includes(url.protocol)) throw new Error('Unsafe landing URL'); return escape(value); };
export function renderLandingContent(content, manifest) {
  const projection = content.publicProjection ?? {};
  const references = projection.references ?? [];
  const clips = new Map((manifest.clips ?? []).map(clip => [clip.id, clip]));
  function player(ids, hero = false) {
    const variants = ids.map(id => clips.get(id)).filter(Boolean);
    if (!variants.length) return '';
    const clip = variants[0];
    const data = escape(JSON.stringify(variants.map(({id,label,src,poster,mobileSrc,mobilePoster,width,height,duration,description,boundary}) => ({id,label,src,poster,mobileSrc,mobilePoster,width,height,duration,description,boundary}))));
    return `<div class="media-stage" data-demo-player data-variants="${data}" ${hero ? 'data-hero="true"' : ''}><div class="media-viewport"><video muted playsinline preload="none" ${clip.poster ? `poster="${publicUrl(clip.poster)}"` : ''} width="${Number(clip.width)}" height="${Number(clip.height)}" aria-label="${escape(clip.description)}"></video><button class="media-surface" data-playback-surface type="button" aria-label="Přehrát: ${escape(clip.description)}" aria-pressed="false"></button></div><p class="media-fallback" hidden>Video se nepodařilo přehrát. ${escape(clip.description)} <a data-media-download href="${clip.src ? publicUrl(clip.src) : '#'}">Otevřít video</a></p></div>`;
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
  const sections = (manifest.sections ?? []).map(section => `<section class="feature reveal" id="${escape(section.id)}" aria-labelledby="${escape(section.id)}-title"><div class="feature-inner wrap"><div class="feature-copy"><p class="eyebrow">${escape(section.eyebrow)}</p><h2 id="${escape(section.id)}-title">${escape(section.title)}</h2><p>${escape(section.description)}</p>${section.features?.length ? `<ul class="feature-tools">${section.features.map(feature => `<li>${escape(feature)}</li>`).join('')}</ul>` : ''}<p class="feature-detail">${escape(section.detail)}</p></div><div class="feature-media">${player(section.clips)}</div></div>${gallery(section)}</section>`).join('');
  return {
    REFERENCE_STRIP: `<div class="reference-carousel" data-reference-carousel><div class="reference-strip" id="reference-track" data-reference-track tabindex="0" role="group" aria-label="Ukázky plesů, posuvná galerie">${references.map(ref => `<a class="reference-card" href="${publicUrl(ref.publicUrl)}">${ref.image ? `<div class="reference-image"><img loading="lazy" src="${publicUrl(ref.image)}" width="640" height="360" alt="Úvodní obrázek: ${escape(ref.name)}"></div>` : ''}<div class="reference-body"><span class="reference-meta">${escape(ref.dateLabel || 'Zveřejněná akce')}${ref.statusLabel ? ` · ${escape(ref.statusLabel)}` : ''}</span><h3>${escape(ref.name)}</h3></div></a>`).join('')}</div><div class="reference-controls" data-reference-controls hidden><span class="reference-position sr-only" data-reference-position aria-live="polite"></span><div><button type="button" data-reference-previous aria-controls="reference-track" aria-label="Předchozí plesy"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m14 6-6 6 6 6"/></svg></button><button type="button" data-reference-next aria-controls="reference-track" aria-label="Další plesy"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m10 6 6 6-6 6"/></svg></button></div></div></div>`,
    DEMO_SECTIONS: sections,
    HERO_MEDIA: '<div class="hero-scene"><img class="hero-hall" src="/organizers-media/hero-hall.jpg" width="860" height="690" alt="Ukázkový plesový sál: kulaté i hranaté stoly, parket a pódium"><span class="hero-scene-label">Ukázka hotového sálu ze skutečného editoru</span></div>',
    DEMO_BOOKING_HREF: publicUrl(projection.bookingUrl || 'mailto:info@vstupenky.online'),
  };
}
