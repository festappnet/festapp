import { assertEquals } from 'jsr:@std/assert@1';
import { PDFArray, PDFDict, PDFDocument, PDFName } from 'npm:pdf-lib';
import { generateTicketPdf } from './ticketGeneration.ts';
import { fontMetrics } from './ticketFonts.ts';
import { preset, pdfBox } from './ticketLayout.ts';
import { sampleData } from './ticketRenderData.ts';

const font = await Deno.readFile('supabase/functions/_shared/ticket-assets/font.ttf');
const resources = { font, metrics: fontMetrics(font) };

Deno.test('optional ticket gradient runs from top left to bottom right in PDF coordinates', async () => {
  const template = { ...preset('wide'), canvasGradient: ['14284B', 'A87F28'] };
  const result = await generateTicketPdf(sampleData(), resources, template);
  const pdf = await PDFDocument.load(result.bytes);
  const shadings = pdf.getPage(0).node.Resources()!.lookup(PDFName.of('Shading'), PDFDict);
  const gradient = shadings.lookup(PDFName.of('SharedGradient'), PDFDict);
  const coords = gradient.lookup(PDFName.of('Coords'), PDFArray);
  const area = pdfBox(template, { x: 0, y: 0, width: template.ticketArea.width, height: template.ticketArea.height });
  // PDF y increases upward: first color at the upper-left, last at the lower-right.
  assertEquals(coords.asArray().map(Number), [area.x, area.y + area.height, area.x + area.width, area.y]);
  const fn = gradient.lookup(PDFName.of('Function'), PDFDict);
  assertEquals(fn.lookup(PDFName.of('C0'), PDFArray).asArray().map(Number), [20 / 255, 40 / 255, 75 / 255]);
  assertEquals(fn.lookup(PDFName.of('C1'), PDFArray).asArray().map(Number), [168 / 255, 127 / 255, 40 / 255]);
});

Deno.test('one-color tickets do not acquire a PDF gradient', async () => {
  const result = await generateTicketPdf(sampleData(), resources, { ...preset('wide'), canvasColor: '14284B' });
  const pdf = await PDFDocument.load(result.bytes);
  assertEquals(pdf.getPage(0).node.Resources()!.has(PDFName.of('Shading')), false);
});
