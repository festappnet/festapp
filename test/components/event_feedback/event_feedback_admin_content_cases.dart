import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/event_feedback/event_feedback_admin_content.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  final feedbackRow = <String, dynamic>{
    'feedback_id': 41,
    'event_id': 7,
    'event_title': 'Program item',
    'event_start_time': '2026-08-07T10:00:00Z',
    'event_end_time': '2026-08-07T11:00:00Z',
    'rating': 'happy',
    'note': 'Great',
    'user_name': 'Test User',
    'is_anonymous': false,
    'created_at': '2026-08-07T11:00:00Z',
    'updated_at': '2026-08-07T11:00:00Z',
  };

  Widget app({
    required bool isAdmin,
    Future<List<Map<String, dynamic>>> Function(int occasionId)? loadOverride,
    Future<void> Function(int occasionId, int feedbackId)? deleteOverride,
  }) {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      capabilities: {AuthorizationCapabilities.scheduleFeedbackDelete: isAdmin},
      isAdmin: isAdmin,
      occasion: OccasionModel(
        id: 7,
        isOpen: true,
        isHidden: false,
        isPromoted: false,
      ),
      occasionUser: OccasionUserModel(isEditor: true, isEditorView: true),
    );
    return MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: EventFeedbackAdminContent(
          loadOverride: loadOverride ?? (_) async => [feedbackRow],
          deleteOverride: deleteOverride,
        ),
      ),
    );
  }

  setUp(() {
    final previous = RightsService.occasionLinkModel;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
  });

  testWidgets('admin feedback grid shows the program-style delete action',
      (tester) async {
    await tester.pumpWidget(app(isAdmin: true));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_forever), findsOneWidget);
  });

  testWidgets('occasion editor without isAdmin does not get a delete action',
      (tester) async {
    await tester.pumpWidget(app(isAdmin: false));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_forever), findsNothing);
  });

  testWidgets('admin delete is deferred until changes are saved',
      (tester) async {
    final deletedIds = <int>[];
    var deleted = false;
    await tester.pumpWidget(app(
      isAdmin: true,
      loadOverride: (_) async => deleted ? [] : [feedbackRow],
      deleteOverride: (occasionId, feedbackId) async {
        expect(occasionId, 7);
        deletedIds.add(feedbackId);
        deleted = true;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_forever));
    await tester.pump();

    expect(deletedIds, isEmpty);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Common.saveChanges'));
    await tester.pumpAndSettle();

    expect(deletedIds, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Common.delete'),
    ));
    await tester.pumpAndSettle();

    expect(deletedIds, [41]);
    expect(find.text('Program item'), findsNothing);
  });
}
