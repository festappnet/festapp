# Occasion setup usability - implementation result

Scope: vstupenky.online, canonical main plus only `prod/festapptickets`. The original heavily dirty checkout is preserved; implementation uses `../festapp-setup-usability-20261021`. The user explicitly authorized publication and production deployment with every ready change. GitHub had no open PRs; ready work is already merged on main. Current runtime was identified as main `f4aa0b6ed`, not the old dirty checkout.

## Requirement coverage

| Screenshot | Result and evidence |
|---|---|
| 1-2 | Explicit From scratch plus shared searchable ProjectPicker; groups, dates, stable IDs and duplicate-title disambiguation. Metadata-only startup, lazy selected detail, page-local identity/unit/source cache, failed requests retry, staged atomic selection. SQL cross-tenant/permission tests and real duplicate-title browser selection. |
| 3 | One server clock rounded up to half hour in unit timezone, exact slot retained, end follows by civil days. Manual end edits are retained and validated. SQL exact/midnight/timezone tests. |
| 4 | Ticketing-only presentation/location questions skipped; they do not impose wizard readiness validation. Existing metadata editors remain available. Story tests. |
| 5 | Existing allocator suggests underscore-separated title/year addresses through a suffix field action. SQL/Dart permit underscores, existing JS readers already do. Server collision handling and alias compatibility tests. No mass rename. |
| 6 | Ticket fields determine ticketing vs registration wording in questions, summaries and sale badges. SQL projects `has_tickets`; no translated-title inference. Six locale namespaces. |
| 7 | Existing wave scheduler supplies a calendar-month default, clamps month-end and valid future/event bounds, preserves existing wave time, explains no valid slot/missing event end. Core tests cover boundaries. Draft mode retains its no-live-write adapter. |
| 8 | No confirmation checkbox. Positive selected account ID plus fingerprint drives readiness; server revalidates linked account, currency and permissions under locks. SQL and widget tests. |
| 9 | Shared effective deadline resolver, inherited null remains null after unrelated saves, explicit zero accepted, restore inheritance action. Core and communication tests. |
| 10 | Explanatory communication copy and default settings action have normal vertical spacing. |
| 11-12 | Stable none/new/copy mode owns geometry and derived spot field. Canonical schema2 editor, supported schema1 adapter, actual seat/area bindings determine counts, no decoration count, no first-plan fallback. Explicit save awaits durable draft revision; dirty close asks to discard; save failures retain retry. None removes active geometry/spot field without deleting products. Registered model/editor tests plus transactional materialization tests. |
| 13 | Scanner question removed from basic wizard; later ticket scanning settings preserved. Historical scanner step resumes at supported team question. |
| 14 | Unit-public-listing intent stored separately from sale mode. Finalized event stays hidden/closed; explicit Publish applies listing choice through existing versioned occasion update. Existing explicit form preparation/scheduled/immediate intent remains independent. Public visibility flags are not replaced by promotion. |
| 15 | Customer preview and its wizard initialization removed; real form editor and ticket appearance editor retained. |
| 16 | Completion uses shared saved FormPublicLink/CopyButton; draft link is not presented as an already saved public URL. Existing copy baseline tests pass. |
| 17-19 | Existing main header placement retained; informational status has no button/tooltip/independent hover/focus. Complete availability detail remains in semantics; parent card and edit menu stay active. Widget tests. |
| 20 | Existing muted inactive-card implementation retained and verified. Paused/hidden/ended states are distinct from future scheduled sales, administrative actions remain available. Widget coverage includes dark theme, narrow cards and large text. |

## Verification

- Final registered targeted Flutter sessions: 100 passed, including the new immediate form-decoding regression and the affected editor/card/copy/story tests.
- Core model tests: 9 passed (price scheduling and form definition).
- Occasion SQL: 10 passed; public link SQL: 1 passed including underscore roundtrips and preserved aliases. After integrating newer main sale-query code, affected usability and sales tests passed separately.
- Integrated main web DOM-ready startup tests: 8 passed.
- `automation/tests/apply_config.test.sh`: passed. Targeted analyzer reports no errors/warnings in affected feature paths; existing informational style findings remain. Whole changed-file analysis also surfaced the preexisting mutable MyApp field warning in main.dart.
- New migration is the mechanically checked canonical SQL bundle, including the latest bounded sale availability query. The local transaction applied successfully. Modern plan-binding cleanup is performed before products during event deletion to avoid a confirmed FK failure; regression deletes the finalized copy while preserving its source.
- Measurements and full raw samples: [evidence](../archive/occasion-setup-usability-performance-2026-10-21/evidence/README.md). Source startup body 329376 B -> 936 B. Repeated UI times are similar; no claim of a diagnosed production latency cause.

## Deliberate compatibility boundary

Plain historical grid data without supported/reviewed geometry is explicitly unavailable for adoption. The user can choose another plan or create a new one; no production source plan conversion occurs. Modern schema2 and supported schema1 use the existing canonical adapter/editor. The deployed old full-source RPC remains as a documented compatibility entrypoint while old clients still call it; all source paths share one private projection. Remove that RPC only after those clients are retired.

The reproduced conversion failure was an untyped spot-field map constructed during normalization. It failed immediate form decoding before a JSON autosave roundtrip. The map now has an explicit string-key type, with a regression exercising that exact in-memory boundary.

## Release

Production backend identity was resolved through tenant activation and matched protected SSH/runtime/database assertions and organization 3. Historical rehearsal names are the documented canonical live target. The nine main migrations after the documented baseline, including canonical authorization, are already present. Five earlier ledger/effect gaps remain preexisting and were not replayed or represented as reconciled by this release. Release scope adds only `20261022000000_occasion_setup_usability_performance.sql` before the new client. Prior function definitions/ACLs and additive-signature rollback must be captured; repeated schema/constraint DDL is real DDL even where its final shape already matches.

Real isolated browser verification completed both journeys: copied 180-seat plan edited/saved/finalized, source canvas still 1200 while the new draft saved 1300; fresh default plan saved/finalized with 72 seats. Draft resume after application reload worked. Public listing enabled -> explicit Publish produced hidden=false/open=true while formOpen=false; listing disabled -> hidden=true/open=true while formOpen=false. No implicit sale opening. Cards inspected at 1440 px light and 390 px actual dark theme, with long titles and working administrative menu.

The local new-template check initially lacked the default Roboto storage service. An owned loopback fixture served the exact vendored font bytes through the existing TicketFontR2 transport and real resolver/hash validation/shaping. This verifies the client/Edge/draft journey, not production R2 grants. The launcher now copies complete owned Edge files rather than a symlink and accepts an explicit FESTAPP_WIZARD_EDGE_ENV input. See browser-result.json and font-fixture.py in the evidence directory. The retry action distinguishes editor-open errors from source-picker errors.

Final source/tenant revisions, migration application, build and live-version verification are recorded in the release receipt after execution.
