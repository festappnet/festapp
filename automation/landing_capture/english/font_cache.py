"""Disposable authenticated font-cache transport for real canonical font bytes.

Implements the existing font-store GET/immutable PUT contract on loopback only.
No font IDs, shaping, renderer, provider responses or UI state are substituted.
"""
from http.server import BaseHTTPRequestHandler,HTTPServer
from pathlib import Path
import argparse,re,hashlib,hmac
p=argparse.ArgumentParser();p.add_argument('--directory',type=Path,required=True);p.add_argument('--env-file',type=Path,required=True);a=p.parse_args();a.directory.mkdir(parents=True,exist_ok=True)
env=dict(line.split('=',1) for line in a.env_file.read_text().splitlines() if '=' in line);secret=env['TICKET_FONT_SERVICE_SECRET'];assert len(secret)>=32
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def handle_request(self,write=False):
  if not hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+secret):self.send_error(403);return
  match=re.fullmatch(r'/service/ticket-fonts/sha256/([a-f0-9]{64}\.(?:ttf|woff|metrics-v1\.json))',self.path)
  if not match:self.send_error(404);return
  f=a.directory/match[1]
  if write:
   size=int(self.headers.get('Content-Length','0'))
   if not 0<size<=8*1024*1024:self.send_error(413);return
   data=self.rfile.read(size)
   if f.suffix in ('.ttf','.woff') and hashlib.sha256(data).hexdigest()!=f.stem:self.send_error(400);return
   try:
    with f.open('xb') as stream:stream.write(data)
   except FileExistsError:self.send_response(409);self.end_headers();return
   self.send_response(201);self.end_headers();return
  if not f.exists():self.send_error(404);return
  data=f.read_bytes();self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 def do_GET(self):self.handle_request()
 def do_PUT(self):self.handle_request(True)
HTTPServer(('127.0.0.1',57382),Handler).serve_forever()
