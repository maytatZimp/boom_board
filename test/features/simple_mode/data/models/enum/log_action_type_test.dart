import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/log_action_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogActionType.fromString', () {
    test('parses every known wire value', () {
      expect(LogActionType.fromString('BOMB_EXPLODED'), LogActionType.bombExploded);
      expect(LogActionType.fromString('PLAYER_ELIMINATED'), LogActionType.playerEliminated);
      expect(LogActionType.fromString('ORBITAL_LASER_FIRED'), LogActionType.orbitalLaserFired);
      expect(LogActionType.fromString('PLAYER_DISCONNECTED'), LogActionType.playerDisconnected);
    });

    test('round-trips through toString for every enum value', () {
      for (final type in LogActionType.values) {
        expect(LogActionType.fromString(type.toString()), type);
      }
    });

    test('throws on an unknown log type', () {
      expect(
        () => LogActionType.fromString('PLAYER_TAUNTED'),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });

    test('rejects the lower-case form of a valid value', () {
      expect(
        () => LogActionType.fromString('bomb_exploded'),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });
  });
}
