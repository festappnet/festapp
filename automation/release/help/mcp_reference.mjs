import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

// The renderer can verify the committed snapshot without installing operator runtime dependencies.
export function referenceSourceDigest(root) {
  const operations='tools/festapp/src/operations';
  const files=[...fs.readdirSync(path.join(root,operations)).filter(f=>f.endsWith('.mjs')).map(f=>`${operations}/${f}`),
    'tools/festapp/src/mcp/server.mjs','tools/festapp/src/remote/delegation.mjs','tools/festapp/src/remote/config.mjs',
    'tools/festapp/scripts/generate-reference.mjs','tools/festapp/package.json',
    'packages/festapp_contracts/mcp-permissions.mjs','integrations/chatgpt/client-policy.json',
    'assets/translations/cs.json','assets/translations/en.json'];
  // Follow local static imports as well: input enums and settings also come from shared JSON contracts.
  const sources=new Set();
  const visit=file=>{
    if(sources.has(file)) return;
    sources.add(file);
    if(!/\.[cm]?js$/.test(file)) return;
    const content=fs.readFileSync(path.join(root,file),'utf8');
    for(const [,relative] of content.matchAll(/\b(?:from\s*|import\s*)['"](\.[^'"]+)['"]/g))
      visit(path.relative(root,path.resolve(root,path.dirname(file),relative)).split(path.sep).join('/'));
  };
  files.forEach(visit);
  const hash=createHash('sha256');
  for(const file of [...sources].sort()) hash.update(file+'\0').update(fs.readFileSync(path.join(root,file))).update('\0');
  return hash.digest('hex');
}
const escape = value => String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const code = text => `<code>${escape(text)}</code>`;
export function readMcpReference(root) {
  const reference=JSON.parse(fs.readFileSync(path.join(root,'automation/release/help/mcp-reference.json'),'utf8'));
  if(reference.sourceDigest!==referenceSourceDigest(root)) throw new Error('MCP reference is stale. Run: pnpm --dir tools/festapp run docs:generate');
  return reference;
}
export function renderMcpReference(reference, locale) {
  const cs=locale==='cs';
  const publicIds=new Set(reference.publicChatgpt.tools.map(t=>t.id));
  const publicTools=new Map(reference.publicChatgpt.tools.map(t=>[t.id,t]));
  const renderTool = tool => `<details id="${escape(tool.name)}"><summary>${code(tool.name)} - ${cs?(tool.readOnly?'čtení / kontrola':'akce vyžadující potvrzení'):(tool.readOnly?'read / inspect':'action requiring confirmation')}</summary>
<p>${cs?'Operace':'Operation'}: ${code(tool.id)}. ${publicIds.has(tool.id)?(cs?'Dostupná i ve veřejném připojení ChatGPT v omezeném profilu souhrnů.':'Also available in the public ChatGPT connection under its summary profile.'):(cs?'Vyžaduje připojení, které tuto operaci povoluje; veřejné připojení ChatGPT ji nenabízí.':'Requires a connection permitting this operation; the public ChatGPT connection does not offer it.')}</p>
<p>${cs?'Požadovaná oprávnění včetně závislostí':'Required permissions including dependencies'}: ${tool.scopes.map(code).join(', ')}.</p>
${tool.requiresLayoutWriteContract?`<p class="note">${cs?'Dostupnost navíc vyžaduje úspěšné ověření kontraktu pro ukládání vzhledu vstupenek.':'Availability also requires a successful ticket artwork write-contract check.'}</p>`:''}
<p>${cs?'Technický popis nástroje (anglicky)':'Tool contract description'}:</p><p lang="en">${escape(tool.description)}</p>
<p>${cs?'Povinné vstupy':'Required inputs'}: ${tool.inputSchema.required?.map(code).join(', ')||(cs?'žádné':'none')}.</p>
<details><summary>${cs?'Vstupy operátorského připojení: JSON Schema':'Operator inputs: JSON Schema'}</summary><pre><code>${escape(JSON.stringify(tool.inputSchema,null,2))}</code></pre></details>${publicTools.has(tool.id)?`<details><summary>${cs?'Varianta veřejného připojení ChatGPT':'Public ChatGPT variant'}</summary><p lang="en">${escape(publicTools.get(tool.id).description)}</p><pre><code>${escape(JSON.stringify(publicTools.get(tool.id).inputSchema,null,2))}</code></pre></details>`:''}</details>`;
  const groups=[{id:'connection',label:cs?'Připojení a vzhled vstupenek - základní čtení':'Connection and ticket artwork - base reads',tools:reference.tools.filter(t=>['context.inspect','access.inspect','ticket_layouts.inspect'].includes(t.id))},
    {id:'create',label:cs?'Založení skryté akce s uzavřeným prodejem':'Create a hidden event with sales closed',tools:reference.tools.filter(t=>t.id==='occasions.create')},
    ...reference.permissions.map(p=>({id:p.scope.replaceAll(':','-'),label:p.labels[locale],scope:p.scope,tools:reference.tools.filter(t=>p.operations.includes(t.id))}))];
  return `<p>${cs?'Implementace obsahuje':'The implementation contains'} <strong>${reference.tools.length}</strong> ${cs?'nástrojů a':'tools and'} <strong>${reference.permissions.length}</strong> ${cs?'funkčních oprávnění. Základní čtení a založení akce jsou uvedené samostatně.':'functional permissions. Base reads and event creation are listed separately.'}</p>
<p class="note">${cs?'Tento katalog popisuje implementaci v aktuální verzi zdrojů. Nedokládá nasazení všech nástrojů ani jejich zpřístupnění Vašemu připojení. Rozhoduje seznam nástrojů po přihlášení, registrace klienta, souhlas, výběr akcí a aktuální práva účtu.':'This catalog describes the current source implementation. It does not establish deployment or access through your connection. Actual availability depends on discovered tools after sign-in, client registration, consent, selected events and current account rights.'}</p>
${groups.map(g=>`<details id="${g.id}"><summary>${escape(g.label)} (${g.tools.length})</summary>${g.scope?`<p>${code(g.scope)}</p>`:''}${g.tools.map(renderTool).join('\n')}</details>`).join('\n')}`;
}

