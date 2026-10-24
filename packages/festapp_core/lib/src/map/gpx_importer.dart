import 'path_node.dart';

/// Parses GPX (GPS Exchange Format) into path segments of free-point
/// [PathNode]s. Works with routes exported from Mapy.com, Strava, Garmin,
/// komoot, etc. — GPX is the universal interchange format, so this covers the
/// "load a route drawn elsewhere" case without any external API.
///
/// Extraction preference: track segments (`<trkseg>` of `<trkpt>`) → route
/// (`<rte>` of `<rtept>`) → standalone waypoints (`<wpt>`). Each `<trkseg>`
/// becomes its own path segment so gaps in a multi-segment track survive.
class GpxImporter {
  /// Hard cap on points kept per segment. GPX tracks routinely carry thousands
  /// of points; storing them all would bloat `path_data`. Longer segments are
  /// evenly decimated down to this many points (endpoints always preserved).
  static const int maxPointsPerSegment = 300;

  /// Parse [gpx] and return one list of nodes per segment. Returns an empty
  /// list when no coordinates are found. Never throws on malformed input — it
  /// simply extracts whatever valid `lat`/`lon` pairs it can find.
  static List<List<PathNode>> parse(String gpx) {
    // Prefer track segments (the actual traced geometry).
    final segments = _parseTagGroups(
      gpx,
      groupTag: 'trkseg',
      pointTag: 'trkpt',
    );
    if (segments.isNotEmpty) return segments;

    // Fall back to a planned route.
    final route = _parseTagGroups(gpx, groupTag: 'rte', pointTag: 'rtept');
    if (route.isNotEmpty) return route;

    // Last resort: standalone waypoints as a single segment.
    final wpts = _parsePoints(gpx, 'wpt');
    return wpts.isEmpty ? [] : [_decimate(wpts)];
  }

  /// Extract every `<groupTag>…</groupTag>` block and, within each, its
  /// `<pointTag>` coordinates. Groups yielding fewer than 2 points are dropped.
  static List<List<PathNode>> _parseTagGroups(
    String gpx, {
    required String groupTag,
    required String pointTag,
  }) {
    final groupRe = RegExp(
      '<$groupTag\\b[^>]*>(.*?)</$groupTag>',
      dotAll: true,
      caseSensitive: false,
    );
    final result = <List<PathNode>>[];
    for (final m in groupRe.allMatches(gpx)) {
      final pts = _parsePoints(m.group(1)!, pointTag);
      if (pts.length >= 2) result.add(_decimate(pts));
    }
    return result;
  }

  /// Extract all `<pointTag ... lat=".." lon="..">` coordinates in document
  /// order. Attribute order (lat/lon vs lon/lat) does not matter.
  static List<PathNode> _parsePoints(String xml, String pointTag) {
    final tagRe = RegExp(
      '<$pointTag\\b([^>]*)',
      dotAll: true,
      caseSensitive: false,
    );
    final latRe = RegExp(r'''\blat\s*=\s*["']([-\d.]+)["']''');
    final lonRe = RegExp(r'''\blon\s*=\s*["']([-\d.]+)["']''');
    final points = <PathNode>[];
    for (final m in tagRe.allMatches(xml)) {
      final attrs = m.group(1)!;
      final lat = double.tryParse(latRe.firstMatch(attrs)?.group(1) ?? '');
      final lon = double.tryParse(lonRe.firstMatch(attrs)?.group(1) ?? '');
      if (lat != null && lon != null) points.add(PathNode.point(lat, lon));
    }
    return points;
  }

  /// Evenly reduce [points] to at most [maxPointsPerSegment], always keeping
  /// the first and last point so the segment's endpoints are exact.
  static List<PathNode> _decimate(List<PathNode> points) {
    if (points.length <= maxPointsPerSegment) return points;
    final step = (points.length - 1) / (maxPointsPerSegment - 1);
    final out = <PathNode>[];
    for (var i = 0; i < maxPointsPerSegment; i++) {
      out.add(points[(i * step).round()]);
    }
    return out;
  }
}
