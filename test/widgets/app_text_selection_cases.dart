import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/widgets/app_text_selection.dart';

void main() {
  for (final selectableHtml in [false, true]) {
    testWidgets('copies header, metadata and HTML together ($selectableHtml)',
        (tester) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        builder: DependencyMaterialBridge.wrapBuilder((context, child) =>
            AppTextSelection(enabled: true, child: child!)),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The Klezmatics (USA)'),
              const Text('ST 11. 11. 19:00 - 20:15'),
              HtmlView(
                html: '<p>Slunovrat <b>Winter Edition</b></p>',
                isSelectable: selectableHtml,
                offlineOverride: false,
              ),
              const Text('Sv. Vaclav'),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionArea), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getTopLeft(find.text('The Klezmatics (USA)')) +
            const Offset(1, 8),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(tester.getBottomRight(find.text('Sv. Vaclav')));
      await gesture.up();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(copiedText, contains('The Klezmatics (USA)'));
      expect(copiedText, contains('ST 11. 11. 19:00 - 20:15'));
      expect(copiedText, contains('Slunovrat Winter Edition'));
      expect(copiedText, contains('Sv. Vaclav'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabled selection preserves the child', (tester) async {
    await tester.pumpWidget(const MaterialApp(builder: DependencyMaterialBridge.builder,
      home: AppTextSelection(enabled: false, child: Text('Native content')),
    ));
    expect(find.text('Native content'), findsOneWidget);
    expect(find.byType(SelectionArea), findsNothing);
  });
}
