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

/// Options are metadata only. The adapter owns loading and committing a font.
class FontFamilyPicker extends StatefulWidget {
  final String? value, label;
  final List<String> families, extraFamilies;
  final Future<void> Function(String?) onSelected;
  final TextStyle? selectedStyle;
  final bool enabled, canReset;
  const FontFamilyPicker({
    super.key,
    required this.value,
    required this.families,
    required this.onSelected,
    this.extraFamilies = const [],
    this.selectedStyle,
    this.label,
    this.enabled = true,
    this.canReset = true,
  });

  /// Advanced choices live in one responsive sheet, including per-text overrides.
  static Future<void> showChoices(
    BuildContext context, {
    required List<String> families,
    required Future<void> Function(String?) onSelected,
    String? value,
    String? title,
    List<String> extraFamilies = const [],
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
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
        ),
      );

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
              child: DropdownButtonFormField<String>(
                key: ValueKey(widget.value),
                initialValue: widget.value,
                isExpanded: true,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.merge(widget.selectedStyle)
                    .copyWith(color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: widget.label ?? FormStrings.typography,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(FormStrings.defaultFont),
                  ),
                  ...choices.map(
                    (f) => DropdownMenuItem(
                      value: f,
                      child: Text(
                        _displayFont(f),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
  final Future<void> Function(String?) onSelected;
  const _FontChoices({
    required this.families,
    required this.extraFamilies,
    required this.value,
    required this.title,
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
        ? {...widget.extraFamilies, ...popularFontFamilies}
            .where(widget.families.contains)
            .toList()
        : widget.families
            .where((f) => f.toLowerCase().contains(query))
            .take(60)
            .toList();
    final media = MediaQuery.of(context);
    final height =
        ((media.size.height - media.viewInsets.bottom) * .85).clamp(0.0, 560.0);
    return PopScope(
        canPop: !busy,
        child: Padding(
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: SizedBox(
                height: height,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                      child: Row(children: [
                        Expanded(
                            child: Text(widget.title ?? FormStrings.moreFonts,
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .closeButtonTooltip,
                            onPressed:
                                busy ? null : () => Navigator.pop(context),
                            icon: const Icon(Icons.close)),
                      ])),
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
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                              child: Text(FormStrings.fontSearchHint,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium))),
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
                          return ListTile(
                              title: Text(_displayFont(family)),
                              selected: widget.value == family,
                              trailing: busy && loading == family
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : widget.value == family
                                      ? const Icon(Icons.check, size: 20)
                                      : null,
                              onTap: busy ? null : () => choose(family));
                        }),
                  ])),
                ]))));
  }
}
