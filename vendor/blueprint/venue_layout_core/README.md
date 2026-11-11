# Venue layout core

Pure Dart immutable venue layout documents, geometry, validation, generators and deterministic scene paths shared by Flutter and JavaScript.

```dart
import 'package:venue_layout_core/venue_layout_core.dart';

final document = tableLayout(shape: 'ellipse', count: 6);
final issues = validateDocument(document);
final scene = compileScene(document, resources: fontResources);
final seat = hitTest(document, 400, 382);
```

Fonts are explicit resource snapshots containing glyph outlines, never runtime text fallback. The package has no Flutter, network, storage or booking dependencies. Geometry uses centered local boxes with clockwise rotations and immutable parent transforms. Serialize through `toJson`, decode with `VenueLayoutDocument.fromJson`, and validate before accepting a new document. Unsupported schemas throw `UnsupportedLayoutSchema` retaining the original data.

See repository `doc/blueprint-v2/CORE-API.md` for protocol 1 and additional operations. Run tests with `dart test`; the repository uses its FVM SDK for reproducibility.


Physical placement uses `collisionIndexFor(document)` for every obstacle kind:
seats, tables, furniture and explicitly marked obstacles. Its immutable hulls,
candidate queries and cache belong to the geometry module. Table/bar movement,
chair reflow, automatic seat fitting and `layoutCollisions` share that owner.
Groups contribute through their physical descendants; ordinary artwork remains
decorative. `LayoutSpatialIndex` keeps precise rendered pointer hit areas. Both
indices share the same internal spatial buckets; appearance work is paid only
when rendered hit testing needs it. A new immutable document gets a new index.
