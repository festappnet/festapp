import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/navigation/help_occasion_picker.dart';
import 'package:fstapp/components/_shared/project_picker_widget.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';

import '../../support/fixtures/localization_log_fixture.dart';

OccasionModel event(
  String link,
  int? unit,
  DateTime? start, {
  DateTime? end,
  String? title,
}) => OccasionModel(
  id: link.hashCode,
  link: link,
  title: title ?? link,
  unit: unit,
  startTime: start,
  endTime: end,
  isOpen: true,
  isHidden: false,
  isPromoted: false,
);

Future<void> mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: DependencyMaterialBridge.builder,
      home: Scaffold(body: SizedBox(width: 480, height: 1050, child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
    final previous = Intl.defaultLocale;
    Intl.defaultLocale = 'en_US';
    addTearDown(() => Intl.defaultLocale = previous);
  });

  testWidgets(
    'organizers contain the ordinary temporal sections and dense dated rows',
    (tester) async {
      final now = DateTime.now();
      final items = [
        event('b-past', 2, now.subtract(const Duration(days: 4))),
        event('a-upcoming', 1, now.add(const Duration(days: 4))),
        event('a-past', 1, now.subtract(const Duration(days: 4))),
        // An ongoing event crosses midnight; use the same instant comparisons as the switcher.
        event(
          'a-current',
          1,
          now.subtract(const Duration(days: 2)).toUtc(),
          end: now.add(const Duration(days: 1)).toUtc(),
        ),
        event('undated', null, null),
      ];
      String? selected;
      var dismissals = 0;
      await mount(
        tester,
        HelpOccasionPicker(
          occasions: items,
          organizers: [
            UnitModel(id: 2, title: 'Beta'),
            UnitModel(id: 1, title: 'Alpha'),
          ],
          selectedLink: 'a-current',
          onSelected: (item) => selected = item.link,
          onCreateNew: () {},
          onDismiss: () => dismissals++,
        ),
      );
      double y(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(y('Alpha'), lessThan(y('a-current')));
      expect(y('a-current'), lessThan(y('a-upcoming')));
      expect(y('a-upcoming'), lessThan(y('a-past')));
      expect(y('a-past'), lessThan(y('Beta')));
      expect(y('Beta'), lessThan(y('b-past')));
      expect(find.text(CommonStrings.pastEvents), findsNWidgets(2));
      expect(find.byIcon(Icons.check), findsOneWidget);
      final row = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'a-current'),
      );
      expect(row.dense, isTrue);
      expect(
        (row.subtitle as Text).data,
        DateFormat.yMd().format(items[3].startTime!),
      );
      expect(find.text('undated'), findsOneWidget);
      await tester.tap(find.text('a-upcoming'));
      expect(selected, 'a-upcoming');
      expect(dismissals, 1);
    },
  );

  testWidgets(
    'search matches organizer names and years, preserves groups and can clear empty results',
    (tester) async {
      final year = DateTime.now().year + 1;
      await mount(
        tester,
        HelpOccasionPicker(
          occasions: [
            event('first', 1, DateTime(year, 5, 1)),
            event('second', 2, DateTime(year - 2, 4, 1)),
          ],
          organizers: [
            UnitModel(id: 1, title: 'Červená organizace'),
            UnitModel(id: 2, title: 'Beta'),
          ],
          onSelected: (_) {},
          onCreateNew: () {},
          onDismiss: () {},
        ),
      );
      await tester.enterText(find.byType(TextField), 'cervena');
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      expect(find.text('Červená organizace'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '$year');
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsNothing);
      await tester.enterText(find.byType(TextField), 'nothing matches');
      await tester.pumpAndSettle();
      expect(find.text('HelpNavigation.noMatches'), findsOneWidget);
      await tester.tap(find.byTooltip('HelpNavigation.clearSearch'));
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
    },
  );

  testWidgets(
    'same organizer names stay distinct and ambiguous events retain dates and links',
    (tester) async {
      final date = DateTime.now().add(const Duration(days: 3));
      await mount(
        tester,
        HelpOccasionPicker(
          occasions: [
            event('dance-a', 1, date, title: 'Dance'),
            event(
              'dance-b',
              1,
              date.add(const Duration(minutes: 1)),
              title: 'Dance',
            ),
            event('another', 2, date, title: 'Another'),
          ],
          organizers: [
            UnitModel(id: 1, title: 'Organizer'),
            UnitModel(id: 2, title: 'Organizer'),
          ],
          recentLink: 'dance-b',
          onSelected: (_) {},
          onCreateNew: () {},
          onDismiss: () {},
        ),
      );
      expect(find.text('Organizer'), findsNWidgets(2));
      final dateLabel = DateFormat.yMd().format(date);
      expect(find.text('$dateLabel · dance-a'), findsOneWidget);
      expect(
        find.text('$dateLabel · dance-b · HelpNavigation.recentEvent'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check), findsNothing);
    },
  );

  testWidgets(
    'unknown organizer events remain distinguishable in the fallback group',
    (tester) async {
      final date = DateTime.now();
      await mount(
        tester,
        HelpOccasionPicker(
          occasions: [
            event('unknown-a', 88, date, title: 'Dance'),
            event('unknown-b', 99, date, title: 'Dance'),
          ],
          organizers: [],
          onSelected: (_) {},
          onCreateNew: () {},
          onDismiss: () {},
        ),
      );
      expect(find.text('HelpNavigation.otherEvents'), findsOneWidget);
      expect(
        find.text('${DateFormat.yMd().format(date)} · unknown-a'),
        findsOneWidget,
      );
      expect(
        find.text('${DateFormat.yMd().format(date)} · unknown-b'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ungrouped switchers retain their temporal ordering and creation callback',
    (tester) async {
      final now = DateTime.now();
      final items = [
        event('later', 1, now.add(const Duration(days: 6))),
        event('older', 1, now.subtract(const Duration(days: 6))),
        event('sooner', 1, now.add(const Duration(days: 3))),
        event('recent', 1, now.subtract(const Duration(days: 3))),
        event(
          'ongoing',
          1,
          now.subtract(const Duration(days: 2)),
          end: now.add(const Duration(days: 1)),
        ),
        event('dateless', 1, null),
      ];
      var created = 0;
      var dismissed = 0;
      await mount(
        tester,
        ProjectPicker<OccasionModel>(
          items: items,
          itemIdBuilder: (item) => item.link,
          itemTitleBuilder: (item) => item.title!,
          itemDateBuilder: (item) => item.startTime,
          happeningNowText: 'Now',
          upcomingText: 'Upcoming',
          pastText: 'Past',
          hintText: 'Search',
          createNewText: 'New event',
          onItemSelected: (_) {},
          onCreateNew: () => created++,
          onDismiss: () => dismissed++,
        ),
      );
      final names = [
        'ongoing',
        'sooner',
        'later',
        'recent',
        'older',
        'dateless',
      ];
      for (var i = 0; i < names.length - 1; i++) {
        expect(
          tester.getTopLeft(find.text(names[i])).dy,
          lessThan(tester.getTopLeft(find.text(names[i + 1])).dy),
        );
      }
      await tester.tap(find.text('New event'));
      expect(created, 1);
      expect(dismissed, 1);
    },
  );
  testWidgets(
    'the grouped chooser fits a narrow dialog and scrolls long organizations',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final bytes = await File('fonts/Futura PT Book.ttf').readAsBytes();
        await (FontLoader(
          'PickerPreview',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
      final key = GlobalKey();
      final now = DateTime.now();
      Widget picker() => HelpOccasionPicker(
        occasions: [
          for (var i = 0; i < 12; i++)
            event(
              'event-$i',
              i < 8 ? 1 : 2,
              now.add(Duration(days: i - 4)),
              title: 'Slavnostní ples ${now.year + i}',
            ),
        ],
        organizers: [
          UnitModel(id: 1, title: 'Kulturní spolek Červená Lhota'),
          UnitModel(id: 2, title: 'Druhá organizace'),
        ],
        onSelected: (_) {},
        onDismiss: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'PickerPreview',
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: AppAlertDialog(
                title: const Text(
                  'Pro kterou akci chcete otevřít administraci?',
                ),
                content: SizedBox(width: 480, height: 320, child: picker()),
                actions: [
                  AppDialogActions(
                    leading: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add),
                        label: const Text('Založit novou akci'),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () {}, child: const Text('Zrušit')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final search = tester.getRect(find.byType(TextField));
      expect(search.left, greaterThanOrEqualTo(0));
      expect(search.right, lessThanOrEqualTo(320));
      expect(
        tester.getRect(find.text('Zrušit')).bottom,
        lessThanOrEqualTo(640),
      );
      if (Platform.environment['FESTAPP_PICKER_CAPTURE_DIR']
          case final String folder) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(folder).create(recursive: true);
          await File('$folder/grouped-help-mobile.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
}
