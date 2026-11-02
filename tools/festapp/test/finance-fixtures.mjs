import {setup as programSetup} from './program-fixtures.mjs';
export async function setup(t){const s=await programSetup(t);await s.db.query('RESET ROLE');
 await s.db.query('SET LOCAL ROLE authenticated');
 return{...s,bank:async(action,payload={},commandId=null)=>(await s.db.query('select manage_bank_authoring($1,$2,$3,$4,$5) value',[s.f.unit,s.f.org,action,payload,commandId])).rows[0].value};}
