import 'package:flutter/foundation.dart';

class SavedProgramPendingOwner {
  const SavedProgramPendingOwner._(this.generation, this.sequence);

  final int generation;
  final int sequence;
}

class SavedProgramPendingState extends ChangeNotifier {
  final Map<int, ({SavedProgramPendingOwner owner, bool saved})> _pending = {};
  int _generation = 0;
  int _sequence = 0;
  int _stateRevision = 0;

  SavedProgramPendingOwner createOwner() =>
      SavedProgramPendingOwner._(_generation, ++_sequence);

  int get mutationVersion => _stateRevision;

  void set(int eventId, SavedProgramPendingOwner owner, bool saved) {
    if (owner.generation != _generation) return;
    final current = _pending[eventId];
    if (current != null && current.owner.sequence > owner.sequence) return;
    _pending[eventId] = (owner: owner, saved: saved);
    _stateRevision++;
    notifyListeners();
  }

  void clear(int eventId, SavedProgramPendingOwner owner) {
    if (identical(_pending[eventId]?.owner, owner)) {
      _pending.remove(eventId);
      _stateRevision++;
      notifyListeners();
    }
  }

  void clearAll() {
    _generation++;
    _pending.clear();
    _stateRevision++;
    notifyListeners();
  }

  bool get hasPending => _pending.isNotEmpty;

  List<int> apply(Iterable<int> confirmedIds) {
    final resolved = confirmedIds.toSet();
    for (final entry in _pending.entries) {
      if (entry.value.saved) {
        resolved.add(entry.key);
      } else {
        resolved.remove(entry.key);
      }
    }
    return resolved.toList(growable: false);
  }
}

final savedProgramPendingState = SavedProgramPendingState();

bool shouldLoadSavedProgramOnline({
  required bool isV1Selected,
  required bool isOffline,
  required bool hasPendingMutation,
}) =>
    !isV1Selected && !isOffline && !hasPendingMutation;
