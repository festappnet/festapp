import 'event_model.dart';

/// Build immutable view relations in the caller's existing child order. IDs
/// remain the wire authority; a closing cycle is represented by those IDs,
/// rather than a mutable cyclic object graph.
List<EventModel> attachEventChildren(
  List<EventModel> events,
  Map<int, List<int>> childrenByParent,
) {
  final byId = {
    for (final event in events)
      if (event.id != null) event.id!: event,
  };
  final complete = <int, EventModel>{};
  EventModel expand(EventModel event, Set<int> path) {
    final id = event.id;
    if (id == null) return event;
    if (complete[id] case final value?) return value;
    if (path.contains(id)) return event;
    final value = event.copyWith(
      childEvents: [
        for (final childId in childrenByParent[id] ?? const <int>[])
          if (byId[childId] case final child?) expand(child, {...path, id}),
      ],
    );
    complete[id] = value;
    return value;
  }

  return [for (final event in events) expand(event, {})];
}
