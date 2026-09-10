import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection_tracker.dart';
import 'package:fstapp/data_services/client_sync/client_sync_remote.dart';
import 'package:fstapp/data_services/client_sync/client_sync_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_store.dart';
import 'package:fstapp/data_services/client_sync/occasion_media_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Process-wide owner of the selected legacy/v1 context mode.
///
/// Features may request a refresh reason but cannot create timers or network
/// loaders. A capability change is observed only on the next context bootstrap.
class ClientSyncRuntime {
  static final state = ValueNotifier<ClientSyncState?>(null);
  static final projectionEpoch = ValueNotifier<int>(0);
  static final searchProjectionEpoch = ValueNotifier<int>(0);
  static ClientSyncService? _service;
  static Future<void> Function(DateTime)? _onLastSuccess;
  static StreamSubscription<ClientSyncState>? _subscription;
  static OccasionLinkModel? _selectedModel;
  static bool _v1Selected = false;
  static int _identityEpoch = 0;
  static SyncContext? _context;
  static final ClientSyncProjectionTracker _projectionTracker =
      ClientSyncProjectionTracker();
  static String? _searchProjectionSignature;
  static final OccasionMediaCache _mediaCache = OccasionMediaCache();

  static bool get isV1Selected => _v1Selected;
  static bool get hasPrivateIdentity => _context?.privateScope != null;
  static String get mutationContextToken =>
      '$_identityEpoch|$_v1Selected|${_context?.publicScope}|${_context?.privateScope}';

  static bool isCurrentMutationContext(String token) =>
      mutationContextToken == token;
  static DateTime? get latestLastSuccess {
    DateTime? latest;
    for (final classState
        in state.value?.classes.values ?? const <SyncClassState>[]) {
      final candidate = classState.lastSuccess;
      if (candidate != null && (latest == null || candidate.isAfter(latest))) {
        latest = candidate;
      }
    }
    return latest;
  }

  static DateTime? lastSuccess(SyncFreshnessClass type) =>
      state.value?.classes[type]?.lastSuccess;
  static ClientSyncStore get store => _store;
  static final ClientSyncStore _store = ClientSyncStore();

  static void configure(
    SupabaseClient supabase, {
    Future<void> Function(DateTime)? onLastSuccess,
    Uri? publicHeadOrigin,
    Uri? publicAssetOrigin,
  }) {
    _onLastSuccess = onLastSuccess;
    final publicRemote = HttpPublicSyncRemote(
      headOrigin: publicHeadOrigin ?? Uri.parse(AppConfig.syncHeadOrigin),
      artifactOrigin: publicAssetOrigin ?? Uri.parse(AppConfig.syncAssetOrigin),
      artifactRequestUriResolver: kIsWeb
          ? (artifactUri) => resolvePublicArtifactRequestUriForPage(
                artifactUri,
                Uri.base,
              )
          : null,
    );
    _service = ClientSyncService(
      publicHeadRemote: publicRemote,
      publicComponentRemote: publicRemote,
      privateRemote: SupabasePrivateSyncRemote(supabase),
      store: _store,
      cacheOccasionMedia: (_, urls, {required refreshExisting}) =>
          _mediaCache.cacheAll(urls, refreshExisting: refreshExisting),
    );
  }

  static Future<OccasionLinkModel?> restoreLastContext() async {
    final stored = await _store.readLastContext();
    if (stored == null) return null;
    final publicScope = '${stored.organizationId}/${stored.occasionId}';
    final catalog = await _store.activeGeneration(
      publicScope,
      SyncFreshnessClass.catalog,
    );
    final hasCompleteCatalog = await _store.isGenerationComplete(
      publicScope,
      SyncFreshnessClass.catalog,
      ReleaseManifest.requiredComponents,
    );
    if (!isRestorableSyncContext(stored, catalog) || !hasCompleteCatalog) {
      await _store.clearLastContext();
      return null;
    }
    final model = OccasionLinkModel(
      code: 200,
      clientSyncV1: true,
      occasion: OccasionModel(
        id: stored.occasionId,
        link: stored.occasionLink,
        organization: stored.organizationId,
        isOpen: true,
        isHidden: false,
        isPromoted: false,
      ),
    );
    await bootstrap(model, networkAvailable: false);
    return model;
  }

