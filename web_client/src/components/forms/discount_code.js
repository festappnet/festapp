import { SupabaseService } from '../../services/supabase_service.js';
import { LocalizationService } from '../../services/localization_service.js';
import { formatPrice } from '../../utils/formatters.js';
const text = key => LocalizationService.tr(`DiscountCodes.${key}`);

// Transport and presentation only. SQL owns prices, scope, allocation and use.
export class DiscountCode {
    constructor(session, rpc = (input) => SupabaseService.getClient().rpc('quote_order_discount', {p_input: input})) {
        this.session = session; session.discountCode = this; this.rpc = rpc; this.code = ''; this.quote = null; this.generation = 0;
    }
    clear() { this.generation++; this.code = ''; this.quote = null; delete this.session.payload.discount; this.session._emitStateChanged?.(); }
    async apply() {
        const generation = ++this.generation;
        const input = {...this.session.payload, discount: {code: this.code}};
        const selection = JSON.stringify(input.ticket);
        const {data, error} = await this.rpc(input);
        if (generation !== this.generation || selection !== JSON.stringify(this.session.payload.ticket)) return false;
        if (error || data?.code !== 200) { this.quote = null; delete this.session.payload.discount; this.session._emitStateChanged?.(); throw new Error(text(data?.reason ?? 'invalid')); }
        this.quote = data.quote;
        this.selection = selection;
        this.session.payload.discount = {code: data.quote.code, fingerprint: data.quote.fingerprint};
        this.session._emitStateChanged?.();
        return true;
    }
    get valid() { return this.quote && this.selection === JSON.stringify(this.session.payload.ticket); }
    priceData(original) { return this.valid ? {...original, totalPrice:Number(this.quote.net), discount:this.quote} : original; }
    mount(form) {
        const section = document.createElement('details'); section.className = 'form-field-container discount-code';
        const summary = document.createElement('summary'); summary.textContent = text('prompt');
        const label = document.createElement('label'); label.textContent = text('code'); label.className = 'form-field-label';
        const input = document.createElement('input'); input.type = 'text'; input.className = 'form-control'; input.maxLength = 32; input.autocomplete = 'off'; input.spellcheck = false;
        label.append(input);
        const apply = document.createElement('button'); apply.type = 'button'; apply.className = 'btn btn-secondary'; apply.textContent = text('apply');
        const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'btn btn-link'; remove.textContent = text('remove');
        const status = document.createElement('p'); status.className = 'form-field-hint'; status.setAttribute('role','status'); status.setAttribute('aria-live','polite');
        const show = () => { status.textContent = this.valid ? `${text('base')}: ${formatPrice(this.quote.base,this.quote.currency,2,LocalizationService.currentLocale)} · ${text('discount')}: ${formatPrice(this.quote.discount,this.quote.currency,2,LocalizationService.currentLocale)} · ${text('net')}: ${formatPrice(this.quote.net,this.quote.currency,2,LocalizationService.currentLocale)}` : this.quote && this.code ? text('changed') : ''; };
        input.addEventListener('input',e=> {e.stopPropagation(); this.clear(); this.code = input.value.trim(); show();});
        apply.addEventListener('click',async()=> {apply.disabled = true; status.textContent = text('busy'); try { if (await this.apply()) show(); } catch(e) {status.textContent = e.message;} finally {apply.disabled = false;}});
        remove.addEventListener('click',()=> {this.clear(); input.value=''; show();});
        const actions = document.createElement('div'); actions.className = 'discount-code-actions';
        actions.append(apply, remove);
        section.append(summary,label,actions,status); form.insertBefore(section,form.querySelector('.form-actions'));
        this.session.addEventListener('state-changed',show);
        this.status = status;
    }
    reportInvalid() { if (this.status) this.status.textContent=text('invalid'); }
}
