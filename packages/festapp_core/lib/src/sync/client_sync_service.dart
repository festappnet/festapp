import 'dart:async';
import 'dart:convert';

import 'package:festapp_core/sync.dart';

typedef CacheOccasionMedia =
    Future<void> Function(
      SyncContext context,
      List<Uri> urls, {
      required bool refreshExisting,
    });

class ClientSyncService {
  ClientSyncService({
    required PublicSyncHeadRemote publicHeadRemote,
    required PublicComponentRemote publicComponentRemote,
    required PrivateSyncRemote privateRemote,
    required ClientSyncStore store,
    SyncPollingPolicy? pollingPolicy,
    SyncClock? clock,
    CacheOccasionMedia? cacheOccasionMedia,
  }) : _publicHeadRemote = publicHeadRemote,
       _publicComponentRemote = publicComponentRemote,
       _privateRemote = privateRemote,
       _store = store,
       _policy = pollingPolicy ?? SyncPollingPolicy(),
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _cacheOccasionMedia = cacheOccasionMedia;

  static const catalogBudget = 5 * 1024 * 1024;
  static const programCatalogBudget = 1024 * 1024;
  static const liveBudget = 512 * 1024;

  final PublicSyncHeadRemote _publicHeadRemote;
  final PublicComponentRemote _publicComponentRemote;
  final PrivateSyncRemote _privateRemote;
  final ClientSyncStore _store;
  final SyncPollingPolicy _policy;
  final SyncClock _clock;
  final CacheOccasionMedia? _cacheOccasionMedia;
  final StreamController<ClientSyncState> _states =
      StreamController<ClientSyncState>.broadcast();

  SyncContext? _context;
  ClientSyncState? _state;
  Timer? _timer;
  Future<void>? _publicFlight;
  Future<void>? _privateFlight;
  bool _foreground = true;
  int _epoch = 0;
  int _successfulPublicTicks = 0;
  int _publicFailures = 0;
  int _privateFailures = 0;
  DateTime? _publicRetryAfter;
  DateTime? _privateRetryAfter;
  PublicSyncHead? _pendingHead;

  Stream<ClientSyncState> open(SyncContext context) async* {
    await closeContext();
    _context = context;
    _epoch++;
    _state = ClientSyncState(
      context: context,
      classes: {
        for (final type in SyncFreshnessClass.values)
          type: const SyncClassState(),
      },
    );
    yield _state!;
    yield* _states.stream;
  }

  Future<void> start() async {
    if (_context == null) throw StateError('Open a sync context before start');
    await refresh(reason: SyncReason.bootstrap, privateConsumer: true);
    _scheduleNextTick();
  }

  Future<void> reconnect() async {
    if (_context == null) return;
    await refresh(reason: SyncReason.reconnect, privateConsumer: true);
    _scheduleNextTick();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    _timer?.cancel();
    if (foreground) {
      unawaited(refresh(reason: SyncReason.resume, privateConsumer: true));
      _scheduleNextTick();
    }
  }

  Future<void> refresh({
    required SyncReason reason,
    bool privateConsumer = false,
  }) async {
    final context = _context;
    final state = _state;
    if (context == null || state == null) return;
    final now = _clock();
    final catalog = state.classes[SyncFreshnessClass.catalog]!;
    final lifecycleOverride =
        reason == SyncReason.resume || reason == SyncReason.reconnect;
    final shouldPollPublic =
        (lifecycleOverride ||
            _publicRetryAfter == null ||
            !now.isBefore(_publicRetryAfter!)) &&
        _policy.publicIsDue(
          now,
          catalog.lastSuccess,
          missingRequiredData: catalog.revision == null,
          reason: reason,
        );
    final shouldPollPrivate =
        context.isAuthenticated &&
        (_successfulPublicTicks > 0 && _successfulPublicTicks % 4 == 0 ||
            reason != SyncReason.timer) &&
        (lifecycleOverride ||
            _privateRetryAfter == null ||
            !now.isBefore(_privateRetryAfter!)) &&
        _policy.privateIsDue(
          now,
          state.classes[SyncFreshnessClass.privateIdentity]!.lastSuccess,
          privateConsumer: privateConsumer,
          reason: reason,
        );

    await Future.wait([
      if (shouldPollPublic) _joinPublic(context),
      if (shouldPollPrivate) _joinPrivate(context),
    ]);
  }

