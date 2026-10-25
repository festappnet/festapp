import '../../images/image_upload_limits.dart';
import '../../_shared/editor_file_drop_strings.dart';
import '../../images/image_file_format.dart';

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fstapp/services/import_file.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/widgets/drop_file.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../../images/db_images.dart';
import '../../images/image_control_client.dart';
import '../blueprint_layout_resources.dart';
import '../blueprint_strings.dart';

const blueprintBackgroundExtensions = [
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
  'svg',
];
const blueprintGraphicExtensions = blueprintBackgroundExtensions;

Future<ImportFile?> _pickBackgroundFile({
  bool graphic = false,
  List<String>? extensions,
}) async {
  final selection = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions:
        extensions ??
        (graphic ? blueprintGraphicExtensions : blueprintBackgroundExtensions),
  );
  if (selection == null) return null;
  final file = selection.single;
  return ImportFile(
    name: file.name,
    readBytes: file.xFile.readAsBytes,
    size: file.length,
  );
}

/// Selection only: opening or cancelling this dialog never uploads an image.
Future<ImportFile?> showBlueprintBackgroundPicker(
  BuildContext context, {
  Future<ImportFile?> Function()? pickFile,
  bool graphic = false,
  List<String>? extensions,
}) {
  String? error;
  var selected = false;
  return showDialog<ImportFile>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        void close() {
          selected = true;
          Navigator.of(dialogContext).pop();
        }

        return AppAlertDialog(
          key: const ValueKey('blueprint-background-picker'),
          title: Text(
            graphic
                ? BlueprintStrings.insertGraphic
                : BlueprintStrings.background,
          ),
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
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  DropFile(
                    height: 220,
                    singleFileOnly: true,
                    onInvalidDrop: () => setState(
                      () => error = EditorFileDropStrings.singleFile,
                    ),
                    hint:
                        extensions?.map((e) => e.toUpperCase()).join(', ') ??
                        (graphic
                            ? 'PNG, JPG, JPEG, WebP, GIF, SVG'
                            : 'PNG, JPG, JPEG, WebP, GIF, SVG'),
                    allowedExtensions:
                        extensions ??
                        (graphic
                            ? blueprintGraphicExtensions
                            : blueprintBackgroundExtensions),
                    pickFile: () async {
                      try {
                        return await (pickFile ??
                            () => _pickBackgroundFile(
                              graphic: graphic,
                              extensions: extensions,
                            ))();
                      } catch (failure) {
                        if (context.mounted) {
                          setState(() => error = failure.toString());
                        }
                        return null;
                      }
                    },
                    onFilePathChanged: (file) async {
                      if (selected || !dialogContext.mounted) return;
                      if (await file.length() >
                          ImageUploadLimits.maxInputBytes) {
                        throw FormatException(EditorFileDropStrings.tooLarge);
                      }
                      final retained = await file.retain();
                      if (selected || !dialogContext.mounted) return;
                      selected = true;
                      Navigator.of(dialogContext).pop(retained);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// The existing image service processes uploads; this only applies its verified
/// asset to the package geometry draft, for either an occasion or a setup unit.
Future<void> uploadBlueprintBackground({
  required ImportFile selection,
  required VenueLayoutController controller,
  required BlueprintLayoutAssetResolver assets,
  required bool Function() isMounted,
  int? occasionId,
  int? unitId,
  Future<ImageUploadResult> Function(Uint8List bytes)? uploadBitmap,
}) async {
  if (!isMounted()) return;
  final asset = await _uploadBitmap(
    selection: selection,
    controller: controller,
    assets: assets,
    isMounted: isMounted,
    occasionId: occasionId,
    unitId: unitId,
    uploadBitmap: uploadBitmap,
  );
  if (!isMounted()) return;
  final document = controller.document;
  final canvas = document.canvas;
  final width = (asset['width'] as num).toDouble();
  final height = (asset['height'] as num).toDouble();
  final applied = controller.apply(
    document.copyWith(
      background: {
        'assetRef': asset['assetRef'],
        'hash': asset['hash'],
        'width': width,
        'height': height,
        'x': (canvas['x'] as num) + (canvas['width'] as num) / 2,
        'y': (canvas['y'] as num) + (canvas['height'] as num) / 2,
        'scale': math.min(
          (canvas['width'] as num) / width,
          (canvas['height'] as num) / height,
        ),
        'rotation': 0,
        'opacity': 1,
        'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
      },
    ),
    label: BlueprintStrings.background,
  );
  if (!applied) throw StateError('background_rejected');
}

Future<Map<String, dynamic>> _uploadBitmap({
  required ImportFile selection,
  required VenueLayoutController controller,
  required BlueprintLayoutAssetResolver assets,
  required bool Function() isMounted,
  int? occasionId,
  int? unitId,
  Future<ImageUploadResult> Function(Uint8List bytes)? uploadBitmap,
}) async {
  if (await selection.length() > ImageUploadLimits.maxInputBytes) {
    throw FormatException(EditorFileDropStrings.tooLarge);
  }
  final bytes = await selection.readAsBytes();
  ImageFileFormat.detect(bytes, allowSvg: true);
  if (!isMounted()) throw StateError('graphic_import_cancelled');
  final uploaded =
      await (uploadBitmap?.call(bytes) ??
          DbImages.uploadImageWithResult(
            bytes,
            occasionId,
            unitId,
            profile: ImageUploadProfile.blueprintBackground,
          ));
  if (!isMounted()) throw StateError('graphic_import_cancelled');
  final asset = uploaded.asset!;
  final requested = <String, dynamic>{
    'protocol': 2,
    'assets': {
      asset['assetRef']: {
        for (final key in [
          'hash',
          'url',
          'width',
          'height',
          'mimeType',
          'byteLength',
        ])
          key: asset[key],
      },
    },
  };
  final resources = await assets.resolve(requested);
  if (!isMounted()) throw StateError('graphic_import_cancelled');
  if (!commitBlueprintImages(
    controller,
    requestedResources: requested,
    resolvedResources: resources,
    addAssets: true,
  ))
    throw StateError('invalid_layout_resources');
  return asset;
}

/// Signatures identify bitmaps; the SVG parser verifies bounded XML inputs.
/// Long authoring comments before the root must not turn valid SVG into a bitmap.
ImageFileFormat blueprintGraphicFormat(Uint8List bytes) {
  const svgLimit = 2097152;
  try {
    final format = ImageFileFormat.detect(bytes, allowSvg: true);
    if (format == ImageFileFormat.svg && bytes.length > svgLimit)
      throw const GraphicImportFailure('svg_input_limit');
    return format;
  } on FormatException {
    if (bytes.length > svgLimit) {
      if (utf8
          .decode(bytes.take(2048).toList(), allowMalformed: true)
          .trimLeft()
          .startsWith('<'))
        throw const GraphicImportFailure('svg_input_limit');
      rethrow;
    }
    if (utf8.decode(bytes, allowMalformed: false).trimLeft().startsWith('<'))
      return ImageFileFormat.svg;
    rethrow;
  }
}

Future<void> uploadBlueprintGraphic({
  required ImportFile selection,
  required VenueLayoutController controller,
  required BlueprintLayoutAssetResolver assets,
  required bool Function() isMounted,
  required Future<SvgTextOutline> Function(SvgTextRequest) prepareText,
  int? occasionId,
  int? unitId,
  Future<ImageUploadResult> Function(Uint8List bytes)? uploadBitmap,
}) async {
  if (!isMounted()) return;
  if (await selection.length() > ImageUploadLimits.maxInputBytes) {
    throw FormatException(EditorFileDropStrings.tooLarge);
  }
  final bytes = await selection.readAsBytes();
  final format = blueprintGraphicFormat(bytes);
  if (format == ImageFileFormat.svg) {
    final source = utf8.decode(bytes, allowMalformed: false);
    final imported = await importSvgGraphicWithText(
      source,
      prepareText: prepareText,
    );
    if (!isMounted()) return;
    if (!controller.insertVectorGraphic(
      imported.graphic,
      originalSource: imported.originalSource,
      label: selection.name,
    ))
      throw StateError(controller.error ?? 'graphic_import_rejected');
  } else {
    final asset = await _uploadBitmap(
      selection: ImportFile.fromData(bytes, name: selection.name),
      controller: controller,
      assets: assets,
      isMounted: isMounted,
      occasionId: occasionId,
      unitId: unitId,
      uploadBitmap: uploadBitmap,
    );
    if (!isMounted()) return;
    if (!controller.insertBitmapAsset(
      asset['assetRef'] as String,
      label: selection.name,
    ))
      throw StateError(controller.error ?? 'graphic_import_rejected');
  }
}
