import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/news/news_form_page.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  testWidgets('keeps form actions in the keyboard avoiding scroll body',
      (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(MaterialApp(
        home: NewsFormPage(
            editorOverride: const SizedBox(height: 200),
            onSubmit: (_) async {})));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.bottomNavigationBar, isNull);
    expect(
        find.ancestor(
            of: find.text('Common.storno'),
            matching: find.byType(SingleChildScrollView)),
        findsOneWidget);
  });
  testWidgets('uses the shared Super Editor and refuses empty submission',
      (tester) async {
    var submissions = 0;
    await tester.pumpWidget(MaterialApp(home: NewsFormPage(onSubmit: (_) async {
      submissions++;
    })));
    expect(find.byType(RichHtmlEditor), findsOneWidget);
    expect(find.byType(SuperEditor), findsOneWidget);
    await tester.tap(find.text('FeatureNews.notificationAudienceSelf'));
    await tester.pump();
    await tester.ensureVisible(find.text('FeatureNews.publishAndSendSelf'));
    await tester.tap(find.text('FeatureNews.publishAndSendSelf'));
    await tester.pump();
    expect(find.text('FeatureNews.contentRequired'), findsOneWidget);
    expect(submissions, 0);
  });
  testWidgets('publish awaits the typed writer and closes only after success',
      (tester) async {
    final completed = Completer<void>();
    var submissions = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    child: const Text('Compose'),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                NewsFormPage(onSubmit: (submission) async {
                                  submissions++;
                                  expect(submission.addToNews, true);
                                  expect(submission.withNotification, false);
                                  await completed.future;
                                }))))))));
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
    controller.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: controller.editor.document.first.id,
              nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'A message',
          attributions: {})
    ]);
    await tester.pump();
    await tester
        .ensureVisible(find.text('FeatureNews.newsWithoutNotification'));
    await tester.tap(find.text('FeatureNews.newsWithoutNotification'));
    await tester.pump();
    await tester
        .ensureVisible(find.text('FeatureNews.publishWithoutNotification'));
    await tester.tap(find.text('FeatureNews.publishWithoutNotification'));
    await tester.pump();
    expect(submissions, 1);
    expect(find.byType(NewsFormPage), findsOneWidget);
    await tester.tap(find.text('FeatureNews.publishWithoutNotification'));
    await tester.pump();
    expect(submissions, 1);
    completed.complete();
    await tester.pumpAndSettle();
    expect(find.byType(NewsFormPage), findsNothing);
  });
  testWidgets('unknown publish retains the draft and disables a new command',
      (tester) async {
    var submissions = 0;
    await tester.pumpWidget(MaterialApp(home: NewsFormPage(onSubmit: (_) async {
      submissions++;
      throw http.ClientException('response lost');
    })));
    final controller =
        tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
    controller.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: controller.editor.document.first.id,
              nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'Keep draft',
          attributions: {})
    ]);
    await tester.pump();
    await tester
        .ensureVisible(find.text('FeatureNews.newsWithoutNotification'));
    await tester.tap(find.text('FeatureNews.newsWithoutNotification'));
    await tester.pump();
    await tester
        .ensureVisible(find.text('FeatureNews.publishWithoutNotification'));
    await tester.tap(find.text('FeatureNews.publishWithoutNotification'));
    await tester.pumpAndSettle();
    expect(find.text('HtmlEditor.unknownPublish'), findsOneWidget);
    expect(controller.html, contains('Keep draft'));
    await tester
        .ensureVisible(find.text('FeatureNews.publishWithoutNotification'));
    await tester.tap(find.text('FeatureNews.publishWithoutNotification'));
    await tester.pump();
    expect(submissions, 1);
  });
  testWidgets('cancelled notification confirmation does not invoke the writer',
      (tester) async {
    var submissions = 0;
    await tester.pumpWidget(MaterialApp(home: NewsFormPage(onSubmit: (_) async {
      submissions++;
    })));
    final controller =
        tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
    controller.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: controller.editor.document.first.id,
              nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'Self test',
          attributions: {})
    ]);
    await tester.pump();
    await tester
        .ensureVisible(find.text('FeatureNews.notificationAudienceSelf'));
    await tester.tap(find.text('FeatureNews.notificationAudienceSelf'));
    await tester.pump();
    await tester.ensureVisible(find.text('FeatureNews.publishAndSendSelf'));
    await tester.tap(find.text('FeatureNews.publishAndSendSelf'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextButton)));
    await tester.pumpAndSettle();
    expect(submissions, 0);
    expect(controller.html, contains('Self test'));
    expect(find.byType(NewsFormPage), findsOneWidget);
  });
}
