import 'package:flutter/material.dart';

import 'layout_style.dart';
import 'layout_font_size_control.dart';
import 'layout_floor_style.dart';

import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/editor_ui.dart';

/// One declaration editor for document, kind, object and direct child styles.
/// Every displayed value and inheritance source comes from the core resolver.
class CanonicalAppearancePanel extends StatefulWidget {
  const CanonicalAppearancePanel({
    super.key,
    required this.controller,
    this.nodeId,
    this.global = false,
    this.fontPickerBuilder,
    this.globalFontPickerBuilder,
  });
  final VenueLayoutController controller;
  final String? nodeId;
  final bool global;
  final Widget Function(BuildContext, LayoutNode)? fontPickerBuilder;
  final Widget Function(BuildContext, String)? globalFontPickerBuilder;
  @override
  State<CanonicalAppearancePanel> createState() =>
      _CanonicalAppearancePanelState();
}

class _CanonicalAppearancePanelState extends State<CanonicalAppearancePanel> {
  String scope = 'node', kind = 'table';
  String? failure;
  VenueLayoutController get c => widget.controller;
  String tr(String value) => VenueLayoutStrings.text(context, value);
  @override
  void initState() {
    super.initState();
    if (widget.global) scope = 'document';
  }

  LayoutNode get node => widget.global
      ? LayoutNode(
          id: '00000000-0000-4000-8000-000000000000',
          kind: scope == 'document' ? 'text' : kind,
        )
      : c.document.nodes.firstWhere((n) => n.id == widget.nodeId);
  Map<String, dynamic> get declaration {
    if (scope == 'document') return {'label': c.document.styles['label'] ?? {}};
    if (scope == 'kind') {
      return Map<String, dynamic>.from(
        (c.document.styles['kinds'] as Map?)?[kind] as Map? ?? {},
      );
    }
    if (scope == 'children') {
      return Map<String, dynamic>.from(node.childStyles['seat'] as Map? ?? {});
    }
    return node.style;
  }

  void change(List<String> path, Object? value, {bool unset = false}) {
    try {
      var d = switch (scope) {
        'document' => setDocumentLabelLeaf(
          c.document,
          path.last,
          value: value,
          unset: unset,
        ),
        'kind' => setKindStyleLeaf(
          c.document,
          kind,
          path,
          value: value,
          unset: unset,
        ),
        'children' => setTableChildStyleLeaf(
          c.document,
          node.id,
          path,
          value: value,
          unset: unset,
        ),
        _ => setNodeStyleLeaf(
          c.document,
          node.id,
          path,
          value: value,
          unset: unset,
        ),
      };
      if (path.length == 1 && path.single == 'material') {
        // Construction is a family choice. Remove conflicting construction
        // leaves while preserving the independent palette and typography.
        const leaves = ['seatStyle', 'cornerRadius', 'strokeWidth'];
        if (scope == 'children') {
          for (final leaf in leaves) {
            d = setTableChildStyleLeaf(d, node.id, [leaf], unset: true);
          }
        } else if (scope == 'kind') {
          for (final leaf in leaves) {
            d = setKindStyleLeaf(d, kind, [leaf], unset: true);
          }
          if (kind == 'table') {
            d = setKindStyleLeaf(
              d,
              'seat',
              ['material'],
              value: value,
              unset: unset,
            );
            for (final leaf in leaves) {
              d = setKindStyleLeaf(d, 'seat', [leaf], unset: true);
            }
          }
        } else if (scope != 'document') {
          for (final leaf in leaves) {
            d = setNodeStyleLeaf(d, node.id, [leaf], unset: true);
          }
          if (node.kind == 'table') {
            d = setTableChildStyleLeaf(
              d,
              node.id,
              ['material'],
              value: value,
              unset: unset,
            );
            for (final leaf in leaves) {
              d = setTableChildStyleLeaf(d, node.id, [leaf], unset: true);
            }
          }
        }
      }
      final accepted = c.apply(d, label: 'Style');
      setState(() => failure = accepted ? null : c.error);
    } catch (error) {
      setState(() => failure = error.toString());
    }
  }

