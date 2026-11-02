import 'package:venue_seat_picker/venue_seat_picker.dart';

/// Immutable drawing data, never occupancy, placement or an authorization result.
class OrderBlueprintPlan {
  OrderBlueprintPlan._(
    this.occasionId,
    this.id,
    this.revision,
    this.document,
    this.resources,
  );
  final int occasionId, id, revision;
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources;
}

class OrderBlueprintView {
  OrderBlueprintView._(this.data, this.plan);
  final Map<String, dynamic> data;
  final OrderBlueprintPlan plan;
}

/// Owned by one Orders screen. Every reuse still needs an authorized server
/// response confirming the saved revision and supplying fresh seat facts.
class OrderBlueprintCache {
  final _plans = <(int, int), OrderBlueprintPlan>{};
  static const _capacity = 3;

  OrderBlueprintPlan? lookup(int occasionId, int blueprintId) =>
      _plans[(occasionId, blueprintId)];

  void clear() => _plans.clear();

  OrderBlueprintView decode(
    Map<String, dynamic> data, {
    required int occasionId,
    required int blueprintId,
    OrderBlueprintPlan? known,
  }) {
    final revision = data['layout_revision'];
    if (data['id'] != blueprintId ||
        data['occasion'] != occasionId ||
        revision is! int) {
      throw const FormatException('Invalid plan scope or revision');
    }
    OrderBlueprintPlan plan;
    if (data['layout'] is Map && data['resources'] is Map) {
      plan = OrderBlueprintPlan._(
        occasionId,
        blueprintId,
        revision,
        VenueLayoutDocument.fromJson(
          Map<String, dynamic>.from(data['layout'] as Map),
        ),
        frozenMap(Map<String, dynamic>.from(data['resources'] as Map)),
      );
    } else if (!data.containsKey('layout') &&
        !data.containsKey('resources') &&
        known != null &&
        known.occasionId == occasionId &&
        known.id == blueprintId &&
        known.revision == revision) {
      // Keep the request's immutable snapshot even if a later request evicted
      // the entry while this authorized read was in flight.
      plan = known;
    } else {
      throw const FormatException('Plan drawing data unavailable');
    }
    final key = (occasionId, blueprintId);
    _plans.remove(key);
    _plans[key] = plan;
    if (_plans.length > _capacity) _plans.remove(_plans.keys.first);
    final metadata = Map<String, dynamic>.from(data)
      ..remove('layout')
      ..remove('resources');
    return OrderBlueprintView._(Map.unmodifiable(metadata), plan);
  }
}
