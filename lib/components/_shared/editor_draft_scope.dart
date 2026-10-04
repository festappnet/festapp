import 'package:flutter/material.dart';

/// Lets nested editor controls report model mutations without rebuilding the
/// whole form (and recreating text controllers while the user is typing).
class EditorDraftScope extends InheritedWidget {
  const EditorDraftScope(
      {super.key, required this.onChanged, required super.child});
  final VoidCallback onChanged;
  static void changed(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EditorDraftScope>()?.onChanged();
  @override
  bool updateShouldNotify(EditorDraftScope oldWidget) => false;
}
