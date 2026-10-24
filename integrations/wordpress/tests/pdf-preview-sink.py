"""Loopback browser access to one real canonical email attachment, not a fake ticket."""
import argparse,hashlib,json
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
ROOT=Path(__file__).resolve().parents[1];P=ROOT/'.private'
a=argparse.ArgumentParser();a.add_argument('pdf');a.add_argument('--port',type=int,default=59840);args=a.parse_args()
pdf=(P/args.pdf).resolve();assert pdf.is_relative_to(P.resolve()) and pdf.suffix=='.pdf' and pdf.read_bytes().startswith(b'%PDF-')
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path=='/':body=b'<!doctype html><meta name="viewport" content="width=device-width"><title>Local canonical email capture</title><h1>Local email capture</h1><p>Canonical queued ticket attachment; no provider send.</p><a href="/ticket.pdf" download="ticket.pdf">Download ticket PDF</a>';typ='text/html'
  elif self.path=='/ticket.pdf':body=pdf.read_bytes();typ='application/pdf'
  else:self.send_error(404);return
  self.send_response(200);self.send_header('Content-Type',typ);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
  with (P/'global-safari-pdf-access.jsonl').open('a') as f:f.write(json.dumps({'path':self.path,'status':200,'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest(),'user_agent':self.headers.get('User-Agent')})+'\n')
 def log_message(self,*args):pass
ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
