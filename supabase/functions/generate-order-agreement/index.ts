import { PDFDocument, rgb, PageSizes, PDFFont } from "npm:pdf-lib";
import * as fontkit from "npm:fontkit";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { authorizeRequest, AuthError } from "../_shared/auth.ts";
import {
  aggregateMetaSurchargeSums,
  extractMetaSurcharge,
  formatSignedMetaSurcharge,
  MetaSurchargeAmount,
} from "../_shared/metaSurcharge.ts";
import { Buffer } from "node:buffer";
import { AgreementConfig, parseAgreementConfig } from "./agreementConfig.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// --- HELPER FUNCTIONS ---
function findFieldDataByType(fields: any[], formFields: any, type: string): any {
  if (!fields || !formFields) return null;
  const fieldDefinition = Object.values(formFields).find((field: any) => field.type === type);
  if (!fieldDefinition) return null;

  const fieldId = (fieldDefinition as any).id.toString();
  const fieldData = fields.find(f => f && f[fieldId] !== undefined);
  return fieldData ? fieldData[fieldId] : null;
}

function formatDate(isoString: string | null): string {
    if (!isoString) return "";
    try {
        const date = new Date(isoString);
        if (isNaN(date.getTime())) return "";
        const day = String(date.getDate()).padStart(2, '0');
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const year = date.getFullYear();
        return `${day}.${month}.${year}`;
    } catch (e) {
        return "";
    }
}

