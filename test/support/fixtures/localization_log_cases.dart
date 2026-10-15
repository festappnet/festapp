import 'package:flutter/widgets.dart';
import 'widget_environment_fixture.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'localization_log_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  testWidgets(
      'strict real catalog still exposes a missing translation to the assertion',
      (tester) async {
    final warnings = <String>[];
    final fixture =
        LocalizationLogFixture.install(observeDiagnostic: warnings.add);
    addTearDown(fixture.dispose);
    final environment = WidgetEnvironmentFixture(
        locale: const Locale('en'), translations: {'present': 'Present'});
    await environment.pumpWidget(tester, const SizedBox.shrink());
    expect('present'.tr(), 'Present');
    expect(warnings, isEmpty);
    expect('deliberately-missing'.tr(), 'deliberately-missing');
    expect(warnings, isNotEmpty);
    expect(() => expect(warnings, isEmpty), throwsA(isA<TestFailure>()));
    expect(fixture.suppressedMissing, 0);
  });
  test('localization scopes A-B-A restore printers and keep strict diagnostics',
      () {
    final original = EasyLocalization.logger.printer;
    addTearDown(() => EasyLocalization.logger.printer = original);
    final output = <String>[];
    EasyLocalization.logger.printer =
        (object, {name, level, stackTrace}) => output.add(object.toString());
    final sink = EasyLocalization.logger.printer;
    for (final fallback in [false, true, false]) {
      final captured = <String>[];
      final fixture = LocalizationLogFixture.install(
          expectedMissingCatalog: fallback,
          observeDiagnostic: captured.add,
          summarize: false);
      try {
        output.clear();
        EasyLocalization.logger.debug('noise');
        EasyLocalization.logger.warning('Localization key [missing] not found');
        EasyLocalization.logger.warning('unexpected warning');
        EasyLocalization.logger.error('actual error');
        expect(captured, [
          'Localization key [missing] not found',
          'unexpected warning',
          'actual error'
        ]);
        expect(output,
            fallback ? ['unexpected warning', 'actual error'] : captured);
        expect(fixture.suppressedDebug, 1);
        expect(fixture.suppressedMissing, fallback ? 1 : 0);
        if (!fallback) {
          // The existing strict-catalog assertion still fails for a missing key.
          expect(() => expect(captured, isEmpty), throwsA(isA<TestFailure>()));
        }
      } finally {
        fixture.dispose();
      }
      expect(identical(EasyLocalization.logger.printer, sink), isTrue);
    }
  });
  test(
      'nested localization cleanup preserves parent and rejects foreign ownership',
      () {
    final original = EasyLocalization.logger.printer;
    final parent = LocalizationLogFixture.install(summarize: false);
    addTearDown(parent.dispose);
    final parentPrinter = EasyLocalization.logger.printer;
    final child = LocalizationLogFixture.install(
        expectedMissingCatalog: true, summarize: false);
    expect(parent.dispose, throwsStateError);
    child.dispose();
    expect(identical(EasyLocalization.logger.printer, parentPrinter), isTrue);
    parent.dispose();
    expect(identical(EasyLocalization.logger.printer, original), isTrue);
    parent.dispose();
  });
  test('partial setup and failing body restore localization in finally', () {
    final original = EasyLocalization.logger.printer;
    for (final stage in ['setup', 'body']) {
      expect(() {
        final fixture = LocalizationLogFixture.install(summarize: false);
        try {
          throw StateError(stage);
        } finally {
          fixture.dispose();
        }
      }, throwsStateError);
      expect(identical(EasyLocalization.logger.printer, original), isTrue);
    }
  });
}
