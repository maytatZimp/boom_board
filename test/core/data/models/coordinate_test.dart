import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fixtures.dart';

void main() {
  group('Coordinate.fromJson', () {
    test('reads x and y', () {
      final coordinate = Coordinate.fromJson(coordinateJson(x: 3, y: 7));

      expect(coordinate.x, 3);
      expect(coordinate.y, 7);
    });

    test('throws when a key is missing', () {
      expect(
        () => Coordinate.fromJson(<String, dynamic>{'x': 1}),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws when a coordinate arrives as a String', () {
      expect(
        () => Coordinate.fromJson(<String, dynamic>{'x': '1', 'y': 2}),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('Coordinate equality', () {
    test('two coordinates with the same x and y are equal', () {
      expect(Coordinate(x: 2, y: 5), Coordinate(x: 2, y: 5));
    });

    test('transposed coordinates are not equal', () {
      // hashCode is `x.hashCode ^ y.hashCode`, and XOR is commutative, so
      // (1,2) and (2,1) collide in a hash bucket. Correct behaviour still
      // depends on `==` telling them apart -- this guards that.
      expect(Coordinate(x: 1, y: 2), isNot(Coordinate(x: 2, y: 1)));
      expect(Coordinate(x: 1, y: 2).hashCode, Coordinate(x: 2, y: 1).hashCode);
    });

    test('equal coordinates share a hashCode', () {
      expect(Coordinate(x: 4, y: 4).hashCode, Coordinate(x: 4, y: 4).hashCode);
    });

    test('a non-Coordinate is never equal', () {
      expect(Coordinate(x: 0, y: 0) == Object(), isFalse);
    });

    test('deduplicates in a Set, including the transposed pair', () {
      final tiles = <Coordinate>{
        Coordinate(x: 1, y: 2),
        Coordinate(x: 1, y: 2),
        Coordinate(x: 2, y: 1),
      };

      expect(tiles.length, 2);
    });

    test('contains works for a value-equal lookup', () {
      final destroyed = <Coordinate>[Coordinate(x: 3, y: 3)];

      expect(destroyed.contains(Coordinate(x: 3, y: 3)), isTrue);
      expect(destroyed.contains(Coordinate(x: 3, y: 4)), isFalse);
    });
  });
}
