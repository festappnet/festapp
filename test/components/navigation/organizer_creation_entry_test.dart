import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/navigation/help_destination_picker.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  testWidgets('creation rejects account changes while choosing an organizer', (
    tester,
  ) async {
    final previous = RightsService.occasionLinkModelNotifier.value;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      userInfo: UserInfoModel(id: 'actor')
        ..units = [
          UnitModel(id: 42, title: 'Organizer A'),
          UnitModel(id: 73, title: 'Organizer B'),
        ],
    );
    String? result = 'pending';
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  result = await createOrganizerOccasion(context),
              child: const Text('Create'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Organizer A'), findsOneWidget);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      userInfo: UserInfoModel(id: 'another-actor'),
    );
    await tester.tap(find.text('Organizer A'));
    await tester.pumpAndSettle();
    expect(
      result,
      isNull,
      reason: 'no capability request or draft creation may run for the previous account',
    );
  });
}
