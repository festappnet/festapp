// Static design review using the actual catalog, draft product adapter and PDF renderer.
// deno run --frozen --lock=supabase/functions/deno.lock --allow-read --allow-write --allow-env --allow-run=sips automation/tickets/preview-template-catalog.ts /absolute/output
import {Buffer} from 'node:buffer';
import {ticketGallery,galleryBackgrounds} from '../../supabase/functions/_shared/ticketGallery.ts';
import {themeTicketTemplate,themedTicketBackground,ticketThemePalettes,ticketThemeFonts} from '../../supabase/functions/_shared/ticketTheme.ts';
import {loadLayoutResources,generateTicketPdf} from '../../supabase/functions/_shared/ticketGeneration.ts';
import {sampleData} from '../../supabase/functions/_shared/ticketRenderData.ts';
import {draftPreviewProducts} from '../../supabase/functions/preview-ticket-layout/draftProducts.ts';
const out=Deno.args[0];if(!out?.startsWith('/'))throw Error('Absolute output directory required');
await Deno.mkdir(out,{recursive:true});
const assets=new URL('../../supabase/functions/_shared/ticket-assets/',import.meta.url);
const manifest=JSON.parse(await Deno.readTextFile(new URL('preview-manifest.json',assets)));
const labels=JSON.parse(await Deno.readTextFile(new URL('../../assets/translations/cs.json',import.meta.url))).TicketLayout;
const styleNames:Record<string,string>={clean:'Čistý',gala:'Slavnostní',energy:'Energický',nature:'Přírodní',soft:'Jemný',contrast:'Kontrastní'};
const draft={title:'Slavnostní večer',start:'2026-11-07T18:00:00Z',placeName:'Kulturní dům',formDraft:{fields:[{title:'Vstupné',product_type_data:{id:-101,type:'spot',products:[{id:-201,title:'Základní vstupné',price:350,currency_code:'CZK'}]}}]}};
await Deno.writeTextFile(`${out}/concept.json`,JSON.stringify(draft,null,2));
const products=draftPreviewProducts(draft);
const occasion={id:0,title:draft.title,start_time:draft.start,data:{place_name:draft.placeName}};
let scenes:any[]=[];
if(Deno.args.includes('--html-only'))scenes=JSON.parse(await Deno.readTextFile(`${out}/contexts.json`));
else {
for(const [style,palette] of Object.entries(ticketThemePalettes)) {
 const fid=ticketThemeFonts[style], font=manifest.fonts[fid];
 await Deno.writeFile(`${out}/font-${style}.ttf`,await Deno.readFile(new URL(font.file,assets)));
 for(const [key,raw] of Object.entries(ticketGallery())) {
  const template=themeTicketTemplate(raw,palette[0],palette[1],fid,key);
  const background=themedTicketBackground(key,palette[0],palette[1],galleryBackgrounds[key]??null);
  const resources=await loadLayoutResources(occasion,{ticket_type:'wide',layout:{schemaVersion:3,templates:{wide:template}},background});
  const scenarios=Object.fromEntries(['normal','long','missing'].map(s=>[s,sampleData(s,occasion,products)]));
  const data=sampleData('normal',occasion,products,template);
  // Keep raw scenario bindings available to the client resource adapter too.
  scenarios.normal.price=data.price;
  const name=`${style}-${key}`;
  for(const kind of ['pdf','background']) {
   const t=structuredClone(template);
   if(kind==='background')t.elements.find(e=>e.binding==='price')!.visible=false;
   const result=await generateTicketPdf(data,resources,t,'wide');
   await Deno.writeFile(`${out}/${name}-${kind}.pdf`,result.bytes);
   const raster=await new Deno.Command('sips',{args:['-s','format','png',`${out}/${name}-${kind}.pdf`,'--out',`${out}/${name}-${kind}.png`],stdout:'null',stderr:'piped'}).output();
   if(!raster.success)throw Error(new TextDecoder().decode(raster.stderr));
  }
  scenes.push({name,key,style,label:labels[`style_${key}`]??key,named:template.elements.some(e=>e.binding==='orderName'&&e.visible),
   source:raw,reply:{resourceProtocol:3,template,preset:template,fontIds:[fid],scenarios,catalog:[...products.types.values()],backgroundUrl:background,logoUrl:null}});
 }
 console.log(`${styleNames[style]}: ${Object.keys(ticketGallery()).length} catalog designs rendered`);
}
await Deno.writeTextFile(`${out}/contexts.json`,JSON.stringify(scenes));
}
const rows=['concert_stub','ball_silk','festival_poster','club_panorama','theatre_program','gallery_square','gala_invitation','boarding_pass','cinema_strip','sports_arena','festival_badge','workshop_card','silk_light','silk_dark','portrait'];
const esc=(s:string)=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const fontCss=(await Promise.all(Object.keys(styleNames).map(async s=>`@font-face{font-family:ticket-${s};src:url(data:font/ttf;base64,${Buffer.from(await Deno.readFile(`${out}/font-${s}.ttf`)).toString('base64')})}`))).join('');
const cards=rows.map(key=>{const first=scenes.find(s=>s.key===key);return `<section class="row" data-named="${first.named}" data-silk="${key.includes('silk')}" data-order="${rows.indexOf(key)}" data-name-size="${Math.max(0,...first.reply.template.elements.filter((e:any)=>e.binding==='orderName').map((e:any)=>e.style.fontSize))}"><h2>${esc(first.label)}${first.named?'<small>Se jménem</small>':''}</h2>${scenes.filter(s=>s.key===key).map(s=>`<article data-style="${s.style}"><div class="sample"><canvas data-name="${s.name}" tabindex="0" role="button" aria-label="Zvětšit: ${esc(s.label+' / '+styleNames[s.style])}"></canvas></div><h3>${esc(styleNames[s.style])}</h3></article>`).join('')}</section>`}).join('');
await Deno.writeTextFile(`${out}/index.html`,`<!doctype html><html lang="cs"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Celá kolekce vstupenek</title><style>${fontCss}*{box-sizing:border-box}body{margin:0;background:#f5f4ee;color:#202925;font:16px/1.5 system-ui}main{max-width:1800px;margin:auto;padding:24px}h1{font-size:28px;margin:0 0 8px}p{max-width:1000px;margin:8px 0}.controls{position:sticky;top:0;background:#f5f4eef5;z-index:1;padding:12px 0;border-bottom:1px solid #bcc7be;display:flex;flex-wrap:wrap;gap:12px;align-items:center}label{display:flex;flex-wrap:wrap;max-width:100%;gap:8px;align-items:center}select{max-width:100%}.single-style .row{grid-template-columns:150px minmax(0,500px)}input,select,button{font:inherit;border:1px solid #66786b;border-radius:4px;padding:8px;background:#fff;color:#202925;min-height:44px}input{width:100px}button{cursor:pointer}.row{display:grid;grid-template-columns:150px repeat(6,minmax(0,1fr));gap:12px;border-bottom:1px solid #cfd5cd;padding:20px 0}.row[hidden],article[hidden]{display:none}h2{font-size:16px;margin:0}small{display:block;font-weight:400;color:#506052}.sample{height:225px;padding:8px;display:flex;align-items:center;justify-content:center;background:#e5e7df}.sample canvas{max-width:100%;max-height:100%;cursor:zoom-in;box-shadow:0 2px 8px #0002}h3{font-size:14px;margin:6px 0}dialog{max-width:95vw;max-height:95vh;padding:18px;border:1px solid #66786b;background:#f5f4ee}dialog::backdrop{background:#0009}dialog canvas{display:block;max-width:85vw;max-height:75vh;margin:12px auto}dialog button{display:block;margin-left:auto}.note{font-size:14px;color:#506052}@media(max-width:1150px){.row{grid-template-columns:repeat(3,minmax(0,1fr))}.row h2{grid-column:1/-1}}@media(max-width:600px){.single-style .row{grid-template-columns:1fr}main{padding:16px}.row{grid-template-columns:repeat(2,minmax(0,1fr))}.sample{height:200px}}</style><main><h1>Celá kolekce: 15 šablon v 6 stylech</h1><p>Propracovaná původní kolekce, varianty se jménem a hedvábí ve světlém i tmavém provedení. Zůstávají rámečky, perforace, barevné panely i původní hierarchie textu. Barvy grafiky a písmo se přebírají ze stylu akce. Text zůstává neutrální a QR černobílý.</p><p>Šablonu si můžete dále upravit v editoru - změnit texty, jejich rozmístění i pozadí.</p><div class="controls"><label>Ukázkový koncept: vstupné <input id="price" type="number" min="0" step="1" value="350" aria-label="Cena vstupného v ukázkovém konceptu"> Kč</label><label>Šablony <select id="filter"><option value="all">Všechny (15)</option><option value="named">Se jménem</option><option value="silk">Hedvábí - světlé i tmavé</option></select></label><label>Styl <select id="style"><option value="all">Všech šest stylů</option>${Object.entries(styleNames).map(([k,v])=>`<option value="${k}">${v}</option>`).join('')}</select></label></div><p class="note">Cena v této prohlídce patří ukázkovému konceptu a lze ji měnit. V aplikaci se bere z produktů aktuálního konceptu. Kliknutím náhled zvětšíte.</p>${cards}</main><dialog id="zoom"><button id="close">Zavřít</button><canvas id="large"></canvas></dialog><script>
const scenes=${JSON.stringify(scenes)},draft=${JSON.stringify(draft)},images=new Map();
const currency=new Intl.NumberFormat('cs-CZ',{style:'currency',currency:'CZK',maximumFractionDigits:0});
async function draw(canvas,scene){
 await document.fonts.load('12px ticket-'+scene.style);
 let image=images.get(scene.name);
 if(!image){image=new Image();image.src=scene.name+'-background.png';await image.decode();images.set(scene.name,image);}
 const t=scene.reply.template,price=t.elements.find(e=>e.binding==='price'),b=price.box,scale=image.naturalWidth/t.page.width;
 canvas.width=image.naturalWidth;canvas.height=image.naturalHeight;const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0);
 const text='Cena: '+currency.format(draft.formDraft.fields[0].product_type_data.products[0].price);
 let size=price.style.fontSize*scale;ctx.font=size+'px ticket-'+scene.style;
 while(ctx.measureText(text).width>b.width*scale&&size>price.style.minFontSize*scale){size-=.25;ctx.font=size+'px ticket-'+scene.style;}
 ctx.fillStyle='#'+price.style.color;ctx.textAlign=price.style.align;ctx.textBaseline='middle';
 const align=price.style.align==='center'?.5:price.style.align==='right'?1:0;
 ctx.fillText(text,(t.ticketArea.x+b.x+b.width*align)*scale,(t.ticketArea.y+b.y+b.height/2)*scale,b.width*scale);
}
async function redraw(){await document.fonts.ready;await Promise.all([...document.querySelectorAll('[data-name]')].map(c=>draw(c,scenes.find(s=>s.name===c.dataset.name))));}
document.getElementById('price').addEventListener('input',e=>{if(e.target.value!==''&&Number(e.target.value)>=0){draft.formDraft.fields[0].product_type_data.products[0].price=Number(e.target.value);redraw();}});
function filter(){const kind=document.getElementById('filter').value,style=document.getElementById('style').value;document.querySelectorAll('.row').forEach(r=>{r.hidden=kind==='named'&&r.dataset.named!=='true'||kind==='silk'&&r.dataset.silk!=='true';});document.body.classList.toggle('single-style',style!=='all');document.querySelector('main').append(...[...document.querySelectorAll('.row')].sort((a,b)=>kind==='named'?Number(b.dataset.nameSize)-Number(a.dataset.nameSize):Number(a.dataset.order)-Number(b.dataset.order)));document.querySelectorAll('article[data-style]').forEach(c=>c.hidden=style!=='all'&&c.dataset.style!==style);}
document.getElementById('filter').onchange=filter;document.getElementById('style').onchange=filter;
const zoom=document.getElementById('zoom');document.getElementById('close').onclick=()=>zoom.close();
for(const c of document.querySelectorAll('[data-name]')){const open=async()=>{await draw(document.getElementById('large'),scenes.find(s=>s.name===c.dataset.name));const large=document.getElementById('large');large.style.width=Math.min(innerWidth*.85,innerHeight*.75*large.width/large.height,1000)+'px';large.style.height='auto';zoom.showModal();};c.onclick=open;c.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();open();}};}
redraw();</script></html>`);
console.log(`Catalog: ${scenes.length} real PDF designs, ${out}/index.html`);
