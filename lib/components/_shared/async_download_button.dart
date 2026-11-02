import 'package:material_ui/material_ui.dart';

import '../../services/exception_handler.dart';

/// A download remains one action through generation and saving the file.
class AsyncDownloadButton extends StatefulWidget {
  const AsyncDownloadButton({
    super.key,
    required this.label,
    required this.loadingLabel,
    required this.onDownload,
    this.iconOnly = false,
  });

  final String label, loadingLabel;
  final Future<void> Function()? onDownload;
  final bool iconOnly;

  @override
  State<AsyncDownloadButton> createState() => _AsyncDownloadButtonState();
}

class _AsyncDownloadButtonState extends State<AsyncDownloadButton> {
  bool _busy = false;

  Future<void> _download() async {
    final action = widget.onDownload;
    if (_busy || action == null) return;
    setState(() => _busy = true);
    try {
      await ExceptionHandler.guard(context, futureFunction: action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.download_outlined);
    final label = _busy ? widget.loadingLabel : widget.label;
    final onPressed = _busy || widget.onDownload == null ? null : _download;
    return Semantics(
      liveRegion: _busy,
      child: widget.iconOnly
          ? IconButton(icon: icon, tooltip: label, onPressed: onPressed)
          : TextButton.icon(
              icon: icon,
              label: Text(label),
              onPressed: onPressed,
            ),
    );
  }
}
