import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/gpx_importer.dart';

/// GPX import: turn a route exported from Mapy.com / Strava / Garmin into
/// free-point path segments.
void main() {
  test('parses a track with two segments (preserves gaps)', () {
    const gpx = '''
<?xml version="1.0"?>
<gpx version="1.1">
  <trk><name>r</name>
    <trkseg>
      <trkpt lat="49.83" lon="18.28"/>
      <trkpt lat="49.84" lon="18.29"/>
    </trkseg>
    <trkseg>
      <trkpt lat="49.90" lon="18.40"/>
      <trkpt lat="49.91" lon="18.41"/>
      <trkpt lat="49.92" lon="18.42"/>
    </trkseg>
  </trk>
</gpx>''';

    final segments = GpxImporter.parse(gpx);
    expect(segments, hasLength(2));
    expect(segments[0], hasLength(2));
    expect(segments[1], hasLength(3));
    expect(segments[0].first.isPoint, isTrue);
    expect(segments[0].first.lat, 49.83);
    expect(segments[0].first.lng, 18.28);
  });

  test('handles lon-before-lat attribute order', () {
    const gpx = '<gpx><rte>'
        '<rtept lon="18.28" lat="49.83"/>'
        '<rtept lon="18.29" lat="49.84"/>'
        '</rte></gpx>';
    final segments = GpxImporter.parse(gpx);
    expect(segments, hasLength(1));
    expect(segments[0].first.lat, 49.83);
    expect(segments[0].first.lng, 18.28);
  });

  test('prefers track over route when both present', () {
    const gpx = '<gpx>'
        '<trk><trkseg><trkpt lat="1.0" lon="2.0"/><trkpt lat="1.1" lon="2.1"/></trkseg></trk>'
        '<rte><rtept lat="9.0" lon="9.0"/><rtept lat="9.1" lon="9.1"/></rte>'
        '</gpx>';
    final segments = GpxImporter.parse(gpx);
    expect(segments, hasLength(1));
    expect(segments[0].first.lat, 1.0); // from the track, not the route
  });

  test('decimates long segments while keeping endpoints', () {
    final buf = StringBuffer('<gpx><trk><trkseg>');
    for (var i = 0; i < 1000; i++) {
      buf.write('<trkpt lat="${40 + i * 0.001}" lon="10.0"/>');
    }
    buf.write('</trkseg></trk></gpx>');

    final segments = GpxImporter.parse(buf.toString());
    expect(segments, hasLength(1));
    expect(segments[0].length, GpxImporter.maxPointsPerSegment);
    // Endpoints preserved exactly.
    expect(segments[0].first.lat, 40.0);
    expect(segments[0].last.lat, closeTo(40 + 999 * 0.001, 1e-9));
  });

  test('empty / coordinate-less GPX yields no segments', () {
    expect(GpxImporter.parse('<gpx></gpx>'), isEmpty);
    expect(GpxImporter.parse('not xml at all'), isEmpty);
  });
}
