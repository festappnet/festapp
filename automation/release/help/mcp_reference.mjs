import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

export const MCP_REFERENCE_LOCALES = ['cs', 'en', 'sk'];

// The renderer can verify the committed snapshot without installing operator runtime dependencies.
export function referenceSourceDigest(root) {
  const operations='tools/festapp/src/operations';
  const files=[...fs.readdirSync(path.join(root,operations)).filter(f=>f.endsWith('.mjs')).map(f=>`${operations}/${f}`),
    'tools/festapp/src/mcp/server.mjs','tools/festapp/src/remote/delegation.mjs','tools/festapp/src/remote/config.mjs',
    'tools/festapp/scripts/generate-reference.mjs','tools/festapp/package.json',
    'packages/festapp_contracts/mcp-permissions.mjs','integrations/chatgpt/client-policy.json',
    ...MCP_REFERENCE_LOCALES.map(locale => `assets/translations/${locale}.json`)];
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
  for(const file of [...sources].sort()) {
    const bytes=fs.readFileSync(path.join(root,file));
    // The generator reads only MCP labels, not unrelated application copy.
    const input=MCP_REFERENCE_LOCALES.some(locale => file === `assets/translations/${locale}.json`)
      ? JSON.stringify(JSON.parse(bytes).McpConnection) : bytes;
    hash.update(file+'\0').update(input).update('\0');
  }
  return hash.digest('hex');
}
const escape = value => String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const code = text => `<code>${escape(text)}</code>`;
export function readMcpReference(root) {
  const reference=JSON.parse(fs.readFileSync(path.join(root,'automation/release/help/mcp-reference.json'),'utf8'));
  if(reference.sourceDigest!==referenceSourceDigest(root)) throw new Error('MCP reference is stale. Run: pnpm --dir tools/festapp run docs:generate');
  return reference;
}
const copy = {
  cs: {
    read: 'čtení / kontrola', write: 'akce vyžadující potvrzení', operation: 'Operace',
    publicTool: 'Dostupná i ve veřejném připojení ChatGPT v omezeném profilu souhrnů.',
    privateTool: 'Vyžaduje připojení, které tuto operaci povoluje; veřejné připojení ChatGPT ji nenabízí.',
    permissions: 'Požadovaná oprávnění včetně závislostí',
    layout: 'Dostupnost navíc vyžaduje úspěšné ověření kontraktu pro ukládání vzhledu vstupenek.',
    description: 'Technický popis nástroje (anglicky)', required: 'Povinné vstupy', none: 'žádné',
    operatorSchema: 'Vstupy operátorského připojení: JSON Schema', publicSchema: 'Varianta veřejného připojení ChatGPT',
    baseGroup: 'Připojení a vzhled vstupenek - základní čtení', createGroup: 'Založení skryté akce s uzavřeným prodejem',
    contains: 'Implementace obsahuje', toolsAnd: 'nástrojů a',
    permissionsSummary: 'funkčních oprávnění. Základní čtení a založení akce jsou uvedené samostatně.',
    notice: 'Tento katalog popisuje implementaci v aktuální verzi zdrojů. Nedokládá nasazení všech nástrojů ani jejich zpřístupnění Vašemu připojení. Rozhoduje seznam nástrojů po přihlášení, registrace klienta, souhlas, výběr akcí a aktuální práva účtu.',
    publicPrompt: 'Lze použít i ve veřejném připojení ChatGPT.',
    privatePrompt: 'Vyžaduje připojení s níže uvedenými nástroji; veřejný klient ChatGPT je neposkytuje.',
    copy: 'Kopírovat', promptRequirements: 'Potřebné nástroje a oprávnění',
  },
  en: {
    read: 'read / inspect', write: 'action requiring confirmation', operation: 'Operation',
    publicTool: 'Also available in the public ChatGPT connection under its summary profile.',
    privateTool: 'Requires a connection permitting this operation; the public ChatGPT connection does not offer it.',
    permissions: 'Required permissions including dependencies',
    layout: 'Availability also requires a successful ticket artwork write-contract check.',
    description: 'Tool contract description', required: 'Required inputs', none: 'none',
    operatorSchema: 'Operator inputs: JSON Schema', publicSchema: 'Public ChatGPT variant',
    baseGroup: 'Connection and ticket artwork - base reads', createGroup: 'Create a hidden event with sales closed',
    contains: 'The implementation contains', toolsAnd: 'tools and',
    permissionsSummary: 'functional permissions. Base reads and event creation are listed separately.',
    notice: 'This catalog describes the current source implementation. It does not establish deployment or access through your connection. Actual availability depends on discovered tools after sign-in, client registration, consent, selected events and current account rights.',
    publicPrompt: 'Also usable in the public ChatGPT connection.',
    privatePrompt: 'Requires a connection exposing the tools below; the public ChatGPT client does not provide them.',
    copy: 'Copy', promptRequirements: 'Required tools and permissions',
  },
  sk: {
    read: 'čítanie / kontrola', write: 'akcia vyžadujúca potvrdenie', operation: 'Operácia',
    publicTool: 'Dostupná aj vo verejnom pripojení ChatGPT v obmedzenom profile súhrnov.',
    privateTool: 'Vyžaduje pripojenie s povolenou operáciou. Verejné pripojenie ChatGPT ju neponúka.',
    permissions: 'Potrebné oprávnenia vrátane závislostí',
    layout: 'Dostupnosť vyžaduje aj úspešné overenie kontraktu na uloženie vzhľadu vstupeniek.',
    description: 'Technický popis nástroja (anglicky)', required: 'Povinné vstupy', none: 'žiadne',
    operatorSchema: 'Vstupy operátorského pripojenia: JSON Schema', publicSchema: 'Variant verejného pripojenia ChatGPT',
    baseGroup: 'Pripojenie a vzhľad vstupeniek: základné čítanie', createGroup: 'Vytvorenie skrytého podujatia s uzavretým predajom',
    contains: 'Implementácia obsahuje', toolsAnd: 'nástrojov a',
    permissionsSummary: 'funkčných oprávnení. Základné čítanie a vytvorenie podujatia sú uvedené samostatne.',
    notice: 'Katalóg opisuje aktuálnu implementáciu. Dostupnosť pre Vaše pripojenie overte podľa zoznamu nástrojov po prihlásení, registrácie klienta, súhlasu, vybraných podujatí a aktuálnych práv účtu.',
    publicPrompt: 'Dostupné aj vo verejnom pripojení ChatGPT.',
    privatePrompt: 'Vyžaduje pripojenie s uvedenými nástrojmi. Verejný klient ChatGPT ich neposkytuje.',
    copy: 'Kopírovať', promptRequirements: 'Potrebné nástroje a oprávnenia',
  },
};

