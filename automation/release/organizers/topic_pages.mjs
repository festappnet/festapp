import fs from 'node:fs';
import {escape as e, publicUrl as url} from './html.mjs';
const hall = fs.readFileSync(new URL('./topic-hall.svg',import.meta.url),'utf8');
const link = item => `<a class="topic-text-link" href="${url(item.href)}">${e(item.label)}<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12h15m-6-6 6 6-6 6"/></svg></a>`;
const bullets = values => `<ul class="topic-bullets">${values.map(value=>`<li>${e(value)}</li>`).join('')}</ul>`;
const highlight = page => {
  const index=page.highlight ? page.heading.indexOf(page.highlight) : -1;
  return index<0 ? e(page.heading) : e(page.heading.slice(0,index))+`<span class="ink">${e(page.highlight)}</span>`+e(page.heading.slice(index+page.highlight.length));
};
export function renderPricingFacts(facts = []) {
  if (!facts.length) return '';
  return `<dl class="pricing-facts">${facts.map(([label, value]) => `
    <div><dt>${e(label)}</dt><dd>${e(value)}</dd></div>`).join('')}</dl>`;
}

function hero(page, projection) {
  const productCrumb = page.overview ? '<a href="/#funkce">Funkce pro pořadatele</a>' : '';
  const shortcuts = page.workflow ? `
    <nav class="topic-quick-links" aria-label="Na této stránce">
      <a href="#ukazky">Ukázky</a><a href="#postup">Postup</a>
      ${page.id === 'payments-and-orders' ? '<a href="#cena-plateb">Cena</a>' : ''}
      <a href="#otazky">Časté otázky</a><a href="#navody">Návody</a>
    </nav>` : page.feature && projection.locale === 'cs' ? `
    <nav class="topic-quick-links" aria-label="Na této stránce">
      <a href="#${e(page.feature.editor.id)}">Editor plánku</a><a href="#${e(page.feature.buyer.id)}">Výběr místa</a>
      <a href="#usporadani">Šablony sálů</a>${page.faq ? '<a href="#otazky">Časté otázky</a>' : ''}
    </nav>` : '';
  return `<div class="wrap"><nav class="topic-crumbs" aria-label="${e(projection.ui.breadcrumbs)}"><a href="/">${e(projection.seo.siteName)}</a>${productCrumb}<span aria-current="page">${e(page.linkLabel ?? page.heading)}</span></nav></div><section class="topic-intro wrap" aria-labelledby="topic-title"><div class="topic-intro-copy"><h1 id="topic-title">${highlight(page)}</h1><p class="topic-lead">${e(page.intro)}</p><div class="actions"><a class="button primary" href="${url(projection.cta.href)}">${e(projection.cta.label)}</a><a class="topic-text-link" href="${url(projection.bookingUrl)}">${e(projection.ui.contactAction)}</a></div>${shortcuts}</div>${renderHeroArt(page)}</section>`;
}
function renderHeroArt(page) {
  if (!page.heroImage) return '';
  const mobile = page.heroMobileImage;
  const image = `<img src="${url(page.heroImage)}" width="${page.heroWidth}" height="${page.heroHeight}" alt="${e(page.heroImageAlt)}" fetchpriority="high">`;
  const media = mobile
    ? `<picture><source media="(max-width:760px)" srcset="${url(mobile.src)}" width="${mobile.width}" height="${mobile.height}">${image}</picture>`
    : image;
  const caption = mobile?.caption
    ? `<span class="topic-hero-desktop-caption">${e(page.heroCaption)}</span><span class="topic-hero-mobile-caption">${e(mobile.caption)}</span>`
    : e(page.heroCaption);
  const full = page.heroDocument ?? {href:page.heroImage,label:'Zvětšit snímek'};
  return `<figure class="topic-intro-art${page.heroPortrait ? ' topic-intro-art-portrait' : ''}">${media}<figcaption>${caption}${page.workflow ? ` <a href="${url(full.href)}" target="_blank" rel="noopener">${e(full.label)}</a>` : ''}</figcaption></figure>`;
}

