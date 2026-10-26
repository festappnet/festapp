import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';
let dom, Page, resumeUrl;
const request = 'R'.repeat(43);
const resume = `https://mcp.festapp.net/connect/test/finish?resume=${'S'.repeat(43)}`;
before(async () => {
    dom = new JSDOM('<div id="app"></div><div id="form-page-container"></div>', { url: `https://vstupenky.online/settings/mcp-connect?request=${request}` });
    Object.assign(globalThis, { window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements });
    ({ McpConnectionPage: Page, mcpResumeUrl: resumeUrl } = await import('../../src/components/mcp/mcp_connection_page.js'));
    const { LocalizationService } = await import('../../src/services/localization_service.js');
    LocalizationService.translations = JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json', import.meta.url)));
});
after(() => dom.window.close());
function fixture({ native = false, authenticated = true, occasions = [{ id: 99, title: '<img src=x onerror=alert(1)>' }, { id: 100, title: 'Ples' }], invoke } = {}) {
    const calls = [], navigation = [], popup = { opener: {}, location: { replace: url => navigation.push(url) }, close() { this.closed = true; } };
    let opened = 0;
    const browser = { location: { href: window.location.href, assign: url => navigation.push(url) }, open() { opened++; return popup; }, close() {} };
    const client = { auth: { getSession: async () => ({ data: { session: authenticated ? { user: { email: '1+test@example.test' } } : null } }) },
        functions: { invoke: async (name, { body }) => {
            assert.equal(name, 'mcp-session-exchange'); calls.push(body);
            if (invoke) return invoke(body);
            return { data: body.operation === 'details' ? { client: 'Codex', applicationType: native ? 'native' : 'web', occasions } : body.operation === 'status' ? { status: 'connected' } : { resumeUrl: resume } };
        } } };
    const container = document.getElementById('form-page-container');
    const page = new Page(container, { client, browser, pause: async () => {} });
    return { page, calls, container, navigation, popup, opened: () => opened };
}
test('select all is explicit, supports mixed/clear, and sends only shown IDs on approval', async () => {
    const f = fixture(); await f.page.init();
    assert.equal(f.container.querySelector('img'), null);
    assert.match(f.container.textContent, /test@example.test/);
    assert.doesNotMatch(f.container.textContent, /1\+test/);
    assert.equal(f.page.selected.size, 0);
    assert.equal([...f.container.querySelectorAll('button')].find(b => b.textContent === 'Povolit a propojit').disabled, true);
    f.container.querySelector('[data-occasion="99"]').click();
    assert.equal(f.container.querySelector('[data-select-all]').indeterminate, true);
    f.container.querySelector('[data-select-all]').click();
    assert.deepEqual([...f.page.selected], [99, 100]);
    f.container.querySelector('[data-select-all]').click(); assert.equal(f.page.selected.size, 0);
    f.container.querySelector('[data-select-all]').click(); assert.equal(f.calls.length, 1);
    await f.page.finish('approve');
    assert.deepEqual(f.calls.at(-1), { request, operation: 'approve', access: { type: 'occasions', occasionIds: [99, 100] } });
    assert.deepEqual(f.navigation, [resume]);
});
test('missing request and logged-out route never query consent details', async () => {
    const f = fixture({ authenticated: false }); await f.page.init();
    assert.equal(f.calls.length, 0); assert.equal(f.page.state, 'login');
    f.page.request = ''; await f.page.init(); assert.equal(f.page.state, 'invalid'); assert.equal(f.calls.length, 0);
});
test('empty events cannot be approved', async () => {
    const f = fixture({ occasions: [] }); await f.page.init();
    assert.equal(f.container.querySelector('[data-select-all]'), null);
    await f.page.finish('approve'); assert.equal(f.calls.length, 1);
});
test('native callback is isolated and success waits for server acknowledgement', async () => {
    const f = fixture({ native: true }); await f.page.init(); f.page.selected.add(99);
    await f.page.finish('approve');
    assert.equal(f.opened(), 1); assert.equal(f.popup.opener, null); assert.equal(f.popup.closed, true);
    assert.deepEqual(f.calls.map(c => c.operation), ['details', 'approve', 'status']);
    assert.equal(f.page.state, 'connected'); assert.match(f.container.textContent, /Propojeno/);
});
test('lost completion acknowledgement offers no second approval and leaves callback alive', async () => {
    const f = fixture({ native: true, invoke: async body => {
        if (body.operation === 'details') return { data: { client: 'Codex', applicationType: 'native', occasions: [{ id: 99, title: 'Ples' }] } };
        if (body.operation === 'approve') return { data: { resumeUrl: resume } };
        throw Error('offline');
    } });
    await f.page.init(); f.page.selected.add(99); await f.page.finish('approve');
    assert.equal(f.page.state, 'completionUnknown'); assert.equal(f.popup.closed, undefined);
    assert.equal(f.container.querySelector('button'), null);
});
test('busy state prevents changed selection and duplicate approval', async () => {
    let release;
    const f = fixture({ invoke: body => body.operation === 'details' ? { data: { client: 'Codex', occasions: [{ id: 99, title: 'Ples' }] } } : new Promise(resolve => { release = resolve; }) });
    await f.page.init(); f.page.selected.add(99); const pending = f.page.finish('approve');
    assert.equal(f.container.querySelector('fieldset').disabled, true);
    await f.page.finish('approve'); assert.equal(f.calls.length, 2);
    release({ data: { resumeUrl: resume } }); await pending;
});
test('continuation is restricted to exact trusted issuer route and unique resume proof', () => {
    assert.equal(resumeUrl(resume), resume);
    for (const bad of ['http://mcp.festapp.net/connect/a/finish?resume=' + 'S'.repeat(43), resume.replace('mcp.festapp.net', 'evil.example'), resume + '&resume=x', resume + '&next=x', resume + '#x', resume.replace('/finish', '/other'), resume.replace('https://', 'https://user@')]) {
        assert.throws(() => resumeUrl(bad));
    }
});
test('router keeps MCP consent in web client even on app-supported tenants', async () => {
    const { RouterService } = await import('../../src/services/router_service.js');
    const { SupabaseService } = await import('../../src/services/supabase_service.js');
    const original = SupabaseService.getClient;
    SupabaseService.getClient = () => ({ auth: { getSession: async () => ({ data: { session: null } }) } });
    try { assert.equal(await RouterService.handleInitialLoad(), true); assert.equal(document.getElementById('app').hidden, true); assert.match(document.getElementById('form-page-container').textContent, /Přihlas se/); }
    finally { SupabaseService.getClient = original; }
});
test('tree combines several organizers and single occasions; selecting children never grants future access', async () => {
    const f = fixture({invoke: body => ({data:body.operation === 'details'
        ? {client:'Codex',units:[{id:4,title:'Organizer',canCreateOccasions:true},{id:5,title:'Other',canCreateOccasions:false}],occasions:[{id:99,title:'Event',unitId:4},{id:100,title:'Other event',unitId:5},{id:101,title:'Single',unitId:6}],canRequestCreate:true}
        : {resumeUrl:resume}})});
    await f.page.init();
    assert.equal(f.container.querySelector('[data-whole-unit]'),null);
    assert.equal(f.page.canApprove,false);
    f.container.querySelector('[data-occasion="99"]').click();
    assert.equal(f.container.querySelector('[data-unit="4"]').indeterminate,true);
    assert.equal(f.page.selectedUnits.size,0);
    f.container.querySelector('[data-unit="4"]').click();
    assert.equal(f.page.selected.size,0);
    assert.equal(f.container.querySelector('[data-occasion="99"]').checked,true);
    assert.equal(f.container.querySelector('[data-occasion="99"]').disabled,true);
    assert.match(f.container.textContent,/zakládání nových/);
    f.container.querySelector('[data-unit="5"]').click();
    f.container.querySelector('[data-occasion="101"]').click();
    assert.equal(f.container.querySelector('[data-unit="6"]').disabled,true);
    assert.equal(f.page.canApprove,true);
    await f.page.finish('approve');
    assert.deepEqual(f.calls.at(-1).access,{type:'selection',units:[{unitId:4,canCreateOccasions:true},{unitId:5,canCreateOccasions:false}],occasionIds:[101]});
});
test('organizer without requested create scope remains read-only and deselection clears inherited access', async () => {
    const f=fixture({invoke:()=>({data:{client:'Codex',units:[{id:4,title:'Organizer',canCreateOccasions:true}],occasions:[{id:99,title:'Event',unitId:4}],canRequestCreate:false}})});
    await f.page.init();f.container.querySelector('[data-unit="4"]').click();
    assert.deepEqual(f.page.access.units,[{unitId:4,canCreateOccasions:false}]);
    f.container.querySelector('[data-unit="4"]').click();
    assert.equal(f.page.canApprove,false);
    assert.equal(f.container.querySelector('[data-occasion="99"]').checked,false);
    assert.equal(f.container.querySelector('[data-occasion="99"]').disabled,false);
});
test('refresh removes lost organizer grants and cannot silently acquire creation rights',async()=>{
    let units=[{id:4,title:'Organizer',canCreateOccasions:false}];
    const f=fixture({invoke:()=>({data:{client:'Codex',units,occasions:[],canRequestCreate:true}})});
    await f.page.init();f.container.querySelector('[data-unit="4"]').click();
    units=[{id:4,title:'Organizer',canCreateOccasions:true}];await f.page.init();
    assert.equal(f.page.access.units[0].canCreateOccasions,false);
    units=[];await f.page.init();assert.equal(f.page.canApprove,false);
});
test('a list beyond the broker limit remains visible and cannot silently bulk truncate',async()=>{
    const f=fixture({occasions:Array.from({length:101},(_,i)=>({id:i+1,title:`Event ${i+1}`}))});
    await f.page.init();
    assert.equal(f.container.querySelectorAll('[data-occasion]').length,101);
    assert.equal(f.container.querySelector('[data-select-all]').disabled,true);
    assert.match(f.container.textContent,/100/);
    for(let i=1;i<=100;i++)f.page.selected.add(i);
    f.page.render();
    assert.equal(f.container.querySelector('[data-occasion="101"]').disabled,true);
    assert.equal(f.page.canApprove,true);
    assert.equal(f.calls.length,1);
});
test('a disposed consent ignores an older pending details response',async()=>{
    let release;
    const f=fixture({invoke:()=>new Promise(resolve=>{release=resolve;})});
    const pending=f.page.init();await new Promise(r=>setImmediate(r));
    f.page.dispose();const before=f.container.innerHTML;
    release({data:{client:'old',occasions:[{id:99,title:'old'}]}});await pending;
    assert.equal(f.container.innerHTML,before);
    assert.equal(f.page.details,undefined);
});

