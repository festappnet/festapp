import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/holder_models/field_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

late WidgetEnvironmentFixture environment;
void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() => environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>));

  for (final card in [false, true]) {
    testWidgets('design $card: email errors wait for blur, including corrections', (tester) async {
      final key = GlobalKey<_HarnessState>();
      await environment.pumpWidget(tester,
          MaterialApp(builder: DependencyMaterialBridge.builder, home: _Harness(key: key, card: card, tickets: true)));
      final inputs = find.byType(TextField);
      final error = find.text(FormHelper.emailInvalidMessage());
      await tester.enterText(inputs.at(0), 'bujnmi@co');
      await tester.pumpAndSettle();
      expect(error, findsNothing);
      await tester.tap(inputs.at(1));
      await tester.pumpAndSettle();
      expect(error, findsOneWidget);
      await tester.enterText(inputs.at(0), 'bujnmi@c');
      await tester.pumpAndSettle();
      expect(error, findsNothing);
      await tester.tap(inputs.at(1));
      await tester.pumpAndSettle();
      expect(error, findsOneWidget);
      await tester.enterText(inputs.at(0), 'bujnmi@example.co');
      await tester.tap(inputs.at(1));
      await tester.pumpAndSettle();
      expect(error, findsNothing);
    });
    testWidgets(
        'design $card: blur, correction, per-ticket confirmation, rerender, edit and submit',
        (tester) async {
      final key = GlobalKey<_HarnessState>();
      await environment.pumpWidget(tester,
          MaterialApp(builder: DependencyMaterialBridge.builder, home: _Harness(key: key, card: card, tickets: true)));
      final inputs = find.byType(TextField);
      await tester.enterText(inputs.at(0), 'a@example.czz');
      expect(find.text(FormStrings.emailSuffixConfirm), findsNothing);
      await tester.tap(inputs.at(1));
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.emailSuffixConfirm), findsOneWidget);
      await tester.enterText(inputs.at(0), 'a@example.czzz');
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.emailSuffixConfirm), findsNothing);
      await tester.tap(inputs.at(1));
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.emailSuffixConfirm), findsOneWidget);
      await tester.enterText(inputs.at(0), 'a@example.cz');
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.emailSuffixConfirm), findsNothing);
      await tester.enterText(inputs.at(0), 'a@example.czz');
      await tester.enterText(inputs.at(1), 'a@example.czz');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(key.currentState!.requests, 0);
      await tester.tap(find.text(FormStrings.emailSuffixConfirm).first);
      await tester.pumpAndSettle();
      expect(key.currentState!.requests, 0, reason: 'confirm never submits');
      key.currentState!.rebuild();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(key.currentState!.requests, 0,
          reason: 'same value on ticket is a separate field');
      await tester.tap(find.text(FormStrings.emailSuffixConfirm));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(key.currentState!.requests, 1);
      await tester.enterText(inputs.at(0), 'b@example.czz');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(key.currentState!.requests, 1);
      expect(find.text(FormStrings.emailSuffixConfirm), findsOneWidget);
      expect(key.currentState!.formKey.currentState!.errors, isEmpty,
          reason: 'suffix warnings are not format errors');
      // A fresh form session must not inherit confirmation.
      await environment.pumpWidget(
          tester, MaterialApp(builder: DependencyMaterialBridge.builder, home: _Harness(key: UniqueKey(), card: card)));
      await tester.enterText(find.byType(TextField), 'a@example.czz');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.emailSuffixConfirm), findsOneWidget);
    });
  }
  testWidgets(
      'required and invalid format block, optional empty and hidden/disabled suffix do not',
      (tester) async {
    final key = GlobalKey<_HarnessState>();
    await environment.pumpWidget(
        tester, MaterialApp(builder: DependencyMaterialBridge.builder, home: _Harness(key: key, card: false)));
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(key.currentState!.requests, 0);
    await tester.enterText(find.byType(TextField), 'broken');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(key.currentState!.requests, 0);
    await tester.enterText(find.byType(TextField), 'bujnmi@co');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(key.currentState!.requests, 0);
    await tester.enterText(find.byType(TextField), 'a@example.cm');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(key.currentState!.requests, 1);
    for (final mode in ['optional', 'hidden', 'disabled']) {
      final special = GlobalKey<_HarnessState>();
      await environment.pumpWidget(tester,
          MaterialApp(builder: DependencyMaterialBridge.builder, home: _Harness(key: special, card: true, mode: mode)));
      if (mode != 'optional') {
        special.currentState!.formKey.currentState!.fields['1']!
            .didChange('a@example.czz');
        await tester.pump();
      }
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(special.currentState!.requests, 1, reason: mode);
      expect(find.text(FormStrings.emailSuffixConfirm), findsNothing);
    }
  });
}

class _Harness extends StatefulWidget {
  final bool card;
  final bool tickets;
  final String mode;
  const _Harness(
      {super.key,
      required this.card,
      this.tickets = false,
      this.mode = 'normal'});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final formKey = GlobalKey<FormBuilderState>();
  late final FormHolder holder;
  int requests = 0;
  void rebuild() => setState(() {});
  @override
  void initState() {
    super.initState();
    FieldHolder email() => FieldHolder(
        id: 1,
        fieldType: 'email',
        title: 'Email',
        isRequired: widget.mode != 'optional',
        isHidden: widget.mode == 'hidden');
    holder = FormHolder(fields: [
      email(),
      if (widget.tickets)
        TicketHolder(
            id: 99, fieldType: 'ticket', maxTickets: 1, fields: [email()])
    ], isCardDesign: widget.card)
      ..controller = FormHolderController(globalKey: formKey);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SingleChildScrollView(
          child: FormBuilder(
              key: formKey,
              enabled: widget.mode != 'disabled',
              child: Column(children: [
                ...FormHelper.getAllFormFields(context, formKey, holder),
                ElevatedButton(
                    onPressed: () async {
                      if (await FormHelper.saveValidateAndScroll(holder)) {
                        requests++;
                      }
                    },
                    child: const Text('Submit')),
              ]))));
}
