# Festapp Tickets repository presentation

## Intended result

An English repository homepage led by Festapp Tickets, with current light-mode
screenshots of ticketing and the companion event app at mobile screen sizes.
Keep Festapp as the platform name and explain vstupenky.online as its regional
portal. Update GitHub's short description and homepage to match.

## Plan

1. Read the current documentation, branding rules and capture workflow. Bring
   `main` up to date without changing unrelated work.
2. Capture real current UI in an isolated, muted, headless browser. Use disposable
   English examples, English controls and light mode. Show ticket purchase and
   management, plus the event app's mobile map and schedule. Record capture
   provenance; identify mobile browser captures accurately.
3. Rewrite the README around the organizer and attendee journeys. Put product
   links and screenshots before developer instructions. Keep the architecture,
   setup, offline limitations and contribution references concise and accurate.
4. Check local Markdown/image targets, image dimensions and the diff. No runtime
   code changes are planned, so no canonical application CI lane is affected.
5. Fetch main again, account for any upstream changes, commit only these docs and
   screenshots, publish through the required pull request, and verify GitHub's
   README, description and homepage.

## Assumptions and boundaries

- Scope is repository presentation, not a tenant deployment or product release.
- Screenshots must come from rendered UI, not translated or invented mockups.
- No live customer data or production mutations are needed.
- A mobile viewport demonstrates responsive web UI, not a native app capture.
- Historical feature screenshots remain separate from the new homepage gallery.

## Execution

- Reconnaissance complete. Main fast-forwarded from `94ba7063c` to `99dc29ae7`;
  the intervening work concerns MCP connections. Two pre-existing untracked plan
  files matched upstream byte-for-byte and were preserved before fast-forward.
- Browser capture delegated to Terra under the owner's standing browser rules.
- GitHub description and homepage now point to Festapp Tickets. Main requires
  one approving review, so publish the documentation via a PR without bypassing
  that rule. No application deployment is involved.
- Captured and visually inspected four new PNGs: seat selection with its price,
  orders, mobile map and mobile schedule. Provenance is recorded beside the images.
- Before publication, fetched main again and rebased onto `c5d32e6a3`.
  The intervening changes concern form measurement and payment settings, not
  the captured seating renderer, order table, map or schedule. Capture revision
  remains explicitly recorded as `99dc29ae7`.
- Documentation validation covers local link/image targets, PNG decoding and
  dimensions, total image size, and whitespace. Application code is unchanged.
- Follow-up: replaced the homepage's two generic mobile examples with three
  real Slunovrat Winter Edition views (program, Opava map, artist detail).
  The owner authorized local English translation; only browser presentation
  responses were translated, without editing the live event. These are explicitly
  labelled mobile web captures at iPhone dimensions, not native iOS captures.
  The static GitHub-style preview displays them in phone frames.
