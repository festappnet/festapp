import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/reception/manual_login_code_field.dart';

void main() {
  testWidgets(
      'manual code entry formats lowercase input without requiring separators',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManualLoginCodeField(controller: controller),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'k7m4p9q2');
    await tester.pump();

    expect(controller.text, 'K7M4 P9Q2');
    expect(ManualLoginCodeField.normalized(controller.text), 'K7M4P9Q2');
    expect(ManualLoginCodeField.isComplete(controller.text), isTrue);
  });

  testWidgets('manual code entry ignores pasted spaces and dashes',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManualLoginCodeField(controller: controller),
      ),
    ));

    await tester.enterText(find.byType(TextField), ' k7m4-p9q2 ');
    await tester.pump();

    expect(controller.text, 'K7M4 P9Q2');
  });

  testWidgets('manual code is offered as an inline scanner fallback',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManualLoginCodeEntry(
          onSubmitted: (value) => submitted = value,
          title: 'Enter code manually',
          fieldLabel: 'Code',
          submitLabel: 'Sign in',
        ),
      ),
    ));

    expect(find.text('Enter code manually'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Sign in'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'k7m4-p9q2');
    await tester.pump();
    await tester.tap(find.byTooltip('Sign in'));
    await tester.pump();

    expect(submitted, 'K7M4P9Q2');
  });
}