export function renderMcpReference(reference, locale) {
  const ui = copy[locale];
  const publicTools = new Map(reference.publicChatgpt.tools.map(tool => [tool.id, tool]));
  const renderTool = tool => {
    const publicTool = publicTools.get(tool.id);
    return `<details id="${escape(tool.name)}"><summary>${code(tool.name)} - ${tool.readOnly ? ui.read : ui.write}</summary>
<p>${ui.operation}: ${code(tool.id)}. ${publicTool ? ui.publicTool : ui.privateTool}</p>
<p>${ui.permissions}: ${tool.scopes.map(code).join(', ')}.</p>
${tool.requiresLayoutWriteContract ? `<p class="note">${ui.layout}</p>` : ''}
<p>${ui.description}:</p><p lang="en">${escape(tool.description)}</p>
<p>${ui.required}: ${tool.inputSchema.required?.map(code).join(', ') || ui.none}.</p>
<details><summary>${ui.operatorSchema}</summary><pre><code>${escape(JSON.stringify(tool.inputSchema, null, 2))}</code></pre></details>${publicTool ? `<details><summary>${ui.publicSchema}</summary><p lang="en">${escape(publicTool.description)}</p><pre><code>${escape(JSON.stringify(publicTool.inputSchema, null, 2))}</code></pre></details>` : ''}</details>`;
  };
  const groups = [
    {id:'connection', label:ui.baseGroup, tools:reference.tools.filter(tool => ['context.inspect','access.inspect','ticket_layouts.inspect'].includes(tool.id))},
    {id:'create', label:ui.createGroup, tools:reference.tools.filter(tool => tool.id === 'occasions.create')},
    ...reference.permissions.map(permission => ({
      id:permission.scope.replaceAll(':', '-'), label:permission.labels[locale], scope:permission.scope,
      tools:reference.tools.filter(tool => permission.operations.includes(tool.id)),
    })),
  ];
  return `<p>${ui.contains} <strong>${reference.tools.length}</strong> ${ui.toolsAnd} <strong>${reference.permissions.length}</strong> ${ui.permissionsSummary}</p>
<p class="note">${ui.notice}</p>
${groups.map(group => `<details id="${group.id}"><summary>${escape(group.label)} (${group.tools.length})</summary>${group.scope ? `<p>${code(group.scope)}</p>` : ''}${group.tools.map(renderTool).join('\n')}</details>`).join('\n')}`;
}

export function renderMcpPrompts(reference, examples, locale) {
  const ui = copy[locale];
  const tools = new Map(reference.tools.map(tool => [tool.id, tool]));
  const publicIds = new Set(reference.publicChatgpt.tools.map(tool => tool.id));
  return examples.map(example => {
    const used = example.operations.map(id => {
      if (!tools.has(id)) throw new Error(`Unknown MCP prompt operation: ${id}`);
      return tools.get(id);
    });
    const scopes = [...new Set(used.flatMap(tool => tool.scopes))];
    const publicAllowed = used.every(tool => publicIds.has(tool.id));
    const {title, prompt, note} = example[locale];
    return `<h3 id="prompt-${escape(example.id)}">${escape(title)}</h3>
<p>${publicAllowed ? ui.publicPrompt : ui.privatePrompt}</p>
<div class="help-code-example" data-code-example><pre><code tabindex="0">${escape(prompt)}</code></pre><button class="button primary" type="button" data-copy-code>${ui.copy}</button><p role="status" aria-live="polite"></p></div>
${note ? `<p class="note">${escape(note)}</p>` : ''}
<details><summary>${ui.promptRequirements}</summary><p>${used.map(tool => `<a href="#${escape(tool.name)}">${code(tool.name)}</a>`).join(', ')}</p><p>${scopes.map(code).join(', ')}</p></details>`;
  }).join('\n');
}
