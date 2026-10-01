import { validateLayout, pdfBox, type Template } from './ticketLayout.ts';
import { fitText } from './ticketText.ts';
import type { RenderData } from './ticketRenderData.ts';
import type { Resources } from './ticketGeneration.ts';
import { formatCurrency } from "../_shared/utilities.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import QRCode from "npm:qrcode";
import { PDFDocument, rgb } from "npm:pdf-lib";
// Import all exports from fontkit (do not try to import a default)
import * as fontkit from "npm:fontkit";
import * as path from "https://deno.land/std/path/mod.ts";

// Set constant for custom font URL.
const CUSTOM_FONT_URL =
  "https://github.com/google/fonts/raw/refs/heads/main/apache/robotoslab/RobotoSlab%5Bwght%5D.ttf";
const MAX_TEXT_ON_TICKET = 45;

export async function fetchTicketResources(ticket: any) {
  // Fetch the occasion data.
  const { data: occasion, error: occasionError } = await supabaseAdmin
    .from("occasions")
    .select("id, features")
    .eq("id", ticket.occasion)
    .single();

  if (occasionError || !occasion) {
    throw new Error(
      `Occasion not found or error fetching occasion: ${occasionError?.message}`
    );
  }

  let backgroundUrl: string | undefined;
  let darkColor = "000000";
  let lightColor = "FFFFFF";

  // Define a reusable regex for 6-character hex colors.
  const hexColorRegex = /^[A-Fa-f0-9]{6}$/;

  if (Array.isArray(occasion.features)) {
    const ticketFeature = occasion.features.find(
      (feature: any) => feature.code === "ticket"
    );
    if (ticketFeature) {
      if (typeof ticketFeature.background === "string") {
        backgroundUrl = ticketFeature.background;
      }
      if (
        typeof ticketFeature.darkColor === "string" &&
        hexColorRegex.test(ticketFeature.darkColor)
      ) {
        darkColor = ticketFeature.darkColor;
      }
      if (
        typeof ticketFeature.lightColor === "string" &&
        hexColorRegex.test(ticketFeature.lightColor)
      ) {
        lightColor = ticketFeature.lightColor;
      }
    }
  }

  if (!backgroundUrl) {
    backgroundUrl = "https://img.festapp.net/default.jpg";
  }

  // Fetch eshop resources (both product types and products) via RPC.
  const { data: eshopData, error: eshopError } = await supabaseAdmin.rpc(
    "get_products_and_types",
    { p_occasion_id: ticket.occasion }
  );

  if (eshopError || !eshopData) {
    throw new Error(
      `Error fetching eshop resources: ${eshopError?.message}`
    );
  }

  // Extract the product types and products from the returned JSON.
  const productTypes = eshopData.product_types || [];
  const products = eshopData.products || [];

  // Build a lookup for product types: product_type_id -> type string.
  const productTypeLookup: Record<number, string> = {};
  productTypes.forEach((pt: any) => {
    productTypeLookup[pt.id] = pt.type;
  });

  // Group products into a map of maps: { [productType: string]: { [productId: number]: product } }
  const productTypeMap: Record<string, Record<number, any>> = {};
  products.forEach((product: any) => {
    const typeStr = productTypeLookup[product.product_type];
    if (typeStr) {
      if (!productTypeMap[typeStr]) {
        productTypeMap[typeStr] = {};
      }
      productTypeMap[typeStr][product.id] = product;
    }
  });

  // Download the background image.
  const bgResponse = await fetch(backgroundUrl);
  if (!bgResponse.ok) {
    throw new Error(`Failed to download background: ${backgroundUrl}`);
  }
  const backgroundBytes = new Uint8Array(await bgResponse.arrayBuffer());

  // Download the custom font.
  const fontResponse = await fetch(CUSTOM_FONT_URL);
  if (!fontResponse.ok) {
    throw new Error(`Failed to download custom font: ${CUSTOM_FONT_URL}`);
  }
  const customFontBytes = new Uint8Array(await fontResponse.arrayBuffer());

  return {
    darkColor,
    lightColor,
    productTypeMap,
    backgroundBytes,
    customFontBytes,
  };
}

