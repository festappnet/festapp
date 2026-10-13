import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/holder_models/field_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/form_ticket_model.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_field_builders.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';

void main() {
  testWidgets(
      'offer reuses runtime fields and keeps person IDs with their answers',
      (tester) async {
    FieldHolder name(String value) => FieldHolder(
        id: 7,
        fieldType: 'name',
        isRequired: true,
        defaultValue: value,
        title: 'Name');
    final ticket = TicketHolder(
        fieldType: 'ticket', id: 1, maxTickets: 2, fields: [name('')])
      ..fixedParticipants = true;
    ticket.tickets = [
      FormTicketModel(
          participantId: 'a',
          ticketValues: [name('Alex')],
          ticketKey: GlobalKey<FormBuilderState>()),
      FormTicketModel(
          participantId: 'b',
          ticketValues: [name('Robin')],
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
    expect(data['ticket'][0]['participantId'], 'a');
    expect(data['ticket'][0]['fields'][0]['7'], 'Alex');
    expect(data['ticket'][1]['participantId'], 'b');
    expect(data['ticket'][1]['fields'][0]['7'], 'Robin');
    expect(tester.takeException(), isNull);
  });
}
