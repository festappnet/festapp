import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:async';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/organization/organization_admin_guard.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:festapp_core/time.dart' as tz;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../support/fixtures/root_supabase_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RootSupabaseFixture backend;
  Completer<bool>? contextResult;
  setUpAll(() async {
    tz.OccasionTimeContext.initializeTimeZones();
    backend = await RootSupabaseFixture.open((request) async {
      if (request.url.path == '/rest/v1/rpc/get_app_config_v219') {
        expect(jsonDecode(request.body)['data_in']['organization'],
            AppConfig.organization);
        expect(request.headers['authorization'], startsWith('Bearer '));
        final granted = await contextResult!.future;
        return http.Response(
            jsonEncode({
              'code': 200,
              'capabilities': {
                AuthorizationCapabilities.organizationSettingsWrite: granted
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request);
      }
      return http.Response('{}', 200, request: request);
    });
    const actor = '00000000-0000-4000-8000-000000000001';
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'sub': actor,
    })));
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token':
          '${base64Url.encode(utf8.encode('{}'))}.$payload.signature',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': actor,
        'aud': 'authenticated',
        'role': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z'
      }
    }));
  });
  tearDownAll(() => backend.dispose());

  setUp(() {
    PackageInfo.setMockInitialValues(
        appName: 'Fixture',
        packageName: 'fixture',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
  });

  testWidgets(
      'direct organization entry loads its missing context before allowing or denying access',
      (tester) async {
    for (final initialContext in <OccasionLinkModel?>[
      null,
      // Startup restores cached settings as a non-null context with no rights.
      OccasionLinkModel(code: 200),
      OccasionLinkModel(code: 200, capabilities: {'orders.read': true}),
    ]) {
      for (final granted in [true, false]) {
        PackageInfo.setMockInitialValues(
            appName: 'Fixture',
            packageName: 'fixture',
            version: '1.0.0',
            buildNumber: '1',
            buildSignature: '');
        final previous = RightsService.occasionLinkModel;
        addTearDown(
            () => RightsService.occasionLinkModelNotifier.value = previous);
        RightsService.occasionLinkModelNotifier.value = initialContext;
        contextResult = Completer<bool>();
        final requests = backend.requests.length;
        await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
            home: OrganizationAdminGuard(
                targetOrganizationId: AppConfig.organization,
                builder: (_, org) => Text('organization-$org'))));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Access Denied'), findsNothing);
        contextResult!.complete(granted);
        await tester.pumpAndSettle();
        expect(find.text('organization-${AppConfig.organization}'),
            granted ? findsOneWidget : findsNothing);
        expect(find.text('Access Denied'),
            granted ? findsNothing : findsOneWidget);
        expect(
            backend.requests
                .skip(requests)
                .where((r) => r.url.path == '/rest/v1/rpc/get_app_config_v219'),
            hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets(
      'organization guard follows scoped projection and immediate revocation without a preflight',
      (tester) async {
    final previous = RightsService.occasionLinkModel;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
    final requests = backend.requests.length;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        unit: UnitModel(id: 8, organization: AppConfig.organization),
        capabilities: {
          AuthorizationCapabilities.organizationSettingsWrite: true
        });
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: OrganizationAdminGuard(
            targetOrganizationId: AppConfig.organization,
            builder: (_, org) => Text('organization-$org'))));
    expect(find.text('organization-${AppConfig.organization}'), findsOneWidget);
    RightsService.invalidateCapabilities();
    await tester.pump();
    expect(find.text('Access Denied'), findsOneWidget);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        unit: UnitModel(id: 8, organization: AppConfig.organization),
        capabilities: {
          AuthorizationCapabilities.organizationSettingsWrite: true
        });
    await tester.pump();
    expect(find.text('organization-${AppConfig.organization}'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: OrganizationAdminGuard(
            targetOrganizationId: AppConfig.organization + 1,
            builder: (_, org) => Text('organization-$org'))));
    expect(find.text('Access Denied'), findsOneWidget);
    expect(backend.requests.length, requests);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
