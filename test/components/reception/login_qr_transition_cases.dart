import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/reception/login_qr_transition.dart';

void main() {
  testWidgets('shows an explicit successful QR sign-in confirmation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: LoginQrTransition(
          state: LoginQrTransitionState.success,
          title: 'Uživatel přihlášen',
          subtitle: 'Hotovo. Otevírám aplikaci.',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Uživatel přihlášen'), findsOneWidget);
    expect(find.text('Hotovo. Otevírám aplikaci.'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('shows progress while the QR credential is exchanged',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: LoginQrTransition(
          state: LoginQrTransitionState.signingIn,
          title: 'Přihlašuji…',
          subtitle: 'Ověřuji přihlašovací QR.',
        ),
      ),
    ));

    expect(find.text('Přihlašuji…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
