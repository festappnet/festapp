import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../fonts/font_family_picker.dart';

import '../form_strings.dart';

class FormDesignSettings extends StatefulWidget {
  final FormModel form;
  final VoidCallback onChanged;

  const FormDesignSettings(
      {super.key, required this.form, required this.onChanged});

  @override
  State<FormDesignSettings> createState() => _FormDesignSettingsState();
}

class _FormDesignSettingsState extends State<FormDesignSettings> {
  bool _showAllPresets = false;

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

          return AlertDialog(
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
    setState(() {
      widget.form.primaryColor = preset['primary'];
      widget.form.secondaryColor = preset['secondary'];
      widget.onChanged();
    });
  }

  TextStyle? _getSafeFont(String? fontFamily) {
    if (fontFamily == null || fontFamily.isEmpty) return null;
    try {
      return GoogleFonts.getFont(fontFamily);
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
            value: widget.form.isCardDesign,
            onChanged: (value) {
              setState(() {
                widget.form.isCardDesign = value;
                widget.onChanged();
              });
            },
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text(FormStrings.designPresets,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ...(_showAllPresets ? _colorPresets : _colorPresets.take(6))
                  .map((preset) {
                return InkWell(
                  onTap: () => _applyPreset(preset),
                  child: Column(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          // Show vertical split: Left=Primary, Right=Secondary (Light Mode BG hint)
                          gradient: LinearGradient(
                            colors: [
                              Color(preset['primary']),
                              Color(preset['primary']),
                              Color(preset['secondary']),
                              Color(preset['secondary'])
                            ],
                            stops: const [0.0, 0.5, 0.5, 1.0],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          boxShadow: const [
                            BoxShadow(blurRadius: 2, color: Colors.black26)
                          ],
                          border:
                              (widget.form.primaryColor == preset['primary'] &&
                                      widget.form.secondaryColor ==
                                          preset['secondary'])
                                  ? Border.all(color: Colors.black, width: 2)
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(preset['name'],
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                );
              }),
              // Show More / Less Button
              InkWell(
                onTap: () => setState(() => _showAllPresets = !_showAllPresets),
                child: Column(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).cardColor,
                        border: Border.all(color: Colors.grey.withOpacity(0.5)),
                      ),
                      child: Icon(_showAllPresets
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down),
                    ),
                    const SizedBox(height: 4),
                    Text(_showAllPresets ? FormStrings.less : FormStrings.more,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          Text(FormStrings.customColors,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _buildColorPickerRow(
              FormStrings.primaryColor,
              widget.form.primaryColor != null
                  ? Color(widget.form.primaryColor!)
                  : Colors.blue, (color) {
            setState(() {
              widget.form.primaryColor = color.value;
              widget.onChanged();
            });
          },
              () => setState(() {
                    widget.form.primaryColor = null;
                    widget.onChanged();
                  }),
              widget.form.primaryColor != null),
          const SizedBox(height: 24),
          // Secondary color is now auto-calculated.
          const Divider(),
          const SizedBox(height: 24),
          Text(FormStrings.typography,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FontFamilyPicker(
              value: widget.form.fontFamily,
              families: GoogleFonts.asMap().keys.toList(),
              selectedStyle: _getSafeFont(widget.form.fontFamily),
              onSelected: (value) async {
                if (value != null) GoogleFonts.getFont(value);
                setState(() => widget.form.fontFamily = value);
                widget.onChanged();
              }),
        ],
      ),
    );
  }

  Widget _buildColorPickerRow(String label, Color color,
      Function(Color) onColorChanged, VoidCallback onClear, bool isSet) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        GestureDetector(
          onTap: () => _pickColor(context, color, onColorChanged),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.withOpacity(0.5)),
              boxShadow: const [
                BoxShadow(blurRadius: 2, color: Colors.black26)
              ],
            ),
            child: const Icon(Icons.edit, size: 20, color: Colors.white54),
          ),
        ),
        if (isSet)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: FormStrings.resetToDefault,
            onPressed: onClear,
          ),
      ],
    );
  }
}
