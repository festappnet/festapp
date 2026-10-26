import 'dart:convert';

import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../../blueprint/blueprint_layout_contract.dart';
import '../../blueprint/blueprint_group_binding.dart';

/// Private setup configuration. Product IDs are provisional form references;
/// physical spot IDs, reservations and catalog prices never enter this draft.
class BlueprintSetupLayoutDraft {
  BlueprintSetupLayoutDraft._(
    this.document,
    this.resources,
    Map<String, BlueprintSeatBinding> seats,
    Map<String, int> groups,
    List<Map<String, dynamic>> areas,
  ) : seatBindings = Map.unmodifiable(seats),
      groupProducts = Map.unmodifiable(groups),
      areaBindings = List.unmodifiable(
        areas.map(Map<String, dynamic>.unmodifiable),
      );
  factory BlueprintSetupLayoutDraft.empty({
    required VenueLayoutDocument document,
    required Map<String, dynamic> resources,
  }) => BlueprintSetupLayoutDraft._(
    document,
    Map.unmodifiable(resources),
    {},
    {},
    [],
  );
  factory BlueprintSetupLayoutDraft.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic> resources = const {},
  }) {
    final portable = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(json)) as Map,
    );
    return BlueprintSetupLayoutDraft._(
      VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(portable['layout'] as Map),
      ),
      Map.unmodifiable(resources),
      {
        for (final raw in portable['seatBindings'] as List? ?? const [])
          (raw as Map)['nodeId'] as String: BlueprintSeatBinding.fromJson(
            Map<String, dynamic>.from(raw)..remove('spotId'),
          ),
      },
      {
        for (final raw in portable['groupProducts'] as List? ?? const [])
          if ((raw as Map)['productId'] != null)
            raw['groupNodeId'] as String: (raw['productId'] as num).toInt(),
      },
      [
        for (final raw in portable['areaBindings'] as List? ?? const [])
          Map<String, dynamic>.from(raw as Map),
      ],
    );
  }
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources;
  final Map<String, BlueprintSeatBinding> seatBindings;
  final Map<String, int> groupProducts;
  final List<Map<String, dynamic>> areaBindings;
  Map<String, dynamic> toJson() => {
    'layout': document.toJson(),
    'seatBindings': [
      for (final seat in seatBindings.values)
        Map<String, dynamic>.from(seat.toJson())..remove('spotId'),
    ],
    'groupProducts': [
      for (final group in groupProducts.entries)
        {'groupNodeId': group.key, 'productId': group.value},
    ],
    'areaBindings': areaBindings,
  };
  BlueprintSetupLayoutDraft reconcile(
    VenueLayoutDocument next, {
    required int? defaultProductId,
  }) {
    final nodes = {for (final node in next.nodes) node.id: node};
    final previousNodes = {for (final node in document.nodes) node.id: node};
    final groups = {...groupProducts};
    final seats = <String, BlueprintSeatBinding>{};
    for (final node in next.nodes.where((node) => node.kind == 'seat')) {
      final previous = seatBindings[node.id];
      final parentChanged = previousNodes[node.id]?.parentId != node.parentId;
      final group = previous == null || parentChanged
          ? blueprintCommercialGroupFor(
              node,
              next,
              groupProducts: groups,
              currentGroupId: previous?.groupNodeId,
            )
          : previous.groupNodeId;
      final groupChanged = parentChanged && group != previous?.groupNodeId;
      final unit = next.selectionUnits.where(
        (unit) => (unit['nodeIds'] as List? ?? const []).contains(node.id),
      );
      final previousGroupProducts = seatBindings.values
          .where((binding) => binding.groupNodeId == group)
          .map((binding) => binding.productId)
          .toSet();
      final unknownGroupDefault =
          group != null &&
          !groups.containsKey(group) &&
          (previousGroupProducts.length > 1 ||
              previousGroupProducts.contains(null));
      if (previous == null &&
          group != null &&
          !groups.containsKey(group) &&
          !unknownGroupDefault &&
          defaultProductId != null) {
        groups[group] = defaultProductId;
      }
      seats[node.id] = BlueprintSeatBinding(
        nodeId: node.id,
        productId: previous != null && !groupChanged
            ? previous.productId
            : unknownGroupDefault
            ? null
            : groups[group] ?? defaultProductId,
        title: node.label.isEmpty ? previous?.title ?? '' : node.label,
        groupNodeId: group,
        selectionUnitId: unit.isEmpty ? null : unit.first['id'] as String,
        blocked: previous?.blocked ?? false,
      );
    }
    return BlueprintSetupLayoutDraft._(
      next,
      resources,
      seats,
      {
        for (final group in groups.entries)
          if (nodes.containsKey(group.key)) group.key: group.value,
      },
      [
        for (final area in areaBindings)
          if (nodes[area['nodeId']]?.kind == 'capacityArea') area,
      ],
    );
  }

  /// An explicit group choice fills empty draft seats while retaining overrides.
  BlueprintSetupLayoutDraft withGroupProduct(
    String groupNodeId,
    int productId, {
    bool assignUnassigned = true,
    Set<String>? assignNodeIds,
  }) {
    if (!document.nodes.any(
      (node) =>
          node.id == groupNodeId &&
          const {'table', 'group', 'furniture'}.contains(node.kind),
    )) {
      throw StateError('invalid_group_draft');
    }
    return BlueprintSetupLayoutDraft._(
      document,
      resources,
      {
        for (final binding in seatBindings.values)
          binding.nodeId:
              assignUnassigned &&
                  binding.groupNodeId == groupNodeId &&
                  binding.productId == null &&
                  (assignNodeIds == null ||
                      assignNodeIds.contains(binding.nodeId))
              ? binding.copyWith(productId: productId)
              : binding,
      },
      {...groupProducts, groupNodeId: productId},
      areaBindings,
    );
  }

  BlueprintSetupLayoutDraft withArea({
    required String nodeId,
    required int productId,
    required int capacity,
  }) {
    if (capacity < 0 ||
        !document.nodes.any(
          (node) => node.id == nodeId && node.kind == 'capacityArea',
        )) {
      throw StateError('invalid_area_draft');
    }
    return BlueprintSetupLayoutDraft._(
      document,
      resources,
      seatBindings,
      groupProducts,
      [
        ...areaBindings.where((area) => area['nodeId'] != nodeId),
        {'nodeId': nodeId, 'productId': productId, 'capacity': capacity},
      ],
    );
  }
}

