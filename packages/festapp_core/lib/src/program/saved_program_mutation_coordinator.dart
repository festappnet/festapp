import 'dart:async';
import 'dart:collection';

enum SavedProgramMutationOutcome { applied, superseded, rejected, scopeChanged }

class SavedProgramMutationResult {
  const SavedProgramMutationResult(this.outcome, {this.error});

  final SavedProgramMutationOutcome outcome;
  final Object? error;

  bool get wasApplied => outcome == SavedProgramMutationOutcome.applied;
}

class SavedProgramMutationCoordinator {
  SavedProgramMutationCoordinator({
    required String Function() currentScope,
    required Future<bool> Function(String scope, int eventId, bool saved)
    persist,
  }) : _currentScope = currentScope,
       _persist = persist;

  final String Function() _currentScope;
  final Future<bool> Function(String scope, int eventId, bool saved) _persist;
  final Queue<_PendingSavedProgramMutation> _pending = Queue();
  bool _isDraining = false;

  Future<SavedProgramMutationResult> enqueue({
    required String scope,
    required int eventId,
    required bool saved,
  }) {
    final completer = Completer<SavedProgramMutationResult>();
    final superseded = _pending
        .where(
          (request) => request.scope == scope && request.eventId == eventId,
        )
        .toList(growable: false);
    for (final request in superseded) {
      _pending.remove(request);
      request.complete(
        const SavedProgramMutationResult(
          SavedProgramMutationOutcome.superseded,
        ),
      );
    }
    _pending.add(
      _PendingSavedProgramMutation(
        scope: scope,
        eventId: eventId,
        saved: saved,
        completer: completer,
      ),
    );
    _startDrain();
    return completer.future;
  }

  void _startDrain() {
    if (_isDraining) return;
    _isDraining = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        final request = _pending.removeFirst();
        if (_currentScope() != request.scope) {
          request.complete(
            const SavedProgramMutationResult(
              SavedProgramMutationOutcome.scopeChanged,
            ),
          );
          continue;
        }
        try {
          final applied = await _persist(
            request.scope,
            request.eventId,
            request.saved,
          );
          request.complete(
            SavedProgramMutationResult(
              _currentScope() == request.scope
                  ? applied
                        ? SavedProgramMutationOutcome.applied
                        : SavedProgramMutationOutcome.rejected
                  : SavedProgramMutationOutcome.scopeChanged,
            ),
          );
        } catch (error) {
          request.complete(
            SavedProgramMutationResult(
              _currentScope() == request.scope
                  ? SavedProgramMutationOutcome.rejected
                  : SavedProgramMutationOutcome.scopeChanged,
              error: error,
            ),
          );
        }
      }
    } finally {
      _isDraining = false;
      if (_pending.isNotEmpty) _startDrain();
    }
  }
}

class _PendingSavedProgramMutation {
  _PendingSavedProgramMutation({
    required this.scope,
    required this.eventId,
    required this.saved,
    required this.completer,
  });

  final String scope;
  final int eventId;
  final bool saved;
  final Completer<SavedProgramMutationResult> completer;

  void complete(SavedProgramMutationResult result) {
    if (!completer.isCompleted) completer.complete(result);
  }
}