export function renderMcpPrompts(reference, examples, locale) {
  const cs=locale==='cs';const tools=new Map(reference.tools.map(t=>[t.id,t]));
  const publicIds=new Set(reference.publicChatgpt.tools.map(t=>t.id));
  return examples.map(example=>{
    const used=example.operations.map(id=>{if(!tools.has(id))throw new Error(`Unknown MCP prompt operation: ${id}`);return tools.get(id);});
    const scopes=[...new Set(used.flatMap(t=>t.scopes))];
    const publicAllowed=used.every(t=>publicIds.has(t.id));
    return `<h3 id="prompt-${escape(example.id)}">${escape(example[locale].title)}</h3>
<p>${publicAllowed?(cs?'Lze použít i ve veřejném připojení ChatGPT.':'Also usable in the public ChatGPT connection.'):(cs?'Vyžaduje připojení s níže uvedenými nástroji; veřejný klient ChatGPT je neposkytuje.':'Requires a connection exposing the tools below; the public ChatGPT client does not provide them.')}</p>
<div class="help-code-example" data-code-example><pre><code tabindex="0">${escape(example[locale].prompt)}</code></pre><button class="button primary" type="button" data-copy-code>${cs?'Kopírovat':'Copy'}</button><p role="status" aria-live="polite"></p></div>
${example[locale].note?`<p class="note">${escape(example[locale].note)}</p>`:''}
<details><summary>${cs?'Potřebné nástroje a oprávnění':'Required tools and permissions'}</summary><p>${used.map(t=>`<a href="#${escape(t.name)}">${code(t.name)}</a>`).join(', ')}</p><p>${scopes.map(code).join(', ')}</p></details>`;
  }).join('\n');
}
