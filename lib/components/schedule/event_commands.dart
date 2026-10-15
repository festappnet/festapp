import 'package:festapp_core/program.dart';

enum EventCommandStatus { applied, unchanged, rejected, conflict }

class EventCommandResult {
  const EventCommandResult({
    required this.status,
    required this.version,
    this.event,
  });

  final EventCommandStatus status;
  final int version;
  final EventModel? event;
}

abstract interface class EventCommands {
  Future<EventCommandResult> save(EventModel event);
  Future<EventCommandResult> delete(EventModel event);
}
