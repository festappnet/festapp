import {indexProductCatalog,type ProductCatalog} from '../_shared/ticketRenderData.ts';

// Draft rows retain their stable local (negative) IDs. Prices and currency are
// read from the same saved form definition that the setup editor changes.
export function draftPreviewProducts(draft:any):ProductCatalog {
 const product_types:any[]=[],products:any[]=[];
 for(const field of draft.formDraft?.fields??[]) {
  const type=field.product_type_data;
  if(!type||!Number.isSafeInteger(type.id)||type.id===0)continue;
  const hidden=field.is_hidden===true;
  product_types.push({id:type.id,occasion:0,title:type.title??field.title??'',
   offered:!hidden,referenced:false,admission:!hidden&&type.type==='spot'});
  for(const product of type.products??[]) {
   products.push({...product,product_type:type.id,
    currency_code:product.currency_code??'CZK',is_hidden:hidden||product.is_hidden===true});
  }
 }
 return indexProductCatalog({product_types,products},0,true);
}
