import 'package:fstapp/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

import '../forms/form_strings.dart';
import '../html/html_view.dart';

const popularFontFamilies = [
  'Roboto',
  'Open Sans',
  'Lato',
  'Montserrat',
  'Raleway',
  'Oswald',
  'Poppins',
  'Inter',
  'Nunito',
  'Ubuntu',
  'Merriweather',
  'Playfair Display',
];

/// Adapters load preview fonts without committing a selection.
class FontFamilyPicker extends StatefulWidget {
  final String? value, label;
  final List<String> families, extraFamilies;
  final Future<void> Function(String?) onSelected;
  final TextStyle? selectedStyle;
  final Future<TextStyle> Function(String)? previewStyle;
  final bool enabled, canReset;
  final Future<void> Function(String?)? onPreview;
  final VoidCallback? onPreviewEnd;
  const FontFamilyPicker({
    super.key,
    required this.value,
    required this.families,
    required this.onSelected,
    this.extraFamilies = const [],
    this.selectedStyle,
    this.previewStyle,
    this.label,
    this.enabled = true,
    this.canReset = true,
    this.onPreview,
    this.onPreviewEnd,
  });

  /// Advanced choices live in one responsive sheet, including per-text overrides.
  static Future<void> showChoices(
    BuildContext context, {
    required List<String> families,
    required Future<void> Function(String?) onSelected,
    String? value,
    String? title,
    List<String> extraFamilies = const [],
    Future<TextStyle> Function(String)? previewStyle,
    Future<void> Function(String?)? onPreview,
    VoidCallback? onPreviewEnd,
  }) {
    if (onPreview != null) {
      return showDialog<void>(
          context: context,
          barrierColor: Colors.transparent,
          builder: (_) => Dialog(
                alignment: Alignment.centerRight,
                insetPadding: const EdgeInsets.all(16),
                child: SizedBox(
                    width: 360,
                    child: _FontChoices(
                      families: families,
                      extraFamilies: extraFamilies,
                      value: value,
                      title: title,
                      onSelected: onSelected,
                      previewStyle: previewStyle,
                      onPreview: onPreview,
                      onPreviewEnd: onPreviewEnd,
                    )),
              )).whenComplete(() => onPreviewEnd?.call());
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: appDialogShape,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _FontChoices(
        families: families,
        extraFamilies: extraFamilies,
        value: value,
        title: title,
        onSelected: onSelected,
        previewStyle: previewStyle,
      ),
    );
  }

  @override
  State<FontFamilyPicker> createState() => _FontFamilyPickerState();
}

String _displayFont(String family) => family.replaceFirst(' (legacy)', '');

