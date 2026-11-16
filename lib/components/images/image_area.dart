import 'package:fstapp/services/import_file.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/images/image_url_helper.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/drop_file.dart';

/// onFileSelected now returns the new public URL
typedef FileUploadCallback = Future<String?> Function(ImportFile file);

class ImageArea extends StatefulWidget {
  /// Initial image URL
  final String? imageUrl;

  /// Optional rendered preview; upload and removal behavior remain shared.
  final Widget? preview;

  /// Called when a file is dropped/selected. Must return the uploaded image's URL.
  final FileUploadCallback onFileSelected;

  /// Called when the user wants to remove the current image.
  final VoidCallback onRemove;

  /// Optional hint text to display above the drop zone.
  final String? hint;

  /// Controls if the user can change or remove the image.
  final bool enabled;
  final double dropHeight;
  final bool dropEnabled;
  final List<String>? allowedExtensions;

  const ImageArea({
    super.key,
    required this.imageUrl,
    required this.onFileSelected,
    required this.onRemove,
    this.hint,
    this.dropHeight = 250,
    this.preview,
    this.enabled = true,
    this.dropEnabled = true,
    this.allowedExtensions,
  });

  @override
  _ImageAreaState createState() => _ImageAreaState();
}

class _ImageAreaState extends State<ImageArea> {
  String? _currentUrl;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.imageUrl;
  }

  @override
  void didUpdateWidget(ImageArea old) {
    super.didUpdateWidget(old);
    // keep in sync if parent gives a new URL
    if (widget.imageUrl != old.imageUrl) {
      _currentUrl = widget.imageUrl;
    }
  }

  Future<void> _handleFileSelected(ImportFile file) async {
    if (!mounted || !widget.enabled || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final uploadedUrl = await widget.onFileSelected(file);
      if (!mounted) return;
      setState(() {
        if (uploadedUrl != null) _currentUrl = uploadedUrl;
      });
    } catch (e) {
      AppLogger.error("Error: $e");
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we're uploading, show a spinner
    if (_uploading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // If there was an error, show it with a retry option
    if (_error != null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 40, color: ThemeConfig.redColor(context)),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ThemeConfig.redColor(context), fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    // If we have a URL (either initial or newly uploaded), show it
    if (_currentUrl != null && _currentUrl!.isNotEmpty) {
      final colors = Theme.of(context).colorScheme;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          // Keep the action clear of the image, including custom crop previews.
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 56),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: widget.preview ?? Image.network(
                ImageUrlHelper.transformImageUrl(_currentUrl!, width: ImageUrlHelper.mediumWidth),
                height: 200,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, size: 40, color: ThemeConfig.grey600(context)),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: ThemeConfig.grey600(context)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: IconButton.filled(
              tooltip: CommonStrings.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: widget.enabled ? widget.onRemove : null,
              style: IconButton.styleFrom(
                backgroundColor: colors.errorContainer,
                foregroundColor: colors.onErrorContainer,
                minimumSize: const Size(48, 48),
                maximumSize: const Size(48, 48),
              ),
            ),
          ),
        ],
      );
    }

    // Otherwise, show the drop/select area.
    // Wrap with IgnorePointer and Opacity to disable interaction and give visual feedback.
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.5,
        child: DropFile(
          height: widget.dropHeight,
          hint: widget.hint,
          dropEnabled: widget.enabled && widget.dropEnabled,
          allowedExtensions: widget.allowedExtensions ??
              const ['jpg', 'jpeg', 'png', 'webp', 'heic'],
          onFilePathChanged: (file) => _handleFileSelected(file),
        ),
      ),
    );
  }
}
