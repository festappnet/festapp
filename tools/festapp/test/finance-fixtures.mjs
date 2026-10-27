import {setup as programSetup} from './program-fixtures.mjs';
import {readFile} from 'node:fs/promises';
export async function setup(t){const s=await programSetup(t);await s.db.query('RESET ROLE');
 await s.db.query(await readFile(new URL('../../../supabase/migrations/20261026220000_occasion_unit_configuration.sql',import.meta.url),'utf8'));
 for(const path of ['user_permissions/bank_operations.sql','eshop_bank_accounts/update_bank_account.sql','eshop_bank_accounts/update_bank_account_user.sql','eshop_bank_accounts/link_bank_account_to_unit.sql','eshop_bank_sync/bank_sync_manage.sql','organization_verification/profile_commands.sql','organization_verification/notifications.sql','others/duplicate_occasion_client_sync_v1.sql','others/add_image_record.sql','units/delete_unit.sql','eshop_orders/delete_order.sql','eshop_orders/delete_order_client_sync_v1.sql','eshop_orders/get_order_deletion_context_v1.sql','eshop_orders/delete_order_history.sql'])await s.db.query(await readFile(new URL('../../../database/functions/'+path,import.meta.url),'utf8'));
 await s.db.query(await readFile(new URL('../../../supabase/migrations/20261027190000_finance_authoring.sql',import.meta.url),'utf8'));
 await s.db.query('ALTER FUNCTION public.enqueue_unit_verification_request(bigint) OWNER TO postgres');
 await s.db.query('SET LOCAL ROLE authenticated');
 return{...s,bank:async(action,payload={},commandId=null)=>(await s.db.query('select manage_bank_authoring($1,$2,$3,$4,$5) value',[s.f.unit,s.f.org,action,payload,commandId])).rows[0].value};}
