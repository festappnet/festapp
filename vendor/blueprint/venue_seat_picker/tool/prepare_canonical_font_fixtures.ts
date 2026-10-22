/** Offline only. Uses the host's canonical shaper with packaged immutable fonts.
 * deno run --allow-read --allow-write tool/prepare_canonical_font_fixtures.ts \
 *   /path/to/host/supabase/functions/_shared /tmp/requests.json assets/layout_fonts
 * Requests come from export_fixture_requests_test.dart (both bundled locales).
 * Existing layouts are retained for editor and consumer test corpora.
 */
const [sharedPath, requestsPath, assetsPath] = Deno.args;
if (!sharedPath || !requestsPath || !assetsPath) {
  throw new Error('Expected shared module directory, request JSON and font assets directory');
}
const shared = new URL(`file://${sharedPath.replace(/\/$/, '')}/`);
const { prepareLayoutTextResources } = await import(new URL('layoutTextResources.ts', shared).href);
const { fontCatalog, fontMetrics, digest } = await import(new URL('ticketFonts.ts', shared).href);
const assets = assetsPath.replace(/\/$/, '');
const manifest = JSON.parse(await Deno.readTextFile(`${assets}/manifest.json`));
const fixturesPath = `${assets}/fixtures.json`;
const fixtures = JSON.parse(await Deno.readTextFile(fixturesPath));
if (fixtures.protocol !== 2 || manifest.protocol !== 2) throw new Error('Canonical protocol 2 required');
const tickets = new Map();
async function resolve(id: string) {
  if (tickets.has(id)) return tickets.get(id);
  const asset = manifest.fixtures.find((f: { id: string }) => f.id === id);
  const entry = fontCatalog.find((f: { id: string }) => f.id === id);
  if (!asset || !entry) throw new Error(`Unbundled font ${id}`);
  const bytes = await Deno.readFile(`${assets}/${asset.file}`);
  if (await digest(bytes) !== entry.sha256 || entry.sha256 !== asset.sha256) {
    throw new Error(`Bundled font hash mismatch ${id}`);
  }
  const ticket = { id, bytes, metrics: fontMetrics(bytes), family: entry.family, weight: entry.weight };
  tickets.set(id, ticket);
  return ticket;
}
const requests = JSON.parse(await Deno.readTextFile(requestsPath));
const numericFaces = Object.values(manifest.fontFamilies).flatMap((raw) => {
  const family = raw as { id: string; faces: Record<string, string> };
  return Object.values(family.faces).map((fontFaceId) => ({ fontFamilyId: family.id, fontFaceId }));
});
const previous = Object.keys(fixtures.textLayouts).length;
for (let offset = 0; offset < requests.length; offset += 32) {
  const prepared = await prepareLayoutTextResources({
    requests: requests.slice(offset, offset + 32),
    numericFaces: offset === 0 ? numericFaces : [],
  }, resolve);
  Object.assign(fixtures.fontFamilies, prepared.fontFamilies);
  Object.assign(fixtures.textLayouts, prepared.textLayouts);
  Object.assign(fixtures.numberSymbols, prepared.numberSymbols);
}
await Deno.writeTextFile(fixturesPath, JSON.stringify(fixtures));
console.log(`Prepared ${requests.length} requests; preserved ${previous} existing layouts; now ${Object.keys(fixtures.textLayouts).length} layouts.`);
