import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
class _Service extends TicketLayoutService {
 int calls = 0;
 @override Future<TicketLayoutResources> resolve(int occasionId, String type, Map<String,dynamic>? layout, String? background, {bool borrowResourcesOnly=false,bool readOnly=false}) async { calls++; throw StateError('Must not load a second preview'); }
}
void main() {
 testWidgets('editor-only ticket action performs no eager preview request', (tester) async {
  final service = _Service();
  await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home:Scaffold(body:TicketSettings(feature:TicketFeature.fromJson({'code':'ticket','is_enabled':true}),occasionId:0,service:service,readOnly:true,showScannerSettingsLink:false,showPreview:false))));
  await tester.pump();
  expect(service.calls,0);
  expect(tester.takeException(),isNull);
 });
}
