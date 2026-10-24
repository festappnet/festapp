"""Encode timestamped native frames; discard only Chrome's off-viewport surface."""
import json,pathlib,subprocess,sys

def encode(take, output, width, height):
    take=pathlib.Path(take); output=pathlib.Path(output)
    frames=json.loads((take/'frames.json').read_text())
    cues=json.loads((take/'cues.json').read_text())['cues']
    end=cues[-1]['time']; start=frames[0]['time']
    normalized=take/'viewport'; normalized.mkdir(exist_ok=True)
    manifest=['ffconcat version 1.0']
    for i,frame in enumerate(frames):
        target=normalized/frame['file']
        # Chromium's minimum outer window can be wider than emulated viewport.
        # Normalize before concat: filter reinitialization otherwise changes timebase.
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(take/frame['file']),'-vf',f'crop={width}:{height}:0:0','-frames:v','1','-q:v','2',str(target)],check=True)
        next_time=frames[i+1]['time'] if i+1<len(frames) else end
        manifest += [f"file '{target}'",'option framerate 30',f'duration {max(.001,next_time-frame["time"]):.6f}']
    manifest += [f"file '{normalized/frames[-1]['file']}'",'option framerate 30']
    (take/'frames.ffconcat').write_text('\n'.join(manifest)+'\n')
    subprocess.run(['ffmpeg','-v','error','-y','-safe','0','-i',str(take/'frames.ffconcat'),'-t',str(end-start),'-vf','fps=30,format=yuv420p','-c:v','libx264','-crf','20','-movflags','+faststart',str(output)],check=True)
    return end-start

if __name__=='__main__':
    print(f'Encoded {encode(sys.argv[1],sys.argv[2],int(sys.argv[3]),int(sys.argv[4])):.2f}s')