class _FontFamilyPickerState extends State<FontFamilyPicker> {
  bool busy = false;
  String? error;
  int generation = 0;
  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> choose(String? value) async {
    final token = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (value != null && !widget.families.contains(value)) {
        throw const FormatException('Unknown font');
      }
      await widget.onSelected(value);
    } catch (_) {
      if (mounted && token == generation) {
        setState(() => error = FormStrings.fontNotFound);
      }
      rethrow;
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  Future<void> chooseInline(String? value) async {
    try {
      await choose(value);
    } catch (_) {
      /* Error is shown beside the picker. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = {
      if (widget.value != null) widget.value!,
      ...widget.extraFamilies,
      ...popularFontFamilies,
    }.where(widget.families.contains).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: widget.onPreview != null
                  ? InkWell(
                      onTap: !widget.enabled || busy
                          ? null
                          : () => FontFamilyPicker.showChoices(context,
                              families: widget.families,
                              extraFamilies: widget.extraFamilies,
                              value: widget.value,
                              onSelected: choose,
                              previewStyle: widget.previewStyle,
                              onPreview: widget.onPreview,
                              onPreviewEnd: widget.onPreviewEnd),
                      child: InputDecorator(
                          decoration: InputDecoration(
                              labelText: widget.label ?? FormStrings.typography,
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14)),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                                    widget.value == null
                                        ? FormStrings.defaultFont
                                        : _displayFont(widget.value!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            const Icon(Icons.arrow_drop_down)
                          ])),
                    )
                  : DropdownButtonFormField<String>(
                      key: ValueKey(widget.value),
                      initialValue: widget.value,
                      isExpanded: true,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.merge(widget.selectedStyle)
                          .copyWith(
                              color: Theme.of(context).colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: widget.label ?? FormStrings.typography,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      selectedItemBuilder: (context) => [
                        Text(FormStrings.defaultFont,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        for (final family in choices)
                          Text(_displayFont(family),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(FormStrings.defaultFont),
                        ),
                        ...choices.map(
                          (f) => DropdownMenuItem(
                            value: f,
                            child: _FontPreview(
                                key: ValueKey(f),
                                family: f,
                                load: widget.previewStyle),
                          ),
                        ),
                      ],
                      onChanged: widget.enabled && !busy ? chooseInline : null,
                    ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (widget.canReset)
              IconButton(
                tooltip: FormStrings.resetToDefault,
                icon: const Icon(Icons.restore),
                onPressed: widget.enabled ? () => chooseInline(null) : null,
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.onPreview == null)
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(FormStrings.moreFonts),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            onPressed: widget.enabled && !busy
                ? () => FontFamilyPicker.showChoices(
                      context,
                      families: widget.families,
                      extraFamilies: widget.extraFamilies,
                      value: widget.value,
                      onSelected: choose,
                      previewStyle: widget.previewStyle,
                      onPreview: widget.onPreview,
                      onPreviewEnd: widget.onPreviewEnd,
                    )
                : null,
          ),
      ],
    );
  }
}

class _FontChoices extends StatefulWidget {
  final List<String> families, extraFamilies;
  final String? value, title;
  final Future<TextStyle> Function(String)? previewStyle;
  final Future<void> Function(String?) onSelected;
  final Future<void> Function(String?)? onPreview;
  final VoidCallback? onPreviewEnd;
  const _FontChoices({
    required this.families,
    required this.extraFamilies,
    required this.value,
    required this.title,
    this.previewStyle,
    this.onPreview,
    this.onPreviewEnd,
    required this.onSelected,
  });
  @override
  State<_FontChoices> createState() => _FontChoicesState();
}

class _FontChoicesState extends State<_FontChoices> {
  final search = TextEditingController();
  String? error, loading;
  bool busy = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> choose(String? family) async {
    if (busy) return;
    setState(() {
      busy = true;
      loading = family;
      error = null;
    });
    try {
      await widget.onSelected(family);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = FormStrings.fontNotFound;
          busy = false;
        });
      }
    }
  }

  Future<void> preview(String family) async {
    if (busy || widget.onPreview == null) return;
    try {
      await widget.onPreview!(family);
    } catch (_) {
      /* A newer hover or cancellation can supersede an async font load. */
    }
  }

  void submit(String name) {
    final family = widget.families
        .where((f) => f.toLowerCase() == name.trim().toLowerCase())
        .firstOrNull;
    if (family == null) {
      setState(() => error = FormStrings.fontNotFound);
      return;
    }
    choose(family);
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final options = query.isEmpty
        ? {
            if (widget.value != null) widget.value!,
            ...widget.extraFamilies,
            ...popularFontFamilies
          }.where(widget.families.contains).toList()
        : widget.families
            .where((f) => f.toLowerCase().contains(query))
            .take(60)
            .toList();
    final media = MediaQuery.of(context);
    final height =
        ((media.size.height - media.viewInsets.bottom) * .85).clamp(0.0, 560.0);
    return AppDialogDismissal(
        enabled: !busy,
        child: PopScope(
            canPop: !busy,
            child: Padding(
                padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                child: SizedBox(
                    height: height,
                    child: Column(children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                          child: AppDialogHeader(
                            title: Text(widget.title ?? FormStrings.moreFonts),
                            closeEnabled: !busy,
                          )),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: TextField(
                              controller: search,
                              enabled: !busy,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                  labelText: FormStrings.customFontNameLabel,
                                  hintText: 'Roboto Slab',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.search),
                                  errorText: error),
                              onChanged: (_) => setState(() => error = null),
                              onSubmitted: submit)),
                      Expanded(
                          child: CustomScrollView(slivers: [
                        if (query.isEmpty)
                          SliverToBoxAdapter(
                              child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 12, 20, 4),
                                  child: Text(FormStrings.fontSearchHint,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium))),
                        if (query.isEmpty)
                          SliverToBoxAdapter(
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 8),
                                  child: HtmlView(
                                      html:
                                          '<a href="https://fonts.google.com/">${FormStrings.browseGoogleFonts}</a>',
                                      isSelectable: false))),
                        SliverList.builder(
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final family = options[index];
                              return MouseRegion(
                                  onEnter: (_) => preview(family),
                                  onExit: (_) => widget.onPreviewEnd?.call(),
                                  child: Focus(
                                      onFocusChange: (focused) {
                                        if (focused) preview(family);
                                      },
                                      child: ListTile(
                                          title: _FontPreview(
                                              key: ValueKey(family),
                                              family: family,
                                              load: widget.previewStyle),
                                          selected: widget.value == family,
                                          trailing: busy && loading == family
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2))
                                              : widget.value == family
                                                  ? const Icon(Icons.check,
                                                      size: 20)
                                                  : null,
                                          onTap: busy
                                              ? null
                                              : () => choose(family))));
                            }),
                      ])),
                    ])))));
  }
}

/// Only menu rows are mounted here; the closed dropdown never downloads fonts.
class _FontPreview extends StatefulWidget {
  final String family;
  final Future<TextStyle> Function(String)? load;
  const _FontPreview({super.key, required this.family, this.load});
  @override
  State<_FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<_FontPreview> {
  late final Future<TextStyle>? style = widget.load == null
      ? null
      : Future<TextStyle>.sync(() => widget.load!(widget.family));
  @override
  Widget build(BuildContext context) => FutureBuilder<TextStyle>(
      future: style,
      builder: (context, snapshot) => Row(children: [
            Expanded(
                child: Text(_displayFont(widget.family),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (snapshot.data ?? const TextStyle()).copyWith(
                        color: Theme.of(context).colorScheme.onSurface))),
            if (style != null &&
                snapshot.connectionState != ConnectionState.done)
              const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5)),
            if (snapshot.hasError)
              Tooltip(
                  message: FormStrings.fontLoadFailed,
                  child: const Icon(Icons.error_outline, size: 16)),
          ]));
}
