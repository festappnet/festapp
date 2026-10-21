import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:venue_seat_picker/editor_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'layout_style.dart';
import 'layout_number_slider_control.dart';
import 'canonical_appearance_panel.dart';
import 'layout_global_style.dart';
import 'layout_floor_style.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

class LayoutInspector extends StatefulWidget {
  const LayoutInspector({
    super.key,
    required this.controller,
    required this.cornerPivot,
    required this.onPivotChanged,
    this.hostBuilder,
    this.onRenameNode,
    this.fontPickerBuilder,
    this.globalFontPickerBuilder,
    this.onOpenGlobalStyle,
    this.canvasSelected = false,
    this.backgroundSelected = false,
    this.onSelectBackground,
    this.onImportBackground,
    this.onClearSelection,
    this.onCopyStyle,
    this.onPasteStyle,
    this.readOnlyLabelNodeIds = const {},
  });
  final VenueLayoutController controller;

  /// Optional host font catalog for object typography, built only in edit mode.
  final Widget Function(BuildContext, LayoutNode)? fontPickerBuilder;
  final Widget Function(BuildContext, String)? globalFontPickerBuilder;
  final void Function(LayoutNode, String)? onRenameNode;
  final VoidCallback? onOpenGlobalStyle;
  final Set<String> readOnlyLabelNodeIds;
  final bool cornerPivot;
  final bool canvasSelected, backgroundSelected;
  final VoidCallback? onSelectBackground;
  final Future<void> Function()? onImportBackground;
  final VoidCallback? onCopyStyle, onPasteStyle, onClearSelection;
  final ValueChanged<bool> onPivotChanged;
  final Widget Function(BuildContext, LayoutNode)? hostBuilder;
  @override
  State<LayoutInspector> createState() => _LayoutInspectorState();
}

class _LayoutInspectorState extends State<LayoutInspector> {
  VenueLayoutController get c => widget.controller;
  String _search = '';
  String? _selectionContext;
  String? _error;
  int _shapeControlRevision = 0;
  Map<String, LayoutNode> _nodesById = {};
  VenueLayoutDocument? _indexedDocument, _layerDocument;
  List<LayoutNode> _orderedLayers = const [], _filteredLayers = const [];
  String? _layerSearch;
  bool _layersExpanded = false;
  Widget? _layerRows;
  Set<String> _layerSelection = const {};

  // Layer rows depend on tree/order/name/lock metadata, not live coordinates or
  // appearance. Geometry previews can retain the same subtree of widgets.
  bool _sameLayerMetadata(
    VenueLayoutDocument before,
    VenueLayoutDocument after,
  ) {
    if (before.nodes.length != after.nodes.length) return false;
    for (var i = 0; i < before.nodes.length; i++) {
      final a = before.nodes[i], b = after.nodes[i];
      if (a.id != b.id ||
          a.parentId != b.parentId ||
          a.z != b.z ||
          a.kind != b.kind ||
          a.label != b.label ||
          a.locked != b.locked) {
        return false;
      }
    }
    return true;
  }

  List<LayoutNode> _layers() {
    final document = c.document;
    if (!identical(document, _layerDocument)) {
      if (_layerDocument == null ||
          !_sameLayerMetadata(_layerDocument!, document)) {
        _orderedLayers = orderedNodes(document);
        _layerSearch = null;
      }
      _layerDocument = document;
    }
    final search = _search.toLowerCase();
    if (_layerSearch != search) {
      _filteredLayers = search.isEmpty
          ? _orderedLayers
          : _orderedLayers
                .where(
                  (n) => '${n.label} ${n.kind}'.toLowerCase().contains(search),
                )
                .toList();
      _layerSearch = search;
      _layerRows = null;
    }
    return _filteredLayers;
  }

