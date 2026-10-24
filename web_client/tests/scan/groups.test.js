import test from 'node:test';
import assert from 'node:assert/strict';
import {groupScannerTickets} from '../../src/components/scan/scanner_groups.js';
const item=(order_id,spot,holder_name='Same name')=>({symbol:spot,controller:{ticket:{order_id,spot,holder_name}}});
test('same order groups interleaved arrivals without losing original selection indexes',()=>{
 const items=[item(17,'Stůl 7 · místo 1'),item(18,'Stůl 7 · místo 3'),item(17,'Stůl 7 · místo 2')];
 const groups=groupScannerTickets(items);
 assert.equal(groups.length,2);assert.deepEqual(groups[0].items.map(i=>i.index),[0,2]);
 assert.equal(groups[0].sharedOrder,true);assert.equal(groups[0].table,'Stůl 7');
 assert.equal(groups[1].sharedOrder,false,'matching table and holder do not merge different orders');
 assert.equal(groups[0].items[1].controller,items[2].controller,'controller identity and pending confirmation are preserved');
});
test('unknown orders stay independent; mixed, missing and unstructured seats never imply a common table',()=>{
 assert.equal(groupScannerTickets([item(undefined,'A1'),item(undefined,'A2')]).length,2);
 for(const spots of [['Stůl 7 · místo 1','Stůl 8 · místo 2'],['Stůl 7 · místo 1',null],['A1','A2']]){
  const [g]=groupScannerTickets(spots.map(s=>item(1,s)));
  assert.equal(g.sharedOrder,true);assert.equal(g.table,null);
 }
});

test('table grouping uses blueprint identity for seat codes such as 28A, without guessing from seat text',()=>{
 const a=item(17,'28A'),b=item(17,'28B');
 a.controller.ticket.spot_group={blueprint_id:4,id:'28',title:'28'};
 b.controller.ticket.spot_group={blueprint_id:4,id:'28',title:'28'};
 assert.equal(groupScannerTickets([a,b])[0].table,'28');
 b.controller.ticket.spot_group.blueprint_id=5;
 assert.equal(groupScannerTickets([a,b])[0].table,null,'same group number in different blueprints is not a shared table');
 b.controller.ticket.spot_group=null;
 assert.equal(groupScannerTickets([a,b])[0].table,null,'missing structured reference never creates a guessed table');
});