test('disposed approval failure cannot overwrite the next route',async()=>{
 let reject;
 const f=fixture({invoke:body=>body.operation==='details'?{data:{client:'Codex',occasions:[{id:99,title:'Ples'}]}}:new Promise((_,r)=>{reject=r;})});
 await f.page.init();f.page.selected.add(99);const pending=f.page.finish('approve');
 f.page.dispose();f.container.textContent='Next route';reject(Error('offline'));await pending;
 assert.equal(f.container.textContent,'Next route');
});
test('occasions are grouped by organizer and sorted without granting access',async()=>{
 const f=fixture({invoke:()=>({data:{client:'Codex',units:[{id:5,title:'Zebra'},{id:4,title:'Áčko'}],occasions:[{id:102,title:'Židle',unitId:5},{id:100,title:'Beta',unitId:4},{id:99,title:'Álfa',unitId:4}]}})});
 await f.page.init();assert.deepEqual([...f.container.querySelectorAll('[data-unit-heading]')].map(x=>x.textContent),['Áčko','Zebra']);
 assert.deepEqual([...f.container.querySelectorAll('[data-occasion]')].map(x=>Number(x.dataset.occasion)),[99,100,102]);
 assert.equal(f.page.selected.size,0);assert.equal(f.calls.length,1);
});
test('router navigation disposes mounted consent before changing the URL',async()=>{
 const {RouterService}=await import('../../src/services/router_service.js');
 let disposed=false;RouterService._mcpPage={dispose(){disposed=true;}};
 RouterService.pushState('/form/test');assert.equal(disposed,true);assert.equal(RouterService._mcpPage,null);
 window.history.replaceState({},'',`/settings/mcp-connect?request=${request}`);
});
test('overlapping router imports mount only the latest consent instance',async()=>{
 const {RouterService}=await import('../../src/services/router_service.js');
 const {SupabaseService}=await import('../../src/services/supabase_service.js');
 const original=SupabaseService.getClient;let sessions=0;
 SupabaseService.getClient=()=>({auth:{getSession:async()=>{sessions++;return{data:{session:null}};}}});
 try {
  assert.deepEqual(await Promise.all([RouterService.handleInitialLoad(),RouterService.handleInitialLoad()]),[true,true]);
  assert.equal(sessions,1);
 } finally {RouterService.disposeMcpPage();SupabaseService.getClient=original;}
});


