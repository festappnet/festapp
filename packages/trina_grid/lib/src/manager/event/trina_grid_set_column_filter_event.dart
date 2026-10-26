import 'package:trina_grid/trina_grid.dart';

/// If the value of [TrinaGridStateManager.filterOnlyEvent] is true,
/// an event is issued.
/// [TrinaInfinityScrollRows] or [TrinaLazyPagination] Event
/// for delegating filtering processing to widgets.
class TrinaGridSetColumnFilterEvent extends TrinaGridEvent {
  TrinaGridSetColumnFilterEvent({required this.filterRows});

  final List<TrinaRow> filterRows;

  @override
  void handler(TrinaGridStateManager stateManager) {}
}
