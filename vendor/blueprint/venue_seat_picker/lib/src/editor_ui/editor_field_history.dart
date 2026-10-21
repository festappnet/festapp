import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keep native undo while a value is being typed; otherwise undo the document.
class EditorFieldHistory extends StatelessWidget {
  const EditorFieldHistory({
    super.key,
    required this.child,
    required this.hasUncommittedChanges,
    required this.onUndo,
    required this.onRedo,
  });
  final Widget child;
  final bool Function() hasUncommittedChanges;
  final VoidCallback onUndo, onRedo;
  void _history(bool redo) {
    if (hasUncommittedChanges()) {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused != null)
        Actions.maybeInvoke(
          focused,
          redo
              ? const RedoTextIntent(SelectionChangedCause.keyboard)
              : const UndoTextIntent(SelectionChangedCause.keyboard),
        );
    } else {
      redo ? onRedo() : onUndo();
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      for (final control in [true, false]) ...{
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: control,
          meta: !control,
        ): () =>
            _history(false),
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: control,
          meta: !control,
          shift: true,
        ): () =>
            _history(true),
        SingleActivator(
          LogicalKeyboardKey.keyY,
          control: control,
          meta: !control,
        ): () =>
            _history(true),
      },
    },
    child: child,
  );
}
