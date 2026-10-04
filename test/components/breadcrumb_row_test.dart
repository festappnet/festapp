import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/breadcrumb_row.dart';
import 'package:fstapp/theme_config.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader(ThemeConfig.fontFamily)
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))
      ..addFont(rootBundle.load('fonts/Gill Sans Bold.otf'));
    await font.load();
  });
  for (final withIcon in [false, true]) {
    testWidgets(
        '${withIcon ? "form" : "admin"} breadcrumb fonts share a baseline',
        (tester) async {
      for (final scale in [1.0, 1.5]) {
        await tester.pumpWidget(MaterialApp(
            theme: ThemeConfig.theme(),
            home: Scaffold(
                appBar: AppBar(
                    title: MediaQuery.withClampedTextScaling(
              minScaleFactor: scale,
              maxScaleFactor: scale,
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: BreadcrumbRow(children: [
                    InkWell(
                        onTap: () {},
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              if (withIcon)
                                const IgnoreBaseline(
                                    child:
                                        Icon(Icons.article_outlined, size: 20)),
                              const Text('Normal title',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal)),
                            ]))),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text('/')),
                    InkWell(
                        onTap: () {},
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              const Text('Bold title',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              if (!withIcon)
                                const Icon(Icons.unfold_more_rounded, size: 20),
                            ]))),
                  ])),
            )))));
        await tester.pumpAndSettle();
        double baseline(String text) {
          final finder = find.text(text);
          final box = tester.renderObject<RenderBox>(finder);
          return tester.getTopLeft(finder).dy +
              box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!;
        }

        expect(baseline('Bold title'), closeTo(baseline('Normal title'), .01));
        expect(tester.takeException(), isNull);
      }
    });
  }
}