test('one informed approval includes exactly the displayed requested capabilities',async()=>{
 const permissions=['festapp:orders:read','festapp:orders:write','festapp:payments:write','festapp:tickets:send'];
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});
 await f.page.init();
 assert.equal(f.page.canApprove,false);
 assert.equal(f.container.querySelector('[data-permission]'),null);
 assert.match(f.container.textContent,/kontaktní údaje/);
 assert.match(f.container.textContent,/ruční platby/);
 assert.match(f.container.textContent,/e-mailem/);
 assert.match(f.container.textContent,/Vyberte alespoň/);
 f.container.querySelector('[data-occasion="99"]').click();
 await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access,{consentVersion:2,selection:{type:'occasions',occasionIds:[99]},permissions});
});
test('a narrow OAuth request stays narrow and invalid scope dependencies fail closed',async()=>{
 let requestedPermissions=['festapp:orders:read'];
 const f=fixture({invoke:()=>({data:{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions}})});
 await f.page.init();assert.deepEqual([...f.page.selectedPermissions],['festapp:orders:read']);
 assert.doesNotMatch(f.container.textContent,/Zapisovat ruční platby|Odesílat zákazníkům|Před rušením/);
 requestedPermissions=[];await f.page.init();assert.equal(f.page.selectedPermissions.size,0);
 requestedPermissions=['festapp:payments:write'];await f.page.init();assert.equal(f.page.state,'error');
});
test('organizers start collapsed above two groups; disclosure preserves selection and focus',async()=>{
 for(const count of [1,2,3]){
  const units=Array.from({length:count},(_,i)=>({id:i+1,title:`Organizer ${i+1}`,canCreateOccasions:true}));
  const f=fixture({invoke:()=>({data:{client:'Codex',units,occasions:units.map(u=>({id:u.id,title:'Event',unitId:u.id})),canRequestCreate:true}})});
  await f.page.init();
  assert.equal(f.container.querySelector('[data-unit-toggle="1"]').getAttribute('aria-expanded'),String(count<=2));
  assert.equal(f.container.querySelector('#mcp-unit-events-1').hidden,count>2);
  const initial=count<=2;
  f.container.querySelector('[data-unit-toggle="1"]').click();
  assert.equal(document.activeElement.dataset.unitToggle,'1');
  assert.equal(f.page.selected.size+f.page.selectedUnits.size,0);
  f.container.querySelector('[data-unit="1"]').click();
  assert.equal(f.container.querySelector('[data-unit-toggle="1"]').getAttribute('aria-expanded'),String(!initial));
  assert.match(f.container.textContent,/Celý pořadatel/);
  f.container.querySelector('[data-unit="1"]').click();
  f.container.querySelector('[data-occasion="1"]').click();
  assert.equal(f.page.selectedUnits.size,0);
  assert.equal(f.container.querySelector('[data-unit="1"]').indeterminate,true);
  assert.match(f.container.textContent,/Vybrané akce: 1 z 1/);
 }
});

