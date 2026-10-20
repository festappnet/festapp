import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Route-scoped Escape dismissal shared by document editors and host dialogs.
class EditorDialogDismissal extends StatefulWidget {
  const EditorDialogDismissal({
    super.key,
    required this.child,
    this.onClose,
    this.enabled = true,
    this.autofocus = true,
  });

  final Widget child;
  final VoidCallback? onClose;
  final bool enabled;
  final bool autofocus;

  @override
  State<EditorDialogDismissal> createState() => _EditorDialogDismissalState();
}

class _EditorDialogDismissalState extends State<EditorDialogDismissal> {
  ModalRoute<dynamic>? _route;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_escapeOutside);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  KeyEventResult _escapeOutside(KeyEvent event) {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    var inside = focusedContext == context;
    focusedContext?.visitAncestorElements((element) {
      if (element == context) inside = true;
      return !inside;
    });
    // Focused children (including editor popovers) get the first opportunity.
    return inside ? KeyEventResult.ignored : _escape(event);
  }

  KeyEventResult _escape(KeyEvent event) {
    // Menus and nested dialogs keep their own Escape. The active dialog must
    // still close when a disabled/replaced control leaves focus on its caller.
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        _route?.isCurrent != true)
      return KeyEventResult.ignored;
    if (widget.enabled)
      (widget.onClose ?? () => Navigator.of(context).maybePop())();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_escapeOutside);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: widget.autofocus, onKeyEvent: (_, event) => _escape(event), child: widget.child);
}

/// All editor modal entry points share route-scoped Escape, even when a
/// replaced/disabled control leaves keyboard focus behind the modal.
Future<T?> showEditorDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
}) => showDialog<T>(
  context: context,
  barrierColor: barrierColor,
  builder: (context) {
    final child = builder(context);
    return child is EditorDialogDismissal
        ? child
        : EditorDialogDismissal(child: child);
  },
);
