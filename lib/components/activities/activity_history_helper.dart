import 'package:fstapp/components/activities/activity_model.dart';

class ActivityHistoryHelper {
  final List<EditDataBundle> _undoStack = [];
  final List<EditDataBundle> _redoStack = [];

  /// Creates a deep copy of the bundle by serializing and deserializing it.
  /// This ensures that history states are independent.
  EditDataBundle _deepCopy(EditDataBundle bundle) {
    final json = bundle.toJsonHistory();
    return EditDataBundle.fromJsonHistory(json);
  }

  /// Creates a deep copy of the bundle by serializing and deserializing it.
  /// This ensures that history states are independent.
  EditDataBundle _deepCopyToHistory(EditDataBundle bundle) {
    final json = bundle.toJsonEditor();
    return EditDataBundle.fromJsonHistory(json);
  }

  /// Clears the history and sets a new initial state.
  /// This is typically called after loading data or after publishing changes.
  void clear(EditDataBundle initialState) {
    _undoStack.clear();
    _redoStack.clear();
    _undoStack.add(_deepCopy(initialState));
  }

  /// Records a new state in the history. When a new state is recorded,
  /// the redo stack is cleared.
  void record(EditDataBundle newState) {
    _redoStack.clear();
    _undoStack.add(_deepCopyToHistory(newState));
  }

  /// Reverts to the previous state in the history.
  /// Returns the state that should be restored.
  EditDataBundle? undo() {
    if (!canUndo) return null;
    final currentState = _undoStack.removeLast();
    _redoStack.add(currentState);
    return _deepCopy(_undoStack.last);
  }

  /// Re-applies an undone action.
  /// Returns the state that should be restored.
  EditDataBundle? redo() {
    if (!canRedo) return null;
    final nextState = _redoStack.removeLast();
    _undoStack.add(nextState);
    return _deepCopy(nextState);
  }

  /// Returns true if there is at least one action to undo.
  bool get canUndo => _undoStack.length > 1;

  /// Returns true if there is at least one action to redo.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Returns the number of changes made since the last publish/load.
  int get changesCount => canUndo ? _undoStack.length - 1 : 0;
}
