"""Recompose cached approved pixels only; protected rounded phone never color-keyed."""
import argparse,subprocess,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
def run(c):return subprocess.run(c,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
for suffix,w,h,box,answer in [('',1200,800,(315,23,354,754),(705,280,210,230,104,88,76)),('-mobile',500,1000,(55,45,370,790),(165,850,150,150,75,54,46))]:
 x,y,pw,ph=box;ax,ay,aw,ah,cx,cy,rad=answer
 # Rounded physical bezel crop, no UI pixels can enter an outside-color operation.
 alpha=f'if(lte(pow(max(abs(X-{pw/2})-({pw/2}-57),0),2)+pow(max(abs(Y-{ph/2})-({ph/2}-57),0),2),57*57),255,0)'
 # Answer symbol circle (including white glyph) and colored label only. Pending
 # background is excluded before the proven accepted timestamp. No phone keying.
 aa=f'if(gte(T,2.65)*lte(pow(X-{cx},2)+pow(Y-{cy},2),{rad-12}*{rad-12}),255,if(gt(max(r(X,Y),max(g(X,Y),b(X,Y)))-min(r(X,Y),min(g(X,Y),b(X,Y))),40),255,0))'
 graph=f"[0:v]split[p][a];[p]crop={pw}:{ph}:{x}:{y},format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='{alpha}'[phone];[a]crop={aw}:{ah}:{ax}:{ay},format=rgba,geq=r='if(gt(Y,{cy+rad+5}),248,r(X,Y))':g='if(gt(Y,{cy+rad+5}),250,g(X,Y))':b='if(gt(Y,{cy+rad+5}),252,b(X,Y))':a='{aa}'[answer];color=c=0x19243b:s={w}x{h}:r=30:d=8.5[matte];[matte][phone]overlay={x}:{y}[base];[base][answer]overlay={ax}:{ay},format=yuv420p[out]"
 out=a.output/('check-in'+suffix+'.mp4');run(['ffmpeg','-v','error','-y','-i',str(a.source/('check-in'+suffix+'.mp4')),'-filter_complex',graph,'-map','[out]','-t','8.5','-c:v','libx264','-crf','18','-movflags','+faststart',str(out)])
 for state,at in [('accepted','3.2'),('rejected','6.3')]:run(['ffmpeg','-v','error','-y','-ss',at,'-i',str(out),'-frames:v','1','-update','1',str(a.output/(state+suffix+'.png'))])
 run(['cwebp','-quiet','-q','92',str(a.output/('accepted'+suffix+'.png')),'-o',str(out.with_suffix('.webp'))])
print(a.output)
