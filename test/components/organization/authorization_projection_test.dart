import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/organization/organization_admin_guard.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../support/fixtures/root_supabase_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RootSupabaseFixture backend;
  setUpAll(() async {
    backend = await RootSupabaseFixture.open((request) async =>
        http.Response('{}', 200, request: request));
    const actor = '00000000-0000-4000-8000-000000000001';
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'sub': actor,
    })));
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': '${base64Url.encode(utf8.encode('{}'))}.$payload.signature',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z'}
    }));
  });
  tearDownAll(() => backend.dispose());

  testWidgets('organization guard follows scoped projection and immediate revocation without a preflight', (tester) async {
    final previous = RightsService.occasionLinkModel;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
    final requests = backend.requests.length;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        unit: UnitModel(id: 8, organization: AppConfig.organization),
        capabilities: {AuthorizationCapabilities.organizationSettingsWrite: true});
    await tester.pumpWidget(MaterialApp(home: OrganizationAdminGuard(
        targetOrganizationId: AppConfig.organization,
        builder: (_, org) => Text('organization-$org'))));
    expect(find.text('organization-${AppConfig.organization}'), findsOneWidget);
    RightsService.invalidateCapabilities();
    await tester.pump();
    expect(find.text('Access Denied'), findsOneWidget);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        unit: UnitModel(id: 8, organization: AppConfig.organization),
        capabilities: {AuthorizationCapabilities.organizationSettingsWrite: true});
    await tester.pump();
    expect(find.text('organization-${AppConfig.organization}'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: OrganizationAdminGuard(
        targetOrganizationId: AppConfig.organization + 1,
        builder: (_, org) => Text('organization-$org'))));
    expect(find.text('Access Denied'), findsOneWidget);
    expect(backend.requests.length, requests);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
