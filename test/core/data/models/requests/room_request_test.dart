import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/requests/create_room_request.dart';
import 'package:boom_board/core/data/models/requests/join_room_request.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  group('CreateRoomRequest.toJson', () {
    test('emits the playerName key the server expects', () {
      expect(
        CreateRoomRequest(playerName: 'Alice').toJson(),
        <String, dynamic>{'playerName': 'Alice'},
      );
    });

    test('does not trim -- callers are responsible for that', () {
      expect(CreateRoomRequest(playerName: ' Alice ').toJson()['playerName'], ' Alice ');
    });
  });

  group('JoinRoomRequest.toJson', () {
    test('emits playerName and roomCode', () {
      expect(
        JoinRoomRequest(playerName: 'Bob', roomCode: 'ABCD').toJson(),
        <String, dynamic>{'playerName': 'Bob', 'roomCode': 'ABCD'},
      );
    });
  });

  group('CreateRoomResponse.fromJson', () {
    test('parses the room, host and player list', () {
      final response = CreateRoomResponse.fromJson(
        createRoomResponseJson(roomCode: 'WXYZ', hostId: 'p-1'),
      );

      expect(response.roomCode, 'WXYZ');
      expect(response.gameMode, GameMode.simple);
      expect(response.hostId, 'p-1');
      expect(response.playerList.single.id, 'player-1');
    });

    test('reads the players key into playerList', () {
      final response = CreateRoomResponse.fromJson(
        createRoomResponseJson(
          players: [playerJson(id: 'a'), playerJson(id: 'b'), playerJson(id: 'c')],
        ),
      );

      expect(response.playerList.map((p) => p.id), ['a', 'b', 'c']);
    });

    test('accepts an empty player list', () {
      final response = CreateRoomResponse.fromJson(
        createRoomResponseJson(players: <Map<String, dynamic>>[]),
      );

      expect(response.playerList, isEmpty);
    });

    test('throws on an unknown gameMode', () {
      expect(
        () => CreateRoomResponse.fromJson(createRoomResponseJson(gameMode: 'chaos')),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when players is absent', () {
      final json = createRoomResponseJson()..remove('players');

      expect(() => CreateRoomResponse.fromJson(json), throwsA(isA<TypeError>()));
    });
  });

  group('JoinRoomResponse.fromJson', () {
    test('parses the room, host and player list', () {
      final response = JoinRoomResponse.fromJson(joinRoomResponseJson(roomCode: 'QRST'));

      expect(response.roomCode, 'QRST');
      expect(response.gameMode, GameMode.simple);
      expect(response.playerList, hasLength(2));
      expect(response.playerList.last.name, 'Bob');
    });

    test('throws on an unknown gameMode', () {
      expect(
        () => JoinRoomResponse.fromJson(joinRoomResponseJson(gameMode: '')),
        throwsA(isA<Exception>()),
      );
    });
  });
}