  Future<void> _joinPublic(SyncContext context) {
    final existing = _publicFlight;
    if (existing != null) return existing;
    late final Future<void> flight;
    flight = _refreshPublic(context).whenComplete(() {
      if (identical(_publicFlight, flight)) _publicFlight = null;
    });
    _publicFlight = flight;
    return flight;
  }

  Future<void> _joinPrivate(SyncContext context) {
    final existing = _privateFlight;
    if (existing != null) return existing;
    late final Future<void> flight;
    flight = _refreshPrivate(context).whenComplete(() {
      if (identical(_privateFlight, flight)) _privateFlight = null;
    });
    _privateFlight = flight;
    return flight;
  }

  Future<void> _refreshPublic(SyncContext context) async {
    final requestEpoch = _epoch;
    _setInFlight(SyncFreshnessClass.catalog, true);
    try {
      final result = await _publicHeadRemote.getHead(context);
      if (!_isCurrent(context, requestEpoch)) return;
      if (result.head case final received?) {
        _pendingHead = received;
      }
      final hasPendingFailure =
          _state!.classes[SyncFreshnessClass.catalog]!.error != null ||
          _state!.classes[SyncFreshnessClass.live]!.error != null;
      final head = result.head ?? (hasPendingFailure ? _pendingHead : null);
      if (head != null) {
        if (head.protocol != 1) {
          throw const FormatException('Unsupported sync protocol');
        }
        await Future.wait([
          if (head.catalog case final descriptor?)
            _runClass(
              SyncFreshnessClass.catalog,
              () => _activateCatalog(
                context,
                requestEpoch,
                descriptor,
                head.serverTime,
              ),
            ),
          if (head.live case final descriptor?)
            _runClass(
              SyncFreshnessClass.live,
              () => _activateLive(
                context,
                requestEpoch,
                descriptor,
                head.serverTime,
              ),
            ),
        ]);
      } else if (result.notModified) {
        final current = _state!.classes[SyncFreshnessClass.catalog]!;
        _replaceClass(
          SyncFreshnessClass.catalog,
          current.copyWith(
            lastSuccess: _clock(),
            clearError: true,
            inFlight: false,
          ),
        );
      }
      if (!_isCurrent(context, requestEpoch)) return;
      if (_state!.classes[SyncFreshnessClass.catalog]!.error == null &&
          _state!.classes[SyncFreshnessClass.live]!.error == null) {
        _successfulPublicTicks++;
        _publicFailures = 0;
        _publicRetryAfter = null;
      }
    } catch (error) {
      _setError(SyncFreshnessClass.catalog, error);
    }
  }

