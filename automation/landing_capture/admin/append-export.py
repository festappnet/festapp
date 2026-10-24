import pathlib,json,subprocess,os,shutil,os
base=pathlib.Path(os.environ['CAPTURE_OUTPUT']);out=pathlib.Path(os.environ['CAPTURE_EXPORT_DIR']);d=base/'orders-export-final-frames';cue=json.loads((base/'orders-export-final-cue.json').read_text());frames=json.loads((d/'frames.json').read_text());start,end=cue['start'],cue['end'];before=[f for f in frames if f['time']<=start];selected=([dict(before[-1],time=start)] if before else [])+[f for f in frames if start<f['time']<end];lines=['ffconcat version 1.0']
for i,f in enumerate(selected):
 nxt=selected[i+1]['time'] if i+1<len(selected) else end
 lines += [f"file '{d/f['file']}'",'option framerate 30',f"duration {nxt-f['time']:.6f}"]
lines += [f"file '{d/selected[-1]['file']}'",'option framerate 30'];concat=base/'orders-export-final.ffconcat';concat.write_text('\n'.join(lines)+'\n')
for suffix,filter in [('', 'crop=820:356:0:45,scale=1200:520'),('-mobile','crop=600:666:0:50,scale=720:800')]:
 name='orders-overview'+suffix;dest=out/(name+'.mp4');source=base/(name+'-before-export.mp4');shutil.copy2(dest,source);segment=base/(name+'-export-segment.mp4')
 subprocess.run(['ffmpeg','-v','error','-y','-safe','0','-i',str(concat),'-t',str(end-start),'-vf','fps=30,'+filter,'-c:v','libx264','-preset','medium','-crf','22','-pix_fmt','yuv420p','-movflags','+faststart','-an',str(segment)],check=True)
 subprocess.run(['ffmpeg','-v','error','-y','-i',str(source),'-i',str(segment),'-filter_complex','[0:v]trim=duration=5.2,setpts=PTS-STARTPTS,setsar=1[a];[1:v]setsar=1[b];[a][b]concat=n=2:v=1:a=0[v]','-map','[v]','-c:v','libx264','-crf','22','-pix_fmt','yuv420p','-movflags','+faststart','-an',str(dest)],check=True)
 subprocess.run(['ffmpeg','-v','error','-y','-ss','7.4','-i',str(dest),'-frames:v','1',str(base/(name+'-export-poster.png'))],check=True)
 subprocess.run(['cwebp','-quiet','-q','82',str(base/(name+'-export-poster.png')),'-o',str(out/(name+'.webp'))],check=True)
 print(name,dest.stat().st_size)
