import 'package:flutter/material.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import '../forms/form_strings.dart';
import '../_shared/common_strings.dart';
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

/// Catalog/localization adapter. Loading and commits remain host-owned.
class FontFamilyPicker extends StatelessWidget {
  final String? value, label;
  final List<String> families, extraFamilies;
  final Future<void> Function(String?) onSelected;
  final TextStyle? selectedStyle;
  final bool enabled, canReset;
  const FontFamilyPicker(
      {super.key,
      required this.value,
      required this.families,
      required this.onSelected,
      this.extraFamilies = const [],
      this.selectedStyle,
      this.label,
      this.enabled = true,
      this.canReset = true});

  static List<EditorFontOption> _options(
          List<String> families, List<String> extraFamilies) =>
      families
          .toSet()
          .map((family) => EditorFontOption(
              id: family,
              family: family.replaceFirst(' (legacy)', ''),
              preferred: extraFamilies.contains(family) ||
                  popularFontFamilies.contains(family)))
          .toList();

  static String _translate(String label) => switch (label) {
        'Typography' => FormStrings.typography,
        'Default font' => FormStrings.defaultFont,
        'Reset to default' => FormStrings.resetToDefault,
        'Font not found' || 'Could not load font' => FormStrings.fontNotFound,
        'Font name' => FormStrings.customFontNameLabel,
        'Search fonts' => FormStrings.fontSearchHint,
        'Cancel' => CommonStrings.cancel,
        _ => label,
      };
  static Widget _footer() => HtmlView(
      html:
          '<a href="https://fonts.google.com/">${FormStrings.browseGoogleFonts}</a>',
      isSelectable: false);

  static Future<void> showChoices(
    BuildContext context, {
    required List<String> families,
    required Future<void> Function(String?) onSelected,
    String? value,
    String? title,
    List<String> extraFamilies = const [],
  }) =>
      EditorFontPicker.showChoices(context,
          options: _options(families, extraFamilies),
          onSelected: onSelected,
          value: value,
          title: title ?? FormStrings.moreFonts,
          translate: _translate,
          catalogFooter: _footer());

  @override
  Widget build(BuildContext context) => EditorFontPicker(
      value: value,
      options: _options(families, extraFamilies),
      onSelected: onSelected,
      enabled: enabled,
      canReset: canReset,
      label: label ?? FormStrings.typography,
      selectedStyle: selectedStyle,
      translate: _translate,
      catalogFooter: _footer());
}
