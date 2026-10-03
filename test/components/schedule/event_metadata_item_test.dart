import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/event_metadata_item.dart';
import 'package:fstapp/theme_config.dart';

void main() {
  const duration = 'sobota, říj 3, 14:00 - 15:00';
  for (final dark in [false, true]) {
    for (final isLink in [false, true]) {
      testWidgets('metadata wraps at 200%: dark=$dark link=$isLink',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeConfig.theme(
              brightness: dark ? Brightness.dark : Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Center(),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 280,
                child: Wrap(children: [
                  EventMetadataItem(
                    icon: Icons.access_time,
                    text: duration,
                    color: Theme.of(context).colorScheme.onSurface,
                    isLink: isLink,
                  ),
                ]),
              ),
            ),
          ),
        ));
        final textRect = tester.getRect(find.text(duration));
        final rowRect = tester.getRect(find.byType(EventMetadataItem));
        expect(textRect.height, greaterThan(40));
        expect(textRect.right, lessThanOrEqualTo(rowRect.right));
        expect(rowRect.width, lessThanOrEqualTo(280));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'compact metadata remains scrollable without an unbounded flex error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeConfig.theme(),
      home: const Center(
        child: SizedBox(
          width: 100,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: EventMetadataItem(
              icon: Icons.access_time,
              text: duration,
              color: Colors.black,
            ),
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.text(duration)).width, greaterThan(100));
    expect(tester.takeException(), isNull);
  });
}
