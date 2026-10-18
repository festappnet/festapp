import { Component } from '../base/component.js';
import { tr, reasonText, escape as e } from './scan_strings.js';
import { scanResult } from './scan_result.js';
export class ScannerSettingsPage extends Component {
    constructor(host,{api,session}) {super(host);Object.assign(this,{api,session});}
    async init() {
        try {const r=await this.api.call('get_scanner_settings',{p_occasion:this.session.occasion_id},false);this.data=r.data;this.draft=structuredClone(r.data.config);this.render();}
        catch(err){this.host.innerHTML=`<main class="scan-shell"><a href="/scan">${tr('scan')}</a><p role="alert">${e(reasonText(err.message))}</p></main>`;}
    }
    render() {
        const d=this.draft;
        this.host.innerHTML=`<main class="scan-shell"><section class="scan-settings"><a href="/scan">${tr('scan')}</a><h1>${tr('settings')}</h1>${this.error?`<p class="scan-warning" role="alert">${e(reasonText(this.error))}</p><button data-reload>${tr('reload')}</button>`:''}${this.conflictDraft?`<button data-restore>${tr('restore_draft')}</button>`:''}${this.message?`<p role="status">${e(this.message)}</p>`:''}
        <div class="scan-settings-grid"><form data-settings><h2>${tr('products')}</h2><label>${tr('products')}<select data-mode>${['all','none','selected'].map(m=>`<option value="${m}" ${d.products.mode===m?'selected':''}>${tr(m)}</option>`).join('')}</select></label>
        <label>${tr('search')}<input data-filter value="${e(this.filter||'')}"></label>
        ${this.data.products.filter(p=>`${p.title} ${p.type_title}`.toLowerCase().includes((this.filter||'').toLowerCase())).map(p=>`<div class="scan-setting-row"><label><input type="checkbox" data-product="${p.id}" ${d.products.ids.includes(p.id)?'checked':''} ${d.products.mode!=='selected'?'disabled':''}>${e(p.title)} <small>${e(p.type_title)}</small></label><button type="button" data-product-up="${p.id}">${tr('up')}</button><button type="button" data-product-down="${p.id}">${tr('down')}</button></div>`).join('')}
        <h2>${tr('fields')}</h2>${d.fields.map((f,i)=>`<div class="scan-setting-row"><label><input type="checkbox" data-visible="${i}" ${f.default_visible?'checked':''}>${e(f.key)}</label><label>${tr('label')}<input data-label="${i}" value="${e(f.label||'')}"></label><label><input type="checkbox" data-hide-empty="${i}" ${f.hide_empty!==false?'checked':''}>${tr('hide_empty')}</label><button type="button" data-up="${i}">${tr('up')}</button><button type="button" data-down="${i}">${tr('down')}</button><button type="button" data-remove="${i}">${tr('remove')}</button></div>`).join('')}
        <label>${tr('fields')}<select data-add-field><option value="">${tr('choose_field')}</option>${['holder_name','spot','groups','note'].map(key=>`<option value="builtin:${key}">${tr(key)}</option>`).join('')}${this.data.fields.map((f,i)=>`<option value="${i}">${e(f.form_title)} / ${e(f.source)} / ${e(f.label)}</option>`).join('')}</select></label>
        <h2>${tr('behavior')}</h2>${[['manual_search','manual_search','tickets'],['user_search','manual_search','users'],['price','sensitive','price'],['hidden_note','sensitive','hidden_note'],['offline_enabled','offline','enabled']].map(([label,group,key])=>`<label><input type="checkbox" data-option="${group}.${key}" ${d[group][key]?'checked':''}>${tr(label)}</label>`).join('')}
        <label>${tr('hours')}<input data-hours type="number" min="0" max="12" step="1" value="${d.offline.max_hours}"></label>
        <button class="scan-primary" ${this.saving?'disabled':''}>${tr('save')}</button></form>
        <section><h2>${tr('preview')}</h2><form data-preview><label>${tr('symbol')}<input name="symbol" required maxlength="200"></label><button>${tr('lookup')}</button></form><div data-preview-result>${this.preview ? scanResult({state:'result',ticket:this.preview},false):''}</div></section></div></section></main>`;
        this.bind();
    }
    bind() {
        const find=s=>this.host.querySelector(s),all=(s,fn)=>this.host.querySelectorAll(s).forEach(fn);
        find('[data-mode]').onchange=ev=>{this.draft.products.mode=ev.target.value;this.render();};
        find('[data-filter]').onchange=ev=>{this.filter=ev.target.value;this.render();};
        all('[data-product]',b=>b.onchange=()=>{const id=Number(b.dataset.product);this.draft.products.ids=this.draft.products.ids.filter(x=>x!==id);if(b.checked)this.draft.products.ids.push(id);});
        const move=(array,index,delta)=>{const next=index+delta;if(index>=0&&next>=0&&next<array.length)[array[index],array[next]]=[array[next],array[index]];this.render();};
        all('[data-product-up],[data-product-down]',b=>b.onclick=()=>{const id=Number(b.dataset.productUp||b.dataset.productDown),a=this.draft.products.order;for(const p of this.data.products)if(!a.includes(p.id))a.push(p.id);move(a,a.indexOf(id),b.dataset.productUp?-1:1);this.data.products.sort((x,y)=>a.indexOf(x.id)-a.indexOf(y.id));this.render();});
        all('[data-up],[data-down]',b=>b.onclick=()=>move(this.draft.fields,Number(b.dataset.up??b.dataset.down),b.dataset.up!=null?-1:1));
        all('[data-visible]',b=>b.onchange=()=>{this.draft.fields[Number(b.dataset.visible)].default_visible=b.checked;});
        all('[data-label]',b=>b.onchange=()=>{this.draft.fields[Number(b.dataset.label)].label=b.value;});
        all('[data-hide-empty]',b=>b.onchange=()=>{this.draft.fields[Number(b.dataset.hideEmpty)].hide_empty=b.checked;});
        all('[data-remove]',b=>b.onclick=()=>{this.draft.fields.splice(Number(b.dataset.remove),1);this.render();});
        find('[data-add-field]').onchange=ev=>{if(ev.target.value==='')return;if(ev.target.value.startsWith('builtin:')){const key=ev.target.value.slice(8);if(!this.draft.fields.some(f=>f.key===key))this.draft.fields.push({key,source:'builtin',label:tr(key),default_visible:true,hide_empty:true});this.render();return;}const f=this.data.fields[Number(ev.target.value)],key=`${f.source==='ticket_field'?'ticket':'order'}:${f.form_id}:${f.field_id}`;if(!this.draft.fields.some(x=>x.key===key))this.draft.fields.push({...f,key,default_visible:true,hide_empty:true});this.render();};
        all('[data-option]',b=>b.onchange=()=>{const [group,key]=b.dataset.option.split('.');this.draft[group][key]=b.checked;});
        find('[data-hours]').onchange=ev=>{this.draft.offline.max_hours=Number(ev.target.value);};
        find('[data-settings]').onsubmit=async ev=>{ev.preventDefault();if(this.saving)return;this.saving=true;this.error=null;try {const r=await this.api.call('update_scanner_settings',{p_occasion:this.session.occasion_id,p_expected_revision:this.data.revision,p_config:this.draft},false);this.data=r.data;this.message=tr('settings_saved');}catch(err){this.error=err.message;}this.saving=false;this.render();};
        if(find('[data-restore]'))find('[data-restore]').onclick=()=>{this.draft=structuredClone(this.conflictDraft);this.conflictDraft=null;this.render();};
        if(find('[data-reload]'))find('[data-reload]').onclick=async()=>{this.conflictDraft=structuredClone(this.draft);await this.init();};
        find('[data-preview]').onsubmit=async ev=>{ev.preventDefault();try{this.preview=(await this.api.call('preview_scanner_ticket',{p_occasion:this.session.occasion_id,p_config:this.draft,p_symbol:ev.target.elements.symbol.value},false)).data;this.render();}catch(err){this.error=err.message;this.render();}};
    }
}
