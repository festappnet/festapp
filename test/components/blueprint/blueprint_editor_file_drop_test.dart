import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/_shared/editor_file_drop_region.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_resources.dart';
import 'package:fstapp/components/blueprint/views/blueprint_plan_editor.dart';
import 'package:fstapp/components/images/image_control_client.dart';
import '../../support/editor_file_drop.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  testWidgetsWithEnvironment(() => environment,
      'current Blueprint body drop shares import lock and preserves background on failure',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC');
    final hash = sha256.convert(bytes).toString();
    final asset = <String, dynamic>{
      'assetRef': 'image:$hash',
      'hash': hash,
      'url': 'https://images.example.test/new.png',
      'width': 2,
      'height': 2,
      'mimeType': 'image/png',
      'byteLength': bytes.length
    };
    final controller = VenueLayoutController(VenueLayoutDocument.empty(),
        resources: {'protocol': 2, 'fontFamilies': {}, 'textLayouts': {}});
    addTearDown(controller.dispose);
    var uploads = 0;
    var fail = false;
    var hostBusy = false;
    final pending = Completer<ImageUploadResult>();
    final resolver = BlueprintLayoutAssetResolver(
        client: MockClient((_) async => http.Response.bytes(bytes, 200)));
    await environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
          locale: const Locale('cs'),
          supportedLocales: VenueLayoutLocalizations.supportedLocales,
          localizationsDelegates:
              [...VenueLayoutLocalizations.localizationsDelegates, ...GlobalMaterialLocalizations.delegates],
          home: Scaffold(
              body: BlueprintPlanEditor(
            controller: controller,
            occasionId: 1,
            showGallery: false,
            assetResolver: resolver,
            onBusyChanged: (busy) => hostBusy = busy,
            uploadBitmap: (_) async {
              uploads++;
              if (fail) throw StateError('fixture_upload_failed');
              return pending.future;
            },
          )),
        ));
    await tester.pumpAndSettle();
    final point = tester.getCenter(find.byType(EditorFileDropRegion));
    await pluginDrop(tester, point, [droppedFile('plan.png', bytes)]);
    await pluginDrop(tester, point, [droppedFile('plan.png', bytes)]);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(uploads, 1);
    expect(hostBusy, isTrue);
    expect(controller.document.background, isNull);
    pending.complete(ImageUploadResult(asset['url'] as String, asset: asset));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(controller.document.background, isNotNull);
    expect(controller.document.nodes, isEmpty);
    expect(controller.dirty, isTrue);
    expect(hostBusy, isFalse);
    final old = controller.document.background;
    fail = true;
    await pluginDrop(tester, point, [droppedFile('plan.png', bytes)]);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(uploads, 2);
    expect(controller.document.background, old);
    expect(hostBusy, isFalse);
    // SVG uses the same existing processed-background manifest, never inserts a node.
    fail = false;
    await pluginDrop(tester, point, [
      droppedFile(
          'plan.svg',
          utf8.encode(
              '<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"/>'))
    ]);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(uploads, 3);
    expect(controller.document.background, isNotNull);
    expect(controller.document.nodes, isEmpty);
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.document.background, isNull);
  });
}
