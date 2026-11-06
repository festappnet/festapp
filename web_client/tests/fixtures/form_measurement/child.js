import { EmbedBridge } from '/src/services/embed_bridge.js';
import { FormDataLayer } from '/src/components/forms/form_datalayer.js';
const policy = {enabled:true, organization_allowed:true, runtime_supported:true, privacy_url:"https://organizer.example/privacy",eligible:true, valid_for_seconds:60};
const model = {data:{analytics:policy}, visibleFields:[{id:1,type:'product_type',options:[{id:1,title:'Ticket',price:10,currency:'CZK'}]}]};
if (location.search.includes('token=')) history.replaceState(null, '', '/form/test?embed=1');
const bridge = new EmbedBridge(); bridge.start();
let layer = new FormDataLayer({model,bridge,entryAllowed:true,session:()=>false});
const cart = {fields:[{'1':'1',email:'private@example.test',phone:'123',name:'Person'}]};
let resolve;
window.addEventListener('message', e => {
 if(e.source!==parent || e.data?.fixture!==true) return;
 const {id,action,arg}=e.data;
 let result;
 try {
  if(action==='state') result={allowed:bridge.measurementAllowed(),instance:bridge.instance,consent:bridge.consent,enabled:layer.enabled()};
  if(action==='view') result=layer.view();
  if(action==='update') result=layer.update(cart);
  if(action==='confirmed') result=layer.confirmed({ticketOrder:{analytics:arg}});
  if(action==='observe') { const pending=new Promise(r=>resolve=r); layer.observe({payload:cart,awaitPendingReservations:()=>pending}); }
  if(action==='resolve') resolve?.();
  if(action==='raw') result=bridge.track(arg);
  if(action==='post') parent.postMessage(arg,'*');
  if(action==='policy') { layer.dispose(); model.data.analytics={...arg}; layer=new FormDataLayer({model,bridge,entryAllowed:true,session:()=>false}); }
  if(action==='dispose') layer.dispose();
  if(action==='visibility') document.dispatchEvent(new Event('visibilitychange'));
  if(action==='pagehide') window.dispatchEvent(new PageTransitionEvent('pagehide'));
  if(action==='pageshow') window.dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true}));
  if(action==='error') { const previous=bridge.track; bridge.track=()=>{throw Error('consumer error')}; result=layer.emit({event:'page_view'}); bridge.track=previous; }
  parent.postMessage({fixtureReply:true,id,result},'*');
 } catch(error) { parent.postMessage({fixtureReply:true,id,error:String(error)},'*'); }
});
parent.postMessage({fixtureReady:true},'*');
