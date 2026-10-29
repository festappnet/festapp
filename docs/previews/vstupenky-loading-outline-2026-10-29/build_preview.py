from pathlib import Path
import xml.etree.ElementTree as E
import copy,re
root=Path(__file__).resolve().parents[3];ns='{http://www.w3.org/2000/svg}';E.register_namespace('',ns[1:-1])
svg=E.parse(root/'assets/brand/vstupenky-online/vstupenky-online-transparent.svg').getroot()
fill=E.Element(ns+'g',{'class':'fill-layer'});outline=E.Element(ns+'g',{'class':'outline-layer','aria-hidden':'true'})
for part in ['ticket','center','name','domain']:
 original=next(e for e in svg if e.get('id')==part)
 for parent,outlined in [(fill,False),(outline,True)]:
  g=copy.deepcopy(original);g.attrib.pop('id');g.set('class','part-'+part);g.attrib.pop('fill',None)
  for node in g.iter():
   if outlined:
    node.attrib.pop('fill',None)
    if node.tag==ns+'path':node.set('pathLength','1');node.set('vector-effect','non-scaling-stroke')
  parent.append(g)
def markup(e):return re.sub(r' xmlns="[^"]*"','',E.tostring(e,encoding='unicode'))
logo='<svg xmlns="http://www.w3.org/2000/svg" viewBox="60 210 904 715" role="img" aria-label="vstupenky.online">'+markup(fill)+markup(outline)+'</svg>'
css='''
:root{--page:#ebf1f6;--ink:#19243b;--muted:#526174;--line:#b7c6d8;--blue:#80bdf2;--focus:#4465a6}*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);font:16px/1.55 system-ui,sans-serif}main{max-width:1120px;margin:auto;padding:34px 26px 46px}h1{font-size:clamp(28px,4vw,38px);letter-spacing:-.03em;line-height:1.15;margin:0 0 12px}header p{margin:0;max-width:78ch;color:var(--muted)}.toolbar{display:flex;align-items:center;flex-wrap:wrap;gap:14px 22px;margin:24px 0 18px}button,select{font:inherit;min-height:42px;padding:8px 14px;border:1px solid #8a9bae;border-radius:8px;background:white;color:var(--ink);cursor:pointer}button:hover,select:hover{background:#dce9f6;border-color:var(--focus)}button:disabled{opacity:.5;cursor:default}button:focus-visible,select:focus-visible,input:focus-visible{outline:3px solid var(--focus);outline-offset:4px}label{display:flex;align-items:center;gap:8px;cursor:pointer}input{accent-color:var(--focus);width:18px;height:18px}.stage{--logo-ink:#fff;--logo-blue:#80bdf2;--surface:#19243b;background:var(--surface);height:440px;display:flex;align-items:center;justify-content:center;overflow:hidden}.light .stage{--logo-ink:#19243b;--surface:#fff}.stage svg{display:block;width:390px;max-width:80%;max-height:92%;overflow:visible}.fill-layer .part-ticket,.fill-layer .part-name{fill:var(--logo-ink)}.fill-layer .part-center,.fill-layer .part-domain{fill:var(--logo-blue)}.outline-layer{fill:none;stroke-width:1.25px;stroke-linecap:round;stroke-linejoin:round;opacity:0}.outline-layer .part-ticket,.outline-layer .part-name{stroke:var(--logo-ink)}.outline-layer .part-center,.outline-layer .part-domain{stroke:var(--logo-blue)}.outline-layer path{fill:none;stroke-dasharray:1;stroke-dashoffset:1}.caption{display:flex;justify-content:space-between;gap:18px;flex-wrap:wrap;font-size:14px;color:var(--muted);margin:10px 0 24px}.choices{border:0;padding:0;margin:0;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:22px}.choices legend{font-size:21px;font-weight:650;letter-spacing:-.02em;margin-bottom:15px}.choice{display:block;cursor:pointer;border-top:2px solid var(--line);padding:16px 0 0}.choice:has(input:checked){border-color:var(--focus)}.choice-title{display:flex;align-items:center;gap:10px;font-weight:650;font-size:18px}.choice p{font-size:15px;color:var(--muted);margin:9px 0 0;max-width:36ch}.choice small{display:block;color:var(--ink);margin-top:8px}.note{border-top:1px solid var(--line);padding-top:20px;margin:28px 0 0;color:var(--muted);max-width:85ch}.note strong{color:var(--ink)}::selection{background:var(--blue);color:#19243b}@media(max-width:720px){main{padding:25px 18px 35px}.choices{grid-template-columns:minmax(0,1fr);gap:21px}.stage{height:340px}.stage svg{width:310px}.toolbar{gap:12px 16px}.choice p{max-width:none}.caption{margin-bottom:22px}}'''
js=r'''
const stage=document.querySelector('.stage');
const reduced=document.querySelector('#reduced');
const systemReduce=matchMedia('(prefers-reduced-motion:reduce)');
reduced.checked=systemReduce.matches;
let animations=[],mode='signature',paused=false,inView=true;
const names={signature:'Celý podpis',anchor:'Vstupenka zůstává',reverse:'Vykreslit a zase odvinout'};
const durations={signature:4400,anchor:4200,reverse:5400};
const fill=part=>stage.querySelector('.fill-layer .part-'+part);
const outline=part=>stage.querySelector('.outline-layer .part-'+part);
function sequence(element,frames){
 const animation=element.animate(frames.map(([offset,properties])=>({offset,...properties})),{duration:durations[mode],iterations:Infinity,easing:'linear',fill:'both'});
 animation.playbackRate=Number(document.querySelector('#speed').value);animations.push(animation);return animation;
}
function opacity(element,points){sequence(element,points.map(([t,v])=>[t,{opacity:v}]))}
function draw(part,start,end,reverse=false){
 const paths=[...outline(part).querySelectorAll('path')];
 paths.forEach((path,i)=>{
  const stagger=0; // Each word is one boolean-unioned path.
  const a=start+stagger,b=end+stagger;
  const frames=[[0,{strokeDashoffset:'1'}]];
  if(a>0)frames.push([a,{strokeDashoffset:'1'}]);
  frames.push([b,{strokeDashoffset:'0'}]);
  if(reverse){const erase=.845+(1-i/Math.max(1,paths.length-1))*.045;frames.push([erase,{strokeDashoffset:'0'}],[.998,{strokeDashoffset:'1'}]);}
  else frames.push([1,{strokeDashoffset:'0'}]);
  sequence(path,frames);
 });
}
function setPlayback(){
 const stop=paused||document.hidden||!inView;
 animations.forEach(a=>stop?a.pause():a.play());
 document.querySelector('#pause').textContent=paused?'Pokračovat':'Pozastavit';
}
function build(){
 animations.forEach(a=>a.cancel());animations=[];
 const reducedMode=reduced.checked;
 stage.querySelector('.outline-layer').style.opacity=reducedMode?'0':'1';
 document.querySelector('#pause').disabled=reducedMode;
 document.querySelector('#restart').disabled=reducedMode;
 document.querySelector('#label').textContent=names[mode];
 document.querySelector('#timing').textContent=reducedMode?'Omezený pohyb · statické logo':`Nekonečná smyčka · ${(durations[mode]/1000).toLocaleString('cs-CZ')} s na cyklus`;
 if(reducedMode)return;
 const back=mode==='reverse';
 for(const part of ['ticket','center']){
  if(mode==='anchor'){fill(part).style.opacity='1';outline(part).style.opacity='0';}
  else{
   fill(part).style.removeProperty('opacity');outline(part).style.removeProperty('opacity');
   opacity(fill(part),back?[[0,0],[.21,0],[.34,1],[.73,1],[.86,0],[1,0]]:[[0,0],[.21,0],[.34,1],[.84,1],[1,0]]);
   opacity(outline(part),back?[[0,1],[.29,1],[.39,0],[.72,0],[.83,1],[1,1]]:[[0,1],[.29,1],[.39,0],[1,0]]);
   draw(part,.015,.24,back);
  }
 }
 for(const [part,start,end,fillStart,fillEnd] of [['name',.16,.48,.44,.59],['domain',.29,.59,.56,.70]]){
  fill(part).style.removeProperty('opacity');outline(part).style.removeProperty('opacity');
  opacity(fill(part),back?[[0,0],[fillStart,0],[fillEnd,1],[.74,1],[.87,0],[1,0]]:[[0,0],[fillStart,0],[fillEnd,1],[.86,1],[1,0]]);
  opacity(outline(part),back?[[0,1],[fillStart+.07,1],[fillEnd+.05,0],[.76,0],[.85,1],[1,1]]:[[0,1],[fillStart+.07,1],[fillEnd+.05,0],[1,0]]);
  draw(part,start,end,back);
 }
 setPlayback();
}
document.querySelectorAll('input[name=mode]').forEach(input=>input.addEventListener('change',()=>{mode=input.value;paused=false;build()}));
document.querySelector('#pause').addEventListener('click',()=>{paused=!paused;setPlayback()});
document.querySelector('#restart').addEventListener('click',()=>{paused=false;build()});
document.querySelector('#speed').addEventListener('change',e=>animations.forEach(a=>a.updatePlaybackRate(Number(e.target.value))));
document.querySelector('#theme').addEventListener('change',e=>document.body.classList.toggle('light',e.target.value==='light'));
reduced.addEventListener('change',build);systemReduce.addEventListener('change',()=>{reduced.checked=systemReduce.matches;build()});
document.addEventListener('visibilitychange',setPlayback);
new IntersectionObserver(entries=>{inView=entries[0].isIntersecting;setPlayback()},{threshold:.05}).observe(stage);
const params=new URLSearchParams(location.search);
if(params.get('theme')==='light'){document.querySelector('#theme').value='light';document.body.classList.add('light')}
if(params.get('motion')==='reduced')reduced.checked=true;
if(params.get('mode') in names){mode=params.get('mode');document.querySelector(`input[value=${mode}]`).checked=true;}
build();
// Deterministic inspection of a phase is useful for static screenshot previews.
if(params.has('phase')){paused=true;animations.forEach(a=>{a.pause();a.currentTime=Number(params.get('phase'))*durations[mode]});setPlayback();}
'''
page='''<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>vstupenky.online - nekonečné načítání z obrysu do barvy</title><style>CSS</style></head><body><main><header><h1>Z obrysu do barvy. Znovu a plynule.</h1><p>Vykresluje se celá značka: vstupenka, „vstupenky“ i „.online“. Písmena Roboto Bold jsou geometricky sjednocená do společných obrysů bez vnitřních překryvů. Všechny návrhy běží automaticky v nekonečné smyčce.</p></header><div class="toolbar"><button id="pause" type="button">Pozastavit</button><button id="restart" type="button">Od začátku</button><label>Pozadí <select id="theme"><option value="dark">Tmavé</option><option value="light">Světlé</option></select></label><label>Rychlost <select id="speed"><option value="1">Normální</option><option value=".5">Zpomaleně</option></select></label><label><input id="reduced" type="checkbox">Omezit pohyb</label></div><div class="stage">LOGO</div><div class="caption"><span id="label">Celý podpis</span><span id="timing">Nekonečná smyčka</span></div><fieldset class="choices"><legend>Jak se má cyklus opakovat?</legend><label class="choice"><span class="choice-title"><input type="radio" name="mode" value="signature" checked>Celý podpis</span><p>Obrys vstupenky, společné obrysy obou řádků nápisu, výplň a krátké podržení. Celá značka pak jemně zmizí a začne znovu.</p><small>4,4 s · nejblíž vybranému návrhu</small></label><label class="choice"><span class="choice-title"><input type="radio" name="mode" value="anchor">Vstupenka zůstává</span><p>Symbol drží na místě. Ve smyčce se kreslí a vyplňuje pouze nápis, takže značka nikdy celá nezmizí.</p><small>4,2 s · klidnější při delším čekání</small></label><label class="choice"><span class="choice-title"><input type="radio" name="mode" value="reverse">Vykreslit a zase odvinout</span><p>Po výplni se logo vrátí k obrysu a ten se postupně odvine. Další kreslení přirozeně naváže.</p><small>5,4 s · plynulý návrat přes kontury</small></label></fieldset><p class="note"><strong>Doporučení:</strong> „Celý podpis“ zachovává původní nápad a přidává kreslení nápisu. „Vstupenka zůstává“ je nejklidnější pro dlouhé načítání. Jakmile jsou data připravená, aplikace se otevře ihned, bez čekání na konec cyklu.</p></main><script>JS</script></body></html>'''.replace('CSS',css).replace('LOGO',logo).replace('JS',js)
out=root/'docs/previews/vstupenky-loading-outline-2026-10-29/index.html';out.write_text(page)
print(f'Created {out} ({len(page):,} chars).')
