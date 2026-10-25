import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_palette_thumbnail.dart';

void main() {
  testWidgets('palette preview cannot paint the plan canvas over dark chrome',
      (tester) async {
    final key = GlobalKey();
    const background = Color(0xff18212a);
    final document = VenueLayoutDocument.empty().copyWith(nodes: [
      LayoutNode(id: 'seat', kind: 'seat', x: 0, y: 0, width: 40, height: 40),
    ]);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Center(
          child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                  color: background,
                  child: SizedBox(
                    width: 240,
                    height: 120,
                    child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 80,
                          height: 80,
                          child: LayoutPaletteThumbnail(
                              document: document,
                              resources: const {},
                              kind: 'Seat'),
                        )),
                  ))),
        )));
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = (await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final offset = (60 * image.width + 160) * 4;
    expect(bytes.buffer.asUint8List().sublist(offset, offset + 4),
        [24, 33, 42, 255]);
    image.dispose();
  });
}
