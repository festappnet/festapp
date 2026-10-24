// Walk actual relative import edges from every ticket consumer. History and
// migration-only readers may exist, but must never be reachable from these roots.
const roots=['supabase/functions/download-ticket/index.ts','supabase/functions/preview-ticket-layout/index.ts','supabase/functions/process-email-queue/index.ts'];
const seen=new Set<string>();
async function walk(path:string){
 if(seen.has(path))return;seen.add(path);
 const source=await Deno.readTextFile(path);
 if(path.includes('/product-type-cutover/')||path.endsWith('ticketTemplateImport.ts'))throw new Error('Offline importer reachable: '+path);
 if(/\/(ticketLayout|ticketRenderData|ticketGeneration|generateTicket|products|handler)\.ts$/.test(path)){
   // Intl formatToParts uses part.type === 'currency'; that is not a catalog selector.
   if(/productTypeMap|product_type\s*===\s*['"]food|\.type\s*===\s*['"](?!currency['"])|schemaVersion\s*:\s*[12]\b|['"]food['"]/.test(source))throw new Error('Legacy ticket contract: '+path);
 }
 for(const match of source.matchAll(/(?:from\s*|import\s*\()\s*['"](\.[^'"]+\.ts)['"]/g)){
  const next=new URL(match[1],new URL(path,'file://'+Deno.cwd()+'/')).pathname.slice(Deno.cwd().length+1);
  await walk(next);
 }
}
for(const root of roots)await walk(root);
for(const file of ['lib/components/ticket_layout/models/ticket_layout.dart','database/functions/others/ticket_layout.sql']) {
 const source=await Deno.readTextFile(file);
 if(/['"]food['"]|productTypeMap|schemaVersion[^\n]*NOT IN\s*\('1'/.test(source))throw new Error('Legacy active validator: '+file);
}
console.log(`Runtime cutover: ${seen.size} reachable modules, no legacy product selector/importer`);