  Widget _rows(List<LayoutNode> layers, Set<String> selection) {
    if (_layerRows != null && setEquals(_layerSelection, selection)) {
      return _layerRows!;
    }
    _layerSelection = selection;
    int depth(LayoutNode node) {
      var result = 0;
      var parent = node.parentId;
      final seen = <String>{};
      while (parent != null && seen.add(parent)) {
        result++;
        parent = _nodesById[parent]?.parentId;
      }
      return result;
    }

    return _layerRows = Column(
      children: [
        for (final n in layers.take(200))
          MouseRegion(
            onEnter: (_) => c.highlightObjects({n.id}),
            onExit: (_) => c.highlightObjects({}),
            child: ListTile(
              key: ValueKey('layout-layer-${n.id}'),
              contentPadding: EdgeInsets.only(left: depth(n) * 12.0),
              leading: Icon(
                n.kind == 'group'
                    ? Icons.folder_outlined
                    : Icons.layers_outlined,
                size: 16,
              ),
              dense: true,
              selected: selection.contains(n.id),
              title: LayoutText(
                n.label.isEmpty ? n.kind : n.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: LayoutText(n.kind),
              trailing: n.locked ? const Icon(Icons.lock_outline) : null,
              onTap: () => c.select({n.id}),
              onLongPress: () => c.select({...c.selection, n.id}),
            ),
          ),
        if (layers.length > 200)
          LayoutText(
            '${layers.length - 200} more objects. Refine search to find them.',
          ),
      ],
    );
  }

  void _run(VoidCallback action) {
    try {
      action();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _nodeFill(LayoutNode node) =>
      '${effectiveNodeProperties(c.document, node)['fill'] ?? switch (node.kind) {
            'seat' => _nodesById[node.parentId]?.assembly?['kind'] == 'couch' ? '#F8FAFCFF' : layoutDefaultSeatFill,
            'table' => '#E2E8F0FF',
            'capacityArea' => '#DBEAFEFF',
            _ => '#F1F5F9FF',
          }}';

  List<String> _collectUsedColors() {
    final colors = <String>{};
    void add(dynamic value) {
      if (value is String &&
          RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(value) &&
          value.substring(7).toUpperCase() != '00') {
        colors.add(value.substring(1, 7).toUpperCase());
      }
    }

    add(c.document.canvas['fill']);
    for (final node in c.document.nodes) {
      add(_nodeFill(node));
      for (final key in ['fill', 'stroke', 'color']) {
        add(effectiveNodeProperties(c.document, node)[key]);
      }
    }
    return colors.toList();
  }

  Widget _field(
    String label,
    String value,
    ValueChanged<String> save, {
    bool multiline = false,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _PropertyField(
      key: ValueKey(label),
      label: label,
      value: value,
      enabled: !(c.readOnly || c.saving),
      multiline: multiline,
      numeric: numeric,
      onUndo: c.undo,
      onRedo: c.redo,
      save: (v) => _run(() => save(v)),
      usedColors: _collectUsedColors,
      paletteImage:
          (c.resources['images'] as Map?)?[c.document.background?['assetRef']]
              as ui.Image?,
    ),
  );
  Widget _number(String label, num value, ValueChanged<double> save) => _field(
    label,
    const {
          'Opacity',
          'Outline width',
          'Line height',
          'Curvature',
        }.contains(label)
        ? value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')
        : value.round().toString(),
    (v) {
      final parsed = double.tryParse(v.replaceAll(',', '.'));
      if (parsed == null || !parsed.isFinite) {
        throw const FormatException('Enter a valid number.');
      }
      if (const {
            'Number of rows',
            'Seats per row',
            'Blocks',
            'Seats on couch',
            'Number of teeth',
            'Standing capacity',
          }.contains(label) &&
          parsed != parsed.roundToDouble()) {
        throw FormatException(
          VenueLayoutStrings.text(context, 'Enter a positive whole number.'),
        );
      }
      save(
        const {
              'Opacity',
              'Outline width',
              'Line height',
              'Curvature',
            }.contains(label)
            ? (parsed * 100).round() / 100
            : parsed.roundToDouble(),
      );
    },
    numeric: true,
  );

  Future<void> _preview(
    String title,
    VenueLayoutDocument Function(Map<String, double>) generate,
    Map<String, double> initial, {
    String? detail,
  }) async {
    final values = Map<String, double>.of(initial);
    c.beginGesture();
    String? error;
    final accepted = await showEditorDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: LayoutText(title),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LayoutText(detail),
                    ),
                  for (final key in values.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        initialValue: values[key]!
                            .toStringAsFixed(2)
                            .replaceFirst(RegExp(r'\.?0+$'), ''),
                        decoration: InputDecoration(
                          labelText: VenueLayoutStrings.text(context, key),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (text) {
                          final value = double.tryParse(text);
                          if (value == null || !value.isFinite) {
                            update(() => error = 'Enter a valid $key.');
                            return;
                          }
                          values[key] = value;
                          try {
                            c.preview(generate(values));
                            update(() => error = c.error);
                          } catch (e) {
                            update(() => error = '$e');
                          }
                        },
                      ),
                    ),
                  if (error != null)
                    LayoutText(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LayoutText('Cancel'),
            ),
            FilledButton(
              onPressed: error == null
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const LayoutText('Apply'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      c.commitGesture();
    } else {
      c.cancelGesture();
    }
  }

  void _updateRows(LayoutNode node, String key, double value) {
    final parameters = rowLayoutParameters(c.document, node.id);
    if (const {'rows', 'seatsPerRow', 'blocks'}.contains(key) &&
        (value != value.roundToDouble() || value < 1)) {
      throw FormatException(
        VenueLayoutStrings.text(context, 'Enter a positive whole number.'),
      );
    }
    final values = <String, num>{...parameters, key: value};
    final generated = rowLayout(
      rows: values['rows']!.toInt(),
      seatsPerRow: values['seatsPerRow']!.toInt(),
      blocks: values['blocks']!.toInt(),
      arc: values['arc']!.toDouble(),
      spacing: values['spacing']!.toDouble(),
      rowSpacing: values['rowSpacing']!.toDouble(),
      aisle: values['aisle']!.toDouble(),
      seating: TableSeating.fromDocument(c.document, node),
    );
    c.apply(
      reconcileAssembly(c.document, node.id, generated),
      label: 'Adjust rows',
    );
  }

  Widget _rowControls(LayoutNode node) {
    final values = rowLayoutParameters(c.document, node.id);
    final enabled = !(c.readOnly || c.saving || node.locked);
    Widget count(String label, String key) {
      final value = values[key]!.toInt();
      final noun = const {
        'rows': 'row',
        'seatsPerRow': 'column',
        'blocks': 'block',
      }[key]!;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _number(label, value, (v) => _updateRows(node, key, v)),
          ),
          IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Remove $noun'),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: !enabled || value <= 1
                ? null
                : () => _run(
                    () => _updateRows(node, key, (value - 1).toDouble()),
                  ),
          ),
          IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Add $noun'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: !enabled
                ? null
                : () => _run(
                    () => _updateRows(node, key, (value + 1).toDouble()),
                  ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        count('Number of rows', 'rows'),
        count('Seats per row', 'seatsPerRow'),
        _number(
          'Curvature',
          values['arc']!,
          (v) => _updateRows(node, 'arc', v),
        ),
        Slider(
          semanticFormatterCallback: (value) => value.toStringAsFixed(1),
          value: values['arc']!.toDouble(),
          min: -math.max(12.0, values['arc']!.abs().toDouble()),
          max: math.max(12.0, values['arc']!.abs().toDouble()),
          divisions: 96,
          label: values['arc']!.toStringAsFixed(1),
          onChangeStart: !enabled ? null : (_) => c.beginGesture(),
          onChanged: !enabled
              ? null
              : (value) => _run(() => _updateRows(node, 'arc', value)),
          onChangeEnd: !enabled
              ? null
              : (_) {
                  if (c.error == null) {
                    c.commitGesture();
                  } else {
                    final error = c.error;
                    c.cancelGesture();
                    c.error = error;
                  }
                },
        ),
        ExpansionTile(
          minTileHeight: 44,
          tilePadding: EdgeInsets.zero,
          title: const LayoutText('Row arrangement'),
          children: [
            _number(
              'Seat spacing',
              values['spacing']!,
              (v) => _updateRows(node, 'spacing', v),
            ),
            _number(
              'Row spacing',
              values['rowSpacing']!,
              (v) => _updateRows(node, 'rowSpacing', v),
            ),
            count('Blocks', 'blocks'),
            _number(
              'Aisle width',
              values['aisle']!,
              (v) => _updateRows(node, 'aisle', v),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _countControl(
    String label,
    int value,
    ValueChanged<int> save, {
    int min = 0,
    int max = 30,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutText(label, style: Theme.of(context).textTheme.labelLarge),
      Row(
        children: [
          IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Remove one'),
            onPressed: c.readOnly || c.saving || value <= min
                ? null
                : () => _run(() => save(value - 1)),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(child: Text('$value', textAlign: TextAlign.center)),
          IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Add one'),
            onPressed: c.readOnly || c.saving || value >= max
                ? null
                : () => _run(() => save(value + 1)),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );

  Widget _transportControls(LayoutNode n) {
    final p = {...n.assembly ?? {}, 'assembly': n.assembly?['kind']};
    void bus({
      int? rows,
      int? left,
      int? right,
      int? rear,
      int? decks,
      int? upperRows,
      int? upperRear,
    }) => c.apply(
      localizeLayoutDefaultLabels(
        updateBusLayout(
          c.document,
          n.id,
          rows: rows,
          left: left,
          right: right,
          rear: rear,
          decks: decks,
          upperRows: upperRows,
          upperRear: upperRear,
          protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
        ),
        (text) => VenueLayoutStrings.text(context, text),
      ),
      label: 'Adjust assembly',
    );
    void coupe({int? compartments, int? seats}) => c.apply(
      localizeLayoutDefaultLabels(
        updateCompartmentLayout(
          c.document,
          n.id,
          compartments: compartments,
          seats: seats,
          protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
        ),
        (text) => VenueLayoutStrings.text(context, text),
      ),
      label: 'Adjust assembly',
    );
    final enabled = !c.readOnly && !c.saving;
    if (p['assembly'] == 'compartments') {
      return Column(
        children: [
          _countControl(
            'Compartments',
            (p['compartments'] as num? ?? 4).toInt(),
            (v) => coupe(compartments: v),
            min: 1,
            max: 12,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: DropdownButtonFormField<int>(
              key: ValueKey('coupe-seats-${p['seats']}'),
              initialValue: (p['seats'] as num? ?? 6).toInt(),
              decoration: InputDecoration(
                labelText: VenueLayoutStrings.text(
                  context,
                  'Seats per compartment',
                ),
              ),
              items: [
                for (final count in [4, 6, 8])
                  DropdownMenuItem(value: count, child: Text('$count')),
              ],
              onChanged: enabled ? (v) => _run(() => coupe(seats: v)) : null,
            ),
          ),
        ],
      );
    }
    final decks = (p['decks'] as num? ?? 1).toInt();
    final layout = '${p['left'] ?? 2}+${p['right'] ?? 2}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LayoutText('Decks'),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1')),
            ButtonSegment(value: 2, label: Text('2')),
          ],
          selected: {decks},
          onSelectionChanged: enabled
              ? (v) => _run(() => bus(decks: v.single))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 16),
          child: DropdownButtonFormField<String>(
            key: ValueKey('bus-seat-layout-$layout'),
            initialValue: layout,
            decoration: InputDecoration(
              labelText: VenueLayoutStrings.text(context, 'Seat layout'),
            ),
            items: [
              for (final value in {'1+1', '1+2', '2+2', '2+3', layout})
                DropdownMenuItem(
                  value: value,
                  child: Text(value.replaceAll('+', ' + ')),
                ),
            ],
            onChanged: enabled
                ? (v) => _run(() {
                    final parts = v!.split('+');
                    bus(left: int.parse(parts[0]), right: int.parse(parts[1]));
                  })
                : null,
          ),
        ),
        _countControl(
          decks == 2 ? 'Rows on lower deck' : 'Rows',
          (p['rows'] as num? ?? 10).toInt(),
          (v) => bus(rows: v),
          min: 1,
        ),
        _countControl(
          decks == 2 ? 'Rear seats on lower deck' : 'Rear seats',
          (p['rear'] as num? ?? 5).toInt(),
          (v) => bus(rear: v),
          max: 6,
        ),
        if (decks == 2) ...[
          _countControl(
            'Rows on upper deck',
            (p['upperRows'] as num? ?? p['rows'] as num? ?? 10).toInt(),
            (v) => bus(upperRows: v),
            min: 1,
          ),
          _countControl(
            'Rear seats on upper deck',
            (p['upperRear'] as num? ?? p['rear'] as num? ?? 5).toInt(),
            (v) => bus(upperRear: v),
            max: 6,
          ),
        ],
      ],
    );
  }

  Widget _seatCountControls(LayoutNode node) {
    final couch = isCouchNode(node), minimum = isCouchNode(node) ? 1 : 0;
    final count = couch
        ? couchSeatCount(c.document, node.id)
        : c.document.nodes
              .where((n) => n.parentId == node.id && n.kind == 'seat')
              .length;
    final enabled = !(c.readOnly || c.saving || node.locked);
    final remaining =
        layoutMaxSeats - c.document.nodes.where((n) => n.kind == 'seat').length;
    final maximum = math.min(
      couch
          ? layoutMaxSeats
          : tableCapacity(
              node.copyWith(
                seating: TableSeating.fromDocument(c.document, node).record,
              ),
            ),
      count + remaining,
    );
    return Row(
      children: [
        Expanded(
          child: _number(couch ? 'Seats on couch' : 'Seats', count, (value) {
            if (value != value.roundToDouble() || value < minimum) {
              throw const FormatException('Enter a valid whole seat count.');
            }
            c.setSeatCount(node.id, value.toInt());
          }),
        ),
        IconButton(
          tooltip: VenueLayoutStrings.text(context, 'Remove one seat'),
          onPressed: enabled && count > minimum
              ? () => c.setSeatCount(node.id, count - 1)
              : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        IconButton(
          tooltip: VenueLayoutStrings.text(context, 'Add one seat'),
          onPressed: enabled && count < maximum
              ? () => c.setSeatCount(node.id, count + 1)
              : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  String _typeTitle(LayoutNode node) => isZigzagNode(node)
      ? 'Zigzag'
      : isBarNode(node)
      ? 'Bar'
      : node.properties['furniture'] == 'stool' ||
            isBarNode(_nodesById[node.parentId] ?? node)
      ? 'Bar stool'
      : isCouchNode(node)
      ? 'Couch'
      : node.assembly?['kind'] == 'rows'
      ? 'Seat rows'
      : node.kind == 'shape'
      ? const {
              'line': 'Line',
              'polyline': 'Polyline',
              'arrow': 'Arrow',
              'polygon': 'Polygon',
              'rect': 'Rectangle',
              'rectangle': 'Rectangle',
              'roundedRect': 'Rectangle',
              'ellipse': 'Ellipse',
              'circle': 'Ellipse',
              'round': 'Ellipse',
              'oval': 'Ellipse',
            }[node.properties['shape']] ??
            'Shape'
      : const {
              'table': 'Table',
              'seat': 'Chair',
              'text': 'Text',
              'capacityArea': 'Standing',
              'group': 'Object group',
              'shape': 'Shape',
            }[node.kind] ??
            node.kind;

  String _tableShape(LayoutNode node) => switch (node.surface!['type']) {
    'circle' => 'round',
    'grid' => 'polygon',
    _ => 'rectangle',
  };

  void _changeTableShape(LayoutNode node, String shape) {
    if (shape == _tableShape(node)) return;
    {
      c.apply(
        setTableSurfaceKind(c.document, node.id, switch (shape) {
          'round' => 'circle',
          'polygon' => 'grid',
          _ => 'rect',
        }, protectedSeatIds: c.protectedSeatIds?.call() ?? const {}),
        label: 'Change table shape',
      );
      return;
    }
  }

  Widget _tableShapeControls(LayoutNode node) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(
            'table-shape-${node.id}-${_tableShape(node)}-$_shapeControlRevision',
          ),
          initialValue: _tableShape(node),
          isExpanded: true,
          decoration: InputDecoration(
            labelText: VenueLayoutStrings.text(
              context,
              isBarNode(node) ? 'Surface shape' : 'Table shape',
            ),
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final entry in {
              'rectangle': 'Rectangle',
              if (!isBarNode(node)) 'round': 'Round',
              'polygon': 'Custom outline',
            }.entries)
              DropdownMenuItem(
                value: entry.key,
                child: LayoutText(entry.value),
              ),
          ],
          onChanged: c.readOnly || c.saving || node.locked
              ? null
              : (shape) {
                  if (shape != null) {
                    _shapeControlRevision++;
                    _run(() => _changeTableShape(node, shape));
                  }
                },
        ),
        if (_tableShape(node) == 'polygon')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LayoutText('Pull an edge handle to extend the surface.'),
          ),
      ],
    ),
  );

  Widget _chairSide(LayoutNode seat) {
    final table = tableForSeat(c.document, seat);
    final side = tableSideForSeat(c.document, seat);
    if (table == null || side == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('chair-side-${seat.id}-$side'),
        initialValue: side,
        decoration: InputDecoration(
          labelText: VenueLayoutStrings.text(context, 'Table side'),
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final entry in const {
            'top': 'Top side',
            'right': 'Right side',
            'bottom': 'Bottom side',
            'left': 'Left side',
          }.entries)
            DropdownMenuItem(value: entry.key, child: LayoutText(entry.value)),
        ],
        onChanged: c.readOnly || c.saving || seat.locked || table.locked
            ? null
            : (side) {
                if (side != null) {
                  _run(() => c.moveChairToTableSide(seat.id, side));
                }
              },
      ),
    );
  }

  Future<String?> _styleName(
    String heading, {
    String initial = '',
    String? id,
  }) {
    var name = initial, error = '';
    return showEditorDialog<String>(
      context: context,
      builder: (dialogContext) => EditorDialogDismissal(
        child: StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Row(
              children: [
                Expanded(child: LayoutText(heading)),
                IconButton(
                  tooltip: VenueLayoutStrings.text(context, 'Close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
            content: TextFormField(
              autofocus: true,
              initialValue: initial,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: VenueLayoutStrings.text(context, 'Style name'),
                errorText: error.isEmpty
                    ? null
                    : VenueLayoutStrings.text(context, error),
              ),
              onChanged: (value) => name = value,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const LayoutText('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final title = name.trim();
                  if (title.isEmpty) {
                    update(() => error = 'Enter a style name.');
                    return;
                  }
                  if (c.document.presets.any(
                    (p) =>
                        p['id'] != id &&
                        (p['title'] as String).toLowerCase() ==
                            title.toLowerCase(),
                  )) {
                    update(
                      () => error = 'A style with this name already exists.',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, title);
                },
                child: const LayoutText('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveNamedStyle(LayoutNode node) async {
    final name = await _styleName('Save as style');
    if (name == null || !mounted) return;
    _run(
      () => c.apply(
        saveLayoutAppearancePreset(c.document, node, name),
        label: 'Save style',
      ),
    );
  }

  Future<void> _manageNamedStyles(String kind) => showEditorDialog<void>(
    context: context,
    builder: (dialogContext) => EditorDialogDismissal(
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final ids = namedLayoutAppearances(c.document, kind).keys.toSet();
          final styles = c.document.presets
              .where((p) => ids.contains(p['id']))
              .toList();
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: LayoutText('My styles')),
                IconButton(
                  tooltip: VenueLayoutStrings.text(context, 'Close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              height: 320,
              child: styles.isEmpty
                  ? const LayoutText('No saved styles yet.')
                  : ListView(
                      children: [
                        for (final preset in styles)
                          ListTile(
                            title: Text(preset['title'] as String),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: VenueLayoutStrings.text(
                                    context,
                                    'Rename style',
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: c.readOnly || c.saving
                                      ? null
                                      : () async {
                                          final name = await _styleName(
                                            'Rename style',
                                            initial: preset['title'] as String,
                                            id: preset['id'] as String,
                                          );
                                          if (name == null || !mounted) return;
                                          _run(
                                            () => c.apply(
                                              c.document.copyWith(
                                                presets: [
                                                  for (final p
                                                      in c.document.presets)
                                                    p['id'] == preset['id']
                                                        ? {...p, 'title': name}
                                                        : p,
                                                ],
                                              ),
                                              label: 'Rename style',
                                            ),
                                          );
                                        },
                                ),
                                IconButton(
                                  tooltip: VenueLayoutStrings.text(
                                    context,
                                    'Delete style',
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: c.readOnly || c.saving
                                      ? null
                                      : () => _run(
                                          () => c.apply(
                                            c.document.copyWith(
                                              presets: [
                                                for (final p
                                                    in c.document.presets)
                                                  if (p['id'] != preset['id'])
                                                    p,
                                              ],
                                            ),
                                            label: 'Delete style',
                                          ),
                                        ),
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

  Widget _quickObjectStyles(LayoutNode node) {
    final custom = namedLayoutAppearances(c.document, node.kind);
    const families = {
      'minimal': 'Minimal',
      'wood': 'Timber',
      'lounge': 'Lounge',
      'round': 'Round seating',
      'banquet': 'Banquet hall',
      'transit': 'Transport',
      'cinema': 'Cinema',
    };
    final canSave = const {
      'table',
      'seat',
      'text',
      'shape',
      'capacityArea',
    }.contains(node.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (widget.onCopyStyle != null)
              IconButton(
                tooltip: VenueLayoutStrings.text(context, 'Copy style'),
                onPressed: widget.onCopyStyle,
                icon: const Icon(Icons.format_paint_outlined),
              ),
            if (widget.onCopyStyle != null || widget.onPasteStyle != null)
              IconButton(
                tooltip: VenueLayoutStrings.text(context, 'Paste style'),
                onPressed: c.readOnly || c.saving ? null : widget.onPasteStyle,
                icon: const Icon(Icons.content_paste),
              ),
            if (canSave)
              PopupMenuButton<String>(
                tooltip: VenueLayoutStrings.text(context, 'Style actions'),
                enabled: !c.readOnly && !c.saving && !node.locked,
                onSelected: (action) {
                  if (action == 'save') {
                    _saveNamedStyle(node);
                  } else {
                    _manageNamedStyles(node.kind);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'save',
                    child: LayoutText('Save as style'),
                  ),
                  if (custom.isNotEmpty)
                    const PopupMenuItem(
                      value: 'manage',
                      child: LayoutText('My styles'),
                    ),
                ],
              ),
          ],
        ),
        OutlinedButton.icon(
          key: const ValueKey('layout-style-default'),
          icon: const Icon(Icons.restart_alt),
          label: const LayoutText('Default'),
          onPressed: c.readOnly || c.saving || node.locked
              ? null
              : () => _run(
                  () => c.apply(
                    c.document.copyWith(
                      nodes: [
                        for (final current in c.document.nodes)
                          if (current.id == node.id)
                            current.copyWith(
                              style: const {},
                              childStyles: current.kind == 'table'
                                  ? ({...current.childStyles}..remove('seat'))
                                  : current.childStyles,
                            )
                          else
                            current,
                      ],
                    ),
                    label: 'Reset style',
                  ),
                ),
        ),
        const SizedBox(height: 8),
        if (node.kind == 'table' || custom.isNotEmpty)
          LayoutStylePresets(
            controller: c,
            appearances: {
              if (node.kind == 'table')
                for (final key in families.keys)
                  key: layoutMaterialFamilyAppearances[key]!,
              ...custom,
            },
            labelFor: (key) => families[key] == null
                ? c.document.presets.firstWhere((p) => p['id'] == key)['title']
                      as String
                : VenueLayoutStrings.text(context, families[key]!),
            onApply: (appearance) => _run(
              () => c.apply(
                applyLayoutAppearance(c.document, {node.id}, appearance),
                label: 'Apply style',
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _canonicalNode(LayoutNode node) {
    final rowBounds = isRowAssemblyNode(node)
        ? rowAssemblyBounds(c.document, node.id)
        : null;
    final currentWidth = rowBounds?['width'] ?? node.width,
        currentHeight = rowBounds?['height'] ?? node.height;
    final seating = node.kind == 'table'
        ? TableSeating.fromDocument(c.document, node)
        : null;
    void dimension(double value, {required bool width}) {
      if (node.surface?['type'] == 'grid') {
        c.apply(
          resizeGridTableSurface(
            c.document,
            node.id,
            width ? value : currentWidth,
            width ? currentHeight : value,
            protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
          ),
          label: 'Resize grid surface',
        );
        return;
      }

      final uniform = node.surface?['type'] == 'circle';
      c.resizeObject(
        node.id,
        width
            ? value
            : uniform
            ? currentWidth * value / currentHeight
            : currentWidth,
        !width
            ? value
            : uniform
            ? currentHeight * value / currentWidth
            : currentHeight,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.readOnlyLabelNodeIds.contains(node.id) ||
            widget.onRenameNode != null)
          _field('Name', node.label, (value) {
            if (widget.readOnlyLabelNodeIds.contains(node.id)) {
              widget.onRenameNode!(node, value);
            } else {
              c.updateNode(node.copyWith(label: value));
            }
          }),
        if (node.kind == 'text')
          _field(
            'Text',
            '${node.properties['text'] ?? ''}',
            (value) => c.updateNode(
              node.copyWith(properties: {...node.properties, 'text': value}),
            ),
            multiline: true,
          ),
        if (node.kind == 'table') _tableShapeControls(node),
        if (seating != null || isCouchNode(node)) _seatCountControls(node),
        if (isBarNode(node))
          DropdownButtonFormField<String>(
            initialValue: node.properties['guestSide'] as String? ?? 'bottom',
            decoration: InputDecoration(
              labelText: VenueLayoutStrings.text(context, 'Guest side'),
            ),
            items: [
              for (final side in barGuestSides)
                DropdownMenuItem(value: side, child: LayoutText(side)),
            ],
            onChanged: c.readOnly || c.saving || node.locked
                ? null
                : (side) {
                    if (side != null)
                      _run(
                        () => c.apply(
                          setBarGuestSide(
                            c.document,
                            node.id,
                            side,
                            protectedSeatIds:
                                c.protectedSeatIds?.call() ?? const {},
                          ),
                          label: 'Change bar side',
                        ),
                      );
                  },
          ),
        if (isZigzagNode(node)) ...[
          Row(
            children: [
              IconButton(
                tooltip: VenueLayoutStrings.text(context, 'Remove one tooth'),
                onPressed:
                    c.readOnly ||
                        c.saving ||
                        node.locked ||
                        (node.properties['zigzagTeeth'] as int) <= 1
                    ? null
                    : () => _run(
                        () => c.apply(
                          updateZigzag(
                            c.document,
                            node.id,
                            teeth: (node.properties['zigzagTeeth'] as int) - 1,
                          ),
                          label: 'Adjust zigzag',
                        ),
                      ),
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: VenueLayoutStrings.text(context, 'Add one tooth'),
                onPressed:
                    c.readOnly ||
                        c.saving ||
                        node.locked ||
                        2 * (node.properties['zigzagTeeth'] as int) + 4 >
                            layoutLimits['verticesMax']!
                    ? null
                    : () => _run(
                        () => c.apply(
                          updateZigzag(
                            c.document,
                            node.id,
                            teeth: (node.properties['zigzagTeeth'] as int) + 1,
                          ),
                          label: 'Adjust zigzag',
                        ),
                      ),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          _number(
            'Number of teeth',
            node.properties['zigzagTeeth'] as num,
            (value) => c.apply(
              updateZigzag(c.document, node.id, teeth: value.toInt()),
              label: 'Adjust zigzag',
            ),
          ),
          _number(
            'Zigzag height',
            (node.properties['zigzagAmplitude'] as num) * 2,
            (value) => c.apply(
              updateZigzag(c.document, node.id, amplitude: value / 2),
              label: 'Adjust zigzag',
            ),
          ),
        ],

        if (node.kind == 'capacityArea')
          _number(
            'Standing capacity',
            node.properties['capacity'] as num? ?? 0,
            (value) => c.updateNode(
              node.copyWith(
                properties: {...node.properties, 'capacity': value.toInt()},
              ),
            ),
          ),
        if (node.kind == 'seat') _chairSide(node),
        if (isRowAssemblyNode(node)) _rowControls(node),
        if (const {'bus', 'compartments'}.contains(node.assembly?['kind']))
          _transportControls(node),
        const SizedBox(height: 12),
        if (node.kind == 'image')
          TextButton(
            onPressed: (c.readOnly || c.saving)
                ? null
                : () {
                    final base = c.document,
                        graphic = node.graphic!,
                        crop = graphic['crop'] as Map;
                    _preview(
                      'Crop image',
                      (values) => base.copyWith(
                        nodes: [
                          for (final current in base.nodes)
                            current.id == node.id
                                ? current.copyWith(
                                    graphic: {
                                      ...graphic,
                                      'crop': {
                                        'x': values['Left'],
                                        'y': values['Top'],
                                        'width': values['Width'],
                                        'height': values['Height'],
                                      },
                                    },
                                  )
                                : current,
                        ],
                      ),
                      {
                        'Left': (crop['x'] as num).toDouble(),
                        'Top': (crop['y'] as num).toDouble(),
                        'Width': (crop['width'] as num).toDouble(),
                        'Height': (crop['height'] as num).toDouble(),
                      },
                      detail:
                          'Normalized image coordinates, from 0 to 1. Original pixels are retained.',
                    );
                  },
            child: const LayoutText('Crop image'),
          ),
        if (node.kind == 'seat' &&
            c.document.nodes.any(
              (parent) => parent.id == node.parentId && parent.kind == 'table',
            ) &&
            seatAttachment(c.document, node.id)?['placement']?['mode'] !=
                'automatic')
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              key: const ValueKey('restore-automatic-chair'),
              onPressed: c.readOnly || c.saving || node.locked
                  ? null
                  : () => c.restoreAutomaticChairPosition(node.id),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const LayoutText('Restore automatic position'),
            ),
          ),
        _quickObjectStyles(node),
        CanonicalAppearancePanel(
          controller: c,
          nodeId: node.id,
          fontPickerBuilder: widget.fontPickerBuilder,
        ),
        ExpansionTile(
          minTileHeight: 44,
          key: ValueKey('object-geometry:${node.id}'),
          childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
          tilePadding: EdgeInsets.zero,
          title: const LayoutText(
            'Position and size',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          children: [
            _number(
              'X',
              node.x,
              (value) => c.updateNode(node.copyWith(x: value)),
            ),
            _number(
              'Y',
              node.y,
              (value) => c.updateNode(node.copyWith(y: value)),
            ),
            if (!const {
              'bus',
              'compartments',
            }.contains(node.assembly?['kind'])) ...[
              _number(
                'Width',
                currentWidth,
                (value) => dimension(value, width: true),
              ),
              _number(
                'Height',
                currentHeight,
                (value) => dimension(value, width: false),
              ),
            ],
            _number(
              'Rotation',
              node.rotation,
              (value) => c.updateNode(node.copyWith(rotation: value)),
            ),
          ],
        ),
        if (seating != null)
          ExpansionTile(
            minTileHeight: 44,
            key: ValueKey('chair-layout:${node.id}'),
            childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
            tilePadding: EdgeInsets.zero,
            title: const LayoutText(
              'Chair layout',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            children: [
              for (final field in seating.record.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: LayoutNumberSliderControl(
                    key: ValueKey('chair-slider:${node.id}:${field.key}'),
                    controller: c,
                    node: node,
                    label: switch (field.key) {
                      'width' => 'Chair width',
                      'height' => 'Chair height',
                      'gap' => 'Chair gap',
                      'spacing' => 'Chair spacing',
                      _ => 'Edge padding',
                    },
                    value: (field.value as num).toDouble(),
                    min: const {'width', 'height'}.contains(field.key) ? 1 : 0,
                    max: 1000000000,
                    rangeMax: const {'width', 'height'}.contains(field.key)
                        ? 160
                        : 64,
                    onReset: () => c.apply(
                      configureTableSeating(
                        c.document,
                        node.id,
                        TableSeating.fromRecord({
                          ...TableSeating.fromDocument(c.document, node).record,
                          field.key: documentSeating(
                            c.document,
                          ).record[field.key],
                        }),
                        protectedSeatIds:
                            c.protectedSeatIds?.call() ?? const {},
                      ),
                      label: 'Reset chair layout',
                    ),
                    updateDocument: (document, value) => configureTableSeating(
                      document,
                      node.id,
                      TableSeating.fromRecord({
                        ...TableSeating.fromDocument(
                          document,
                          document.nodes.firstWhere((n) => n.id == node.id),
                        ).record,
                        field.key: value,
                      }),
                      protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _node(LayoutNode n) {
    return _canonicalNode(n);
  }

  Future<void> _backgroundSource() async {
    final assets = c.resources['assets'] as Map? ?? const {};
    if (assets.isEmpty) {
      setState(
        () => _error =
            'No background images loaded. Use your host image import first.',
      );
      return;
    }
    final ref = await showEditorDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const LayoutText('Choose background image'),
        children: [
          for (final key in assets.keys)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '$key'),
              child: LayoutText('$key'),
            ),
        ],
      ),
    );
    if (ref == null || !mounted) return;
    final asset = assets[ref] as Map;
    final before = c.document;
    var mode = 'Keep layout and canvas';
    VenueLayoutDocument candidate() {
      var draft = before;
      if (mode == 'Match image aspect ratio') {
        final ratio = (asset['width'] as num) / (asset['height'] as num);
        final width = (before.canvas['width'] as num).toDouble();
        final height = (before.canvas['height'] as num).toDouble();
        final targetWidth = width > height * ratio ? width : height * ratio;
        draft = resizeCanvas(before, targetWidth, targetWidth / ratio);
      }
      final b = backgroundPlacement(
        (asset['width'] as num).toDouble(),
        (asset['height'] as num).toDouble(),
        draft.canvas,
      );
      if (mode == 'Keep background registration' && before.background != null) {
        final old = before.background!;
        b.addAll({
          'x': old['x'],
          'y': old['y'],
          'rotation': old['rotation'],
          'scale':
              (old['scale'] as num? ?? 1) *
              (old['width'] as num? ?? asset['width']) /
              (asset['width'] as num),
        });
      }
      return draft.copyWith(
        background: {
          ...b,
          'assetRef': ref,
          if (asset['sha256'] != null) 'hash': asset['sha256'],
        },
      );
    }

    final apply = await showEditorDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const LayoutText('Replace background'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  isExpanded: true,
                  value: mode,
                  items: [
                    for (final value in [
                      'Keep layout and canvas',
                      'Keep background registration',
                      'Match image aspect ratio',
                    ])
                      DropdownMenuItem(value: value, child: LayoutText(value)),
                  ],
                  onChanged: (v) => update(() => mode = v!),
                ),
                const LayoutText(
                  'Image crop resets. Seats keep their positions. Matching the image ratio expands the canvas without clipping objects.',
                ),
                SizedBox(
                  height: 260,
                  child: VenueLayoutViewer(
                    key: ValueKey(mode),
                    document: candidate(),
                    resources: c.resources,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LayoutText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LayoutText('Use image'),
            ),
          ],
        ),
      ),
    );
    if (apply == true) {
      c.apply(candidate(), label: 'Replace background');
    }
  }

  Widget _backgroundControls() {
    final b = c.document.background;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onImportBackground != null)
          OutlinedButton.icon(
            onPressed: (c.readOnly || c.saving)
                ? null
                : () async {
                    try {
                      await widget.onImportBackground!();
                    } catch (e) {
                      if (mounted) setState(() => _error = '$e');
                    }
                  },
            icon: const Icon(Icons.upload_file_outlined),
            label: const LayoutText('Upload background image'),
          ),
        if ((c.resources['assets'] as Map? ?? const {}).isNotEmpty)
          OutlinedButton(
            onPressed: (c.readOnly || c.saving) ? null : _backgroundSource,
            child: LayoutText(b == null ? 'Choose image' : 'Replace image'),
          ),
        if (b != null) ...[
          Wrap(
            children: [
              for (final mode in ['contain', 'fill'])
                TextButton(
                  onPressed: (c.readOnly || c.saving)
                      ? null
                      : () => _run(
                          () => c.apply(
                            c.document.copyWith(
                              background: {
                                ...b,
                                ...backgroundPlacement(
                                  (b['width'] as num).toDouble(),
                                  (b['height'] as num).toDouble(),
                                  c.document.canvas,
                                  fit: mode,
                                ),
                              },
                            ),
                            label: 'Place background',
                          ),
                        ),
                  child: LayoutText(
                    mode == 'contain' ? 'Fit whole image' : 'Fill canvas',
                  ),
                ),
            ],
          ),
          for (final field in [
            'X',
            'Y',
            'Width',
            'Height',
            'Rotation',
            'Opacity',
          ])
            _number(
              field,
              switch (field) {
                'X' => b['x'] as num? ?? 0,
                'Y' => b['y'] as num? ?? 0,
                'Width' => (b['width'] as num) * (b['scale'] as num? ?? 1),
                'Height' => (b['height'] as num) * (b['scale'] as num? ?? 1),
                'Rotation' => b['rotation'] as num? ?? 0,
                _ => b['opacity'] as num? ?? 1,
              },
              (value) => c.apply(
                c.document.copyWith(
                  background: {
                    ...b,
                    if (field == 'X') 'x': value,
                    if (field == 'Y') 'y': value,
                    if (field == 'Width') 'scale': value / (b['width'] as num),
                    if (field == 'Height')
                      'scale': value / (b['height'] as num),
                    if (field == 'Rotation') 'rotation': value,
                    if (field == 'Opacity') 'opacity': value,
                  },
                ),
                label: 'Transform background',
              ),
            ),
          OutlinedButton(
            onPressed: (c.readOnly || c.saving)
                ? null
                : () {
                    final base = c.document;
                    final crop = b['crop'] as Map? ?? const {};
                    _preview(
                      'Crop image',
                      (v) => base.copyWith(
                        background: {
                          ...b,
                          'crop': {
                            'x': v['Left'],
                            'y': v['Top'],
                            'width': v['Width'],
                            'height': v['Height'],
                          },
                        },
                      ),
                      {
                        'Left': (crop['x'] as num? ?? 0).toDouble(),
                        'Top': (crop['y'] as num? ?? 0).toDouble(),
                        'Width': (crop['width'] as num? ?? 1).toDouble(),
                        'Height': (crop['height'] as num? ?? 1).toDouble(),
                      },
                      detail:
                          'Normalized image coordinates, from 0 to 1. Original pixels are retained.',
                    );
                  },
            child: const LayoutText('Crop image'),
          ),
          TextButton(
            onPressed: (c.readOnly || c.saving)
                ? null
                : () => c.apply(
                    c.document.copyWith(clearBackground: true),
                    label: 'Remove background',
                  ),
            child: const LayoutText('Remove image'),
          ),
        ],
      ],
    );
  }

  Widget _canvas() => ExpansionTile(
    minTileHeight: 44,
    key: ValueKey('canvas-${widget.canvasSelected}'),
    initiallyExpanded: widget.canvasSelected,
    tilePadding: EdgeInsets.zero,
    title: const LayoutText('Canvas'),
    children: [
      const SizedBox(height: 12),
      if (widget.canvasSelected) ...[
        _number(
          'Width',
          c.document.canvas['width'] as num,
          (value) => c.apply(
            resizeCanvas(
              c.document,
              value,
              (c.document.canvas['height'] as num).toDouble(),
            ),
            label: 'Canvas width',
          ),
        ),
        _number(
          'Height',
          c.document.canvas['height'] as num,
          (value) => c.apply(
            resizeCanvas(
              c.document,
              (c.document.canvas['width'] as num).toDouble(),
              value,
            ),
            label: 'Canvas height',
          ),
        ),
      ],
      if (!widget.canvasSelected)
        OutlinedButton(
          onPressed: (c.readOnly || c.saving)
              ? null
              : () {
                  final base = c.document;
                  _preview(
                    'Canvas size',
                    (v) => resizeCanvas(base, v['Width']!, v['Height']!),
                    {
                      'Width': (base.canvas['width'] as num).toDouble(),
                      'Height': (base.canvas['height'] as num).toDouble(),
                    },
                    detail:
                        'Objects keep their positions. A smaller canvas cannot hide seats.',
                  );
                },
          child: const LayoutText('Set canvas size'),
        ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LayoutText(
          'Objects stay in place. To move an object that fills the canvas, increase Width or Height first.',
        ),
      ),
      TextButton(
        onPressed: (c.readOnly || c.saving)
            ? null
            : () => _run(
                () => c.apply(
                  fitCanvas(c.document),
                  label: 'Fit canvas to content',
                ),
              ),
        child: const LayoutText('Fit canvas to content'),
      ),
      const SizedBox(height: 8),
      _canvasColor(),
      LayoutFloorStyleField(controller: c),
      const LayoutText('Schematic size. No physical measurements required.'),
      const SizedBox(height: 8),
      if (!widget.backgroundSelected) _backgroundControls(),
    ],
  );
  Widget _canvasColor() => _field(
    'Background #RRGGBBAA',
    '${c.document.canvas['fill'] ?? '#FFFFFFFF'}',
    (v) => c.apply(
      c.document.copyWith(canvas: {...c.document.canvas, 'fill': v}),
      label: 'Canvas color',
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!identical(_indexedDocument, c.document)) {
      _indexedDocument = c.document;
      _nodesById = {for (final node in c.document.nodes) node.id: node};
    }
    final selection = c.selection;
    final selected = c.document.nodes
        .where((n) => selection.contains(n.id))
        .toList();
    final ids = selected.map((node) => node.id).toList()..sort();
    final selectionContext =
        '${widget.canvasSelected}:${widget.backgroundSelected}:${ids.join(',')}';
    if (_selectionContext != selectionContext) {
      _selectionContext = selectionContext;
      _error = null;
      _search = '';
    }
    final layers = _layersExpanded ? _layers() : const <LayoutNode>[];

    Widget layerAction(
      String label,
      IconData icon, {
      int? direction,
      bool? toFront,
    }) => IconButton(
      tooltip: VenueLayoutStrings.text(context, label),
      icon: Icon(icon, size: 19),
      onPressed: c.readOnly || c.saving || selection.isEmpty
          ? null
          : () => _run(
              () => c.apply(
                direction == null
                    ? moveLayoutLayers(
                        c.document,
                        c.selection,
                        toFront: toFront!,
                      )
                    : reorderLayoutLayers(
                        c.document,
                        c.selection,
                        direction: direction,
                      ),
                label: label,
              ),
            ),
    );
    return Material(
      color: layoutPanelColor(context),
      child: SingleChildScrollView(
        key: ValueKey('inspector-context-$selectionContext'),
        primary: false,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: LayoutText(
                    selected.length == 1
                        ? (selected.single.label.isEmpty
                              ? _typeTitle(selected.single)
                              : selected.single.label)
                        : selected.length > 1
                        ? '${selected.length} objects selected. Individual values vary.'
                        : widget.backgroundSelected
                        ? 'Background image'
                        : widget.canvasSelected
                        ? 'Canvas'
                        : 'Properties',
                    key: const ValueKey('inspector-heading'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (selected.isNotEmpty ||
                    widget.canvasSelected ||
                    widget.backgroundSelected)
                  IconButton(
                    key: const ValueKey('clear-layout-selection'),
                    tooltip: VenueLayoutStrings.text(
                      context,
                      'Clear selection',
                    ),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onClearSelection ?? () => c.select({}),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  key: const ValueKey('layout-inspector-error'),
                  liveRegion: true,
                  child: LayoutText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (widget.backgroundSelected && c.document.background != null)
              _backgroundControls(),
            if (selected.isEmpty && !widget.backgroundSelected)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LayoutText(
                  widget.canvasSelected
                      ? 'Canvas selected. Drag an edge or corner to resize. Escape exits.'
                      : 'Select an object on the plan or in Layers to edit it.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (selected.length > 1 &&
                (widget.onCopyStyle != null || widget.onPasteStyle != null))
              Row(
                children: [
                  IconButton(
                    tooltip: VenueLayoutStrings.text(context, 'Copy style'),
                    onPressed: widget.onCopyStyle,
                    icon: const Icon(Icons.format_paint_outlined),
                  ),
                  IconButton(
                    tooltip: VenueLayoutStrings.text(context, 'Paste style'),
                    onPressed: c.readOnly || c.saving
                        ? null
                        : widget.onPasteStyle,
                    icon: const Icon(Icons.content_paste),
                  ),
                ],
              ),
            if (selected.length == 1)
              KeyedSubtree(
                key: ValueKey(selected.first.id),
                child: _node(selected.first),
              ),
            if (selected.length == 1 && widget.hostBuilder != null)
              widget.hostBuilder!(context, selected.single),
            if (selected.length > 1)
              ExpansionTile(
                minTileHeight: 44,
                tilePadding: EdgeInsets.zero,
                title: const LayoutText('Object appearance'),
                children: [
                  LayoutText(
                    'Style',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  LayoutStylePresets(controller: c),
                  const SizedBox(height: 12),
                  _field('Selected fill #RRGGBBAA', _nodeFill(selected.first), (
                    value,
                  ) {
                    final targets = <String>{};
                    for (final root in selected.where((n) => !n.locked)) {
                      targets.addAll(
                        root.kind == 'group'
                            ? layoutSubtree(c.document, {root.id})
                            : {root.id},
                      );
                    }
                    c.apply(
                      c.document.copyWith(
                        nodes: [
                          for (final n in c.document.nodes)
                            if (targets.contains(n.id) &&
                                !n.locked &&
                                n.kind != 'group')
                              n.copyWith(
                                style: patchCanonicalStyle(
                                  n.style,
                                  n.kind == 'text'
                                      ? ['label', 'color']
                                      : ['fill'],
                                  value: value,
                                ),
                              )
                            else
                              n,
                        ],
                      ),
                      label: 'Change selected colors',
                    );
                  }),
                ],
              ),
            if (selected.isNotEmpty) const Divider(height: 24),
            if (selected.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: (c.readOnly || c.saving)
                              ? null
                              : c.duplicateSelection,
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: const LayoutText('Duplicate'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 40),
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: (c.readOnly || c.saving)
                              ? null
                              : c.deleteSelection,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const LayoutText('Delete'),
                        ),
                      ),
                    ],
                  ),
                  if (selected.length > 1) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: (c.readOnly || c.saving)
                          ? null
                          : () => _run(
                              () => c.apply(
                                groupNodes(c.document, c.selection),
                                label: 'Group',
                              ),
                            ),
                      icon: const Icon(Icons.group_work_outlined, size: 16),
                      label: const LayoutText('Group'),
                    ),
                  ],
                  if (selected.any(
                    (node) =>
                        node.kind == 'group' &&
                        (node.assembly?['kind'] == null ||
                            node.assembly?['kind'] == 'rows'),
                  )) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: (c.readOnly || c.saving)
                          ? null
                          : () => _run(
                              () => c.apply(
                                ungroupNodes(c.document, c.selection),
                                label: 'Ungroup',
                              ),
                            ),
                      icon: const Icon(Icons.grid_view_outlined, size: 16),
                      label: LayoutText(
                        selected.any((n) => n.assembly?['kind'] == 'rows')
                            ? 'Split into seats'
                            : 'Ungroup',
                      ),
                    ),
                  ],
                ],
              ),
            if (selected.length > 1)
              ExpansionTile(
                minTileHeight: 44,
                tilePadding: EdgeInsets.zero,
                title: const LayoutText(
                  'Align and distribute',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in {
                        'left': 'Align left',
                        'centerX': 'Center horizontally',
                        'right': 'Align right',
                        'top': 'Align top',
                        'centerY': 'Center vertically',
                        'bottom': 'Align bottom',
                      }.entries)
                        IconButton(
                          tooltip: VenueLayoutStrings.text(
                            context,
                            entry.value,
                          ),
                          onPressed: (c.readOnly || c.saving)
                              ? null
                              : () => _run(
                                  () => c.apply(
                                    alignNodes(
                                      c.document,
                                      c.selection,
                                      entry.key,
                                    ),
                                    label: entry.value,
                                  ),
                                ),
                          icon: Icon(switch (entry.key) {
                            'left' => Icons.align_horizontal_left,
                            'centerX' => Icons.align_horizontal_center,
                            'right' => Icons.align_horizontal_right,
                            'top' => Icons.align_vertical_top,
                            'centerY' => Icons.align_vertical_center,
                            _ => Icons.align_vertical_bottom,
                          }),
                        ),
                      IconButton(
                        tooltip: VenueLayoutStrings.text(
                          context,
                          'Distribute horizontally',
                        ),
                        onPressed:
                            (c.readOnly || c.saving) || selected.length < 3
                            ? null
                            : () => _run(
                                () => c.apply(
                                  distributeNodes(
                                    c.document,
                                    c.selection,
                                    horizontal: true,
                                  ),
                                  label: 'Distribute horizontally',
                                ),
                              ),
                        icon: const Icon(Icons.horizontal_distribute),
                      ),
                      IconButton(
                        tooltip: VenueLayoutStrings.text(
                          context,
                          'Distribute vertically',
                        ),
                        onPressed:
                            (c.readOnly || c.saving) || selected.length < 3
                            ? null
                            : () => _run(
                                () => c.apply(
                                  distributeNodes(
                                    c.document,
                                    c.selection,
                                    horizontal: false,
                                  ),
                                  label: 'Distribute vertically',
                                ),
                              ),
                        icon: const Icon(Icons.vertical_distribute),
                      ),
                    ],
                  ),
                ],
              ),
            if (selected.isEmpty) const Divider(height: 16),
            if (selected.isEmpty) ...[
              OutlinedButton.icon(
                onPressed: c.readOnly || c.saving
                    ? null
                    : widget.onOpenGlobalStyle ??
                          () => showLayoutGlobalStyleDialog(
                            context,
                            c,
                            globalFontPickerBuilder:
                                widget.globalFontPickerBuilder,
                          ),
                icon: const Icon(Icons.palette_outlined),
                label: const LayoutText('Plan style'),
              ),
              const SizedBox(height: 12),
              _canvas(),
            ],
            ExpansionTile(
              minTileHeight: 44,
              title: const LayoutText('Layers'),
              initiallyExpanded: _layersExpanded,
              onExpansionChanged: (value) =>
                  setState(() => _layersExpanded = value),
              tilePadding: EdgeInsets.zero,
              children: [
                if (_layersExpanded) ...[
                  Row(
                    children: [
                      layerAction(
                        'Bring to front',
                        Icons.vertical_align_top,
                        toFront: true,
                      ),
                      layerAction(
                        'Bring forward',
                        Icons.arrow_upward,
                        direction: 1,
                      ),
                      layerAction(
                        'Send backward',
                        Icons.arrow_downward,
                        direction: -1,
                      ),
                      layerAction(
                        'Send to back',
                        Icons.vertical_align_bottom,
                        toFront: false,
                      ),
                    ],
                  ),
                  TextField(
                    decoration: InputDecoration(
                      labelText: VenueLayoutStrings.text(
                        context,
                        'Find object',
                      ),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  _rows(layers, selection),
                  if (c.document.background != null)
                    ListTile(
                      key: const ValueKey('layout-background-layer'),
                      selected: widget.backgroundSelected,
                      leading: const Icon(Icons.image_outlined),
                      title: const LayoutText('Background image'),
                      onTap: c.readOnly || c.saving
                          ? null
                          : widget.onSelectBackground,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertyField extends StatefulWidget {
  const _PropertyField({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.multiline,
    this.numeric = false,
    required this.onUndo,
    required this.onRedo,
    required this.save,
    this.usedColors,
    this.paletteImage,
  });
  final List<String> Function()? usedColors;
  final ui.Image? paletteImage;
  final String label, value;
  final bool enabled, multiline, numeric;
  final VoidCallback onUndo, onRedo;
  final ValueChanged<String> save;
  @override
  State<_PropertyField> createState() => _PropertyFieldState();
}

class _PropertyFieldState extends State<_PropertyField> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();
  String? _submittedThisFrame;
  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _text.text = widget.value;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus && widget.enabled && _text.text != widget.value) {
      if (_text.value.composing.isValid && !_text.value.composing.isCollapsed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_focus.hasFocus) _save();
        });
      } else {
        _save();
      }
    }
  }

  @override
  void didUpdateWidget(_PropertyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        (!_focus.hasFocus || _text.text == oldWidget.value)) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    if (!widget.enabled ||
        (_text.value.composing.isValid && !_text.value.composing.isCollapsed)) {
      return;
    }
    final value = _text.text;
    if (value == widget.value || value == _submittedThisFrame) return;
    // Blur and the suffix button can both submit before the model rebuilds.
    // Release next frame even after rejection so the same edit can be retried.
    _submittedThisFrame = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _submittedThisFrame == value) _submittedThisFrame = null;
    });
    widget.save(value);
  }

  Future<void> _chooseColor() async {
    EditorColorValue initial;
    try {
      initial = EditorColorValue.fromRgba(_text.text);
    } on FormatException {
      initial = EditorColorValue.fromRgba(widget.value);
    }
    final usedColors = widget.usedColors?.call() ?? const <String>[];
    final result = await showEditorDialog<EditorColorResult>(
      context: context,
      builder: (_) => EditorColorDialog(
        value: initial,
        usedColors: usedColors,
        image: widget.paletteImage,
        translate: (text) => VenueLayoutStrings.text(context, text),
      ),
    );
    if (result == null || !mounted) return;
    _text.text = result.primary.rgba;
    _save();
  }

  @override
  Widget build(BuildContext context) => EditorFieldHistory(
    hasUncommittedChanges: () => _text.text != widget.value,
    onUndo: widget.onUndo,
    onRedo: widget.onRedo,
    child: EditorNumberScroll(
      enabled: widget.enabled && widget.numeric,
      onChanged: _save,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        enabled: widget.enabled,
        keyboardType: widget.numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
        minLines: widget.multiline ? 2 : 1,
        maxLines: widget.multiline ? 6 : 1,
        decoration: InputDecoration(
          labelText: VenueLayoutStrings.text(context, widget.label),
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: widget.label.contains('#RRGGBBAA')
              ? IconButton(
                  tooltip: VenueLayoutStrings.text(context, 'Choose color'),
                  onPressed: widget.enabled ? _chooseColor : null,
                  icon: EditorColorSwatch(
                    value: EditorColorValue.fromRgba(widget.value),
                  ),
                )
              : null,
        ),
        onTapOutside: (_) {
          if (_text.value.composing.isValid) {
            _text.value = _text.value.copyWith(composing: TextRange.empty);
          }
          _save();
          _focus.unfocus();
        },
        onEditingComplete: _save,
        onSubmitted: (_) => _save(),
      ),
    ),
  );
}
