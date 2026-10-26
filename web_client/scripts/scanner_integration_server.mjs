// Loopback-only, test-only SQL adapter. Never part of the application build.
import QRCode from 'qrcode';import { createServer } from 'vite';import pg from 'pg';import { readFile } from 'node:fs/promises';import path from 'node:path';
const url=process.env.SCANNER_DATABASE_URL;if(!url)throw new Error('SCANNER_DATABASE_URL required');const u=new URL(url);
if(!['127.0.0.1','localhost'].includes(u.hostname)||!/^\/festapp_scanner_/.test(u.pathname))throw new Error('explicit isolated local database required');
const pool=new pg.Pool({connectionString:url});const root=path.resolve(import.meta.dirname,'..');
await pool.query(await readFile(path.join(root,'../database/tests/scanning/fixture.sql'),'utf8'));
const fixture=process.env.SCANNER_REUSE_FIXTURE_FILE?JSON.parse(await readFile(process.env.SCANNER_REUSE_FIXTURE_FILE,'utf8')):(await pool.query('select public.scanner_test_fixture(10000) fx')).rows[0].fx;
fixture.organization=(await pool.query('select organization from public.occasions where id=$1',[fixture.occasion])).rows[0].organization;
await pool.query("update public.scanner_settings set config=jsonb_set(config,'{manual_search,tickets}','true') where occasion_id=$1",[fixture.occasion]);
const signatures={open_scanner_session:['p_scan_code','p_occasion','p_device_name'],lookup_scanner_ticket:['p_session','p_token','p_symbol'],sync_scanner_operations:['p_session','p_token','p_operations'],get_scanner_receipts:['p_session','p_token','p_operation_ids'],get_scanner_summary:['p_session','p_token'],prepare_scanner_snapshot:['p_session','p_token'],get_scanner_snapshot_page:['p_session','p_token','p_snapshot','p_page'],search_scanner_tickets:['p_session','p_token','p_query','p_after'],revoke_scanner_session:['p_session','p_token']};
const rpcCounts={};
const server=await createServer({root,configFile:path.join(root,'vite.config.js'),server:{host:'127.0.0.1',port:5174,strictPort:true},plugins:[{name:'scanner-local-fixture',configureServer(s){s.middlewares.use(async(req,res,next)=>{
 try {
  const requestURL=new URL(req.url,'http://127.0.0.1:5174');
  let activeFixture=fixture,privateCatalog=null;
  if(process.env.SCANNER_REAL_FIXTURES_FILE && ['/__scanner-fixture','/__scanner-demo-scenes','/__scanner-demo-ticket','/__scanner-real-cases'].includes(requestURL.pathname)){
    privateCatalog=JSON.parse(await readFile(process.env.SCANNER_REAL_FIXTURES_FILE,'utf8'));
    const key=requestURL.searchParams.get('real');
    if(key){if(!Object.hasOwn(privateCatalog.events,key))throw Error('Unknown real sample');activeFixture=privateCatalog.events[key].fixture;}
  }
  if(requestURL.pathname==='/__scanner-real-cases'){
    const key=requestURL.searchParams.get('real'),selected=privateCatalog?.events[key];
    const events=Object.entries(privateCatalog?.events||{}).map(([key,event])=>({key,title:event.title}));
    const orders=await Promise.all((selected?.orders||[]).map(async order=>{
      const rows=(await pool.query('select state,count(*)::int n from eshop.tickets where occasion=$1 and ticket_symbol=any($2::text[]) group by state',[activeFixture.occasion,order.symbols])).rows;
      const counts=Object.fromEntries(rows.map(row=>[row.state,row.n]));
      const mixed=counts.used && (counts.sent||counts.paid);
      return {key:order.key,label:(mixed?'Použitá + platná · ':'')+order.label,symbols:order.symbols,counts,source_state:order.source_state,qr:await Promise.all(order.symbols.map(async symbol=>({symbol,svg:await QRCode.toString(symbol,{type:'svg',margin:4,width:240,errorCorrectionLevel:'M'})})))};
    }));
    res.setHeader('content-type','application/json');res.setHeader('cache-control','no-store');res.end(JSON.stringify({events,selected:key&&selected?{key,title:selected.title,captured_at:privateCatalog.captured_at,orders}:null}));return;
  }
  if(requestURL.pathname==='/__scanner-demo-scenes'){
    const unused=(await pool.query("select ticket_symbol symbol from eshop.tickets where occasion=$1 and state='sent' order by id desc limit 6",[activeFixture.occasion])).rows;
    const used=(await pool.query("select ticket_symbol symbol from eshop.tickets where occasion=$1 and state='used' order by id limit 1",[activeFixture.occasion])).rows[0];
    const symbols=[...unused.map(t=>t.symbol),used?.symbol].filter(Boolean);
    const qr=await Promise.all(symbols.map(async symbol=>({symbol,svg:await QRCode.toString(symbol,{type:'svg',margin:4,width:240,errorCorrectionLevel:'M'})})));
    res.setHeader('content-type','application/json');res.setHeader('cache-control','no-store');res.end(JSON.stringify({unused:unused.map(t=>t.symbol),used:used?.symbol,qr}));return;
  }
  if(requestURL.pathname==='/__scanner-demo-ticket'){
    const ticket=(await pool.query("select t.ticket_symbol symbol from eshop.tickets t where t.occasion=$1 and t.state='sent' and exists(select 1 from eshop.order_product_ticket opt join eshop.orders o on o.id=opt.\"order\" where opt.ticket=t.id and o.state='sent') order by t.id desc limit 1",[activeFixture.occasion])).rows[0];
    if(!ticket)throw new Error('No unused fixture ticket remains');
    ticket.qr=await QRCode.toString(ticket.symbol,{type:'svg',margin:4,width:240,errorCorrectionLevel:'M'});
    res.setHeader('content-type','application/json');res.setHeader('cache-control','no-store');res.end(JSON.stringify(ticket));return;
  }
  if(req.url==='/__scanner-translations'){res.setHeader('content-type','application/json');res.end(await readFile(path.join(root,'../assets/translations/cs.json')));return;}
  if(requestURL.pathname==='/__scanner-fixture'){res.setHeader('content-type','application/json');res.end(JSON.stringify(activeFixture));return;}
  if(req.url==='/__scanner-counts'){res.setHeader('content-type','application/json');res.end(JSON.stringify(rpcCounts));return;}
  if(process.env.SCANNER_PWA_DIR && req.method==='GET') {
    const uri=new URL(req.url,'http://127.0.0.1:5174');let target=uri.pathname;
    if(target==='/'||target.startsWith('/scan')||target==='/tests/scan/browser.html'||target==='/login-qr')target='/webclient';
    if(!target.includes('..'))try {const file=await readFile(path.join(process.env.SCANNER_PWA_DIR,target));res.setHeader('content-type',target.endsWith('.js')?'text/javascript':target.endsWith('.css')?'text/css':target.includes('webclient')?'text/html':'application/octet-stream');res.end(file);return;}catch{}
  }
  if(/^\/(scan(?:\/|$)|login-qr(?:\/|$))/.test(new URL(req.url,'http://127.0.0.1:5174').pathname)){req.url='/tests/scan/browser.html';return next();}
  if(req.url!=='/__scanner-rpc')return next();
  let raw='';for await(const chunk of req){raw+=chunk;if(raw.length>300000)throw new Error('request too large');}
  const {name,params}=JSON.parse(raw);if(!signatures[name])throw new Error('not permitted');
  const keys=signatures[name].filter(k=>params[k]!==undefined);const values=keys.map(k=>k==='p_operations'?JSON.stringify(params[k]):params[k]);
  const args=keys.map((k,i)=>`${k} => $${i+1}`).join(',');rpcCounts[name]=(rpcCounts[name]||0)+1;
  const result=await pool.query(`select public.${name}(${args}) result`,values);
  res.setHeader('content-type','application/json');res.end(JSON.stringify({data:result.rows[0].result,error:null}));
 }catch(error){res.setHeader('content-type','application/json');res.end(JSON.stringify({data:null,error:{message:error.message,code:error.code}}));}
 });}}]});await server.listen();console.log('Scanner isolated SQL/browser fixture: http://127.0.0.1:5174/tests/scan/browser.html (10000 tickets)');
for(const sig of ['SIGINT','SIGTERM'])process.on(sig,async()=>{await server.close();await pool.end();process.exit(0);});
