import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'package:fstapp/components/occasion_settings/occasion_advanced_settings.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() => environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>,
      ));
  testWidgetsWithEnvironment(() => environment,
      'occasion address follows app support without hiding other advanced settings',
      (tester) async {
    final link = TextEditingController();
    final email = TextEditingController();
    addTearDown(link.dispose);
    addTearDown(email.dispose);
    final form = GlobalKey<FormState>();
    var linkSaves = 0;
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
          body: SingleChildScrollView(
              child: Form(
                  key: form,
                  child: OccasionAdvancedSettings(
                    linkController: link,
                    replyToEmailController: email,
                    selectedTimezone: 'UTC',
                    allTimezones: const ['UTC'],
                    isEditingEnabled: true,
                    initiallyExpanded: true,
                    onExpansionChanged: (_) {},
                    onTimezoneSelected: (_) {},
                    onLinkChanged: (_) {},
                    onLinkSaved: (_) => linkSaves++,
                  ))),
        )));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is TextFormField && w.controller == link),
        AppConfig.isAppSupported ? findsOneWidget : findsNothing);
    expect(find.byType(PublicLink),
        AppConfig.isAppSupported ? findsOneWidget : findsNothing);
    expect(
        find.byWidgetPredicate(
            (w) => w is TextFormField && w.controller == email),
        findsOneWidget);
    expect(form.currentState!.validate(), !AppConfig.isAppSupported);
    form.currentState!.save();
    expect(linkSaves, AppConfig.isAppSupported ? 1 : 0);
  });
}
