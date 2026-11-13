import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';
import { MCP_SCOPES } from '../../../packages/festapp_contracts/mcp-permissions.mjs';
let dom, Page, resumeUrl;
const request = 'R'.repeat(43);
const issuer = 'https://mcp.vstupenky.online';
const resume = `https://mcp.vstupenky.online/connect/test/finish?resume=${'S'.repeat(43)}`;
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
            return { data: body.operation === 'details' ? { client: 'Codex', applicationType: native ? 'native' : 'web', occasions } : body.operation === 'status' ? { status: 'connected' } : { resumeUrl: resume, issuer } };
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
    assert.match(f.container.textContent, /Připojená aplikace má povolený přístup/);
    assert.doesNotMatch(f.container.textContent, /Codex/);
    assert.equal(f.container.querySelector('button[data-primary]').textContent, 'Zavřít okno');
    assert.equal(f.container.querySelector('.mcp-connected').getAttribute('role'), 'status');
});
test('lost completion acknowledgement offers no second approval and leaves callback alive', async () => {
    const f = fixture({ native: true, invoke: async body => {
        if (body.operation === 'details') return { data: { client: 'Codex', applicationType: 'native', occasions: [{ id: 99, title: 'Ples' }] } };
        if (body.operation === 'approve') return { data: { resumeUrl: resume, issuer } };
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
    release({ data: { resumeUrl: resume, issuer } }); await pending;
});
test('continuation is restricted to exact trusted issuer route and unique resume proof', () => {
    assert.equal(resumeUrl(resume, issuer), resume);
    assert.throws(() => resumeUrl(resume));
    assert.throws(() => resumeUrl(resume, 'https://mcp.festapp.net'));
    assert.throws(() => resumeUrl(resume, issuer + '/unexpected'));
    assert.throws(() => resumeUrl(resume, 'http://mcp.vstupenky.online'));
    for (const bad of ['http://mcp.vstupenky.online/connect/a/finish?resume=' + 'S'.repeat(43), resume.replace('mcp.vstupenky.online', 'evil.example'), resume + '&resume=x', resume + '&next=x', resume + '#x', resume.replace('/finish', '/other'), resume.replace('https://', 'https://user@')]) {
        assert.throws(() => resumeUrl(bad, issuer));
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
        : {resumeUrl: resume, issuer}})});
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


test('general consent uses current user rights without a functional checklist',async()=>{
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Inspector',occasions:[{id:99,title:'Ples'}],requestedPermissions:MCP_SCOPES}:{resumeUrl:resume,issuer}})});
 await f.page.init();
 assert.equal(f.container.querySelector('[data-permission]'),null);
 assert.equal(f.container.querySelector('[data-allow-create]'),null);
 assert.match(f.container.textContent,/aktuálními.*právy/);
 assert.doesNotMatch(f.container.textContent,/Vyberte povolené funkce|festapp:/);
 f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access,{consentVersion:2,selection:{type:'occasions',occasionIds:[99]},permissions:MCP_SCOPES});
});
test('organizer selection includes its available creation rights without another toggle',async()=>{
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Inspector',units:[{id:4,title:'Testovací organizace',canCreateOccasions:true}],occasions:[{id:99,title:'Ples',unitId:4}],canRequestCreate:true,requestedPermissions:[]}:{resumeUrl:resume,issuer}})});
 await f.page.init();f.container.querySelector('[data-unit="4"]').click();
 assert.equal(f.container.querySelector('[data-allow-create]'),null);
 assert.equal(f.page.access.units[0].canCreateOccasions,true);
 await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access.selection.units,[{unitId:4,canCreateOccasions:true}]);
});
test('a narrow OAuth request stays narrow and invalid scope dependencies fail closed',async()=>{
 let requestedPermissions=['festapp:orders:read'];
 const f=fixture({invoke:()=>({data:{client:'Codex',occasions:[{id:99,title:'Event'}],requestedPermissions}})});
 await f.page.init();assert.deepEqual(f.page.details.requestedPermissions,['festapp:orders:read']);
 assert.doesNotMatch(f.container.textContent,/Zapisovat ruční platby|Odesílat zákazníkům|Před rušením/);
 requestedPermissions=[];await f.page.init();assert.equal(f.page.details.requestedPermissions.length,0);
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

for (const [name, permissions] of [
  [
    "product-only consent displays and submits exactly the new catalog scopes without requiring order access",
    [
      "festapp:products:read",
      "festapp:products:write"
    ]
  ],
  [
    "schedule consent is explicit and preserves all registry dependencies",
    [
      "festapp:products:read",
      "festapp:product-schedules:read",
      "festapp:product-schedules:write"
    ]
  ],
  [
    "standing preparation consent is separate from product edits",
    [
      "festapp:products:read",
      "festapp:standing-inventory:write"
    ]
  ],
  [
    "inventory summaries display and persist only their explicit read consent",
    [
      "festapp:inventory:read"
    ]
  ],
  [
    "stock authoring consent names stock settings and retains only requested permissions",
    [
      "festapp:inventory:read",
      "festapp:inventory:write"
    ]
  ],
  [
    "product choices require the requested explicit authoring-read consent",
    [
      "festapp:products:read",
      "festapp:product-options:read"
    ]
  ],
  [
    "seat consent distinguishes lifecycle reads from changing blocked bindings",
    [
      "festapp:seats:read",
      "festapp:seats:block"
    ]
  ],
  [
    "temporary-hold release consent is distinct from blocking seats",
    [
      "festapp:seats:read",
      "festapp:seats:release-holds"
    ]
  ],
  [
    "seat swap consent explicitly includes changing the order total",
    [
      "festapp:seats:read",
      "festapp:orders:read",
      "festapp:seats:swap"
    ]
  ],
  [
    "seat order consent includes original ticket replacement and customer reads without broader writes",
    [
      "festapp:seats:read",
      "festapp:orders:read",
      "festapp:seats:create-orders"
    ]
  ],
  [
    "configuration consent names four separate permissions without expanding existing grants",
    [
      "festapp:occasion-settings:read",
      "festapp:occasion-settings:write",
      "festapp:unit-settings:read",
      "festapp:unit-settings:write"
    ]
  ]
]) test('internal request stays bounded: '+name,async()=>{
 const f=fixture({invoke:body=>({data:body.operation==='details'?{client:'Inspector',occasions:[{id:99,title:'Ples'}],requestedPermissions:permissions}:{resumeUrl:resume,issuer}})});
 await f.page.init();assert.equal(f.page.state,'consent');
 assert.equal(f.container.querySelector('[data-permission]'),null);
 assert.doesNotMatch(f.container.textContent,/festapp:/);
 f.container.querySelector('[data-occasion="99"]').click();await f.page.finish('approve');
 assert.deepEqual(f.calls.at(-1).access.permissions,permissions);
 assert.deepEqual(f.calls.at(-1).access.selection,{type:'occasions',occasionIds:[99]});
});

test('regional brand explanation is opt-in and absent for the global platform', async () => {
    const global = fixture(); await global.page.init();
    assert.doesNotMatch(global.container.textContent, /společné platformě|Toto připojení platí/);
    const regional = fixture({ invoke: async () => ({ data: { client: 'ChatGPT',
        regionalPortal: { name: 'vstupenky.online', platform: 'Festapp' }, occasions: [{ id: 99, title: 'Ples' }] } }) });
    await regional.page.init();
    assert.match(regional.container.textContent, /vstupenky.online, který běží na společné platformě Festapp/);
    assert.match(regional.container.textContent, /Toto připojení platí pro vstupenky.online/);
});

for (const client of ['Desktop application', 'Browser application']) test(`replacement and device naming for ${client}`, async () => {
    const connections = [
        { id: 'latest', durationDays: 365, name: '<img src=x>', expiresAt: '2030-01-02T12:00:00Z', access: { units: [{ unitId: 2, canCreateOccasions: true }], occasionIds: [] }, permissions: ['festapp:orders:read'] },
        { id: 'older', name: null, expiresAt: '2030-01-01T12:00:00Z', access: { units: [], occasionIds: [99] }, permissions: [] },
    ];
    const f = fixture({ invoke: async body => ({ data: body.operation === 'details' ?
        { client, occasions: [{ id: 99, title: 'Concert' }], connections } : { resumeUrl: resume, issuer } }) });
    await f.page.init();
    assert.equal(f.container.querySelector('h2').textContent, client);
    assert.equal(f.page.connection.connectionId, 'latest');
    assert.equal(f.page.connection.durationDays, 7, 'replacing an annual connection still defaults to seven days');
    assert.equal(f.container.querySelector('img'), null);
    f.container.querySelector('[data-occasion="99"]').click();
    assert.equal(f.page.canApprove, true);
    const select = f.container.querySelector('[name=connectionId]'); select.value = 'older'; select.dispatchEvent(new window.Event('change'));
    assert.equal(f.page.connection.connectionId, 'older');
    f.container.querySelector('input[value="new"]').click();
    assert.equal(f.page.canApprove, false, 'another device must have a name');
    const name = f.container.querySelector('[data-connection-name]');
    name.value = '   '; name.dispatchEvent(new window.Event('input')); assert.equal(f.page.canApprove, false);
    name.value = 'Office laptop'; name.dispatchEvent(new window.Event('input')); assert.equal(f.page.canApprove, true);
    await f.page.finish('approve');
    assert.deepEqual(f.calls.at(-1).access.connection, { mode: 'new', name: 'Office laptop', durationDays: 7 });
});

test('first connection has optional name and no replacement choice', async () => {
    const f = fixture({ invoke: async body => ({ data: body.operation === 'details' ?
        { client: 'Application', occasions: [{ id: 99, title: 'Concert' }], connections: [] } : { resumeUrl: resume, issuer } }) });
    await f.page.init(); assert.equal(f.container.querySelector('[name="connection-mode"]'), null);
    assert.equal(f.container.querySelector('[data-connection-name]').required, false);
    f.container.querySelector('[data-occasion="99"]').click(); assert.equal(f.page.canApprove, true);
    await f.page.finish('approve');
    assert.deepEqual(f.calls.at(-1).access.connection, { mode: 'new', name: '', durationDays: 7 });
});

for (const durationDays of [7, 30, 90, 365]) test(`duration ${durationDays} is selectable and sent in consent`, async () => {
    const f = fixture({ invoke: async body => ({ data: body.operation === 'details' ?
        { client: 'Registered application', occasions: [{ id: 99, title: 'Concert' }], connections: [] } : { resumeUrl: resume, issuer } }) });
    await f.page.init();
    const duration = f.container.querySelector('[name="durationDays"]');
    assert.deepEqual([...duration.options].map(o => o.value), ['7', '30', '90', '365']);
    assert.equal(duration.value, '7');
    assert.equal(f.container.querySelector('[data-long-duration-hint]'), null);
    duration.value = String(durationDays); duration.dispatchEvent(new window.Event('change'));
    assert.equal(Boolean(f.container.querySelector('[data-long-duration-hint]')), durationDays === 365);
    assert(!f.container.textContent.includes('Přístup platí 7 dní'));
    f.container.querySelector('[data-occasion="99"]').click();
    await f.page.finish('approve'); assert.equal(f.calls.at(-1).access.connection.durationDays, durationDays);
});

test('Czech and English duration copy describes the selected lifetime and revocation', async () => {
    const { LocalizationService } = await import('../../src/services/localization_service.js');
    const original = LocalizationService.translations;
    try {
        for (const locale of ['cs', 'en']) {
            LocalizationService.translations = JSON.parse(readFileSync(new URL(`../../../assets/translations/${locale}.json`, import.meta.url)));
            const f = fixture({ invoke: async () => ({ data: { client: 'Registered application', occasions: [{ id: 99, title: 'Concert' }], connections: [] } }) });
            await f.page.init();
            const select = f.container.querySelector('[name=durationDays]');
            assert.equal(select.options[3].textContent, locale === 'cs' ? '1 rok' : '1 year');
            select.value = '365'; select.dispatchEvent(new window.Event('change'));
            assert.match(f.container.querySelector('[data-long-duration-hint]').textContent, locale === 'cs' ? /Kdykoli jej můžete odebrat/ : /revoke it at any time/);
            assert.match(f.container.textContent, locale === 'cs' ? /Obnova tokenu ji neprodlužuje/ : /Token refresh does not extend it/);
        }
    } finally { LocalizationService.translations = original; }
});

test('unused legacy connections require an explicit choice and eligible default skips them', async () => {
    const old = { id: 'historical', name: 'Dřívější připojení', defaultEligible: false, expiresAt: '2030-01-01T12:00:00Z', access: { units: [], occasionIds: [99] }, permissions: [] };
    const connections = [old];
    const f = fixture({ invoke: async () => ({ data: { client: 'Aplikace', occasions: [{ id: 99, title: 'Ples' }], connections } }) });
    await f.page.init(); f.page.selected.add(99);
    assert.equal(f.page.connection.mode, ''); assert.equal(f.page.canApprove, false);
    connections.push({ ...old, id: 'issued', defaultEligible: true });
    await f.page.init();
    assert.equal(f.page.connection.connectionId, 'issued');
    assert.match(f.container.textContent, /30 dnech bez obnovy tokenu/);
});

test('global issuer selector stays on the protected broker transport', async () => {
    const { McpConnectionPage } = await import('../../src/components/mcp/mcp_connection_page.js');
    const calls = [];
    const page = new McpConnectionPage(null, {
        browser: { location: { href: 'https://vstupenky.online/settings/mcp-connect?request=' + 'a'.repeat(43) + '&issuer=https%3A%2F%2Fmcp.festapp.net' } },
        client: { functions: { invoke: async (_name, request) => { calls.push(request); return { data: {} }; } } },
    });
    await page.call('details');
    assert.equal(calls[0].headers['X-Festapp-Mcp-Issuer'], 'https://mcp.festapp.net');
    assert.equal(calls[0].body.organizationId, undefined);
});
