#!/usr/bin/env python3
"""Run ticket email preparation in a real isolated Edge user worker."""
import base64
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FUNCTIONS = ROOT / 'supabase/functions'
PINS = ROOT / 'automation/hetzner-supabase/runtime/pins.json'
IMAGE = json.loads(PINS.read_text())['supabase']['images']['edgeRuntime']
RESULT = 'FESTAPP_TICKET_EMAIL_USER_WORKER '

MAIN = r"""
Deno.serve(async request => {
  const worker = await EdgeRuntime.userWorkers.create({
    servicePath: '/fixture/worker',
    memoryLimitMb: 512,
    workerTimeoutMs: 20_000,
    envVars: [],
  });
  return worker.fetch(request);
});
setTimeout(async () => {
  try {
    const response = await fetch('http://127.0.0.1:9000/test');
    const result = await response.json();
    console.log('FESTAPP_TICKET_EMAIL_USER_WORKER ' + JSON.stringify(result));
  } catch (error) {
    console.log('FESTAPP_TICKET_EMAIL_USER_WORKER ' + JSON.stringify({error: String(error)}));
  }
}, 100);
"""

WORKER = r"""
import { TicketFontResolver, fontCatalog } from '../_shared/ticketFonts.ts';
import { prepareTicketDelivery } from '../_shared/ticketDelivery.ts';
import { drainEmails } from '../_shared/emailDispatcher.ts';
import { preset } from '../_shared/ticketLayout.ts';
import { PDFDocument } from 'npm:pdf-lib';

Deno.serve(async () => {
  try {
    const asset = fontCatalog.find(f => f.family === 'Archivo' && f.weight === 400 && f.style === 'normal')!;
    const font = await new TicketFontResolver({
      bundled: async () => null,
      store: {read: async () => null, create: async () => true},
      fetch: async () => new Response(Uint8Array.from(atob(fontBase64), char => char.charCodeAt(0))),
    }).resolve(asset.id);
    const template = preset('named');
    template.fontId = font.id;
    const event = {id: 7, locale: 'cs', title: 'Maturitní ples EDUCAnet Praha', features: [{
      code: 'ticket', is_enabled: true, ticket_type: 'named', layout: {schemaVersion: 3, templates: {named: template}},
    }]};
    const tickets = [1, 2].map(id => ({id, occasion: 7, state: 'paid', ticket_symbol: 'SAMPLE000' + id}));
    let pending = true;
    let sent = 0;
    let failed = 0;
    const {claimed} = await drainEmails({
      now: Date.now,
      rpc: async name => {
        if (name === 'claim_email' && pending) {
          pending = false;
          return {message_id: 'fixture', attempt_id: 'fixture', lease_token: 'fixture', prepared: null};
        }
        if (name === 'finish_email_attempt') failed++;
        return null;
      },
      prepare: async () => {
        const delivery = await prepareTicketDelivery(event, {}, tickets, async (...args) => {
          const { prepareTicketRenderer } = await import('../_shared/ticketGeneration.ts');
          return prepareTicketRenderer(...args, {
            load: async () => ({fonts: {[font.id]: font}, font: font.bytes, metrics: font.metrics}),
            products: async () => ({products: [], product_types: []}),
          });
        });
        return {prepared: delivery.attachments, postAction: {}};
      },
      seal: async prepared => prepared,
      send: async row => {
        for (const attachment of row.prepared) {
          if (attachment.contentType !== 'application/pdf' ||
             (await PDFDocument.load(attachment.content)).getPageCount() !== 1) throw new Error('Invalid attachment');
          sent++;
        }
      },
    });
    return Response.json({claimed, sent, failed});
  } catch (error) {
    return Response.json({error: String(error)}, {status: 500});
  }
});
"""

with tempfile.TemporaryDirectory(prefix='.ticket-email-worker-', dir=ROOT) as temporary:
    fixture = Path(temporary)
    for directory in ('main', 'worker'):
        (fixture / directory).mkdir()
    for directory in ('_shared', 'fetch-http-data'):
        shutil.copytree(FUNCTIONS / directory, fixture / directory)
    shutil.copyfile(FUNCTIONS / 'deno.lock', fixture / 'deno.lock')
    font = base64.b64encode((ROOT / 'test/fixtures/ticket_fonts/Archivo.ttf').read_bytes()).decode()
    (fixture / 'main/index.ts').write_text(MAIN)
    (fixture / 'worker/index.ts').write_text(f'const fontBase64 = {json.dumps(font)};\n' + WORKER)
    result = subprocess.run([
        'docker', 'run', '--rm', '--entrypoint', 'timeout',
        '--mount', f'type=bind,source={fixture},target=/fixture,readonly',
        IMAGE, '45s', 'edge-runtime', 'start', '--ip', '127.0.0.1',
        '--port', '9000', '--main-service', '/fixture/main', '--policy', 'per_request',
    ], capture_output=True, text=True, timeout=260)
    output = result.stdout + result.stderr
    lines = [line.split(RESULT, 1)[1] for line in output.splitlines() if RESULT in line]
    if not lines or json.loads(lines[-1]) != {'claimed': 1, 'sent': 2, 'failed': 0}:
        raise SystemExit(output[-5000:])
    print('Isolated Edge worker prepared both Archivo Regular PDF attachments and reached the sender.')
