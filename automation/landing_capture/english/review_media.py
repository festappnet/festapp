"""Generate a server-free review of every required localized video export."""
import argparse,json,base64
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[3]
m=json.loads((root/'automation/release/organizers/clips.en.json').read_text());used={i for s in m['sections'] for i in s['clips']}|{m['hero']};rows=[]
for c in m['clips']:
 if c['id'] in used:
  for key in ('src','mobileSrc'):
   rows.append({'id':c['id']+(' mobile' if key=='mobileSrc' else ' desktop'),'src':'data:video/mp4;base64,'+base64.b64encode((root/'web'/c[key].lstrip('/')).read_bytes()).decode('ascii')})
a.output.write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><title>English product media review</title><style>body{font:16px system-ui;background:#edf1f6;color:#142238;margin:24px}main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}video{width:100%;height:330px;background:#111}article{min-width:0}pre{white-space:pre-wrap}</style><h1>English product media review</h1><p>Actual English UI. Desktop and mobile exports. Playback runs in bounded groups of four.</p><button id="run">Play and verify all 16 variants</button><pre id="status">Ready</pre><main></main><script>
const media='''+json.dumps(rows)+''';window.mediaEvidence=[];let running=false;
for(const [i,row] of media.entries()){const a=document.createElement('article');a.innerHTML='<h2></h2><video controls muted playsinline preload="metadata"></video>';a.querySelector('h2').textContent=row.id;const v=a.querySelector('video');v.src=row.src;v.id='clip-'+i;document.querySelector('main').append(a);}
async function check(row,i){const v=document.getElementById('clip-'+i);const started=performance.now();await new Promise(async(resolve,reject)=>{const timeout=setTimeout(()=>reject(Error('Playback timeout: '+row.id)),100000);v.onended=()=>{clearTimeout(timeout);resolve()};v.onerror=()=>reject(Error('Media failed: '+row.id));v.currentTime=0;await v.play();});const full=performance.now()-started;v.currentTime=Math.min(.5,v.duration/2);await new Promise(r=>v.addEventListener('seeked',r,{once:true}));window.mediaEvidence.push({id:row.id,fullPlayback:'pass',seek:'pass',duration:v.duration,width:v.videoWidth,height:v.videoHeight,wallMs:Math.round(full)});document.getElementById('status').textContent=JSON.stringify(window.mediaEvidence,null,2);}
document.getElementById('run').onclick=async()=>{if(running)return;running=true;try{for(let i=0;i<media.length;i+=4)await Promise.all(media.slice(i,i+4).map((r,j)=>check(r,i+j)));window.mediaComplete=true;}catch(e){window.mediaError=e.message;document.getElementById('status').textContent=e.message;}};
</script></html>''');print(a.output)
