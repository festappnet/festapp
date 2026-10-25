import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/eshop.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import '../occasion_sale_strings.dart';
import 'blueprint_setup_layout_draft.dart';

class _PreviewSeatObject extends BlueprintObjectModel {
  _PreviewSeatObject(
      {super.id,
      super.title,
      super.spotProduct,
      super.product,
      BlueprintGroupModel? group}) {
    this.group = group;
  }
  @override
  String toString() => [group?.title, title]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(' · ');
}

class OccasionSetupSeatSelection {
  const OccasionSetupSeatSelection(this.seats, this.quantities);
  final List<BlueprintSeat> seats;
  final Map<String, int> quantities;
}

/// A private selection session over portable geometry. No real spot identity,
/// source occupancy or reservation capability enters this view.
class OccasionSetupSeatPreview extends StatefulWidget {
  const OccasionSetupSeatPreview(
      {super.key,
      required this.draft,
      required this.products,
      required this.maximum,
      required this.loadResources,
      this.selected = const [],
      this.quantities = const {}});
  final BlueprintSetupLayoutDraft draft;
  final List<ProductModel> products;
  final int maximum;
  final List<BlueprintSeat> selected;
  final Map<String, int> quantities;
  final Future<Map<String, dynamic>> Function() loadResources;
  @override
  State<OccasionSetupSeatPreview> createState() => _SeatPreviewState();
}

class _SeatPreviewState extends State<OccasionSetupSeatPreview> {
  late Future<Map<String, dynamic>> _resources = widget.loadResources();
  late final Map<String, int> _quantities = {...widget.quantities};
  late final _bindings = widget.draft.seatBindings.values.toList();
  late final Set<String> _selected = {
    for (var i = 0; i < _bindings.length; i++)
      if (widget.selected.any((s) => s.seat?.id == -(i + 1)))
        _bindings[i].nodeId,
  };
  ProductModel? _product(String id) {
    final binding = widget.draft.seatBindings[id];
    return widget.products.where((p) => p.id == binding?.productId).firstOrNull;
  }

  bool _available(String id) =>
      widget.draft.seatBindings[id]?.blocked == false &&
      _product(id)?.isHidden != true &&
      _product(id)?.price != null;
  String _group(String nodeId) {
    final groupId = widget.draft.seatBindings[nodeId]?.groupNodeId;
    return widget.draft.document.nodes
            .where((n) => n.id == groupId)
            .firstOrNull
            ?.label ??
        '';
  }

  List<BlueprintSeat> _result() => [
        for (var i = 0; i < _bindings.length; i++)
          if (_selected.contains(_bindings[i].nodeId))
            BlueprintSeat(
                position: SeatPosition(0, i),
                size: 0,
                seatId: -(i + 1),
                label: _bindings[i].title,
                seat: _PreviewSeatObject(
                    group:
                        BlueprintGroupModel(title: _group(_bindings[i].nodeId)),
                    id: -(i + 1),
                    title: _bindings[i].title,
                    spotProduct: _product(_bindings[i].nodeId)?.id,
                    product: _product(_bindings[i].nodeId)))
              ..isSelected = true,
      ];
  @override
  Widget build(BuildContext context) => AppDialog(
      child: SizedBox(
          width: 960,
          height: MediaQuery.sizeOf(context).height * .85,
          child: Column(children: [
            AppDialogHeader(
                title: Text(OccasionSaleStrings.text('customerPreview')),
                onClose: () => Navigator.of(context).pop()),
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(OccasionSaleStrings.text('previewSafe'))),
            Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                    future: _resources,
                    builder: (context, state) {
                      if (state.hasError)
                        return TextButton(
                            onPressed: () {
                              final request = widget.loadResources();
                              request.ignore();
                              setState(() {
                                _resources = request;
                              });
                            },
                            child: Text(CommonStrings.retry));
                      if (!state.hasData)
                        return const Center(child: CircularProgressIndicator());
                      return VenueLayoutPicker(
                          document: widget.draft.document,
                          resources: state.data!,
                          seatPresentation: {
                            for (final binding in _bindings)
                              binding.nodeId: {
                                'status': _available(binding.nodeId)
                                    ? 'available'
                                    : 'disabled',
                                'selectable': _available(binding.nodeId),
                                'selected': _selected.contains(binding.nodeId),
                                'label': [_group(binding.nodeId), binding.title]
                                    .where((s) => s.isNotEmpty)
                                    .join(' · '),
                                'tooltip':
                                    '${binding.title} · ${_product(binding.nodeId)?.title ?? ""}',
                              }
                          },
                          capacityPresentation: {
                            for (final area in widget.draft.areaBindings)
                              area['nodeId'] as String: {
                                'available': area['capacity'] ?? 0,
                                'quantity': _quantities[area['nodeId']] ?? 0,
                                'label': area['nodeId'],
                                'selectable': true
                              }
                          },
                          onQuantityRequested: (id, quantity) async {
                            final area = widget.draft.areaBindings
                                .where((a) => a['nodeId'] == id)
                                .first;
                            final total = _selected.length +
                                quantity +
                                _quantities.entries
                                    .where((e) => e.key != id)
                                    .fold<int>(0, (n, e) => n + e.value);
                            if (quantity < 0 ||
                                quantity > (area['capacity'] as int? ?? 0) ||
                                total > widget.maximum)
                              return const LayoutSelectionResult(
                                  accepted: false);
                            setState(() => _quantities[id] = quantity);
                            return const LayoutSelectionResult(accepted: true);
                          },
                          onSelectionRequested: (ids, selecting) async {
                            final next = {..._selected};
                            selecting ? next.addAll(ids) : next.removeAll(ids);
                            if (next.length +
                                        _quantities.values
                                            .fold<int>(0, (n, q) => n + q) >
                                    widget.maximum ||
                                ids.any((id) => !_available(id)))
                              return const LayoutSelectionResult(
                                  accepted: false);
                            setState(() {
                              _selected.clear();
                              _selected.addAll(next);
                            });
                            return LayoutSelectionResult(
                                accepted: true, authoritativeSeatIds: next);
                          });
                    })),
            Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                        OccasionSetupSeatSelection(
                            _result(), Map.unmodifiable(_quantities))),
                    child: Text(CommonStrings.continueAction))),
          ])));
}
