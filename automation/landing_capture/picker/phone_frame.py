"""Wrap a genuine 390x844 viewport with a compact device frame, without cropping UI."""
import argparse,pathlib,struct,zlib,subprocess
W,H=426,900

def frame(path):
 def inside(x,y,l,t,r,b,rad):
  if not(l<=x<r and t<=y<b):return False
  cx=max(l+rad,min(x,r-rad-1));cy=max(t+rad,min(y,b-rad-1))
  return (x-cx)**2+(y-cy)**2<=rad**2
 rows=[]
 for y in range(H):
  row=bytearray()
  for x in range(W):
   c=(235,241,246,255)
   if inside(x,y,7,3,419,897,35):c=(21,29,45,255)
   if 18<=x<408 and 28<=y<872:c=(0,0,0,0)
   if inside(x,y,174,12,252,18,3):c=(80,91,110,255)
   if inside(x,y,169,881,257,886,2):c=(190,197,208,255)
   row.extend(c)
  rows.append(b'\0'+row)
 def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',W,H,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows)))+chunk(b'IEND',b''))

def main():
 p=argparse.ArgumentParser();p.add_argument('source',type=pathlib.Path);p.add_argument('output',type=pathlib.Path);a=p.parse_args();a.output.parent.mkdir(parents=True,exist_ok=True)
 overlay=a.output.parent/'phone-frame.png';frame(overlay)
 cmd=['ffmpeg','-v','error','-y','-i',str(a.source),'-i',str(overlay),'-filter_complex','[0:v]pad=426:900:18:28:color=0xebf1f6[screen];[screen][1:v]overlay=0:0:format=auto,format=yuv420p[out]','-map','[out]']
 cmd+=['-frames:v','1'] if a.output.suffix in ('.png','.jpg') else ['-c:v','libx264','-crf','19','-movflags','+faststart']
 subprocess.run(cmd+[str(a.output)],check=True)
if __name__=='__main__':main()