  List<String> usedColors() {
    final colors = <String>{};
    void visit(Object? value) {
      if (value is String && RegExp(r'^#[a-fA-F0-9]{8}$').hasMatch(value)) {
        colors.add(value);
      } else if (value is Map) {
        for (final entry in value.values) {
          visit(entry);
        }
      } else if (value is List) {
        for (final entry in value) {
          visit(entry);
        }
      }
    }

    visit(c.document.canvas['fill']);
    visit(c.document.styles);
    for (final node in c.document.nodes) {
      visit(node.style);
      visit(node.childStyles);
    }
    final sampled = <String>{};
    for (final node in c.document.nodes) {
      if (sampled.add(node.kind)) {
        visit(resolveNodeAppearance(c.document, node).values);
      }
    }
    return colors.map((color) => color.substring(0, 7)).toSet().toList();
  }

  String sourceName(Object? value) {
    final source = value?.toString() ?? 'core';
    if (source.startsWith('node:')) return tr('Object');
    if (source.startsWith('table:')) return tr('Table chair style');
    if (source.startsWith('styles.kinds.')) {
      return '${tr('Kind style')}: ${tr(source.substring(13))}';
    }
    return tr(source == 'styles.label' ? 'All labels' : 'Default');
  }

  Future<void> _previewChoice(
    String title,
    List<String> path,
    String current,
    List<String> choices,
    Map<String, dynamic> values,
  ) async {
    var selected = current;
    var selectedDocument = c.document;
    c.beginGesture();
    bool? accepted;
    try {
      accepted = await showEditorDialog<bool>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (dialogContext) => EditorDialogDismissal(
          child: StatefulBuilder(
            builder: (context, update) {
              void preview(String value) {
                c.preview(selectedDocument);
                change(path, value);
              }

              void select(String value) {
                preview(value);
                selectedDocument = c.document;
                update(() => selected = value);
              }

              return Dialog(
                alignment: Alignment.centerRight,
                insetPadding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 300,
                    maxHeight: 560,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: Text(tr(title)),
                        trailing: IconButton(
                          tooltip: tr('Close'),
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(dialogContext, false),
                        ),
                      ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final value in choices)
                              MouseRegion(
                                onEnter: (_) => preview(value),
                                onExit: (_) {
                                  if (c.gestureActive) {
                                    c.preview(selectedDocument);
                                  }
                                },
                                child: RadioListTile<String>(
                                  value: value,
                                  // Retain compatibility with the declared Flutter 3.32 minimum.
                                  // ignore: deprecated_member_use
                                  groupValue: selected,
                                  // Retain compatibility with the declared Flutter 3.32 minimum.
                                  // ignore: deprecated_member_use
                                  onChanged: (_) => select(value),
                                  title: Text(tr(value)),
                                  secondary: LayoutStylePreview(
                                    size: const Size(64, 42),
                                    appearance: title == 'Material'
                                        ? layoutMaterialFamilyAppearances[value]!
                                        : LayoutAppearance(
                                            layoutMaterialFamilyAppearances['minimal']!
                                                .object,
                                            seats: {
                                              ...layoutMaterialFamilyAppearances['minimal']!
                                                  .seats!,
                                              if (title == 'Chair style')
                                                'seatStyle': value,
                                            },
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: Text(tr('Cancel')),
                            ),
                            FilledButton(
                              onPressed: () {
                                c.preview(selectedDocument);
                                Navigator.pop(dialogContext, true);
                              },
                              child: Text(tr('Apply')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      if (accepted == true) {
        c.commitGesture();
      } else {
        c.cancelGesture();
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final target = scope == 'children'
          ? LayoutNode(
              id: '00000000-0000-4000-8000-000000000001',
              kind: 'seat',
              parentId: node.id,
            )
          : node;
      final document = scope == 'document'
          ? c.document.copyWith(
              styles: {'label': c.document.styles['label'] ?? {}},
            )
          : c.document;
      final resolved = resolveNodeAppearance(document, target),
          values = resolved.values,
          label = resolved.label;
      final enabled =
              !c.readOnly && !c.saving && (widget.global || !node.locked),
          media = {'image', 'vector'}.contains(target.kind);
      final openPath =
          target.kind == 'shape' &&
          const {
            'line',
            'polyline',
            'arrow',
          }.contains(target.properties['shape']);
      final labelVisible =
          scope == 'document' ||
          (!media && target.kind != 'group' && target.kind != 'seat');
      bool owns(List<String> path) => path.length == 1
          ? declaration.containsKey(path.single)
          : (declaration['label'] as Map?)?.containsKey(path.last) == true;
      Widget row(String title, List<String> path, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (control is! _CanonicalNumber &&
                      control is! LayoutFontSizeControl)
                    Text(tr(title)),
                  if (control is Switch)
                    Tooltip(
                      message: tr(title),
                      child: Semantics(label: tr(title), child: control),
                    )
                  else
                    control,
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Reset to inherited value'),
              onPressed: enabled && owns(path)
                  ? () => change(path, null, unset: true)
                  : null,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
      );
      Widget number(
        String title,
        List<String> path,
        num value,
        double min,
        double max,
      ) => row(
        title,
        path,
        _CanonicalNumber(
          key: ValueKey('$scope:$kind:${node.id}:${path.join('.')}'),
          label: tr(title),
          value: value.toDouble(),
          enabled: enabled,
          min: min,
          max: max,
          onChanged: (v) => change(path, v),
          onUndo: c.undo,
          onRedo: c.redo,
        ),
      );
      Widget choice(
        String title,
        List<String> path,
        String value,
        List<String> choices,
      ) => row(
        title,
        path,
        title == 'Material' || title == 'Chair style'
            ? OutlinedButton(
                onPressed: enabled
                    ? () => _previewChoice(title, path, value, choices, values)
                    : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  textStyle: Theme.of(context).textTheme.labelLarge,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    LayoutStylePreview(
                      size: const Size(48, 32),
                      appearance: title == 'Material'
                          ? layoutMaterialFamilyAppearances[value]!
                          : LayoutAppearance(
                              {...values},
                              seats: {
                                ...layoutMaterialFamilyAppearances['minimal']!
                                    .seats!,
                                'seatStyle': value,
                              },
                            ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.expand_more, size: 20),
                  ],
                ),
              )
            : DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: value,
                items: [
                  for (final item in choices)
                    DropdownMenuItem(
                      value: item,
                      child: Row(
                        children: [
                          if (title == 'Material' ||
                              title == 'Chair style') ...[
                            LayoutStylePreview(
                              size: const Size(48, 32),
                              appearance: LayoutAppearance(
                                {
                                  ...values,
                                  if (title == 'Material') 'material': item,
                                },
                                seats: {
                                  ...layoutMaterialFamilyAppearances['minimal']!
                                      .seats!,
                                  if (title == 'Chair style') 'seatStyle': item,
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              tr(item),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: enabled
                    ? (v) {
                        if (v != null) change(path, v);
                      }
                    : null,
              ),
      );
      Future<void> color(List<String> path, String value) async {
        c.beginGesture();
        EditorColorResult? result;
        try {
          result = await showEditorDialog<EditorColorResult>(
            context: context,
            barrierColor: Colors.transparent,
            builder: (_) => EditorColorDialog(
              value: EditorColorValue.fromRgba(value),
              usedColors: usedColors(),
              translate: tr,
              onPreview: (result) {
                if (mounted) change(path, result.primary.rgba);
              },
            ),
          );
          if (result != null && mounted) change(path, result.primary.rgba);
        } finally {
          if (result != null && mounted) {
            c.commitGesture();
          } else {
            c.cancelGesture();
          }
        }
      }

      Widget colorRow(String title, String field) => row(
        title,
        [field],
        OutlinedButton(
          key: ValueKey('canonical-style-$field'),
          onPressed: enabled
              ? () => color([field], values[field] as String)
              : null,
          child: EditorColorSwatch(
            value: EditorColorValue.fromRgba(values[field] as String),
          ),
        ),
      );

      final family =
              (c.resources['fontFamilies'] as Map?)?[label['fontFamilyId']]
                  as Map?,
          faces = family?['faces'] as Map? ?? {};
      final boldKey =
              '${label['weight'] == 700 ? 400 : 700}:${label['italic'] == true ? 'italic' : 'normal'}',
          italicKey =
              '${label['weight']}:${label['italic'] == true ? 'normal' : 'italic'}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.global) ...[
            Text(tr('Apply to'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: scope == 'document' ? 'document' : kind,
              key: const ValueKey('canonical-style-target'),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'document',
                  child: Text(tr('All labels')),
                ),
                for (final k in canonicalStyleKinds)
                  DropdownMenuItem(value: k, child: Text(tr(k))),
              ],
              onChanged: enabled
                  ? (value) {
                      if (value != null) {
                        setState(() {
                          scope = value == 'document' ? 'document' : 'kind';
                          kind = value == 'document' ? 'table' : value;
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 24),
          ],
          if (!widget.global && node.kind == 'table') ...[
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'node', label: Text(tr('Table'))),
                ButtonSegment(value: 'children', label: Text(tr('Chairs'))),
              ],
              selected: {scope},
              onSelectionChanged: enabled
                  ? (v) => setState(() => scope = v.single)
                  : null,
            ),
            const SizedBox(height: 24),
          ],
          if (failure != null)
            Semantics(
              liveRegion: true,
              child: Text(
                failure!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (scope != 'document' &&
              target.kind != 'group' &&
              !media &&
              target.kind != 'text' &&
              !openPath) ...[
            choice(
              'Material',
              ['material'],
              values['material'] as String,
              (canonicalVisualFields['material']!['enum'] as List)
                  .cast<String>(),
            ),
            if (target.kind == 'seat')
              choice(
                'Chair style',
                ['seatStyle'],
                values['seatStyle'] as String,
                (canonicalVisualFields['seatStyle']!['enum'] as List)
                    .cast<String>(),
              ),
            colorRow('Fill color', 'fill'),
          ],
          if (openPath) ...[
            colorRow('Outline color', 'stroke'),
            row(
              'Outline style',
              ['strokePattern'],
              DropdownButtonFormField<String>(
                initialValue:
                    (values['strokePattern'] as Map?)?['type'] as String? ??
                    'solid',
                items: [
                  for (final type in ['solid', 'dashed', 'dotted', 'custom'])
                    DropdownMenuItem(value: type, child: Text(tr(type))),
                ],
                onChanged: enabled
                    ? (type) {
                        if (type != null) {
                          change(
                            ['strokePattern'],
                            {
                              'type': type,
                              if (type == 'custom')
                                'lengths':
                                    (values['strokePattern']
                                        as Map?)?['lengths'] ??
                                    [12, 8],
                            },
                          );
                        }
                      }
                    : null,
              ),
            ),
            if ((values['strokePattern'] as Map?)?['type'] == 'custom')
              TextFormField(
                key: ValueKey('dash-${node.id}-${values['strokePattern']}'),
                initialValue:
                    ((values['strokePattern'] as Map)['lengths'] as List).join(
                      ', ',
                    ),
                enabled: enabled,
                maxLength: 256,
                decoration: InputDecoration(labelText: tr('Dash lengths')),
                onFieldSubmitted: (text) => change(
                  ['strokePattern'],
                  {
                    'type': 'custom',
                    'lengths': text
                        .split(',')
                        .map((value) => double.tryParse(value.trim()))
                        .toList(),
                  },
                ),
              ),
            number(
              'Outline width',
              ['strokeWidth'],
              values['strokeWidth'] as num,
              0,
              1000000000,
            ),
          ],
          if (labelVisible)
            ExpansionTile(
              minTileHeight: 44,
              key: ValueKey('text-style:$scope:$kind:${node.id}'),
              initiallyExpanded: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
              title: Text(
                tr('Text'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              children: [
                if (!widget.global &&
                    scope == 'node' &&
                    widget.fontPickerBuilder != null)
                  widget.fontPickerBuilder!(context, node)
                else if (widget.global &&
                    widget.globalFontPickerBuilder != null)
                  widget.globalFontPickerBuilder!(
                    context,
                    scope == 'document' ? 'document' : kind,
                  )
                else
                  row(
                    'Font family',
                    ['label', 'fontFamilyId'],
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: family == null
                          ? null
                          : label['fontFamilyId'] as String,
                      items: [
                        for (final entry
                            in (c.resources['fontFamilies'] as Map? ?? {})
                                .entries)
                          DropdownMenuItem(
                            value: entry.key as String,
                            child: Text(
                              '${entry.value['family']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: enabled
                          ? (v) {
                              if (v != null) {
                                change(['label', 'fontFamilyId'], v);
                              }
                            }
                          : null,
                    ),
                  ),
                row(
                  'Font size',
                  ['label', 'size'],
                  LayoutFontSizeControl(
                    key: ValueKey('font-size:$scope:$kind:${node.id}'),
                    controller: c,
                    node: node,
                    onReset: () => change(['label', 'size'], null, unset: true),
                    value: (label['size'] as num).toDouble(),
                    updateDocument: (document, value) => switch (scope) {
                      'document' => setDocumentLabelLeaf(
                        document,
                        'size',
                        value: value,
                      ),
                      'kind' => setKindStyleLeaf(document, kind, [
                        'label',
                        'size',
                      ], value: value),
                      'children' => setTableChildStyleLeaf(document, node.id, [
                        'label',
                        'size',
                      ], value: value),
                      _ => setNodeStyleLeaf(document, node.id, [
                        'label',
                        'size',
                      ], value: value),
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: EditorTextStyleControl(
                    key: const ValueKey('canonical-font-style'),
                    translate: tr,
                    showUnderline: false,
                    available: {
                      if (enabled && faces.containsKey(boldKey)) 'bold',
                      if (enabled && faces.containsKey(italicKey)) 'italic',
                    },
                    selected: {
                      if (label['weight'] == 700) 'bold',
                      if (label['italic'] == true) 'italic',
                    },
                    onChanged: enabled
                        ? (selection) {
                            var next = c.document;
                            for (final entry in {
                              'weight': selection.contains('bold') ? 700 : 400,
                              'italic': selection.contains('italic'),
                            }.entries) {
                              final path = ['label', entry.key];
                              next = switch (scope) {
                                'document' => setDocumentLabelLeaf(
                                  next,
                                  entry.key,
                                  value: entry.value,
                                ),
                                'kind' => setKindStyleLeaf(
                                  next,
                                  kind,
                                  path,
                                  value: entry.value,
                                ),
                                'children' => setTableChildStyleLeaf(
                                  next,
                                  node.id,
                                  path,
                                  value: entry.value,
                                ),
                                _ => setNodeStyleLeaf(
                                  next,
                                  node.id,
                                  path,
                                  value: entry.value,
                                ),
                              };
                            }
                            final accepted = c.apply(next, label: 'Text style');
                            setState(() => failure = accepted ? null : c.error);
                          }
                        : null,
                  ),
                ),
                if (family != null &&
                    (!faces.containsKey(boldKey) ||
                        !faces.containsKey(italicKey)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      tr(
                        'This font does not provide all bold and italic faces. Choose another font to use them.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                row(
                  'Alignment',
                  ['label', 'align'],
                  EditorTextAlignmentControl(
                    value: label['align'] as String,
                    translate: tr,
                    onChanged: enabled
                        ? (value) => change(['label', 'align'], value)
                        : null,
                  ),
                ),
                row(
                  'Text color',
                  ['label', 'color'],
                  OutlinedButton(
                    onPressed: enabled
                        ? () => color([
                            'label',
                            'color',
                          ], label['color'] as String)
                        : null,
                    child: EditorColorSwatch(
                      value: EditorColorValue.fromRgba(
                        label['color'] as String,
                      ),
                    ),
                  ),
                ),
                if (!widget.global && scope == 'node')
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Builder(
                      builder: (context) {
                        final targets = layoutTextStyleTargets(
                          c.document,
                          node,
                        );
                        final title = switch (node.kind) {
                          'table' => 'Apply text to other tables',
                          'seat' => 'Apply text to other seats',
                          'text' => 'Apply text to other texts',
                          _ => 'Apply text to matching objects',
                        };
                        return Tooltip(
                          message: tr(
                            'Copy font, size, weight, alignment and text color',
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const ValueKey('apply-text-style-to-peers'),
                              icon: const Icon(
                                Icons.format_paint_outlined,
                                size: 18,
                              ),
                              label: Text('${tr(title)} (${targets.length})'),
                              onPressed: enabled && targets.isNotEmpty
                                  ? () {
                                      final accepted = c.apply(
                                        applyLayoutTextStyle(c.document, node),
                                        label: 'Apply text style',
                                      );
                                      setState(
                                        () =>
                                            failure = accepted ? null : c.error,
                                      );
                                      if (accepted) {
                                        ScaffoldMessenger.maybeOf(
                                          context,
                                        )?.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${tr('Text style applied')}: ${targets.length}',
                                            ),
                                            action: SnackBarAction(
                                              label: tr('Undo'),
                                              onPressed: c.undo,
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ExpansionTile(
            minTileHeight: 44,
            key: ValueKey('advanced-appearance:$scope:$kind:${node.id}'),
            childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
            tilePadding: EdgeInsets.zero,
            title: Text(
              tr('Advanced appearance'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            children: [
              if (labelVisible) ...[
                choice(
                  'Direction',
                  ['label', 'direction'],
                  label['direction'] as String,
                  ['auto', 'ltr', 'rtl'],
                ),
                number(
                  'Line height',
                  ['label', 'lineHeight'],
                  label['lineHeight'] as num,
                  .8,
                  3,
                ),
                if (target.kind != 'text')
                  choice(
                    'Label orientation',
                    ['label', 'orientation'],
                    label['orientation'] as String,
                    ['object', 'screen'],
                  ),
              ],
              if (scope != 'document' && target.kind != 'group') ...[
                number('Opacity', ['opacity'], values['opacity'] as num, 0, 1),
                if (!media && target.kind != 'text') ...[
                  if (!openPath) ...[
                    colorRow('Outline color', 'stroke'),
                    row(
                      'Outline style',
                      ['strokePattern'],
                      DropdownButtonFormField<String>(
                        initialValue:
                            (values['strokePattern'] as Map?)?['type']
                                as String? ??
                            'solid',
                        items: [
                          for (final type in [
                            'solid',
                            'dashed',
                            'dotted',
                            'custom',
                          ])
                            DropdownMenuItem(
                              value: type,
                              child: Text(tr(type)),
                            ),
                        ],
                        onChanged: enabled
                            ? (type) {
                                if (type != null) {
                                  change(
                                    ['strokePattern'],
                                    {
                                      'type': type,
                                      if (type == 'custom')
                                        'lengths':
                                            (values['strokePattern']
                                                as Map?)?['lengths'] ??
                                            [12, 8],
                                    },
                                  );
                                }
                              }
                            : null,
                      ),
                    ),
                    if ((values['strokePattern'] as Map?)?['type'] == 'custom')
                      TextFormField(
                        key: ValueKey(
                          'dash-${node.id}-${values['strokePattern']}',
                        ),
                        initialValue:
                            ((values['strokePattern'] as Map)['lengths']
                                    as List)
                                .join(', '),
                        enabled: enabled,
                        maxLength: 256,
                        decoration: InputDecoration(
                          labelText: tr('Dash lengths'),
                        ),
                        onFieldSubmitted: (text) => change(
                          ['strokePattern'],
                          {
                            'type': 'custom',
                            'lengths': text
                                .split(',')
                                .map((value) => double.tryParse(value.trim()))
                                .toList(),
                          },
                        ),
                      ),
                    number(
                      'Outline width',
                      ['strokeWidth'],
                      values['strokeWidth'] as num,
                      0,
                      1000000000,
                    ),
                  ],
                  number(
                    'Corner radius',
                    ['cornerRadius'],
                    values['cornerRadius'] as num,
                    0,
                    1000000000,
                  ),
                ],
              ],
            ],
          ),
        ],
      );
    },
  );
}

class _CanonicalNumber extends StatefulWidget {
  const _CanonicalNumber({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onUndo,
    required this.onRedo,
  });
  final String label;
  final double value, min, max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback onUndo, onRedo;
  @override
  State<_CanonicalNumber> createState() => _CanonicalNumberState();
}

class _CanonicalNumberState extends State<_CanonicalNumber> {
  late final text = TextEditingController(text: widget.value.toString());
  final focus = FocusNode();
  String? error;
  @override
  void initState() {
    super.initState();
    focus.addListener(blur);
  }

  void blur() {
    if (!focus.hasFocus) submit();
  }

  void submit() {
    if (!widget.enabled) return;
    final value = double.tryParse(text.text);
    if (value == null ||
        !value.isFinite ||
        value < widget.min ||
        value > widget.max) {
      setState(() => error = '${widget.min} - ${widget.max}');
      return;
    }
    setState(() => error = null);
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  void didUpdateWidget(covariant _CanonicalNumber old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && old.value != widget.value) {
      text.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    focus.removeListener(blur);
    focus.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditorFieldHistory(
    hasUncommittedChanges: () =>
        double.tryParse(text.text.replaceAll(',', '.')) != widget.value,
    onUndo: widget.onUndo,
    onRedo: widget.onRedo,
    child: EditorNumberScroll(
      enabled: widget.enabled,
      min: widget.min,
      max: widget.max,
      step: widget.max <= 3 ? .1 : 1,
      onChanged: submit,
      child: TextField(
        controller: text,
        focusNode: focus,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: widget.label, errorText: error),
        onEditingComplete: () => submit(),
        onSubmitted: (_) => submit(),
      ),
    ),
  );
}

Future<void> showCanonicalAppearanceDialog(
  BuildContext context,
  VenueLayoutController controller, {
  String? nodeId,
  bool global = false,
  Widget Function(BuildContext, String)? globalFontPickerBuilder,
}) => showEditorDialog<void>(
  context: context,
  barrierColor: Colors.transparent,
  builder: (context) => EditorDialogDismissal(
    child: AlertDialog(
      alignment: Alignment.centerRight,
      insetPadding: const EdgeInsets.all(16),
      title: Row(
        children: [
          Expanded(child: LayoutText(global ? 'Plan style' : 'Object style')),
          IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Close'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LayoutText('Style family'),
              const SizedBox(height: 12),
              LayoutMaterialFamilies(
                controller: controller,
                nodeId: global ? null : nodeId,
              ),
              const SizedBox(height: 16),
              const LayoutText('Color palette'),
              const SizedBox(height: 8),
              LayoutStylePresets(
                colorsOnly: true,
                controller: controller,
                onApply: (appearance) => controller.apply(
                  global
                      ? applyGlobalLayoutAppearance(
                          controller.document,
                          appearance,
                        )
                      : applyLayoutAppearance(controller.document, {
                          nodeId!,
                        }, appearance),
                  label: 'Apply style',
                ),
              ),
              if (global)
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) =>
                      LayoutFloorStyleField(controller: controller),
                ),
              const SizedBox(height: 12),
              ExpansionTile(
                minTileHeight: 44,
                title: const LayoutText('Detailed settings'),
                children: [
                  CanonicalAppearancePanel(
                    controller: controller,
                    nodeId: nodeId,
                    global: global,
                    globalFontPickerBuilder: globalFontPickerBuilder,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
