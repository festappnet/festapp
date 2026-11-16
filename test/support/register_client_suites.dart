import 'dart:io';
import 'fixtures/localization_log_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

/// Share an engine only across compatible environments. Each group keeps its
/// original setup/teardown and constructs its own test data and widgets.
/// Reverse order is a deterministic isolation check, not another registration.
void registerClientSuites(Map<String, void Function()> suites,
    {String orderVariable = 'FESTAPP_FIXTURE_ORDER'}) {
  final entries = suites.entries;
  final ordered = Platform.environment[orderVariable] == 'reverse'
      ? entries.toList().reversed
      : entries;
  for (final entry in ordered) {
    group(entry.key, () {
      // No catalog assumptions here: mixed sessions retain all warnings.
      setUp(() {
        final logs = LocalizationLogFixture.install();
        addTearDown(logs.dispose);
      });
      entry.value();
    });
  }
}
