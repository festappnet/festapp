import { getMinimalisticDateRange } from './ticketDate.ts';
import { generateTicketImage, type LayoutTicketRequest } from './generateTicket.ts';
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import QRCode from "npm:qrcode";
import { PDFDocument, rgb } from "npm:pdf-lib";
import * as fontkit from "npm:fontkit";

// Default font URL if none provided in occasion.data.font.
const DEFAULT_FONT_URL = "https://fonts.cdnfonts.com/s/12165/Roboto-Regular.woff";

/**
 * Fetches the resources needed to build the basic mobile ticket.
 *
 * It fetches the occasion details (selecting title, start_time, end_time, and data),
 * downloads the logo image from occasion.data.logo (if available), and downloads the custom font.
 * The font URL is taken from occasion.data.font (if provided) or falls back to a default.
 */
export async function fetchNamedTicketResources(ticket: any) {
  const { data: occasion, error: occError } = await supabaseAdmin
    .from("occasions")
    .select("id, title, start_time, end_time, data")
    .eq("id", ticket.occasion)
    .single();

  if (occError || !occasion) {
    throw new Error(
      `Occasion not found or error fetching occasion: ${occError?.message}`
    );
  }

  // Determine the font URL: use the one provided in occasion.data.font, if available.
  const fontUrl =
    occasion.data && occasion.data.font && occasion.data.font.trim() !== ""
      ? occasion.data.font
      : DEFAULT_FONT_URL;

  // Determine the logo image (if provided).
  let logoBytes: Uint8Array | null = null;
  if (occasion.data && occasion.data.logo && occasion.data.logo.trim() !== "") {
    const logoResponse = await fetch(occasion.data.logo);
    if (!logoResponse.ok) {
      throw new Error(`Failed to download logo image from ${occasion.data.logo}`);
    }
    logoBytes = new Uint8Array(await logoResponse.arrayBuffer());
  }

  const fontResponse = await fetch(fontUrl);
  if (!fontResponse.ok) {
    throw new Error(`Failed to download custom font from ${fontUrl}`);
  }
  const customFontBytes = new Uint8Array(await fontResponse.arrayBuffer());

  return { occasion, logoBytes, customFontBytes };
}

/**
 * Returns a minimalistic date range string formatted according to the given locale.
 */
/**
 * Draws a dashed line between two points.
 * The line is drawn as a series of dashes.
 */
function drawDashedLine(
  page: any,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  dashLength: number,
  gapLength: number,
  color: any
) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const length = Math.hypot(dx, dy);
  const dashGap = dashLength + gapLength;
  const dashCount = Math.floor(length / dashGap);

  for (let i = 0; i <= dashCount; i++) {
    const startDist = i * dashGap;
    const endDist = Math.min(startDist + dashLength, length);
    const tStart = startDist / length;
    const tEnd = endDist / length;
    const sx = x1 + dx * tStart;
    const sy = y1 + dy * tStart;
    const ex = x1 + dx * tEnd;
    const ey = y1 + dy * tEnd;
    page.drawLine({
      start: { x: sx, y: sy },
      end: { x: ex, y: ey },
      color: color,
      thickness: 1,
    });
  }
}

/**
 * Draws a dashed border around a rectangle.
 * The border is drawn along the four edges using dashes.
 * Here the default dash length is increased to 6px and gap length is 2px (scaled accordingly).
 */
function drawDashedRectangle(
  page: any,
  x: number,
  y: number,
  width: number,
  height: number,
  dashLength: number = 6,
  gapLength: number = 2,
  color: any
) {
  // Top edge.
  drawDashedLine(page, x, y + height, x + width, y + height, dashLength, gapLength, color);
  // Right edge.
  drawDashedLine(page, x + width, y + height, x + width, y, dashLength, gapLength, color);
  // Bottom edge.
  drawDashedLine(page, x + width, y, x, y, dashLength, gapLength, color);
  // Left edge.
  drawDashedLine(page, x, y, x, y + height, dashLength, gapLength, color);
}

/**
 * Helper function to wrap text into multiple lines if it exceeds a maximum width.
 */
function wrapText(
  text: string,
  font: any,
  size: number,
  maxWidth: number
): string[] {
  const words = text.split(" ");
  const lines: string[] = [];
  let currentLine = "";
  for (const word of words) {
    const testLine = currentLine ? currentLine + " " + word : word;
    const testWidth = font.widthOfTextAtSize(testLine, size);
    if (testWidth > maxWidth && currentLine) {
      lines.push(currentLine);
      currentLine = word;
    } else {
      currentLine = testLine;
    }
  }
  if (currentLine) {
    lines.push(currentLine);
  }
  return lines;
}

