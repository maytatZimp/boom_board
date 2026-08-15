import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/game_started_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../../helpers/fixtures.dart';

void main() {
  group('GameStartedModel.fromJson', () {
    test('flattens the nested boardSize object', () {
      final model = GameStartedModel.fromJson(gameStartedJson(width: 8, height: 8));

      expect(model.boardWidth, 8);
      expect(model.boardHeight, 8);
    });

    test('parses state, timeLimit and destroyed tiles', () {
      final model = GameStartedModel.fromJson(
        gameStartedJson(
          state: 'position',
          timeLimit: 45,
          destroyedTiles: [coordinateJson(x: 2, y: 2)],
        ),
      );

      expect(model.state, GameState.position);
      expect(model.timeLimit, 45);
      expect(model.destroyedTiles.single.x, 2);
    });

    test('throws when boardSize is absent', () {
      // NoSuchMethodError, not TypeError: the nested read is
      // `json['boardSize']['width']`, so the failure is indexing into null
      // rather than a failed cast.
      final json = gameStartedJson()..remove('boardSize');

      expect(() => GameStartedModel.fromJson(json), throwsA(isA<NoSuchMethodError>()));
    });

    test('throws when boardSize is present but missing width', () {
      final json = gameStartedJson();
      json['boardSize'] = <String, dynamic>{'height': 8};

      expect(() => GameStartedModel.fromJson(json), throwsA(isA<TypeError>()));
    });
  });
}