export function renderFaqItems(items) {
  return `<div class="faq-items">${items.map(item=>`<details><summary>${e(item.question)}</summary><p>${e(item.answer)}</p>${item.guide ? link(item.guide) : ''}</details>`).join('')}</div>`;
}
function faq(page) {
  return `<section id="otazky" class="topic-faq wrap" aria-labelledby="topic-faq-title"><div><h2 id="topic-faq-title">${e(page.faqHeading)}</h2></div>${renderFaqItems(page.faq)}</section>`;
}
function ending({title,text,primary,primaryHref,secondary,secondaryHref}, art) {
  return `<section class="topic-ending"><div class="wrap topic-ending-inner"><div><h2>${e(title)}</h2><p>${e(text)}</p><div class="actions"><a class="button light" href="${url(primaryHref)}">${e(primary)}</a><a class="topic-text-link" href="${url(secondaryHref)}">${e(secondary)}</a></div></div><div class="topic-ending-art" aria-hidden="true">${art}</div></div></section>`;
}
function featurePage(page, projection, player, related, sections) {
  const f=page.feature;
  const example=f ? `<section class="topic-layouts wrap" id="usporadani"><div class="topic-section-intro"><h2>${e(f.introTitle)}</h2><p>${e(f.introText)}</p></div><div data-layout-examples><fieldset class="layout-choices" data-layout-choices hidden><legend class="sr-only">${e(f.layoutLegend)}</legend>${f.layouts.map((layout,index)=>`<label><input type="radio" name="layout-example" value="${index}"${index===0 ? ' checked' : ''}><span>${e(layout.label)}</span></label>`).join('')}</fieldset>${f.layouts.map((layout,index)=>`<figure class="topic-layout" data-layout-example="${index}"><div class="topic-layout-image"><img loading="lazy" src="${url(layout.image)}" width="${Number(layout.width)}" height="${Number(layout.height)}" alt="${e(layout.alt)}"></div><figcaption><h3>${e(layout.title)}</h3><p>${e(layout.text)}</p><a href="${url(layout.image)}" target="_blank" rel="noopener">${e(f.zoomLabel)}</a></figcaption></figure>`).join('')}</div></section>` : '';
  const demonstrations=f ? [f.editor,f.buyer].map((item,index)=>`<section class="topic-demonstration wrap${index===1 ? ' topic-demonstration-reverse' : ''}" id="${e(item.id)}"><div class="topic-demonstration-copy"><h2>${e(item.title)}</h2><p>${e(item.text)}</p>${item.bullets ? bullets(item.bullets) : ''}${link({href:item.helpHref,label:item.helpLabel})}</div><div class="topic-demonstration-media">${player(item.clips)}</div></section>`).join('') : '';
  const fallback=f ? '' : `<section class="topic-process wrap"><h2 class="sr-only">${e(page.stepsHeading)}</h2><ol>${page.steps.map((text,index)=>`<li><span aria-hidden="true">${String(index+1).padStart(2,'0')}</span><p>${e(text)}</p></li>`).join('')}</ol></section>${sections}${faq(page)}${related}`;
  return `<div class="topic-page topic-feature">${hero(page,projection)}${demonstrations}${example}${f && page.faq ? faq(page) : ''}${fallback}${f ? related : ""}${ending({title:f?.ending.title ?? projection.ui.closing,text:f?.ending.text ?? projection.ui.priceNote,primary:f?.ending.primary ?? projection.ui.contactAction,primaryHref:projection.bookingUrl,secondary:f?.ending.secondary ?? projection.cta.label,secondaryHref:projection.cta.href},hall)}</div>`;
}
export function renderTopicPage(page,{projection,player,related,sections}) {
  if (page.workflow) return workflowPage(page, projection, player, related);
  return featurePage(page,projection,player,related,sections);
}

function workflowPage(page, projection, player, related) {
  const workflow = page.workflow;
  const capabilities = workflow.capabilities.map(item => `
    <article><h3>${e(item.title)}</h3><p>${e(item.text)}</p>${item.guide ? link(item.guide) : ''}</article>`).join('');
  const steps = page.steps.map((text, index) => `
    <li><span aria-hidden="true">${index + 1}</span><p>${e(text)}</p></li>`).join('');
  const demos = workflow.demos.map((demo, index) => `
    <section class="topic-demonstration wrap${index % 2 ? ' topic-demonstration-reverse' : ''}"${index === 0 ? ' id="ukazky"' : ''}>
      <div class="topic-demonstration-copy">
        <h2>${e(demo.title)}</h2><p>${e(demo.text)}</p>
        ${link(demo.guide)}
      </div>
      <div class="topic-demonstration-media">${demo.image
        ? `<img class="topic-demo-still" src="${url(demo.image.src)}" width="${Number(demo.image.width)}" height="${Number(demo.image.height)}" alt="${e(demo.image.alt)}" loading="lazy" decoding="async">`
        : player(demo.clips, false, demo.portrait)}</div>
    </section>`).join('');
  const priceSummary = page.id === 'payments-and-orders' ? `
    <section class="wrap product-overview product-price-summary" id="cena-plateb" aria-labelledby="payment-price-title">
      <h2 id="payment-price-title">Z čeho se skládá cena</h2>
      ${renderPricingFacts(projection.pricingFacts)}
      <a class="topic-text-link" href="/#cena">Probrat cenu pro Vaši akci</a>
    </section>` : '';
  const guides = workflow.guides.map(guide => `<li>${link(guide)}</li>`).join('');
  return `
    <div class="topic-page topic-feature">
      ${hero(page, projection)}
      ${priceSummary}
      <section class="wrap product-overview" aria-labelledby="capabilities-title">
        <h2 id="capabilities-title">${e(workflow.capabilitiesHeading)}</h2>
        <div class="technical-grid">${capabilities}</div>
      </section>
      <section class="topic-process wrap product-process" id="postup" aria-labelledby="workflow-steps-title">
        <h2 id="workflow-steps-title">${e(page.stepsHeading)}</h2>
        <ol>${steps}</ol>
      </section>
      ${demos}
      ${faq(page)}
      <section class="wrap product-guides" id="navody" aria-labelledby="workflow-guides-title">
        <h2 id="workflow-guides-title">Návody krok za krokem</h2>
        <ul>${guides}</ul>
      </section>
      ${related}
      ${ending({
        title: projection.ui.closing,
        text: projection.ui.priceNote,
        primary: projection.cta.label,
        primaryHref: projection.cta.href,
        secondary: projection.ui.contactAction,
        secondaryHref: projection.bookingUrl,
      }, hall)}
    </div>`;
}
