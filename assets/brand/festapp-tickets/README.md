# Festapp Tickets

Canonical source assets for the global ticketing identity. The asymmetric ticket is based on the owner's `source/Festapp_Tickets_asymmetric.svg`, with the outer ticket contour and typography normalized to the approved vstupenky.online identity. Contact: **info@festapp.net**. This source work does not deploy or change a production tenant.

The name is **Festapp Tickets**. The global symbol has a navy left half, blue right half and the uploaded stepped internal separation. It intentionally differs from the regional V-shaped interior. Both identities share the exact outer corner and notch curves. The separator is transparent on transparent assets.

## Masters and exports

All files use the `festapp-tickets-` prefix. Each SVG and PNG master has a light version and `-dark` companion:

- `square`: complete logo on a square background.
- `transparent`: complete stacked logo without background, SVG and PNG.
- `symbol`: standalone ticket without background, SVG and PNG.
- `wordmark`: stacked outlined lettering without the ticket, SVG and PNG.
- `header`: horizontal ticket and stacked lettering for navigation, SVG and PNG.
- `icon`: square background and symbol, SVG and PNG; 32, 64 and 180px PNG sizes.
- `linkedin-300` and `linkedin-400`: complete square logo PNG avatars.
- `social`: 1200 x 630 SVG/PNG sharing image.
- `loading`: SVG outline/fill reveal, with the regional 4.4-second timeline, then a 2.2-second pulse. Reduced motion shows the static complete logo.
- `web-icons/`: favicon ICO, 16/32px PNG, Apple 180px and Android 192/512px PNG and the web app manifest.

`festapp-tickets-logos.zip` packages the 48 deliverables and their SHA-256 manifest. `preview.html` opens directly from disk and shows comparisons, variants, downloads and loading animations. `proof/` contains outer-contour overlays.

## Rebuild and verification

Run `uv run assets/brand/festapp-tickets/tools/build_vectors.py` from any directory. Its dependencies are declared in the script. It reads the canonical regional symbol, `../vstupenky-online/source/Roboto-Bold.ttf`, and the regional loading timeline. It does not rewrite regional assets, app adapters or tenant configuration.

Each lettering row is a boolean union of the exact font glyphs, flattened into one path with tracking -0.035em, matching the regional lettering method. SVG masters contain no raster images, text elements, font references, filters or gradients. Light/dark variants use identical geometry with the foreground changed.

`vector-verification.json` records the source/font digests, uploaded glyph differences, and zero symmetric-difference area against the real regional geometry in the complete left/right edge bands. Those bands include all four exterior corner curves and both side notches. The new interior separation is preserved intentionally.

The uploaded outlines were close, but not identical: its ticket aspect ratio was 494/244 rather than 632/309; its left and right corner extents also differed from each other. None of the 14 uploaded glyph contours exactly matched the canonical font. See `AUDIT.md` for measured differences.