/// Persistent mode identity and active geometry are one setup contract.
enum SetupBlueprintMode { none, create, copy }

class SetupBlueprintConfiguration {
  SetupBlueprintConfiguration(this.data);
  final Map<String, dynamic> data;
  SetupBlueprintMode get mode => switch (data['blueprintMode']) {
    'new' || 'Nový' => SetupBlueprintMode.create,
    'copy' || 'Převzít' => SetupBlueprintMode.copy,
    null when data['blueprintLayoutDraft'] is Map => SetupBlueprintMode.copy,
    _ => SetupBlueprintMode.none,
  };
  String get modeId => switch (mode) {
    SetupBlueprintMode.none => 'none',
    SetupBlueprintMode.create => 'new',
    SetupBlueprintMode.copy => 'copy',
  };
  String get label => switch (mode) {
    SetupBlueprintMode.none => 'Bez plánku',
    SetupBlueprintMode.create => 'Nový',
    SetupBlueprintMode.copy => 'Převzít',
  };
  bool get active => mode != SetupBlueprintMode.none;
  Map? get _layout => data['blueprintLayoutDraft'] as Map?;
  Set<String> nodes(String kind) => {
    for (final node
        in ((_layout?['layout'] as Map?)?['nodes'] as List? ?? [])
            .whereType<Map>())
      if (node['kind'] == kind && node['id'] is String) node['id'] as String,
  };
  Iterable<Map> get seats => (_layout?['seatBindings'] as List? ?? [])
      .whereType<Map>()
      .where((s) => nodes('seat').contains(s['nodeId']));
  Iterable<Map> get areas => (_layout?['areaBindings'] as List? ?? [])
      .whereType<Map>()
      .where((s) => nodes('capacityArea').contains(s['nodeId']));
  int get seatCount =>
      seats.where((s) => s['blocked'] != true && s['productId'] is num).length;
  int get areaCount => areas
      .where(
        (s) =>
            s['productId'] is num &&
            (s['inventoryContextId'] is num ||
                (s['capacity'] is num && s['capacity'] > 0)),
      )
      .length;
  Set<num> get products => {
    for (final field
        in ((data['formDraft'] as Map?)?['fields'] as List? ?? [])
            .whereType<Map>())
      if ((field['product_type_data'] ?? field['product_type']) is Map)
        for (final type in [
          field['product_type_data'] ?? field['product_type'],
        ])
          if (type['type'] == 'spot')
            for (final product
                in (type['products'] as List? ?? []).whereType<Map>())
              if (product['id'] is num) product['id'] as num,
  };
  bool get ready {
    if (!active) return true;
    if (data['formEnabled'] == false ||
        _layout == null ||
        seatCount + areaCount == 0)
      return false;
    try {
      BlueprintSetupLayoutDraft.fromJson(Map<String, dynamic>.from(_layout!));
    } catch (_) {
      return false;
    }
    final ids = products;
    return seats.every((s) => ids.contains(s['productId'])) &&
        areas.every((s) => ids.contains(s['productId']));
  }

