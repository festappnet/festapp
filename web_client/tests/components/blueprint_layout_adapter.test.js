import fs from 'node:fs';
await import(process.env.BLUEPRINT_KERNEL_FILE ?? '@festapp/venue-layout/kernel');
import {FormModel} from '../../src/components/forms/form_models.js';
import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { BlueprintLayoutAdapter } from '../../src/components/blueprint/blueprint_layout_adapter.js';
import { FormSession } from '../../src/components/forms/form_session.js';
import { DbForms } from '../../src/components/forms/db_forms.js';
const dom = new JSDOM('<html><body></body></html>', {url:'http://localhost'});
globalThis.window = dom.window; globalThis.document = dom.window.document;
const data = () => ({layout:{nodes:[{id:'a',kind:'seat'},{id:'b',kind:'seat'}],selectionUnits:[{id:'unit',nodeIds:['a','b']}]},
    products:[{id:7,title:'Chair',price:100,currency_code:'CZK'}],
    seatBindings:[{nodeId:'a',spotId:11,productId:7,title:'A'},{nodeId:'b',spotId:12,productId:7,title:'B'}],
    spots:[{id:11,state:'available',customer:{email:'private'}},{id:12,state:'available'}]});
const session = () => new FormSession({key:'form',secret:'initial',visibleFields:[],relatedFields:[{type:'ticket',data:{max_tickets:5}}]});

test('unit selection creates both normal tickets with one hold command and latest secret', async t => {
    const calls=[];
    t.mock.method(DbForms,'selectSpot',async (...args)=>{calls.push(args); return {code:200,spotIds:[11,12],secret:'returned',expiresAt:'2026-10-19T18:00:00Z'};});
    const form=session(), adapter=new BlueprintLayoutAdapter(data(),{session:form});
    assert.equal((await adapter.requestSelection(new Set(['a']),true)).accepted,false);
    assert.equal(calls.length,0);
    assert.equal((await adapter.requestSelection(new Set(['a','b']),true)).accepted,true);
    assert.equal(calls.length,1);
    assert.deepEqual(form.payload.ticket.map(t=>t.spot),[11,12]);
    assert.equal(form.formModel.secret,'returned');
    assert.equal(form.payload[DbForms.metaSecret],'returned');
    assert.equal(adapter.selectedSeats.length,2);
    await form.removeTicket(0);
    assert.equal(calls.length,2);
    assert.equal(calls[1][1],'returned');
    assert.equal(form.state.tickets.length,0);
});
test('rejection rolls back all member tickets and pending duplicate is suppressed',async t=>{
    let reject, calls=0;
    t.mock.method(DbForms,'selectSpot',()=>{calls++;return new Promise((_,r)=>reject=r);});
    const form=session(), adapter=new BlueprintLayoutAdapter(data(),{session:form});
    const pending=adapter.requestSelection(new Set(['a','b']),true);
    await Promise.resolve();
    assert.equal((await adapter.requestSelection(new Set(['b','a']),true)).accepted,false);
    reject(new Error('held by another buyer'));
    assert.equal((await pending).accepted,false);
    assert.equal(calls,1); assert.equal(form.payload.ticket.length,0); assert.equal(adapter.selectedSeats.length,0);
});
test('presentation refresh during pending does not replace geometry or suppress completion; disposal stops callbacks',async()=>{
    let finish, patches=0;
    const adapter=new BlueprintLayoutAdapter(data(),{session:{toggleSpotUnit:()=>new Promise(r=>finish=r)}});
    const document=adapter.document;
    adapter.onPresentationChanged=()=>patches++;
    const pending=adapter.requestSelection(new Set(['a','b']),true);
    adapter.updatePresentation([{id:11,state:'ordered'},{id:12,state:'ordered'}]);
    assert.equal(adapter.document,document);
    finish({spotIds:[11,12]}); await pending;
    assert.equal(adapter.selectedSeats.length,2); assert.equal(patches,2);
    adapter.dispose(); adapter.updatePresentation([{id:11,state:'available'}]);
    assert.equal(patches,2);
    assert.equal(JSON.stringify(adapter.seatPresentation).includes('private'),false);
});
test('standing quantity uses offered admission fields and leaves unrelated tickets intact',async()=>{
    const form=new FormSession({key:'form',secret:'s',visibleFields:[{type:'ticket',subFields:[{id:23,type:'product_type',data:{product_type_data:{products:[{id:9,title:'Standing',price:80,currency_code:'CZK'}]}}}]}],relatedFields:[{type:'ticket',data:{max_tickets:5}}]});
    form.addTicket({spot:99,spotPrice:50});
    const source=data();source.areaBindings=[{nodeId:'standing',productId:9,inventoryContextId:3}];source.areaAvailability=[{nodeId:'standing',available:3}];
    source.products.push({id:9,title:'Standing',price:80,currency_code:'CZK'});
    const adapter=new BlueprintLayoutAdapter(source,{session:form});
    assert.equal((await adapter.requestQuantity('standing',2)).accepted,true);
    assert.equal(form.payload.ticket.length,3);
    assert.equal(form.payload.ticket[0].spot,99);
    assert.equal(form.payload.ticket[1].fields[0].product_type,9);
    assert.equal((await adapter.requestQuantity('standing',1)).accepted,true);
    assert.equal(form.payload.ticket.length,2);
    assert.equal((await adapter.requestQuantity('standing',4)).accepted,false);
});
test('authoritative sold state beats stale initial selection; own holds can release after wave closes',async()=>{
    const source=data();source.spots[0].state='ordered';source.spots[1].state='selected_by_me';
    source.products[0].is_available_dynamic_capacity=false;
    const adapter=new BlueprintLayoutAdapter(source,{session:{toggleSpotUnit:async()=>({})},initialSeats:[{id:11},{id:12}]});
    assert.equal(adapter.seatPresentation.a.status,'occupied');
    assert.equal(adapter.seatPresentation.a.selectable,false);
    assert.equal(adapter.seatPresentation.b.selected,true);
    assert.equal(adapter.seatPresentation.b.selectable,true);
});

