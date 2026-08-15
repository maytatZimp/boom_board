import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:flutter_test/flutter_test.dart';

SimpleModePlayerEntity buildPlayer({
  String id = 'p-1',
  bool hasPositioned = false,
  bool hasThrowBomb = false,
  int? x,
  int? y,
  int? throwOrder,
}) {
  return SimpleModePlayerEntity(
    id: id,
    name: 'Alice',
    isAlive: true,
    hasPositioned: hasPositioned,
    hasThrowBomb: hasThrowBomb,
    isDisconnected: false,
    x: x,
    y: y,
    throwOrder: throwOrder,
  );
}

void main() {
  group('SimpleModePlayerEntity.copyWith', () {
    test('returns an identical copy when given no arguments', () {
      final original = buildPlayer(x: 3, y: 4, throwOrder: 2, hasPositioned: true);
      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.name, original.name);
      expect(copy.isAlive, original.isAlive);
      expect(copy.hasPositioned, original.hasPositioned);
      expect(copy.hasThrowBomb, original.hasThrowBomb);
      expect(copy.isDisconnected, original.isDisconnected);
      expect(copy.x, original.x);
      expect(copy.y, original.y);
      expect(copy.throwOrder, original.throwOrder);
    });

    test('returns a new instance rather than mutating in place', () {
      final original = buildPlayer();

      expect(identical(original.copyWith(), original), isFalse);
    });

    test('overrides only the fields it is given', () {
      final copy = buildPlayer(x: 3, y: 4).copyWith(hasPositioned: true);

      expect(copy.hasPositioned, isTrue);
      expect(copy.x, 3);
      expect(copy.y, 4);
    });

    test('carries throwOrder forward when it is not passed', () {
      expect(buildPlayer(throwOrder: 5).copyWith(hasThrowBomb: true).throwOrder, 5);
    });

    test('sets throwOrder when passed', () {
      expect(buildPlayer().copyWith(throwOrder: 1).throwOrder, 1);
    });

    group('clearThrowOrder', () {
      test('nulls an existing throwOrder', () {
        expect(buildPlayer(throwOrder: 3).copyWith(clearThrowOrder: true).throwOrder, isNull);
      });

      test('wins over a throwOrder passed in the same call', () {
        // The only non-trivial branch in copyWith: the ternary checks
        // clearThrowOrder first, so an explicit throwOrder is discarded.
        final copy = buildPlayer(throwOrder: 3).copyWith(throwOrder: 9, clearThrowOrder: true);

        expect(copy.throwOrder, isNull);
      });

      test('defaults to false, preserving throwOrder', () {
        expect(buildPlayer(throwOrder: 3).copyWith().throwOrder, 3);
      });
    });

    test('cannot clear x or y back to null', () {
      // `x ?? this.x` means a null argument is indistinguishable from an
      // omitted one. Once a player has a position it survives every copyWith,
      // which is what onRoundResolvedEventReceived depends on to keep the
      // local player's coordinates across a server list replacement.
      final positioned = buildPlayer(x: 3, y: 4);

      expect(positioned.copyWith(x: null, y: null).x, 3);
      expect(positioned.copyWith(x: null, y: null).y, 4);
    });

    test('overwrites x and y when new values are given', () {
      final moved = buildPlayer(x: 3, y: 4).copyWith(x: 7, y: 0);

      expect(moved.x, 7);
      expect(moved.y, 0);
    });
  });
}
