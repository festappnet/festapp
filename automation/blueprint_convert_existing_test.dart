// Explicit offline migration gate. Input/output stay private; writes no backend.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_legacy_converter.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_contract.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all frozen existing blueprints convert losslessly to canonical Basic', () {
    const inputPath = String.fromEnvironment('BLUEPRINT_LEGACY_INPUT');
    const assetsPath = String.fromEnvironment('BLUEPRINT_LEGACY_ASSETS');
    const outputPath = String.fromEnvironment('BLUEPRINT_LEGACY_OUTPUT');
    const reviewedPath = String.fromEnvironment('BLUEPRINT_LEGACY_REVIEWED');
    const nativePath = String.fromEnvironment('BLUEPRINT_LEGACY_NATIVE');
    const fontsPath = String.fromEnvironment('BLUEPRINT_LEGACY_FONTS');
    const requestsPath=String.fromEnvironment('BLUEPRINT_LEGACY_REQUESTS_OUTPUT');
    final requests=<String,Map<String,dynamic>>{};
    if (inputPath.isEmpty || assetsPath.isEmpty || outputPath.isEmpty) {
      throw StateError('Explicit private input, processed assets and output required');
    }
    final inputBytes = File(inputPath).readAsBytesSync();
    final input = jsonDecode(utf8.decode(inputBytes)) as Map<String, dynamic>;
    final reviewed = jsonDecode(File(reviewedPath).readAsStringSync()) as Map;
    final assets = (jsonDecode(File(assetsPath).readAsStringSync()) as Map)['assets'] as Map;
    final fontResources = Map<String, dynamic>.from(jsonDecode(File(fontsPath).readAsStringSync()) as Map);
    final catalog = jsonDecode(File('supabase/functions/_shared/ticket-assets/font-catalog.json').readAsStringSync()) as Map;
    final families = {for (final family in catalog['families'] as List)
      family['id'] as String: Map<String, dynamic>.from(family as Map)};
    if (fontResources['protocol'] != 2) throw StateError('canonical_text_resources_required');
    final nativePlans = (jsonDecode(File(nativePath).readAsStringSync()) as Map)['blueprints'] as Map;
    final records = (input['blueprints'] as List).cast<Map>();
    expect(records.length, input['allBlueprintCount']);
    final converted = <Map<String, dynamic>>[];
    var seats = 0, backgrounds = 0, unassigned = 0, empty = 0, nativeCount = 0, tables = 0;
    for (final row in records) {
      final source = Map<String, dynamic>.from(row);
      final before = jsonEncode(source);
      final id = source['id'];
      final assetEntry = assets['$id'] as Map?;
      final model = BlueprintModel.fromLegacyJson(source);
      final nativePlan = nativePlans['$id'] == null ? null : Map<String, dynamic>.from(nativePlans['$id'] as Map);
      final conversion = convertLegacyBlueprint(model, fontFamilies: families,
          nativePlan: nativePlan, reviewedSourceSha256: source['conversionSourceSha256'] as String);
      final result = conversion.snapshot;
      final sourceSpots = (source['spots'] as List? ?? const []).cast<Map>();
      final sourceById = {for (final spot in sourceSpots) spot['id']: spot};
      expect(result.seatBindings.values.map((s) => s.spotId).toSet(), sourceById.keys.toSet(), reason: 'stable identities blueprint$id');
      for (final binding in result.seatBindings.values) {
        final original = sourceById[binding.spotId]!;
        expect(binding.productId, original['product'], reason: 'product blueprint$id/spot${binding.spotId}');
        expect(binding.title, original['title'] ?? '', reason: 'label blueprint$id/spot${binding.spotId}');
        if (binding.productId == null) unassigned++;
      }
      expect(validateDocument(result.document), isEmpty, reason: 'valid geometry blueprint$id');
      expect(result.document.background, isNull, reason: 'no bitmap hall blueprint$id');
      for (final raw in (nativePlan?['nodes'] as List? ?? const []).cast<Map>().where((n) => n['pathPattern'] == 'zigzag')) {
        final originalPoints = raw['points'] ?? (raw['properties'] as Map?)?['points'];
        expect(result.document.nodes.any((n) => n.kind == 'shape' && n.properties['shape'] == 'polyline' && jsonEncode(n.properties['points']) == jsonEncode(originalPoints)), isTrue, reason: 'exact zigzag endpoints blueprint$id');
      }
      if(requestsPath.isEmpty) {expect(compileScene(result.document,resources:fontResources)['issues'],isEmpty,reason:'real font and scene blueprint$id');}
      else {for(final request in collectTextRequests(result.document,families,includePresets:true).values)requests[request.id]=request.toJson();}
      for (final table in result.document.nodes.where((n) => n.kind == 'table')) {
        final expectedFill = const {22:'#574569FF',32:'#574569FF',87:'#574569FF',25:'#FFFFFFFF',33:'#FFFFFFFF',59:'#FFFFFFFF',27:'#D4D4D4FF',91:'#D4D4D4FF'}[id] ?? '#D0D5C9FF';
        expect(effectiveNodeProperties(result.document, table)['fill'], expectedFill);
        expect(effectiveNodeProperties(result.document, table)['cornerRadius'], 8, reason: 'blueprint$id styles=${result.document.styles} local=${table.style}');
        expect(effectiveNodeProperties(result.document, table)['stroke'], '#000000FF');
      }
      if (nativePlan != null) nativeCount++;
      tables += result.document.nodes.where((n) => n.kind == 'table').length;
      final sourceObjects = {for (final obj in (source['objects'] as List? ?? const []).cast<Map>()) obj['id']: obj};
      for (final binding in result.seatBindings.values) {
        final node = result.document.nodes.firstWhere((n) => n.id == binding.nodeId);
        final world = worldMatrix(result.document, node);
        final old = sourceObjects[binding.spotId]!;
        expect(world[4], closeTo((old['x'] as num) * 48 + 24, .005));
        expect(world[5], closeTo((old['y'] as num) * 48 + 24, .005));
      }
      expect(result.document.styles['kinds']?['seat'], layoutAppearancePresets['Original']!.seats);
      expect(result.document.nodes.where((n) => n.kind == 'seat').every((n) => n.properties['shape'] == 'roundedRect'), true);
      final reopened = VenueLayoutDocument.fromJson(result.document.toJson());
      expect(reopened.toJson(), result.document.toJson(), reason: 'canonical roundtrip blueprint$id');
      expect(convertLegacyBlueprint(model, fontFamilies: families, nativePlan: nativePlan, reviewedSourceSha256: source['conversionSourceSha256'] as String).snapshot.document.toJson(), result.document.toJson(), reason: 'deterministic blueprint$id');
      expect(jsonEncode(source), before, reason: 'source immutable blueprint$id');
      final request=requestsPath.isEmpty?BlueprintLayoutSaveRequest(snapshot:result,baseline:result.copyWith(seatBindings:{},groupProducts:{}),resources:fontResources).toJson():{'layout':result.document.toJson()};
      final layoutBytes = utf8.encode(jsonEncode(result.document.toJson()));
      converted.add({
        'blueprintId': id, 'occasionId': source['occasion'], 'organizationId': source['organization'],
        'sourceSha256': source['conversionSourceSha256'],
        'importReceipt': conversion.receipt,
        'reviewedSourceText': reviewed['$id'],
        'layoutSha256': sha256.convert(layoutBytes).toString(),
        'appearancePreset': 'Original', 'appearanceName': 'Basic',
        'request': request,
        if (assetEntry != null) 'reviewedAsset': assetEntry,
        if (nativePlan != null) 'reviewedNativePlan': nativePlan,
      });
      seats += result.seatBindings.length;
      if (result.seatBindings.isEmpty) empty++;
      if (result.document.background != null) backgrounds++;
    }
    final output = {
      'sourceExportSha256': sha256.convert(inputBytes).toString(),
      'allBlueprintCount': records.length, 'convertedCount': converted.length,
      'stableSpotCount': seats, 'unassignedSpotCount': unassigned,
      'backgroundCount': backgrounds, 'nativeArtworkCount': nativeCount, 'nativeTableCount': tables, 'emptyBlueprintCount': empty,
      'productionApplied':false,'textPreparationPending':requestsPath.isNotEmpty,'blueprints':converted,
    };
    File(outputPath).writeAsStringSync(jsonEncode(output));
    if(requestsPath.isNotEmpty)File(requestsPath).writeAsStringSync(jsonEncode(requests.values.toList()));
    expect(converted.length, records.length);
    // Geometry/business source only. No customer/order/hold data is imported.
    print('${requestsPath.isEmpty?'PASS':'PREPARED GEOMETRY - TEXT PENDING'} ${converted.length}/${records.length} canonical Basic layouts; $seats stable spots; $unassigned unassigned; $nativeCount native halls/$tables tables, $backgrounds raster backgrounds; $empty empty layouts');
  });
}
