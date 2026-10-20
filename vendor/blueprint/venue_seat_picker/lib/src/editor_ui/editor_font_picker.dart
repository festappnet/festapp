import 'package:flutter/material.dart';
import 'editor_dialog.dart';

@immutable
class EditorFontOption {
  const EditorFontOption({
    required this.id,
    required this.family,
    this.preferred = false,
  });
  final String id, family;
  final bool preferred;
}

/// Catalog-free font selection. The host callback owns loading and persistence.
class EditorFontPicker extends StatefulWidget {
  const EditorFontPicker({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.enabled = true,
    this.allowDefault = true,
    this.canReset = true,
    this.label,
    this.selectedStyle,
    this.translate,
    this.catalogFooter,
  });
  final String? value;
  final List<EditorFontOption> options;
  final Future<void> Function(String?) onSelected;
  final bool enabled, allowDefault, canReset;
  final String? label;
  final TextStyle? selectedStyle;
  final String Function(String)? translate;
  final Widget? catalogFooter;
  static Future<void> showChoices(
    BuildContext context, {
    required List<EditorFontOption> options,
    required Future<void> Function(String?) onSelected,
    String? value,
    String title = 'Typography',
    bool enabled = true,
    bool allowDefault = true,
    bool canReset = true,
    String Function(String)? translate,
    Widget? catalogFooter,
  }) async {
    if (!enabled) return;
    await showEditorDialog<void>(
      context: context,
      builder: (context) => _FontChoices(
        options: options,
        value: value,
        onSelected: onSelected,
        title: title,
        allowDefault: allowDefault && canReset,
        translate: translate,
        catalogFooter: catalogFooter,
      ),
    );
  }

  @override
  State<EditorFontPicker> createState() => _EditorFontPickerState();
}

class _EditorFontPickerState extends State<EditorFontPicker> {
  bool _busy = false;
  String? _error;
  String tr(String text) => widget.translate?.call(text) ?? text;
  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSelected(null);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '${tr('Could not load font')}: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String family = tr(
      widget.value == null ? 'Default font' : 'Font not found',
    );
    for (final option in widget.options) {
      if (option.id == widget.value) {
        family = option.family;
        break;
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              tr(widget.label!),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: !widget.enabled || _busy
                    ? null
                    : () => EditorFontPicker.showChoices(
                        context,
                        options: widget.options,
                        value: widget.value,
                        onSelected: widget.onSelected,
                        allowDefault: widget.allowDefault,
                        canReset: widget.canReset,
                        translate: widget.translate,
                        catalogFooter: widget.catalogFooter,
                      ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        family,
                        style: widget.selectedStyle?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ),
              ),
            ),
            if (widget.canReset && widget.allowDefault && widget.value != null)
              IconButton(
                tooltip: tr('Reset to default'),
                onPressed: widget.enabled && !_busy ? _reset : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restart_alt),
              ),
          ],
        ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _FontChoices extends StatefulWidget {
  const _FontChoices({
    required this.options,
    required this.value,
    required this.onSelected,
    required this.title,
    required this.allowDefault,
    this.translate,
    this.catalogFooter,
  });
  final List<EditorFontOption> options;
  final String? value;
  final Future<void> Function(String?) onSelected;
  final String title;
  final bool allowDefault;
  final String Function(String)? translate;
  final Widget? catalogFooter;
  @override
  State<_FontChoices> createState() => _FontChoicesState();
}

class _FontChoicesState extends State<_FontChoices> {
  String _query = '';
  String? _error;
  bool _busy = false;
  String? _loading;
  String tr(String text) => widget.translate?.call(text) ?? text;
  Future<void> _select(String? id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _loading = id;
      _error = null;
    });
    try {
      await widget.onSelected(id);
      if (mounted) {
        setState(() => _busy = false);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '${tr('Could not load font')}: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options =
        widget.options
            .where((o) => o.family.toLowerCase().contains(_query.toLowerCase()))
            .toList()
          ..sort((a, b) {
            final preferred = (b.preferred ? 1 : 0).compareTo(
              a.preferred ? 1 : 0,
            );
            return preferred != 0 ? preferred : a.family.compareTo(b.family);
          });
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(tr(widget.title)),
        content: SizedBox(
          width: 380,
          height:
              (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      240)
                  .clamp(120.0, 400.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: tr('Font name'),
                  hintText: tr('Search fonts'),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    if (widget.allowDefault && _query.isEmpty)
                      ListTile(
                        title: Text(tr('Default font')),
                        selected: widget.value == null,
                        enabled: !_busy,
                        trailing: _busy && _loading == null
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: () => _select(null),
                      ),
                    for (final option in options)
                      ListTile(
                        key: ValueKey('editor-font-${option.id}'),
                        title: Text(option.family),
                        selected: widget.value == option.id,
                        enabled: !_busy,
                        trailing: _busy && _loading == option.id
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : widget.value == option.id
                            ? const Icon(Icons.check, size: 18)
                            : null,
                        onTap: () => _select(option.id),
                      ),
                    if (options.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(tr('Font not found')),
                      ),
                    if (_error != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    if (widget.catalogFooter != null)
                      IgnorePointer(
                        ignoring: _busy,
                        child: widget.catalogFooter!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
        ],
      ),
    );
  }
}
