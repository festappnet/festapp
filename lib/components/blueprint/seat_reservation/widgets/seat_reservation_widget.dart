import 'package:flutter/material.dart';
import '../../blueprint_layout_resources.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_adapter.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_contract.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

/// Public geometry is rendered by the package. Session holds remain server-owned.
class SeatReservationWidget extends StatefulWidget {
  static const int boxSize =
      15; // Legacy converter/prototype compatibility only.
  final int blueprintId;
  final String secret;
  final String formDataKey;
  final void Function(List<BlueprintSeat>)? onSelectionChanged;
  final void Function(List<BlueprintSeat>?)? onCloseSeatReservation;
  final void Function(String, DateTime?)? onSessionChanged;
  final List<BlueprintSeat> selectedSeats;
  final int? maxTickets;
  final bool demoSimulation;
  final Future<void> Function(BlueprintAreaBinding, int, int)?
      onQuantityRequested;
  final int Function(String)? selectedAreaQuantity;

  const SeatReservationWidget(
      {super.key,
      required this.blueprintId,
      required this.secret,
      required this.formDataKey,
      required this.selectedSeats,
      this.maxTickets,
      this.onSelectionChanged,
      this.onCloseSeatReservation,
      this.onSessionChanged,
      this.demoSimulation = false,
      this.onQuantityRequested,
      this.selectedAreaQuantity});
  @override
  State<SeatReservationWidget> createState() => _SeatReservationWidgetState();
}

