import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:festapp_core/forms.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/holder_models/field_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/form_ticket_model.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_field_builders.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets(
      'offer reuses runtime fields and keeps numeric ticket IDs with their answers',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FieldHolder name(String value) => FieldHolder(
        id: 7,
        fieldType: 'name',
        isRequired: true,
        defaultValue: value,
        title: 'Name');
    FieldHolder custom(int id, String value) => FieldHolder(
        id: id,
        fieldType: 'text',
        isRequired: false,
        defaultValue: value,
        title: 'Custom $id');
    OptionsFieldHolder choices(dynamic saved) => OptionsFieldHolder(
            id: 112,
            fieldType: 'select_many',
            isRequired: false,
            title: 'Choices',
            options: [
              FormOptionDefinition('a', 'A'),
              FormOptionDefinition('b', 'B'),
              FormOptionDefinition('c', 'C')
            ],
            value: [
              'A'
            ])
          ..defaultValue = saved;
    OptionsFieldProductHolder emptyProduct() => OptionsFieldProductHolder(
        id: 113,
        fieldType: 'product_type',
        isRequired: false,
        title: 'Optional admission',
        productOptions: [],
        selectionType: OptionsFieldProductSelectionType.selectOne);
    final ticket =
        TicketHolder(fieldType: 'ticket', id: 1, maxTickets: 2, fields: [
      name(''),
      custom(109, ''),
      custom(110, ''),
      choices(['A']),
      emptyProduct()
    ])
          ..fixedTickets = true;
    ticket.tickets = [
      FormTicketModel(
          ticketId: 101,
          ticketValues: [
            name('Alex'),
            custom(109, 'Vegan'),
            custom(110, 'Step-free'),
            choices('B | C'),
            emptyProduct()
          ],
          ticketKey: GlobalKey<FormBuilderState>()),
      FormTicketModel(
          ticketId: 102,
          ticketValues: [
            name('Robin'),
            custom(109, 'No nuts'),
            custom(110, 'Hearing loop'),
            choices(''),
            emptyProduct()
          ],
          ticketKey: GlobalKey<FormBuilderState>()),
    ];
    final key = GlobalKey<FormBuilderState>();
    final holder = FormHolder(fields: [ticket], isCardDesign: false)
      ..controller = FormHolderController(globalKey: key);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FormBuilder(
                key: key,
                child: Builder(
                    builder: (context) => FormFieldBuilders.buildTicketField(
                        context, holder, ticket))))));
    await tester.pump();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Robin'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    final data = FormHelper.getDataFromForm(holder);
    expect(data['ticket'][0]['ticketId'], 101);
    expect(data['ticket'][0]['fields'][0]['7'], 'Alex');
    expect(data['ticket'][1]['ticketId'], 102);
    expect(data['ticket'][1]['fields'][0]['7'], 'Robin');
    expect(data['ticket'][0]['fields'][1]['109'], 'Vegan');
    expect(data['ticket'][0]['fields'][2]['110'], 'Step-free');
    expect(data['ticket'][1]['fields'][1]['109'], 'No nuts');
    expect(data['ticket'][1]['fields'][2]['110'], 'Hearing loop');
    expect(data['ticket'][0]['fields'].any((f) => f['112'] == 'B | C'), isTrue);
    expect(data['ticket'][1]['fields'].any((f) => f['112'] == 'A'), isFalse);
    for (final item in data['ticket']) {
      expect(item['fields'].any((f) => (f as Map).containsKey('product_type')),
          isFalse);
    }
    expect(tester.takeException(), isNull);
  });
}
