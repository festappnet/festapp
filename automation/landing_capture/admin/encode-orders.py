import pathlib,json,subprocess,os
base=pathlib.Path(os.environ['CAPTURE_OUTPUT']);out=pathlib.Path(os.environ['CAPTURE_EXPORT_DIR']);d=base/'orders-overview-v3-frames';cue=json.loads((base/'orders-overview-cue.json').read_text());frames=json.loads((d/'frames.json').read_text());start,end=cue['start'],cue['end'];before=[f for f in frames if f['time']<=start];selected=([dict(before[-1],time=start)] if before else [])+[f for f in frames if start<f['time']<end];lines=['ffconcat version 1.0']
for i,f in enumerate(selected):
 nxt=selected[i+1]['time'] if i+1<len(selected) else end
 lines += [f"file '{d/f['file']}'",'option framerate 30',f"duration {nxt-f['time']:.6f}"]
lines += [f"file '{d/selected[-1]['file']}'",'option framerate 30'];concat=base/'orders-overview.ffconcat';concat.write_text('\n'.join(lines)+'\n')
for suffix,filter in [('', 'crop=1340:580:0:187,scale=1200:520'),('-mobile','crop=540:600:280:237,scale=720:800')]:
 name='orders-overview'+suffix;dest=out/(name+'.mp4')
 subprocess.run(['ffmpeg','-v','error','-y','-safe','0','-i',str(concat),'-t',str(end-start),'-vf','fps=30,'+filter,'-c:v','libx264','-preset','medium','-crf','22','-pix_fmt','yuv420p','-movflags','+faststart','-an',str(dest)],check=True)
 subprocess.run(['ffmpeg','-v','error','-y','-ss','5.5','-i',str(dest),'-frames:v','1',str(base/(name+'-poster.png'))],check=True)
 subprocess.run(['cwebp','-quiet','-q','82',str(base/(name+'-poster.png')),'-o',str(out/(name+'.webp'))],check=True)
 print(name,round(end-start,2),dest.stat().st_size)
