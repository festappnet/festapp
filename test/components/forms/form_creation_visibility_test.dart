import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/time.dart' as tz;
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/form_tab.dart';
import 'package:fstapp/components/forms/views/forms_tab.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/rights_context_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

class _VisibilityRouter extends RootStackRouter {
  _VisibilityRouter(this.detail);
  final bool detail;
  static final forms = [
    FormEditorDraft(id: 1, link: 'selected', title: 'Selected').toBundle(),
    FormEditorDraft(id: 2, link: 'second', title: 'Second').toBundle(),
  ];
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      path: detail
          ? '/:{occasionLink}/forms/:formLink'
          : '/:{occasionLink}/forms',
      page: PageInfo(
        detail ? FormDetailRoute.name : FormsListRoute.name,
        builder: (_) => detail
            ? FormDetailPage(
                formLink: 'selected',
                loadForms: (_) async => forms,
              )
            : FormsListView(loadForms: (_) async => forms),
      ),
      children: detail
          ? [
              AutoRoute(
                path: '',
                initial: true,
                page: PageInfo(
                  'VisibilityContentRoute',
                  builder: (_) => const Text('Readable form'),
                ),
              ),
            ]
          : null,
    ),
  ];
}

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(tz.OccasionTimeContext.initializeTimeZones);
  final environment = WidgetEnvironmentFixture(
    locale: const Locale('en'),
    translations: jsonDecode(
      File('assets/translations/en.json').readAsStringSync(),
    ),
  );
  for (final detail in [false, true]) {
    for (final canCreate in [false, true]) {
      testWidgetsWithEnvironment(
        () => environment,
        '${detail ? 'detail' : 'list'} creates forms only with the server capability $canCreate',
        (tester) async {
          final state = RightsContextFixture(
            context: OccasionLinkModel(
              capabilities: {
                'forms.catalog.read': true,
                'forms.create': canCreate,
              },
            ),
          );
          addTearDown(state.dispose);
          RightsService.currentLink = 'occasion-a';
          final router = _VisibilityRouter(detail);
          await environment.pumpWidget(
            tester,
            MaterialApp.router(
              builder: DependencyMaterialBridge.builder,
              routerConfig: router.config(
                deepLinkBuilder: (_) => DeepLink.path(
                  '/occasion-a/forms${detail ? '/selected' : ''}',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(FormStrings.createNewForm),
            canCreate ? findsOneWidget : findsNothing,
          );
          if (!detail)
            expect(
              find.byType(PopupMenuButton<String>),
              canCreate ? findsNWidgets(2) : findsNothing,
            );
          if (detail) expect(find.text('Readable form'), findsOneWidget);
        },
      );
    }
  }
}