test('raw form retains separately offered spot admission catalog only for area requests',async()=>{
    const model=new FormModel({key:'k',secret:'s',fields:[
        {id:99,type:'ticket',data:{max_tickets:5}},
        {id:17,type:'spot',is_ticket_field:true},
        {id:21,type:'product_type',is_ticket_field:true,product_type_data:{id:2,type:'spot',products:[{id:7,title:'Chair',price:100,currency_code:'CZK'}]}},
        {id:23,type:'product_type',is_ticket_field:true,product_type_data:{id:3,type:'spot',products:[{id:9,title:'Standing',price:80,currency_code:'CZK'}]}},
        {id:24,type:'product_type',is_ticket_field:true,is_hidden:true,product_type_data:{id:4,type:'spot',products:[{id:10,title:'Hidden',price:90,currency_code:'CZK'}]}},
    ]});
    const form=new FormSession(model);
    assert.equal(form._getTicketSubDefs().some(field=>field.type==='product_type'),false);
    assert.equal(Object.isFrozen(model.offeredTicketProductFields),true);
    assert.deepEqual(model.offeredTicketProductFields.map(field=>field.id),[21,23]);
    form.addTicket({spot:11,spotPrice:100});
    form.setAreaQuantity({nodeId:'standing',productId:9},2,5,{id:9,title:'Standing',price:80,currency_code:'CZK'});
    assert.equal(form.payload.ticket.length,3);
    assert.equal(form.payload.ticket[0].spot,11);
    assert.equal(form.payload.ticket[1].fields[0].product_type,9);
    assert.equal(form.payload.ticket[1].fields[0]._subFieldId,23);
    assert.equal(form.state.totalPrice,260);
    assert.throws(()=>form.setAreaQuantity({nodeId:'hidden',productId:10},1,5),/area_product_unavailable/);
});

test('unassigned available seat is empty while protected live state survives missing product',()=>{
    const source=data();source.products=[];source.spots[1].state='used';
    const adapter=new BlueprintLayoutAdapter(source,{session:{}});
    assert.equal(adapter.seatModel('a').state,'empty');
    assert.equal(adapter.seatPresentation.a.status,'unavailable');
    assert.equal(adapter.seatPresentation.a.selectable,false);
    assert.equal(adapter.seatModel('b').state,'used');
    assert.equal(adapter.seatPresentation.b.status,'occupied');
});

test('Basic status palette preserves seven distinct domain states through generic presentation', () => {
    const cases = [['available','#267329FF'],['selected_by_me','#267329FF'],['selected','#00000042'],['ordered','#0000001F'],['used','#412673FF'],['black','#000000DE'],['empty','#267329FF']];
    for (const [state, fill] of cases) {
        const fixture = data(); fixture.spots[0].state = state;
        if (state === 'black') fixture.seatBindings[0].blocked = true;
        if (state === 'empty') fixture.seatBindings[0].productId = null;
        const item = new BlueprintLayoutAdapter(fixture).seatPresentation.a;
        assert.equal(item.fill, fill, state);
        assert.equal(item.stateMarker, state === 'used' ? 'none' : 'auto');
        assert.equal(item.selected, state === 'selected_by_me');
        if (state === 'empty') { assert.equal(item.selectable, false); assert.equal(item.status, 'unavailable'); }
    }
});

test('public tooltip retains the original product-seat line and whole-number price',()=>{
 const a=new BlueprintLayoutAdapter(data());const t=a.seatPresentation.a.tooltip;
 assert.match(t,/^Chair A\n/);assert.match(t,/100/);assert.equal(t.includes('undefined'),false);assert.equal(t.includes('private'),false);
});