test('product-only consent displays and submits exactly the new catalog scopes without requiring order access', async () => {
 const permissions=['festapp:products:read','festapp:products:write'];
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});
 await f.page.init();assert.equal(f.page.state,'consent');
 assert.match(f.container.textContent,/produkty/);
 f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});

test('schedule consent is explicit and preserves all registry dependencies',async()=>{
 const permissions=['festapp:products:read','festapp:product-schedules:read','festapp:product-schedules:write'];
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});
 await f.page.init();assert.equal(f.page.state,'consent');
 assert.match(f.container.textContent,/cenové vlny/);
 f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});


test('standing preparation consent is separate from product edits',async()=>{
 const permissions=['festapp:products:read','festapp:standing-inventory:write'];
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});
 await f.page.init();assert.equal(f.page.state,'consent');assert.match(f.container.textContent,/stání/);
 f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});

test('inventory summaries display and persist only their explicit read consent',async()=>{
 const permissions=['festapp:inventory:read'];
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});
 await f.page.init();assert.equal(f.page.state,'consent');assert.match(f.container.textContent,/Číst sklady, kapacity, nastavení a obsazení kontextů/);
 f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});

test('stock authoring consent names stock settings and retains only requested permissions',async()=>{
 const permissions=['festapp:inventory:read','festapp:inventory:write'];
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});
 await f.page.init();assert.equal(f.page.state,'consent');assert.match(f.container.textContent,/Upravovat sklady, jejich kontexty a zdroje/);
 f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});

