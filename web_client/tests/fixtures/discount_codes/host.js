import {FormModel} from '../../../src/components/forms/form_models.js';
import {FormSession} from '../../../src/components/forms/form_session.js';
import {FormRenderer} from '../../../src/components/forms/form_renderer.js';
import {PriceWidget} from '../../../src/components/forms/widgets/price_widget.js';
import {DiscountCode} from '../../../src/components/forms/discount_code.js';
import {FormPage} from '../../../src/components/forms/form_page.js';
import {SupabaseService} from '../../../src/services/supabase_service.js';
import {OrderPreview} from '../../../src/components/forms/order_preview.js';
import '../../../src/theme_config.css';
import '../../../src/components/forms/form_component.css';
import {LocalizationService} from '../../../src/services/localization_service.js';

// The quote transport is a controlled test double; pricing and SQL are not exercised.
await LocalizationService.loadTranslations(new URLSearchParams(location.search).get('lang') || 'cs', {persist:false});
const model = new FormModel({fields:[{id:1,type:'email'}], payments:{available:['bank'],bank:{available:true,configured:true}}});
const session = new FormSession(model);
session.payload.ticket = [{id:1}];
Object.assign(session.state,{totalPrice:1000,totalItems:1,currency:'CZK'});
FormRenderer.render(document.querySelector('main'),session,model,false,{onInput:(e,form)=>session.handleInput(e,form)});
const widget = new PriceWidget(session,document.querySelector('main'));
window.calls = [];
let resolveQuote;
const discount = new DiscountCode(session, input => { window.calls.push(structuredClone(input)); return new Promise(resolve => {resolveQuote=resolve;}); });
discount.mount(document.querySelector('form'));
widget.render();
window.resolveQuote = result => resolveQuote(result);
window.changeSelection = () => {session.payload.ticket = [{id:2}]; session._emitStateChanged();};
window.showReview = () => OrderPreview.show(document.querySelector('form'), model, discount.priceData(session.state), (overlay, paymentType, method, quote) => { window.paymentQuote = {paymentType,method,quote}; }, null, session.payload);
// Explicit local transport double: the first response is lost and the replay succeeds.
window.startRetryFixture = () => {
    const sent = []; const counts = {preflight:0, completed:0, retryStartedAfterClose:false};
    SupabaseService.getClient = () => ({auth:{getSession:async () => ({data:{session:null},error:null})},
        functions:{invoke:async (name, {body}) => { if (sent.length === 1) counts.retryStartedAfterClose = !document.querySelector('.fullscreen-result-overlay') && location.hash !== '#order-result'; sent.push(JSON.parse(JSON.stringify(body))); return sent.length === 1 ? {data:null,error:{message:'lost'}} : {data:{code:200},error:null}; }}});
    session.payload.discount = {code:'SAVE',fingerprint:'fixture-fingerprint'};
    session.awaitPendingReservations = async () => {counts.preflight++;};
    session.captureReservationCapability = () => 'fixture-capability';
    session.completeReservation = capability => {if (capability === 'fixture-capability') counts.completed++;};
    const page = {currentSession:session, discountCode:discount, closePreview(){}, host:document.querySelector('main'), cleanup(){},
        showFullScreenLoader:FormPage.prototype.showFullScreenLoader, showFullScreenResult:FormPage.prototype.showFullScreenResult,
        submitOrder:FormPage.prototype.submitOrder};
    window.retryFixture = {sent,counts,session};
    page.submitOrder(document.querySelector('form'),model,document.body);
};
window.fixture = {session,discount};
window.fixtureReady = true;
