import '../order_detail_strings.dart';

import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../../blueprint/blueprint_layout_resources.dart';
import '../../blueprint/blueprint_layout_adapter.dart';
import '../../_shared/common_strings.dart';
import '../models/order_admin_detail.dart';
import '../order_detail_controller.dart';

/// Read-only saved geometry. No checkout, editor or mutation endpoint is used.
class OrderPlacesView extends StatefulWidget {
  OrderPlacesView({
    super.key,
    required this.controller,
    this.ticketId,
    this.onTicket,
    this.onMapTickets,
    this.onOpenPlan,
  });
  final OrderDetailController controller;
  final int? ticketId;
  final ValueChanged<int?>? onTicket;
  final ValueChanged<Set<int>>? onMapTickets;
  final void Function(int blueprintId, Set<String> nodeIds)? onOpenPlan;
  @override
  State<OrderPlacesView> createState() => _OrderPlacesViewState();
}

class _OrderPlacesViewState extends State<OrderPlacesView>
    with SingleTickerProviderStateMixin {
  late final _highlightPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    value: 1,
  );

  void _locateSeats() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _highlightPulse.value = 1;
    } else {
      _highlightPulse.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _highlightPulse.value = 1;
  }

  final _resolver = BlueprintLayoutAssetResolver();
  int? _plan;
  int _request = 0, _focusRevision = 0;
  Map<String, dynamic>? _map, _resources;
  Map<String, dynamic> _seatPresentation = const {};
  VenueLayoutDocument? _document;
  String? _error;
  bool _loading = false;
  bool _wholePlan = false;
  List<Map<String, dynamic>> get places =>
      widget.controller.detail?.places ?? [];
  @override
  void initState() {
    super.initState();
    _scheduleSinglePlan();
  }

  void _scheduleSinglePlan() {
    final plans = widget.controller.detail?.plans ?? [];
    if (widget.controller.busy || _plan != null || plans.length != 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _plan == null) _load(plans.single['id'] as int);
    });
  }

  @override
  void didUpdateWidget(covariant OrderPlacesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSinglePlan();
    final current = widget.controller.detail;
    final plan = current?.plans.where((p) => p['id'] == _plan).firstOrNull;
    if (!identical(oldWidget.controller, widget.controller) ||
        (_map != null &&
            (current == null ||
                _map!['placementFingerprint'] != current.placementFingerprint ||
                plan == null ||
                _map!['layout_revision'] != plan['layoutRevision']))) {
      _request++;
      _document = null;
      _resources = null;
      _map = null;
      _plan = null;
      _error = null;
      _loading = false;
      _scheduleSinglePlan();
    }
  }

  @override
  void dispose() {
    _request++;
    _resolver.dispose();
    _highlightPulse.dispose();
    super.dispose();
  }

  Future<void> showPlace(Map<String, dynamic> place) async {
    if (place['active'] != true || place['blueprintId'] == null) return;
    final ticketId = place['ticketId'] as int?;
    if (ticketId != null) widget.onMapTickets?.call({ticketId});
    widget.onTicket?.call(ticketId);
    final plan = place['blueprintId'] as int;
    await _load(plan);
    if (!mounted || _plan != plan) return;
    if (_document != null) _locateSeats();
    // Selection highlights the place; keep the user's overview camera.
  }

  Future<void> _load(int id) async {
    if (widget.controller.busy ||
        (_plan == id && (_document != null || _loading))) {
      return;
    }
    final owner = widget.controller;
    final expectedFingerprint = owner.detail?.placementFingerprint;
    final request = ++_request;
    setState(() {
      _plan = id;
      _wholePlan = false;
      _loading = true;
      _error = null;
      _document = null;
      _map = null;
    });
    try {
      final view = await owner.blueprint(id);
      final map = view.data;
      final document = view.plan.document;
      if (map['seatStates'] is! List) {
        throw const FormatException('Plan occupancy unavailable');
      }
      final seatPresentation = <String, dynamic>{
        for (final facts in detailRows(map['seatStates']))
          facts['nodeId'] as String:
              BlueprintLayoutAdapter.readonlySeatPresentation(facts),
      };
      final resources = await _resolver.resolve(view.plan.resources);
      if (!mounted ||
          request != _request ||
          !identical(owner, widget.controller) ||
          !owner.validContext)
        return;
      setState(() {
        _map = map;
        _resources = resources;
        _seatPresentation = seatPresentation;
        _document = document;
        _loading = false;
        _focusRevision++;
      });
      _locateSeats();
    } catch (_) {
      if (mounted && request == _request) {
        final changed =
            widget.controller.busy ||
            widget.controller.detail?.placementFingerprint !=
                expectedFingerprint;
        setState(() {
          _loading = false;
          if (changed) {
            _plan = null;
            _error = null;
          } else {
            _error = OrderDetailStrings.text(
              'planek_se_nepodarilo_nacist_nebo_se_zmenilo_prirazeni_seznam_mist_zustava_dostupny',
            );
          }
        });
        if (changed) _scheduleSinglePlan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = widget.controller.detail?.plans ?? [];
    final own = {
      for (final p in places)
        if (p['blueprintId'] == _plan && p['active'] == true)
          p['nodeId'] as String,
    };
    final active = {
      for (final p in places)
        if (p['blueprintId'] == _plan &&
            p['active'] == true &&
            p['ticketId'] == widget.ticketId)
          p['nodeId'] as String,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plans.length > 1)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final plan in plans)
                OutlinedButton.icon(
                  onPressed: () => _load(plan['id'] as int),
                  icon: Icon(Icons.map_outlined),
                  label: Text(
                    plan['title'] is String &&
                            (plan['title'] as String).trim().isNotEmpty
                        ? plan['title'] as String
                        : '${CommonStrings.blueprint} #${plan['id']}',
                  ),
                ),
            ],
          ),
        if (_loading)
          Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: () => _load(_plan!),
            child: Text(OrderDetailStrings.text('obnovit_planek')),
          ),
        ],
        if (_document != null) ...[
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (_map!['title'] is String &&
                          (_map!['title'] as String).trim().isNotEmpty)
                        (_map!['title'] as String).trim(),
                      OrderDetailStrings.text('current_plan'),
                    ].join(' · '),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: OrderDetailStrings.text('open_order_plan'),
                  onPressed: widget.onOpenPlan == null || own.isEmpty
                      ? null
                      : () => widget.onOpenPlan!(_plan!, own),
                  icon: const Icon(Icons.open_in_new, size: 18),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return VenueLayoutViewer(
                  key: ValueKey(_plan),
                  document: _document!,
                  wheelZoomRequiresModifier: true,
                  resources: _resources ?? {},
                  seatPresentation: _seatPresentation,
                  highlightedNodeIds: own,
                  highlightPulse: _highlightPulse,
                  activeNodeIds: active,
                  // The shared camera targets readable seats while retaining their context.
                  // Ticket selection does not reframe the user's camera.
                  focusNodeIds: !_wholePlan ? own : const {},
                  focusMaxZoomFactor: 2.6,
                  focusSeatPixelSize: 12,
                  focusRevision: _focusRevision,
                  onNodeTap: (node) {
                    final found = places
                        .where(
                          (p) =>
                              p['blueprintId'] == _plan &&
                              p['active'] == true &&
                              p['nodeId'] == node,
                        )
                        .toList();
                    final admissions = {
                      for (final p in found) p['admissionItemId']: p,
                    };
                    if (admissions.isNotEmpty) {
                      _locateSeats();
                      widget.onMapTickets?.call(
                        admissions.values
                            .map((p) => p['ticketId'] as int)
                            .toSet(),
                      );
                    }
                    if (admissions.length == 1)
                      widget.onTicket?.call(
                        admissions.values.single['ticketId'] as int,
                      );
                    else if (admissions.length > 1) {
                      widget.onTicket?.call(null);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            OrderDetailStrings.count(
                              'standing_count',
                              admissions.length,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _wholePlan = true;
                  _focusRevision++;
                }),
                child: Text(OrderDetailStrings.text('cely_sal')),
              ),
            ],
          ),
          Text(
            OrderDetailStrings.text(
              'mista_teto_objednavky_prave_zobrazene_misto_obrys_ostatni_mista',
            ),
          ),
        ],
        for (final place in places)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: place['ticketId'] == widget.ticketId,
            onTap: place['active'] == true ? () => showPlace(place) : null,
            leading: Icon(
              place['standing'] == true
                  ? Icons.accessibility_new
                  : Icons.event_seat_outlined,
            ),
            title: Text(
              [
                if (place['standing'] == true) OrderDetailStrings.text('stani'),
                place['groupTitle'],
                place['title'],
              ].whereType<String>().join(' · '),
            ),
            subtitle: place['problem'] == null
                ? null
                : Text(OrderDetailStrings.text('assignment_problem')),
            trailing: place['active'] == true
                ? IconButton(
                    tooltip: OrderDetailStrings.text('ukazat_misto'),
                    onPressed:
                        place['nodeId'] is String &&
                            place['blueprintId'] is int &&
                            widget.onOpenPlan != null
                        ? () => widget.onOpenPlan!(
                            place['blueprintId'] as int,
                            {place['nodeId'] as String},
                          )
                        : null,
                    icon: Icon(Icons.location_searching),
                  )
                : null,
          ),
      ],
    );
  }
}
