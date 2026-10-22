# Occasion setup types and appearance - integration verification

Implemented on authoritative main `56a56e506a11fccbbc4c62938455c9d53a36caab`, retaining current venue-layout, bank membership, invitation, pricing and communication behavior. The older dirty development checkout remains untouched.

- Flutter: 40 targeted story, shared appearance, preview-definition and responsive/keyboard navigation tests passed. After the final active-field projection change, 33 affected contract tests passed; unchanged shell/panel tests were not repeated.
- Targeted Dart analyzer: no errors; existing/style informational diagnostics remain.
- SQL: migration applied to the disposable local canonical-baseline backend using its administrative role. All 13 occasion_setup test scripts passed, including authorized cross-unit sources, copy isolation, finalization, invitations, sales and the new private type/style projection. Fixtures are rolled back. Local fixture sequence was advanced past explicitly seeded organization IDs.
- Deno: 46 layout/preview tests passed, including actual PDF axial shading, strict layout metadata and authorized own-draft preview.
- Web client: saved shared appearance reaches the actual FormModel/ThemeService and resets correctly for another form (Node test passed).

The server projection excludes inactive seating/tickets without rewriting the saved draft. Existing clients without eventKind remain compatible. The migration adds optional gradient readers and leaves existing events unchanged. Publish order: SQL, canonical Edge bundle, tenant client. Actual production revision and live probes are recorded separately by the release operation.
