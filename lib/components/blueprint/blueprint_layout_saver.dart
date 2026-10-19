import 'blueprint_layout_contract.dart';
import 'blueprint_command_rejection.dart';
import '../forms/form_commands.dart';

/// One unresolved submission is retained after an ambiguous transport failure.
/// Later edits remain local until that exact submission receives its receipt.
class BlueprintLayoutSaver {
  BlueprintLayoutSaver(this.commands);
  final FormCommands commands;
  BlueprintLayoutSaveRequest? _pending;
  Future<BlueprintLayoutSaveResult>? _flight;
  BlueprintLayoutSaveRequest? get pending => _pending;
  Future<BlueprintLayoutSaveResult> save(BlueprintLayoutSaveRequest request) {
    if (_flight != null) return _flight!;
    _pending ??= request;
    final submitted = _pending!;
    final future = commands.saveBlueprint(submitted.toJson()).then((json) {
      final result = BlueprintLayoutSaveResult.fromJson(json);
      if (result.accepted && result.revision == null) {
        throw const FormatException('Missing blueprint revision');
      }
      _pending = null;
      return result;
    }).onError((Object error, StackTrace stack) {
      // A definitive rejected receipt ends the intent; network failures do not.
      if (error is BlueprintCommandRejection) _pending = null;
      Error.throwWithStackTrace(error, stack);
    }).whenComplete(() => _flight = null);
    _flight = future;
    return future;
  }
}
