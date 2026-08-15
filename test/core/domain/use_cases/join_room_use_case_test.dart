import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/requests/join_room_request.dart';
import 'package:boom_board/core/domain/entities/join_room_entity.dart';
import 'package:boom_board/core/domain/entities/player_entity.dart';
import 'package:boom_board/core/domain/use_cases/join_room_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockRoomServerRepository repository;
  late MockSimpleModeSocketHandler socketHandler;
  late JoinRoomUseCase useCase;

  JoinRoomEntity entity() {
    return JoinRoomEntity(
      roomCode: 'ABCD',
      gameMode: GameMode.simple,
      hostId: 'p-1',
      playerList: [
        PlayerEntity(
          id: 'p-2',
          name: 'Bob',
          isAlive: true,
          hasPositioned: false,
          isDisconnected: false,
        ),
      ],
    );
  }

  setUpAll(registerTestFallbackValues);

  setUp(() {
    repository = MockRoomServerRepository();
    socketHandler = MockSimpleModeSocketHandler();
    useCase = JoinRoomUseCase(
      roomServerRepository: repository,
      simpleModeSocketHandler: socketHandler,
    );
  });

  group('JoinRoomUseCase', () {
    test('forwards both the player name and the room code', () async {
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'WXYZ'));

      final captured = verify(() => repository.joinRoom(captureAny())).captured.single;

      expect((captured as JoinRoomRequest).playerName, 'Bob');
      expect(captured.roomCode, 'WXYZ');
    });

    test('returns the entity the repository produced', () async {
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity());

      final result = await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD'));

      expect(result.roomCode, 'ABCD');
      expect(result.playerList.single.id, 'p-2');
    });

    test('binds the simple-mode socket handlers exactly once on success', () async {
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD'));

      verify(() => socketHandler.init()).called(1);
    });

    test('does not bind handlers when the join is rejected', () async {
      // The realistic failure: ROOM_NOT_FOUND / ROOM_IS_FULL come back as a
      // thrown BBServerException, and binding handlers for a room we never
      // entered would leave the client reacting to another room's events.
      when(() => repository.joinRoom(any())).thenThrow(Exception('ROOM_NOT_FOUND'));

      await expectLater(
        useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ZZZZ')),
        throwsA(isA<Exception>()),
      );

      verifyNever(() => socketHandler.init());
    });

    test('does not trim or normalise the room code', () async {
      // HomeController validates length before calling, but the use case
      // itself passes the raw text straight through.
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: ' ab '));

      final captured = verify(() => repository.joinRoom(captureAny())).captured.single;

      expect((captured as JoinRoomRequest).roomCode, ' ab ');
    });
  });
}
