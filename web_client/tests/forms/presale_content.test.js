import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {FormModel} from '../../src/components/forms/form_models.js';
import {renderPresaleContent} from '../../src/components/forms/widgets/presale_content.js';
import {CountdownWidget} from '../../src/components/forms/widgets/countdown_widget.js';
import {FormAvailabilityService as Availability} from '../../src/components/forms/form_availability_service.js';
import {LocalizationService} from '../../src/services/localization_service.js';
const fixtures=JSON.parse(readFileSync(new URL('../../../shared/presale/render-cases.json',import.meta.url)));
LocalizationService.currentLocale='cs';
LocalizationService.translations=JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url)));
for(const f of fixtures) test(f.name,()=>{
 const dom=new JSDOM('<main></main>');globalThis.document=dom.window.document;
 try {
 const model=new FormModel({title:'Form',occasion:{title:'Event'},is_open:true,link:'test',saleOpeningNotification:{canSubscribe:f.email},
   data:{design:{presale_header:f.header},schedule:{start_time:'2099-01-01T12:00:00Z',enable_countdown:f.timer,countdown_title:f.html},sale_opening_notifications:{enabled:f.email}}});
 const host=document.querySelector('main');renderPresaleContent(host,model,()=>{}, {preview:true});
 assert.equal(Boolean(host.querySelector('h2')),f.title);
 assert.equal(Boolean(host.querySelector('.form-scheduled-opening')),f.fallback);
 assert.equal(host.querySelectorAll('.countdown-widget').length,f.timer?1:0);
 assert.equal(host.querySelectorAll('input[type=email]').length,f.email && f.html.includes('form-sale-opening-notification')?1:0);
 const legacyHtml=host.innerHTML;
 host.replaceChildren();assert.equal(Availability.renderStatus(host,model,Availability.getStatus(model),{onReload:()=>{}}),true);
 assert.ok(host.textContent.trim());
 assert.ok(!legacyHtml.includes('undefined'));
 } finally { CountdownWidget.stop();dom.window.close(); }
});
test('preview respects collection pause even when it contains a subscription slot',()=>{
 const dom=new JSDOM('<main></main>');globalThis.document=dom.window.document;
 try {const host=document.querySelector('main');renderPresaleContent(host,new FormModel({data:{schedule:{countdown_title:'<div class="html-editor-block form-sale-opening-notification"></div>',start_time:'2099-01-01T12:00:00Z'},sale_opening_notifications:{enabled:true,collection_paused:true}}}),()=>{},{preview:true});assert.equal(host.querySelector('input'),null);}finally{dom.window.close();}
});
