import 'package:boom_board/core/data/data_source/room_socket_service.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/requests/create_room_request.dart';
import 'package:boom_board/core/data/models/requests/join_room_request.dart';
import 'package:boom_board/core/exceptions/bb_server_offline_exception.dart';
import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:boom_board/core/utils/socket_response.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/mocks.dart';

void main() {
  late MockSocketService socketService;
  late RoomSocketService service;

  setUpAll(registerTestFallbackValues);

  setUp(() {
    socketService = MockSocketService();
    service = RoomSocketService(socketService: socketService);
  });

  void stubEmit(SocketResponse response) {
    when(
      () => socketService.emitSocket(
        actionName: any(named: 'actionName'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => response);
  }

  group('createRoom', () {
    test('emits createRoom with the serialised request', () async {
      stubEmit(SocketResponse(code: 200, data: createRoomResponseJson()));

      await service.createRoom(request: CreateRoomRequest(playerName: 'Alice'));

      verify(
        () => socketService.emitSocket(
          actionName: 'createRoom',
          data: <String, dynamic>{'playerName': 'Alice'},
        ),
      ).called(1);
    });

    test('parses the ack payload into a CreateRoomResponse', () async {
      stubEmit(
        SocketResponse(code: 200, data: createRoomResponseJson(roomCode: 'WXYZ', hostId: 'p-1')),
      );

      final response = await service.createRoom(request: CreateRoomRequest(playerName: 'Alice'));

      expect(response.roomCode, 'WXYZ');
      expect(response.hostId, 'p-1');
      expect(response.gameMode, GameMode.simple);
    });

    test('throws InvalidSocketResponseException when the ack carries no data', () async {
      stubEmit(SocketResponse(code: 200, data: null));

      await expectLater(
        service.createRoom(request: CreateRoomRequest(playerName: 'Alice')),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });

    test('lets a server-offline error propagate untouched', () async {
      when(
        () => socketService.emitSocket(
          actionName: any(named: 'actionName'),
          data: any(named: 'data'),
        ),
      ).thenThrow(BbServerOfflineException(code: 503, errorType: 'SERVER_OFFLINE'));

      await expectLater(
        service.createRoom(request: CreateRoomRequest(playerName: 'Alice')),
        throwsA(isA<BbServerOfflineException>()),
      );
    });
  });

  group('joinRoom', () {
    test('emits joinRoom with both fields serialised', () async {
      stubEmit(SocketResponse(code: 200, data: joinRoomResponseJson()));

      await service.joinRoom(request: JoinRoomRequest(playerName: 'Bob', roomCode: 'ABCD'));

      verify(
        () => socketService.emitSocket(
          actionName: 'joinRoom',
          data: <String, dynamic>{'playerName': 'Bob', 'roomCode': 'ABCD'},
        ),
      ).called(1);
    });

    test('parses the ack payload into a JoinRoomResponse', () async {
      stubEmit(SocketResponse(code: 200, data: joinRoomResponseJson(roomCode: 'QRST')));

      final response = await service.joinRoom(
        request: JoinRoomRequest(playerName: 'Bob', roomCode: 'QRST'),
      );

      expect(response.roomCode, 'QRST');
      expect(response.playerList, hasLength(2));
    });

    test('throws InvalidSocketResponseException when the ack carries no data', () async {
      stubEmit(SocketResponse(code: 200, data: null));

      await expectLater(
        service.joinRoom(request: JoinRoomRequest(playerName: 'Bob', roomCode: 'ABCD')),
        throwsA(isA<InvalidSocketResponseException>()),
      );
    });
  });

  group('leaveRoom', () {
    test('emits leaveRoom with no payload', () async {
      when(
        () => socketService.emitSocket(actionName: any(named: 'actionName')),
      ).thenAnswer((_) async => SocketResponse(code: 200));

      await service.leaveRoom();

      verify(() => socketService.emitSocket(actionName: 'leaveRoom')).called(1);
    });

    test('does not require data on the ack', () async {
      // Unlike create/join, leaveRoom ignores the response body entirely.
      when(
        () => socketService.emitSocket(actionName: any(named: 'actionName')),
      ).thenAnswer((_) async => SocketResponse(code: 200, data: null));

      await expectLater(service.leaveRoom(), completes);
    });
  });
}
