import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'layout_scene_surface.dart';

/// Customer selection with atomic selection units and asynchronous rollback.
///
/// Replacing the immutable [document] starts a fresh selection session. Retain
/// its instance when updating only live presentation, resources or callbacks.
class VenueLayoutPicker extends StatefulWidget {
  const VenueLayoutPicker({
    super.key,
    required this.document,
    this.resources = const {},
    this.seatPresentation = const {},
    this.capacityPresentation = const {},
    required this.onSelectionRequested,
    this.onQuantityRequested,
    this.showSelectionControls = true,
  });
  final VenueLayoutDocument document;

  /// Hosts with existing chrome can retain map semantics without an extra footer.
  final bool showSelectionControls;
  final Map<String, dynamic> resources, seatPresentation, capacityPresentation;
  final Future<LayoutSelectionResult> Function(
    Set<String> nodeIds,
    bool selecting,
  )
  onSelectionRequested;
  final Future<LayoutSelectionResult> Function(String, int)?
  onQuantityRequested;
  @override
  State<VenueLayoutPicker> createState() => _VenueLayoutPickerState();
}

class _VenueLayoutPickerState extends State<VenueLayoutPicker> {
  final Set<String> _selected = {}, _pending = {};
  final Map<String, int> _quantities = {};
  String? _message;
  int _generation = 0;
  double _viewportScale = 1;
  Route<dynamic>? _quantityRoute, _listRoute;

  bool _current(int generation) => mounted && generation == _generation;

