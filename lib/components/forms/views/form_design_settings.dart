import 'package:fstapp/components/_shared/appearance_color_strings.dart';
import 'package:fstapp/widgets/appearance_color_controls.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/fonts/form_font_catalog.dart';
import '../../fonts/font_family_picker.dart';

import '../form_strings.dart';

class FormDesignSettings extends StatefulWidget {
  final FormEditorDraft form;
  final bool enabled;
  final VoidCallback onChanged;
  final Future<FormFontCatalog> Function() loadFonts;

  const FormDesignSettings(
      {super.key,
      required this.form,
      required this.onChanged,
      this.enabled = true,
      this.loadFonts = FormFontCatalog.load});

  @override
  State<FormDesignSettings> createState() => _FormDesignSettingsState();
}

class _FormDesignSettingsState extends State<FormDesignSettings> {
  bool _showAllPresets = false;
  late Future<FormFontCatalog> _fonts;

  @override
  void initState() {
    super.initState();
    _fonts = Future<FormFontCatalog>.sync(widget.loadFonts);
  }

  final List<Map<String, dynamic>> _colorPresets = [
    {
      'name': 'Ocean',
      'primary': 0xFF0288D1,
      'secondary': 0xFFE1F5FE
    }, // Light Blue 50
    {
      'name': 'Forest',
      'primary': 0xFF2E7D32,
      'secondary': 0xFFE8F5E9
    }, // Green 50
    {
      'name': 'Sunset',
      'primary': 0xFFE64A19,
      'secondary': 0xFFFBE9E7
    }, // Deep Orange 50
    {
      'name': 'Lavender',
      'primary': 0xFF673AB7,
      'secondary': 0xFFEDE7F6
    }, // Deep Purple 50
    {
      'name': 'Night',
      'primary': 0xFF263238,
      'secondary': 0xFFECEFF1
    }, // Blue Grey 50
    {
      'name': 'Berry',
      'primary': 0xFF880E4F,
      'secondary': 0xFFFCE4EC
    }, // Pink 50
    {'name': 'Teal', 'primary': 0xFF00695C, 'secondary': 0xFFE0F2F1}, // Teal 50
    {
      'name': 'Gold',
      'primary': 0xFFFF8F00,
      'secondary': 0xFFFFF8E1
    }, // Amber 50
    {
      'name': 'Cherry',
      'primary': 0xFFC2185B,
      'secondary': 0xFFF8BBD0
    }, // Pink 100
    {
      'name': 'Royal',
      'primary': 0xFF1565C0,
      'secondary': 0xFFE3F2FD
    }, // Blue 50
    {
      'name': 'Slate',
      'primary': 0xFF455A64,
      'secondary': 0xFFECEFF1
    }, // Blue Grey 50
    {
      'name': 'Cozy',
      'primary': 0xFF5D4037,
      'secondary': 0xFFEFEBE9
    }, // Brown 50
    {'name': 'Mint', 'primary': 0xFF00796B, 'secondary': 0xFFE0F2F1}, // Teal 50
    {
      'name': 'Coral',
      'primary': 0xFFFF5722,
      'secondary': 0xFFFBE9E7
    }, // Deep Orange 50
    {
      'name': 'Indigo',
      'primary': 0xFF3F51B5,
      'secondary': 0xFFE8EAF6
    }, // Indigo 50
    {'name': 'Lime', 'primary': 0xFF827717, 'secondary': 0xFFF9FBE7}, // Lime 50
  ];

