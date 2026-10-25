import 'package:fstapp/services/import_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/toast_helper.dart';

import 'editor_file_drop_strings.dart';

const editorRasterExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif'];

/// Plugin listeners bypass hit testing, including Offstage and modal barriers.
/// Check every enclosing route, including the route above a nested Navigator.
bool editorFileDropIsActive(BuildContext context) {
  if (!context.mounted || !TickerMode.valuesOf(context).enabled) return false;
  var active = ModalRoute.of(context)?.isCurrent ?? true;
  context.visitAncestorElements((element) {
    if (element.widget is Navigator) {
      active = active && (ModalRoute.of(element)?.isCurrent ?? true);
    }
    return active;
  });
  return active;
}

/// Owns external file-drop interaction only. The host owns validation/import.
class EditorFileDropRegion extends StatefulWidget {
  const EditorFileDropRegion({
    super.key,
    required this.enabled,
    required this.active,
    required this.hint,
    required this.allowedExtensions,
    required this.onFileDropped,
    required this.child,
  });
  final bool enabled;
  final bool active;
  final String hint;
  final List<String> allowedExtensions;
  final Future<void> Function(ImportFile) onFileDropped;
  final Widget child;

  @override
  State<EditorFileDropRegion> createState() => _EditorFileDropRegionState();
}

class _EditorFileDropRegionState extends State<EditorFileDropRegion> {
  bool _hover = false;
  bool _busy = false;
  bool get _enabled =>
      widget.enabled &&
      widget.active &&
      !_busy &&
      editorFileDropIsActive(context);

  @override
  void didUpdateWidget(EditorFileDropRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || !widget.active) _hover = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!editorFileDropIsActive(context)) _hover = false;
  }

  Future<void> _drop(DropDetails details) async {
    if (_hover) setState(() => _hover = false);
    if (!_enabled) return;
    final files = details.items
        .where((item) => item is DropFileItem || item is DropDirectoryItem)
        .toList();
    String? error;
    if (files.length != 1 || files.first is! DropFileItem) {
      error = EditorFileDropStrings.singleFile;
    } else if (!widget.allowedExtensions.contains(
      (files.single as DropFileItem).name.toLowerCase().split('.').last,
    )) {
      error = EditorFileDropStrings.unsupported;
    }
    if (error != null) {
      ToastHelper.Show(context, error, severity: ToastSeverity.NotOk);
      return;
    }
    setState(() => _busy = true);
    try {
      final item = files.single as DropFileItem;
      // Await the consumer before returning; the provider stays live throughout.
      await widget.onFileDropped(
        ImportFile(
          name: item.name,
          mimeType: item.mimeType,
          readBytes: item.file.readAsBytes,
          size: item.file.length,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to nearest route changes as well as retained-tab TickerMode.
    final active =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        _enabled;
    return DropTarget(
      enabled: active,
      operation: DropOperation.copy,
      acceptedKinds: const {DropItemKind.file, DropItemKind.directory},
      onEnter: (_) {
        if (_enabled) setState(() => _hover = true);
      },
      onLeave: () {
        if (mounted && _hover) setState(() => _hover = false);
      },
      onDrop: _drop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_hover && active)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer
                        .withValues(alpha: .9),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.hint,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
