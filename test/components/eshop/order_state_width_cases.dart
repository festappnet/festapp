import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/views/order_state_column_width.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync());
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'status minimum grows with warning, expiry and accessibility text scaling',
      (tester) async {
    await EasyLocalization.ensureInitialized();
    double regular = 0, decorated = 0, scaled = 0;
    final plain = OrderModel(state: OrderModel.orderedState);
    final expired = OrderModel(
        state: OrderModel.expiredState,
        paymentInfoModel: PaymentInfoModel.fromJson({
          'bank_account': 1,
          'amount': 100,
          'paid': 0,
          'bank_sync_warning': {
            'code': 'suspended',
            'bank_account_title': 'Bank'
          },
        }));
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'unused',
      startLocale: const Locale('cs'),
      assetLoader: const _Translations(),
      child: Builder(
          builder: (context) => MaterialApp(
                locale: context.locale,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                home: Builder(builder: (context) {
                  regular = orderStateColumnWidth(context, [plain]);
                  decorated = orderStateColumnWidth(context, [expired]);
                  return MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: const TextScaler.linear(2)),
                      child: Builder(builder: (context) {
                        scaled = orderStateColumnWidth(context, [expired]);
                        return const SizedBox();
                      }));
                }),
              )),
    ));
    await tester.pump();
    expect(regular, greaterThanOrEqualTo(140));
    expect(decorated, greaterThanOrEqualTo(regular));
    expect(scaled, greaterThan(decorated));
    expect(
        orderStateColumnWidth(tester.element(find.byType(SizedBox).last), []),
        140);
  });
}
