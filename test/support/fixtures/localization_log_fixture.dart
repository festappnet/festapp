import 'package:easy_localization/easy_localization.dart';
// Public printer type of EasyLocalization's existing locked logger dependency.
// No dependency/version changes are needed for this test fixture.
// ignore: depend_on_referenced_packages
import 'package:easy_logger/easy_logger.dart';

/// Scoped public logger ownership. Observers receive diagnostics before filtering.
/// Only explicitly empty/uninitialized catalogs may omit missing-key output.
class LocalizationLogFixture {
  LocalizationLogFixture.install({
    this.expectedMissingCatalog = false,
    this.observeDiagnostic,
    this.summarize = true,
  }) : _previous = EasyLocalization.logger.printer {
    _printer = (object, {name, stackTrace, level}) {
      final diagnostic =
          level == LevelMessages.warning || level == LevelMessages.error;
      if (diagnostic) observeDiagnostic?.call(object.toString());
      final missing = level == LevelMessages.warning &&
          RegExp(r'^Localization key \[.*\] not found$')
              .hasMatch(object.toString());
      if (level == LevelMessages.debug || (expectedMissingCatalog && missing)) {
        if (missing) {
          suppressedMissing++;
        } else {
          suppressedDebug++;
        }
        return;
      }
      _previous?.call(object, name: name, stackTrace: stackTrace, level: level);
    };
    EasyLocalization.logger.printer = _printer;
  }

  final bool expectedMissingCatalog;
  final bool summarize;
  final void Function(String)? observeDiagnostic;
  final EasyLogPrinter? _previous;
  late final EasyLogPrinter _printer;
  bool _disposed = false;
  int suppressedDebug = 0;
  int suppressedMissing = 0;

  void dispose() {
    if (_disposed) return;
    if (!identical(EasyLocalization.logger.printer, _printer)) {
      throw StateError(
          'Localization printer scopes must be disposed in reverse order');
    }
    EasyLocalization.logger.printer = _previous;
    _disposed = true;
    if (summarize && suppressedDebug + suppressedMissing > 0) {
      // ignore: avoid_print
      print(
          'Localization logs omitted: debug=$suppressedDebug, expected missing=$suppressedMissing');
    }
  }
}
