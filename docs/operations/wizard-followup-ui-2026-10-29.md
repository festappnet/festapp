# Wizard follow-up UI and editing parity - 2026-10-29

Additional real UI exploration after the earlier wizard QA and reliability work.
One new reproducible UX defect was fixed locally: choosing Blank layout opened
the template gallery a second time inside the editor.

## Environment and boundaries

- Product source `7d9f2ff62`; subsequent HEAD `00f05276d` only adds release documentation. Final build also includes the local gallery fix described below.
- Real Flutter release application, `test/browser/occasion_setup_e2e.dart`, isolated headless `agent-browser`, API `127.0.0.1:56921`, UI `127.0.0.1:56982`.
- Reused retained synthetic data in `festapp-wizard-backend-qa-20261029`. No reset or production mutation. Verified Test Organization, paused email queue, absent worker URL, zero active cron jobs and zero email messages before testing.
- External backend/push domains blocked; OneSignal resolve/reject callbacks use the established fixture. Local Edge ticket preview was started separately. Missing local font storage configuration prevents claiming a complete PDF rendering check.
- Some Flutter controls required their DOM semantics click rather than CDP pointer click. Form changes were typed through focused inputs and confirmed through database readback. This establishes UI handlers and persistence, not all physical hit targets.

## Additional scenarios

| UI scenario | Result |
| --- | --- |
| Existing Ocean action -> ordinary Settings -> change venue -> Save | Occasion 85 saved `QA parity hall 29`; forms/products, exact ticket layout and custom Reply-to unchanged. Only ordinary settings defaults were materialized. |
| Used manual form address plus negative product price | Both displayed their specific validation errors and blocked continuation. Correcting address and price enabled progression. |
| Ticket quantity 0 | Normalized to the supported default of 1; final `ticket.max_tickets=1`. |
| New Forest appearance, zero price, scheduled sales, catalogue listing disabled | Created hidden occasion 136 / form 139 through UI, with Open Sans, selected gradient and scheduled start/end. Payment-only questions disappeared for zero price. |
| Manual form address -> Review -> Edit event name -> Review -> Create | Address remained `qa-parity-d-20261029`; form title followed the renamed event. |
| Select Blank layout -> save empty plan -> Continue | Empty selected plan blocked continuation. Selecting No seating plan then allowed continuation; final occasion contains zero blueprints. |
| Created occasion -> Manage event -> Forms -> Schedule & Limits | Ordinary editor displayed the wizard's scheduled start/end and disabled countdown. |
| Form Settings -> rename form and select Informal -> Save -> physical reload | Name and tone persisted; manual address, design and exact schedule unchanged. Browser URL retained `/forms/qa-parity-d-20261029/settings`, with Forms and Settings selected. |

Persistence assertions are recorded in [readback](wizard-followup-ui-2026-10-29/readback.json). All event/draft mutations above used the UI; SQL was used for readback only.

## Fixed: duplicate gallery after choosing a blank plan

Minimal real UI reproduction: new wizard -> Venue -> Create a seating plan ->
Blank layout. The wizard opens the editor, which immediately prompts for another
template. A second selection is required to reach the blank canvas.

The editor automatically opens its gallery whenever its document has no nodes.
An explicitly selected blank template satisfies that condition. The host now
passes `openGalleryOnStart=false` for explicitly supplied documents, while
keeping the manual gallery available and preserving automatic prompting for
other hosts by default.

The regression exercises the actual wizard template caller: choose blank, assert
that the editor is open without another gallery, open the gallery manually,
choose a populated template, and assert no canonical text preparation requests.
The pre-fix run failed on the duplicate-gallery assertion. The final targeted
Flutter run passed. The final compiled UI also passed: a fresh wizard F opened
the blank canvas after a single selection; Choose template still opened the
gallery manually. [Before](wizard-followup-ui-2026-10-29/gallery.png) and
[after](wizard-followup-ui-2026-10-29/blank-fixed.png). An initial two-case expansion exposed cached fixture state
between cases; the final regression uses one continuous user journey instead.

## Remaining coverage limits

- Wizard date/time pickers could not be reliably opened through this session's semantics/pointer automation. No overnight or DST picker result is claimed; the event uses its initial dates. The draft's original working title mentioned overnight, but that scenario was not completed.
- Inline/both ticket-delivery selection, live external font storage/PDF, real payment, email delivery, OAuth, organization verification and invitation delivery were not validated.
- This is targeted exploration, not exhaustive parity or combinatorial certification. No deployment or publication was performed.

## Verification and final workspace

- `fvm flutter test --concurrency=1 test/components/occasion/occasion_setup_blueprint_open_test.dart`: 1 discovered regression journey passed. The populated-template variant also passed in a separate isolated diagnostic run.
- Targeted `fvm dart analyze` on the four changed Dart files: no errors or warnings, 14 informational diagnostics.
- Release app compiled successfully and the corrected flow passed in the isolated headless browser.
- Exact source/evidence snapshot moved, with SHA256 verification, from shared main to `/Users/miakh/source/festapp-blueprint-active-20261029`, branch `wip/blueprint-active-20261029`, base `00f05276d`. The move did not change tested product bytes. No commit, push or deployment.
- Browser, owned UI server, local Edge process and this QA Supabase project stopped. Data retained. Final [queue guard](wizard-followup-ui-2026-10-29/final-queue-guard.json): zero messages, zero active cron jobs, paused queue without worker URL.
