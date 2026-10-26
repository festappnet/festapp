import 'dart:convert';

enum ClientSyncComponent {
  occasionConfig,
  programCatalog,
  mapCatalog,
  contentCatalog,
  unitCatalog,
  livePublic,
  privateProgram,
  privateProfile,
  privateInventory,
  privateActivity,
  privateNews,
  privateFeedback,
}

extension ClientSyncComponentWireName on ClientSyncComponent {
  String get wireName => switch (this) {
    ClientSyncComponent.occasionConfig => 'occasion_config',
    ClientSyncComponent.programCatalog => 'program_catalog',
    ClientSyncComponent.mapCatalog => 'map_catalog',
    ClientSyncComponent.contentCatalog => 'content_catalog',
    ClientSyncComponent.unitCatalog => 'unit_catalog',
    ClientSyncComponent.livePublic => 'live_public',
    ClientSyncComponent.privateProgram => 'private_program',
    ClientSyncComponent.privateProfile => 'private_profile',
    ClientSyncComponent.privateInventory => 'private_inventory',
    ClientSyncComponent.privateActivity => 'private_activity',
    ClientSyncComponent.privateNews => 'private_news',
    ClientSyncComponent.privateFeedback => 'private_feedback',
  };

  bool get isPrivate => wireName.startsWith('private_');

  /// Whether replacing this component changes text or relationships indexed
  /// by global search. Occasion configuration participates because feature
  /// flags decide which content types are searchable. Live counters and
  /// per-user state deliberately do not.
  bool get affectsSearchIndex => switch (this) {
    ClientSyncComponent.occasionConfig ||
    ClientSyncComponent.programCatalog ||
    ClientSyncComponent.mapCatalog ||
    ClientSyncComponent.contentCatalog => true,
    _ => false,
  };

  static ClientSyncComponent parse(String value) =>
      ClientSyncComponent.values.firstWhere((item) => item.wireName == value);
}

String clientSyncSearchProjectionSignature(
  String publicScope,
  Map<ClientSyncComponent, int> revisions,
) => [
  publicScope,
  for (final component in ClientSyncComponent.values)
    if (component.affectsSearchIndex)
      '${component.wireName}:${revisions[component] ?? -1}',
].join('|');

class SyncContext {
  const SyncContext({
    required this.organizationId,
    required this.occasionId,
    required this.occasionLink,
    required this.identityEpoch,
    this.userId,
  });

  final int organizationId;
  final int occasionId;
  final String occasionLink;
  final String? userId;
  final int identityEpoch;

  bool get isAuthenticated => userId != null;
  String get publicScope => '$organizationId/$occasionId';
  String? get privateScope => userId == null
      ? null
      : '$organizationId/$occasionId/$userId/$identityEpoch';
}

class ArtifactDescriptor {
  const ArtifactDescriptor({
    required this.revision,
    required this.mediaType,
    required this.url,
    required this.sha256,
    required this.bytes,
  });

  final int revision;
  final String mediaType;
  final Uri url;
  final String sha256;
  final int bytes;

  factory ArtifactDescriptor.fromJson(Map<String, dynamic> json) =>
      ArtifactDescriptor(
        revision: json['revision'] as int,
        mediaType: json['mediaType'] as String? ?? 'application/json',
        url: Uri.parse(json['url'] as String),
        sha256: json['sha256'] as String,
        bytes: json['bytes'] as int,
      );

  Map<String, dynamic> toJson() => {
    'revision': revision,
    'mediaType': mediaType,
    'url': url.toString(),
    'sha256': sha256,
    'bytes': bytes,
  };
}

class ReleaseManifest {
  const ReleaseManifest({
    required this.protocol,
    required this.schema,
    required this.scope,
    required this.releaseRevision,
    required this.generatedAt,
    required this.components,
  });

  static const requiredComponents = {
    ClientSyncComponent.occasionConfig,
    ClientSyncComponent.programCatalog,
    ClientSyncComponent.mapCatalog,
    ClientSyncComponent.contentCatalog,
    ClientSyncComponent.unitCatalog,
  };

  final int protocol;
  final int schema;
  final String scope;
  final int releaseRevision;
  final DateTime generatedAt;
  final Map<ClientSyncComponent, ArtifactDescriptor> components;

  factory ReleaseManifest.fromBytes(List<int> bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final descriptors = (json['components'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        ClientSyncComponentWireName.parse(key),
        ArtifactDescriptor.fromJson((value as Map).cast<String, dynamic>()),
      ),
    );
    final missing = requiredComponents.difference(descriptors.keys.toSet());
    if (missing.isNotEmpty) {
      throw FormatException(
        'Release manifest misses required components: $missing',
      );
    }
    return ReleaseManifest(
      protocol: json['protocol'] as int,
      schema: json['schema'] as int,
      scope: json['scope'] as String,
      releaseRevision: json['releaseRevision'] as int,
      generatedAt: DateTime.parse(json['generatedAt'] as String).toUtc(),
      components: descriptors,
    );
  }
}

class PublicSyncHead {
  const PublicSyncHead({
    required this.protocol,
    required this.serverTime,
    required this.catalog,
    required this.live,
    required this.publicationPending,
  });

  final int protocol;
  final DateTime serverTime;
  final ArtifactDescriptor? catalog;
  final ArtifactDescriptor? live;
  final bool publicationPending;

  factory PublicSyncHead.fromJson(Map<String, dynamic> json) => PublicSyncHead(
    protocol: json['protocol'] as int,
    serverTime: DateTime.parse(json['serverTime'] as String).toUtc(),
    catalog: json['catalog'] == null
        ? null
        : ArtifactDescriptor.fromJson(
            (json['catalog'] as Map).cast<String, dynamic>(),
          ),
    live: json['live'] == null
        ? null
        : ArtifactDescriptor.fromJson(
            (json['live'] as Map).cast<String, dynamic>(),
          ),
    publicationPending: json['publicationPending'] as bool? ?? false,
  );
}

class PrivateComponentReplacement {
  const PrivateComponentReplacement({
    required this.component,
    required this.revision,
    required this.payload,
  });

  final ClientSyncComponent component;
  final int revision;
  final Object? payload;
}

class PrivateSyncResponse {
  const PrivateSyncResponse({
    required this.serverTime,
    required this.vector,
    required this.replacements,
  });

  final DateTime serverTime;
  final Map<ClientSyncComponent, int> vector;
  final List<PrivateComponentReplacement> replacements;
}

enum SyncReason {
  bootstrap,
  timer,
  navigation,
  resume,
  reconnect,
  login,
  logout,
  manual,
}

enum SyncFreshnessClass { catalog, live, privateIdentity }

class SyncClassState {
  const SyncClassState({
    this.revision,
    this.lastSuccess,
    this.error,
    this.inFlight = false,
  });

  final int? revision;
  final DateTime? lastSuccess;
  final Object? error;
  final bool inFlight;

  SyncClassState copyWith({
    int? revision,
    DateTime? lastSuccess,
    Object? error,
    bool clearError = false,
    bool? inFlight,
  }) => SyncClassState(
    revision: revision ?? this.revision,
    lastSuccess: lastSuccess ?? this.lastSuccess,
    error: clearError ? null : error ?? this.error,
    inFlight: inFlight ?? this.inFlight,
  );
}

class ClientSyncState {
  const ClientSyncState({required this.context, required this.classes});

  final SyncContext context;
  final Map<SyncFreshnessClass, SyncClassState> classes;

  ClientSyncState replace(SyncFreshnessClass type, SyncClassState state) =>
      ClientSyncState(context: context, classes: {...classes, type: state});
}
