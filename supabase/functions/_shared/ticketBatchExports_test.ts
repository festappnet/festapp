import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { PageSizes, PDFDict, PDFDocument, PDFName, rgb } from "npm:pdf-lib";
import { unzipSync } from "npm:fflate@0.8.2";
import { batchSheetLayout, exportTicketBatch } from "./ticketBatchExports.ts";
import { digest } from "./ticketFonts.ts";

async function fixture(count = 9) {
  const pdf = await PDFDocument.create();
  pdf.addPage(PageSizes.A4).drawRectangle({
    x: 40,
    y: 500,
    width: 200,
    height: 300,
    color: rgb(1, 0, 0),
  });
  const bytes = await pdf.save(), hash = await digest(bytes);
  const documents = Array.from(
    { length: count },
    (_, n) => ({
      ordinal: n + 1,
      objectKey: `batch/single-${n + 1}.pdf`,
      bytes: bytes.length,
      digest: hash,
    }),
  );
  const manifest = {
    batchId: "batch",
    documents,
    template: { ticketArea: { x: 40, y: 41.89, width: 200, height: 300 } },
    abuseLimits: {
      "document.input.bytes": 4194304,
      "document.asset.bytes": 16777216,
      "document.output.bytes": 16777216,
      "document.output.pages": 20,
    },
  };
  return {
    bytes,
    manifest,
    store: {
      read: async () => bytes,
      create: async () => {
        throw new Error("Export must not write");
      },
    },
  };
}
Deno.test("A4 export crops empty original page and packs nine real tickets onto three sheets at physical size", async () => {
  const f = await fixture();
  const layout = batchSheetLayout(200, 300);
  assertEquals(layout.capacity, 4);
  assertEquals(layout.scale, 1);
  const output = await PDFDocument.load(
    await exportTicketBatch(f.manifest, "a4", f.store),
  );
  assertEquals(output.getPageCount(), 3);
  for (const page of output.getPages()) {
    assertEquals(page.getSize(), {
      width: layout.sheet[0],
      height: layout.sheet[1],
    });
  }
  // Distinct embedded ticket objects are retained; no ticket/QR is silently dropped.
  assertEquals(
    output.getPages().map((p) =>
      p.node.Resources()!.lookup(PDFName.of("XObject"), PDFDict).keys().length
    ),
    [4, 4, 1],
  );
});
Deno.test("a complete 200-ticket batch downloads as one 50-page A4 document", async () => {
  const f = await fixture(200);
  const output = await PDFDocument.load(
    await exportTicketBatch(f.manifest, "a4", f.store),
  );
  assertEquals(output.getPageCount(), 50);
});
Deno.test("ZIP contains each original frozen PDF byte for byte in ordinal order", async () => {
  const f = await fixture(200);
  const files = unzipSync(await exportTicketBatch(f.manifest, "zip", f.store));
  assertEquals(Object.keys(files).length, 200);
  assertEquals(Object.keys(files).slice(0, 2), [
    "ticket-001.pdf",
    "ticket-002.pdf",
  ]);
  assertEquals(files["ticket-001.pdf"], f.bytes);
  assertEquals(files["ticket-200.pdf"], f.bytes);
});
Deno.test("export rejects corrupt/missing bytes, foreign keys, incomplete sequence, invalid crop and output overflow", async () => {
  const f = await fixture(2);
  await assertRejects(() =>
    exportTicketBatch(f.manifest, "a4", {
      ...f.store,
      read: async () => new Uint8Array([1]),
    })
  );
  await assertRejects(() =>
    exportTicketBatch(f.manifest, "zip", { ...f.store, read: async () => null })
  );
  for (
    const change of [
      () => f.manifest.documents[0].objectKey = "foreign/file.pdf",
      () => f.manifest.documents[0].ordinal = 2,
    ]
  ) {
    const old = structuredClone(f.manifest.documents);
    change();
    await assertRejects(() => exportTicketBatch(f.manifest, "zip", f.store));
    f.manifest.documents = old;
  }
  f.manifest.template.ticketArea.x = 1000;
  await assertRejects(() => exportTicketBatch(f.manifest, "a4", f.store));
  f.manifest.abuseLimits["document.output.bytes"] = 1;
  await assertRejects(() => exportTicketBatch(f.manifest, "zip", f.store));
  assert(batchSheetLayout(800, 800).scale < 1);
});
