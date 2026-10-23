import 'dart:convert';
import 'package:fstapp/components/eshop/order_amount_change.dart';

/// One immutable resource request. Local map selection never replaces it.
class BlueprintSeatOrderRequest {
  BlueprintSeatOrderRequest(
      {required this.occasionId,
      required this.organizationId,
      this.unitId,
      required this.blueprintId,
      required List<int> spotIds})
      : spotIds = List.unmodifiable(spotIds) {
    if ([occasionId, organizationId, blueprintId, ...spotIds]
            .any((id) => id <= 0) ||
        spotIds.isEmpty ||
        spotIds.length > 20000 ||
        spotIds.toSet().length != spotIds.length)
      throw const FormatException('Invalid seat order request');
  }
  final int occasionId, organizationId, blueprintId;
  final int? unitId;
  final List<int> spotIds;
  Map<String, dynamic> get parameters => {
        'p_occasion': occasionId,
        'p_organization': organizationId,
        'p_unit': unitId,
        'p_blueprint': blueprintId,
        'p_spots': spotIds,
        'p_editor': true
      };
}

class BlueprintSeatOrderRequirements {
  BlueprintSeatOrderRequirements._(
      this.request,
      this.principalBinding,
      this.actorId,
      this.formKey,
      this.spotIds,
      this.affectedSpotIds,
      this.items,
      this.conflicts,
      this.requiredFields,
      this.phonePrefixes,
      this.seatSubtotal,
      this.currencyCode);
  final BlueprintSeatOrderRequest request;
  final String? principalBinding;
  final String actorId;
  final String? formKey, seatSubtotal, currencyCode;
  final List<int> spotIds, affectedSpotIds;
  final List<Map<String, dynamic>> items, conflicts, requiredFields;
  final Object? phonePrefixes;
  factory BlueprintSeatOrderRequirements.fromJson(Map<String, dynamic> json,
      {required BlueprintSeatOrderRequest request,
      required String? principalBinding}) {
    _checkScope(json, request);
    if (json['code'] != 200 || json['mode'] != 'requirements')
      throw const FormatException('Order requirements unavailable');
    final spots = _ids(json['spotIds']),
        affected = _ids(json['affectedSpotIds']);
    final items = _rows(json['items']),
        conflicts = _rows(json['conflicts']),
        fields = _rows(json['requiredFields']);
    final actor = _uuid(json['actorId']);
    final form = json['formKey'] == null ? null : _uuid(json['formKey']);
    if (request.spotIds.any((id) => !spots.contains(id)) ||
        spots.any((id) => !affected.contains(id)) ||
        items.length != spots.length ||
        items.map((row) => _id(row['spotId'])).toSet().length != spots.length ||
        items.any((row) => !spots.contains(row['spotId'])))
      throw const FormatException('Incomplete order requirements');
    for (final row in items) {
      _amount(row['amount'], nullable: true);
      _currency(row['currencyCode'], nullable: true);
    }
    _checkConflicts(conflicts, spots);
    if (fields.map((row) => _id(row['id'])).toSet().length != fields.length)
      throw const FormatException('Duplicate form field');
    return BlueprintSeatOrderRequirements._(
        request,
        principalBinding,
        actor,
        form,
        spots,
        affected,
        items,
        conflicts,
        fields,
        _freeze(json['phonePrefixes']),
        _amount(json['seatSubtotal'], nullable: true),
        _currency(json['currencyCode'], nullable: true));
  }
}

