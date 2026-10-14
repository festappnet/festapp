# Demo artwork

Generated with the built-in image_gen tool; exact prompts are in `prompts.json`.
The five JPEG assets are versioned, optimized to a maximum 1600 px edge, and
published without overwriting existing objects at:
`https://img.festapp.net/images/demo-occasions/20261014/<filename>`.

The three covers live in `occasion.data.image`; only ball/concert have ticket
backgrounds. Backgrounds contain no baked-in ticket text or QR. Editable schema-3
layouts in the parent directory own all text and QR geometry. Concert is
320 x 480 pt portrait; ball is 580 x 290 pt landscape; both add 3 mm white paper
margins. QR uses vector modules and an opaque four-module white quiet zone.

After uploading and checking the assets, run `automation/refresh_demo_artwork.sql`
with the explicitly authorized `demo_organization`. It locks only registered
version `2026-10-14.3` in that tenant, resolves its own product-type IDs, registers
media for the ordinary picker/copier, and records configuration invalidation.
It does not touch orders, payments, ticket identities or operational mail.
The standard demo seeder calls the same maintenance function, so replay uses
exactly these assets and layouts. Maintenance is idempotent.

`deno run --allow-read --allow-write database/fixtures/demo_occasions/render.ts`
uses the actual shared PDF renderer and checks demo and copied variants for text
warnings. Generated PDF evidence is in `docs/plans/demo-occasions-evidence-2026-10-14`.
