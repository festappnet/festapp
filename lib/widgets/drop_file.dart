import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
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
  final void Function(XFile) onFilePathChanged;

  /// Called when multiple valid files are found (e.g. folder drop).
  /// If null, only [onFilePathChanged] is called with the first file.
  final void Function(List<XFile>)? onMultipleFilesChanged;

  /// Optional hint text (e.g. what files, dimensions, etc.) displayed above the upload icon.
  final String? hint;

  /// List of allowed file extensions (e.g. ['jpg', 'png']).
  final List<String>? allowedExtensions;

  /// Height of the drop area.
  final double height;

  const DropFile({
    super.key,
    required this.onFilePathChanged,
    this.onMultipleFilesChanged,
    this.hint,
    this.allowedExtensions,
    this.height = 250,
  });

  @override
  _DropFileState createState() => _DropFileState();
}

class _DropFileState extends State<DropFile> {
  XFile? file;
  int _fileCount = 0;
  bool _dragging = false;
  Offset? offset;

  /// Check whether a single [DropItem] passes the extension / MIME filter.
  bool _isAllowed(XFile item) {
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

  /// Recursively extract all leaf files from a list of [DropItem]s,
  /// flattening any [DropItemDirectory] children.
  List<DropItem> _flattenDropItems(List<DropItem> items) {
    final result = <DropItem>[];
    for (final item in items) {
      if (item is DropItemDirectory) {
        result.addAll(_flattenDropItems(item.children));
      } else {
        result.add(item);
      }
    }
    return result;
  }

  Future<void> _pickFile() async {
    if (!PlatformHelper.isWeb) return;

    FilePickerResult? result = await FilePicker.pickFiles(
      type: widget.allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: widget.allowedExtensions,
      allowMultiple: widget.onMultipleFilesChanged != null,
    );

    if (result != null && result.files.isNotEmpty) {
      final xFiles = <XFile>[];
      for (final picked in result.files) {
        if (picked.bytes != null) {
          xFiles.add(XFile.fromData(picked.bytes!, name: picked.name));
        } else if (picked.path != null) {
          xFiles.add(XFile(picked.path!, name: picked.name));
        }
      }
      if (xFiles.isEmpty) return;

      setState(() {
        file = xFiles.first;
        _fileCount = xFiles.length;
      });

      if (xFiles.length > 1 && widget.onMultipleFilesChanged != null) {
        widget.onMultipleFilesChanged!(xFiles);
      } else {
        widget.onFilePathChanged(xFiles.first);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isClickable = PlatformHelper.isWeb;
    bool isCompact = widget.height < 160;
    double iconSize = isCompact ? 32 : 50;
    double iconSpacing = isCompact ? 6 : 12;

    return DropTarget(
      onDragDone: (detail) async {
        if (detail.files.isEmpty) return;

        // Flatten directories into individual files
        final allFiles = _flattenDropItems(detail.files);
        if (allFiles.isEmpty) return;

        // Filter by allowed extensions / MIME types
        final valid = widget.allowedExtensions != null
            ? allFiles.where(_isAllowed).toList()
            : allFiles;
        if (valid.isEmpty) return;

        setState(() {
          file = valid.first;
          _fileCount = valid.length;
        });

        if (valid.length > 1 && widget.onMultipleFilesChanged != null) {
          widget.onMultipleFilesChanged!(valid);
        } else {
          widget.onFilePathChanged(valid.first);
        }
      },
      onDragUpdated: (details) {
        setState(() {
          offset = details.localPosition;
        });
      },
      onDragEntered: (detail) {
        setState(() {
          _dragging = true;
          offset = detail.localPosition;
        });
      },
      onDragExited: (detail) {
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
