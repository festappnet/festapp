import 'package:festapp_core/map.dart';
import 'package:test/test.dart';

void main() {
  group('PathNode', () {
    test('place ref serializes to a bare int', () {
      final node = PathNode.place(7);
      expect(node.isPoint, isFalse);
      expect(node.placeId, 7);
      expect(node.toJson(), 7);
    });

    test('free point serializes to a {lat,lng} map', () {
      final node = PathNode.point(49.83, 18.28);
      expect(node.isPoint, isTrue);
      expect(node.placeId, isNull);
      expect(node.toJson(), {'lat': 49.83, 'lng': 18.28});
    });

    test('fromJson parses numbers as place refs and maps as points', () {
      expect(PathNode.fromJson(3), PathNode.place(3));
      expect(PathNode.fromJson(3.0), PathNode.place(3));
      expect(
        PathNode.fromJson({'lat': 1.5, 'lng': 2.5}),
        PathNode.point(1.5, 2.5),
      );
    });

    test('fromJson returns null for unrecognized input', () {
      expect(PathNode.fromJson('nope'), isNull);
      expect(PathNode.fromJson({'lat': 1.0}), isNull);
    });
  });
}
