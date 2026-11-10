import {escape as e} from './html.mjs';

export const pressAssetBase = '/organizers-media/press-kit/';
// Only approved static artwork. Concepts, loading animations and source fonts
// are deliberately outside the public download set.
export const pressLogos = [
  {stem:'header', label:'Vodorovné logo', png:true},
  {stem:'transparent', label:'Celé logo bez pozadí', png:false},
  {stem:'square', label:'Čtvercové logo', png:true},
  {stem:'symbol', label:'Samostatný symbol', png:false},
  {stem:'wordmark', label:'Samostatný název', png:true},
  {stem:'icon', label:'Ikona na čtvercovém pozadí', png:true},
];
export const logoFilename = (logo, dark = false, format = 'svg') => `vstupenky-online-${logo.stem}${dark ? '-dark' : ''}.${format}`;
export function renderPressPage(page, projection) {
  const p = page.press;
  const downloads = pressLogos.map(logo => `<article class="press-logo"><h3>${e(logo.label)}</h3><div class="press-logo-variants">${[false,true].map(dark => `<div><div class="press-logo-preview${dark ? ' press-logo-preview-dark' : ''}"><img src="${pressAssetBase}${logoFilename(logo,dark)}" alt="${e(logo.label)} pro ${dark ? 'tmavé' : 'světlé'} pozadí" width="320" height="180" loading="lazy"></div><p>Pro ${dark ? 'tmavé' : 'světlé'} pozadí</p><div class="press-format-links">${['svg',...(logo.png ? ['png'] : [])].map(format => `<a href="${pressAssetBase}${logoFilename(logo,dark,format)}" download aria-label="Stáhnout ${e(logo.label.toLowerCase())} pro ${dark ? 'tmavé' : 'světlé'} pozadí (${format.toUpperCase()})">${format.toUpperCase()} <span class="sr-only">ke stažení</span></a>`).join('')}</div></div>`).join('')}</div></article>`).join('');
  return `<div class="press-page wrap"><nav class="topic-crumbs" aria-label="${e(projection.ui.breadcrumbs)}"><a href="/">${e(projection.seo.siteName)}</a><span aria-current="page">${e(page.heading)}</span></nav>
<header class="press-intro"><h1>${e(page.heading)}</h1><p class="press-lead">${e(page.intro)}</p><div class="actions"><a class="button primary" href="${pressAssetBase}vstupenky-online-loga.zip" download>Stáhnout balíček log (ZIP)</a><a class="topic-text-link" href="#kontakt-pro-media">Kontakt</a></div></header>
<section class="press-section" aria-labelledby="press-about"><h2 id="press-about">O projektu</h2><div class="press-copy"><p>${e(p.summary)}</p><a class="topic-text-link" href="${pressAssetBase}o-projektu.txt" download>Stáhnout představení projektu (TXT)</a></div></section>
<section class="press-section" aria-labelledby="press-features"><h2 id="press-features">Co vstupenky.online umí</h2><dl class="press-features">${p.features.map(item=>`<div><dt>${e(item.title)}</dt><dd>${e(item.text)}</dd></div>`).join('')}</dl></section>
<section class="press-section press-downloads" aria-labelledby="press-logos"><div class="press-section-heading"><h2 id="press-logos">Loga ke stažení</h2><p>SVG pro web i tisk, PNG pro běžné použití. ${e(p.usage.join(" "))}</p></div><div class="press-logos">${downloads}</div></section>
<section class="press-section press-contact" id="kontakt-pro-media" aria-labelledby="press-contact"><h2 id="press-contact">Kontakt</h2><div class="press-copy"><p><strong>${e(projection.provider.name)}</strong><br><a href="mailto:${e(projection.contact)}">${e(projection.contact)}</a></p></div></section></div>`;
}