  void _pickColor(BuildContext context, Color currentColor,
      Function(Color) onColorChanged) {
    if (!widget.enabled) return;
    showDialog(
        context: context,
        builder: (context) {
          Color pickerColor = currentColor;
          // Strip alpha (FF) from start of value string for display
          // color.value.toRadixString(16) -> ffrrggbb
          // We want #RRGGBB
          String colorToHex(Color c) =>
              '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

          TextEditingController hexController =
              TextEditingController(text: colorToHex(pickerColor));
          FocusNode hexFocus = FocusNode();

          return AppAlertDialog(
            title: Text(FormStrings.pickColor),
            content: StatefulBuilder(builder: (context, setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ColorPicker(
                      pickerColor: pickerColor,
                      onColorChanged: (c) {
                        setState(() {
                          pickerColor = c;
                          // Only update text if user is NOT typing in it to prevent cursor jumps
                          if (!hexFocus.hasFocus) {
                            hexController.text = colorToHex(c);
                          }
                        });
                        onColorChanged(c);
                      },
                      pickerAreaHeightPercent: 0.8,
                      enableAlpha: false, // Standard for simple UI
                      labelTypes: const [], // Hide default labels to keep it clean
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: hexController,
                      focusNode: hexFocus,
                      decoration: InputDecoration(
                          labelText: FormStrings.hexCodeLabel,
                          hintText: '#RRGGBB',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.tag),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.content_paste),
                            onPressed: () async {
                              final data =
                                  await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null) {
                                hexController.text = data!.text!;
                                // Trigger change logic manually
                                String clean =
                                    data.text!.replaceAll('#', '').trim();
                                if (clean.length == 6) {
                                  try {
                                    Color c =
                                        Color(int.parse('FF$clean', radix: 16));
                                    setState(() {
                                      pickerColor = c;
                                    });
                                    onColorChanged(c);
                                  } catch (_) {}
                                }
                              }
                            },
                          )),
                      onChanged: (val) {
                        String clean = val.replaceAll('#', '').trim();
                        if (clean.length == 6) {
                          try {
                            // Assume full opacity
                            Color c = Color(int.parse('FF$clean', radix: 16));
                            setState(() {
                              pickerColor = c;
                            });
                            onColorChanged(c);
                          } catch (e) {
                            // Invalid hex, ignore
                          }
                        }
                      },
                    ),
                  ],
                ),
              );
            }),
            actions: <Widget>[
              ElevatedButton(
                child: Text(FormStrings.buttonGotIt),
                onPressed: () {
                  widget.onChanged();
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        });
  }

  void _applyPreset(Map<String, dynamic> preset) {
    if (!widget.enabled) return;
    setState(() {
      widget.form.definition =
          widget.form.definition.withPrimaryColor(preset['primary']);
      widget.form.definition =
          widget.form.definition.withSecondaryColor(preset['secondary']);
      widget.onChanged();
    });
  }

  TextStyle? _getSafeFont(FormFontCatalog fonts, String? fontFamily) {
    if (fontFamily == null || fontFamily.isEmpty) return null;
    try {
      return fonts.getFont(fontFamily);
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? get _selectedPalette {
    final definition = widget.form.definition;
    for (final preset in _colorPresets) {
      if (definition.primaryColor == preset['primary'] &&
          (definition.backgroundMode != 'gradient' ||
              definition.secondaryColor == preset['secondary'])) {
        return preset;
      }
    }
    return null;
  }

  Widget _paletteChoices(Map<String, dynamic>? selected) {
    final gradient = widget.form.definition.backgroundMode == 'gradient';
    final visible = _showAllPresets
        ? _colorPresets
        : [
            ..._colorPresets.take(6),
            if (selected != null && !_colorPresets.take(6).contains(selected))
              selected,
          ];
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final availableColumns = (constraints.maxWidth / (140 * scale)).floor();
        final columns = availableColumns >= 6
            ? 6
            : availableColumns >= 3
            ? 3
            : availableColumns >= 2
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in visible)
              SizedBox(
                width: width,
                child: Semantics(
                  selected: selected == preset,
                  child: OutlinedButton(
                    key: ValueKey('form-palette-${preset['name']}'),
                    onPressed: widget.enabled
                        ? () => _applyPreset(preset)
                        : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                      minimumSize: const Size(48, 48),
                      foregroundColor: selected == preset
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onSurface,
                      backgroundColor: selected == preset
                          ? theme.colorScheme.secondaryContainer
                          : null,
                      side: BorderSide(
                        color: selected == preset
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                        width: selected == preset ? 2 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: theme.colorScheme.outline,
                            ),
                            color: Color(preset['primary']),
                            gradient: gradient
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(preset['primary']),
                                      Color(preset['secondary']),
                                    ],
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(preset['name'])),
                        if (selected == preset) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.check, size: 18),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedPalette;
    final definition = widget.form.definition;
    final inherited =
        definition.primaryColor == null &&
        (definition.backgroundMode != 'gradient' ||
            definition.secondaryColor == null);
    final status = selected != null
        ? AppearanceColorStrings.palette(selected['name'])
        : inherited
        ? AppearanceColorStrings.inherited
        : AppearanceColorStrings.custom;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: Text(FormStrings.labelCardDesign),
            subtitle: Text(FormStrings.subtitleCardDesign),
            value: widget.form.definition.isCardDesign,
            onChanged: widget.enabled ? (value) {
              setState(() {
                widget.form.definition =
                    widget.form.definition.withIsCardDesign(value);
                widget.onChanged();
              });
            } : null,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            AppearanceColorStrings.style,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              status,
              key: const ValueKey('form-palette-status'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 4),
          Text(AppearanceColorStrings.paletteHint),
          const SizedBox(height: 16),
          _paletteChoices(selected),
          const SizedBox(height: 4),
          TextButton.icon(
            key: const ValueKey('form-palettes-more'),
            onPressed: () => setState(() => _showAllPresets = !_showAllPresets),
            icon: Icon(_showAllPresets ? Icons.expand_less : Icons.expand_more),
            label: Text(_showAllPresets ? FormStrings.less : FormStrings.more),
          ),
          const SizedBox(height: 8),
          AppearanceColorControls(
            gradient: widget.form.definition.backgroundMode == 'gradient',
            primaryColor: Color(
              widget.form.definition.primaryColor ?? Theme.of(context).primaryColor.toARGB32(),
            ),
            secondaryColor: Color(
              widget.form.definition.secondaryColor ??
                  widget.form.definition.primaryColor ??
                  Theme.of(context).primaryColor.toARGB32(),
            ),
            onGradientChanged: widget.enabled
                ? (value) => setState(() {
                    var definition = widget.form.definition;
                    if (value) {
                      final primary = definition.primaryColor ?? Theme.of(context).primaryColor.toARGB32();
                      definition = definition
                          .withPrimaryColor(primary)
                          .withSecondaryColor(
                            definition.secondaryColor ?? primary,
                          );
                    }
                    widget.form.definition = definition.withBackgroundMode(
                      value ? 'gradient' : 'solid',
                    );
                    widget.onChanged();
                  })
                : null,
            onPrimaryPressed: widget.enabled
                ? () => _pickColor(
                    context,
                    Color(widget.form.definition.primaryColor ?? Theme.of(context).primaryColor.toARGB32()),
                    (color) => setState(() {
                      widget.form.definition = widget.form.definition
                          .withPrimaryColor(color.toARGB32());
                      widget.onChanged();
                    }),
                  )
                : null,
            onSecondaryPressed: widget.enabled
                ? () => _pickColor(
                    context,
                    Color(
                      widget.form.definition.secondaryColor ??
                          widget.form.definition.primaryColor ??
                          Theme.of(context).primaryColor.toARGB32(),
                    ),
                    (color) => setState(() {
                      widget.form.definition = widget.form.definition
                          .withSecondaryColor(color.toARGB32());
                      widget.onChanged();
                    }),
                  )
                : null,
            onPrimaryReset:
                widget.enabled && widget.form.definition.primaryColor != null
                ? () => setState(() {
                    widget.form.definition = widget.form.definition
                        .withPrimaryColor(null);
                    widget.onChanged();
                  })
                : null,
            onSecondaryReset:
                widget.enabled && widget.form.definition.secondaryColor != null
                ? () => setState(() {
                    widget.form.definition = widget.form.definition
                        .withSecondaryColor(null);
                    widget.onChanged();
                  })
                : null,
            resetLabel: FormStrings.resetToDefault,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          Text(FormStrings.typography,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<FormFontCatalog>(
            future: _fonts,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Text(FormStrings.fontLoadFailed),
                    TextButton(
                      onPressed: () => setState(() {
                        _fonts = Future<FormFontCatalog>.sync(widget.loadFonts);
                      }),
                      child: Text(CommonStrings.retry),
                    ),
                  ],
                );
              }
              final fonts = snapshot.data;
              if (fonts == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return FontFamilyPicker(
                value: widget.form.definition.fontFamily,
                families: fonts.families,
                previewStyle: fonts.previewStyle,
                selectedStyle:
                    _getSafeFont(fonts, widget.form.definition.fontFamily),
                onSelected: (value) async {
                  if (value != null) fonts.getFont(value);
                  setState(() => widget.form.definition =
                      widget.form.definition.withFontFamily(value));
                  widget.onChanged();
                },
              );
            },
          ),
        ],
      ),
    );
  }

}
