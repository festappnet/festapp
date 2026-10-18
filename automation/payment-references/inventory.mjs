#!/usr/bin/env node
// Read-only operator inventory. Generates review artifacts; never imports/activates.
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const args=process.argv.slice(2),org=args[args.indexOf('--organization-id')+1],destination=args[args.indexOf('--output-dir')+1];
if(!args.includes('--organization-id')||!/^\d+$/.test(org??'')||BigInt(org)<1||!args.includes('--output-dir')||!destination||!process.env.DATABASE_URL){
 throw Error('Require DATABASE_URL, --organization-id <selected organization> and --output-dir <new directory>');
}
const canonical=value=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])])):value;
const hash=value=>createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
const quote=value=>"'"+String(value).replaceAll("'","''")+"'";
const number=value=>{if(!/^\d+$/.test(String(value)))throw Error('Invalid numeric inventory field');return String(value);};
const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();
try{
 await db.query('BEGIN READ ONLY');
 const organization=(await db.query('SELECT id FROM public.organizations WHERE id=$1',[org])).rows[0];
 if(!organization)throw Error('Selected organization does not exist');
 const accounts=(await db.query(`SELECT DISTINCT b.id,b.account_number,
  public.try_payment_reference_account_internal(b.account_number) AS canonical_account
  FROM eshop.bank_accounts b JOIN eshop.unit_bank_accounts u ON u.bank_account=b.id
  JOIN public.units unit ON unit.id=u.unit WHERE unit.organization=$1 AND b.type IS DISTINCT FROM 'CASH' ORDER BY b.id`,[org])).rows;
 const receiving=accounts.map(a=>a.canonical_account).filter(Boolean);
 const payments=(await db.query(`SELECT p.id,p.bank_account,p.variable_symbol,p.currency_code,ord.form,
   public.try_payment_reference_account_internal(b.account_number) AS canonical_account,
   r.source_ref AS existing_source
  FROM eshop.payment_info p JOIN eshop.bank_accounts b ON b.id=p.bank_account
  LEFT JOIN LATERAL(SELECT min(form) AS form FROM eshop.orders WHERE payment_info=p.id) ord ON true
  LEFT JOIN eshop.payment_reference_reservations r ON r.payment_info_id=p.id
  WHERE p.amount>0 AND p.variable_symbol IS NOT NULL AND public.try_payment_reference_account_internal(b.account_number)=ANY($1::text[])
  ORDER BY canonical_account,p.variable_symbol,p.id`,[receiving])).rows;
 await db.query('ROLLBACK');
 const seen=new Map(),conflicts=[];
 for(const p of payments){const key=p.canonical_account+':'+p.variable_symbol;if(seen.has(key)&&seen.get(key)!==p.id)conflicts.push({namespace:p.canonical_account,symbol:p.variable_symbol,payments:[seen.get(key),p.id]});seen.set(key,p.id);}
 const rows=payments.map(p=>({...p,source_ref:p.existing_source??`legacy:payment:${p.id}`,payload_sha256:hash({payment:p.id,bank:p.bank_account,symbol:p.variable_symbol,form:p.form})}));
 const manifest={version:1,owner:'Festapp',organization_id:org,coverage:'current positive payment rows only; deleted history and issued archives require separate review',accounts,payments:rows,conflicts,invalid_accounts:accounts.filter(a=>!a.canonical_account)};
 const digest=hash(manifest),dir=path.resolve(destination);await mkdir(dir,{mode:0o700});
 await writeFile(path.join(dir,'manifest.json'),JSON.stringify({manifest_sha256:digest,...manifest},null,2)+'\n',{mode:0o600});
 if(conflicts.length||manifest.invalid_accounts.length){console.error('Inventory blocked: review manifest conflicts/invalid accounts. No import SQL generated.');process.exitCode=2;}
 else{
  const sql=[`-- Selected organization ${org}; manifest SHA-256 ${digest}`,'-- Review archives/shared writers and separately authorize historical writes before executing.','BEGIN;',"SET LOCAL request.jwt.claim.role='service_role';"];
  for(const a of accounts)sql.push(`SELECT public.enroll_payment_reference_account(${number(a.id)});`);
  for(const p of rows.filter(p=>!p.existing_source))sql.push(`SELECT public.import_payment_reference(${number(p.bank_account)},${quote(p.source_ref)},${number(p.variable_symbol)},${quote(p.payload_sha256)},${number(p.id)},${p.form===null?'NULL':number(p.form)});`);
  sql.push('COMMIT;');await writeFile(path.join(dir,'reviewed-import.sql'),sql.join('\n')+'\n',{mode:0o600});
  console.info(JSON.stringify({organization_id:org,accounts:accounts.length,payments:rows.length,manifest_sha256:digest,coverage:manifest.coverage}));
 }
}finally{await db.end();}
