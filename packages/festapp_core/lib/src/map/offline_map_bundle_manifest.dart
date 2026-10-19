class OfflineMapBundleException implements Exception {
  OfflineMapBundleException(this.message);

  final String message;

  @override
  String toString() => 'OfflineMapBundleException: $message';
}

enum OfflineMapAssetRole {
  style,
  pmtiles,
  mbtiles,
  spriteJson1x,
  spritePng1x,
  spriteJson2x,
  spritePng2x,
  glyph,
}

enum OfflineMapBundleMode { mbtiles, mapLibreOnly }

class OfflineMapBundleAsset {
  const OfflineMapBundleAsset({
    required this.role,
    required this.path,
    required this.url,
    required this.bytes,
    required this.sha256,
  });

  final OfflineMapAssetRole role;
  final String path;
  final Uri url;
  final int bytes;
  final String sha256;
}

class OfflineMapBundleManifest {
  OfflineMapBundleManifest._({
    required this.bundleMode,
    required this.artifactVersion,
    required this.sourceName,
    required this.baseUrl,
    required this.assets,
  });

  static const _roleNames = <String, OfflineMapAssetRole>{
    'style': OfflineMapAssetRole.style,
    'pmtiles': OfflineMapAssetRole.pmtiles,
    'mbtiles': OfflineMapAssetRole.mbtiles,
    'sprite_json_1x': OfflineMapAssetRole.spriteJson1x,
    'sprite_png_1x': OfflineMapAssetRole.spritePng1x,
    'sprite_json_2x': OfflineMapAssetRole.spriteJson2x,
    'sprite_png_2x': OfflineMapAssetRole.spritePng2x,
    'glyph': OfflineMapAssetRole.glyph,
  };

  static const _mapLibreRoles = <OfflineMapAssetRole>{
    OfflineMapAssetRole.style,
    OfflineMapAssetRole.pmtiles,
    OfflineMapAssetRole.spriteJson1x,
    OfflineMapAssetRole.spritePng1x,
    OfflineMapAssetRole.spriteJson2x,
    OfflineMapAssetRole.spritePng2x,
  };

  final OfflineMapBundleMode bundleMode;
  final String artifactVersion;
  final String sourceName;
  final Uri baseUrl;
  final List<OfflineMapBundleAsset> assets;

  factory OfflineMapBundleManifest.parse(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'];
    final bundleMode = switch (schemaVersion) {
      2 when json['bundle_mode'] == null => OfflineMapBundleMode.mbtiles,
      3 when json['bundle_mode'] == 'maplibre_only' =>
        OfflineMapBundleMode.mapLibreOnly,
      _ => throw OfflineMapBundleException(
        'Unsupported manifest schema version or bundle mode.',
      ),
    };
    final artifactVersion = _nonEmptyString(json, 'artifact_version');
    final sourceName = _nonEmptyString(json, 'source_name');
    if (!_isSafeDirectorySegment(artifactVersion) ||
        !_isSafeDirectorySegment(sourceName)) {
      throw OfflineMapBundleException(
        'artifact_version and source_name must be safe directory names.',
      );
    }
    final baseUrl = Uri.tryParse(_nonEmptyString(json, 'base_url'));
    if (baseUrl == null || baseUrl.scheme != 'https' || !baseUrl.hasAuthority) {
      throw OfflineMapBundleException(
        'base_url must be an absolute HTTPS URL.',
      );
    }
    final rawAssets = json['assets'];
    if (rawAssets is! List) {
      throw OfflineMapBundleException('assets must be a list.');
    }

    final assets = <OfflineMapBundleAsset>[];
    final paths = <String>{};
    final singleRoles = <OfflineMapAssetRole>{};
    for (final raw in rawAssets) {
      if (raw is! Map) {
        throw OfflineMapBundleException('Every asset must be an object.');
      }
      final assetJson = Map<String, dynamic>.from(raw);
      final roleName = _nonEmptyString(assetJson, 'role');
      final role = _roleNames[roleName];
      if (role == null) {
        throw OfflineMapBundleException('Unknown asset role: $roleName.');
      }
      final path = _nonEmptyString(assetJson, 'path');
      if (!_isSafeRelativePath(path) || !paths.add(path)) {
        throw OfflineMapBundleException(
          'Invalid or duplicate asset path: $path.',
        );
      }
      if (role != OfflineMapAssetRole.glyph && !singleRoles.add(role)) {
        throw OfflineMapBundleException('Duplicate asset role: $roleName.');
      }
      final url = Uri.tryParse(_nonEmptyString(assetJson, 'url'));
      if (url == null || url.scheme != 'https' || !url.hasAuthority) {
        throw OfflineMapBundleException('Asset URL must use HTTPS: $path.');
      }
      final bytes = assetJson['bytes'];
      final hash = assetJson['sha256'];
      if (bytes is! int ||
          bytes < 0 ||
          hash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw OfflineMapBundleException('Invalid size or SHA-256 for $path.');
      }
      assets.add(
        OfflineMapBundleAsset(
          role: role,
          path: path,
          url: url,
          bytes: bytes,
          sha256: hash,
        ),
      );
    }

    final requiredRoles = <OfflineMapAssetRole>{
      ..._mapLibreRoles,
      if (bundleMode == OfflineMapBundleMode.mbtiles)
        OfflineMapAssetRole.mbtiles,
    };
    final missing = requiredRoles.difference(singleRoles);
    if (missing.isNotEmpty ||
        !assets.any((asset) => asset.role == OfflineMapAssetRole.glyph)) {
      throw OfflineMapBundleException('Manifest is missing required assets.');
    }
    for (final fontStack in const ['noto_sans_regular', 'noto_sans_bold']) {
      if (!assets.any(
        (asset) =>
            asset.role == OfflineMapAssetRole.glyph &&
            asset.path.startsWith('glyphs/$fontStack/'),
      )) {
        throw OfflineMapBundleException('Missing glyphs for $fontStack.');
      }
    }

    return OfflineMapBundleManifest._(
      bundleMode: bundleMode,
      artifactVersion: artifactVersion,
      sourceName: sourceName,
      baseUrl: baseUrl,
      assets: List.unmodifiable(assets),
    );
  }

  OfflineMapBundleAsset assetFor(OfflineMapAssetRole role) {
    return assets.singleWhere((asset) => asset.role == role);
  }

  static String _nonEmptyString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw OfflineMapBundleException('$key must be a non-empty string.');
    }
    return value;
  }

  static bool _isSafeRelativePath(String path) {
    final uri = Uri.tryParse(path);
    return uri != null &&
        !uri.hasScheme &&
        !path.startsWith('/') &&
        !path.startsWith('\\') &&
        !path.split('/').contains('..') &&
        !path.split('/').contains('.') &&
        !path.contains('\\');
  }

  static bool _isSafeDirectorySegment(String value) =>
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      !value.contains(r'\');
}
