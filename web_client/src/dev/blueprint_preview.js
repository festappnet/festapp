// Imported only by the local preview HTML, never by the production client.
import kernelUrl from '@festapp/venue-layout/kernel?url';
import {loadKernel,loadLayoutAssets,mount} from '@festapp/venue-layout';
import {BlueprintLayoutAdapter} from '../components/blueprint/blueprint_layout_adapter.js';
import {BlueprintStrings} from '../components/blueprint/blueprint_strings.js';
import {LocalizationService} from '../services/localization_service.js';
const $=s=>document.querySelector(s);
let handle,adapter,current,serial=0;
const fetchJSON=async url=>{const r=await fetch(url,{cache:'no-store'}),v=await r.json();if(!r.ok)throw Error(v.error||'Náhled se nepodařilo načíst.');return v;};
function summary(){
 const seats=adapter?.selectedSeats||[],totals=new Map();
 for(const s of seats){const p=s.productModel;if(p)totals.set(p.currency_code,(totals.get(p.currency_code)||0)+p.price);}
 $('#selection').textContent=`Vybraná místa: ${seats.length}`;
 $('#price').textContent=[...totals].map(([currency,total])=>currency?new Intl.NumberFormat('cs',{style:'currency',currency}).format(total):`${total} (měna neuvedena)`).join(' + ')||'0 Kč';
 $('#cart').hidden=!seats.length;
}
async function show(key){
 const ticket=++serial;$('#refresh').disabled=true;$('#status').textContent='Načítám a ověřuji plánek…';$('#error').hidden=true;$('#error').textContent='';
 adapter?.dispose();handle?.dispose();adapter=handle=null;$('#viewer').replaceChildren();$('#cart').hidden=true;
 const [kind,id]=key.split('/');
 try{
  const result=await fetchJSON(`/__blueprint-preview/${kind}/${id}`);if(ticket!==serial)return;
  current=result;
  const session={state:{tickets:[]},async toggleSpotUnit(){return {};}};
  adapter=new BlueprintLayoutAdapter(result.data,{session});
  for(const model of adapter.models.values())if(model.productModel&&!model.productModel.currency_code)model.priceLabel=`${model.productModel.price} (měna neuvedena)`;
  const options=adapter.options();options.resources=await loadLayoutAssets(options.resources);options.messages=BlueprintStrings.viewerMessages;options.minZoom=1;options.maxZoom=8;options.canvasCornerRadius=12;
  handle=mount($('#viewer'),options);
  adapter.onPresentationChanged=seatPresentation=>{handle.update({seatPresentation});summary();};
  const p=result.parity;
  $('#status').textContent=p?`${p.seats} míst · ${p.groups} stolů/skupin · volná ${p.states.available||0} · prodaná ${p.states.ordered||0} · ostatní ${Object.entries(p.states).filter(([s])=>!['available','ordered'].includes(s)).reduce((n,[,v])=>n+v,0)} · ověřeno ${new Date(p.verifiedAt).toLocaleTimeString('cs')}`:'Ukázková šablona · všechna místa volná · ukázková cena 150 Kč';
  $('#notice').textContent=p?'Obsazenost se načítá z živé akce při otevření a tlačítkem Obnovit. Výběr je pouze místní zkouška, místa na živé akci nerezervuje.':'Zkouška výběru v kanonické šabloně. Nevytváří objednávku.';
  $('#full-form').hidden=!result.formUrl;if(result.formUrl)$('#full-form').href=result.formUrl;
  $('#source').hidden=!result.sourceUrl;if(result.sourceUrl)$('#source').href=result.sourceUrl;
  $('#receipt').textContent=p?`Kontrola ID míst, produktů, názvů a vazeb na stoly: shoda ${p.seats}/${p.seats}. Otisk obsazenosti: ${p.spotStateSha256.slice(0,16)}.`:'';
  document.documentElement.dataset.ready=key;
 }catch(e){$('#status').textContent='Náhled není dostupný';$('#error').hidden=false;$('#error').textContent=e.message;}
 finally{if(ticket===serial)$('#refresh').disabled=false;}
}
await LocalizationService.init();await LocalizationService.loadTranslations('cs');await loadKernel(kernelUrl);
const catalog=await fetchJSON('/__blueprint-preview/catalog');
for(const [label,kind,items] of [['Živé akce','live',catalog.events],['Šablony','template',catalog.templates]]){
 const group=document.createElement('optgroup');group.label=label;
 for(const item of items){const o=document.createElement('option');o.value=`${kind}/${item.id}`;o.textContent=item.title+(item.date?` · ${item.date}`:'');group.append(o);}$('#plans').append(group);
}
const initial=decodeURIComponent(location.hash.slice(1));if([...$('#plans').options].some(o=>o.value===initial))$('#plans').value=initial;
$('#plans').onchange=()=>{location.hash=$('#plans').value;};
window.addEventListener('hashchange',()=>{const key=decodeURIComponent(location.hash.slice(1));if([...$('#plans').options].some(o=>o.value===key)){$('#plans').value=key;show(key);}});
$('#refresh').onclick=()=>show($('#plans').value);
$('#fit').onclick=()=>handle?.fitToScreen();$('#zoom-in').onclick=()=>handle?.zoomBy(1.3);$('#zoom-out').onclick=()=>handle?.zoomBy(1/1.3);
$('#reset').onclick=()=>{adapter.updatePresentation(current.data.spots);summary();};
$('#theme').onclick=()=>document.documentElement.classList.toggle('dark');
await show($('#plans').value);