  Future<void> _runClass(
    SyncFreshnessClass type,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      _setError(type, error);
    }
  }

  Future<void> _activateCatalog(
    SyncContext context,
    int requestEpoch,
    ArtifactDescriptor descriptor,
    DateTime serverTime,
  ) async {
    final existing = await _store.activeGeneration(
      context.publicScope,
      SyncFreshnessClass.catalog,
    );
    final activeReleaseRevision =
        _state?.classes[SyncFreshnessClass.catalog]?.revision;
    if (activeReleaseRevision != null &&
        descriptor.revision < activeReleaseRevision) {
      throw const FormatException('Release manifest revision regression');
    }
    if (existing?.pointer == descriptor.sha256 &&
        await _store.isGenerationComplete(
          context.publicScope,
          SyncFreshnessClass.catalog,
          ReleaseManifest.requiredComponents,
        )) {
      _replaceClass(
        SyncFreshnessClass.catalog,
        _state!.classes[SyncFreshnessClass.catalog]!.copyWith(
          revision: descriptor.revision,
          lastSuccess: serverTime,
          clearError: true,
          inFlight: false,
        ),
      );
      unawaited(_cacheStoredMediaBestEffort(context));
      return;
    }
    final manifestBytes = await _downloadUnknown(descriptor, catalogBudget);
    final manifest = ReleaseManifest.fromBytes(manifestBytes);
    if (manifest.protocol != 1 ||
        manifest.schema != 1 ||
        manifest.scope != context.publicScope ||
        manifest.releaseRevision != descriptor.revision) {
      throw const FormatException('Release manifest protocol/scope mismatch');
    }
    if (existing != null) {
      for (final entry in existing.revisions.entries) {
        final next = manifest.components[entry.key]?.revision;
        if (next == null || next < entry.value) {
          throw const FormatException('Release manifest regresses a component');
        }
      }
    }
    final declaredBytes = manifest.components.values.fold<int>(
      0,
      (total, descriptor) => total + descriptor.bytes,
    );
    if (declaredBytes > catalogBudget) {
      throw const FormatException('Public component set exceeds 5 MiB');
    }
    final payloadEntries = await Future.wait(
      manifest.components.entries.map((entry) async {
        final componentBudget = entry.key == ClientSyncComponent.programCatalog
            ? programCatalogBudget
            : catalogBudget;
        final bytes = await _downloadUnknown(entry.value, componentBudget);
        final artifact = jsonDecode(utf8.decode(bytes));
        if (artifact is! Map) {
          throw const FormatException('Component artifact must be an object');
        }
        final json = artifact.cast<String, dynamic>();
        if (json['protocol'] != 1 ||
            json['schema'] != 1 ||
            json['component'] != entry.key.wireName ||
            json['scope'] != context.publicScope ||
            json['revision'] != entry.value.revision ||
            !json.containsKey('payload')) {
          throw FormatException(
            '${entry.key.wireName} artifact metadata mismatch',
          );
        }
        return MapEntry(entry.key, json);
      }),
    );
    if (!_isCurrent(context, requestEpoch)) return;
    final payloads = Map<ClientSyncComponent, Object?>.fromEntries(
      payloadEntries,
    );
    _validateMapClosure(payloads[ClientSyncComponent.mapCatalog]);
    final activated = await _store.activateGuarded(
      scope: context.publicScope,
      type: SyncFreshnessClass.catalog,
      pointer: descriptor.sha256,
      updatedAt: serverTime,
      revisions: manifest.components.map(
        (key, value) => MapEntry(key, value.revision),
      ),
      payloads: payloads,
      precondition: () => _isCurrent(context, requestEpoch),
    );
    if (!activated) {
      _replaceClass(
        SyncFreshnessClass.catalog,
        _state!.classes[SyncFreshnessClass.catalog]!.copyWith(inFlight: false),
      );
      return;
    }
    _replaceClass(
      SyncFreshnessClass.catalog,
      _state!.classes[SyncFreshnessClass.catalog]!.copyWith(
        revision: manifest.releaseRevision,
        lastSuccess: serverTime,
        clearError: true,
        inFlight: false,
      ),
    );
    unawaited(_cacheMediaBestEffort(context, payloads, refreshExisting: true));
  }

  Future<void> _cacheStoredMediaBestEffort(SyncContext context) async {
    final occasionConfig = await _store.readComponent(
      context.publicScope,
      SyncFreshnessClass.catalog,
      ClientSyncComponent.occasionConfig,
    );
    await _cacheMediaBestEffort(context, {
      ClientSyncComponent.occasionConfig: occasionConfig,
    }, refreshExisting: false);
  }

  Future<void> _cacheMediaBestEffort(
    SyncContext context,
    Map<ClientSyncComponent, Object?> payloads, {
    required bool refreshExisting,
  }) async {
    final cache = _cacheOccasionMedia;
    if (cache == null) return;
    final envelope = payloads[ClientSyncComponent.occasionConfig];
    final rawPayload = envelope is Map ? envelope['payload'] : null;
    final config = rawPayload is Map ? rawPayload : envelope;
    final urls = <Uri>[];
    final seen = <String>{};
    if (config is Map) {
      for (final item in (config['media'] as List? ?? const [])) {
        final value = item is Map ? item['url'] : item;
        final uri = Uri.tryParse(value?.toString() ?? '');
        if (uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            seen.add(uri.toString())) {
          urls.add(uri);
        }
      }
    }
    if (urls.isEmpty) return;
    try {
      await cache(context, urls, refreshExisting: refreshExisting);
    } catch (_) {
      // Media is a retryable sidecar. Never roll back a valid JSON generation
      // merely because one binary is temporarily unavailable.
    }
  }

  Future<void> _activateLive(
    SyncContext context,
    int requestEpoch,
    ArtifactDescriptor descriptor,
    DateTime serverTime,
  ) async {
    final existing = await _store.activeGeneration(
      context.publicScope,
      SyncFreshnessClass.live,
    );
    final existingRevision =
        existing?.revisions[ClientSyncComponent.livePublic];
    if (existingRevision != null && descriptor.revision < existingRevision) {
      throw const FormatException('live_public revision regression');
    }
    if (existing?.pointer == descriptor.sha256 &&
        await _store.isGenerationComplete(
          context.publicScope,
          SyncFreshnessClass.live,
          const {ClientSyncComponent.livePublic},
        )) {
      _replaceClass(
        SyncFreshnessClass.live,
        _state!.classes[SyncFreshnessClass.live]!.copyWith(
          revision: descriptor.revision,
          lastSuccess: serverTime,
          clearError: true,
        ),
      );
      return;
    }
    final bytes = await _downloadUnknown(descriptor, liveBudget);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('live_public artifact must be an object');
    }
    final payload = decoded.cast<String, dynamic>();
    if (payload['protocol'] != 1 ||
        payload['schema'] != 1 ||
        payload['component'] != ClientSyncComponent.livePublic.wireName ||
        payload['scope'] != context.publicScope ||
        payload['revision'] != descriptor.revision ||
        !payload.containsKey('payload')) {
      throw const FormatException('live_public artifact metadata mismatch');
    }
    if (!_isCurrent(context, requestEpoch)) return;
    final activated = await _store.activateGuarded(
      scope: context.publicScope,
      type: SyncFreshnessClass.live,
      pointer: descriptor.sha256,
      updatedAt: serverTime,
      revisions: {ClientSyncComponent.livePublic: descriptor.revision},
      payloads: {ClientSyncComponent.livePublic: payload},
      precondition: () => _isCurrent(context, requestEpoch),
    );
    if (!activated) {
      _replaceClass(
        SyncFreshnessClass.live,
        _state!.classes[SyncFreshnessClass.live]!.copyWith(inFlight: false),
      );
      return;
    }
    _replaceClass(
      SyncFreshnessClass.live,
      _state!.classes[SyncFreshnessClass.live]!.copyWith(
        revision: descriptor.revision,
        lastSuccess: serverTime,
        clearError: true,
      ),
    );
  }

  Future<List<int>> _downloadUnknown(
    ArtifactDescriptor descriptor,
    int budget,
  ) async {
    final cached = await _store.readBlob(descriptor.sha256);
    if (cached != null) return cached;
    final bytes = await _publicComponentRemote.download(
      descriptor,
      maxBytes: budget,
    );
    await _store.stageBlob(descriptor.sha256, bytes);
    return bytes;
  }

  Future<void> _refreshPrivate(SyncContext context) async {
    final scope = context.privateScope;
    if (scope == null) return;
    final requestEpoch = _epoch;
    _setInFlight(SyncFreshnessClass.privateIdentity, true);
    try {
      final current = await _store.activeGeneration(
        scope,
        SyncFreshnessClass.privateIdentity,
      );
      final knownVector = <ClientSyncComponent, int>{};
      for (final entry
          in current?.revisions.entries ??
              const <MapEntry<ClientSyncComponent, int>>[]) {
        if (await _store.readComponent(
              scope,
              SyncFreshnessClass.privateIdentity,
              entry.key,
            ) !=
            null) {
          knownVector[entry.key] = entry.value;
        }
      }
      final response = await _privateRemote.getChanges(context, knownVector);
      if (!_isCurrent(context, requestEpoch)) return;
      final privateComponents = {
        for (final component in ClientSyncComponent.values)
          if (component.isPrivate) component,
      };
      if (response.vector.keys.toSet().length != privateComponents.length ||
          !response.vector.keys.toSet().containsAll(privateComponents)) {
        throw const FormatException('Private vector is incomplete');
      }
      for (final entry
          in current?.revisions.entries ??
              const <MapEntry<ClientSyncComponent, int>>[]) {
        if ((response.vector[entry.key] ?? -1) < entry.value) {
          throw const FormatException('Private vector revision regression');
        }
      }
      final replacementComponents = <ClientSyncComponent>{};
      for (final replacement in response.replacements) {
        if (!replacementComponents.add(replacement.component) ||
            response.vector[replacement.component] != replacement.revision) {
          throw const FormatException('Private replacement/vector mismatch');
        }
      }
      for (final entry in response.vector.entries) {
        final previous = current?.revisions[entry.key] ?? -1;
        if (entry.value > previous &&
            !replacementComponents.contains(entry.key)) {
          throw const FormatException(
            'Private revision advanced without payload',
          );
        }
      }
      if (response.replacements.isNotEmpty) {
        final replacements = {
          for (final replacement in response.replacements)
            replacement.component: replacement.payload,
        };
        for (final component in response.vector.keys) {
          if (!replacements.containsKey(component)) {
            replacements[component] = await _store.readComponent(
              scope,
              SyncFreshnessClass.privateIdentity,
              component,
            );
          }
        }
        final activated = await _store.activateGuarded(
          scope: scope,
          type: SyncFreshnessClass.privateIdentity,
          pointer:
              '${context.identityEpoch}-${response.serverTime.microsecondsSinceEpoch}',
          updatedAt: response.serverTime,
          revisions: response.vector,
          payloads: replacements,
          precondition: () => _isCurrent(context, requestEpoch),
        );
        if (!activated) {
          _replaceClass(
            SyncFreshnessClass.privateIdentity,
            _state!.classes[SyncFreshnessClass.privateIdentity]!.copyWith(
              inFlight: false,
            ),
          );
          return;
        }
      }
      final revision = response.vector.values.fold<int>(
        0,
        (a, b) => a > b ? a : b,
      );
      _replaceClass(
        SyncFreshnessClass.privateIdentity,
        _state!.classes[SyncFreshnessClass.privateIdentity]!.copyWith(
          revision: revision,
          lastSuccess: response.serverTime,
          clearError: true,
          inFlight: false,
        ),
      );
      _privateFailures = 0;
      _privateRetryAfter = null;
    } catch (error) {
      _setError(SyncFreshnessClass.privateIdentity, error);
    }
  }

  void _validateMapClosure(Object? payload) {
    if (payload is! Map) {
      throw const FormatException('map_catalog must be an object');
    }
    final envelope = payload.cast<String, dynamic>();
    final raw = envelope['payload'];
    final json = raw is Map ? raw.cast<String, dynamic>() : envelope;
    final icons = ((json['icons'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item['id'])
        .toSet();
    for (final collection in ['places', 'placeTypes', 'paths']) {
      for (final item
          in ((json[collection] as List?) ?? const []).whereType<Map>()) {
        final icon = item['icon'];
        if (icon != null && !icons.contains(icon)) {
          throw FormatException(
            '$collection references an icon outside map_catalog',
          );
        }
      }
    }
  }

  bool _isCurrent(SyncContext context, int requestEpoch) =>
      identical(context, _context) && requestEpoch == _epoch;

  void _setInFlight(SyncFreshnessClass type, bool value) =>
      _replaceClass(type, _state!.classes[type]!.copyWith(inFlight: value));

  void _setError(SyncFreshnessClass type, Object error) {
    if (type == SyncFreshnessClass.privateIdentity) {
      _privateRetryAfter = _clock().add(
        _policy.backoffForFailure(_privateFailures++),
      );
    } else {
      _publicRetryAfter = _clock().add(
        _policy.backoffForFailure(_publicFailures++),
      );
    }
    _replaceClass(
      type,
      _state!.classes[type]!.copyWith(error: error, inFlight: false),
    );
  }

  void _replaceClass(SyncFreshnessClass type, SyncClassState value) {
    _state = _state!.replace(type, value);
    _states.add(_state!);
  }

  void _scheduleNextTick() {
    _timer?.cancel();
    if (!_foreground || _context == null) return;
    _timer = Timer(_policy.nextTickDelay(), () async {
      await refresh(reason: SyncReason.timer, privateConsumer: true);
      _scheduleNextTick();
    });
  }

  Future<void> closeContext() async {
    _timer?.cancel();
    _timer = null;
    _epoch++;
    _context = null;
    _state = null;
    _successfulPublicTicks = 0;
    _publicFailures = 0;
    _privateFailures = 0;
    _publicRetryAfter = null;
    _privateRetryAfter = null;
    _pendingHead = null;
    _publicFlight = null;
    _privateFlight = null;
  }

  Future<void> dispose() async {
    await closeContext();
    await _states.close();
  }
}
