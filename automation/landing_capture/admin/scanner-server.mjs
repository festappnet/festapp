import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const root=resolve(process.env.FESTAPP_REPO_ROOT||'.','web_client');
const {createServer}=await import(pathToFileURL(root+'/node_modules/vite/dist/node/index.js'));
const locale=process.env.CAPTURE_LOCALE||'cs';if(!['cs','en'].includes(locale))throw Error('Unsupported capture locale');
const privateDir=process.env.CAPTURE_PRIVATE_DIR;if(!privateDir)throw Error('Set CAPTURE_PRIVATE_DIR');
const db=process.env.CAPTURE_DATABASE_URL;if(!db||!['127.0.0.1','localhost'].includes(new URL(db).hostname))throw Error('Loopback database required');
import {createRequire} from 'node:module';import {readFile} from 'node:fs/promises';
const require=createRequire(root+'/package.json');const pg=require('pg');
const pool=new pg.Pool({connectionString:db});
const localEnv=await readFile(privateDir+'/local-env','utf8');const anon=localEnv.match(/^ANON_KEY="([^"]+)"/m)?.[1];if(!anon)throw Error('Missing local anon');
const fixture=JSON.parse(await readFile(privateDir+'/scanner-fixture.json'));
fixture.organization=(await pool.query('select organization from public.occasions where id=$1',[fixture.occasion])).rows[0].organization;
await pool.query('update public.occasions set title=$1 where id=$2',[locale==='cs'?'Ples pod hvězdami':'Ball under the stars',fixture.occasion]);
const methods={open_scanner_session:['p_scan_code','p_occasion','p_device_name'],lookup_scanner_ticket:['p_session','p_token','p_symbol'],sync_scanner_operations:['p_session','p_token','p_operations'],get_scanner_receipts:['p_session','p_token','p_operation_ids'],get_scanner_summary:['p_session','p_token'],prepare_scanner_snapshot:['p_session','p_token'],get_scanner_snapshot_page:['p_session','p_token','p_snapshot','p_page'],search_scanner_tickets:['p_session','p_token','p_query','p_after'],revoke_scanner_session:['p_session','p_token']};
const server=await createServer({root,configFile:false,server:{host:'127.0.0.1',port:56843,strictPort:true},plugins:[{name:'capture-fixture',transform(code,id){if(!id.endsWith('/src/app_config.js'))return;return code.replace(/static supabaseUrl = '[^']*'/, "static supabaseUrl = 'http://127.0.0.1:56831'").replace(/static anonKey = '[^']*'/,"static anonKey = '"+anon+"'").replace(/static webLink = [^;]+;/,"static webLink = 'http://127.0.0.1:56843';");},configureServer(s){s.middlewares.use(async(req,res,next)=>{try{
if(req.url==='/scan'){req.url='/__capture.html';}
if(req.url==='/__capture.html'){res.setHeader('content-type','text/html');res.end((await readFile(new URL('./scanner.html',import.meta.url),'utf8')).replaceAll('__LOCALE__',locale));return;}
if(req.url==='/qr'){res.setHeader('content-type','application/json');res.end(JSON.stringify(await require('qrcode').toDataURL('SCANNER-'+fixture.occasion+'-2',{width:320,margin:4})));return;}
if(req.url==='/fixture'){res.setHeader('content-type','application/json');res.end(JSON.stringify(fixture));return;}
if(req.url==='/translations'){res.setHeader('content-type','application/json');res.end(await readFile(root+'/../assets/translations/'+locale+'.json'));return;}
if(req.url!=='/rpc')return next();let raw='';for await(const chunk of req){raw+=chunk;if(raw.length>300000)throw Error('Too large');}const {name,params}=JSON.parse(raw);if(!methods[name])throw Error('Not allowed');const keys=methods[name].filter(k=>params[k]!==undefined);const result=await pool.query(`select public.${name}(${keys.map((k,i)=>k+' => $'+(i+1)).join(',')}) result`,keys.map(k=>k==='p_operations'?JSON.stringify(params[k]):params[k]));res.setHeader('content-type','application/json');res.end(JSON.stringify({data:result.rows[0].result,error:null}));
}catch(e){res.setHeader('content-type','application/json');res.end(JSON.stringify({data:null,error:{message:e.message,code:e.code}}));}})}}]});await server.listen();console.log('Capture scanner listening127.0.0.1:56843');for(const sig of ['SIGINT','SIGTERM'])process.on(sig,async()=>{await server.close();await pool.end();process.exit(0)});