// --- PDF GENERATION LOGIC ---
async function generateAgreement(data: any, config: AgreementConfig): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.create();
  pdfDoc.registerFontkit(fontkit);

  const page = pdfDoc.addPage(PageSizes.A4);
  const { width, height } = page.getSize();

  let font: PDFFont, boldFont: PDFFont;
  try {
    const fontResponse = await fetch(config.fontUrl);
    if (!fontResponse.ok) throw new Error(`Font fetch failed: ${fontResponse.statusText}`);
    const fontData = await fontResponse.arrayBuffer();
    
    font = await pdfDoc.embedFont(new Uint8Array(fontData));
    boldFont = font; // Reusing regular font as bold as requested

  } catch (e) {
    console.error("CRITICAL: Custom font failed to load. PDF will likely have encoding errors.", e);
    throw new Error("Custom font loading failed. Cannot generate PDF.");
  }

  const logoResponse = await fetch(config.logoUrl);
  if (!logoResponse.ok) throw new Error(`Logo fetch failed: ${logoResponse.status}`);
  const logoImageBytes = await logoResponse.arrayBuffer();
  const logoImage = await pdfDoc.embedPng(logoImageBytes);


  const colorPrimaryBlue = rgb(0.10, 0.25, 0.45);
  const colorSecondaryBlue = rgb(0.3, 0.5, 0.7);
  const fieldBorderColor = rgb(0.9, 0.9, 0.9);
  const colorSeparatorLine = rgb(0.82, 0.85, 0.92);
  const colorLabelText = rgb(0.25, 0.25, 0.25);
  const colorDataText = rgb(0.1, 0.1, 0.1);
  const colorBlack = rgb(0,0,0);

  const margin = 40;
  let y = height - margin - 12;

  const lineThickness = 0.3;
  const fieldTextPadding = 4;
  const fieldHeight = 18;

  const smallFontSize = 7.5;
  const regularFontSize = 9;
  const dataFontSize = 9;
  const sectionTitleFontSize = 12;
  const mainTitleFontSize = 16;

  const spaceBetweenRows = 5;
  const spaceBetweenSections = 14;
  const spaceBelowSectionTitle = 8;
  const spaceBelowLabel = 1.5;

  function getTextBaselineInField(fieldTopY: number, fHeight: number, textFontSize: number): number {
    return fieldTopY - fHeight + (fHeight - textFontSize) / 2 + (textFontSize / 10) + 1;
  }

  function drawField(text: string, x: number, fieldTopY: number, fieldWidth: number, fHeight: number, align: 'left' | 'center' | 'right' = 'left', currentFont = font, fontSize = dataFontSize, textColor = colorDataText) {
    page.drawRectangle({
      x, y: fieldTopY - fHeight, width: fieldWidth, height: fHeight,
      borderColor: fieldBorderColor, borderWidth: lineThickness,
    });
    let textX = x + fieldTextPadding;
    const textWidthVal = currentFont.widthOfTextAtSize(text, fontSize);
    if (align === 'center') textX = x + (fieldWidth - textWidthVal) / 2;
    else if (align === 'right') textX = x + fieldWidth - textWidthVal - fieldTextPadding;
    const textY = getTextBaselineInField(fieldTopY, fHeight, fontSize);
    page.drawText(text, { x: textX, y: textY, font: currentFont, size: fontSize, color: textColor });
  }

  function drawLabel(text: string, x: number, labelBaselineY: number, currentFont = font, fontSize = smallFontSize, color = colorLabelText) {
    page.drawText(text, { x, y: labelBaselineY, font: currentFont, size: fontSize, color: color });
  }

  y -= mainTitleFontSize;
  const mainTitleBaselineY = y;
  page.drawText("SMLOUVA O ZÁJEZDU", { x: margin, y: mainTitleBaselineY, font: boldFont, size: mainTitleFontSize, color: colorPrimaryBlue });

  if (!/^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$/.test(data.orderSymbol ?? '')) throw new Error('Order symbol unavailable');
  page.drawText(`Symbol objednávky: ${data.orderSymbol}`, { x: margin, y: 20, font, size: 9, color: colorLabelText });
  const contractNoText = data.contractNumber || '';
  const contractNoLabelText = "č. smlouvy:";
  const contractNoFieldWidth = 120;
  const contractNoLabelWidth = font.widthOfTextAtSize(contractNoLabelText, regularFontSize);
  const contractNoX = width - margin - contractNoFieldWidth;

  const tempFieldTextBaselineOffset = fieldHeight - (fieldHeight - dataFontSize) / 2 - (dataFontSize / 10) - 1;
  const contractNoLabelBaselineY = mainTitleBaselineY + (mainTitleFontSize - regularFontSize) / 2;
  const contractNoFieldTopY = contractNoLabelBaselineY + tempFieldTextBaselineOffset;

  drawField(contractNoText, contractNoX, contractNoFieldTopY, contractNoFieldWidth, fieldHeight, 'left');
  drawLabel(contractNoLabelText, contractNoX - contractNoLabelWidth - 8, contractNoLabelBaselineY, boldFont, regularFontSize, colorPrimaryBlue);

  y = mainTitleBaselineY - (mainTitleFontSize * 0.3) - spaceBetweenSections;

  y = Math.min(y, contractNoFieldTopY - fieldHeight - spaceBetweenSections * 0.5);
  const orgSectionTopY = y;
  y -= regularFontSize;
  drawLabel("Pořadatel zájezdu:", margin, y, font, regularFontSize - 0.5, colorSecondaryBlue);
  y -= (spaceBelowLabel + regularFontSize + 2);

  const orgTextLineHeight = regularFontSize + 2;
  const orgDataX = margin;
  let orgTextCurrentY = y;

  page.drawText(data.organizer.name || '', { x: orgDataX, y: orgTextCurrentY, font: boldFont, size: regularFontSize, color: colorDataText });
  orgTextCurrentY -= orgTextLineHeight;
  page.drawText(`IČO: ${data.organizer.ico || ''}  DIČ: ${data.organizer.dic || ''}`, { x: orgDataX, y: orgTextCurrentY, font: font, size: smallFontSize + 0.5, color: colorDataText });
  orgTextCurrentY -= orgTextLineHeight;
  page.drawText(`Sídlo firmy: ${data.organizer.address || ''}`, { x: orgDataX, y: orgTextCurrentY, font: font, size: smallFontSize + 0.5, color: colorDataText });
  orgTextCurrentY -= orgTextLineHeight;
  page.drawText(`Email: ${data.organizer.email || ''}`, { x: orgDataX, y: orgTextCurrentY, font: font, size: smallFontSize + 0.5, color: colorDataText });
  orgTextCurrentY -= orgTextLineHeight;
  page.drawText(`Telefon: ${data.organizer.phone || ''}`, { x: orgDataX, y: orgTextCurrentY, font: font, size: smallFontSize + 0.5, color: colorDataText });
  orgTextCurrentY -= orgTextLineHeight;
  page.drawText(`Číslo účtu: ${data.organizer.account || ''}`, { x: orgDataX, y: orgTextCurrentY, font: font, size: smallFontSize + 0.5, color: colorDataText });

  const logoAreaWidth = 170;
  const logoAreaX = width - margin - logoAreaWidth;
  const logoDims = logoImage.scale(logoAreaWidth / logoImage.width * 0.90); // Made logo bigger
  page.drawImage(logoImage, {
      x: logoAreaX,
      y: orgSectionTopY - logoDims.height,
      width: logoDims.width,
      height: logoDims.height,
  });

  y = Math.min(orgTextCurrentY, orgSectionTopY - logoDims.height);
  y -= (spaceBetweenSections * 0.8);
  page.drawLine({ start: { x: margin, y: y }, end: { x: width - margin, y: y }, thickness: lineThickness, color: colorSeparatorLine });

  y -= spaceBetweenSections;
  y -= sectionTitleFontSize;
  page.drawText("INFORMACE K ZÁJEZDU", { x: margin , y: y, font: boldFont, size: sectionTitleFontSize, color: colorPrimaryBlue });
  y -= spaceBelowSectionTitle;

  const contentWidth = width - 2 * margin;
  const gap = 8;
  const rightEdge = width - margin;

  let rowY = y;
  y -= smallFontSize; drawLabel("Termín zájezdu:", margin, y); drawLabel("Název zájezdu:", margin + contentWidth/2 + gap, y);
  y -= spaceBelowLabel; const fieldTopInfo1 = y;
  drawField(data.tourInfo.tourDate || '', margin, fieldTopInfo1, contentWidth/2 - gap, fieldHeight);
  drawField(data.tourInfo.tourName || '', margin + contentWidth/2 + gap, fieldTopInfo1, contentWidth/2 - gap, fieldHeight);
  rowY = fieldTopInfo1 - fieldHeight - spaceBetweenRows;

  y = rowY;
  y -= smallFontSize; drawLabel("Doprava:", margin, y); drawLabel("Místo pobytu:", margin + contentWidth/2 + gap, y);
  y -= spaceBelowLabel; const fieldTopInfo2 = y;
  drawField(data.tourInfo.transport || '', margin, fieldTopInfo2, contentWidth/2 - gap, fieldHeight);
  drawField(data.tourInfo.placeOfStay || '', margin + contentWidth/2 + gap, fieldTopInfo2, contentWidth/2 - gap, fieldHeight);
  rowY = fieldTopInfo2 - fieldHeight - spaceBetweenRows;

  y = rowY;
  y -= smallFontSize; drawLabel("Nástupní místo:", margin, y); drawLabel("Počet dní:", margin + contentWidth/2 + gap, y);
  y -= spaceBelowLabel; const fieldTopInfo3 = y;
  drawField(data.tourInfo.departurePoint || '', margin, fieldTopInfo3, contentWidth/2 - gap, fieldHeight);
  drawField(data.tourInfo.nights || '', margin + contentWidth/2 + gap, fieldTopInfo3, contentWidth/2 - gap, fieldHeight);
  y = fieldTopInfo3 - fieldHeight - spaceBetweenRows;

  y -= spaceBetweenSections;
  y -= sectionTitleFontSize;
  page.drawText("ZÁKAZNÍK (OBJEDNATEL)", { x: margin , y: y, font: boldFont, size: sectionTitleFontSize, color: colorPrimaryBlue });
  y -= spaceBelowSectionTitle;

  // --- START: RIGHT-ALIGNED CUSTOMER FIELDS ---
  const dobFieldWidth = 140;
  const dobFieldX = rightEdge - dobFieldWidth;
  const nameFieldWidth = dobFieldX - margin - gap;
  rowY = y;
  y -= smallFontSize; drawLabel("Příjmení, jméno:", margin, y); drawLabel("Datum nar.:", dobFieldX, y);
  y -= spaceBelowLabel; const clientFieldTop1 = y;
  drawField(data.client.fullName || '', margin, clientFieldTop1, nameFieldWidth, fieldHeight);
  drawField(data.client.dob || '', dobFieldX, clientFieldTop1, dobFieldWidth, fieldHeight);
  rowY = clientFieldTop1 - fieldHeight - spaceBetweenRows;

  y = rowY;
  y -= smallFontSize; drawLabel("Adresa včetně PSČ:", margin, y);
  y -= spaceBelowLabel; const clientFieldTop2 = y;
  drawField(data.client.address || '', margin, clientFieldTop2, contentWidth, fieldHeight);
  rowY = clientFieldTop2 - fieldHeight - spaceBetweenRows;

  // New Single Row: Nationality | Phone | Email
  // Ratios: ~20% | ~30% | ~50%
  const widthNat = (contentWidth - 2 * gap) * 0.20;
  const widthPhone = (contentWidth - 2 * gap) * 0.30;
  const widthEmail = (contentWidth - 2 * gap) * 0.50;

  y = rowY;
  y -= smallFontSize; 
  drawLabel("Státní příslušnost:", margin, y); 
  drawLabel("Tel. číslo:", margin + widthNat + gap, y); 
  drawLabel("Email:", margin + widthNat + gap + widthPhone + gap, y);

  y -= spaceBelowLabel; const clientFieldTop3 = y;
  
  drawField(data.client.nationality || '', margin, clientFieldTop3, widthNat, fieldHeight);
  drawField(data.client.phone || '', margin + widthNat + gap, clientFieldTop3, widthPhone, fieldHeight);
  drawField(data.client.email || '', margin + widthNat + gap + widthPhone + gap, clientFieldTop3, widthEmail, fieldHeight);
  
  y = clientFieldTop3 - fieldHeight - spaceBetweenRows;
  // --- END: RIGHT-ALIGNED CUSTOMER FIELDS ---

  y -= spaceBetweenSections;
  y -= sectionTitleFontSize;
  page.drawText("CENA A PLATBA", { x: margin, y: y, font: boldFont, size: sectionTitleFontSize, color: colorPrimaryBlue });
  y -= spaceBelowSectionTitle;

  const calculationTableWidth = contentWidth * 0.65;
  const colDescW = calculationTableWidth * 0.45;
  const colPrice1W = calculationTableWidth * 0.22;
  const colNumPersW = calculationTableWidth * 0.11;
  const colTotalItemW = calculationTableWidth * 0.22;

  let leftY = y;

  let currentHeaderX = margin;
  const headerLabelY = leftY - smallFontSize;
  drawLabel("KALKULACE", currentHeaderX, headerLabelY, boldFont, smallFontSize, colorBlack);
  currentHeaderX += colDescW;
  drawLabel("Cena za 1 osobu", currentHeaderX, headerLabelY, boldFont, smallFontSize, colorBlack);
  currentHeaderX += colPrice1W;
  drawLabel("Počet osob", currentHeaderX, headerLabelY, boldFont, smallFontSize, colorBlack);
  currentHeaderX += colNumPersW;
  drawLabel("Cena", currentHeaderX, headerLabelY, boldFont, smallFontSize, colorBlack);

  leftY -= (smallFontSize + spaceBelowLabel + 4);

  (data.calculation.items || []).forEach((item: any) => {
    const pricePerPersonText = (item.pricePerPerson ?? 0).toLocaleString('cs-CZ') + ` ${item.currency || 'Kč'}`;

    // Wrap any meta surcharge sub-line and compute how much extra height the row needs.
    // The cell rectangles are drawn at rowHeight (not just fieldHeight) so the main item
    // text and the meta surcharge text sit inside the same bordered row — reads as one
    // logical entry rather than overflowing into the gap below.
    const metaLineHeight = smallFontSize + 2;
    const metaTopPadding = 3;
    const metaBottomPadding = 4;
    const metaLines: string[] = item.metaSurcharge
      ? wrapText(item.metaSurcharge, font, smallFontSize, calculationTableWidth - 12)
      : [];
    const metaExtraHeight = metaLines.length > 0
      ? metaTopPadding + metaLines.length * metaLineHeight + metaBottomPadding
      : 0;
    const rowHeight = fieldHeight + metaExtraHeight;

    const cells: Array<{ x: number; w: number; text: string; align: 'left' | 'center' | 'right' }> = [];
    let cx = margin;
    cells.push({ x: cx, w: colDescW,      text: item.description || '', align: 'left'   }); cx += colDescW;
    cells.push({ x: cx, w: colPrice1W,    text: pricePerPersonText,     align: 'right'  }); cx += colPrice1W;
    cells.push({ x: cx, w: colNumPersW,   text: '1',                    align: 'center' }); cx += colNumPersW;
    cells.push({ x: cx, w: colTotalItemW, text: pricePerPersonText,     align: 'right'  });

    for (const cell of cells) {
      page.drawRectangle({
        x: cell.x, y: leftY - rowHeight, width: cell.w, height: rowHeight,
        borderColor: fieldBorderColor, borderWidth: lineThickness,
      });
      const tw = font.widthOfTextAtSize(cell.text, dataFontSize);
      let tx = cell.x + fieldTextPadding;
      if (cell.align === 'center') tx = cell.x + (cell.w - tw) / 2;
      else if (cell.align === 'right') tx = cell.x + cell.w - tw - fieldTextPadding;
      // Main text sits in the TOP fieldHeight band of the (possibly taller) cell.
      const ty = getTextBaselineInField(leftY, fieldHeight, dataFontSize);
      page.drawText(cell.text, { x: tx, y: ty, font, size: dataFontSize, color: colorDataText });
    }

    if (metaLines.length > 0) {
      // First meta baseline: just below the main text band, offset by top padding.
      // ~0.75 * fontSize approximates the ascender so visible top sits at the padding line.
      let metaY = leftY - fieldHeight - metaTopPadding - smallFontSize * 0.75;
      for (const line of metaLines) {
        page.drawText(line, {
          x: margin + 6,
          y: metaY,
          font,
          size: smallFontSize,
          color: colorLabelText,
        });
        metaY -= metaLineHeight;
      }
    }

    leftY -= (rowHeight + spaceBetweenRows * 0.6);
  });

  const paymentBlockX = margin + calculationTableWidth + 20;
  const paymentBlockWidth = rightEdge - paymentBlockX;
  let rightY = y;

  drawLabel("PLATBA", paymentBlockX, headerLabelY, boldFont, smallFontSize, colorBlack);
  rightY -= (smallFontSize + spaceBelowLabel + 10);

  const paymentLineHeight = regularFontSize + 3;
  const paymentValueX = paymentBlockX + 55;

  const isDeposit = data.calculation.isDepositPayment || false;
  const firstSectionLabel = isDeposit ? "Záloha:" : "Cena celkem:";

  page.drawText(firstSectionLabel, { x: paymentBlockX, y: rightY, font: boldFont, size: regularFontSize, color: colorDataText });
  rightY -= paymentLineHeight;
  page.drawText("Částka:", { x: paymentBlockX + 10, y: rightY, font: font, size: smallFontSize, color: colorLabelText });
  page.drawText(data.calculation.zaloha.castka || '', { x: paymentValueX, y: rightY, font: font, size: regularFontSize, color: colorDataText });
  rightY -= paymentLineHeight;
  page.drawText("Uhradit do:", { x: paymentBlockX + 10, y: rightY, font: font, size: smallFontSize, color: colorLabelText });
  page.drawText(data.calculation.zaloha.uhraditDo || '', { x: paymentValueX, y: rightY, font: font, size: regularFontSize, color: colorDataText });
  rightY -= (paymentLineHeight + 4);
  page.drawLine({start: {x: paymentBlockX, y: rightY}, end: {x: paymentBlockX + paymentBlockWidth, y: rightY}, thickness: lineThickness, color: colorSeparatorLine});
  rightY -= (paymentLineHeight + 2);

  if (isDeposit) {
      page.drawText("Doplatek:", { x: paymentBlockX, y: rightY, font: boldFont, size: regularFontSize, color: colorDataText });
      rightY -= paymentLineHeight;
      page.drawText("Částka:", { x: paymentBlockX + 10, y: rightY, font: font, size: smallFontSize, color: colorLabelText });
      page.drawText(data.calculation.doplatek.castka || '', { x: paymentValueX, y: rightY, font: font, size: regularFontSize, color: colorDataText });
      rightY -= paymentLineHeight;
      page.drawText("Uhradit do:", { x: paymentBlockX + 10, y: rightY, font: font, size: smallFontSize, color: colorLabelText });
      page.drawText(data.calculation.doplatek.uhraditDo || '', { x: paymentValueX, y: rightY, font: font, size: regularFontSize, color: colorDataText });
      rightY -= (paymentLineHeight + 4);
      page.drawLine({start: {x: paymentBlockX, y: rightY}, end: {x: paymentBlockX + paymentBlockWidth, y: rightY}, thickness: lineThickness, color: colorSeparatorLine});
      rightY -= (paymentLineHeight + 1);
  }

  page.drawText("Celkem:", { x: paymentBlockX, y: rightY, font: boldFont, size: regularFontSize, color: colorDataText });
  const totalPriceString = data.calculation.totalPriceForDisplay || '';
  page.drawText(totalPriceString, { x: paymentValueX, y: rightY, font: boldFont, size: regularFontSize + 1, color: colorBlack });

  // Visual-only meta-surcharge sums per currency, rendered under "Celkem:" so the
  // customer sees the on-site amount alongside the bank total. NEVER added to totalPrice.
  const metaSumLines: string[] = data.calculation.metaSurchargeSumLines || [];
  for (const line of metaSumLines) {
    rightY -= (paymentLineHeight + 1);
    page.drawText(line, {
      x: paymentValueX,
      y: rightY,
      font: boldFont,
      size: regularFontSize,
      color: colorDataText,
    });
  }

  y = Math.min(leftY, rightY) - 20; // Increased space

  const paymentClauseLines = wrapText(data.paymentClause || '', font, smallFontSize, contentWidth);
  paymentClauseLines.forEach(line => {
    const textWidth = font.widthOfTextAtSize(line, smallFontSize);
    page.drawText(line, { x: margin + (contentWidth - textWidth)/2, y: y, font: font, size: smallFontSize, color: colorLabelText});
    y -= (smallFontSize + 2);
  });

  const signatureLineWidth = (contentWidth - gap) / 2;
  const signatureLineY = margin + 30;
  const signatureLabelBaselineY = signatureLineY - smallFontSize - 3;

  const termsLineHeight = smallFontSize + 2.5;
  const termsLines = wrapText(data.termsClause || '', font, smallFontSize, contentWidth - 10);
  const termsBlockHeight = termsLines.length * termsLineHeight;
  let termsBlockTopY = signatureLineY + 15 + termsBlockHeight; // Positioned relative to signature

  for (const line of termsLines) {
    page.drawText(line, { x: margin + 5, y: termsBlockTopY, font: font, size: smallFontSize, color: colorDataText });
    termsBlockTopY -= termsLineHeight;
  }

  const podpisZakaznikaLabelText = "Podpis zákazníka";
  page.drawLine({ start: {x: margin, y: signatureLineY}, end: {x: margin + signatureLineWidth, y: signatureLineY}, thickness: lineThickness, color: colorBlack });
  drawLabel(podpisZakaznikaLabelText, margin + (signatureLineWidth - font.widthOfTextAtSize(podpisZakaznikaLabelText,smallFontSize))/2 , signatureLabelBaselineY, font, smallFontSize, colorBlack);

  const dateLabelText = "Datum";
  const dateText = data.signatureDate || '';
  const dateFieldX = rightEdge - signatureLineWidth;
  page.drawLine({ start: {x: dateFieldX, y: signatureLineY}, end: {x: rightEdge, y: signatureLineY}, thickness: lineThickness, color: colorBlack });
  page.drawText(dateText, {
      x: dateFieldX + (signatureLineWidth - font.widthOfTextAtSize(dateText, regularFontSize)) / 2,
      y: signatureLineY + 5,
      font: font,
      size: regularFontSize,
      color: colorDataText,
  });
  drawLabel(dateLabelText, dateFieldX + (signatureLineWidth - font.widthOfTextAtSize(dateLabelText,smallFontSize))/2, signatureLabelBaselineY, font, smallFontSize, colorBlack);

  return pdfDoc.save();
}

