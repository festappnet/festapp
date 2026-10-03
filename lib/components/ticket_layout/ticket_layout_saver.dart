import '../features/ticket_feature.dart';
import '../occasion/db_occasions.dart';
import '../occasion/occasion_model.dart';

/// Saves only ticket artwork/geometry using the existing versioned occasion command.
class TicketLayoutSaver {
  final Future<OccasionModel> Function(String) load;
  final Future<void> Function(OccasionModel) persist;
  TicketLayoutSaver(
      {Future<OccasionModel> Function(String)? load,
      Future<void> Function(OccasionModel)? persist})
      : load = load ?? DbOccasions.getOccasionByLink,
        persist = persist ?? DbOccasions.updateOccasion;

  Future<void> save(OccasionModel current, TicketFeature draft) async {
    final fresh = await load(current.link!);
    if (fresh.id != current.id ||
        fresh.aggregateVersion != current.aggregateVersion) {
      throw StateError('Occasion was changed by another editor');
    }
    final ticket = fresh.features.whereType<TicketFeature>().firstOrNull ??
        TicketFeature(code: draft.code, isEnabled: draft.isEnabled);
    if (!fresh.features.contains(ticket)) fresh.features.add(ticket);
    ticket.layout = draft.layout;
    ticket.ticketBackground = draft.ticketBackground;
    ticket.ticketType = draft.ticketType;
    await persist(fresh);
    current.aggregateVersion = fresh.aggregateVersion;
  }
}
