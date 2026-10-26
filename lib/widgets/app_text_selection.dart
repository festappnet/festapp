import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// One selection region for web pages, including headers and rendered HTML.
class AppTextSelection extends StatelessWidget {
  const AppTextSelection({
    super.key,
    required this.child,
    this.enabled = kIsWeb,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    // MaterialApp's builder is above the Navigator overlay. Selection handles
    // and context menus need an overlay above the selection region itself.
    return Overlay.wrap(child: SelectionArea(child: child));
  }
}
