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
