import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  group('PlayerModel.fromJson', () {
    test('reads every field off the wire payload', () {
      final model = PlayerModel.fromJson(
        playerJson(
          id: 'p-9',
          name: 'Zoe',
          isAlive: false,
          hasPositioned: true,
          isDisconnected: true,
        ),
      );

      expect(model.id, 'p-9');
      expect(model.name, 'Zoe');
      expect(model.isAlive, isFalse);
      expect(model.hasPositioned, isTrue);
      expect(model.isDisconnected, isTrue);
    });

    // Characterization: every field is an unchecked cast off a dynamic map, so
    // a null or wrong-typed field from the server is a hard TypeError rather
    // than a defaulted value. These tests pin today's behaviour so a later
    // hardening pass is a deliberate, visible change.
    test('throws when a required field is absent', () {
      final json = playerJson()..remove('isAlive');

      expect(() => PlayerModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws when a bool field arrives as null', () {
      final json = playerJson();
      json['hasPositioned'] = null;

      expect(() => PlayerModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws when a bool field arrives as an int', () {
      final json = playerJson();
      json['isAlive'] = 1;

      expect(() => PlayerModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws when the id arrives as an int', () {
      final json = playerJson();
      json['id'] = 42;

      expect(() => PlayerModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('accepts an empty name', () {
      expect(PlayerModel.fromJson(playerJson(name: '')).name, '');
    });
  });
}
