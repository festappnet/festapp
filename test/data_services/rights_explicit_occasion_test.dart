import '../support/fixtures/client_command_response_fixture.dart';

import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/eshop/eshop_commands.dart';
import 'package:fstapp/components/eshop/product_grid_record.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/navigation/occasion_administration_boundary.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/bank_accounts/supabase_bank_accounts.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/components/users/unit_user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fixtures/root_supabase_fixture.dart';
import '../support/fixtures/local_app_storage_fixture.dart';
import '../support/fixtures/rights_context_fixture.dart';

import 'dart:convert';
import 'dart:async';

import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

// Supabase's storage fixture uses its shared_preferences dependency.
// ignore: depend_on_referenced_packages
import 'package:festapp_core/time.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RootSupabaseFixture fixture;
  final contexts = <Map<String, dynamic>>[];
  var bankDispatches = 0;
  var bankRpcDispatches = 0;
  var unitUserUpdates = 0;
  var contextFailures = 0;
  Completer<void>? contextGate;
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    tz.OccasionTimeContext.initializeTimeZones();
    fixture = await RootSupabaseFixture.open((request) async {
      if (request.url.path == '/auth/v1/logout') {
        return http.Response('', 204, request: request);
      }
      if (request.url.path == '/functions/v1/bank-sync-manage') {
        bankDispatches++;
        return http.Response(
          jsonEncode({'error': 'bank_account_admin_required'}),
          403,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/rest/v1/rpc/manage_bank_authoring') {
        bankRpcDispatches++;
        return http.Response(
          jsonEncode({'code': '42501', 'message': 'Bank role revoked'}),
          403,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/rest/v1/rpc/save_unit_user_client_sync_v1') {
        unitUserUpdates++;
        final input = jsonDecode(request.body) as Map;
        return http.Response(
          jsonEncode(
            commandResponseFixture(
              input['p_command_id'],
              data: {'userId': input['p_user'], 'version': 1},
            ),
          ),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path.startsWith('/rest/v1/rpc/get_app_config_')) {
        final context = (jsonDecode(request.body)['data_in'] as Map)
            .cast<String, dynamic>();
        contexts.add(context);
        await contextGate?.future;
        if (contextFailures > 0) {
          contextFailures--;
          throw http.ClientException('Fixture context unavailable');
        }
        return http.Response(
          jsonEncode({
            'code': context['link'] == 'server-denied' ? 403 : 200,
            if (context['unit_id'] == null)
              'occasion': {'id': 1072557, 'link': context['link'], 'data': {}},
            if (context['unit_id'] != null) 'unit': {'id': context['unit_id']},
            'occasion_user': {'is_editor_view': true},
            'capabilities': {
              'navigation.administration': context['link'] != 'access-revoked',
              if (context['unit_id'] == 12) 'media.unit.write': true,
            },
            if (context['unit_id'] == 12) 'user_info': {'id': 'self-user'},
            if (context['link'] == 'bank-changed')
              'bank_capabilities': {
                '7': {'bank_sync.manage': true},
              },
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      throw StateError('Unexpected fixture request: ${request.url.path}');
    });
  });
  tearDownAll(() => fixture.dispose());
  setUp(() async {
    contexts.clear();
    bankDispatches = 0;
    bankRpcDispatches = 0;
    unitUserUpdates = 0;
    contextFailures = 0;
    contextGate = null;
    final state = RightsContextFixture();
    addTearDown(state.dispose);
    final storage = await LocalAppStorageFixture.open();
    addTearDown(storage.dispose);
  });

  test(
    'an explicit backend denial differs from a failed context request',
    () async {
      await expectLater(
        RightsService.updateAppData(
          link: 'server-denied',
          force: true,
          refreshOffline: false,
        ),
        throwsA(isA<ContextAccessDenied>()),
      );
      contextFailures = 1;
      await expectLater(
        RightsService.updateAppData(
          link: 'access-recovery',
          force: true,
          refreshOffline: false,
        ),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test(
    'explicit administration link survives a configured landing occasion',
    () async {
      await RightsService.updateAppData(
        link: '2025we',
        force: true,
        refreshOffline: false,
      );
      expect(contexts.single['link'], '2025we');
      expect(RightsService.currentLink, '2025we');
      expect(RightsService.canSeeAdministration(), isTrue);
    },
  );

  test('unit administration does not send a forced occasion', () async {
    await RightsService.updateAppData(
      unitId: 999,
      force: true,
      refreshOffline: false,
    );
    expect(contexts.single['unit_id'], 999);
    expect(contexts.single['link'], isNull);
  });

  test('implicit startup keeps the configured landing occasion', () async {
    if (AppConfig.forceOccasionLink == null) return;
    await RightsService.updateAppData(force: true, refreshOffline: false);
    expect(contexts.single['link'], AppConfig.forceOccasionLink);
  });
  test(
    'operation controls consume SQL capabilities and discard them on logout',
    () {
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasionUser: OccasionUserModel(isEditorOrder: true),
      );
      expect(RightsService.canUpdateOrders(), isFalse);
      RightsService.occasionLinkModelNotifier.value =
          OccasionLinkModel.fromJson({
            'capabilities': {
              'orders.read': true,
              'orders.write': true,
              'occasions.write': true,
              'users.write': true,
              'navigation.admin_app': true,
              'invalid': 'true',
            },
          });
      expect(RightsService.canSeeReservations(), isTrue);
      expect(RightsService.canUpdateOrders(), isTrue);
      expect(RightsService.canEditOccasion(), isTrue);
      expect(RightsService.canUpdateUsers(), isTrue);
      expect(RightsService.canSeeAdmin(), isTrue);
      expect(RightsService.hasCapability('invalid'), isFalse);
      expect(RightsService.hasCapability('unknown'), isFalse);
      var notifications = 0;
      void changed() {
        notifications++;
      }

      RightsService.occasionLinkModelNotifier.addListener(changed);
      addTearDown(
        () => RightsService.occasionLinkModelNotifier.removeListener(changed),
      );
      RightsService.invalidateCapabilities();
      expect(notifications, 1);
      expect(RightsService.canUpdateOrders(), isFalse);
      expect(RightsService.canSeeAdmin(), isFalse);
    },
  );
  test('logout publishes cleared identity even without capabilities', () {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      isAdmin: true,
      occasionUser: OccasionUserModel(isEditorOrder: true),
    );
    var notifications = 0;
    void changed() {
      notifications++;
      expect(RightsService.occasionLinkModel?.isAdmin, isFalse);
      expect(RightsService.occasionLinkModel?.occasionUser, isNull);
    }

    RightsService.occasionLinkModelNotifier.addListener(changed);
    addTearDown(
      () => RightsService.occasionLinkModelNotifier.removeListener(changed),
    );
    RightsService.invalidateCapabilities(clearIdentity: true);
    expect(notifications, 1);
  });
  test('navigation uses SQL projection instead of legacy role flags', () {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel.fromJson({
      'occasion_user': {'is_approver': true, 'is_cleaning_crew': true},
    });
    expect(RightsService.canOpenScheduleEntryCheck(), isFalse);
    expect(RightsService.canOpenCleaningCrewWorkspace(), isFalse);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel.fromJson({
      'capabilities': {
        'navigation.schedule_entry_check': true,
        'navigation.cleaning_crew': true,
      },
    });
    expect(RightsService.canOpenScheduleEntryCheck(), isTrue);
    expect(RightsService.canOpenCleaningCrewWorkspace(), isTrue);
    RightsService.invalidateCapabilities();
    expect(RightsService.canOpenScheduleEntryCheck(), isFalse);
    expect(RightsService.canOpenCleaningCrewWorkspace(), isFalse);
  });

  test(
    'resource capabilities bind group and place and invalidate with context',
    () {
      RightsService.occasionLinkModelNotifier.value =
          OccasionLinkModel.fromJson({
            'capabilities': {'map.places.write': false},
            'user_info': {'id': '00000000-0000-0000-0000-000000000001'},
            'groups': {
              '7': {
                'id': 7,
                'title': 'Owned group',
                'place': 70,
                'is_admin': false,
                'capabilities': {'groups.write': true, 'map.place.move': true},
              },
              '8': {
                'id': 8,
                'title': 'Role without projection',
                'place': 80,
                'is_admin': true,
              },
            },
          });
      expect(RightsService.canMovePlace(70), isTrue);
      expect(RightsService.canMovePlace(71), isFalse);
      expect(RightsService.canMovePlace(80), isFalse);
      expect(RightsService.hasGroupCapability(7, 'groups.write'), isTrue);
      expect(RightsService.hasGroupCapability(8, 'groups.write'), isFalse);
      RightsService.invalidateCapabilities();
      expect(RightsService.canMovePlace(70), isFalse);
      expect(RightsService.hasGroupCapability(7, 'groups.write'), isFalse);
    },
  );
  test(
    'permission rejection clears old controls and reloads the same context',
    () async {
      RightsService.currentLink = 'denied-context';
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: const {'orders.write': true},
      );
      final refresh = RightsService.refreshAfterAuthorizationDenial();
      expect(RightsService.canUpdateOrders(), isFalse);
      await refresh;
      expect(contexts, hasLength(1));
      expect(contexts.single['link'], 'denied-context');
      expect(RightsService.canUpdateOrders(), isFalse);
      expect(RightsService.canSeeAdministration(), isTrue);
    },
  );
  for (final deleting in [false, true]) {
    testWidgets(
      'product ${deleting ? 'delete' : 'save'} denial refreshes capabilities and retains the record',
      (tester) async {
        RightsService.currentLink = 'product-denied';
        RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          capabilities: const {'orders.write': true},
        );
        final denial = PostgrestException(
          message: 'Product permission revoked',
          code: '42501',
        );
        final commands = _DeniedProductCommands(denial);
        final product = ProductModel(
          id: 7,
          title: 'Unsaved lunch',
          aggregateVersion: 4,
        );
        final record = ProductGridRecord(
          product: product,
          commands: commands,
          guard: ExceptionHandler.guardVoid,
        );
        await tester.pumpWidget(
          const MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(body: SizedBox()),
          ),
        );
        final context = tester.element(find.byType(Scaffold));
        const channel = MethodChannel('PonnamKarthik/fluttertoast');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        expect(messenger.checkMockMessageHandler(channel.name, null), isTrue);
        messenger.setMockMethodCallHandler(channel, (_) async => true);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.runAsync(() async {
          await expectLater(
            deleting
                ? record.deleteMethod(context)
                : record.updateMethod(context),
            throwsA(same(denial)),
          );
        });
        expect(commands.calls, [
          deleting ? 'delete' : 'save',
        ], reason: 'Authorization refresh cannot replay the denied mutation');
        expect(commands.expectedVersion, 4);
        expect(contexts, hasLength(1));
        expect(contexts.single['link'], 'product-denied');
        expect(RightsService.canUpdateOrders(), isFalse);
        expect(
          RightsService.canSeeAdministration(),
          isTrue,
          reason: 'The authoritative projection was loaded by the real guard',
        );
        expect(record.product, same(product));
        expect(record.product.title, 'Unsaved lunch');
        expect(record.product.aggregateVersion, 4);
      },
    );
  }
  test(
    'bank actions use scoped operation projections and clear them together',
    () {
      RightsService.occasionLinkModelNotifier.value =
          OccasionLinkModel.fromJson({
            'capabilities': {'bank_accounts.unit.manage': false},
            'bank_accounts_admin': [7, 8],
            'bank_capabilities': {
              '7': {'bank_sync.manage': true},
            },
          });
      expect(RightsService.hasBankCapability(7, 'bank_sync.manage'), isTrue);
      expect(RightsService.hasBankCapability(8, 'bank_sync.manage'), isFalse);
      expect(RightsService.banksWithCapability('bank_sync.manage'), [7]);
      RightsService.invalidateCapabilities();
      expect(RightsService.hasBankCapability(7, 'bank_sync.manage'), isFalse);
      expect(RightsService.occasionLinkModel?.bankCapabilities, isEmpty);
    },
  );
  test(
    'bank role or link changes load newly granted SQL capabilities once',
    () async {
      RightsService.currentLink = 'bank-changed';
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: const {'navigation.administration': true},
        bankCapabilities: const {
          8: {'bank_sync.manage': true},
        },
      );
      final refresh = RightsService.refreshAfterAuthorizationChange();
      expect(RightsService.hasBankCapability(8, 'bank_sync.manage'), isFalse);
      await refresh;
      expect(contexts, hasLength(1));
      expect(contexts.single['link'], 'bank-changed');
      expect(RightsService.hasBankCapability(7, 'bank_sync.manage'), isTrue);
      expect(RightsService.hasBankCapability(8, 'bank_sync.manage'), isFalse);
    },
  );
  test('bank Edge denial refreshes the SQL projection without retrying the mutation', () async {
    RightsService.currentLink = 'bank-denied';
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      capabilities: const {'navigation.administration': true},
      bankCapabilities: const {
        7: {'bank_sync.manage': true},
      },
    );
    final accounts = SupabaseBankAccounts(Supabase.instance.client);
    await expectLater(
      accounts.manage(7, 'suspend'),
      throwsA(isA<BankSyncError>()),
    );
    expect(bankDispatches, 1);
    expect(contexts, hasLength(1));
    expect(contexts.single['link'], 'bank-denied');
    expect(RightsService.hasBankCapability(7, 'bank_sync.manage'), isFalse);
  });
  test('bank SQL denial refreshes once even when the UI handles the same exception', () async {
    RightsService.currentLink = 'bank-denied';
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      capabilities: const {'navigation.administration': true},
      bankCapabilities: const {
        7: {'bank_accounts.users.write': true},
      },
    );
    final accounts = SupabaseBankAccounts(Supabase.instance.client);
    PostgrestException? denial;
    try {
      await accounts.updateBankAccountUser(
        7,
        'target@example.invalid',
        true,
        false,
      );
    } on PostgrestException catch (error) {
      denial = error;
    }
    expect(denial, isNotNull);
    await RightsService.refreshAfterAuthorizationDenial(error: denial);
    expect(bankRpcDispatches, 1);
    expect(contexts, hasLength(1));
    expect(
      RightsService.hasBankCapability(7, 'bank_accounts.users.write'),
      isFalse,
    );
    await RightsService.refreshAfterAuthorizationDenial(
      error: const PostgrestException(
        message: 'A later response',
        code: '42501',
      ),
    );
    expect(
      contexts,
      hasLength(2),
      reason: 'a new failed request must check live context again',
    );
  });
  test('self unit role changes refresh current capabilities while other-user edits keep one RPC', () async {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel.fromJson({
      'code': 200,
      'unit': {'id': 12},
      'user_info': {'id': 'self-user'},
      'capabilities': {'media.unit.write': false},
    });
    await DbUsers.updateUnitUser(
      UnitUserModel(unit: 12, user: 'other-user', isManager: true),
    );
    expect(unitUserUpdates, 1);
    expect(contexts, isEmpty);
    await DbUsers.updateUnitUser(
      UnitUserModel(
        unit: 12,
        user: 'self-user',
        isManager: true,
        isEditor: true,
      ),
    );
    expect(unitUserUpdates, 2);
    expect(contexts, hasLength(1));
    expect(contexts.single['unit_id'], 12);
    expect(RightsService.hasCapability('media.unit.write'), isTrue);
  });
  for (final revoked in [false, true]) {
    test(
      'administration retry reloads invalidated capabilities, revoked=$revoked',
      () async {
        const actor = '00000000-0000-4000-8000-000000000001';
        final payload = base64Url.encode(
          utf8.encode(
            jsonEncode({
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              'sub': actor,
            }),
          ),
        );
        await Supabase.instance.client.auth.recoverSession(
          jsonEncode({
            'access_token':
                '${base64Url.encode(utf8.encode('{}'))}.$payload.signature',
            'refresh_token': 'fixture-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': actor,
              'aud': 'authenticated',
              'role': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
        );
        addTearDown(
          () =>
              Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
        );
        final link = revoked ? 'access-revoked' : 'access-recovery';
        await RightsService.updateAppData(
          link: link,
          force: true,
          refreshOffline: false,
        );
        if (!revoked) {
          contextGate = Completer<void>();
          final refreshing = RightsService.updateAppData(
            link: link,
            force: true,
            refreshOffline: false,
          );
          final joining = const RightsAdministrationAccess().load(
            link,
            reservations: false,
          );
          await Future<void>.delayed(Duration.zero);
          expect(contexts, hasLength(2));
          expect(RightsService.canSeeAdministration(), isFalse);
          contextGate!.complete();
          await refreshing;
          expect(await joining, isTrue);
          expect(
            contexts,
            hasLength(2),
            reason: 'Boundary joins the existing refresh instead of invalidating it again',
          );
          contextGate = null;
        }
        final initialReads = contexts.length;
        contextFailures = 1;
        await RightsService.refreshAfterAuthorizationDenial();
        expect(RightsService.canSeeAdministration(), isFalse);
        expect(AuthService.isLoggedIn(), isTrue);
        final mutationCount =
            bankDispatches + bankRpcDispatches + unitUserUpdates;
        expect(
          await const RightsAdministrationAccess().load(
            link,
            reservations: false,
          ),
          !revoked,
        );
        expect(
          contexts,
          hasLength(initialReads + 2),
          reason: 'Retry must fetch current SQL capabilities for the same link',
        );
        expect(AuthService.currentUserId(), actor);
        expect(
          bankDispatches + bankRpcDispatches + unitUserUpdates,
          mutationCount,
          reason: 'Reloading context cannot replay the rejected mutation',
        );
      },
    );
  }
}

class _DeniedProductCommands implements EshopCommands {
  _DeniedProductCommands(this.denial);
  final PostgrestException denial;
  final calls = <String>[];
  int? expectedVersion;

  @override
  Future<SavedProduct> saveProduct(Map<String, dynamic> product) async {
    calls.add('save');
    expectedVersion = product['expected_aggregate_version'] as int;
    throw denial;
  }

  @override
  Future<void> deleteProduct(int id, {required int expectedVersion}) async {
    expect(id, 7);
    calls.add('delete');
    this.expectedVersion = expectedVersion;
    throw denial;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
