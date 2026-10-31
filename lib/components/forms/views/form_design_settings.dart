import 'package:fstapp/components/_shared/appearance_palettes.dart';
import 'package:fstapp/widgets/appearance_style_chooser.dart';
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
  late Future<FormFontCatalog> _fonts;

  @override
  void initState() {
    super.initState();
    _fonts = Future<FormFontCatalog>.sync(widget.loadFonts);
  }

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

  void _applyPreset(AppearancePalette preset) {
    if (!widget.enabled) return;
    setState(() {
      widget.form.definition =
          widget.form.definition.withPrimaryColor(preset.primary);
      widget.form.definition =
          widget.form.definition.withSecondaryColor(preset.secondary);
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: Text(FormStrings.labelCardDesign),
            subtitle: Text(FormStrings.subtitleCardDesign),
            value: widget.form.definition.isCardDesign,
            onChanged: widget.enabled
                ? (value) {
                    setState(() {
                      widget.form.definition = widget.form.definition
                          .withIsCardDesign(value);
                      widget.onChanged();
                    });
                  }
                : null,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          AppearanceStyleChooser(
            primaryColor: widget.form.definition.primaryColor,
            secondaryColor: widget.form.definition.secondaryColor,
            gradient: widget.form.definition.backgroundMode == 'gradient',
            onSelected: widget.enabled ? _applyPreset : null,
            controls: AppearanceColorControls(
              paletteName: AppearancePalettes.match(
                widget.form.definition.primaryColor,
                widget.form.definition.secondaryColor,
                widget.form.definition.backgroundMode == 'gradient',
              )?.label,
              gradient: widget.form.definition.backgroundMode == 'gradient',
              primaryColor: Color(
                widget.form.definition.primaryColor ??
                    Theme.of(context).primaryColor.toARGB32(),
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
                        final primary =
                            definition.primaryColor ??
                            Theme.of(context).primaryColor.toARGB32();
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
                      Color(
                        widget.form.definition.primaryColor ??
                            Theme.of(context).primaryColor.toARGB32(),
                      ),
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
                  widget.enabled &&
                      widget.form.definition.secondaryColor != null
                  ? () => setState(() {
                      widget.form.definition = widget.form.definition
                          .withSecondaryColor(null);
                      widget.onChanged();
                    })
                  : null,
              resetLabel: FormStrings.resetToDefault,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            FormStrings.formAppearance,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in ['system', 'light', 'dark'])
                ChoiceChip(
                  key: ValueKey('form-theme-$mode'),
                  label: Text(switch (mode) {
                    'light' => FormStrings.appearanceLight,
                    'dark' => FormStrings.appearanceDark,
                    _ => FormStrings.appearanceSystem,
                  }),
                  selected: widget.form.definition.themeMode == mode,
                  onSelected: widget.enabled
                      ? (_) => setState(() {
                          widget.form.definition = widget.form.definition
                              .withThemeMode(mode);
                          widget.onChanged();
                        })
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            FormStrings.formAppearanceHint,
            style: Theme.of(context).textTheme.bodySmall,
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
