import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameState.fromString', () {
    test('parses every known wire value', () {
      expect(GameState.fromString('lobby'), GameState.lobby);
      expect(GameState.fromString('position'), GameState.position);
      expect(GameState.fromString('attack'), GameState.attack);
      expect(GameState.fromString('process'), GameState.process);
      expect(GameState.fromString('end'), GameState.end);
    });

    test('round-trips through toString for every enum value', () {
      for (final state in GameState.values) {
        expect(GameState.fromString(state.toString()), state);
      }
    });

    test('throws on an unknown phase', () {
      expect(
        () => GameState.fromString('sudden_death'),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });

    test('is case sensitive', () {
      expect(
        () => GameState.fromString('Attack'),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });
  });
}
