import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/requests/create_room_request.dart';
import 'package:boom_board/core/data/models/requests/join_room_request.dart';
import 'package:boom_board/core/data/repositories/room_server_repository_impl.dart';
import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/mocks.dart';

void main() {
  late MockRoomSocketService socketService;
  late RoomServerRepositoryImpl repository;

  setUpAll(registerTestFallbackValues);

  setUp(() {
    socketService = MockRoomSocketService();
    repository = RoomServerRepositoryImpl(socketService: socketService);
  });

  group('createRoom', () {
    test('maps the response model onto a domain entity', () async {
      when(() => socketService.createRoom(request: any(named: 'request'))).thenAnswer(
        (_) async => CreateRoomResponse.fromJson(
          createRoomResponseJson(
            roomCode: 'WXYZ',
            hostId: 'p-1',
            players: [playerJson(id: 'p-1', name: 'Alice', hasPositioned: true)],
          ),
        ),
      );

      final entity = await repository.createRoom(CreateRoomRequest(playerName: 'Alice'));

      expect(entity.roomCode, 'WXYZ');
      expect(entity.gameMode, GameMode.simple);
      expect(entity.hostId, 'p-1');
      expect(entity.playerList.single.name, 'Alice');
      expect(entity.playerList.single.hasPositioned, isTrue);
    });

    test('passes the request straight through', () async {
      final request = CreateRoomRequest(playerName: 'Alice');
      when(() => socketService.createRoom(request: any(named: 'request'))).thenAnswer(
        (_) async => CreateRoomResponse.fromJson(createRoomResponseJson()),
      );

      await repository.createRoom(request);

      verify(() => socketService.createRoom(request: request)).called(1);
    });

    test('maps an empty player list to an empty entity list', () async {
      when(() => socketService.createRoom(request: any(named: 'request'))).thenAnswer(
        (_) async => CreateRoomResponse.fromJson(
          createRoomResponseJson(players: <Map<String, dynamic>>[]),
        ),
      );

      final entity = await repository.createRoom(CreateRoomRequest(playerName: 'Alice'));

      expect(entity.playerList, isEmpty);
    });

    test('propagates a data-source error without wrapping it', () async {
      when(() => socketService.createRoom(request: any(named: 'request')))
          .thenThrow(InvalidSocketResponseException());

      await expectLater(
        repository.createRoom(CreateRoomRequest(playerName: 'Alice')),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });
  });

  group('joinRoom', () {
    test('maps the response model onto a domain entity', () async {
      when(() => socketService.joinRoom(request: any(named: 'request'))).thenAnswer(
        (_) async => JoinRoomResponse.fromJson(joinRoomResponseJson(roomCode: 'QRST')),
      );

      final entity = await repository.joinRoom(
        JoinRoomRequest(playerName: 'Bob', roomCode: 'QRST'),
      );

      expect(entity.roomCode, 'QRST');
      expect(entity.playerList.map((p) => p.name), ['Alice', 'Bob']);
    });

    test('preserves player order', () async {
      when(() => socketService.joinRoom(request: any(named: 'request'))).thenAnswer(
        (_) async => JoinRoomResponse.fromJson(
          joinRoomResponseJson(
            players: [playerJson(id: 'c'), playerJson(id: 'a'), playerJson(id: 'b')],
          ),
        ),
      );

      final entity = await repository.joinRoom(
        JoinRoomRequest(playerName: 'Bob', roomCode: 'ABCD'),
      );

      expect(entity.playerList.map((p) => p.id), ['c', 'a', 'b']);
    });
  });

  group('leaveRoom', () {
    test('delegates to the data source', () async {
      when(() => socketService.leaveRoom()).thenAnswer((_) async {});

      await repository.leaveRoom();

      verify(() => socketService.leaveRoom()).called(1);
    });

    test('propagates a data-source error', () async {
      when(() => socketService.leaveRoom()).thenThrow(InvalidSocketResponseException());

      await expectLater(
        repository.leaveRoom(),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });
  });
}
