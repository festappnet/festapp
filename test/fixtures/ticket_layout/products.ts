import {preset,type Template} from '../../../supabase/functions/_shared/ticketLayout.ts';
export const rawCatalog={product_types:[{id:123,occasion:7,title:'VIP menu',type:'anything',offered:true,referenced:true},{id:124,occasion:7,title:'Odvoz',type:'anything',offered:true,referenced:true}],products:[
 {id:1,product_type:123,title:'Plný název',short_title:'  ',data:{short_title:' Řízek '},price:0,currency_code:'CZK',order:2},
 {id:2,product_type:123,title:'Skrytá historická večeře',is_hidden:true,price:170,currency_code:'CZK',order:1},
 {id:3,product_type:124,title:'Autobus',price:50,currency_code:'CZK',order:1},
]};
export function productTemplate():Template {
 const t=preset('wide');
 t.elements.push({id:'vip',binding:'productType',productTypeId:123,label:'VIP menu',visible:true,locked:false,box:{x:10,y:10,width:180,height:24},style:{fontSize:12,minFontSize:6,maxLines:2,color:'2A2A2A',align:'left'}});
 t.elements.push({...structuredClone(t.elements.at(-1)!),id:'transport',productTypeId:124,label:'',box:{x:10,y:40,width:180,height:24}});
 return t;
}
