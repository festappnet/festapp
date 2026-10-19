import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/widgets/drop_file.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../../images/db_images.dart';
import '../blueprint_layout_resources.dart';
import '../blueprint_strings.dart';

const blueprintBackgroundExtensions = ['png', 'jpg', 'jpeg', 'webp', 'svg'];

Future<XFile?> _pickBackgroundFile() async {
  final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: blueprintBackgroundExtensions,
      withData: true);
  if (selection == null) return null;
  final file = selection.files.single;
  if (file.bytes == null) throw StateError('image_bytes_unavailable');
  return XFile.fromData(file.bytes!, name: file.name);
}

/// Selection only: opening or cancelling this dialog never uploads an image.
Future<XFile?> showBlueprintBackgroundPicker(BuildContext context,
    {Future<XFile?> Function()? pickFile}) {
  String? error;
  var selected = false;
  return showDialog<XFile>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(builder: (context, setState) {
      void close() {
        selected = true;
        Navigator.of(dialogContext).pop();
      }

      return AppAlertDialog(
        key: const ValueKey('blueprint-background-picker'),
        title: Text(BlueprintStrings.background),
        onClose: close,
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Semantics(
                      liveRegion: true,
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                DropFile(
                  height: 220,
                  hint: 'PNG, JPG, JPEG, WebP, SVG',
                  allowedExtensions: blueprintBackgroundExtensions,
                  pickFile: () async {
                    try {
                      return await (pickFile ?? _pickBackgroundFile)();
                    } catch (failure) {
                      if (context.mounted) {
                        setState(() => error = failure.toString());
                      }
                      return null;
                    }
                  },
                  onFilePathChanged: (file) {
                    if (selected || !dialogContext.mounted) return;
                    selected = true;
                    Navigator.of(dialogContext).pop(file);
                  },
                ),
              ],
            ))),
      );
    }),
  );
}

/// The existing image service processes uploads; this only applies its verified
/// asset to the package geometry draft, for either an occasion or a setup unit.
Future<void> uploadBlueprintBackground(
    {required XFile selection,
    required VenueLayoutController controller,
    required BlueprintLayoutAssetResolver assets,
    required bool Function() isMounted,
    int? occasionId,
    int? unitId}) async {
  if (!isMounted()) return;
  final bytes = await selection.readAsBytes();
  if (!isMounted()) return;
  final uploaded = await DbImages.uploadImageWithResult(
      bytes, occasionId, unitId,
      profile: ImageUploadProfile.blueprintBackground);
  if (!isMounted()) return;
  final asset = uploaded.asset!;
  final resources = await assets.resolve({
    ...controller.resources,
    'assets': {
      ...controller.resources['assets'] as Map? ?? {},
      asset['assetRef']: asset
    }
  });
  if (!isMounted()) return;
  final document = controller.document;
  final canvas = document.canvas;
  final width = (asset['width'] as num).toDouble();
  final height = (asset['height'] as num).toDouble();
  if (!controller.setResources(resources))
    throw StateError('invalid_layout_resources');
  final applied = controller.apply(
      document.copyWith(background: {
        'assetRef': asset['assetRef'],
        'hash': asset['hash'],
        'width': width,
        'height': height,
        'x': (canvas['x'] as num) + (canvas['width'] as num) / 2,
        'y': (canvas['y'] as num) + (canvas['height'] as num) / 2,
        'scale': math.min((canvas['width'] as num) / width,
            (canvas['height'] as num) / height),
        'rotation': 0,
        'opacity': 1,
        'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
      }),
      label: BlueprintStrings.background);
  if (!applied) throw StateError('background_rejected');
}
