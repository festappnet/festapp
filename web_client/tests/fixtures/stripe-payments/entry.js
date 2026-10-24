import { OrderResult } from '../../../src/components/forms/order_result.js';
import { renderOrderOverview } from '../../../src/components/forms/order_overview.js';
import { LocalizationService } from '../../../src/services/localization_service.js';
import cs from '../../../../assets/translations/cs.json';
import de from '../../../../assets/translations/de.json';
import '../../../src/theme_config.css';

const states = ['preparing','open','pending','declined','paid','expired','action_required','refund_pending','partially_refunded','refunded','disputed','unknown'];
document.body.innerHTML=`<main><h1>Card payment component fixture</h1><p>This fixture renders the actual result and overview components with synthetic server projections. It does not create an order or perform a payment.</p><nav><label>State <select id="state"></select></label><label>Surface <select id="surface"><option value="result">Result</option><option value="overview">Overview</option></select></label><label>Language <select id="language"><option value="cs">Čeština</option><option value="de">Deutsch</option></select></label><label><input type="checkbox" id="dark"> Dark theme</label></nav><div id="result"></div></main>`;
const extra=document.createElement('style');extra.textContent='*{box-sizing:border-box}h1,p{overflow-wrap:anywhere}main{max-width:850px;padding:16px}nav{display:flex;flex-wrap:wrap;gap:16px;margin-block:24px}label{display:flex;flex-wrap:wrap;align-items:center;gap:8px;min-width:0;max-width:100%}select{font:inherit;min-width:0;max-width:100%;min-height:44px;background:var(--surface-color);color:var(--text-color)}:focus-visible{outline:2px solid var(--primary-color);outline-offset:4px}';document.head.append(extra);
const stateSelect=document.querySelector('#state');for(const state of states){const option=document.createElement('option');option.value=state;option.textContent=state;stateSelect.append(option);}
function render(){
 const lang=document.querySelector('#language').value;LocalizationService.currentLocale=lang;LocalizationService.translations=lang==='de'?de:cs;document.documentElement.lang=lang;
 document.body.classList.toggle('dark-mode',document.querySelector('#dark').checked);
 const state=stateSelect.value;
 const payment={method:'stripe',status:state,amount:'1234.50',received:state==='paid'?'1234.50':'0',returned:state==='refunded'?'1234.50':state==='partially_refunded'?'234.50':'0',currency:'CZK',deliveryState:'suppressed',admissionState:state==='disputed'?'hold':'pending',allowedActions:['refresh']};
 const host=document.querySelector('#result');
 if(document.querySelector('#surface').value==='result') OrderResult.render(host,true,{payment,overviewAvailable:true,ticketOrder:{order:{order_symbol:'1A2C3E4F5G'}}},{visibleFields:[],communicationTone:'formal'},()=>{});
 else renderOrderOverview(host,{root:{title:'Spolek přátel kulturního a společenského života ve Větřkovicích a okolí',symbol:'1A2C3E4F5G'},serverTime:'2026-10-21T12:00:00Z',people:[],offers:[],orders:[{symbol:'1A2C3E4F5G',state:state==='paid'?'paid':'ordered',currency:'CZK',total:1234.5,payment,tickets:[],items:[]}]},()=>{});
}
for(const control of document.querySelectorAll('select,input'))control.addEventListener('change',render);
render();