  static Future<void> bootstrap(
    OccasionLinkModel model, {
    bool networkAvailable = true,
  }) async {
    final service = _service;
    final occasion = model.occasion;
    if (service == null || occasion?.id == null || occasion?.link == null) {
      return;
    }
    final previousSearchScope = _v1Selected ? _context?.publicScope : null;
    final nextSearchScope = model.clientSyncV1
        ? '${occasion?.organization ?? AppConfig.organization}/${occasion!.id!}'
        : null;
    final searchContextChanged = previousSearchScope != nextSearchScope;
    await _subscription?.cancel();
    await service.closeContext();
    _selectedModel = model;
    _v1Selected = model.clientSyncV1;
    _context = null;
    _projectionTracker.reset();
    projectionEpoch.value++;
    if (searchContextChanged) {
      _searchProjectionSignature = null;
      searchProjectionEpoch.value++;
    }
    state.value = null;
    if (!_v1Selected) {
      if (networkAvailable) await _store.clearLastContext();
      return;
    }
    final context = SyncContext(
      organizationId: occasion?.organization ?? AppConfig.organization,
      occasionId: occasion!.id!,
      occasionLink: occasion.link!,
      userId: Supabase.instance.client.auth.currentUser?.id,
      identityEpoch: _identityEpoch,
    );
    _context = context;
    final opened = Completer<void>();
    _subscription = service.open(context).listen(
      (value) {
        state.value = value;
        final latest = latestLastSuccess;
        final persist = _onLastSuccess;
        if (latest != null && persist != null) {
          unawaited(persist(latest));
        }
        unawaited(_updateProjectionEpoch());
        if (!opened.isCompleted) opened.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!opened.isCompleted) opened.completeError(error, stackTrace);
      },
    );
    await opened.future;
    if (!networkAvailable) return;
    final hasCompleteCatalog = await _store.isGenerationComplete(
      context.publicScope,
      SyncFreshnessClass.catalog,
      ReleaseManifest.requiredComponents,
    );
    if (!hasCompleteCatalog) {
      await service.start();
    } else {
      unawaited(service.start());
    }
    final activated = await _store.isGenerationComplete(
      context.publicScope,
      SyncFreshnessClass.catalog,
      ReleaseManifest.requiredComponents,
    );
    if (activated) {
      await _store.saveLastContext(
          StoredSyncContext(
            organizationId: context.organizationId,
            occasionId: context.occasionId,
            occasionLink: context.occasionLink,
          ),
          privateScope: context.privateScope);
    }
  }

  static Future<void> identityChanged() async {
    final oldPrivateScope = _context?.privateScope;
    _identityEpoch++;
    if (oldPrivateScope != null) {
      await _store.clearPrivateScope(oldPrivateScope);
    }
    final selected = _selectedModel;
    if (selected != null) await bootstrap(selected);
  }

  static Future<void> refresh(SyncReason reason,
      {bool privateConsumer = false}) async {
    if (!_v1Selected) return;
    await _service?.refresh(reason: reason, privateConsumer: privateConsumer);
  }

  static Future<void> connectivityRestored() async {
    if (!_v1Selected) return;
    await _service?.reconnect();
  }

  static Future<Map<String, dynamic>?> readPublic(
      ClientSyncComponent component) async {
    final context = _context;
    if (!_v1Selected || context == null) return null;
    final type = component == ClientSyncComponent.livePublic
        ? SyncFreshnessClass.live
        : SyncFreshnessClass.catalog;
    final stored =
        await _store.readComponent(context.publicScope, type, component);
    if (stored is! Map) return null;
    final artifact = stored.cast<String, dynamic>();
    final payload = artifact['payload'];
    return payload is Map ? payload.cast<String, dynamic>() : artifact;
  }

  static Future<Object?> readPrivate(ClientSyncComponent component) async {
    final context = _context;
    final scope = context?.privateScope;
    if (!_v1Selected || scope == null) return null;
    final payload = await _store.readComponent(
        scope, SyncFreshnessClass.privateIdentity, component);
    return _v1Selected && _context == context ? payload : null;
  }

  static Future<void> applyPrivateReplacement({
    required ClientSyncComponent component,
    required int revision,
    required Object? payload,
    bool notifyProjection = true,
    String? expectedContextToken,
  }) async {
    if (expectedContextToken != null &&
        !isCurrentMutationContext(expectedContextToken)) {
      return;
    }
    final context = _context;
    final scope = context?.privateScope;
    if (!_v1Selected || context == null || scope == null) return;
    final current = await _store.activeGeneration(
        scope, SyncFreshnessClass.privateIdentity);
    if (current != null && (current.revisions[component] ?? -1) > revision) {
      return;
    }
    final revisions = {...?current?.revisions, component: revision};
    final payloads = <ClientSyncComponent, Object?>{};
    for (final item in revisions.keys) {
      payloads[item] = item == component
          ? payload
          : await _store.readComponent(
              scope, SyncFreshnessClass.privateIdentity, item);
    }
    if (_context != context ||
        (expectedContextToken != null &&
            !isCurrentMutationContext(expectedContextToken))) {
      return;
    }
    final pointer =
        '${context.identityEpoch}-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final activated = await _store.activateGuarded(
      scope: scope,
      type: SyncFreshnessClass.privateIdentity,
      pointer: pointer,
      updatedAt: DateTime.now().toUtc(),
      revisions: revisions,
      payloads: payloads,
      precondition: () =>
          _context == context &&
          (expectedContextToken == null ||
              isCurrentMutationContext(expectedContextToken)),
    );
    if (_context != context ||
        (expectedContextToken != null &&
            !isCurrentMutationContext(expectedContextToken))) {
      return;
    }
    if (!activated) {
      return applyPrivateReplacement(
        component: component,
        revision: revision,
        payload: payload,
        notifyProjection: notifyProjection,
        expectedContextToken: expectedContextToken,
      );
    }
    if (notifyProjection) {
      _notifyProjectionChanged();
    } else {
      _projectionTracker.acknowledgePrivate(
        scope: scope,
        pointer: pointer,
      );
    }
  }

  /// Reconciles fields returned authoritatively by a private mutation even
  /// when an idempotent/no-op response carries no replacement artifact.
  static Future<void> patchPrivateComponent({
    required ClientSyncComponent component,
    required Map<String, dynamic> fields,
    bool notifyProjection = true,
    String? expectedContextToken,
  }) async {
    if (expectedContextToken != null &&
        !isCurrentMutationContext(expectedContextToken)) {
      return;
    }
    final context = _context;
    final scope = context?.privateScope;
    if (!_v1Selected || context == null || scope == null) return;
    final current = await _store.activeGeneration(
      scope,
      SyncFreshnessClass.privateIdentity,
    );
    final raw = await readPrivate(component);
    final revision = current?.revisions[component];
    if (_context != context ||
        (expectedContextToken != null &&
            !isCurrentMutationContext(expectedContextToken))) {
      return;
    }
    if (raw is! Map || revision == null) {
      await refresh(SyncReason.manual, privateConsumer: true);
      return;
    }
    await applyPrivateReplacement(
      component: component,
      revision: revision,
      payload: {...raw.cast<String, dynamic>(), ...fields},
      notifyProjection: notifyProjection,
      expectedContextToken: expectedContextToken,
    );
  }

  static Future<void> applyPublicReplacement({
    required ClientSyncComponent component,
    required int revision,
    required Object? payload,
    bool notifyProjection = true,
    String? expectedContextToken,
  }) async {
    if (expectedContextToken != null &&
        !isCurrentMutationContext(expectedContextToken)) {
      return;
    }
    final context = _context;
    if (!_v1Selected || context == null) return;
    final current = await _store.activeGeneration(
        context.publicScope, SyncFreshnessClass.catalog);
    if (current == null) return;
    if ((current.revisions[component] ?? -1) > revision) return;
    final revisions = {...current.revisions, component: revision};
    final payloads = <ClientSyncComponent, Object?>{};
    for (final item in revisions.keys) {
      payloads[item] = item == component
          ? payload
          : await _store.readComponent(
              context.publicScope, SyncFreshnessClass.catalog, item);
    }
    if (_context != context ||
        (expectedContextToken != null &&
            !isCurrentMutationContext(expectedContextToken))) {
      return;
    }
    final pointer = 'mutation-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final activated = await _store.activateGuarded(
      scope: context.publicScope,
      type: SyncFreshnessClass.catalog,
      pointer: pointer,
      updatedAt: DateTime.now().toUtc(),
      revisions: revisions,
      payloads: payloads,
      precondition: () =>
          _context == context &&
          (expectedContextToken == null ||
              isCurrentMutationContext(expectedContextToken)),
    );
    if (_context != context ||
        (expectedContextToken != null &&
            !isCurrentMutationContext(expectedContextToken))) {
      return;
    }
    if (!activated) {
      return applyPublicReplacement(
        component: component,
        revision: revision,
        payload: payload,
        notifyProjection: notifyProjection,
        expectedContextToken: expectedContextToken,
      );
    }
    if (notifyProjection) {
      _notifyProjectionChanged(
          searchIndexChanged: component.affectsSearchIndex);
    } else {
      _projectionTracker.acknowledgeCatalog(
        scope: context.publicScope,
        pointer: pointer,
      );
    }
  }

  static Future<void> applyLiveReplacement({
    required int revision,
    required Object? payload,
    bool notifyProjection = true,
    String? expectedContextToken,
  }) async {
    if (expectedContextToken != null &&
        !isCurrentMutationContext(expectedContextToken)) {
      return;
    }
    final context = _context;
    if (!_v1Selected || context == null) return;
    final current = await _store.activeGeneration(
        context.publicScope, SyncFreshnessClass.live);
    if (current != null &&
        (current.revisions[ClientSyncComponent.livePublic] ?? -1) > revision) {
      return;
    }
    if (_context != context ||
        (expectedContextToken != null &&
            !isCurrentMutationContext(expectedContextToken))) {
      return;
    }
    final pointer = 'mutation-live-$revision';
    final activated = await _store.activateGuarded(
      scope: context.publicScope,
      type: SyncFreshnessClass.live,
      pointer: pointer,
      updatedAt: DateTime.now().toUtc(),
      revisions: {ClientSyncComponent.livePublic: revision},
      payloads: {ClientSyncComponent.livePublic: payload},
      precondition: () =>
          _context == context &&
          (expectedContextToken == null ||
              isCurrentMutationContext(expectedContextToken)),
    );
    if (_context != context ||
        (expectedContextToken != null &&
            !isCurrentMutationContext(expectedContextToken))) {
      return;
    }
    if (!activated) return;
    if (notifyProjection) {
      _notifyProjectionChanged();
    } else {
      _projectionTracker.acknowledgeLive(
        scope: context.publicScope,
        pointer: pointer,
      );
    }
  }

  static void _notifyProjectionChanged({bool searchIndexChanged = false}) {
    final current = state.value;
    if (current == null) return;
    state.value = ClientSyncState(
      context: current.context,
      classes: {...current.classes},
    );
    _projectionTracker.reset();
    projectionEpoch.value++;
    if (searchIndexChanged) {
      _searchProjectionSignature = null;
      searchProjectionEpoch.value++;
    }
  }

  static Future<void> _updateProjectionEpoch() async {
    final context = _context;
    if (!_v1Selected || context == null) return;
    final catalog = await _store.activeGeneration(
        context.publicScope, SyncFreshnessClass.catalog);
    final live = await _store.activeGeneration(
        context.publicScope, SyncFreshnessClass.live);
    final privateScope = context.privateScope;
    final private = privateScope == null
        ? null
        : await _store.activeGeneration(
            privateScope, SyncFreshnessClass.privateIdentity);
    if (_context != context) return;
    if (_projectionTracker.observe(
      publicScope: context.publicScope,
      catalogPointer: catalog?.pointer,
      livePointer: live?.pointer,
      privateScope: privateScope,
      privatePointer: private?.pointer,
    )) {
      projectionEpoch.value++;
    }

    final searchSignature = clientSyncSearchProjectionSignature(
      context.publicScope,
      catalog?.revisions ?? const {},
    );
    if (_searchProjectionSignature != searchSignature) {
      _searchProjectionSignature = searchSignature;
      searchProjectionEpoch.value++;
    }
  }

  static void setForeground(bool foreground) {
    if (_v1Selected) _service?.setForeground(foreground);
  }
}

bool isRestorableSyncContext(
  StoredSyncContext? context,
  StoredSyncGeneration? catalog,
) =>
    context != null && catalog != null;
