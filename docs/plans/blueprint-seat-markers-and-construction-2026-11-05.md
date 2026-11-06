# Seat state markers and applicable construction controls

## Scope and decision

Fix in canonical source `/private/tmp/festapp-venue-current`, based on the source
revision recorded by `vendor/blueprint/manifest.json`. Import verified archives;
never edit the dependency snapshot directly. Preserve unrelated local changes.

1. Derive the usable seat surface from existing chair outline contours. Reuse it
   for occupied, selected and pending markers in the shared scene compiler.
   Center markers on the cushion, scale them to it, preserve upright selected
   checks and object rotation for other states. No new persisted style fields.
2. Show construction families only for seats, tables and furniture in the
   inspector and object appearance dialog. Preserve group/global family tools,
   ordinary fills, outlines, corner controls and saved style inheritance.
3. Regression-test seven chair styles, rotation, all three markers, partial-scene
   parity and applicable inspector controls. Rebuild the shared JS kernel and
   verified package archives, then import them into Festapp.

## Related findings and limits

Material families also supply corner radius and stroke width through the existing
cascade. Ordinary shapes can therefore respond to a family even though they have
no furniture construction. Hide the misleading furniture chooser rather than
changing saved style semantics. Keep explicit generic geometry controls.

Couch cushions and stools have their own outlines; derive markers from those
contours too. Do not add separate Flutter/JS rendering rules or marker styling
that could obscure availability meaning. Existing presentation colors and state
precedence remain unchanged. No production deployment or registry publication.

## Completed validation

- Canonical source commit: `c069b04d6eb738c01dbc2afdc095b359001d264f`.
- Existing host focus/navigation additions were preserved in canonical source
  before packaging; the previous dependency tree is retained as local Git object
  `92c6a785500a2aba6b1f19f20b49aac797440fda`.
- 33 targeted core tests passed, including seven styles and all marker states.
- Five new inspector/dialog cases passed; the 18 existing appearance, quick-dialog
  and render-parity cases passed as well.
- Distribution gate passed: four clean-consumer tests, 15 browser scenes and
  archived Flutter boot, with actual source-byte verification.
- Host integration passed: four focus-navigation tests and the archive/lock/hash
  consistency contract. Frozen pnpm install succeeded.
- Imported JS archive: `festapp-venue-layout-0.3.9-a167f6fadc9f.tgz`.
  The previous selected archive is retained under the ignored
  `.codex-artifacts/blueprint/seat-markers-20261105/previous-inputs/` directory.
- No registry publication or production deployment was performed.
