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
  'Playfair Display'
];

/// Metadata-only options. Loading and committing a selection belongs to the
/// adapter; this widget never downloads fonts while opening or scrolling.
class FontFamilyPicker extends StatefulWidget {
  final String? value;
  final List<String> families, extraFamilies;
  final Future<void> Function(String?) onSelected;
  final TextStyle? selectedStyle;
  final bool enabled;
  final Widget? preview;
  const FontFamilyPicker(
      {super.key,
      required this.value,
      required this.families,
      required this.onSelected,
      this.extraFamilies = const [],
      this.selectedStyle,
      this.preview,
      this.enabled = true});
  @override
  State<FontFamilyPicker> createState() => _FontFamilyPickerState();
}

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
      if (mounted && token == generation) error = FormStrings.fontNotFound;
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final popular = {...widget.extraFamilies, ...popularFontFamilies}
        .where(widget.families.contains)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(
                FormStrings.currentFont +
                    (widget.value ?? FormStrings.defaultFont),
                style: widget.selectedStyle)),
        if (busy)
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        IconButton(
            tooltip: FormStrings.resetToDefault,
            icon: const Icon(Icons.restore),
            onPressed: widget.enabled ? () => choose(null) : null),
      ]),
      DropdownButtonFormField<String>(
          key: ValueKey(widget.value),
          initialValue: popular.contains(widget.value) ? widget.value : null,
          isExpanded: true,
          decoration:
              InputDecoration(labelText: FormStrings.choosePopularFonts),
          items: popular
              .map((f) => DropdownMenuItem(value: f, child: Text(f)))
              .toList(),
          onChanged: widget.enabled ? (v) => choose(v) : null),
      Autocomplete<String>(
          optionsBuilder: (value) => value.text.trim().isEmpty
              ? const Iterable<String>.empty()
              : widget.families
                  .where((f) =>
                      f.toLowerCase().contains(value.text.trim().toLowerCase()))
                  .take(40),
          onSelected: choose,
          fieldViewBuilder: (context, controller, focus, submit) => TextField(
              controller: controller,
              focusNode: focus,
              enabled: widget.enabled,
              decoration: InputDecoration(
                  labelText: FormStrings.customFontNameLabel,
                  errorText: error,
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: widget.enabled
                          ? () => choose(controller.text.trim())
                          : null)),
              onSubmitted: (v) => choose(v.trim()))),
      if (widget.preview != null) widget.preview!,
      HtmlView(
          html:
              '<a href="https://fonts.google.com/">${FormStrings.browseGoogleFonts}</a>',
          isSelectable: false),
    ]);
  }
}
