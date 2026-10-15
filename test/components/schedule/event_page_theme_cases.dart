import '../../support/fixtures/localization_log_fixture.dart';
import 'package:fstapp/components/schedule/event_type_colors.dart';
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/event_page_theme.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test('event colors preserve occasion/unit configuration and fallback', () {
    final previous = RightsService.occasionLinkModelNotifier.value;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
    RightsService.occasionLinkModelNotifier.value = null;
    expect(EventTypeColors.background(null), ThemeConfig.appBarColor());
    expect(EventTypeColors.background('unknown'), ThemeConfig.appBarColor());
    final schedule = ScheduleFeature(isEnabled: false, eventTypes: [
      EventType(code: 'custom', title: 'Custom', colorDefinition: '#123456'),
      EventType(code: 'custom', title: 'Duplicate', colorDefinition: '#FFFFFF'),
      EventType(code: 'seed', title: 'Seed', colorDefinition: 'seed2'),
    ]);
    for (final context in [
      OccasionLinkModel(
          occasion: OccasionModel(
              features: [schedule],
              isOpen: true,
              isHidden: false,
              isPromoted: false)),
      OccasionLinkModel(unit: UnitModel(features: [schedule])),
    ]) {
      RightsService.occasionLinkModelNotifier.value = context;
      expect(EventTypeColors.background('custom'), const Color(0xff123456));
      expect(EventTypeColors.background('seed'), ThemeConfig.seed2);
      expect(EventTypeColors.background('unknown'), ThemeConfig.appBarColor());
      expect(EventTypeColors.foreground('custom'),
          ThemeConfig.textColorForBackground(const Color(0xff123456)));
    }
  });

  test('sliver height does not count the safe area twice', () {
    expect(EventPageTheme.sliverExpandedHeight(320, 59), 261);
  });

  test('collapsed event header follows app brightness', () {
    const base = Color(0xffffa680);

    final light = EventPageTheme.collapsedTint(base, Brightness.light);
    final dark = EventPageTheme.collapsedTint(base, Brightness.dark);

    expect(light.computeLuminance(), greaterThan(0.7));
    expect(dark.computeLuminance(), lessThan(0.2));
  });

  test('signed-in participant pill uses the active primary theme colors', () {
    const primary = Color(0xff123456);
    const onPrimary = Color(0xfffefefe);

    final colors = EventPageTheme.participantPillColors(
      primary: primary,
      onPrimary: onPrimary,
    );

    expect(colors.background, primary);
    expect(colors.foreground, onPrimary);
  });
}
