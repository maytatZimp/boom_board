import 'package:boom_board/core/exceptions/bb_server_offline_exception.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/reset_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/set_position_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/start_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/throw_bomb_request.dart';
import 'package:boom_board/features/simple_mode/data/repositories/simple_mode_server_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSimpleModeSocketService socketService;
  late SimpleModeServerRepositoryImpl repository;

  setUpAll(registerTestFallbackValues);

  setUp(() {
    socketService = MockSimpleModeSocketService();
    repository = SimpleModeServerRepositoryImpl(socketService: socketService);
  });

  group('SimpleModeServerRepositoryImpl', () {
    test('startGame delegates with the same request instance', () async {
      final request = StartGameRequest(roomCode: 'ABCD');
      when(() => socketService.startGame(any())).thenAnswer((_) async {});

      await repository.startGame(request);

      verify(() => socketService.startGame(request)).called(1);
    });

    test('setPosition delegates with the same request instance', () async {
      final request = SetPositionRequest(roomCode: 'ABCD', x: 2, y: 3);
      when(() => socketService.setPosition(any())).thenAnswer((_) async {});

      await repository.setPosition(request);

      verify(() => socketService.setPosition(request)).called(1);
    });

    test('resetGame delegates with the same request instance', () async {
      final request = ResetGameRequest(roomCode: 'ABCD');
      when(() => socketService.resetGame(any())).thenAnswer((_) async {});

      await repository.resetGame(request);

      verify(() => socketService.resetGame(request)).called(1);
    });

    test('throwBomb returns the data source response', () async {
      when(() => socketService.throwBomb(any()))
          .thenAnswer((_) async => ThrowBombResponse(throwOrder: 3));

      final response = await repository.throwBomb(
        ThrowBombRequest(roomCode: 'ABCD', x: 1, y: 1),
      );

      expect(response?.throwOrder, 3);
    });

    test('throwBomb passes a null response through', () async {
      when(() => socketService.throwBomb(any())).thenAnswer((_) async => null);

      final response = await repository.throwBomb(
        ThrowBombRequest(roomCode: 'ABCD', x: 1, y: 1),
      );

      expect(response, isNull);
    });

    test('propagates a data-source error', () async {
      when(() => socketService.startGame(any()))
          .thenThrow(BbServerOfflineException(code: 503, errorType: 'SERVER_OFFLINE'));

      await expectLater(
        repository.startGame(StartGameRequest(roomCode: 'ABCD')),
        throwsA(isA<BbServerOfflineException>()),
      );
    });
  });
}
