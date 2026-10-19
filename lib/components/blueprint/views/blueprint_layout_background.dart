import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../../images/db_images.dart';
import '../blueprint_layout_resources.dart';
import '../blueprint_strings.dart';

/// The existing image service processes uploads; this only applies its verified
/// asset to the package geometry draft, for either an occasion or a setup unit.
Future<void> pickBlueprintBackground({required VenueLayoutController controller,
    required BlueprintLayoutAssetResolver assets, required bool Function() isMounted,
    int? occasionId, int? unitId}) async {
      final selection = await FilePicker.pickFiles(type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'svg'], withData: true);
      if (selection == null || !isMounted()) return;
      final bytes = selection.files.single.bytes;
      if (bytes == null) throw StateError('image_bytes_unavailable');
      final uploaded = await DbImages.uploadImageWithResult(bytes,
          occasionId, unitId,
          profile: ImageUploadProfile.blueprintBackground);
      if (!isMounted()) return;
      final asset = uploaded.asset!;
      final resources = await assets.resolve({...controller.resources,
        'assets': {...controller.resources['assets'] as Map? ?? {},
          asset['assetRef']: asset}});
      if (!isMounted()) return;
      final document = controller.document;
      final canvas = document.canvas;
      final width = (asset['width'] as num).toDouble();
      final height = (asset['height'] as num).toDouble();
      if (!controller.setResources(resources)) throw StateError('invalid_layout_resources');
      final applied = controller.apply(document.copyWith(background: {
        'assetRef': asset['assetRef'], 'hash': asset['hash'],
        'width': width, 'height': height,
        'x': (canvas['x'] as num) + (canvas['width'] as num) / 2,
        'y': (canvas['y'] as num) + (canvas['height'] as num) / 2,
        'scale': math.min((canvas['width'] as num) / width, (canvas['height'] as num) / height),
        'rotation': 0, 'opacity': 1,
        'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
      }), label: BlueprintStrings.background);
      if (!applied) throw StateError('background_rejected');
}
