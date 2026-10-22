from http.server import BaseHTTPRequestHandler,HTTPServer
from pathlib import Path
import hashlib,json
root=Path('/Users/miakh/source/festapp-setup-usability-20261021/vendor/blueprint/venue_seat_picker/assets/layout_fonts')
fonts={hashlib.sha256(p.read_bytes()).hexdigest()+'.ttf':p.read_bytes() for p in root.glob('Roboto-*.ttf')}
secret='local-wizard-font-fixture-20261021-only'
env=Path('/Users/miakh/source/festapp-wizard-usability-main-20261021/font-fixture.env');env.write_text('TICKET_FONT_SERVICE_URL=http://host.docker.internal:56885/service/ticket-fonts/\nTICKET_FONT_SERVICE_SECRET='+secret+'\n');env.chmod(0o600)
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.headers.get('Authorization')!='Bearer '+secret:self.send_error(403);return
  name=self.path.removeprefix('/service/ticket-fonts/sha256/')
  if not self.path.startswith('/service/ticket-fonts/sha256/') or name not in fonts:self.send_error(404);return
  self.send_response(200);self.send_header('Content-Length',str(len(fonts[name])));self.end_headers();self.wfile.write(fonts[name])
 def log_message(self,*args):pass
print('Local immutable font fixture ready',flush=True)
HTTPServer(('127.0.0.1',56885),Handler).serve_forever()
