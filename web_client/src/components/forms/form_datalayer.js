import {analyticsPayload, currencies} from './form_measurement_contract.js';

// Public catalog labels only: the product type and the occasion it belongs to.
const catalogItem = (product, currency, item_category, item_brand) => ({item_id: `product_${product.id}`, item_name: product.title,
    price: Number(product.price), quantity: 1, currency, item_category, item_brand});

export class FormDataLayer {
    constructor({win = window, model, sink}) {
        this.win=win; this.model=model; this.sink=sink;
        this.previous=[]; this.pageType='product'; this.viewedPages=new Set();
        this.viewedCurrencies=new Set(); this.conversions=new Set();
        this.catalog = new Map(); this.fields = new Map();
        const visit = fields => {
            for (const field of fields || []) {
                if (field.isHidden) continue;
                if (field.type === 'product_type') {
                    this.fields.set(String(field.id), field);
                    for (const product of field.options || []) {
                        if (!/^[1-9]\d{0,15}$/.test(String(product.id))) continue;
                        const currency = product.currency || product.currency_code;
                        if (!currencies(currency)) continue;
                        this.catalog.set(String(product.id), catalogItem(product, currency, field.productTypeData?.title, model.occasionTitle));
                    }
                }
                visit(field.subFields);
            }
        };
        visit(model.visibleFields || model.relatedFields);
    }
    cancelPending() {this.observation=(this.observation||0)+1;}
    dispose() {this.cancelPending(); this.disposed=true;}
    emit(input) {return !this.disposed && this.sink.record(input);}
    activate(session) {
        this.previous=this.cart(session?.payload,session);
        this.view();
    }
    captureSubmission() {
        const send=this.sink.capture();
        return (success,data)=>{
            if(this.disposed)return;
            if(!success){send({event:'form_submit_error'});return;}
            const conversion=analyticsPayload(data?.ticketOrder?.analytics);
            if(!conversion || !['purchase','generate_lead'].includes(conversion.event))return;
            const identity=conversion.ecommerce?.transaction_id||conversion.event_id;
            if(this.conversions.has(identity))return;
            if(!this.#publishPage('confirmation',send))return;
            this.pageType='confirmation';
            if(send(conversion))this.conversions.add(identity);
        };
    }

    page(page_type) {
        this.pageType = page_type;
        return this.#publishPage(page_type,input=>this.emit(input));
    }
    #publishPage(page_type, send) {
        const language = this.win.document.documentElement.lang?.slice(0, 2);
        if(!send({page_type, language}))return false;
        if (!this.viewedPages.has(page_type) && send({event: 'page_view'})) this.viewedPages.add(page_type);
        return true;
    }
    // First real visitor input. Field names and values never leave.
    started() { if (!this.formStarted && this.emit({event: 'form_start'})) this.formStarted = true; }
    groups(event, items, extra = {}, send = input=>this.emit(input)) {
        for (const currency of new Set(items.map(item => item.currency))) {
            send({event, ecommerce: {currency, items: items.filter(item => item.currency === currency), ...extra}});
        }
    }
    view() {
        this.page(this.pageType);
        const items = [...this.catalog.values()];
        for (const currency of new Set(items.map(item => item.currency))) {
            if (!this.viewedCurrencies.has(currency) && this.emit({event:'view_item', ecommerce:{currency, items:items.filter(item => item.currency === currency)}}))
                this.viewedCurrencies.add(currency);
        }
        return this.viewedPages.size > 0;
    }
    cart(payload = {}, session) {
        const selected = new Map();
        const add = value => {
            for (const id of Array.isArray(value) ? value : String(value ?? '').split(' | ')) {
                const product = this.catalog.get(String(id));
                if (product) selected.set(product.item_id, {...product, quantity: (selected.get(product.item_id)?.quantity || 0) + 1});
            }
        };
        for (const field of payload.fields || []) {
            for (const id of this.fields.keys()) if (Object.hasOwn(field, id)) add(field[id]);
        }
        for (const [index, ticket] of (payload.ticket || []).entries()) {
            const cached = session?.spotModels?.get(String(ticket.spot));
            const product = cached?.productModel || cached?.product || session?.state?.tickets?.[index]?._blueprintProduct;
            if (product && /^[1-9]\d{0,15}$/.test(String(product.id))) {
                const currency = product.currency_code || product.currencyCode || product.currency || session?.state?.currency;
                if (currencies(currency)) {
                    this.catalog.set(String(product.id), catalogItem(product, currency,
                        product.type_title ?? this.catalog.get(String(product.id))?.item_category, this.model.occasionTitle));
                    if (ticket.spot) add(product.id);
                }
            }
            // Only a catalog product is accepted. Spot IDs, notes and all answers are ignored.
            for (const field of ticket.fields || []) if (Object.hasOwn(field, 'product_type')) add(field.product_type);
        }
        return [...selected.values()];
    }
    update(payload, session, send = input=>this.emit(input)) {
        const next = this.cart(payload, session);
        for (const [event, from, to] of [['add_to_cart', next, this.previous], ['remove_from_cart', this.previous, next]]) {
            const delta = from.map(item => ({...item, quantity: item.quantity - (to.find(old => old.item_id === item.item_id && old.currency === item.currency)?.quantity || 0)})).filter(item => item.quantity > 0);
            this.groups(event, delta, {}, send);
        }
        this.previous = next;
    }
    observe(session) {
        const send=this.sink.capture();
        const version = this.observation = (this.observation || 0) + 1;
        Promise.resolve().then(() => session.awaitPendingReservations?.({recover: false})).then(() => {
            if (version !== this.observation) return;
            this.update(session.payload, session, send);
        }).catch(() => {}); // Failed reservations never become successful cart changes.
    }
    review(payload, session) {
        const items = this.cart(payload, session);
        this.page('checkout');
        this.groups('begin_checkout', items);
    }
    payment(payload, method, session) {
        const items = this.cart(payload, session);
        this.groups('add_payment_info', items, {payment_type: items.every(item => item.price === 0) ? 'free' : method === 'stripe' ? 'card' : 'bank_transfer'});
    }
}
