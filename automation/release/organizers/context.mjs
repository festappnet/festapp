import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolvePages } from './page_definitions.mjs';
const directory = path.dirname(fileURLToPath(import.meta.url));
export function readConfig(file) {
  return Object.fromEntries([...fs.readFileSync(file,'utf8').matchAll(/^([A-Z_0-9]+)=(.*)$/gm)].map(([,key,value]) => [key,value.trim().replace(/^(['"])(.*)\1$/, '$2')]));
}
export function resolveContext(config, { profilesDir = directory, preview = false } = {}) {
  const url = new URL(config.WEB_LINK);
  if (url.protocol !== 'https:' || url.username || url.password || url.port || url.pathname !== '/' || url.search || url.hash || (config.DOMAIN && config.DOMAIN !== url.hostname)) throw new Error('DOMAIN/WEB_LINK must agree on a bare HTTPS origin');
  const flag = config.WEB_ORGANIZER_LANDING_ENABLED ?? 'false';
  if (!['true','false'].includes(flag)) throw new Error('Invalid marketing capability');
  const context = { enabled: flag === 'true', origin: url.origin, pages: [] };
  if (!context.enabled) return context;
  const profiles = JSON.parse(fs.readFileSync(path.join(profilesDir,'profiles.json'),'utf8'));
  const profile = profiles[config.WEB_ORGANIZER_CONTENT_PROFILE];
  const locale = config.WEB_SUPPORTED_LANGUAGES?.split(',')[0]?.trim();
  if (!profile || profile.locale !== locale) throw new Error('Missing marketing profile/locale; no fallback');
  const content = JSON.parse(fs.readFileSync(path.join(profilesDir,profile.content),'utf8'));
  const projection = content.publicProjection;
  if (projection?.page) projection.templateTexts = projection.page;
  if (!projection || projection.locale !== locale) throw new Error('Invalid public projection locale');
  for (const key of ['languageTag','ogLocale','contact','serviceName','serviceType','referencesHeading','catalogLabel']) if (!projection[key]?.trim()) throw new Error(`Marketing requires ${key}`);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(projection.contact)) throw new Error('Invalid marketing contact');
  for (const key of ['title','description','image','imageAlt','catalogTitle','catalogDescription']) if (!projection.seo?.[key]?.trim()) throw new Error(`Marketing SEO requires ${key}`);
  if (!projection.provider?.name || !projection.provider?.identifier || !projection.provider?.identifierLabel || !projection.cta?.label || !projection.cta?.note || projection.cta.href !== '/login') throw new Error('Missing provider/CTA');
  for (const key of ['play','pause','retry','replay','failed','download','referenceLabel','previous','next','position','total','imagePrefix','catalogNav','organizers','related','home','contactAction','legalNav','closing','priceNote']) if (!projection.ui?.[key]?.trim()) throw new Error(`Marketing UI requires ${key}`);
  for (const [key, expected] of [['PRIVACY_URL','/privacy/'],['TERMS_URL','/terms/'],['SUPPORT_URL','/support/']]) {
    if (config[key] !== context.origin + expected) throw new Error(`Invalid ${key}`);
  }
  if (!config.APP_NAME?.trim() || (projection.seo.siteName && projection.seo.siteName !== config.APP_NAME)) throw new Error('Marketing brand must agree with config');
  projection.seo.siteName = config.APP_NAME;
  const clips = JSON.parse(fs.readFileSync(path.join(profilesDir,profile.clips),'utf8'));
  const pages = resolvePages(projection.pages.map(page=>page.id === 'home' ? {...page,title:projection.seo.title,description:projection.seo.description} : page), context.origin);
  const safeLink = value => {
    const destination = new URL(value, context.origin);
    if (!['https:','mailto:'].includes(destination.protocol) || destination.username || destination.password) throw new Error('Unsafe marketing link');
  };
  if (!projection.bookingUrl) throw new Error('Missing booking contact');
  safeLink(projection.bookingUrl);
  for (const link of projection.footerLinks ?? []) { if (!link.label) throw new Error('Link requires label'); safeLink(link.href); }
  for (const ref of projection.references ?? []) {
    if (!ref.name || !ref.dateLabel || !/^\d{4}-\d{2}-\d{2}$/.test(ref.date ?? '')) throw new Error('Reference requires date');
    safeLink(ref.publicUrl);
  }
  const usedClips = new Set([clips.hero, ...(clips.sections ?? []).flatMap(section=>section.clips ?? [])].filter(Boolean));
  const clipIds = new Set();
  for (const clip of clips.clips ?? []) {
    if (clip.captureStatus === "pending" && usedClips.has(clip.id) && !preview) throw new Error("English product recordings are incomplete");
    if (clipIds.has(clip.id) || !clip.description || !clip.label || !clip.src || !clip.poster) throw new Error('Invalid/duplicate clip');
    clipIds.add(clip.id);
  }
  for (const section of clips.sections ?? []) for (const id of section.clips ?? []) if (!clipIds.has(id)) throw new Error(`Missing required clip ${id}`);
  for (const page of pages) for (const id of page.sections ?? []) if (!(clips.sections ?? []).some(section => section.id === id)) throw new Error(`Missing required section ${id}`);
  return { ...context, locale, profileId: config.WEB_ORGANIZER_CONTENT_PROFILE, pages, projection, clips };
}
export function marketingMedia(context) {
  if (!context.enabled) return [];
  const {projection, clips} = context;
  const usedClips = new Set([clips.hero, ...(clips.sections ?? []).flatMap(section=>section.clips ?? [])].filter(Boolean));
  return [...new Set([projection.seo.image, ...(projection.references ?? []).map(ref=>ref.image),
    ...(clips.clips ?? []).filter(clip=>usedClips.has(clip.id)).flatMap(clip=>[clip.src,clip.poster,clip.mobileSrc,clip.mobilePoster]),
    ...(clips.sections ?? []).flatMap(section=>(section.showcase?.items ?? []).map(item=>item.image))].filter(Boolean))];
}
export function publicManifest(context) {
  return { schemaVersion: 1, enabled: context.enabled, origin: context.origin, locale: context.locale ?? null,
    pages: context.pages.map(({id,path,asset,canonical,title,heading}) => ({id,path,asset,canonical,title,heading:heading ?? null})),
    sitemapPaths: context.enabled ? [...context.pages.map(page=>page.path),'/events'] : ['/'] };
}
if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const index = process.argv.indexOf('--config');
  process.stdout.write(JSON.stringify(publicManifest(resolveContext(readConfig(index < 0 ? 'automation/project.conf' : process.argv[index+1])))));
}
