// Native input only, on the exact isolated browser target opened by the wrapper.
const [port,url,seat]=process.argv.slice(2);
const targets=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const pages=targets.filter(t=>t.type==='page'&&!t.url.startsWith('chrome://'));
if(pages.length!==1||pages[0].url!==url)throw Error('Expected exactly the owned capture tab');
const ws=new WebSocket(pages[0].webSocketDebuggerUrl),pending=new Map();let seq=0;
await new Promise(r=>ws.addEventListener('open',r,{once:true}));
ws.addEventListener('message',({data})=>{const m=JSON.parse(data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}});
const call=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const box=(await call('Runtime.evaluate',{expression:`JSON.stringify(document.querySelector('[data-seat-id="${seat}"]').getBoundingClientRect().toJSON())`,returnByValue:true})).result.value;
const b=JSON.parse(box),sx=b.x+b.width/2,sy=b.y+b.height/2;
// One continuous two-finger gesture, translating towards the visible centre
// while the finger distance grows smoothly from 24 to 120px (5x zoom).
const points=(t)=>{const ease=t*t*(3-2*t),x=sx+(165-sx)*ease,y=sy+(270-sy)*ease,r=12+48*ease;return [{x:x-r,y,id:1},{x:x+r,y,id:2}];};
await call('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:points(0)});
for(let i=0;i<=90;i++){await call('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:points(i/90)});await wait(25);}
await call('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});ws.close();
