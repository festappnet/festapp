import test from 'node:test';
import assert from 'node:assert/strict';
// Executable contract oracle. Real SQL integration tests must agree with this
// model; this is not a substitute for database isolation/concurrency tests.
class Personal {
 constructor(){this.sequence=0;this.events=new Map();this.receipts=[];this.seen=0;this.revision=0;this.dirty=new Set();this.views=new Set();}
 deliver(id,count=1){if(!this.events.has(id))this.events.set(id,{sequence:++this.sequence,count,hidden:false,cancelled:false});}
 invalidate(id,patch){Object.assign(this.events.get(id),patch);this.revision++;this.dirty.add(id);}
 repair(){this.dirty.clear();}
 open(){if(this.dirty.size)return {state:'preparing'};if(this.views.size===4)return {state:'view_limit'};const v={sequence:this.sequence,revision:this.revision,ids:[...this.events].filter(([,e])=>!e.hidden&&!e.cancelled).map(([id])=>id)};this.views.add(v);this.seen=v.sequence;return v;}
 read(v){this.receipts.push(v.sequence);}
 render(v){if(this.dirty.size||v.revision!==this.revision)return {state:'preparing'};const ids=v.ids.filter(id=>this.events.has(id));return {ids,count:ids.reduce((n,id)=>n===null||this.events.get(id).count===null?null:n+this.events.get(id).count,0),read:ids.every(id=>this.events.get(id).sequence<=Math.max(0,...this.receipts))};}
 repairView(v){v.ids=v.ids.filter(id=>this.events.has(id)&&!this.events.get(id).hidden&&!this.events.get(id).cancelled);v.revision=this.revision;}
}
test('open is unacknowledged during repair, frozen membership survives later arrivals and reverse tab reads',()=>{
 const p=new Personal();for(let i=1;i<=100;i++)p.deliver(i);const first=p.open(),second=p.open();
 for(let i=101;i<=150;i++)p.deliver(i);p.read(second);p.read(first);
 assert.equal(p.render(first).count,100);assert.equal(p.render(first).read,true);assert.equal(p.seen,100);
 p.invalidate(1,{hidden:true});assert.deepEqual(p.open(),{state:'preparing'});assert.equal(p.seen,100);assert.deepEqual(p.render(first),{state:'preparing'});
 p.repair();p.repairView(first);assert.equal(p.render(first).count,99);
 p.invalidate(2,{cancelled:true});p.repair();p.repairView(first);assert.equal(p.render(first).count,98);
 assert.equal(p.open().sequence,150);
});
test('unknown totals, independent recipients and quotas never silently invent data or evict live views',()=>{
 const a=new Personal(),b=new Personal();a.deliver('unknown',null);a.deliver('known',2);b.deliver('known',2);
 assert.equal(a.render(a.open()).count,null);assert.equal(b.seen,0);
 a.open();a.open();a.open();assert.deepEqual(a.open(),{state:'view_limit'});assert.equal(a.views.size,4);
});
