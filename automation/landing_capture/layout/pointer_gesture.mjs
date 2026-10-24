/** Native pointer gestures in the task-owned capture tab.
 * agent-browser handles normal interaction. CDP supplies held modifiers, which
 * the CLI's press command releases immediately and cannot carry across a drag.
 */
const [port,targetUrl,...args]=process.argv.slice(2);
if(!port||!targetUrl||!args.length)throw Error("Usage: gesture-cdp.mjs PORT EXACT_URL X0 Y0 X1 Y1 [Control|Shift]");
const path=args[0]==='--path'?JSON.parse(args[1]):[[+args[0],+args[1]],[+args[2],+args[3]]];
const modifier=args[0]==='--path'?(args[2]??'none'):(args[4]??'none');
const [[x0,y0]]=path,[x1,y1]=path.at(-1);
const target=(await(await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t=>t.type==='page'&&t.url===targetUrl);
if(!target)throw Error('Missing isolated capture tab');
const ws=new WebSocket(target.webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));let id=0;const waiting=new Map();
ws.addEventListener('message',e=>{const m=JSON.parse(e.data);const p=waiting.get(m.id);if(p){waiting.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}});
function send(method,params){return new Promise((resolve,reject)=>{waiting.set(++id,{resolve,reject});ws.send(JSON.stringify({id,method,params}))})}
const modifiers=modifier==='Control'?2:modifier==='Shift'?8:modifier==='Alt'?1:0,key=modifier,code=modifier+'Left',keyCode=modifier==='Control'?17:modifier==='Alt'?18:16;
try{
  await send('Input.dispatchMouseEvent',{type:'mouseMoved',x:+x0,y:+y0});
  if(modifiers)await send('Input.dispatchKeyEvent',{type:'keyDown',key,code,windowsVirtualKeyCode:keyCode,modifiers});
  await send('Input.dispatchMouseEvent',{type:'mousePressed',x:+x0,y:+y0,button:'left',clickCount:1,modifiers});
  for(let j=1;j<path.length;j++){const [ax,ay]=path[j-1],[bx,by]=path[j],steps=Math.max(12,Math.ceil(Math.hypot(bx-ax,by-ay)/9));for(let i=1;i<=steps;i++){const u=i/steps,t=u*u*(3-2*u);await send('Input.dispatchMouseEvent',{type:'mouseMoved',x:ax+(bx-ax)*t,y:ay+(by-ay)*t,button:'left',buttons:1,modifiers});await new Promise(r=>setTimeout(r,22));}}
  await send('Input.dispatchMouseEvent',{type:'mouseReleased',x:+x1,y:+y1,button:'left',clickCount:1,modifiers});
}finally{if(modifiers)await send('Input.dispatchKeyEvent',{type:'keyUp',key,code,windowsVirtualKeyCode:keyCode,modifiers:0});ws.close();}