  void _dismiss(Route<dynamic>? route) {
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  void _syncSelected() {
    for (final entry in widget.capacityPresentation.entries) {
      if (_pending.contains(entry.key) || entry.value is! Map) continue;
      final quantity = (entry.value as Map)['quantity'];
      if (quantity is num &&
          quantity.isFinite &&
          quantity >= 0 &&
          (quantity > 0 || _quantities.containsKey(entry.key)) &&
          quantity == quantity.roundToDouble()) {
        _quantities[entry.key] = quantity.toInt();
      }
    }
    for (final entry in widget.seatPresentation.entries) {
      if (_pending.contains(entry.key) || entry.value is! Map) continue;
      final selected = (entry.value as Map)['selected'];
      if (selected == true) _selected.add(entry.key);
      if (selected == false) _selected.remove(entry.key);
    }
  }

  @override
  void initState() {
    super.initState();
    _syncSelected();
  }

  @override
  void didUpdateWidget(covariant VenueLayoutPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.document, widget.document)) {
      if (!identical(oldWidget.seatPresentation, widget.seatPresentation) ||
          !identical(
            oldWidget.capacityPresentation,
            widget.capacityPresentation,
          )) {
        _syncSelected();
      }
      return;
    }
    _generation++;
    _selected.clear();
    _pending.clear();
    _quantities.clear();
    _message = null;
    _dismiss(_quantityRoute);
    _dismiss(_listRoute);
    _syncSelected();
  }

  @override
  void dispose() {
    _generation++;
    _dismiss(_quantityRoute);
    _dismiss(_listRoute);
    super.dispose();
  }

  bool _unavailable(Map presentation) =>
      const [
        'occupied',
        'unavailable',
        'disabled',
        'reserved',
        'blocked',
        'sold',
      ].contains(presentation['status']) ||
      presentation['selectable'] == false;

  Map _presentation(String id) => widget.seatPresentation[id] is Map
      ? widget.seatPresentation[id] as Map
      : const {};
  String _label(LayoutNode n) =>
      '${_presentation(n.id)['accessibilityLabel'] ?? _presentation(n.id)['label'] ?? (n.label.isEmpty ? n.kind : n.label)}';
  Future<void> _choose(String id) async {
    final candidates = widget.document.nodes.where((n) => n.id == id);
    if (candidates.isEmpty) return;
    final node = candidates.first;
    if (node.kind == 'capacityArea') {
      await _quantity(node);
      return;
    }
    if (node.kind != 'seat') return;
    final ids = <String>{id};
    for (final unit in widget.document.selectionUnits) {
      final members = (unit['nodeIds'] as List? ?? const []).cast<String>();
      if (members.contains(id)) ids.addAll(members);
    }
    if (ids.any(_pending.contains)) return;
    if (ids.any((id) => _unavailable(_presentation(id)))) {
      setState(() => _message = 'This seat or its paired seat is unavailable.');
      return;
    }
    final generation = _generation;
    final callback = widget.onSelectionRequested;
    final selecting = !ids.every(_selected.contains);
    final before = Set<String>.of(_selected);
    setState(() {
      _pending.addAll(ids);
      selecting ? _selected.addAll(ids) : _selected.removeAll(ids);
      _message = null;
    });
    try {
      final result = await callback(ids, selecting);
      if (!_current(generation)) return;
      setState(() {
        if (result.authoritativeSeatIds != null) {
          _selected.removeAll(ids);
          _selected.addAll(result.authoritativeSeatIds!.intersection(ids));
        } else if (!result.accepted) {
          _selected.removeAll(ids);
          _selected.addAll(before.intersection(ids));
        }
        _message =
            result.message ??
            (result.accepted
                ? '${ids.length} seat${ids.length == 1 ? '' : 's'} ${selecting ? 'selected' : 'released'}.'
                : 'Selection was not accepted. Please try again.');
      });
    } catch (_) {
      if (!_current(generation)) return;
      setState(() {
        _selected.removeAll(ids);
        _selected.addAll(before.intersection(ids));
        _message = 'Could not confirm selection. Please try again.';
      });
    } finally {
      if (_current(generation)) setState(() => _pending.removeAll(ids));
    }
  }

  Future<void> _quantity(LayoutNode node) async {
    if (widget.onQuantityRequested == null || _pending.contains(node.id)) {
      return;
    }
    final generation = _generation;
    final callback = widget.onQuantityRequested!;
    final p = widget.capacityPresentation[node.id] as Map? ?? const {};
    if ((_unavailable(p) || (p['available'] as num? ?? node.properties['capacity'] as num? ?? 0) <= 0) && (_quantities[node.id] ?? 0) == 0) {
      setState(() => _message = 'Standing places are unavailable.');
      return;
    }
    final maximum =
        (p['available'] as num? ?? node.properties['capacity'] as num? ?? 0)
            .toInt();
    var value = (_quantities[node.id] ?? 1).clamp(0, maximum < 0 ? 0 : maximum);
    final route = DialogRoute<int>(
      context: context,
      themes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: LayoutText(_label(node)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutText('$maximum available'),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: VenueLayoutStrings.text(context, 'Remove one'),
                    onPressed: value > 0 ? () => update(() => value--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  LayoutText('$value'),
                  IconButton(
                    tooltip: VenueLayoutStrings.text(context, 'Add one'),
                    onPressed: value < maximum
                        ? () => update(() => value++)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const LayoutText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, value),
              child: const LayoutText('Confirm quantity'),
            ),
          ],
        ),
      ),
    );
    _quantityRoute = route;
    final requested = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    if (identical(_quantityRoute, route)) _quantityRoute = null;
    if (requested == null || !_current(generation)) return;
    final current = widget.capacityPresentation[node.id] as Map? ?? const {};
    final available =
        (current['available'] as num? ??
                node.properties['capacity'] as num? ??
                0)
            .toInt();
    if ((requested > 0 && _unavailable(current)) || requested > available) {
      setState(() => _message = 'Standing places are unavailable.');
      return;
    }
    setState(() {
      _pending.add(node.id);
      _message = null;
    });
    try {
      final result = await callback(node.id, requested);
      if (!_current(generation)) return;
      setState(() {
        if (result.accepted) _quantities[node.id] = requested;
        _message =
            result.message ??
            (result.accepted
                ? 'Quantity updated.'
                : 'Quantity was not accepted.');
      });
    } catch (_) {
      if (_current(generation)) {
        setState(
          () => _message =
              'Could not update quantity. Previous quantity retained.',
        );
      }
    } finally {
      if (_current(generation)) setState(() => _pending.remove(node.id));
    }
  }

  void _list() {
    final generation = _generation;
    final nodes = widget.document.nodes
        .where((n) => n.kind == 'seat' || n.kind == 'capacityArea')
        .toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final route = ModalRoute.of(context);
        _listRoute = route;
        if (!_current(generation)) _dismiss(route);
        return DraggableScrollableSheet(
          expand: false,
          builder: (context, scroll) => ListView.builder(
            controller: scroll,
            itemCount: nodes.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const ListTile(
                  title: LayoutText('Choose seats or standing places'),
                );
              }
              final n = nodes[index - 1];
              return ListTile(
                title: LayoutText(_label(n)),
                subtitle: LayoutText(
                  '${_presentation(n.id)['status'] ?? 'Available'}',
                ),
                trailing: Icon(
                  _selected.contains(n.id)
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (_current(generation)) _choose(n.id);
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    customSemanticsActions: widget.showSelectionControls
        ? null
        : {
            CustomSemanticsAction(
              label: VenueLayoutStrings.text(context, 'Accessible seat list'),
            ): _list,
          },
    child: Column(
      children: [
        Expanded(
          child: LayoutSceneSurface(
            document: widget.document,
            compactZoomControls: !widget.showSelectionControls,
            resources: widget.resources,
            presentation: {
              ...widget.seatPresentation,
              for (final entry in widget.capacityPresentation.entries)
                if (entry.value is Map)
                  entry.key: {
                    ...Map<String, dynamic>.from(entry.value),
                    'capacity':
                        entry.value['available'] ?? entry.value['capacity'],
                  },
              for (final id in {
                ...widget.seatPresentation.keys,
                ..._selected,
                ..._pending,
              })
                id: {
                  ..._presentation(id),
                  'selected': _selected.contains(id),
                  'pending': _pending.contains(id),
                },
            },
            onViewportScaleChanged: (scale) => _viewportScale = scale,
            onTap: (p) {
              final id = spatialIndexFor(widget.document).resolveTap(
                p.dx,
                p.dy,
                tolerance: 8 / _viewportScale,
                classify: (node) {
                  if (node.kind == 'seat') {
                    return _pending.contains(node.id) ||
                            _unavailable(_presentation(node.id))
                        ? LayoutTapDisposition.block
                        : LayoutTapDisposition.activate;
                  }
                  if (node.kind == 'capacityArea' &&
                      widget.onQuantityRequested != null) {
                    final presentation =
                        widget.capacityPresentation[node.id] as Map? ??
                        const {};
                    return _pending.contains(node.id) ||
                            _unavailable(presentation)
                        ? LayoutTapDisposition.block
                        : LayoutTapDisposition.activate;
                  }
                  return LayoutTapDisposition.ignore;
                },
              );
              if (id != null) _choose(id);
            },
          ),
        ),
        if (widget.showSelectionControls && _pending.isNotEmpty)
          LinearProgressIndicator(
            semanticsLabel: VenueLayoutStrings.text(
              context,
              'Confirming selection',
            ),
          ),
        if (_message != null && !widget.showSelectionControls)
          Semantics(
            liveRegion: true,
            label: VenueLayoutStrings.text(context, _message!),
            child: const SizedBox.shrink(),
          ),
        if (_message != null && widget.showSelectionControls)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Semantics(liveRegion: true, child: LayoutText(_message!)),
          ),
        if (widget.showSelectionControls)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  LayoutText('${_selected.length} seats selected'),
                  OutlinedButton.icon(
                    onPressed: _list,
                    icon: const Icon(Icons.list),
                    label: const LayoutText('Accessible seat list'),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
