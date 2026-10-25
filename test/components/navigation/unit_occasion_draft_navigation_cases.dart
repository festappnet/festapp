import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/html/html_strings.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/views/occasions_screen.dart';
import 'package:super_editor/super_editor.dart';

late WidgetEnvironmentFixture _environment;

class _UnitOccasionRouter extends RootStackRouter {
  final coordinator = HtmlSaveCoordinator();
  @override
  List<AutoRouteGuard> get guards => [RetainedDraftGuard.instance];
  @override
  List<AutoRoute> get routes => [
        AutoRoute(
            path: '/unit/:id/edit',
            page: PageInfo(UnitAdminRoute.name,
                builder: (_) => const RoutedTabScaffold(tabs: [
                      RoutedTabDefinition(
                          slug: 'occasions',
                          route: UnitOccasionsRoute(),
                          label: 'Occasions',
                          icon: Icons.event),
                      RoutedTabDefinition(
                          slug: 'email-templates',
                          route: UnitEmailTemplatesRoute(),
                          label: 'Templates',
                          icon: Icons.mail),
                    ])),
            children: [
              AutoRoute(
                  path: 'occasions',
                  page: PageInfo(UnitOccasionsRoute.name,
                      builder: (_) => OccasionsScreen(
                              unit: UnitModel(id: 8),
                              initialOccasions: [
                                OccasionModel(
                                    id: 1,
                                    title: 'Festival',
                                    link: 'festival',
                                    startTime: DateTime(2026, 10, 1),
                                    endTime: DateTime(2026, 11, 1),
                                    isOpen: true,
                                    isHidden: false,
                                    isPromoted: false,
                                    features: [
                                      FormFeature(code: 'form', isEnabled: true)
                                    ]),
                              ]))),
              AutoRoute(
                  path: 'email-templates',
                  page: PageInfo(UnitEmailTemplatesRoute.name,
                      builder: (_) => Material(
                          child: HtmlEditingScope(
                              coordinator: coordinator,
                              child: SingleChildScrollView(
                                  child: EditableHtmlField(
                                html: '<p contenteditable="true">Original</p>',
                                onChanged: (_) {},
                              )))))),
            ]),
        AutoRoute(
            path: '/:link/reservations',
            page: PageInfo(ReservationsRoute.name,
                builder: (_) => const Scaffold(body: Text('FESTIVAL ORDERS')))),
      ];
}

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() async {
    await initializeDateFormatting();
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  for (final edit in [null, false, true]) {
    testWidgetsWithEnvironment(() => _environment,
        'unit occasion card prompts only for user edits ($edit)',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = _UnitOccasionRouter();
      await _environment.pumpWidget(
          tester,
          MaterialApp.router(builder: DependencyMaterialBridge.builder,
              routerConfig: router.config(
            deepLinkBuilder: (_) =>
                const DeepLink.path('/unit/8/edit/email-templates'),
          )));
      await tester.pumpAndSettle();
      RichHtmlEditorController? controller;
      if (edit != null) {
        await tester.tap(find.byIcon(Icons.edit));
        await tester.pumpAndSettle();
        controller = tester
            .widget<RichHtmlEditor>(find.byType(RichHtmlEditor))
            .controller;
        expect(controller.hasUserChanges, isFalse);
        expect(controller.html, isNot(contains('contenteditable')),
            reason: 'The fixture exercises load-time sanitization');
        expect(
            tester
                .widget<FilledButton>(
                    find.widgetWithText(FilledButton, CommonStrings.save))
                .onPressed,
            isNull);
        if (edit == true) {
          final node = controller.editor.document.first as TextNode;
          controller.editor.execute([
            InsertTextRequest(
                documentPosition: DocumentPosition(
                    nodeId: node.id,
                    nodePosition: const TextNodePosition(offset: 0)),
                textToInsert: 'Changed ',
                attributions: {})
          ]);
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.text('Occasions'));
      await tester.pumpAndSettle();
      expect(router.currentUrl, '/unit/8/edit/occasions');
      await tester.tap(find.text('Festival'));
      await tester.pumpAndSettle();
      if (edit == true) {
        expect(find.text(HtmlStrings.discardDraft), findsOneWidget);
        await tester.tap(find.text(CommonStrings.storno));
        await tester.pumpAndSettle();
        expect(router.currentUrl, '/unit/8/edit/occasions');
        await tester.tap(find.text('Templates'));
        await tester.pumpAndSettle();
        expect(controller!.hasUserChanges, isTrue);
      } else {
        expect(find.text(HtmlStrings.discardDraft), findsNothing);
        expect(find.text('FESTIVAL ORDERS'), findsOneWidget);
      }
      await _environment.pumpWidget(tester, const SizedBox.shrink());
      router.dispose();
      router.coordinator.dispose();
    });
  }
}
