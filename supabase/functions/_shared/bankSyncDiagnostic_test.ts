import {assertEquals,assertFalse} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {bankSyncAccountError,bankSyncLastFailure} from './bankSyncRemote.ts';
Deno.test('known legacy parse failures have an actionable cause without inventing a timestamp',()=>{
 assertEquals(bankSyncAccountError('Error: missing_statement_info'),'fio_invalid_response');
 assertEquals(bankSyncLastFailure({api_last_error:'Error: missing_statement_info',api_last_fetch_at:'2026-11-01 22:33:04'}),{version:1,code:'missing_statement_info',stage:'response_decode'});
});
Deno.test('diagnostic projection accepts only bounded safe fields and preserves historical failures',()=>{
 const source={version:1,id:'046aec2a-c9ef-4d94-8b1c-7bcf319d345a',occurred_at:'2026-11-01T22:33:04.000Z',code:'missing_statement_info',stage:'response_decode',operation:'transactions',transport:'proxy',http_status:200,document_shape:'object',statement_shape:'object',info_shape:'missing'};
 assertEquals(bankSyncLastFailure({api_last_error:null,api_last_failure:{...source,body:'private-bank-data',token:'private-token',url:'https://private.invalid'}}),source);
 const malformed=bankSyncLastFailure({api_last_failure:{...source,id:'private-token',occurred_at:'private',http_status:900,info_shape:'private'}})!;
 for(const key of ['id','occurred_at','http_status','info_shape'])assertFalse(key in malformed);
 assertEquals(bankSyncLastFailure({api_last_failure:{...source,code:['missing_statement_info']}}),null);
 assertEquals(bankSyncLastFailure({api_last_failure:{...source,code:'private-token'}}),null);
 assertEquals(bankSyncLastFailure({api_last_error:'private-token'}),null);
});
