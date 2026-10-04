import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'common_strings.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/services/exception_handler.dart';

/// Keeps a detached baseline, including nested mutable models.
class EditorSnapshot {
  Object? _baseline;
  bool _initialized = false;
  Object? _copy(Object? value) => jsonDecode(jsonEncode(value));
  void accept(Object? value) {
    _baseline = _copy(value);
    _initialized = true;
  }

  bool differs(Object? value) =>
      _initialized &&
      !const DeepCollectionEquality().equals(_baseline, _copy(value));
}

Future<bool> confirmDiscardChanges(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(CommonStrings.discardChanges),
        content: Text(CommonStrings.discardChangesConfirmation),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(CommonStrings.keepEditing)),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(CommonStrings.discardChanges)),
        ],
      ),
    ) ==
    true;

/// Page-level draft actions never navigate away from an embedded editor.
/// Dialog dismissal and explicit Back actions belong to their own navigation UI.
class EditorActionBar extends StatefulWidget {
  const EditorActionBar(
      {super.key,
      required this.hasChanges,
      required this.onSave,
      required this.onDiscard,
      this.enabled = true});
  final bool hasChanges;
  final bool enabled;
  final Future<void> Function() onSave;
  final Future<void> Function() onDiscard;

  @override
  State<EditorActionBar> createState() => _EditorActionBarState();
}

class _EditorActionBarState extends State<EditorActionBar> {
  bool _busy = false;
  bool _performing = false;
  Future<void> _run({required bool discard}) async {
    if (_busy || !widget.enabled || !widget.hasChanges) return;
    setState(() => _busy = true);
    try {
      if (discard) {
        if (!await confirmDiscardChanges(context) || !mounted) return;
        setState(() => _performing = true);
        await ExceptionHandler.guardVoid(context,
            futureFunction: widget.onDiscard);
      } else {
        setState(() => _performing = true);
        await ExceptionHandler.guardVoid(context,
            futureFunction: widget.onSave);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _performing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.hasChanges && !_busy;
    final header = Theme.of(context).appBarTheme;
    final background = header.backgroundColor ?? ThemeConfig.appBarColor();
    final foreground = header.foregroundColor ??
        ThemeConfig.textColorForBackground(background);
    return BottomAppBar(
      color: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Flexible(
            child: TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: foreground,
                    disabledForegroundColor: foreground.withValues(alpha: .38)),
                onPressed: active ? () => _run(discard: true) : null,
                child: Text(CommonStrings.discardChanges,
                    maxLines: 1, overflow: TextOverflow.ellipsis))),
        const SizedBox(width: 8),
        FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: foreground,
                foregroundColor: background,
                disabledBackgroundColor: foreground.withValues(alpha: .12),
                disabledForegroundColor: foreground.withValues(alpha: .38)),
            onPressed: active ? () => _run(discard: false) : null,
            child: _performing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(CommonStrings.save)),
      ]),
    );
  }
}