  void clear({bool create = false}) {
    data['blueprintMode'] = create ? 'new' : 'none';
    data.remove('blueprintLayoutDraft');
    data.remove('blueprintSourceId');
    for (final key in [
      'blueprintObjects',
      'blueprintGroups',
      'blueprintBackground',
    ]) {
      data.remove(key);
    }
    normalize();
  }

  static Map<String, dynamic> adaptSource(
    Map plan, {
    required Map<String, Map<String, dynamic>> fontFamilies,
  }) {
    final copy = Map<String, dynamic>.from(jsonDecode(jsonEncode(plan)) as Map);
    final raw = copy['blueprintLayoutDraft'];
    if (raw is Map &&
        raw['layout'] is Map &&
        raw['layout']['schemaVersion'] == 1) {
      final imported = importLegacyLayout(
        Map<String, dynamic>.from(raw['layout'] as Map),
        fontFamilies: fontFamilies,
        sourceRevision: 0,
      );
      if (!imported.isReady)
        throw const FormatException('Starší plánek vyžaduje ruční přípravu.');
      raw['layout'] = imported.document!.toJson();
    }
    if (raw is Map) {
      copy['blueprintLayoutDraft'] = BlueprintSetupLayoutDraft.fromJson(
        Map<String, dynamic>.from(raw),
      ).toJson();
    }
    return copy;
  }

  void importPlan(Map plan) {
    final raw = plan['blueprintLayoutDraft'];
    if (raw is! Map)
      throw const FormatException(
        'Tento starší plánek nelze převzít bez přípravy. Vyberte jiný nebo vytvořte nový.',
      );
    final parsed = BlueprintSetupLayoutDraft.fromJson(
      Map<String, dynamic>.from(raw),
    );
    data['blueprintLayoutDraft'] = parsed.toJson();
    data['blueprintMode'] = 'copy';
    data['blueprintSourceId'] = plan['id'];
    data['blueprintTitle'] = plan['title'];
    normalize();
  }

  void normalize() {
    data['blueprintMode'] = modeId;
    if (!active) data.remove('blueprintLayoutDraft');
    final originalForm = data['formDraft'];
    if (originalForm is! Map) return;
    // Locally constructed forms may carry narrower inferred collection types.
    // Own a JSON-shaped map before replacing fields or clearing the reference.
    final form = Map<String, dynamic>.from(originalForm);
    final fields = List<dynamic>.from(form['fields'] as List? ?? []);
    final existing = fields
        .whereType<Map>()
        .where((f) => f['type'] == 'spot')
        .firstOrNull;
    fields.removeWhere((f) => f is Map && f['type'] == 'spot');
    if (active)
      // A raw Map spread otherwise infers Map<dynamic, dynamic>, which the
      // form parser cannot read until an unrelated JSON save roundtrip.
      fields.add(<String, dynamic>{
        'order': -1,
        if (existing != null) ...Map<String, dynamic>.from(existing),
        'type': 'spot',
        'is_ticket_field': true,
        'is_hidden': false,
        'is_required': true,
      });
    form['fields'] = fields;
    form['blueprint'] = null;
    data['formDraft'] = form;
  }
}
