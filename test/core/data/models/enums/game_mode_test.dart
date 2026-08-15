import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameMode.fromString', () {
    test('parses every known wire value', () {
      expect(GameMode.fromString('simple'), GameMode.simple);
    });

    test('round-trips through toString for every enum value', () {
      for (final mode in GameMode.values) {
        expect(GameMode.fromString(mode.toString()), mode);
      }
    });

    test('throws on an unknown value', () {
      expect(
        () => GameMode.fromString('battle_royale'),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });

    test('is case sensitive', () {
      expect(
        () => GameMode.fromString('SIMPLE'),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });

    test('throws on an empty string', () {
      expect(
        () => GameMode.fromString(''),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });
  });
}
