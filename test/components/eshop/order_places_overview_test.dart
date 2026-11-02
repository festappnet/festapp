import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/eshop/order_detail_controller.dart';
import 'package:fstapp/components/eshop/views/order_places_view.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  testWidgets(
    'single plan stays in overview when a ticket or place is selected',
    (tester) async {
      final previous = RightsService.occasionLinkModelNotifier.value;
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasion: OccasionModel(
          id: 71,
          isHidden: false,
          isOpen: true,
          isPromoted: false,
        ),
      );
      final document = VenueLayoutDocument.empty().copyWith(
        nodes: [
          for (final n in [1, 2])
            LayoutNode.fromJson({
              'id': '00000000-0000-4000-8000-00000000000$n',
              'kind': 'seat',
              'width': 40,
              'height': 40,
              'transform': {'x': n * 200, 'y': 200, 'rotation': 0},
            }),
        ],
      );
      final places = [
        for (final n in [1, 2])
          {
            'blueprintId': 5,
            'active': true,
            'ticketId': n,
            'nodeId': '00000000-0000-4000-8000-00000000000$n',
            'spotId': n,
            'admissionItemId': n,
            'title': 'Seat $n',
          },
      ];
      final calls = <String>[];
      final controller = OrderDetailController(
        orderId: 42,
        occasionId: 71,
        read: (name, args) async {
          calls.add(name);
          return {
            'code': 200,
            'data': name == 'get_order_admin_detail'
                ? {
                    'order': {
                      'id': 42,
                      'occasion': 71,
                      'state': 'ordered',
                      'data': {},
                    },
                    'plans': [
                      {'id': 5, 'title': 'Hall', 'layoutRevision': 2},
                    ],
                    'places': places,
                    'placementFingerprint': 'current',
                  }
                : {
                    'title': 'Hall',
                    'layout': document.toJson(),
                    'resources': {},
                    'layout_revision': 2,
                    'placementFingerprint': 'current',
                  },
          };
        },
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        RightsService.occasionLinkModelNotifier.value = previous;
      });
      expect(await controller.load(), isTrue);
      int? selected;
      Set<int> selectedGroup = {};
      final environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ),
      );
      await environment.pumpWidget(
        tester,
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, refresh) => OrderPlacesView(
                  controller: controller,
                  ticketId: selected,
                  onTicket: (id) => refresh(() => selected = id),
                  onMapTickets: (ids) => selectedGroup = ids,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      VenueLayoutViewer viewer() =>
          tester.widget(find.byType(VenueLayoutViewer));
      expect(viewer().focusNodeIds, isEmpty);
      final revision = viewer().focusRevision;
      await tester.tap(find.text('Seat 2'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(selectedGroup, {2});
      expect(viewer().activeNodeIds, {'00000000-0000-4000-8000-000000000002'});
      expect(viewer().focusNodeIds, isEmpty);
      expect(viewer().focusRevision, revision);
      viewer().onNodeTap!('00000000-0000-4000-8000-000000000001');
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(selectedGroup, {1});
      expect(viewer().activeNodeIds, {'00000000-0000-4000-8000-000000000001'});
      expect(viewer().focusNodeIds, isEmpty);
      expect(viewer().focusRevision, revision);
      expect(calls, ['get_order_admin_detail', 'get_order_blueprint_view']);
      expect(viewer().document.toJson(), document.toJson());
      expect(tester.takeException(), isNull);
    },
  );
}
