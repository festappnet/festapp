import { assertEquals } from 'jsr:@std/assert@1';
import { handlePreview, type PreviewDependencies } from './handler.ts';
import { futuraId, fontMetrics } from '../_shared/ticketFonts.ts';

const bytes = await Deno.readFile('supabase/functions/_shared/ticket-assets/font.ttf');
const admission = {abuseLimits:{'document.input.bytes':1048576,'document.asset.bytes':5242880,'document.output.bytes':16777216,'document.output.pages':20}};
const request = (body:unknown) => new Request('https://fixture.invalid', {method:'POST',headers:{Authorization:'Bearer geometry-editor'},body:JSON.stringify(body)});

Deno.test('geometry editor can load shared fonts without gaining ticket preview access', async () => {
  const modes: unknown[] = [];
  const deps: PreviewDependencies = {
    authorize: async (_header,_occasion,_bytes,_readOnly,...resource) => {
      modes.push(resource[0]);
      return resource[0] === 'font' ? admission : false;
    },
    font: async () => ({id:futuraId,bytes,metrics:fontMetrics(bytes),family:'Futura PT',weight:400}),
    occasion: async () => {throw Error('Font request must not read occasion data');},
    products: async () => {throw Error('No product access');},
    resources: async () => {throw Error('No ticket resource access');},
  };
  const font = await handlePreview(request({occasionId:7,mode:'font',fontProtocol:2,fontId:futuraId}),deps);
  assertEquals(font.status,200);
  assertEquals((await font.json()).id,futuraId);
  for(const mode of ['resolve','pdf']) {
    assertEquals((await handlePreview(request({occasionId:7,mode,type:'wide',fontProtocol:2}),deps)).status,403);
  }
  assertEquals(modes,['font',undefined,undefined]);
});
