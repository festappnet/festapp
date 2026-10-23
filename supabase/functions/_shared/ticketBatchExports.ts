import { PageSizes, PDFDocument } from "npm:pdf-lib";
import { zipSync } from "npm:fflate@0.8.2";
import { documentLimits } from "./documentLimits.ts";
import {
  type BatchObjectStore,
  readBatchStoredPdf,
} from "./ticketBatchDocuments.ts";

type Crop = { x: number; y: number; width: number; height: number };
export type BatchExportFormat = "a4" | "zip";
const margin = 18, gap = 12;

/** Preserve physical ticket size, choosing the A4 orientation with more slots.
 * Oversized tickets get a single sheet scaled down only as much as necessary. */
export function batchSheetLayout(width: number, height: number) {
  if (![width, height].every((v) => Number.isFinite(v) && v > 0)) {
    throw new Error("batch_export_dimensions");
  }
  return [PageSizes.A4, [...PageSizes.A4].reverse()].map((sheet) => {
    const scale = Math.min(
      1,
      (sheet[0] - 2 * margin) / width,
      (sheet[1] - 2 * margin) / height,
    );
    const w = width * scale, h = height * scale;
    const columns = Math.max(
      1,
      Math.floor((sheet[0] - 2 * margin + gap) / (w + gap)),
    );
    const rows = Math.max(
      1,
      Math.floor((sheet[1] - 2 * margin + gap) / (h + gap)),
    );
    return {
      sheet,
      scale,
      width: w,
      height: h,
      columns,
      rows,
      capacity: columns * rows,
    };
  }).sort((a, b) => b.capacity - a.capacity || b.scale - a.scale)[0];
}

/** Only server-authorized, digest-checked frozen singles enter either export. */
export async function exportTicketBatch(
  manifest: any,
  format: BatchExportFormat,
  store: BatchObjectStore,
) {
  if (format !== "a4" && format !== "zip") {
    throw new Error("batch_export_format");
  }
  const docs = manifest.documents, limits = documentLimits(manifest);
  if (!Array.isArray(docs) || docs.length < 1 || docs.length > 200) {
    throw new Error("batch_export_count");
  }
  let total = 0;
  for (let n = 0; n < docs.length; n++) {
    const d = docs[n];
    if (
      d.ordinal !== n + 1 || !Number.isSafeInteger(d.bytes) || d.bytes < 1 ||
      !d.objectKey?.startsWith(`${manifest.batchId}/`)
    ) throw new Error("batch_export_manifest");
    total += d.bytes;
  }
  if (total > limits.outputBytes) throw new Error("batch_export_size");
  const entries: Record<string, Uint8Array> = {};
  const output = format === "a4" ? await PDFDocument.create() : undefined;
  const crop: Crop = manifest.template?.ticketArea;
  const sheet = output
    ? batchSheetLayout(crop?.width, crop?.height)
    : undefined;
  let page: ReturnType<PDFDocument["addPage"]> | undefined;
  for (let n = 0; n < docs.length; n++) {
    const bytes = await readBatchStoredPdf(docs[n], store);
    if (!output) {
      entries[`ticket-${String(docs[n].ordinal).padStart(3, "0")}.pdf`] = bytes;
      continue;
    }
    const single = await PDFDocument.load(bytes);
    if (single.getPageCount() !== 1) {
      throw new Error("batch_export_single_page");
    }
    const source = single.getPage(0), top = source.getHeight() - crop.y;
    if (
      ![crop.x, crop.y, crop.width, crop.height].every(Number.isFinite) ||
      crop.x < 0 || crop.y < 0 ||
      crop.x + crop.width > source.getWidth() + .01 ||
      crop.y + crop.height > source.getHeight() + .01
    ) throw new Error("batch_export_crop");
    const embedded = await output.embedPage(source, {
      left: crop.x,
      bottom: top - crop.height,
      right: crop.x + crop.width,
      top,
    });
    const slot = n % sheet!.capacity;
    if (slot === 0) page = output.addPage(sheet!.sheet as [number, number]);
    const column = slot % sheet!.columns,
      row = Math.floor(slot / sheet!.columns);
    page!.drawPage(embedded, {
      x: margin + column * (sheet!.width + gap),
      y: sheet!.sheet[1] - margin - sheet!.height - row * (sheet!.height + gap),
      width: sheet!.width,
      height: sheet!.height,
    });
  }
  // PDF streams are already compressed; storing ZIP entries avoids redundant CPU work.
  const bytes = output ? await output.save() : zipSync(entries, { level: 0 });
  if (bytes.length > limits.outputBytes) throw new Error("batch_export_size");
  return bytes;
}
