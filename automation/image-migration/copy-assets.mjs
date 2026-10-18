#!/usr/bin/env node
import { createHash, randomUUID } from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { readFile, mkdir, open, stat, link, unlink } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { copyVerifiedAsset } from './lib/verified-copy.js';

const { values } = parseArgs({ options: {
  manifest:{type:'string'}, 'r2-inventory':{type:'string'}, 'r2-config':{type:'string'}, receipts:{type:'string'}, validate:{type:'boolean'},
} });
if (!values.manifest) throw new Error('manifest_required');
const manifestBytes=await readFile(values.manifest);
const manifestSha256=createHash('sha256').update(manifestBytes).digest('hex');
const manifest = JSON.parse(manifestBytes);
if (values.validate) {
  process.stdout.write(JSON.stringify({objects:manifest.objects.length,orphanObjects:manifest.orphan_objects?.length ?? 0,readyForCopy:manifest.summary.ready_for_copy,readyForReferenceRewrite:manifest.summary.ready_for_reference_rewrite ?? false,blockers:manifest.summary.blockers})+'\n');
  process.exitCode=manifest.summary.ready_for_copy?0:2;
} else {
  // Only fully resolved source objects may be copied additively. A missing
  // reference target still blocks its rewrite and the full cutover, not copies
  // of independent verified objects. No source deletion occurs here.
  if (!manifest.summary.ready_for_copy || manifest.objects.some(obj=>obj.issues.length)) throw new Error('inventory_gate_not_passed');
  const repositoryRoot=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
  const git=(...args)=>execFileSync('git',args,{encoding:'utf8',cwd:repositoryRoot}).trim();
  // A detached release worktree at the exact reviewed main commit is canonical
  // too. Branch names grant no authority; source identity and cleanliness do.
  if(git('rev-parse','HEAD')!==git('rev-parse','origin/main')||git('status','--porcelain')) throw new Error('reviewed_clean_canonical_main_required');
  const sourceRevision=git('rev-parse','HEAD');
  if (!values['r2-config'] || !values.receipts) throw new Error('protected_config_and_receipts_required');
  if (!values['r2-inventory']) throw new Error('complete_r2_inventory_required');
  const r2Bytes=await readFile(values['r2-inventory']);
  if(createHash('sha256').update(r2Bytes).digest('hex')!==manifest.r2_inventory_sha256)throw new Error('r2_inventory_digest_mismatch');
  const r2Inventory=JSON.parse(r2Bytes);
  if(r2Inventory.version!==1||r2Inventory.read_only!==true)throw new Error('invalid_r2_inventory');
  const configStat=await stat(values['r2-config']);
  if ((configStat.mode & 0o777)!==0o600 || configStat.uid!==process.getuid()) throw new Error('private_config_mode_or_owner');
  const config=JSON.parse(await readFile(values['r2-config'],'utf8'));
  if (config.endpoint!=='https://84b32318ac235bf6738bdf1c8caa0795.r2.cloudflarestorage.com') throw new Error('unexpected_r2_account');
  const { S3Client, GetObjectCommand, HeadObjectCommand, PutObjectCommand }=await import('@aws-sdk/client-s3');
  const client=new S3Client({region:'auto',endpoint:config.endpoint,credentials:{accessKeyId:config.accessKeyId,secretAccessKey:config.secretAccessKey},requestChecksumCalculation:'WHEN_REQUIRED'});
  await mkdir(values.receipts,{mode:0o700,recursive:true});
  const receiptStat=await stat(values.receipts);
  if ((receiptStat.mode & 0o777)!==0o700 || receiptStat.uid!==process.getuid()) throw new Error('private_receipt_directory');
  const missing=error=>error?.$metadata?.httpStatusCode===404;
  const sourceProgram=`import json,sys,os,stat\nfrom pathlib import Path\nassert os.uname().nodename.split('.')[0]=='festapp-supabase-rehearsal-01'\nroot=Path('/opt/festapp-supabase/docker/volumes/storage')\nvalue=json.load(sys.stdin)\np=root/value['path']\nassert not Path(value['path']).is_absolute() and '..' not in Path(value['path']).parts\nassert p.resolve().is_relative_to(root)\nfd=os.open(p,os.O_RDONLY|os.O_NOFOLLOW)\nassert stat.S_ISREG(os.fstat(fd).st_mode) and os.fstat(fd).st_size==value['size']\nwith os.fdopen(fd,'rb') as f:\n while True:\n  data=f.read(1048576)\n  if not data:break\n  sys.stdout.buffer.write(data)\n`;
  const quote=value=>"'"+value.replaceAll("'","'\\''")+"'";
  const destination={
    async exists(Bucket,Key) { try { await client.send(new HeadObjectCommand({Bucket,Key}));return true; } catch(error) {if(missing(error))return false;throw new Error('destination_head_failed');} },
    async read(Bucket,Key) { try {const object=await client.send(new GetObjectCommand({Bucket,Key}));return {stream:object.Body,contentType:object.ContentType};} catch(error) {if(missing(error))return null;throw new Error('destination_read_failed');} },
    async create(Bucket,Key,Body,options) {
      try { await client.send(new PutObjectCommand({Bucket,Key,Body,ContentLength:options.contentLength,ContentType:options.contentType,Metadata:{sha256:options.sha256},IfNoneMatch:'*'})); }
      catch(error) { if(error?.$metadata?.httpStatusCode===412) throw Object.assign(new Error('conditional_create_conflict'),{code:'PRECONDITION_FAILED'}); throw new Error('destination_create_failed'); }
    },
  };
  let verified=0;
  const importedR2=r2Inventory.objects.map(item=>({
    identity:{bucket:item.source_bucket,key:item.key},issues:[],
    source:{size:item.size,sha256:item.sha256},
    visibility:item.source_bucket.endsWith('-private')?'private':'public',
    destination:{bucket:item.destination_bucket,key:item.destination_key},
    metadata:{mimetype:item.source_metadata?.Metadata?.['content-type']??item.source_metadata?.MimeType},
    sourceKind:'r2',
  }));
  for (const item of [...importedR2,...manifest.objects,...(manifest.orphan_objects ?? [])]) {
    const contentType=item.metadata?.mimetype;
    if(typeof contentType!=='string'||!contentType) throw new Error('source_mime_requires_review');
    const asset={...item,contentType};
    await copyVerifiedAsset(asset,{
      async openSource() {
        if(item.sourceKind==='r2') {
          if(!['festapp-images','festapp-images-a','festapp-images-private','festapp-images-a-private'].includes(item.identity.bucket))throw new Error('unexpected_r2_source');
          const object=await client.send(new GetObjectCommand({Bucket:item.identity.bucket,Key:item.identity.key}));
          if(object.ContentType!==contentType)throw new Error('source_mime_changed');
          return {stream:object.Body,done:Promise.resolve()};
        }
        const child=spawn('ssh',['-o','ConnectTimeout=20','festapp-backend-agent','python3 -c '+quote(sourceProgram)],{stdio:['pipe','pipe','ignore']});
        const done=new Promise((resolve,reject)=>{child.on('error',()=>reject(new Error('source_transport_failed')));child.on('close',code=>code===0?resolve():reject(new Error('source_read_failed')));});
        child.stdin.on('error',()=>{});
        child.stdin.end(JSON.stringify({path:item.source.path,size:item.source.size}));
        return {stream:child.stdout,done};
      },destination,
      async persistReceipt(receipt) {
        receipt.sourceRevision=sourceRevision;
        receipt.manifestSha256=manifestSha256;
        receipt.r2InventorySha256=manifest.r2_inventory_sha256;
        const identity=createHash('sha256').update(JSON.stringify(receipt.identity)).digest('hex');
        const target=path.join(values.receipts,identity+'.json');
        const pending=path.join(values.receipts,identity+'.'+randomUUID()+'.pending');
        try {
          const file=await open(pending,'wx',0o600);
          try{await file.writeFile(JSON.stringify(receipt)+'\n');await file.sync();}finally{await file.close();}
          try{await link(pending,target);}
          catch(error){if(error.code!=='EEXIST')throw error;const old=JSON.parse(await readFile(target,'utf8'));if(old.sha256!==receipt.sha256||JSON.stringify(old.destination)!==JSON.stringify(receipt.destination))throw new Error('receipt_conflict');}
        } finally {await unlink(pending).catch(()=>{});}
      },
    });
    verified++;
  }
  process.stdout.write(JSON.stringify({verifiedStorageCopies:verified,sourceDeletes:0})+'\n');
}