function wrapText(text: string, currentFont: PDFFont, fontSize: number, maxWidth: number): string[] {
  if (!text) return [];
  const words = text.split(' ');
  const lines: string[] = [];
  if (words.length === 0 || !words[0]) return [""];
  let currentLine = words[0];

  for (let i = 1; i < words.length; i++) {
    const word = words[i];
    if (!word) continue;
    const testLine = currentLine + " " + word;
    try {
        if (currentFont.widthOfTextAtSize(testLine, fontSize) < maxWidth) {
            currentLine = testLine;
        } else {
            lines.push(currentLine);
            currentLine = word;
        }
    } catch (e) {
        console.warn("Warning: Error during text wrapping width calculation.", e);
        if (currentLine.length > word.length || lines.length === 0 ) lines.push(currentLine);
        currentLine = word;
    }
  }
  lines.push(currentLine);
  return lines;
}

// --- MAIN DENO SERVER ---
Deno.serve(async (req: Request) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body) ||
        Object.keys(body).some((key) => !["requestSecret", "orderId"].includes(key))) {
      throw new Error("Invalid request body");
    }
    const { requestSecret, orderId } = body;

    if (!orderId) {
        throw new Error("Order ID is missing from the request");
    }

    const { data: rpcData, error: rpcError } = await supabaseAdmin.rpc('get_order_details', {
        orderid: orderId
    });

    if (rpcError) {
      console.error("Error fetching order details:", rpcError);
      throw new Error(`Supabase RPC Error: ${rpcError.message}`);
    }
    if (!rpcData || !rpcData.data) {
        throw new Error(`No data returned from RPC for orderId: ${orderId}`);
    }

    const { order: rpcOrder, occasion, form_fields, payment_info } = rpcData.data;

    // --- AUTHORIZATION ---
    // Authorize using the shared helper. Supports secret (backend) or user token (frontend).
    const authorizationHeader = req.headers.get("Authorization");
    await authorizeRequest({ requestSecret, authorizationHeader, occasionId: occasion.id });
    // ---------------------

    const { data: externalServices, error: externalServicesError } =
      await supabaseAdmin.rpc("get_external_services", { p_order_id: orderId });
    if (externalServicesError) throw new Error("Agreement configuration unavailable");
    const agreementConfig = parseAgreementConfig(externalServices);

    const orderFields = rpcOrder?.data?.fields;

    const surname = findFieldDataByType(orderFields, form_fields, 'surname') || '';
    const name = findFieldDataByType(orderFields, form_fields, 'name') || '';
    const clientData = {
        fullName: [surname, name].filter(Boolean).join(', ') || 'N/A',
        address: findFieldDataByType(orderFields, form_fields, 'address') || 'N/A',
        nationality: findFieldDataByType(orderFields, form_fields, 'nationality') || 'N/A',
        email: findFieldDataByType(orderFields, form_fields, 'email') || rpcOrder?.data?.email || 'N/A',
        phone: findFieldDataByType(orderFields, form_fields, 'phone') || rpcOrder?.data?.phone || 'N/A',
        dob: formatDate(findFieldDataByType(orderFields, form_fields, 'birth_date')),
    };

    const startTime = occasion?.start_time ? new Date(occasion.start_time) : null;
    const endTime = occasion?.end_time ? new Date(occasion.end_time) : null;
    let nights = 'N/A';
    if(startTime && endTime) {
        const diffTime = Math.abs(endTime.getTime() - startTime.getTime());
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        nights = String(diffDays);
    }

    const occasionDescription = occasion?.description || '';
    const transportMatch = occasionDescription.match(/Doprava (.*?)\./);

    const contractFeatureRaw = occasion?.features?.find((f:any) => f.code === 'contract');
    // Only use the feature data if it is explicitly enabled
    const contractFeature = contractFeatureRaw?.is_enabled ? contractFeatureRaw : null;

    const tourInfoData = {
        tourDate: contractFeature?.tour_date || `${formatDate(occasion?.start_time)} - ${formatDate(occasion?.end_time)}`,
        transport: contractFeature?.transport || transportMatch?.[1] || "Bude upřesněno",
        departurePoint: contractFeature?.departure_point || "Podle domluvy",
        notes: contractFeature?.notes || "",
        tourName: contractFeature?.tour_name || occasion?.title || 'N/A',
        placeOfStay: contractFeature?.place_of_stay || "Medjugorje",
        nights: contractFeature?.number_of_days || nights,
    };

    const depositFeatureRaw = occasion?.features?.find((f: any) => f.code === 'deposit');
    const depositFeature = depositFeatureRaw?.is_enabled ? depositFeatureRaw : null;
    // Meta surcharge data only relevant in virtual mode. Real mode = payment-linked deposit; no per-item surcharge text.
    const isVirtualMode = depositFeature?.deposit_mode === 'virtual';
    const metaSurchargeDescription = isVirtualMode &&
            depositFeature?.meta_surcharge_description &&
            String(depositFeature.meta_surcharge_description).trim().length > 0
        ? String(depositFeature.meta_surcharge_description).trim()
        : null;

    // Flatten products across ALL tickets in the order so multi-person contracts list every item.
    // Tickets are 1-indexed in the contract label (e.g. "Lístek 1: ...").
    const allTickets = rpcOrder?.data?.tickets || [];
    const multipleTickets = allTickets.length > 1;
    const flatProducts: any[] = allTickets.flatMap((t: any, idx: number) =>
        (t?.products || []).map((p: any) => ({ ...p, _ticketIndex: idx + 1 }))
    );

    // Per-product meta surcharge amounts collected during the items.map below.
    // Aggregated per currency and rendered as sub-lines under "Celkem:".
    const metaSurchargeAmounts: MetaSurchargeAmount[] = [];
    // PDF uses raw 3-letter codes ("150 EUR") to match the organizer info section,
    // unlike the email which prefers Intl currency style ("150 €").
    const pdfFormatAmount = (abs: number, currency: string) =>
        `${abs.toLocaleString('cs-CZ')} ${currency}`;

    const calculationItems = flatProducts.map((p: any) => {
        const title = p.title || '';
        const typeTitle = p.type_title || '';
        // Define the absolute maximum character length for the entire description field.
        const MAX_LENGTH = 42;

        // 1. Construct the ideal, full description string.
        //    Multi-ticket orders prepend "Lístek N: " so each row is unambiguous.
        const ticketPrefix = multipleTickets ? `Lístek ${p._ticketIndex}: ` : '';
        const fullDescription = typeTitle
            ? `${ticketPrefix}${title} (${typeTitle})`
            : `${ticketPrefix}${title}`;

        let finalDescription = fullDescription;

        // 2. Check if the full description exceeds the maximum length.
        if (fullDescription.length > MAX_LENGTH) {
            const suffix = typeTitle ? ` (${typeTitle})` : '';
            // Reserve space for the prefix when truncating.
            const maxTitleLength = MAX_LENGTH - suffix.length - ticketPrefix.length;

            // 3. Decide on the truncation strategy.
            // If the suffix is too long and leaves no meaningful space for the title (e.g., < 5 chars),
            // then we just truncate the entire combined string. This is our fallback.
            if (maxTitleLength < 5) {
                let raw = fullDescription.substring(0, MAX_LENGTH - 3);
                // Trim trailing single characters (e.g. "Title A" -> "Title")
                raw = raw.replace(/(\s\S)+$/, "").trim();
                finalDescription = raw + '...';
            } else {
                // Otherwise, the "smart" approach: truncate the main title and append the full suffix.
                // This preserves the (type_title) information completely.
                let raw = title.substring(0, maxTitleLength - 3);
                // Trim trailing single characters
                raw = raw.replace(/(\s\S)+$/, "").trim();
                finalDescription = `${ticketPrefix}${raw}...${suffix}`;
            }
        }

        // Visual-only meta surcharge text shown under the item. Only renders in virtual
        // mode — real mode uses payment-linked deposit so the per-item text is suppressed.
        // The amount is also collected for the per-currency sum under "Celkem:".
        let metaSurcharge: string | null = null;
        const meta = extractMetaSurcharge(p, depositFeature?.deposit_mode);
        if (meta) {
            metaSurchargeAmounts.push(meta);
            const amountText = formatSignedMetaSurcharge(meta.amount, meta.currency, pdfFormatAmount);
            metaSurcharge = metaSurchargeDescription
                ? `${amountText} — ${metaSurchargeDescription}`
                : amountText;
        }

        return {
            description: finalDescription,
            pricePerPerson: p.price ?? 0,
            currency: p.currency_code || 'Kč',
            metaSurcharge,
        };
    });

    const orderAmount = payment_info?.amount != null ? Number(payment_info.amount) : 0;
    const depositAmount = payment_info?.deposit_amount != null ? Number(payment_info.deposit_amount) : 0;
    const orderCurrency = payment_info?.currency_code || rpcOrder?.currency_code || 'Kč';
    // In virtual mode the "doplatek" is purely visual (rendered as a sub-line under each
    // product via meta_surcharge); there is no payment-linked split. Suppress the
    // Záloha / Doplatek breakdown even if payment_info.deposit_amount is populated
    // (e.g. legacy orders created before the mode switch).
    const isDepositPayment = !isVirtualMode && depositAmount > 0 && depositAmount < orderAmount;
    const doplatekAmount = isDepositPayment ? orderAmount - depositAmount : 0;

    // Determine surcharge deadline from payment_info
    // deposit_deadline set = specific date, NULL with deposit = on-site payment
    let doplatekUhraditDo = '';
    if (isDepositPayment) {
        if (payment_info?.deposit_deadline) {
            doplatekUhraditDo = formatDate(payment_info.deposit_deadline);
        } else {
            doplatekUhraditDo = 'Na místě';
        }
    }

    const totalPriceDisplay = orderAmount > 0
        ? `${orderAmount.toLocaleString('cs-CZ')} ${orderCurrency}`
        : 'N/A';

    // Format per-currency meta surcharge sums for the PDF.
    const metaSurchargeSumLines = aggregateMetaSurchargeSums(metaSurchargeAmounts).map(
        ({ currency, sum }) => formatSignedMetaSurcharge(sum, currency, pdfFormatAmount),
    );

    const calculationData = {
        items: calculationItems,
        zaloha: {
            castka: isDepositPayment
                ? `${depositAmount.toLocaleString('cs-CZ')} ${orderCurrency}`
                : (orderAmount > 0 ? `${orderAmount.toLocaleString('cs-CZ')} ${orderCurrency}` : 'Dle pokynů'),
            uhraditDo: formatDate(payment_info?.deadline),
        },
        doplatek: {
            totalAmount: doplatekAmount,
            castka: doplatekAmount > 0 ? `${doplatekAmount.toLocaleString('cs-CZ')} ${orderCurrency}` : '',
            uhraditDo: doplatekUhraditDo || 'Dle pokynů',
        },
        isDepositPayment,
        totalPriceForDisplay: totalPriceDisplay,
        metaSurchargeSumLines,
    };

    const dataForPdf = {
        orderSymbol: rpcOrder.order_symbol,
        contractNumber: payment_info?.variable_symbol?.toString() || '',
        organizer: agreementConfig.organizer,
        tourInfo: tourInfoData,
        client: clientData,
        calculation: calculationData,
        paymentClause: contractFeature?.payment_info || agreementConfig.paymentClause,
        termsClause: agreementConfig.termsClause,
        signatureDate: '',
    };

    const pdfBytes = await generateAgreement(dataForPdf, agreementConfig);
    const base64Pdf = Buffer.from(pdfBytes).toString('base64');
    
    if (!rpcOrder?.order_symbol) throw new Error('Order symbol unavailable');
    const filenameCode = rpcOrder.order_symbol;

    return new Response(
      JSON.stringify({ file: base64Pdf, filename: `contract_${filenameCode}.pdf` }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error: any) {
    const isAuthError = error instanceof AuthError;
    const status = isAuthError ? error.status : 500;
    const message = error.message || "Unknown error";
    
    if (!isAuthError) {
        console.error("Error generating agreement PDF:", error);
    }

    return new Response(
      JSON.stringify({ error: message }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: status,
      }
    );
  }
});
