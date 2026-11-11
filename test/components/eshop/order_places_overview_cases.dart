import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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
  setUpAll(() async {
    if (Platform.environment['FESTAPP_PAYMENT_CAPTURE_DIR'] == null) return;
    await (FontLoader('Futura')
          ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))
          ..addFont(rootBundle.load('fonts/Futura PT Medium.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final (dense, reducedMotion, platform) in [
    (false, false, TargetPlatform.windows),
    (false, true, TargetPlatform.macOS),
    (true, false, TargetPlatform.windows),
    (true, true, TargetPlatform.macOS),
  ]) {
    testWidgets(
      'plan selection keeps camera and bounded initial focus dense=$dense reducedMotion=$reducedMotion',
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
            for (final n in [1, 2, 3, 4, 5])
              LayoutNode.fromJson({
                'id': '00000000-0000-4000-8000-00000000000$n',
                'kind': 'seat',
                'width': dense ? 10 : 80,
                'height': dense ? 10 : 80,
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
        final mapReady = Completer<void>();
        final controller = OrderDetailController(
          orderId: 42,
          occasionId: 71,
          read: (name, args) async {
            calls.add(name);
            if (name == 'get_order_blueprint_view') await mapReady.future;
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
                      'id': 5,
                      'occasion': 71,
                      'title': null,
                      'seatStates': [
                        for (var n = 1; n <= 5; n++)
                          {
                            'nodeId': '00000000-0000-4000-8000-00000000000$n',
                            'title': 'Seat $n',
                            'blocked': n == 5,
                            'hasProduct': true,
                            'state': {
                              1: 'ordered',
                              2: 'used',
                              3: 'selected',
                              4: 'available',
                              5: 'available',
                            }[n],
                          },
                      ],
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
        (int, Set<String>)? openedPlan;
        final environment = WidgetEnvironmentFixture(
          locale: const Locale('cs'),
          translations: jsonDecode(
            File('assets/translations/cs.json').readAsStringSync(),
          ),
        );
        await environment.pumpWidget(
          tester,
          MaterialApp(
            theme: ThemeData(platform: platform, fontFamily: 'Futura'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reducedMotion),
              child: child!,
            ),
            home: RepaintBoundary(
              key: const ValueKey('plan-capture'),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (context, refresh) => OrderPlacesView(
                      controller: controller,
                      ticketId: selected,
                      onTicket: (id) => refresh(() => selected = id),
                      onMapTickets: (ids) => selectedGroup = ids,
                      onOpenPlan: (plan, node) => openedPlan = (plan, node),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        // Repeated selection during the same in-flight map load reuses that request.
        final secondPlace = tester
            .widgetList<ListTile>(find.byType(ListTile))
            .last;
        secondPlace.onTap!();
        secondPlace.onTap!();
        await tester.pump();
        expect(calls, ['get_order_admin_detail', 'get_order_blueprint_view']);
        mapReady.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        VenueLayoutViewer viewer() =>
            tester.widget(find.byType(VenueLayoutViewer));
        expect(
          viewer().highlightPulse!.value,
          reducedMotion ? 1 : inExclusiveRange(0, 1),
        );
        await tester.pumpAndSettle();
        expect(viewer().highlightPulse!.value, 1);
        expect(viewer().focusMaxZoomFactor, 2.6);
        expect(viewer().focusSeatPixelSize, 12);

        expect(viewer().focusNodeIds, places.map((p) => p['nodeId']).toSet());
        expect(viewer().focusMaxZoomFactor, inInclusiveRange(1, 2.6));
        expect(find.textContaining('null'), findsNothing);
        final states = viewer().seatPresentation;
        expect(
          (states['00000000-0000-4000-8000-000000000001'] as Map?)?['state'],
          'ordered',
        );
        expect(
          (states['00000000-0000-4000-8000-000000000002'] as Map?)?['state'],
          'used',
        );
        expect(
          (states['00000000-0000-4000-8000-000000000003'] as Map?)?['state'],
          'selected',
        );
        expect(
          (states['00000000-0000-4000-8000-000000000004'] as Map?)?['state'],
          'available',
        );
        expect(
          (states['00000000-0000-4000-8000-000000000005'] as Map?)?['state'],
          'blocked',
        );
        final revision = viewer().focusRevision;
        await tester.tap(find.text('Seat 2'));
        await tester.pumpAndSettle();
        expect(selected, 2);
        expect(selectedGroup, {2});
        expect(viewer().activeNodeIds, {
          '00000000-0000-4000-8000-000000000002',
        });
        expect(viewer().focusNodeIds, places.map((p) => p['nodeId']).toSet());
        expect(viewer().focusMaxZoomFactor, inInclusiveRange(1, 2.6));
        expect(viewer().focusRevision, revision);
        viewer().onNodeTap!('00000000-0000-4000-8000-000000000001');
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(selectedGroup, {1});
        expect(viewer().activeNodeIds, {
          '00000000-0000-4000-8000-000000000001',
        });
        expect(viewer().focusNodeIds, places.map((p) => p['nodeId']).toSet());
        expect(viewer().focusMaxZoomFactor, inInclusiveRange(1, 2.6));
        expect(viewer().focusRevision, revision);
        await tester.ensureVisible(find.byIcon(Icons.location_searching).last);
        await tester.tap(find.byIcon(Icons.location_searching).last);
        await tester.pumpAndSettle();
        expect(openedPlan!.$1, 5);
        expect(openedPlan!.$2, {'00000000-0000-4000-8000-000000000002'});
        expect(
          selected,
          1,
          reason: 'Opening the main plan is distinct from selection',
        );
        expect(viewer().focusRevision, revision);
        await tester.ensureVisible(
          find.byTooltip('Otevřít plánek s místy objednávky'),
        );
        await tester.tap(find.byTooltip('Otevřít plánek s místy objednávky'));
        await tester.pumpAndSettle();
        expect(openedPlan!.$1, 5);
        expect(
          openedPlan!.$2,
          places.map((p) => p['nodeId'] as String).toSet(),
        );
        expect(calls, ['get_order_admin_detail', 'get_order_blueprint_view']);
        expect(viewer().document.toJson(), document.toJson());
        expect(
          find.text('Celý sál'),
          findsNothing,
          reason: 'Only the canvas fit/focus control remains',
        );
        expect(
          find.text(
            platform == TargetPlatform.macOS
                ? 'Přiblížení: ⌘ + kolečko myši.'
                : 'Přiblížení: Ctrl + kolečko myši.',
          ),
          findsOneWidget,
        );
        Future<void> capture(String state) async {
          final directory = Platform.environment['FESTAPP_PAYMENT_CAPTURE_DIR'];
          if (directory == null || dense || reducedMotion) return;
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('plan-capture')),
            );
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('$directory/plan-$state.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('focused');
        final control = find.byIcon(Icons.fit_screen);
        await tester.ensureVisible(control);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(viewer().focusNodeIds, places.map((p) => p['nodeId']).toSet());
        expect(
          viewer().focusRevision,
          revision,
          reason: 'Camera toggling stays in its owner',
        );
        await capture('overview');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
