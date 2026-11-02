import '../order_detail_strings.dart';

import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../../blueprint/blueprint_layout_resources.dart';
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
  });
  final OrderDetailController controller;
  final int? ticketId;
  final ValueChanged<int?>? onTicket;
  final ValueChanged<Set<int>>? onMapTickets;
  @override
  State<OrderPlacesView> createState() => _OrderPlacesViewState();
}

class _OrderPlacesViewState extends State<OrderPlacesView> {
  final _resolver = BlueprintLayoutAssetResolver();
  int? _plan;
  int _request = 0, _focusRevision = 0;
  Map<String, dynamic>? _map, _resources;
  VenueLayoutDocument? _document;
  String? _error;
  bool _loading = false;
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
    if (_map != null &&
        (current == null ||
            _map!['placementFingerprint'] != current.placementFingerprint ||
            plan == null ||
            _map!['layout_revision'] != plan['layoutRevision'])) {
      _request++;
      _document = null;
      _resources = null;
      _map = null;
      _plan = null;
      _error = null;
      _scheduleSinglePlan();
    }
  }

  @override
  void dispose() {
    _request++;
    _resolver.dispose();
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
    // Selection highlights the place; keep the user's overview camera.
  }

  Future<void> _load(int id) async {
    if (widget.controller.busy || (_plan == id && _document != null)) return;
    final expectedFingerprint = widget.controller.detail?.placementFingerprint;
    final request = ++_request;
    setState(() {
      _plan = id;
      _loading = true;
      _error = null;
      _document = null;
      _map = null;
    });
    try {
      final map = await widget.controller.blueprint(id);
      final document = VenueLayoutDocument.fromJson(detailMap(map['layout']));
      final resources = await _resolver.resolve(detailMap(map['resources']));
      if (!mounted || request != _request || !widget.controller.validContext)
        return;
      setState(() {
        _map = map;
        _resources = resources;
        _document = document;
        _loading = false;
        _focusRevision++;
      });
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
                  label: Text('${plan['title']}'),
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
            child: Text(
              '${_map!['title']} · ${OrderDetailStrings.text('current_plan')}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          SizedBox(
            height: 300,
            child: VenueLayoutViewer(
              key: ValueKey(_plan),
              document: _document!,
              wheelZoomRequiresModifier: true,
              resources: _resources ?? {},
              highlightedNodeIds: own,
              activeNodeIds: active,
              // Never auto-zoom to an order or a selected ticket.
              focusNodeIds: const {},
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
                if (admissions.isNotEmpty)
                  widget.onMapTickets?.call(
                    admissions.values.map((p) => p['ticketId'] as int).toSet(),
                  );
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
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() {
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
                    onPressed: () => showPlace(place),
                    icon: Icon(Icons.location_searching),
                  )
                : null,
          ),
      ],
    );
  }
}