test('product choices require the requested explicit authoring-read consent',async()=>{
 const permissions=['festapp:products:read','festapp:product-options:read'];
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});
 await f.page.init();assert.equal(f.page.state,'consent');assert.match(f.container.textContent,/Číst dostupné typy produktů a skladové volby/);
 f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});

test('seat consent distinguishes lifecycle reads from changing blocked bindings',async()=>{
 const permissions=['festapp:seats:read','festapp:seats:block'];const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});await f.page.init();assert.equal(f.page.state,'consent');assert.match(f.container.textContent,/Číst místa a jejich provozní stav/);assert.match(f.container.textContent,/Blokovat a odblokovat vybraná místa/);f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});

test('temporary-hold release consent is distinct from blocking seats',async()=>{
 const permissions=['festapp:seats:read','festapp:seats:release-holds'];const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});await f.page.init();assert.equal(f.page.state,'consent');assert.match(f.container.textContent,/Uvolňovat dočasné rezervace vybraných míst/);assert(!f.container.textContent.includes('Blokovat a odblokovat vybraná místa'));f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});

test('seat swap consent explicitly includes changing the order total',async()=>{
 const permissions=['festapp:seats:read','festapp:orders:read','festapp:seats:swap'];const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});await f.page.init();assert.equal(f.page.state,'consent');assert.match(f.container.textContent,/Prohazovat místa vstupenek a upravovat cenu objednávky/);assert(!f.container.textContent.includes('Uvolňovat dočasné rezervace vybraných míst'));f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});

test('seat order consent includes original ticket replacement and customer reads without broader writes',async()=>{
 const permissions=['festapp:seats:read','festapp:orders:read','festapp:seats:create-orders'];
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});
 await f.page.init();assert.equal(f.page.state,'consent');
 assert.match(f.container.textContent,/Vytvářet objednávky z míst a nahrazovat původní vstupenky/);
 assert.match(f.container.textContent,/kontaktní údaje/);
 assert(!f.container.textContent.includes('Prohazovat místa vstupenek a upravovat cenu objednávky'));
 f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
});

test('configuration consent names four separate permissions without expanding existing grants',async()=>{
 const permissions=['festapp:occasion-settings:read','festapp:occasion-settings:write','festapp:unit-settings:read','festapp:unit-settings:write'];
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions:permissions}:{resumeUrl:resume}})});
 await f.page.init();
 for(const text of ['Číst nastavení akce a hry','Měnit nastavení akce','Číst nastavení pořadatele','Měnit nastavení pořadatele']) assert(f.container.textContent.includes(text));
 f.container.querySelector('[data-occasion="99"]').click();
 await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
 assert.deepEqual(f.calls.at(-1).access.selection,{type:'occasions',occasionIds:[99]});
});
