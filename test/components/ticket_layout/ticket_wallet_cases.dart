import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/ticket_layout/google_wallet_appearance.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_wallet_selector.dart';

void main() {
  test('Native Wallet appearance shares the backend contract and preserves overrides', () {
    final cases = jsonDecode(
      File('packages/festapp_contracts/ticket-wallet-appearance-cases.json')
          .readAsStringSync(),
    ) as List;
    for (final sample in cases) {
      expect(
        GoogleWalletAppearance.fromTicket(
          Map<String, dynamic>.from(sample['feature']),
          Map<String, dynamic>.from(sample['data']),
        ).toJson(),
        sample['expected'],
        reason: sample['name'],
      );
    }
    final feature = TicketFeature.fromJson({
      'code': 'ticket',
      'wallet_appearance': {'background_color': '#216acf', 'logo': null},
    });
    expect(
      TicketFeature.fromJson(feature.toJson()).walletAppearance,
      feature.walletAppearance,
    );
  });
  test('Wallet preference survives model edits, modes and round trip', () {
    final feature = TicketFeature.fromJson({
      'code': 'ticket',
      'is_enabled': true,
    });
    expect(feature.walletEnabled, true);
    feature.walletEnabled = false;
    for (final mode in TicketDeliveryMode.values) {
      feature.deliveryMode = mode;
      expect(TicketFeature.fromJson(feature.toJson()).walletEnabled, false);
    }
    expect(
      () =>
          TicketFeature.fromJson({'code': 'ticket', 'wallet_enabled': 'false'}),
      throwsA(isA<TypeError>()),
    );
  });
  testWidgets(
    'Wallet row toggles independently and disabled retains preference',
    (tester) async {
      bool value = false;
      Widget view(bool enabled) => MaterialApp(
        home: Scaffold(
          body: TicketWalletSelector(
            value: value,
            enabled: enabled,
            onChanged: (next) => value = next,
          ),
        ),
      );
      await tester.pumpWidget(view(true));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(value, true);
      await tester.pumpWidget(view(false));
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );
    },
  );
}
