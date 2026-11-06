/** Build-time entry for the standalone demo. The production shaper remains the
 * sole owner; the distributed bundle only adapts licensed, same-origin fonts. */
import {prepareLayoutTextResources} from '../../supabase/functions/_shared/layoutTextResources.ts';
import {fontCatalog,fontMetrics,digest,TicketFontError,type TicketFont} from '../../supabase/functions/_shared/ticketFonts.ts';

declare const document: {baseURI: string};
const fonts = new Map<string,Promise<TicketFont>>();
let manifest: Promise<{fixtures:Array<{id:string;file:string;sha256:string}>}>;
async function resolve(id: string) {
  if (!fonts.has(id)) fonts.set(id, (async () => {
    const base = new URL('assets/packages/venue_seat_picker/assets/layout_fonts/', document.baseURI);
    manifest ??= fetch(new URL('manifest.json',base)).then(r => {
      if (!r.ok) throw new TicketFontError('font_unavailable');
      return r.json();
    });
    const entry = (await manifest).fixtures.find(f => f.id === id);
    const asset = fontCatalog.find(f => f.id === id);
    if (!entry || !asset || !/^[\w.-]+\.ttf$/.test(entry.file)) throw new TicketFontError('font_unavailable');
    const response = await fetch(new URL(entry.file,base));
    if (!response.ok) throw new TicketFontError('font_unavailable');
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (await digest(bytes) !== entry.sha256 || entry.sha256 !== asset.sha256)
      throw new TicketFontError('font_integrity');
    return {id,bytes,metrics:fontMetrics(bytes),family:asset.family,weight:asset.weight};
  })().catch(error => {fonts.delete(id);throw error;}));
  return fonts.get(id)!;
}
Object.assign(globalThis, {venueLayoutPrepareText: async (input: string) =>
  JSON.stringify(await prepareLayoutTextResources(JSON.parse(input),resolve))});