export async function generateTicketImage(
  ticket: any,
  resources: {
    darkColor: string;
    lightColor: string;
    productTypeMap: Record<string, Record<number, any>>;
    backgroundBytes: Uint8Array;
    customFontBytes: Uint8Array;
  },
  custom?: LayoutTicketRequest
): Promise<Uint8Array> {
  if (custom) {
    const result=await drawLayoutTicket(custom.data,custom.resources,custom.template,custom.type,custom.sample);
    custom.warnings.push(...result.warnings);
    return result.bytes;
  }
  try {
    const {
      darkColor,
      lightColor,
      productTypeMap,
      backgroundBytes,
      customFontBytes,
    } = resources;

    // Retrieve the products from the productTypeMap for each product type.
    // Since productTypeMap is now a map of maps keyed by product id,
    // we use the ticket.order_product_ticket to find the corresponding product.
    const spotTicketOpt = ticket.order_product_ticket.find(
      (opt: any) => productTypeMap["spot"] && productTypeMap["spot"][opt.product]
    );
    const spotProduct = spotTicketOpt ? productTypeMap["spot"][spotTicketOpt.product] : undefined;

    const foodTicketOpt = ticket.order_product_ticket.find(
      (opt: any) => productTypeMap["food"] && productTypeMap["food"][opt.product]
    );
    const foodProduct = foodTicketOpt ? productTypeMap["food"][foodTicketOpt.product] : undefined;

    const taxiTicketOpt = ticket.order_product_ticket.find(
      (opt: any) => productTypeMap["taxi"] && productTypeMap["taxi"][opt.product]
    );
    const taxiProduct = taxiTicketOpt ? productTypeMap["taxi"][taxiTicketOpt.product] : undefined;

    // Create the PDF document.
    const pdfDoc = await PDFDocument.create();

    // Register fontkit to enable embedding custom fonts.
    pdfDoc.registerFontkit(fontkit);

    const pageWidth = 595.28;
    const pageHeight = 841.89;
    const page = pdfDoc.addPage([pageWidth, pageHeight]);

    // Embed and draw the background image.
    let bgImage;
    try {
      bgImage = await pdfDoc.embedJpg(backgroundBytes);
    } catch (e) {
      bgImage = await pdfDoc.embedPng(backgroundBytes);
    }

    const bgWidth = bgImage.width;
    const bgHeight = bgImage.height;
    const marginPercentage = 0.05;
    const margin = (pageWidth * (marginPercentage * 2)) / 2;
    const scale = (pageWidth * (1 - marginPercentage * 2)) / bgWidth;
    const bgX = (pageWidth - bgWidth * scale) / 2;
    const bgY = (pageHeight - margin) - bgHeight * scale;

    page.drawImage(bgImage, {
      x: bgX,
      y: bgY,
      width: bgWidth * scale,
      height: bgHeight * scale,
    });

    // Generate QR Code and embed it.
    const qrSize = 240 * scale;
    const qrX = bgX + (bgWidth * scale) - qrSize - 150 * scale;
    const qrY = bgY + 140 * scale;

    const qrData = await QRCode.toDataURL(ticket.ticket_symbol, {
      width: qrSize,
      margin: 1.6,
      color: {
        dark: `#${darkColor}`,
        light: `#${lightColor}C0`,
      },
    });

    const rawQR = qrData.split(",")[1];
    // Convert base64 string to Uint8Array.
    const qrBytes = Uint8Array.from(atob(rawQR), (c) => c.charCodeAt(0));
    const qrImage = await pdfDoc.embedPng(qrBytes);

    page.drawImage(qrImage, {
      x: qrX,
      y: qrY,
      width: qrSize,
      height: qrSize,
    });

    // Draw the ticket symbol text directly below the QR Code.
    const qrTextPadding = 10 * scale;
    const qrFontSize = 28 * scale;
    const ticketSymbol = ticket.ticket_symbol;
    const customFont = await pdfDoc.embedFont(customFontBytes);
    const ticketSymbolTextWidth = customFont.widthOfTextAtSize(ticketSymbol, qrFontSize);
    const ticketSymbolX = qrX + qrSize / 2 - ticketSymbolTextWidth / 2;
    const ticketSymbolY = qrY - qrTextPadding - qrFontSize;
    const textColor = hexToRgb(darkColor);

    page.drawText(ticketSymbol, {
      x: ticketSymbolX,
      y: ticketSymbolY,
      size: qrFontSize,
      font: customFont,
      color: textColor,
    });

    // Prepare the starting positions for additional text.
    let textX = bgX + 150 * scale;
    let textY = bgY + 280 * scale;

    const texts = [];

    // Add Spot Title.
    const spotOrder = ticket.order_product_ticket.find(
      (opt: any) => spotProduct && opt.product === spotProduct.id
    );
    if (spotOrder && spotOrder.spot_group_title) {
      texts.push(`Stůl: ${truncateText(spotOrder.spot_group_title)}`);
    }

    // Add Food Title.
    if (foodProduct) {
      const foodTitle = foodProduct.short_title || foodProduct.title || "N/A";
      texts.push(`Večeře: ${truncateText(foodTitle)}`);
    }

    // Add Ticket Note if available.
    if (ticket.note && ticket.note.trim() !== "") {
      texts.push(`Poznámka: ${truncateText(ticket.note)}`);
    }

    // Add Ticket Price not null.
    if (ticket.price != null) {
          texts.push(`Cena: ${formatCurrency(ticket.price, ticket.currency_code)}`);
    }

    texts.forEach((text) => {
      page.drawText(text, {
        x: textX,
        y: textY,
        size: 40 * scale,
        font: customFont,
        color: textColor,
      });
      textY -= 50 * scale;
    });

    const pdfBytes = await pdfDoc.save();
    return pdfBytes;
  } catch (error) {
    console.error("Error generating ticket PDF:", error);
    throw error;
  }

  // Helper function to convert a hex color string to a PDF-lib rgb color.
  function hexToRgb(hex: string) {
    const r = parseInt(hex.substring(0, 2), 16) / 255;
    const g = parseInt(hex.substring(2, 4), 16) / 255;
    const b = parseInt(hex.substring(4, 6), 16) / 255;
    return rgb(r, g, b);
  }

  function truncateText(text: string, maxLength: number = MAX_TEXT_ON_TICKET): string {
    const trimmed = text.trim();
    return trimmed.length > maxLength ? trimmed.slice(0, maxLength) + "..." : trimmed;
  }
}