class BlueprintSeatOrderPreview {
  BlueprintSeatOrderPreview._(
      this.requirements,
      this.principalBinding,
      this.actorId,
      this.confirmationHash,
      this.inputData,
      this.spotIds,
      this.affectedSpotIds,
      this.releasedSpotIds,
      this.blueprints,
      this.seats,
      this.orders,
      this.conflicts,
      this.newOrderAmount,
      this.currencyCode,
      this.newOrderState,
      this.newOrderProducts);
  final BlueprintSeatOrderRequirements requirements;
  final String? principalBinding;
  final String actorId,
      confirmationHash,
      newOrderAmount,
      currencyCode,
      newOrderState;
  final Map<String, dynamic> inputData;
  final List<int> spotIds, affectedSpotIds, releasedSpotIds;
  final List<Map<String, dynamic>> blueprints,
      seats,
      conflicts,
      newOrderProducts;
  final List<OrderAmountChange> orders;
  BlueprintSeatOrderRequest get request => requirements.request;
  factory BlueprintSeatOrderPreview.fromJson(Map<String, dynamic> json,
      {required BlueprintSeatOrderRequirements requirements,
      required Map<String, dynamic> inputData,
      required String? principalBinding}) {
    _checkScope(json, requirements.request);
    if (json['code'] != 200 ||
        json['mode'] != 'quote' ||
        _uuid(json['actorId']) != requirements.actorId ||
        inputData['form_key'] != requirements.formKey ||
        requirements.principalBinding != principalBinding)
      throw const FormatException('Order quote scope changed');
    final hash = json['confirmationHash'] as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))
      throw const FormatException('Invalid order quote');
    final quote = Map<String, dynamic>.from(json['quote'] as Map),
        spots = _ids(quote['spotIds']),
        affected = _ids(quote['affectedSpotIds']);
    final released = _ids(quote['releasedSpotIds'], empty: true),
        seats = _rows(quote['seats']),
        blueprints = _rows(quote['blueprints']);
    final conflicts = _rows(json['conflicts']);
    _checkConflicts(conflicts, spots);
    final orders = (quote['orders'] as List)
        .map((row) =>
            OrderAmountChange.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    final previousOrders =
        seats.map((row) => row['previousOrderId']).whereType<int>().toSet();
    final actualBlueprints =
        seats.map((row) => row['blueprintId']).whereType<int>().toSet();
    final next = Map<String, dynamic>.from(quote['newOrder'] as Map),
        products = _rows(next['products']);
    if (requirements.request.spotIds.any((id) => !spots.contains(id)) ||
        spots.any((id) => !affected.contains(id)) ||
        released.any((id) => !affected.contains(id) || spots.contains(id)) ||
        released.length != affected.length - spots.length ||
        seats.length != affected.length ||
        seats.map((row) => _id(row['spotId'])).toSet().length !=
            affected.length ||
        seats.any((row) => !affected.contains(row['spotId'])) ||
        orders.length != previousOrders.length ||
        orders.map((row) => row.orderId).toSet().length !=
            previousOrders.length ||
        orders.any((row) => !previousOrders.contains(row.orderId)) ||
        conflicts.map((row) => row['orderId']).toSet().length !=
            previousOrders.length ||
        conflicts.any((row) => !previousOrders.contains(row['orderId'])) ||
        blueprints.length != actualBlueprints.length ||
        blueprints.map((row) => _id(row['id'])).toSet().length !=
            actualBlueprints.length ||
        blueprints.any((row) =>
            !actualBlueprints.contains(row['id']) ||
            row['revision'] is! int ||
            (row['revision'] as int) < 0) ||
        next['ticketCount'] != spots.length ||
        products.any((row) => !spots.contains(row['spotId'])) ||
        products.map((row) => _id(row['spotId'])).toSet().length !=
            spots.length ||
        quote['formKey'] != requirements.formKey ||
        next['paymentMethod'] != 'bank')
      throw const FormatException('Incomplete seat order confirmation');
    for (final row in seats) {
      for (final key in ['stateBefore', 'stateAfter'])
        if (!const {'available', 'selected', 'ordered', 'used'}
            .contains(row[key]))
          throw const FormatException('Invalid seat lifecycle');
    }
    for (final row in products) {
      _id(row['productId']);
      _amount(row['amount']);
      _currency(row['currencyCode']);
    }
    return BlueprintSeatOrderPreview._(
        requirements,
        principalBinding,
        requirements.actorId,
        hash,
        _freeze(jsonDecode(jsonEncode(inputData))) as Map<String, dynamic>,
        spots,
        affected,
        released,
        blueprints,
        seats,
        List.unmodifiable(orders),
        conflicts,
        _amount(next['amount'])!,
        _currency(next['currencyCode'])!,
        next['state'] as String,
        products);
  }
  Map<String, dynamic> get parameters => {
        ...request.parameters,
        'p_input': inputData,
        'p_target_spots': spotIds,
        'p_affected_spots': affectedSpotIds,
        'p_blueprints': blueprints,
        'p_confirmation_hash': confirmationHash,
        'p_expected_actor': actorId
      };
}

void _checkScope(Map<String, dynamic> json, BlueprintSeatOrderRequest request) {
  if (json['occasionId'] != request.occasionId ||
      json['blueprintId'] != request.blueprintId ||
      jsonEncode(json['requestedSpotIds']) != jsonEncode(request.spotIds))
    throw const FormatException('Seat order scope changed');
}

void _checkConflicts(List<Map<String, dynamic>> conflicts, List<int> spots) {
  if (conflicts.map((row) => _id(row['orderId'])).toSet().length !=
      conflicts.length) throw const FormatException('Duplicate order conflict');
  for (final group in conflicts) {
    final tickets = _rows(group['tickets']);
    if (tickets.length != group['selectedTicketCount'] ||
        tickets.map((row) => _id(row['ticketId'])).toSet().length !=
            tickets.length)
      throw const FormatException('Incomplete ticket conflict');
    for (final ticket in tickets) {
      if (_ids(ticket['selectedSpotIds']).any((id) => !spots.contains(id)))
        throw const FormatException('Foreign ticket conflict');
    }
  }
}

int _id(Object? value) {
  if (value is! int || value <= 0)
    throw const FormatException('Invalid domain identity');
  return value;
}

String _uuid(Object? value) {
  if (value is! String ||
      !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(value))
    throw const FormatException('Invalid actor or form');
  return value;
}

List<int> _ids(Object? value, {bool empty = false}) {
  final ids = (value as List).map(_id).toList();
  if ((ids.isEmpty && !empty) ||
      ids.length > 20000 ||
      ids.toSet().length != ids.length)
    throw const FormatException('Invalid seat selection');
  return List.unmodifiable(ids);
}

String? _amount(Object? value, {bool nullable = false}) {
  if (value == null && nullable) return null;
  if (value is! String ||
      value.length > 40 ||
      !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value))
    throw const FormatException('Invalid authoritative amount');
  return value;
}

String? _currency(Object? value, {bool nullable = false}) {
  if (value == null && nullable) return null;
  if (value is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(value))
    throw const FormatException('Invalid currency');
  return value;
}

List<Map<String, dynamic>> _rows(Object? value) => List.unmodifiable(
    (value as List).map((row) => _freeze(Map<String, dynamic>.from(row as Map))
        as Map<String, dynamic>));
Object? _freeze(Object? value) {
  if (value is Map)
    return Map<String, dynamic>.unmodifiable(
        value.map((key, value) => MapEntry(key.toString(), _freeze(value))));
  if (value is List) return List.unmodifiable(value.map(_freeze));
  return value;
}
