import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/requests/create_room_request.dart';
import 'package:boom_board/core/domain/entities/create_room_entity.dart';
import 'package:boom_board/core/domain/entities/player_entity.dart';
import 'package:boom_board/core/domain/use_cases/create_room_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockRoomServerRepository repository;
  late MockSimpleModeSocketHandler socketHandler;
  late MockIdentityStore identityStore;
  late CreateRoomUseCase useCase;

  CreateRoomEntity entity() {
    return CreateRoomEntity(
      roomCode: 'ABCD',
      gameMode: GameMode.simple,
      hostId: 'p-1',
      playerList: [
        PlayerEntity(
          id: 'p-1',
          name: 'Alice',
          isAlive: true,
          hasPositioned: false,
          isDisconnected: false,
        ),
      ],
      spectatorList: const [],
      playerId: 'p-1',
      secret: 'sh-sh-secret',
      isSpectator: false,
    );
  }

  setUpAll(registerTestFallbackValues);

  setUp(() {
    repository = MockRoomServerRepository();
    socketHandler = MockSimpleModeSocketHandler();
    identityStore = emptyIdentityStore();
    useCase = CreateRoomUseCase(
      roomServerRepository: repository,
      simpleModeSocketHandler: socketHandler,
      identityStore: identityStore,
    );
  });

  group('CreateRoomUseCase', () {
    test('forwards the player name to the repository as a CreateRoomRequest', () async {
      when(() => repository.createRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(CreateRoomParams(playerName: 'Alice'));

      final captured = verify(() => repository.createRoom(captureAny())).captured.single;

      expect((captured as CreateRoomRequest).playerName, 'Alice');
    });

    test('returns the entity the repository produced', () async {
      when(() => repository.createRoom(any())).thenAnswer((_) async => entity());

      final result = await useCase.call(CreateRoomParams(playerName: 'Alice'));

      expect(result.roomCode, 'ABCD');
      expect(result.hostId, 'p-1');
      expect(result.playerList.single.name, 'Alice');
    });

    test('persists the minted credentials against the new room', () async {
      when(() => repository.createRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(CreateRoomParams(playerName: 'Alice'));

      verify(
        () => identityStore.save(
          playerId: 'p-1',
          secret: 'sh-sh-secret',
          roomCode: 'ABCD',
          playerName: 'Alice',
        ),
      ).called(1);
    });

    test('binds the simple-mode socket handlers before the request goes out', () async {
      // The server may emit a private roomSnapshot the instant it acks, so a
      // handler bound after the await could miss it entirely.
      when(() => repository.createRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(CreateRoomParams(playerName: 'Alice'));

      verifyInOrder([
        () => socketHandler.init(),
        () => repository.createRoom(any()),
      ]);
    });

    test('unbinds the handlers again when the repository throws', () async {
      // Binding early means the failure path has to clean up, or the next
      // create/join would double-register every handler.
      when(() => repository.createRoom(any())).thenThrow(Exception('server offline'));

      await expectLater(
        useCase.call(CreateRoomParams(playerName: 'Alice')),
        throwsA(isA<Exception>()),
      );

      verify(() => socketHandler.dispose()).called(1);
    });

    test('does not persist credentials when the create fails', () async {
      when(() => repository.createRoom(any())).thenThrow(Exception('server offline'));

      await expectLater(
        useCase.call(CreateRoomParams(playerName: 'Alice')),
        throwsA(isA<Exception>()),
      );

      verifyNever(
        () => identityStore.save(
          playerId: any(named: 'playerId'),
          secret: any(named: 'secret'),
          roomCode: any(named: 'roomCode'),
          playerName: any(named: 'playerName'),
        ),
      );
    });

    test('propagates the repository error rather than swallowing it', () async {
      when(() => repository.createRoom(any())).thenThrow(StateError('boom'));

      await expectLater(
        useCase.call(CreateRoomParams(playerName: 'Alice')),
        throwsA(isA<StateError>()),
      );
    });

    test('rebinds cleanly on a second create', () async {
      // init() unbinds first, so repeated creates can't stack handlers.
      when(() => repository.createRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(CreateRoomParams(playerName: 'Alice'));
      await useCase.call(CreateRoomParams(playerName: 'Alice'));

      verify(() => socketHandler.init()).called(2);
    });
  });
}
