import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('waitlist grid row has no payment or reminder values',
      (tester) async {
    final order =
        OrderModel.fromJson({'id': 5, 'state': 'waitlisted', 'price': null});
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      final row = order.toTrinaRow(context);
      expect(row.cells[EshopColumnIds.PAYMENT_INFO_REMINDER_SENT]!.value, '');
      expect(row.cells[EshopColumnIds.ORDER_PRICE]!.value, '');
      return const SizedBox();
    })));
    expect(tester.takeException(), isNull);
  });

  test(
      'capacity settings preserve explicit null and mode-specific public limit',
      () {
    final model = FormEditorDraft.fromJson({
      'id': 8,
      'registrationMode': 'regular',
      'participant_capacity': 20,
      'waitlist_enabled': true,
      'waitlist_offer_duration_seconds': 7200,
      'capacity': {
        'enabled': true,
        'limit': 20,
        'remainingPublic': 2,
        'showRemaining': true
      },
      'fields': [
        {
          'id': 1,
          'type': 'ticket',
          'data': {'max_tickets': 4}
        },
        {'id': 2, 'type': 'name', 'is_ticket_field': true},
        {
          'id': 3,
          'type': 'product_type',
          'is_ticket_field': true,
          'product_type_data': {'id': 9, 'products': []}
        },
      ],
    });
    expect(model.definition.capacity!.remainingPublic, 2);
    expect(
        FormHolder.fromDefinition(model.freeze()).getTicket()!.maxTickets, 2);
    model.definition = model.definition.copyWith(registrationMode: 'waitlist');
    final waiting = FormHolder.fromDefinition(model.freeze()).getTicket()!;
    expect(waiting.maxTickets, 4);
    expect(waiting.fields.map((f) => f.id), [2]);
    model.definition = model.definition.copyWith(participantCapacity: null);
    expect(model.toEditedJson().containsKey('participant_capacity'), true);
    expect(model.toEditedJson()['participant_capacity'], null);
  });

  test('mixed waitlist group remains active but cannot use paid/send actions',
      () {
    final order = OrderModel.fromJson({
      'id': 5,
      'state': 'waitlisted',
      'price': null,
      'isActive': true,
      'allowedActions': ['view', 'note', 'offer', 'withdraw'],
      'waitlistSummary': {
        'counts': {'waiting': 1, 'offer_expired': 3},
        'pendingPlaces': 0,
        'isActive': true
      },
    });
    expect(order.isActive, true);
    expect(order.canEdit, false);
    expect(order.allows('paid'), false);
    expect(order.allows('send'), false);
    expect(order.allows('note'), true);
    expect(order.price, null);
    final inactive =
        OrderModel.fromJson({'state': 'waitlisted', 'isActive': false});
    expect(inactive.isActive, false);
    expect(inactive.allows('cancel'), false);
  });

  test('server action projection overrides regular-state fallback', () {
    final preparing = OrderModel.fromJson({
      'state': 'ordered',
      'allowedActions': ['view']
    });
    expect(preparing.canEdit, false);
    expect(preparing.allows('paid'), false);
    expect(OrderModel(state: 'paid').allows('send'), true);
    expect(OrderModel(state: 'storno').canEdit, false);
  });
}
