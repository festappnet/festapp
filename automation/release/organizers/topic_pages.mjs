import fs from 'node:fs';
import {escape as e, publicUrl as url} from './html.mjs';
const hall = fs.readFileSync(new URL('./topic-hall.svg',import.meta.url),'utf8');
const link = item => `<a class="topic-text-link" href="${url(item.href)}">${e(item.label)}<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12h15m-6-6 6 6-6 6"/></svg></a>`;
const bullets = values => `<ul class="topic-bullets">${values.map(value=>`<li>${e(value)}</li>`).join('')}</ul>`;
const highlight = page => {
  const index=page.highlight ? page.heading.indexOf(page.highlight) : -1;
  return index<0 ? e(page.heading) : e(page.heading.slice(0,index))+`<span class="ink">${e(page.highlight)}</span>`+e(page.heading.slice(index+page.highlight.length));
};
function hero(page, projection) {
  return `<div class="wrap"><nav class="topic-crumbs" aria-label="${e(projection.ui.breadcrumbs)}"><a href="/">${e(projection.seo.siteName)}</a><span aria-current="page">${e(page.linkLabel ?? page.heading)}</span></nav></div><section class="topic-intro wrap" aria-labelledby="topic-title"><div class="topic-intro-copy"><h1 id="topic-title">${highlight(page)}</h1><p class="topic-lead">${e(page.intro)}</p><div class="actions"><a class="button primary" href="${url(projection.cta.href)}">${e(projection.cta.label)}</a><a class="topic-text-link" href="${url(projection.bookingUrl)}">${e(projection.ui.contactAction)}</a></div></div>${page.heroImage ? `<figure class="topic-intro-art"><img src="${url(page.heroImage)}" width="${page.heroWidth}" height="${page.heroHeight}" alt="${e(page.heroImageAlt)}" fetchpriority="high"><figcaption>${e(page.heroCaption)}</figcaption></figure>` : ''}</section>`;
}
function faq(page, intro='') {
  return `<section id="otazky" class="topic-faq wrap" aria-labelledby="topic-faq-title"><div><h2 id="topic-faq-title">${e(page.faqHeading)}</h2>${intro ? `<p>${e(intro)}</p>` : ''}</div><div class="faq-items">${page.faq.map(item=>`<details><summary>${e(item.question)}</summary><p>${e(item.answer)}</p></details>`).join('')}</div></section>`;
}
function ending({title,text,primary,primaryHref,secondary,secondaryHref}, art) {
  return `<section class="topic-ending"><div class="wrap topic-ending-inner"><div><h2>${e(title)}</h2><p>${e(text)}</p><div class="actions"><a class="button light" href="${url(primaryHref)}">${e(primary)}</a><a class="topic-text-link" href="${url(secondaryHref)}">${e(secondary)}</a></div></div><div class="topic-ending-art" aria-hidden="true">${art}</div></div></section>`;
}
function featurePage(page, projection, player, related, sections) {
  const f=page.feature;
  const example=f ? `<section class="topic-layouts wrap" id="usporadani"><div class="topic-section-intro"><h2>${e(f.introTitle)}</h2><p>${e(f.introText)}</p></div><div data-layout-examples><fieldset class="layout-choices" data-layout-choices hidden><legend class="sr-only">${e(f.layoutLegend)}</legend>${f.layouts.map((layout,index)=>`<label><input type="radio" name="layout-example" value="${index}"${index===0 ? ' checked' : ''}><span>${e(layout.label)}</span></label>`).join('')}</fieldset>${f.layouts.map((layout,index)=>`<figure class="topic-layout" data-layout-example="${index}"><div class="topic-layout-image"><img loading="lazy" src="${url(layout.image)}" width="${Number(layout.width)}" height="${Number(layout.height)}" alt="${e(layout.alt)}"></div><figcaption><h3>${e(layout.title)}</h3><p>${e(layout.text)}</p><a href="${url(layout.image)}" target="_blank" rel="noopener">${e(f.zoomLabel)}</a></figcaption></figure>`).join('')}</div></section>` : '';
  const demonstrations=f ? [f.editor,f.buyer].map((item,index)=>`<section class="topic-demonstration wrap${index===1 ? ' topic-demonstration-reverse' : ''}" id="${e(item.id)}"><div class="topic-demonstration-copy"><h2>${e(item.title)}</h2><p>${e(item.text)}</p>${item.bullets ? bullets(item.bullets) : ''}${link({href:item.helpHref,label:item.helpLabel})}</div><div class="topic-demonstration-media">${player(item.clips)}</div></section>`).join('') : '';
  const fallback=f ? '' : `<section class="topic-process wrap"><h2 class="sr-only">${e(page.stepsHeading)}</h2><ol>${page.steps.map((text,index)=>`<li><span aria-hidden="true">${String(index+1).padStart(2,'0')}</span><p>${e(text)}</p></li>`).join('')}</ol></section>${sections}${faq(page)}${related}`;
  return `<div class="topic-page topic-feature">${hero(page,projection)}${demonstrations}${example}${fallback}${ending({title:f?.ending.title ?? projection.ui.closing,text:f?.ending.text ?? projection.ui.priceNote,primary:f?.ending.primary ?? projection.ui.contactAction,primaryHref:projection.bookingUrl,secondary:f?.ending.secondary ?? projection.cta.label,secondaryHref:projection.cta.href},hall)}</div>`;
}
export function renderTopicPage(page,{projection,player,related,sections}) {
  return featurePage(page,projection,player,related,sections);
}
