import {
  type CanvasKit,
  init,
  type Paragraph,
  type TypefaceFontProvider,
} from "https://deno.land/x/canvas@v1.4.2/mod.ts";

export const paymentQrSize = 384;
const imageWidth = 480;
const textInset = 32;
const textWidth = imageWidth - textInset * 2;

interface PaymentQrCaption {
  title: string;
  recipient: string;
  amount: string;
  reference: string;
}

let typography:
  | Promise<{ kit: CanvasKit; fonts: TypefaceFontProvider }>
  | undefined;

function loadTypography() {
  typography ??= (async () => {
    const fontData = await Deno.readFile(
      new URL("./ticket-assets/roboto.ttf", import.meta.url),
    );
    const kit = await init();
    const fonts = kit.TypefaceFontProvider.Make();
    fonts.registerFont(fontData, "Roboto");
    return { kit, fonts };
  })().catch((error) => {
    typography = undefined;
    throw error;
  });
  return typography;
}

export async function decoratePaymentQr(
  png: Uint8Array,
  caption: PaymentQrCaption,
): Promise<Uint8Array> {
  const { kit, fonts } = await loadTypography();
  const qr = kit.MakeImageFromEncoded(png);
  if (!qr) throw new Error("payment_qr_image_decode_failed");

  const paragraphs: { text: Paragraph; offset: number }[] = [];
  let top = paymentQrSize + 8;
  const addParagraph = (
    value: string,
    size: number,
    color: Float32Array,
    gap: number,
    bold = false,
  ) => {
    if (!value) return;
    const builder = kit.ParagraphBuilder.MakeFromFontProvider(
      new kit.ParagraphStyle({
        textAlign: kit.TextAlign.Center,
        textStyle: {
          fontFamilies: ["Roboto"],
          fontSize: size,
          color,
          fontStyle: {
            weight: bold ? kit.FontWeight.Bold : kit.FontWeight.Normal,
          },
        },
      }),
      fonts,
    );
    try {
      builder.addText(value);
      const text = builder.build();
      paragraphs.push({ text, offset: top });
      text.layout(textWidth);
      top += text.getHeight() + gap;
      return text;
    } finally {
      builder.delete();
    }
  };

  try {
    const ink = kit.Color(23, 31, 44);
    const title = addParagraph(caption.title, 34, ink, 6, true);
    if (title && title.getLineMetrics().length > 2) {
      top = paragraphs.pop()!.offset;
      title.delete();
      addParagraph(caption.title, 29, ink, 6, true);
    }
    addParagraph(caption.recipient, 26, kit.Color(71, 84, 103), 16);
    const details = addParagraph(
      [caption.amount, caption.reference].filter(Boolean).join("  ·  "),
      26,
      ink,
      0,
    );
    if (
      details && caption.reference && details.getMaxIntrinsicWidth() > textWidth
    ) {
      top = paragraphs.pop()!.offset;
      details.delete();
      addParagraph(caption.amount, 26, ink, 4);
      addParagraph(caption.reference, 26, ink, 0);
    }

    const surface = kit.MakeSurface(imageWidth, Math.ceil(top + 28));
    if (!surface) throw new Error("payment_qr_surface_failed");
    try {
      const canvas = surface.getCanvas();
      canvas.clear(kit.WHITE);
      // Copy the original symbol with its quiet zone at native resolution.
      canvas.drawImage(qr, (imageWidth - paymentQrSize) / 2, 0);
      for (const { text, offset } of paragraphs) {
        canvas.drawParagraph(text, textInset, offset);
      }
      const image = surface.makeImageSnapshot();
      try {
        const bytes = image.encodeToBytes();
        if (!bytes) throw new Error("payment_qr_image_encode_failed");
        return new Uint8Array(bytes);
      } finally {
        image.delete();
      }
    } finally {
      surface.dispose();
    }
  } finally {
    for (const { text } of paragraphs) text.delete();
    qr.delete();
  }
}
