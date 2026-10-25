import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:async';

import 'package:cross_file/cross_file.dart' as cross;
import 'package:fstapp/services/import_file.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/platform_helper.dart';
import 'package:fstapp/theme_config.dart';

/// MIME types considered valid image files when checking dropped items.
const _mimeToExt = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
};

class DropFile extends StatefulWidget {
  /// Called when a single file is dropped/selected (first valid file).
  final FutureOr<void> Function(ImportFile) onFilePathChanged;

  /// Called when multiple valid files are found (e.g. folder drop).
  /// If null, only [onFilePathChanged] is called with the first file.
  final FutureOr<void> Function(List<ImportFile>)? onMultipleFilesChanged;

  /// Optional hint text (e.g. what files, dimensions, etc.) displayed above the upload icon.
  final String? hint;
  final Future<ImportFile?> Function()? pickFile;

  /// List of allowed file extensions (e.g. ['jpg', 'png']).
  final List<String>? allowedExtensions;

  /// Height of the drop area.
  final double height;
  final bool dropEnabled;
  final bool singleFileOnly;
  final VoidCallback? onInvalidDrop;

  const DropFile({
    super.key,
    required this.onFilePathChanged,
    this.onMultipleFilesChanged,
    this.hint,
    this.pickFile,
    this.allowedExtensions,
    this.height = 250,
    this.dropEnabled = true,
    this.singleFileOnly = false,
    this.onInvalidDrop,
  });

  @override
  _DropFileState createState() => _DropFileState();
}

class _DropFileState extends State<DropFile> {
  ImportFile? file;
  int _fileCount = 0;
  bool _dragging = false;
  Offset? offset;

  /// Check whether a single [DropItem] passes the extension / MIME filter.
  bool _isAllowed(ImportFile item) {
    if (widget.allowedExtensions == null) return true;

    final name = item.name.toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    final ext = dotIndex >= 0 ? name.substring(dotIndex + 1) : '';

    if (ext.isNotEmpty && widget.allowedExtensions!.contains(ext)) return true;

    // Fallback: check MIME type
    final mime = item.mimeType?.toLowerCase() ?? '';
    final mimeExt = _mimeToExt[mime];
    return mimeExt != null && widget.allowedExtensions!.contains(mimeExt);
  }

  Future<List<ImportFile>> _flattenDropItems(List<DropItem> items) async {
    final result = <ImportFile>[];
    ImportFile fromFile(cross.XFile file, String name, [String? mimeType]) =>
        ImportFile(
          name: name,
          mimeType: mimeType,
          readBytes: file.readAsBytes,
          size: file.length,
        );
    Future<void> directory(cross.XDirectory container) async {
      await for (final entity in container.list()) {
        if (entity is cross.XDirectory) {
          await directory(entity);
        } else if (entity is cross.XFile) {
          result.add(fromFile(entity, await entity.name() ?? ''));
        }
      }
    }

    for (final item in items) {
      if (item is DropDirectoryItem) {
        await directory(item.directory);
      } else if (item is DropFileItem) {
        result.add(fromFile(item.file, item.name, item.mimeType));
      }
    }
    return result;
  }

  Future<void> _deliver(List<ImportFile> selected) async {
    if (selected.isEmpty || !mounted) return;
    final delivered = widget.onMultipleFilesChanged == null
        ? [selected.first]
        : selected;
    // Await consumers so provider access survives their reads. Consumers that
    // keep a file beyond this callback must retain its content explicitly.
    setState(() {
      file = selected.first;
      _fileCount = selected.length;
    });
    if (delivered.length > 1 && widget.onMultipleFilesChanged != null) {
      await widget.onMultipleFilesChanged!(delivered);
    } else {
      await widget.onFilePathChanged(delivered.first);
    }
  }

  Future<void> _pickFile() async {
    if (widget.pickFile != null) {
      final picked = await widget.pickFile!();
      if (!mounted || picked == null) return;
      await _deliver([await picked.retain()]);
      return;
    }
    if (!PlatformHelper.isWeb) return;

    final List<PlatformFile> selected;
    final type = widget.allowedExtensions != null
        ? FileType.custom
        : FileType.any;
    if (widget.onMultipleFilesChanged != null) {
      selected = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: widget.allowedExtensions,
      );
    } else {
      final picked = await FilePicker.pickFile(
        type: type,
        allowedExtensions: widget.allowedExtensions,
      );
      selected = picked == null ? [] : [picked];
    }
    if (!mounted) return;

    await _deliver(
      selected
          .map(
            (picked) => ImportFile(
              name: picked.name,
              readBytes: picked.readAsBytes,
              size: picked.length,
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isClickable = widget.pickFile != null || PlatformHelper.isWeb;
    bool isCompact = widget.height < 160;
    double iconSize = isCompact ? 32 : 50;
    double iconSpacing = isCompact ? 6 : 12;

    return DropTarget(
      enabled: widget.dropEnabled,
      operation: DropOperation.copy,
      acceptedKinds: const {DropItemKind.file, DropItemKind.directory},
      onDrop: (detail) => ExceptionHandler.guardVoid(
        context,
        futureFunction: () async {
          if (!widget.dropEnabled) return;
          final items = detail.items
              .where(
                (item) => item is DropFileItem || item is DropDirectoryItem,
              )
              .toList();
          if (items.isEmpty) return;
          if (widget.singleFileOnly &&
              (items.length != 1 || items.single is! DropFileItem)) {
            widget.onInvalidDrop?.call();
            return;
          }
          final allFiles = await _flattenDropItems(items);
          final valid = allFiles.where(_isAllowed).toList();
          if (widget.singleFileOnly && valid.isEmpty) {
            widget.onInvalidDrop?.call();
            return;
          }
          await _deliver(valid);
        },
      ),
      onMove: (details) {
        setState(() {
          offset = details.localPosition;
        });
      },
      onEnter: (detail) {
        setState(() {
          _dragging = true;
          offset = detail.localPosition;
        });
      },
      onLeave: () {
        setState(() {
          _dragging = false;
          offset = null;
        });
      },
      child: InkWell(
        onTap: isClickable ? _pickFile : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: widget.height,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _dragging
                ? Colors.blue.withValues(alpha: 0.2)
                : ThemeConfig.grey200(context),
            border: Border.all(
              color: _dragging ? Colors.blue : ThemeConfig.grey380(context),
              width: 2,
            ),
          ),
          child: Center(
            child: file == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_upload,
                        size: iconSize,
                        color: _dragging
                            ? Colors.blue
                            : ThemeConfig.grey600(context),
                      ),
                      SizedBox(height: iconSpacing),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          isClickable
                              ? CommonStrings.dropFileHereOrClick
                              : CommonStrings.dropFileHere,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _dragging
                                ? Colors.blue
                                : ThemeConfig.grey600(context),
                          ),
                        ),
                      ),
                      if (widget.hint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            widget.hint!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _dragging
                                  ? Colors.blue
                                  : ThemeConfig.grey600(context),
                            ),
                          ),
                        ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.insert_drive_file,
                        size: iconSize,
                        color: Colors.green,
                      ),
                      SizedBox(height: iconSpacing),
                      Text(
                        _fileCount > 1
                            ? '${file!.name} (+${_fileCount - 1})'
                            : file!.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ThemeConfig.grey800(context),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
