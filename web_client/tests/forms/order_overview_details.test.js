import test from 'node:test';
import assert from 'node:assert/strict';
import {overviewItemChanges} from '../../src/components/forms/order_overview_details.js';
test('history diff preserves duplicate instances and separates tickets',()=>{
 const a={ticketId:1,id:10,title:'Dinner',price:100}, b={...a,ticketId:2};
 const result=overviewItemChanges([a,a,b],[a,{...b,price:150},{ticketId:2,id:11,title:'Seat',price:50}]);
 assert.deepEqual(result.map(c=>c.kind),['removed','changed','added']);
 assert.equal(result[0].before.ticketId,1);
 assert.equal(result[1].before.price,100); assert.equal(result[1].after.price,150);
 assert.deepEqual(overviewItemChanges([a,b],[b,a]),[]);
});
