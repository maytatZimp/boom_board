import 'package:boom_board/core/exceptions/bb_server_offline_exception.dart';
import 'package:boom_board/core/utils/socket_response.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_service.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/reset_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/set_position_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/start_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/throw_bomb_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSocketService socketService;
  late SimpleModeSocketService service;

  setUpAll(registerTestFallbackValues);

  setUp(() {
    socketService = MockSocketService();
    service = SimpleModeSocketService(socketService: socketService);
  });

  void stubEmit(SocketResponse response) {
    when(
      () => socketService.emitSocket(
        actionName: any(named: 'actionName'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => response);
  }

  group('startGame', () {
    test('emits startGame with the room code', () async {
      stubEmit(SocketResponse(code: 200));

      await service.startGame(StartGameRequest(roomCode: 'ABCD'));

      verify(
        () => socketService.emitSocket(
          actionName: 'startGame',
          data: <String, dynamic>{'roomCode': 'ABCD'},
        ),
      ).called(1);
    });
  });

  group('setPosition', () {
    test('emits setPosition with the room code and coordinates', () async {
      stubEmit(SocketResponse(code: 200));

      await service.setPosition(SetPositionRequest(roomCode: 'ABCD', x: 3, y: 6));

      verify(
        () => socketService.emitSocket(
          actionName: 'setPosition',
          data: <String, dynamic>{'roomCode': 'ABCD', 'x': 3, 'y': 6},
        ),
      ).called(1);
    });

    test('forwards coordinates without validating them', () async {
      // Bounds are the controller's job; this layer is a pure transport.
      stubEmit(SocketResponse(code: 200));

      await service.setPosition(SetPositionRequest(roomCode: 'ABCD', x: 99, y: -1));

      verify(
        () => socketService.emitSocket(
          actionName: 'setPosition',
          data: <String, dynamic>{'roomCode': 'ABCD', 'x': 99, 'y': -1},
        ),
      ).called(1);
    });
  });

  group('throwBomb', () {
    test('emits throwBomb and parses the returned throw order', () async {
      stubEmit(SocketResponse(code: 200, data: <String, dynamic>{'throwOrder': 2}));

      final response = await service.throwBomb(ThrowBombRequest(roomCode: 'ABCD', x: 1, y: 2));

      expect(response?.throwOrder, 2);
      verify(
        () => socketService.emitSocket(
          actionName: 'throwBomb',
          data: <String, dynamic>{'roomCode': 'ABCD', 'x': 1, 'y': 2},
        ),
      ).called(1);
    });

    test('returns null when the ack carries no data', () async {
      // Unlike createRoom this is not an error -- ThrowBombUseCase turns the
      // null into a null throwOrder and the player simply has no queue slot.
      stubEmit(SocketResponse(code: 200, data: null));

      final response = await service.throwBomb(ThrowBombRequest(roomCode: 'ABCD', x: 1, y: 2));

      expect(response, isNull);
    });

    test('throws when the ack payload is missing throwOrder', () async {
      stubEmit(SocketResponse(code: 200, data: <String, dynamic>{}));

      await expectLater(
        service.throwBomb(ThrowBombRequest(roomCode: 'ABCD', x: 1, y: 2)),
        throwsA(isA<TypeError>()),
      );
    });

    test('lets a server-offline error propagate', () async {
      when(
        () => socketService.emitSocket(
          actionName: any(named: 'actionName'),
          data: any(named: 'data'),
        ),
      ).thenThrow(BbServerOfflineException(code: 503, errorType: 'SERVER_OFFLINE'));

      await expectLater(
        service.throwBomb(ThrowBombRequest(roomCode: 'ABCD', x: 1, y: 2)),
        throwsA(isA<BbServerOfflineException>()),
      );
    });
  });

  group('resetGame', () {
    test('emits resetGame with the room code', () async {
      stubEmit(SocketResponse(code: 200));

      await service.resetGame(ResetGameRequest(roomCode: 'ABCD'));

      verify(
        () => socketService.emitSocket(
          actionName: 'resetGame',
          data: <String, dynamic>{'roomCode': 'ABCD'},
        ),
      ).called(1);
    });
  });
}
