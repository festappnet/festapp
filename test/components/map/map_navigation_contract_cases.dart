import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_navigation.dart';
import 'package:fstapp/components/map/public_map_host.dart';
import 'package:fstapp/components/map/public_map_session.dart';

void main() {
  testWidgets('command lookup does not subscribe the caller to session changes',
      (tester) async {
    final session = PublicMapSession()..setVisible(true);
    final dependencyChanges = ValueNotifier<int>(0);

    await tester.pumpWidget(MaterialApp(
      home: PublicMapSessionScope(
        session: session,
        child: _CommandCaller(dependencyChanges: dependencyChanges),
      ),
    ));
    expect(dependencyChanges.value, 1);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(dependencyChanges.value, 1);

    session.acceptExternalIntent(const MapPlaceIntent(2));
    await tester.pump();
    expect(dependencyChanges.value, 1);

    session.dispose();
    dependencyChanges.dispose();
  });
}

final class _CommandCaller extends StatefulWidget {
  final ValueNotifier<int> dependencyChanges;

  const _CommandCaller({required this.dependencyChanges});

  @override
  State<_CommandCaller> createState() => _CommandCallerState();
}

final class _CommandCallerState extends State<_CommandCaller> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.dependencyChanges.value++;
  }

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () => MapNavigation.openPlace(context, 1),
        child: const Text('open'),
      );
}
