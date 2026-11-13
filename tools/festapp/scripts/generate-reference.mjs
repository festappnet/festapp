import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {catalogProjection,schemaProjection} from '../src/operations/contract-projection.mjs';
import {READ_OPERATIONS, MCP_PERMISSIONS, scopesForOperation} from '../../../packages/festapp_contracts/mcp-permissions.mjs';
import {clientAllowsScopes} from '../src/remote/config.mjs';
import {referenceSourceDigest} from '../../../automation/release/help/mcp_reference.mjs';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const read = file => JSON.parse(fs.readFileSync(path.join(root,file),'utf8'));
const policy = read('integrations/chatgpt/client-policy.json');
const ids = [...READ_OPERATIONS, 'occasions.create', ...Object.values(MCP_PERMISSIONS).flatMap(p => p.operations)];
const catalog = catalogProjection;
const schema = value => schemaProjection(value, 'input');
const tool = d => ({id:d.id,name:d.name,description:d.description,scopes:scopesForOperation(d.id),
  readOnly:d.domainReadOnly,destructive:d.destructive ?? false,idempotent:d.idempotent ?? d.domainReadOnly,
  requiresLayoutWriteContract:d.requiresLayoutWriteContract ?? false,inputSchema:schema(d.input)});
const descriptors = catalog(ids);
if (new Set(descriptors.map(d=>d.id)).size !== descriptors.length || ids.some(id=>!descriptors.some(d=>d.id===id)))
  throw new Error('MCP permission/catalog coverage mismatch');
const translations = Object.fromEntries(['cs','en'].map(locale=>[locale,read(`assets/translations/${locale}.json`).McpConnection]));
const result = {
  schemaVersion:1,sourceDigest:referenceSourceDigest(root),
  permissions:Object.entries(MCP_PERMISSIONS).map(([scope,p])=>({scope,labels:Object.fromEntries(['cs','en'].map(locale=>{
    if(!translations[locale][p.label]) throw new Error(`Missing ${locale} MCP permission label: ${p.label}`);
    return [locale,translations[locale][p.label]];
  })),operations:p.operations,requires:p.requires})),
  tools:descriptors.map(tool).sort((a,b)=>a.id.localeCompare(b.id,'en')),
  publicChatgpt:{...policy,tools:catalog(ids.filter(id=>clientAllowsScopes({clients:[policy]},policy.id,scopesForOperation(id))),policy.dataProfile==='order-summary').map(tool)},
};
const text=JSON.stringify(result,null,2)+'\n';
const target=path.join(root,'automation/release/help/mcp-reference.json');
if(process.argv.includes('--check')) {
  if(!fs.existsSync(target)||fs.readFileSync(target,'utf8')!==text) throw new Error('MCP reference is stale. Run: pnpm --dir tools/festapp run docs:generate');
} else fs.writeFileSync(target,text);
console.log(`MCP reference: ${result.tools.length} tools, ${result.permissions.length} permissions${process.argv.includes('--check')?' (current)':''}.`);
