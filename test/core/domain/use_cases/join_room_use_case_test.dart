import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/requests/join_room_request.dart';
import 'package:boom_board/core/domain/entities/join_room_entity.dart';
import 'package:boom_board/core/domain/entities/player_entity.dart';
import 'package:boom_board/core/domain/use_cases/join_room_use_case.dart';
import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockRoomServerRepository repository;
  late MockSimpleModeSocketHandler socketHandler;
  late MockIdentityStore identityStore;
  late JoinRoomUseCase useCase;

  JoinRoomEntity entity({
    String roomCode = 'ABCD',
    String playerId = 'p-2',
    bool isSpectator = false,
  }) {
    return JoinRoomEntity(
      roomCode: roomCode,
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
      spectatorList: const [],
      playerId: playerId,
      secret: 'sh-sh-secret',
      isSpectator: isSpectator,
    );
  }

  BBServerException serverError(String errorType) {
    return BBServerException(code: 403, errorType: errorType, data: errorType);
  }

  setUpAll(registerTestFallbackValues);

  setUp(() {
    repository = MockRoomServerRepository();
    socketHandler = MockSimpleModeSocketHandler();
    identityStore = emptyIdentityStore();
    useCase = JoinRoomUseCase(
      roomServerRepository: repository,
      simpleModeSocketHandler: socketHandler,
      identityStore: identityStore,
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

    test('normalises the room code so a stored slot can be matched against it', () async {
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: ' ab '));

      final captured = verify(() => repository.joinRoom(captureAny())).captured.single;

      expect((captured as JoinRoomRequest).roomCode, 'AB');
    });

    test('replays the stored credentials when re-entering their own room', () async {
      when(() => identityStore.credentialsFor('ABCD')).thenReturn(
        RoomCredentials(playerId: 'p-2', secret: 'sh-sh-secret', roomCode: 'ABCD', playerName: 'Bob'),
      );
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD'));

      final captured = verify(() => repository.joinRoom(captureAny())).captured.single;

      expect((captured as JoinRoomRequest).playerId, 'p-2');
      expect(captured.secret, 'sh-sh-secret');
    });

    test('sends no credentials when entering a room the slot does not cover', () async {
      // Credentials belong to one room. Presenting them elsewhere is exactly
      // the situation the room-scoping is there to prevent.
      when(() => identityStore.credentialsFor('WXYZ')).thenReturn(null);
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity(roomCode: 'WXYZ'));

      await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'WXYZ'));

      final captured = verify(() => repository.joinRoom(captureAny())).captured.single;

      expect((captured as JoinRoomRequest).playerId, isNull);
      expect(captured.secret, isNull);
      expect(captured.toJson().containsKey('playerId'), isFalse);
    });

    test('overwrites the slot with whatever identity the server resolved', () async {
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity(playerId: 'p-9'));

      await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD'));

      verify(
        () => identityStore.save(
          playerId: 'p-9',
          secret: 'sh-sh-secret',
          roomCode: 'ABCD',
          playerName: 'Bob',
        ),
      ).called(1);
    });

    test('returns the entity the repository produced', () async {
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity());

      final result = await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD'));

      expect(result.roomCode, 'ABCD');
      expect(result.playerList.single.id, 'p-2');
    });

    test('surfaces a mid-game entry as a spectator', () async {
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity(isSpectator: true));

      final result = await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD'));

      expect(result.isSpectator, isTrue);
    });

    test('binds the simple-mode socket handlers before the request goes out', () async {
      // A mid-game join is answered with a private roomSnapshot straight after
      // the ack, so the handler has to already be bound.
      when(() => repository.joinRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD'));

      verifyInOrder([
        () => socketHandler.init(),
        () => repository.joinRoom(any()),
      ]);
    });

    test('unbinds the handlers again when the join is rejected', () async {
      when(() => repository.joinRoom(any())).thenThrow(serverError('ROOM_IS_FULL'));

      await expectLater(
        useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ZZZZ')),
        throwsA(isA<BBServerException>()),
      );

      verify(() => socketHandler.dispose()).called(1);
    });

    test('clears the slot when the server rejects the credentials', () async {
      // SECRET_MISMATCH means these creds will never work again; keeping them
      // would make every retry fail the same way.
      when(() => identityStore.credentialsFor('ABCD')).thenReturn(
        RoomCredentials(playerId: 'p-2', secret: 'stale', roomCode: 'ABCD', playerName: 'Bob'),
      );
      when(() => repository.joinRoom(any())).thenThrow(serverError('SECRET_MISMATCH'));

      await expectLater(
        useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD')),
        throwsA(isA<BBServerException>()),
      );

      verify(() => identityStore.clear()).called(1);
    });

    test('clears the slot when the room it points at is gone', () async {
      when(() => identityStore.credentialsFor('ABCD')).thenReturn(
        RoomCredentials(playerId: 'p-2', secret: 'sh-sh-secret', roomCode: 'ABCD', playerName: 'Bob'),
      );
      when(() => repository.joinRoom(any())).thenThrow(serverError('ROOM_NOT_FOUND'));

      await expectLater(
        useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD')),
        throwsA(isA<BBServerException>()),
      );

      verify(() => identityStore.clear()).called(1);
    });

    test('keeps a slot for another room when this join hits ROOM_NOT_FOUND', () async {
      // Typing a bad room code must not cost the player the seat they still
      // hold somewhere else.
      when(() => identityStore.credentialsFor('ZZZZ')).thenReturn(null);
      when(() => repository.joinRoom(any())).thenThrow(serverError('ROOM_NOT_FOUND'));

      await expectLater(
        useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ZZZZ')),
        throwsA(isA<BBServerException>()),
      );

      verifyNever(() => identityStore.clear());
    });

    test('keeps the slot on a transient failure so a retry can still reconnect', () async {
      when(() => identityStore.credentialsFor('ABCD')).thenReturn(
        RoomCredentials(playerId: 'p-2', secret: 'sh-sh-secret', roomCode: 'ABCD', playerName: 'Bob'),
      );
      when(() => repository.joinRoom(any())).thenThrow(StateError('timeout'));

      await expectLater(
        useCase.call(JoinRoomParams(playerName: 'Bob', roomCode: 'ABCD')),
        throwsA(isA<StateError>()),
      );

      verifyNever(() => identityStore.clear());
    });
  });
}
