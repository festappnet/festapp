import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {openDisposableDatabase} from './postgres.mjs';
import {install as installFormSql} from './form-fixtures.mjs';
import {installCurrentMigrationOwners,installCurrentLayoutContract,installCurrentSql} from './current-sql.mjs';

export async function prepareCurrentDatabase(connection=process.env.FESTAPP_MCP_TEST_DATABASE_URL){
 if(!connection)return false;
 const db=await openDisposableDatabase(connection);
 try{
  await db.query('BEGIN');await installFormSql(db);
  await db.query(await readFile(new URL('../../../supabase/migrations/20261026220000_occasion_unit_configuration.sql',import.meta.url),'utf8'));
  await installCurrentMigrationOwners(db,['20261026220000_occasion_unit_configuration.sql']);
  await installCurrentLayoutContract(db);
  await installCurrentSql(db,['eshop_orders/operator_orders.sql']);
  await db.query('COMMIT');return true;
 }catch(error){await db.query('ROLLBACK');throw error;}finally{await db.end();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 if(await prepareCurrentDatabase())console.log('Current canonical local MCP SQL prepared.');
}