test('atomic seat unit over the form ticket limit sends no hold and creates no partial tickets',async t=>{
 let calls=0;t.mock.method(DbForms,'selectSpot',async()=>{calls++;return{code:200,spotIds:[11,12],secret:'s'};});
 const form=new FormSession({key:'form',secret:'s',visibleFields:[],relatedFields:[{type:'ticket',data:{max_tickets:1}}]});
 const adapter=new BlueprintLayoutAdapter(data(),{session:form});
 assert.equal((await adapter.requestSelection(new Set(['a','b']),true)).accepted,false);
 assert.equal(calls,0);assert.equal(form.state.tickets.length,0);assert.equal(adapter.selectedSeats.length,0);
});


test('distributed kernel renders the SQL canonical whole-text save/read/setup/copy corpus', () => {
    const corpus = JSON.parse(fs.readFileSync(new URL('../../../test/fixtures/blueprint/canonical-text-sql-roundtrip.json', import.meta.url), 'utf8'));
    assert.deepEqual(Object.keys(corpus).sort(), ['admin', 'copy', 'public', 'setup']);
    for (const [reader, {document, resources}] of Object.entries(corpus)) {
        const kernel = globalThis.VenueLayoutKernel;
        assert.deepEqual(JSON.parse(kernel.validate(JSON.stringify(document))), [], `${reader} document`);
        assert.deepEqual(JSON.parse(kernel.validateResources(JSON.stringify(resources))), [], `${reader} resources`);
        const scene = JSON.parse(kernel.compileScene(JSON.stringify(document), JSON.stringify(resources), '{}'));
        assert.deepEqual(scene.issues, [], `${reader} scene`);
        const labels = scene.items.filter(item => item.kind === 'glyphs');
        assert.ok(labels.length > 0, `${reader} prepared paragraphs`);
        assert.ok(labels.every(item => item.path.length > 0), `${reader} glyph paths`);
    }
});


test('distributed kernel matches exact Dart scenes from fresh SQL canonical readbacks', () => {
    const corpus = JSON.parse(fs.readFileSync(new URL('../../../test/fixtures/blueprint/canonical-text-sql-roundtrip.json', import.meta.url), 'utf8'));
    const expected = JSON.parse(fs.readFileSync(new URL('../../../test/fixtures/blueprint/canonical-text-sql-scenes.json', import.meta.url), 'utf8'));
    for (const [reader, {document, resources}] of Object.entries(corpus)) {
        const scene = JSON.parse(globalThis.VenueLayoutKernel.compileScene(JSON.stringify(document), JSON.stringify(resources), '{}'));
        assert.deepEqual(scene.issues, [], `${reader} scene`);
        assert.deepEqual(scene, expected[reader].scene, `${reader}: paths, matrices, bounds, clips, paint order`);
        assert.deepEqual(document.selectionUnits, expected[reader].selectionUnits);
        assert.ok(scene.items.some(item => item.kind === 'glyphs'));
    }
});

test('distributed core rejects historical masks and malformed canonical styles', () => {
    const {admin: {document}} = JSON.parse(fs.readFileSync(new URL('../../../test/fixtures/blueprint/canonical-text-sql-roundtrip.json', import.meta.url), 'utf8'));
    for (const style of [{label: {weight: 'bold'}}, {unknown: 1}, {opacity: 2}]) {
        const candidate = structuredClone(document);
        candidate.nodes[0].style = style;
        assert.ok(JSON.parse(globalThis.VenueLayoutKernel.validate(JSON.stringify(candidate))).length > 0);
    }
    const candidate = structuredClone(document);
    candidate.nodes[0].appearanceOverrides = ['fontId'];
    assert.ok(JSON.parse(globalThis.VenueLayoutKernel.validate(JSON.stringify(candidate))).length > 0);
});

test('capacity callback uses the bound blueprint catalog without admission form fields',async()=>{
    const form=new FormSession(new FormModel({key:'k',secret:'s',fields:[{id:99,type:'ticket',data:{max_tickets:5}},{id:17,type:'spot',is_ticket_field:true}]}));
    const source=data();source.areaBindings=[{nodeId:'standing',productId:9}];source.areaAvailability=[{nodeId:'standing',available:3}];source.products.push({id:9,title:'Standing',price:80,currency_code:'CZK'});
    source.products.push({id:9,title:'Standing',price:80,currency_code:'CZK'});
    const adapter=new BlueprintLayoutAdapter(source,{session:form});
    assert.equal((await adapter.requestQuantity('standing',2)).accepted,true);
    assert.equal(form.payload.ticket.length,2);
    assert.equal(form.state.totalPrice,160);
    assert.equal(form.payload.ticket[0].fields[0].product_type,9);
    assert.equal((await adapter.requestQuantity('unknown',1)).accepted,false);
});
