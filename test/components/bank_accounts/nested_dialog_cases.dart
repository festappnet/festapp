import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_dialog_scope.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_settings_screen.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  for (final picker in [false, true]) {
    testWidgets(
        'bank modal keeps ${picker ? 'calendar' : 'child dialog'} above it',
        (tester) async {
      var parentClosed = false;
      var selected = false;
      await tester.pumpWidget(MaterialApp(
        home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => RoutedBankAccountDialog(
                    title: 'Account',
                    onClose: () => parentClosed = true,
                    child: Navigator(
                        onGenerateRoute: (_) => MaterialPageRoute<void>(
                            builder: (_) => Builder(
                                builder: (context) => TextButton(
                                      child: const Text('Open child'),
                                      onPressed: () async {
                                        final dialogContext =
                                            BankAccountDialogScope.contextOf(
                                                context);
                                        if (picker) {
                                          selected = await showDatePicker(
                                                context: dialogContext,
                                                useRootNavigator: false,
                                                initialDate:
                                                    DateTime(2026, 10, 14),
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2030),
                                              ) !=
                                              null;
                                        } else {
                                          selected = await showDialog<bool>(
                                                context: dialogContext,
                                                useRootNavigator: false,
                                                builder: (context) =>
                                                    AlertDialog(
                                                  title: const Text('Child'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              context, true),
                                                      child:
                                                          const Text('Choose'),
                                                    )
                                                  ],
                                                ),
                                              ) ??
                                              false;
                                        }
                                      },
                                    )))),
                  ),
                )),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open child'));
      await tester.pumpAndSettle();
      final confirm = find.text(picker ? 'OK' : 'Choose');
      expect(confirm.hitTestable(), findsOneWidget);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(parentClosed, isFalse);
      expect(find.text('Open child').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
