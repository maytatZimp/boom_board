import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/round_resolved_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../../helpers/fixtures.dart';

void main() {
  group('RoundResolvedModel.fromJson', () {
    test('parses a full round payload across all five nested lists', () {
      final model = RoundResolvedModel.fromJson(
        roundResolvedJson(
          explosions: [
            explosionJson(bomberId: 'p-1', victimId: 'p-2', isHit: true, x: 1, y: 1),
            explosionJson(bomberId: 'p-2', x: 5, y: 5),
          ],
          remainingPlayers: [playerJson(id: 'p-1'), playerJson(id: 'p-2', name: 'Bob')],
          destroyedTiles: [coordinateJson(x: 0, y: 0), coordinateJson(x: 7, y: 7)],
          newDestroyedTiles: [coordinateJson(x: 7, y: 7)],
          newLogs: [actionLogJson(id: 'log-a'), actionLogJson(id: 'log-b')],
          roundNumber: 4,
        ),
      );

      expect(model.explosionList, hasLength(2));
      expect(model.explosionList.first.victimId, 'p-2');
      expect(model.playerList, hasLength(2));
      expect(model.playerList.last.name, 'Bob');
      expect(model.destroyedTiles, hasLength(2));
      expect(model.destroyedTiles.last, Coordinate(x: 7, y: 7));
      expect(model.newDestroyedTiles, hasLength(1));
      expect(model.newLogs, hasLength(2));
      expect(model.roundNumber, 4);
    });

    test('parses a quiet round with every list empty', () {
      final model = RoundResolvedModel.fromJson(
        roundResolvedJson(
          explosions: <Map<String, dynamic>>[],
          remainingPlayers: <Map<String, dynamic>>[],
          destroyedTiles: <Map<String, dynamic>>[],
          newDestroyedTiles: <Map<String, dynamic>>[],
          newLogs: <Map<String, dynamic>>[],
          roundNumber: 1,
        ),
      );

      expect(model.explosionList, isEmpty);
      expect(model.playerList, isEmpty);
      expect(model.destroyedTiles, isEmpty);
      expect(model.newDestroyedTiles, isEmpty);
      expect(model.newLogs, isEmpty);
    });

    test('reads the remainingPlayers key, not players', () {
      // The wire key and the Dart field name differ here; a rename on either
      // side silently yields an empty player list without this test.
      final json = roundResolvedJson(remainingPlayers: [playerJson(id: 'only')]);
      json['players'] = <Map<String, dynamic>>[playerJson(id: 'decoy')];

      final model = RoundResolvedModel.fromJson(json);

      expect(model.playerList.single.id, 'only');
    });

    test('one malformed player aborts the whole round parse', () {
      // The parse is all-or-nothing: a single bad entry in remainingPlayers
      // throws, the socket handler catches it, and the entire roundResolved
      // event is dropped rather than partially applied.
      final bad = playerJson(id: 'p-2')..remove('isAlive');
      final json = roundResolvedJson(remainingPlayers: [playerJson(id: 'p-1'), bad]);

      expect(() => RoundResolvedModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws when a list key is absent entirely', () {
      final json = roundResolvedJson()..remove('newLogs');

      expect(() => RoundResolvedModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws when roundNumber is absent', () {
      final json = roundResolvedJson()..remove('roundNumber');

      expect(() => RoundResolvedModel.fromJson(json), throwsA(isA<TypeError>()));
    });
  });
}
