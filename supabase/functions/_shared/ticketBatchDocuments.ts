import { PDFDocument } from 'npm:pdf-lib';
import { digest, fontMetrics, type TicketFont } from './ticketFonts.ts';
import { loadLayoutResources, prepareTicketRendererFromResources, type Resources } from './ticketGeneration.ts';
import { boundDocumentOutput, documentLimits } from './documentLimits.ts';
import { layoutFontIds } from './ticketLayout.ts';

type Asset = {key:string;digest:string;bytes:number};
export interface BatchObjectStore {
  read(key:string):Promise<Uint8Array|null>;
  create(key:string,bytes:Uint8Array,contentType:string):Promise<void>;
}
function validAssetKey(batchId:string,key:string) {
  if(!key.startsWith(`${batchId}/resources/`) || !/^[a-zA-Z0-9/.-]+$/.test(key)||key.includes('..'))throw new Error('batch_resource_key_invalid');
}
async function persistAsset(batchId:string,bytes:Uint8Array,store:BatchObjectStore,limit:number):Promise<Asset> {
  if(!bytes.length||bytes.length>limit)throw new Error('batch_resource_limit');
  const hash=await digest(bytes),key=`${batchId}/resources/${hash}`;
  await store.create(key,bytes,'application/octet-stream');
  const stored=await store.read(key);
  if(!stored||await digest(stored)!==hash)throw new Error('batch_resource_integrity');
  return {key,digest:hash,bytes:stored.length};
}
/** Conservative sizing keeps large artwork/font batches in smaller fixed parts.
 * The renderer still verifies actual bytes before any ready publication. */
export function batchPrintPartSize(assetBytes:number,pages:number,outputBytes:number) {
  if(!Number.isSafeInteger(assetBytes)||assetBytes<0||pages<1||outputBytes<1)throw new Error('batch_part_policy_invalid');
  const perPage=Math.max(65536,assetBytes*3+262144);
  return Math.max(1,Math.min(20,pages,Math.floor(outputBytes/perPage)));
}
export async function sealBatchResources(claim:any,store:BatchObjectStore,load=loadLayoutResources) {
  const limits=documentLimits(claim),snapshot=claim.snapshot;
  const resources=await load(snapshot.occasion);
  const fonts:Record<string,any>={};let total=0;
  for(const [id,font] of Object.entries(resources.fonts??{})) {
    total+=font.bytes.length;
    fonts[id]={...await persistAsset(claim.batchId,font.bytes,store,limits.assetBytes),family:font.family,weight:font.weight};
  }
  const defaultId=Object.keys(fonts).find(id=>resources.fonts?.[id].bytes===resources.font);
  if(!defaultId)throw new Error('batch_default_font_missing');
  const background=resources.background?await persistAsset(claim.batchId,resources.background,store,limits.assetBytes):null;
  const logo=resources.logo?await persistAsset(claim.batchId,resources.logo,store,limits.assetBytes):null;
  total+=(background?.bytes??0)+(logo?.bytes??0);
  if(total>limits.assetBytes)throw new Error('batch_resource_total_limit');
  return {version:1,snapshot,printPartSize:batchPrintPartSize(total,limits.pages,limits.outputBytes),resources:{fonts,defaultId,background,logo}};
}
async function frozenAsset(batchId:string,asset:Asset,store:BatchObjectStore,limit:number) {
  validAssetKey(batchId,asset.key);
  if(asset.bytes>limit)throw new Error('batch_resource_limit');
  const bytes=await store.read(asset.key);
  if(!bytes||bytes.length!==asset.bytes||await digest(bytes)!==asset.digest)throw new Error('batch_resource_integrity');
  return bytes;
}
export async function renderBatchPart(claim:any,store:BatchObjectStore) {
  const limits=documentLimits(claim),m=claim.manifest;
  if(m.version!==1||m.snapshot.renderContractVersion!==1)throw new Error('batch_render_version');
  if(!Array.isArray(claim.ticketIds)||claim.ticketIds.length<1||claim.ticketIds.length>Math.min(20,limits.pages))throw new Error('batch_part_limit');
  const fonts:Record<string,TicketFont>={};let total=0;
  for(const [id,asset] of Object.entries(m.resources.fonts) as [string,any][]) {
    const bytes=await frozenAsset(claim.batchId,asset,store,limits.assetBytes);total+=bytes.length;
    fonts[id]={id,bytes,metrics:fontMetrics(bytes),family:asset.family,weight:asset.weight};
  }
  const selected=fonts[m.resources.defaultId];if(!selected)throw new Error('batch_default_font_missing');
  const background=m.resources.background?await frozenAsset(claim.batchId,m.resources.background,store,limits.assetBytes):undefined;
  const logo=m.resources.logo?await frozenAsset(claim.batchId,m.resources.logo,store,limits.assetBytes):undefined;
  total+=(background?.length??0)+(logo?.length??0);if(total>limits.assetBytes)throw new Error('batch_resource_total_limit');
  const feature=m.snapshot.occasion.features.find((f:any)=>f.code==='ticket');
  const resources:Resources={fonts,font:selected.bytes,metrics:selected.metrics,registeredIds:layoutFontIds(feature.layout),background,logo};
  const render=await prepareTicketRendererFromResources(m.snapshot.occasion,{},resources,m.snapshot.catalog);
  const pdf=await PDFDocument.create();
  for(const id of claim.ticketIds) {
    const data=m.snapshot.documentData.find((d:any)=>d.ticket.id===id);
    if(!data)throw new Error('batch_ticket_snapshot_missing');
    const single=await render(data.ticket);
    const source=await PDFDocument.load(single.bytes);
    if(source.getPageCount()!==1)throw new Error('batch_ticket_page_count');
    for(const page of await pdf.copyPages(source,[0]))pdf.addPage(page);
  }
  const bytes=await pdf.save();boundDocumentOutput(bytes,pdf.getPageCount(),limits);
  return {bytes,pages:pdf.getPageCount(),digest:await digest(bytes)};
}
export async function readBatchStoredPdf(document:any,store:BatchObjectStore) {
  if(!document||typeof document.objectKey!=='string'||!document.objectKey.endsWith('.pdf')||document.objectKey.includes('..'))throw new Error('batch_document_key_invalid');
  const bytes=await store.read(document.objectKey);
  if(!bytes||bytes.length!==document.bytes||await digest(bytes)!==document.digest)throw new Error('batch_document_integrity');
  return bytes;
}
