import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:fstapp/components/features/feature_settings_editor.dart';
import 'package:material_ui/material_ui.dart';
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
  group('Map bundle configuration', () {
    test('online is the default base mode', () {
      expect(MapLayer.fromJson(const {}).mapBaseMode, MapBaseMode.online);
    });

    test('obsolete renderer and standalone URLs cannot survive a save', () {
      final layer = MapLayer.fromJson({
        'offlineMapRenderer': 'legacy',
        'offlineMapPackageURL': 'https://maps.test/old.mbtiles',
        'offlineMapStyleURL': 'https://maps.test/old-style.json',
        'offlineMapLayerName': 'openmaptiles',
        FeatureConstants.offlineMapBundleManifestURL:
            'https://maps.test/csmostrava2026/manifest.json',
        FeatureConstants.forceOfflineMap: true,
      });
      final serialized = layer.toJson();
      for (final obsoleteKey in [
        'offlineMapRenderer',
        'offlineMapPackageURL',
        'offlineMapStyleURL',
        'offlineMapLayerName',
      ]) {
        expect(serialized.containsKey(obsoleteKey), isFalse);
      }
      final restored = MapLayer.fromJson(serialized);
      expect(restored.mapBaseMode, MapBaseMode.maplibre);
      expect(restored.offlineMapBundleManifestURL,
          'https://maps.test/csmostrava2026/manifest.json');
    });

    test('switching base mode preserves the canonical offline bundle', () {
      final layer = MapLayer(
        offlineMapBundleManifestURL: 'https://maps.test/manifest.json',
      );
      layer.mapBaseMode = MapBaseMode.maplibre;
      expect(layer.forceOfflineMap, isTrue);
      layer.mapBaseMode = MapBaseMode.online;
      expect(layer.forceOfflineMap, isFalse);
      expect(MapLayer.fromJson(layer.toJson()).offlineMapBundleManifestURL,
          'https://maps.test/manifest.json');
    });

    testWidgets('occasion settings selects an explicit base map mode',
        (tester) async {
      final feature = MapFeature.getDefault();

      await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
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
        feature.offlineMapLayer.mapBaseMode,
        MapBaseMode.maplibre,
      );
    });

    testWidgets('MapLibre cannot be saved without a bundle manifest',
        (tester) async {
      final formKey = GlobalKey<FormState>();
      final feature = MapFeature.getDefault();

      await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
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

    testWidgets('Online base mode does not require an offline contract',
        (tester) async {
      final formKey = GlobalKey<FormState>();
      final feature = MapFeature.getDefault();

      await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
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
      final manifestField = find.widgetWithText(
        TextFormField,
        FeaturesStrings.offlineMapBundleManifestUrl,
      );
      expect(manifestField, findsOneWidget);
      await tester.enterText(manifestField, 'http://maps.test/manifest.json');
      expect(formKey.currentState!.validate(), isFalse);
      await tester.enterText(manifestField, 'https://maps.test/manifest.json');
      expect(formKey.currentState!.validate(), isTrue);
      formKey.currentState!.save();
      expect(feature.offlineMapLayer.offlineMapBundleManifestURL,
          'https://maps.test/manifest.json');
      expect(feature.offlineMapLayer.forceOfflineMap, isFalse);
    });
  });
}

Future<void> _selectBaseMode(
  WidgetTester tester,
  MapBaseMode mode,
) async {
  final label = switch (mode) {
    MapBaseMode.online => FeaturesStrings.mapBaseModeOnline,
    MapBaseMode.maplibre => FeaturesStrings.mapBaseModeMapLibre,
  };
  final dropdown = find.byType(DropdownButtonFormField<MapBaseMode>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
