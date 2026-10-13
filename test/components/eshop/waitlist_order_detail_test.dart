import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/views/waitlist_order_detail.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Localization.load(const Locale('cs'),
        translations: Translations(
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>,
        ));
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = null;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
  });

  Future<void> open(WidgetTester tester,
      {required String lifecycle, String? displayName}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WaitlistOrderDetail(
      order: OrderModel(id: 5, orderSymbol: '9W6L1I6R4V', state: 'waitlisted'),
      loadDetail: (id) async {
        expect(id, 5);
        loads++;
        return {
          'occasionTitle': 'Festival & letní setkání',
          'tickets': [
            {
              'id': 8837,
              'displayName': displayName,
              'lifecycle': lifecycle,
              'ticket_symbol': null,
              'waitlist_queue_at': null,
              'created_at': null,
              'updated_at': null
            }
          ],
          'capacity': {'serverTime': null},
          'offers': [],
          'linkedOrders': [],
        };
      },
    ))));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Festival & letní setkání'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text(WaitlistStrings.offers), findsNothing);
    expect(find.text(WaitlistStrings.linkedOrders), findsNothing);
    expect(find.text(WaitlistStrings.withdraw), findsNothing);
    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('8837'), findsNothing);
    expect(find.textContaining('Osoba 1'), findsNothing);
  }

  testWidgets(
      'withdrawn single ticket shows safe display name and no empty sections or actions',
      (tester) async {
    await open(tester, lifecycle: 'withdrawn', displayName: 'Jana <Nováková>');
    expect(find.text('Jana <Nováková>'), findsOneWidget);
    expect(find.text(WaitlistStrings.text('withdrawn')), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('single readonly waiting ticket uses canonical application label',
      (tester) async {
    expect(RightsService.isEditorOrder(), isFalse);
    await open(tester, lifecycle: 'waiting');
    expect(find.text(OrdersStrings.itemSingular), findsOneWidget);
    expect(find.text(WaitlistStrings.text('waiting')), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });
}
