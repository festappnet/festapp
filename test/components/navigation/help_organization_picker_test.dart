import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/navigation/help_destination_picker.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  testWidgets(
    'organization help chooses an organizer without selecting an event',
    (tester) async {
      final previous = RightsService.occasionLinkModelNotifier.value;
      addTearDown(
        () => RightsService.occasionLinkModelNotifier.value = previous,
      );
      final user = UserInfoModel(id: 'actor')
        ..units = [
          UnitModel(id: 42, title: 'Organizer A'),
          UnitModel(id: 73, title: 'Organizer B'),
        ];
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        userInfo: user,
      );
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await chooseHelpOrganization(context),
                child: const Text('Open organizer'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open organizer'));
      await tester.pumpAndSettle();
      expect(find.text('Organizer A'), findsOneWidget);
      expect(find.text('Organizer B'), findsOneWidget);
      await tester.tap(find.text('Organizer B'));
      await tester.pumpAndSettle();
      expect(result, 73);

      result = -1;
      await tester.tap(find.text('Open organizer'));
      await tester.pumpAndSettle();
      // Signing into another account while the picker is open invalidates it.
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        userInfo: UserInfoModel(id: 'another-actor'),
      );
      await tester.tap(find.text('Organizer A'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );
}
