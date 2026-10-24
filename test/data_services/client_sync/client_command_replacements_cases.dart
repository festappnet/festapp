import 'dart:async';
import 'package:festapp_core/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../support/fixtures/local_app_storage_fixture.dart';
import '../../support/fixtures/root_supabase_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real replacement applier preserves sequence errors notification and context fence',
      () async {
    final storage = await LocalAppStorageFixture.open();
    addTearDown(storage.dispose);
    addTearDown(() => StorageHelper.closeDatabase('client_sync_v1.db'));
    final root =
        await RootSupabaseFixture.open((_) => http.Response('{}', 200));
    addTearDown(root.dispose);
    ClientSyncRuntime.configure(Supabase.instance.client);
    final legacy = OccasionLinkModel(
        code: 200,
        occasion: OccasionModel(
            id: 42,
            link: 'fixture',
            organization: 7,
            isOpen: true,
            isHidden: false,
            isPromoted: false));
    addTearDown(
        () => ClientSyncRuntime.bootstrap(legacy, networkAvailable: false));
    final initialProjection = Completer<void>();
    final beforeBootstrap = ClientSyncRuntime.projectionEpoch.value;
    void onProjection() {
      if (ClientSyncRuntime.projectionEpoch.value >= beforeBootstrap + 2 &&
          !initialProjection.isCompleted) {
        initialProjection.complete();
      }
    }

    ClientSyncRuntime.projectionEpoch.addListener(onProjection);
    addTearDown(
        () => ClientSyncRuntime.projectionEpoch.removeListener(onProjection));
    await ClientSyncRuntime.bootstrap(
        OccasionLinkModel(
            code: 200,
            clientSyncV1: true,
            occasion: OccasionModel(
                id: 42,
                link: 'fixture',
                organization: 7,
                isOpen: true,
                isHidden: false,
                isPromoted: false)),
        networkAvailable: false);
    await initialProjection.future.timeout(const Duration(seconds: 5));
    final token = ClientSyncRuntime.mutationContextToken;
    final epoch = ClientSyncRuntime.projectionEpoch.value;
    Map<String, dynamic> live(int revision) => {
          'component': 'live_public',
          'revision': revision,
          'payload': {'events': [], 'marker': revision}
        };
    ClientCommandResponse response(List<Map<String, dynamic>> replacements) =>
        ClientCommandResponse(
            status: 'applied', code: 200, data: {}, replacements: replacements);
    await applyClientCommandReplacements(response([live(1), live(2)]),
        notifyProjection: false, expectedContextToken: token);
    expect(
        (await ClientSyncRuntime.readPublic(
            ClientSyncComponent.livePublic))!['marker'],
        2);
    expect(ClientSyncRuntime.projectionEpoch.value, epoch);
    await expectLater(
        applyClientCommandReplacements(response([
          live(3),
          {'component': 'unknown', 'revision': 1},
          live(4)
        ])),
        throwsStateError);
    expect(
        (await ClientSyncRuntime.readPublic(
            ClientSyncComponent.livePublic))!['marker'],
        3);
    expect(ClientSyncRuntime.projectionEpoch.value, greaterThan(epoch));
    await applyClientCommandReplacements(response([live(5)]),
        expectedContextToken: '$token-stale');
    expect(
        (await ClientSyncRuntime.readPublic(
            ClientSyncComponent.livePublic))!['marker'],
        3);
    await ClientSyncRuntime.bootstrap(legacy, networkAvailable: false);
    expect(ClientSyncRuntime.isCurrentMutationContext(token), isFalse);
    expect(root.requests, isEmpty,
        reason: 'Offline fixture must not use a backend');
  });
}
