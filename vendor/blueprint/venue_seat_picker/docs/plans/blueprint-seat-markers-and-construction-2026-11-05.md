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