/**
 * Generates a mobile-size ticket PDF.
 *
 * The design includes:
 * - A ticket drawn inside a non-rounded rectangle with a dashed border (simulating cut lines).
 * - A solid background color (instead of a gradient).
 * - A centered logo (if provided in occasion.data.logo).
 * - An event title that wraps if too long.
 * - A date (and optional location) line.
 * - The attendee's full name (shifted slightly further down, without a separator line).
 * - A QR code and ticket code.
 * - A footer with additional information.
 *
 * @param ticket The ticket data.
 * @param resources Resources (occasion details, logo image, and font).
 * @param orderData Order data (containing name, surname, and link).
 * @param locale Locale for date formatting (default "cs").
 */
export async function generateNamedTicketImage(
  ticket: any,
  resources: {
    occasion: any;
    logoBytes: Uint8Array | null;
    customFontBytes: Uint8Array;
  },
  orderData: any,
  locale: string = "cs",
  custom?: LayoutTicketRequest
): Promise<Uint8Array> {
  if(custom)return generateTicketImage(ticket,resources as any,custom);
  try {
    const { occasion, logoBytes, customFontBytes } = resources;

    // Scale factor to reduce size by 1.6×.
    const scale = 1 / 1.6; // ≈0.625

    // Set up a PDF page with scaled dimensions.
    const pageWidth = 340 * scale;
    const pageHeight = 620 * scale;
    const pdfDoc = await PDFDocument.create();
    pdfDoc.registerFontkit(fontkit);
    const page = pdfDoc.addPage([pageWidth, pageHeight]);

    // Define the ticket area within the page (scaled).
    const ticketLeft = 10 * scale;
    const ticketBottom = 10 * scale;
    const ticketWidth = 320 * scale;
    const ticketHeight = 600 * scale;
    const ticketTop = ticketBottom + ticketHeight;

    // Colors.
    const backgroundColor = rgb(230 / 255, 230 / 255, 230 / 255); // solid background (slightly darker from gradient)
    const borderColor = rgb(224 / 255, 224 / 255, 224 / 255); // light gray for dashed border
    const primaryTextColor = rgb(42 / 255, 42 / 255, 42 / 255); // dark gray
    const secondaryTextColor = rgb(102 / 255, 102 / 255, 102 / 255); // medium gray
    const footerTextColor = rgb(153 / 255, 153 / 255, 153 / 255); // #999

    // Draw a solid background for the ticket area.
    page.drawRectangle({
      x: ticketLeft,
      y: ticketBottom,
      width: ticketWidth,
      height: ticketHeight,
      color: backgroundColor,
    });

    // Draw the dashed border (non-rounded) with scaled dash/gap lengths.
    drawDashedRectangle(
      page,
      ticketLeft,
      ticketBottom,
      ticketWidth,
      ticketHeight,
      6 * scale, // dash length scaled longer
      2 * scale, // gap length scaled
      borderColor
    );

    // Embed the custom font.
    const customFont = await pdfDoc.embedFont(customFontBytes);

    // Draw the logo if available (scaled).
    if (logoBytes) {
      let logoImage;
      try {
        logoImage = await pdfDoc.embedPng(logoBytes);
      } catch {
        logoImage = await pdfDoc.embedJpg(logoBytes);
      }
      page.drawImage(logoImage, {
        x: ticketLeft + 115 * scale,
        y: ticketTop - 20 * scale - 90 * scale,
        width: 90 * scale,
        height: 90 * scale,
      });
    }

    // Wrap and draw the Event Title.
    const eventTitle = occasion.title || "Event";
    const eventTitleFontSize = 20 * scale;
    const maxTitleWidth = ticketWidth - 20 * scale;
    const titleLines = wrapText(eventTitle, customFont, eventTitleFontSize, maxTitleWidth);
    let currentY = ticketTop - 140 * scale;
    for (const line of titleLines) {
      const lineWidth = customFont.widthOfTextAtSize(line, eventTitleFontSize);
      const lineX = ticketLeft + (ticketWidth - lineWidth) / 2;
      page.drawText(line, {
        x: lineX,
        y: currentY,
        size: eventTitleFontSize,
        font: customFont,
        color: primaryTextColor,
      });
      currentY -= eventTitleFontSize + 4 * scale;
    }

    // Draw the date (and location if provided).
    let dateText = "";
    try {
      const startDate = new Date(occasion.start_time);
      const endDate = new Date(occasion.end_time);
      dateText = getMinimalisticDateRange(startDate, endDate, locale);
    } catch {
      dateText = "Date N/A";
    }
    if (occasion.data && occasion.data["place_name"] && occasion.data["place_name"].trim() !== "") {
      dateText += ", " + occasion.data["place_name"];
    }
    const dateFontSize = 14 * scale;
    const maxDateWidth = ticketWidth - 20 * scale;
    const dateLines = wrapText(dateText, customFont, dateFontSize, maxDateWidth);
    let dateY = ticketTop - 185 * scale;
    for (const line of dateLines) {
      const lineWidth = customFont.widthOfTextAtSize(line, dateFontSize);
      const lineX = ticketLeft + (ticketWidth - lineWidth) / 2;
      page.drawText(line, {
        x: lineX,
        y: dateY,
        size: dateFontSize,
        font: customFont,
        color: secondaryTextColor,
      });
      dateY -= dateFontSize + 2 * scale;
    }

    // Draw the attendee's full name (shifted further down).
    if (orderData && orderData.name && orderData.surname) {
      const fullName = `${orderData.name} ${orderData.surname}`.trim();
      const nameFontSize = 20 * scale;
      const nameWidth = customFont.widthOfTextAtSize(fullName, nameFontSize);
      const nameX = ticketLeft + (ticketWidth - nameWidth) / 2;
      const nameY = ticketTop - 270 * scale; // shifted a bit further down
      page.drawText(fullName, {
        x: nameX,
        y: nameY,
        size: nameFontSize,
        font: customFont,
        color: primaryTextColor,
      });
    }

    // Generate and draw the QR code.
    const qrShift = 20 * scale;
    const qrOptions = {
      width: 160 * scale,
      margin: 3 * scale,
      color: {
        dark: "#2A2A2A",
        light: "#FFFFFF",
      },
    };
    const qrDataUrl = await QRCode.toDataURL(ticket.ticket_symbol, qrOptions);
    const rawQR = qrDataUrl.split(",")[1];
    const qrBytes = Uint8Array.from(atob(rawQR), (c) => c.charCodeAt(0));
    let qrImage;
    try {
      qrImage = await pdfDoc.embedPng(qrBytes);
    } catch {
      qrImage = await pdfDoc.embedJpg(qrBytes);
    }
    page.drawImage(qrImage, {
      x: ticketLeft + 80 * scale,
      y: ticketBottom + (600 * scale - 310 * scale - 160 * scale) - qrShift,
      width: 160 * scale,
      height: 160 * scale,
    });

    // Draw the ticket code beneath the QR code.
    const codeText = ticket.ticket_symbol;
    const codeFontSize = 14 * scale;
    const codeWidth = customFont.widthOfTextAtSize(codeText, codeFontSize);
    const codeY = ticketTop - 490 * scale - qrShift;
    page.drawText(codeText, {
      x: ticketLeft + (ticketWidth - codeWidth) / 2,
      y: codeY,
      size: codeFontSize,
      font: customFont,
      color: secondaryTextColor,
    });

    // Draw the footer at the bottom.
    let footerText = "Vstupenka je nepřenosná";
    if (occasion.data && occasion.data.link && occasion.data.link.trim() !== "") {
      footerText += " • " + occasion.data.link;
    }
    const footerFontSize = 10 * scale;
    const maxFooterWidth = ticketWidth - 20 * scale;
    // Wrap footer text if too long.
    const footerLines = wrapText(footerText, customFont, footerFontSize, maxFooterWidth);
    // Start drawing footer lines from the bottom upward.
    let footerY = ticketBottom + 5 * scale + (footerLines.length - 1) * (footerFontSize + 2 * scale);
    for (const line of footerLines) {
      const lineWidth = customFont.widthOfTextAtSize(line, footerFontSize);
      const lineX = ticketLeft + (ticketWidth - lineWidth) / 2;
      page.drawText(line, {
        x: lineX,
        y: footerY,
        size: footerFontSize,
        font: customFont,
        color: footerTextColor,
      });
      footerY -= footerFontSize + 2 * scale;
    }

    const pdfBytes = await pdfDoc.save();
    return pdfBytes;
  } catch (error) {
    console.error("Error generating basic ticket PDF:", error);
    throw error;
  }
}
