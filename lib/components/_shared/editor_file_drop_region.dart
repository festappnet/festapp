import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
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
  final Future<void> Function(XFile) onFileDropped;
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

  Future<void> _drop(DropDoneDetails details) async {
    if (_hover) setState(() => _hover = false);
    if (!_enabled) return;
    String? error;
    if (details.files.length != 1 || details.files.first is DropItemDirectory) {
      error = EditorFileDropStrings.singleFile;
    } else if (!widget.allowedExtensions
        .contains(details.files.single.name.toLowerCase().split('.').last)) {
      error = EditorFileDropStrings.unsupported;
    }
    if (error != null) {
      ToastHelper.Show(context, error, severity: ToastSeverity.NotOk);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onFileDropped(details.files.single);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to nearest route changes as well as retained-tab TickerMode.
    final active = (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        _enabled;
    return DropTarget(
      enable: active,
      onDragEntered: (_) {
        if (_enabled) setState(() => _hover = true);
      },
      onDragExited: (_) {
        if (mounted && _hover) setState(() => _hover = false);
      },
      onDragDone: _drop,
      child: Stack(fit: StackFit.expand, children: [
        widget.child,
        if (_hover && active)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: .9),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.primary, width: 3),
                ),
                child: Center(
                    child: Text(widget.hint,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer))),
              ),
            ),
          ),
      ]),
    );
  }
}
