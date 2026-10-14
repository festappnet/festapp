import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:fstapp/widgets/app_text_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_controller.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'package:fstapp/components/ticket_layout/ticket_text.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_layout_canvas.dart';

void main() {
  for (final scale in [.5, 2.0]) {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      for (final snap in [false, true]) {
        testWidgets(
            'selection tolerates jitter at zoom $scale with $kind, snap $snap',
            (tester) async {
          final template = TicketTemplate(
              page: const Size(400, 400),
              area: const Rect.fromLTWH(0, 0, 400, 400),
              elements: const [
                TicketElement(
                    id: 'qr',
                    binding: 'qr',
                    box: Rect.fromLTWH(100, 100, 80, 80))
              ]);
          final controller = TicketLayoutController(template);
          final transform = TransformationController();
          final resources = TicketLayoutResources(
              template: template,
              preset: template,
              scenarios: const {},
              metrics: const TicketFontMetrics({}, .8, -.2),
              qrSize: 1,
              qrModules: const [1]);
          addTearDown(controller.dispose);
          addTearDown(transform.dispose);
          addTearDown(resources.dispose);
          await tester.pumpWidget(MaterialApp(
              builder: (context, child) =>
                  AppTextSelection(enabled: true, child: child!),
              home: TicketLayoutCanvas(
                  controller: controller,
                  resources: resources,
                  data: const {'qr': 'preview'},
                  transform: transform,
                  snap: snap,
                  grid: true)));
          await tester.pump();
          transform.value = Matrix4.identity()
            ..scaleByDouble(scale, scale, 1, 1);
          await tester.pump();
          final origin = tester.getTopLeft(find.byType(TicketLayoutCanvas));
          Offset screenPoint(Offset point) =>
              origin + MatrixUtils.transformPoint(transform.value, point);
          final center = screenPoint(const Offset(140, 140));
          final before = controller.document.toJson();
          final click = await tester.startGesture(center, kind: kind);
          await tester.pump();
          expect(controller.selectedIds, {'qr'});
          await click.moveTo(center + const Offset(5, 0));
          await click.up();
          await tester.pump();
          expect(controller.document.toJson(), before);
          expect(controller.canUndo, isFalse);

          final drag = await tester.startGesture(center, kind: kind);
          await tester.pump();
          final distance =
              scale * (kind == PointerDeviceKind.mouse ? 20 : 60) + 1;
          await drag.moveTo(center + Offset(distance, 0));
          await drag.moveTo(center + Offset(distance + 1, 0));
          await drag.up();
          await tester.pump();
          final unsnappedLeft = 100 + (distance + 1) / scale;
          final expectedLeft =
              snap ? (unsnappedLeft / 10).round() * 10.0 : unsnappedLeft;
          expect(controller.document.elements.single.box.left,
              closeTo(expectedLeft, .001));
          expect(controller.canUndo, isTrue);
          controller.undo();
          expect(controller.document.toJson(), before);

          // Clicking an existing resize handle also tolerates a shaky pointer.
          final corner = screenPoint(const Offset(100, 100));
          final resizeClick = await tester.startGesture(corner, kind: kind);
          await tester.pump();
          await resizeClick.moveTo(corner + const Offset(5, 0));
          await resizeClick.up();
          await tester.pump();
          expect(controller.document.toJson(), before);
          expect(controller.canUndo, isFalse);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