export interface LayoutTicketRequest {data:RenderData;resources:Resources;template:Template;type:'wide'|'named';sample:boolean;warnings:string[]}
async function drawLayoutTicket(data:RenderData,r:Resources,t:Template,_type:'wide'|'named'=t.page.width===595.28?'wide':'named',sample=false) {
  validateLayout({schemaVersion:1,templates:{[_type]:t}});
  const doc=await PDFDocument.create();doc.registerFontkit(fontkit);
  const font=await doc.embedFont(r.font);const page=doc.addPage([t.page.width,t.page.height]);const warnings:string[]=[];
  const color=(hex:string)=>rgb(...([0,2,4].map(i=>parseInt(hex.slice(i,i+2),16)/255) as [number,number,number]));
  const image=async(bytes:Uint8Array,b:any)=>{
    const img=bytes[0]===137?await doc.embedPng(bytes):await doc.embedJpg(bytes);
    const scale=Math.min(b.width/img.width,b.height/img.height);
    page.drawImage(img,{x:b.x+(b.width-img.width*scale)/2,y:b.y+(b.height-img.height*scale)/2,width:img.width*scale,height:img.height*scale});
  };
  const area=pdfBox(t,{x:0,y:0,width:t.ticketArea.width,height:t.ticketArea.height});
  page.drawRectangle({...area,color:rgb(.9,.9,.9)});
  if(r.background)await image(r.background,area);
  for(const e of t.elements.filter(e=>e.visible && e.binding!=='qr')) {
    const b=pdfBox(t,e.box);
    if(e.binding==='logo') {if(r.logo)await image(r.logo,b);continue;}
    const text=data[e.binding];if(!text)continue;
    const fit=fitText(text,e,r.metrics);if(fit.overflow||fit.replaced)warnings.push(e.binding);
    fit.lines.forEach((line,i)=>{
      let x=b.x+(e.style.align==='center'?(b.width-fit.widths[i])/2:e.style.align==='right'?b.width-fit.widths[i]:0);
      const y=t.page.height-t.ticketArea.y-e.box.y-r.metrics.ascent*fit.size-i*fit.size*1.2;
      for(const c of Array.from(line)) {page.drawText(c,{x,y,size:fit.size,font,color:color(e.style.color)});x+=(r.metrics.advances[c]??r.metrics.advances['?'])*fit.size;}
    });
  }
  const q=t.elements.find(e=>e.binding==='qr')!;const b=pdfBox(t,q.box);
  const qr=QRCode.create(data.qr!,{errorCorrectionLevel:'M'}).modules;
  const module=b.width/(qr.size+8);if(module<1.2)throw new Error('QR modules are too small for print');
  page.drawRectangle({...b,color:rgb(1,1,1)});
  for(let y=0;y<qr.size;y++)for(let x=0;x<qr.size;x++)if(qr.get(y,x))page.drawRectangle({x:b.x+(x+4)*module,y:b.y+b.height-(y+5)*module,width:module,height:module,color:color(q.style.color)});
  if(sample)page.drawText('VZOR',{x:4,y:Math.max(1,t.page.height-6),size:5,font,color:rgb(1,0,0)});
  return {bytes:await doc.save(),warnings};
}
