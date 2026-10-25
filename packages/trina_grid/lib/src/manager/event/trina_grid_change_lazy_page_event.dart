import 'package:trina_grid/trina_grid.dart';

/// Allows changing the current page when using lazy pagination.
class TrinaGridChangeLazyPageEvent extends TrinaGridEvent {
  /// In case of null the current lazy page will be used.
  final int? page;

  TrinaGridChangeLazyPageEvent({required this.page});

  @override
  void handler(TrinaGridStateManager stateManager) {
    // This event is handled by TrinaLazyPagination plugin
    // No need to implement handler here
  }
}