class _SeatReservationWidgetState extends State<SeatReservationWidget> {
  final _assets = BlueprintLayoutAssetResolver();
  Map<String, dynamic> _resources = {};
  BlueprintModel? _blueprint;
  BlueprintLayoutSnapshot? _snapshot;
  BlueprintLayoutAdapter? _adapter;
  late String _secret;
  final Set<int> _selected = {};
  final Set<String> _pending = {};
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _secret = widget.secret;
    _selected
        .addAll(widget.selectedSeats.map((s) => s.seatId).whereType<int>());
    _load();
  }

  @override
  void didUpdateWidget(covariant SeatReservationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blueprintId != widget.blueprintId ||
        oldWidget.formDataKey != widget.formDataKey) {
      _generation++;
      _secret = widget.secret;
      _selected
        ..clear()
        ..addAll(widget.selectedSeats.map((s) => s.seatId).whereType<int>());
      _pending.clear();
      _snapshot = null;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _assets.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.demoSimulation) {
      setState(() {
        _loading = false;
        _error = FormStrings.demoNotice;
      });
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final blueprint = await DbForms.getBlueprint(
          _secret, widget.formDataKey, widget.blueprintId);
      if (!mounted || generation != _generation) return;
      if (blueprint?.layoutSnapshot == null) {
        setState(() {
          _loading = false;
          _error = BlueprintStrings.layoutUnavailable;
        });
        return;
      }
      final resources = await _assets.resolve(blueprint!.layoutResources);
      if (!mounted || generation != _generation) return;
      _resources = resources;
      _blueprint = blueprint;
      _snapshot = blueprint!.layoutSnapshot;
      _adapter = BlueprintLayoutAdapter(blueprint);
      _selected.clear();
      _selected.addAll(_snapshot!.seatBindings.values
          .where((b) => _adapter!.state(b) == BlueprintSeatState.selectedByMe)
          .map((b) => b.spotId)
          .whereType<int>());
      setState(() => _loading = false);
      widget.onSelectionChanged?.call(_selectedSeats);
    } catch (error, stack) {
      AppLogger.error('Blueprint picker loading failed: $error\n$stack');
      if (mounted && generation == _generation)
        setState(() {
          _loading = false;
          _error = error.toString();
        });
    }
  }

  List<BlueprintSeat> get _selectedSeats {
    final bindings = _snapshot?.seatBindings.values.toList() ??
        const <BlueprintSeatBinding>[];
    return [
      for (var index = 0; index < bindings.length; index++)
        if (_selected.contains(bindings[index].spotId))
          _slot(bindings[index], index)
    ];
  }

  BlueprintSeat _slot(BlueprintSeatBinding binding, int index) {
    // The form payload still consumes SeatSlot. Its position is only an opaque
    // compatibility key; it is never used to render or derive V2 geometry.
    final product = _adapter!.product(binding);
    final seat = BlueprintObjectModel(
        id: binding.spotId,
        title: binding.title,
        spotProduct: binding.productId,
        product: product,
        blueprint: _blueprint);
    return BlueprintSeat(
        position: SeatPosition(0, index),
        size: 0,
        seatId: binding.spotId,
        seat: seat,
        label: binding.title)
      ..isSelected = true;
  }

  Future<LayoutSelectionResult> _request(
      Set<String> ids, bool selecting) async {
    final snapshot = _snapshot!;
    final spots = ids
        .map((id) => snapshot.seatBindings[id]?.spotId)
        .whereType<int>()
        .toSet();
    if (spots.length != ids.length || ids.any(_pending.contains)) {
      return const LayoutSelectionResult(accepted: false);
    }
    if (selecting &&
        widget.maxTickets != null &&
        {..._selected, ...spots}.length > widget.maxTickets!) {
      return LayoutSelectionResult(
          accepted: false, message: BlueprintStrings.toastMaxTicketsReached);
    }
    final generation = _generation;
    setState(() => _pending.addAll(ids));
    try {
      // The existing server owner expands the clicked seat to its atomic unit.
      final result = await DbOrders.selectSpotResult(
          widget.formDataKey, _secret, spots.first, selecting);
      if (!mounted || generation != _generation)
        return const LayoutSelectionResult(accepted: false);
      _secret = result.secret;
      widget.onSessionChanged?.call(_secret, result.expiresAt);
      if (result.accepted) {
        selecting
            ? _selected.addAll(result.spotIds)
            : _selected.removeAll(result.spotIds);
        widget.onSelectionChanged?.call(_selectedSeats);
      }
      return LayoutSelectionResult(
          accepted: result.accepted, message: result.message);
    } catch (error) {
      return LayoutSelectionResult(accepted: false, message: error.toString());
    } finally {
      if (mounted && generation == _generation)
        setState(() => _pending.removeAll(ids));
    }
  }

  Map<String, dynamic> get _capacityPresentation => {
        for (final binding in _snapshot!.areaBindings.values)
          binding.nodeId: {
            'quantity': widget.selectedAreaQuantity?.call(binding.nodeId) ?? 0,
            'available':
                _blueprint!.areaAvailability[binding.nodeId]?['available'] ?? 0,
            'selectable': widget.onQuantityRequested != null &&
                _blueprint!.areaAvailability[binding.nodeId]?['reason'] ==
                    null &&
                _blueprint!.areaAvailability.containsKey(binding.nodeId),
            'label': _adapter!.products[binding.productId]?.title ?? '',
          },
      };

  Future<LayoutSelectionResult> _quantity(String id, int quantity) async {
    final binding = _snapshot!.areaBindings[id];
    if (binding == null ||
        widget.onQuantityRequested == null ||
        _pending.contains(id)) {
      return const LayoutSelectionResult(accepted: false);
    }
    final generation = _generation;
    setState(() => _pending.add(id));
    try {
      final available =
          (_blueprint!.areaAvailability[id]?['available'] as num?)?.toInt() ??
              0;
      await widget.onQuantityRequested!(binding, quantity, available);
      return LayoutSelectionResult(
          accepted: mounted && generation == _generation);
    } catch (error) {
      return LayoutSelectionResult(accepted: false, message: error.toString());
    } finally {
      if (mounted && generation == _generation)
        setState(() => _pending.remove(id));
    }
  }

  Map<String, dynamic> get _presentations => {
        for (final b in _snapshot!.seatBindings.values)
          b.nodeId: {
            ..._adapter!.publicPresentation(b),
            'selected': _selected.contains(b.spotId),
            'label': b.title,
            'tooltip': BlueprintObjectModel(
                    title: b.title, product: _adapter!.product(b))
                .blueprintTooltip(context),
          },
      };

  @override
  Widget build(BuildContext context) => SafeArea(
          child: Center(
              child: Container(
        width: double.infinity,
        child: Column(children: [
          Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                              Text(_error!),
                              TextButton(
                                  onPressed: _load,
                                  child: Text(CommonStrings.retry))
                            ]))
                      : TooltipTheme(
                          data: const TooltipThemeData(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.fromBorderSide(
                                    BorderSide(color: Colors.black, width: 2)),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(8))),
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            textStyle:
                                TextStyle(color: Colors.black, fontSize: 14),
                          ),
                          child: VenueLayoutPicker(
                              showSelectionControls: false,
                              document: _snapshot!.document,
                              resources: _resources,
                              seatPresentation: _presentations,
                              capacityPresentation: _capacityPresentation,
                              onQuantityRequested: _quantity,
                              onSelectionRequested: _request))),
          Padding(
              padding: const EdgeInsets.all(16),
              child: ButtonsHelper.primaryButton(
                  context: context,
                  onPressed: _loading || _error != null || _pending.isNotEmpty
                      ? null
                      : () {
                          if (!_loading && _error == null && _pending.isEmpty)
                            widget.onCloseSeatReservation?.call(_selectedSeats);
                        },
                  label: _pending.isNotEmpty
                      ? CommonStrings.loading
                      : CommonStrings.continueAction,
                  width: 250)),
        ]),
      )));
}
