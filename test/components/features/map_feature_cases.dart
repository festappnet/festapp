import '../../support/fixtures/localization_log_fixture.dart';
import 'package:fstapp/components/features/feature_settings_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/features/map_feature.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  group('OfflineMapRenderer', () {
    test('missing configuration defaults to MapLibre', () {
      final layer = MapLayer.fromJson(const {});

      expect(layer.offlineMapRenderer, OfflineMapRenderer.maplibre);
      expect(layer.hasExplicitOfflineMapRenderer, isFalse);
    });

    test('complete pre-migration offline contract stays on Legacy', () {
      final layer = MapLayer.fromJson({
        FeatureConstants.forceOfflineMap: true,
        FeatureConstants.offlineMapPackageURL: 'https://maps.test/map.mbtiles',
        FeatureConstants.offlineMapStyleURL: 'https://maps.test/style.json',
        FeatureConstants.offlineMapLayerName: 'openmaptiles',
      });

      expect(layer.offlineMapRenderer, OfflineMapRenderer.legacy);
      expect(layer.hasExplicitOfflineMapRenderer, isFalse);
      expect(layer.mapBaseMode, MapBaseMode.legacy);
    });

    test('parses and serializes both renderer values', () {
      for (final renderer in OfflineMapRenderer.values) {
        final layer = MapLayer.fromJson({
          FeatureConstants.offlineMapRenderer: renderer.wireValue,
          FeatureConstants.offlineMapPackageURL:
              'https://maps.test/map.mbtiles',
        });

        expect(layer.offlineMapRenderer, renderer);
        expect(layer.hasExplicitOfflineMapRenderer, isTrue);
        expect(
          layer.toJson()[FeatureConstants.offlineMapRenderer],
          renderer.wireValue,
        );
      }
    });

    test('explicit Legacy survives an empty-configuration round trip', () {
      final layer = MapLayer(offlineMapRenderer: OfflineMapRenderer.legacy);

      final restored = MapLayer.fromJson(layer.toJson());

      expect(restored.offlineMapRenderer, OfflineMapRenderer.legacy);
    });

    test('rejects unknown renderer instead of falling back', () {
      expect(
        () => MapLayer.fromJson(const {
          FeatureConstants.offlineMapRenderer: 'automatic',
        }),
        throwsFormatException,
      );
    });

    test('renderer switch preserves both rollback configurations', () {
      final layer = MapLayer(
        offlineMapRenderer: OfflineMapRenderer.maplibre,
        offlineMapBundleManifestURL: 'https://maps.test/manifest.json',
        offlineMapPackageURL: 'https://maps.test/map.mbtiles',
        offlineMapStyleURL: 'https://maps.test/style.json',
        offlineMapLayerName: 'openmaptiles',
      );

      layer.offlineMapRenderer = OfflineMapRenderer.legacy;
      final restored = MapLayer.fromJson(layer.toJson());

      expect(restored.offlineMapRenderer, OfflineMapRenderer.legacy);
      expect(
        restored.offlineMapBundleManifestURL,
        'https://maps.test/manifest.json',
      );
      expect(restored.offlineMapPackageURL, 'https://maps.test/map.mbtiles');
      expect(restored.offlineMapStyleURL, 'https://maps.test/style.json');
      expect(restored.offlineMapLayerName, 'openmaptiles');
    });

    test('three base modes map onto the compatible wire fields', () {
      final layer = MapLayer(offlineMapRenderer: OfflineMapRenderer.legacy);

      expect(layer.mapBaseMode, MapBaseMode.online);

      layer.mapBaseMode = MapBaseMode.maplibre;
      expect(layer.forceOfflineMap, isTrue);
      expect(layer.offlineMapRenderer, OfflineMapRenderer.maplibre);

      layer.mapBaseMode = MapBaseMode.legacy;
      expect(layer.forceOfflineMap, isTrue);
      expect(layer.offlineMapRenderer, OfflineMapRenderer.legacy);

      layer.mapBaseMode = MapBaseMode.online;
      expect(layer.forceOfflineMap, isFalse);
      expect(layer.offlineMapRenderer, OfflineMapRenderer.legacy);
    });

    testWidgets('occasion settings selects an explicit base map mode',
        (tester) async {
      final feature = MapFeature.getDefault();
      feature.offlineMapLayer.offlineMapRenderer = OfflineMapRenderer.legacy;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            child: SingleChildScrollView(
              child: Builder(
                  builder: (context) => buildFeatureSettingsEditor(
                      context, feature,
                      occasionId: 1)),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pumpAndSettle();
      final modeDropdown = find.byType(DropdownButtonFormField<MapBaseMode>);
      await tester.ensureVisible(modeDropdown);
      await tester.tap(modeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(FeaturesStrings.mapBaseModeMapLibre).last);
      await tester.pumpAndSettle();

      expect(feature.offlineMapLayer.forceOfflineMap, isTrue);
      expect(
        feature.offlineMapLayer.offlineMapRenderer,
        OfflineMapRenderer.maplibre,
      );
    });

    testWidgets('MapLibre cannot be saved without a bundle manifest',
        (tester) async {
      final formKey = GlobalKey<FormState>();
      final feature = MapFeature.getDefault();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Builder(
                  builder: (context) => buildFeatureSettingsEditor(
                      context, feature,
                      occasionId: 1)),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pumpAndSettle();
      await _selectBaseMode(tester, MapBaseMode.maplibre);

      expect(formKey.currentState!.validate(), isFalse);

      final manifestField = find.widgetWithText(
        TextFormField,
        FeaturesStrings.offlineMapBundleManifestUrl,
      );
      await tester.enterText(manifestField, 'http://maps.test/manifest.json');

      expect(formKey.currentState!.validate(), isFalse);

      await tester.enterText(manifestField, 'https://maps.test/manifest.json');

      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('Legacy cannot be saved without its complete map contract',
        (tester) async {
      final formKey = GlobalKey<FormState>();
      final feature = MapFeature.getDefault();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Builder(
                  builder: (context) => buildFeatureSettingsEditor(
                      context, feature,
                      occasionId: 1)),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pumpAndSettle();
      await _selectBaseMode(tester, MapBaseMode.legacy);

      expect(formKey.currentState!.validate(), isFalse);

      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          FeaturesStrings.offlineMapPackageUrl,
        ),
        'https://maps.test/map.mbtiles',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          FeaturesStrings.offlineMapStyleUrl,
        ),
        'https://maps.test/style.json',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          FeaturesStrings.offlineMapLayerName,
        ),
        'openmaptiles',
      );

      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('Online base mode does not require an offline contract',
        (tester) async {
      final formKey = GlobalKey<FormState>();
      final feature = MapFeature.getDefault();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Builder(
                  builder: (context) => buildFeatureSettingsEditor(
                      context, feature,
                      occasionId: 1)),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pumpAndSettle();

      expect(feature.offlineMapLayer.mapBaseMode, MapBaseMode.online);
      expect(formKey.currentState!.validate(), isTrue);
      expect(
        find.widgetWithText(
          TextFormField,
          FeaturesStrings.offlineMapBundleManifestUrl,
        ),
        findsNothing,
      );
    });
  });
}

Future<void> _selectBaseMode(
  WidgetTester tester,
  MapBaseMode mode,
) async {
  final label = switch (mode) {
    MapBaseMode.online => FeaturesStrings.mapBaseModeOnline,
    MapBaseMode.legacy => FeaturesStrings.mapBaseModeLegacy,
    MapBaseMode.maplibre => FeaturesStrings.mapBaseModeMapLibre,
  };
  final dropdown = find.byType(DropdownButtonFormField<MapBaseMode>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
