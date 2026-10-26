import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import '../venue_layout_controller.dart';
import 'canonical_appearance_panel.dart';
import 'layout_floor_style.dart';
import 'layout_strings.dart';
import 'layout_style.dart';

Future<void> showLayoutGlobalStyleDialog(
  BuildContext context,
  VenueLayoutController controller, {
  Widget Function(BuildContext, String)? globalFontPickerBuilder,
}) => showCanonicalAppearanceDialog(
  context,
  controller,
  global: true,
  globalFontPickerBuilder: globalFontPickerBuilder,
);

/// A canvas-side appearance workspace. Choosing a preset commits one history
/// entry. Hover previews revert on exit and never change the selected preset.
class LayoutGlobalStylePanel extends StatefulWidget {
  const LayoutGlobalStylePanel({
    super.key,
    required this.controller,
    required this.onClose,
    this.globalFontPickerBuilder,
  });

  final VenueLayoutController controller;
  final VoidCallback onClose;
  final Widget Function(BuildContext, String)? globalFontPickerBuilder;

  @override
  State<LayoutGlobalStylePanel> createState() => LayoutGlobalStylePanelState();
}

class LayoutGlobalStylePanelState extends State<LayoutGlobalStylePanel> {
  VenueLayoutDocument? _baseline;
  VenueLayoutDocument? _preview;
  String? _choice;
  VenueLayoutDocument? _selectedDocument;
  String? _selectedFamily;
  String? _selectedPalette;
  VenueLayoutController get c => widget.controller;
  bool get _enabled => !c.readOnly && !c.saving;

  void cancelPreview() {
    final ownsGesture = _baseline != null && identical(c.document, _preview);
    _baseline = null;
    _preview = null;
    _choice = null;
    if (ownsGesture && c.gestureActive) c.cancelGesture();
  }

  void _prepareChoice(
    String id,
    VenueLayoutDocument Function(VenueLayoutDocument) apply,
  ) {
    if (!_enabled) return;
    if (_baseline != null && !identical(c.document, _preview)) {
      _baseline = null;
      _preview = null;
      _choice = null;
    }
    if (_baseline == null) {
      if (c.gestureActive) return;
      _baseline = c.document;
      c.beginGesture();
    }
    if (c.preview(apply(_baseline!))) {
      _preview = c.document;
      _choice = id;
    } else {
      // Even a rejected preview must release the gesture we just opened.
      _preview = c.document;
      cancelPreview();
    }
  }

  void _choose(
    String id,
    VenueLayoutDocument Function(VenueLayoutDocument) apply,
  ) {
    if (!_enabled) return;
    if (_choice != id) _prepareChoice(id, apply);
    if (_choice != id || !identical(c.document, _preview)) return;
    _baseline = null;
    _preview = null;
    _choice = null;
    c.commitGesture();
    setState(() {
      _selectedDocument = c.document;
      if (id.startsWith('family:')) _selectedFamily = id;
      if (id.startsWith('palette:')) _selectedPalette = id;
    });
  }

  void _close() {
    cancelPreview();
    widget.onClose();
  }

  @override
  void dispose() {
    final controller = c;
    final preview = _preview;
    final owned = _baseline != null;
    // A responsive layout may unmount this panel during an editor rebuild.
    // Restore after that build, only if the preview is still ours.
    if (owned) {
      scheduleMicrotask(() {
        if (identical(controller.document, preview) &&
            controller.gestureActive) {
          controller.cancelGesture();
        }
      });
    }
    super.dispose();
  }

  Widget _option({
    required String id,
    required String label,
    required Widget preview,
    required VenueLayoutDocument Function(VenueLayoutDocument) apply,
    required bool selected,
  }) => MouseRegion(
    onEnter: (_) => _prepareChoice(id, apply),
    onExit: (_) => cancelPreview(),
    child: OutlinedButton(
      key: ValueKey(
        id
            .replaceFirst('family:', 'appearance-family-')
            .replaceFirst('palette:', 'layout-style-'),
      ),
      onPressed: _enabled ? () => _choose(id, apply) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(8),
        backgroundColor: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          preview,
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected) ...[
                const Icon(Icons.check, size: 13),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: LayoutText(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: LayoutText(title, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _close();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.palette_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutText(
                  'Plan style',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: VenueLayoutStrings.text(context, 'Close'),
                onPressed: _close,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('Style family'),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final family in const {
                      'minimal': 'Minimal',
                      'wood': 'Timber',
                      'lounge': 'Lounge',
                      'round': 'Round seating',
                      'banquet': 'Banquet hall',
                      'transit': 'Transport',
                      'cinema': 'Cinema',
                    }.entries)
                      SizedBox(
                        width: (constraints.maxWidth - 8) / 2,
                        height: 100,
                        child: _option(
                          id: 'family:${family.key}',
                          label: family.value,
                          selected:
                              _selectedFamily == 'family:${family.key}' &&
                              (identical(c.document, _selectedDocument) ||
                                  identical(_baseline, _selectedDocument)),
                          preview: LayoutStylePreview(
                            appearance:
                                layoutMaterialFamilyAppearances[family.key]!,
                            size: const Size(88, 44),
                          ),
                          apply: (document) =>
                              applyLayoutFamily(document, family.key),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle('Color palette'),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final palette in layoutColorPalettes.entries)
                      SizedBox(
                        width: (constraints.maxWidth - 8) / 2,
                        child: _option(
                          id: 'palette:${palette.key}',
                          label: palette.key,
                          selected:
                              _selectedPalette == 'palette:${palette.key}' &&
                              (identical(c.document, _selectedDocument) ||
                                  identical(_baseline, _selectedDocument)),
                          preview: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final hex in [
                                palette.value.object['fill'] as String,
                                palette.value.seats!['fill'] as String,
                                palette.value.canvasFill!,
                              ])
                                Container(
                                  width: 22,
                                  height: 18,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Color(
                                      int.parse(
                                        hex.substring(7, 9) +
                                            hex.substring(1, 7),
                                        radix: 16,
                                      ),
                                    ),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                            ],
                          ),
                          apply: (document) => applyGlobalLayoutAppearance(
                            document,
                            palette.value,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const LayoutText('Floor appearance'),
                children: [
                  AnimatedBuilder(
                    animation: c,
                    builder: (_, _) => LayoutFloorStyleField(controller: c),
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const LayoutText('Detailed settings'),
                children: [
                  CanonicalAppearancePanel(
                    controller: c,
                    global: true,
                    globalFontPickerBuilder: widget.globalFontPickerBuilder,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
