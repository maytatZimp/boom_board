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
    );
  }

  setUpAll(registerTestFallbackValues);

  setUp(() {
    repository = MockRoomServerRepository();
    socketHandler = MockSimpleModeSocketHandler();
    useCase = CreateRoomUseCase(
      roomServerRepository: repository,
      simpleModeSocketHandler: socketHandler,
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

    test('binds the simple-mode socket handlers exactly once on success', () async {
      // GameMode has a single value today, so the `== GameMode.simple` branch
      // cannot currently be driven the other way. This pins the behaviour that
      // exists; adding a second mode is what makes the negative case testable.
      when(() => repository.createRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(CreateRoomParams(playerName: 'Alice'));

      verify(() => socketHandler.init()).called(1);
    });

    test('does not bind handlers when the repository throws', () async {
      when(() => repository.createRoom(any())).thenThrow(Exception('server offline'));

      await expectLater(
        useCase.call(CreateRoomParams(playerName: 'Alice')),
        throwsA(isA<Exception>()),
      );

      verifyNever(() => socketHandler.init());
    });

    test('propagates the repository error rather than swallowing it', () async {
      when(() => repository.createRoom(any())).thenThrow(StateError('boom'));

      await expectLater(
        useCase.call(CreateRoomParams(playerName: 'Alice')),
        throwsA(isA<StateError>()),
      );
    });

    test('binds handlers again on a second create, without unbinding first', () async {
      // Each create unconditionally calls init(). Nothing here calls dispose(),
      // so a create -> leave(failed) -> create sequence leaves two sets of
      // handlers bound. See leave_room_use_case_test.dart for the other half.
      when(() => repository.createRoom(any())).thenAnswer((_) async => entity());

      await useCase.call(CreateRoomParams(playerName: 'Alice'));
      await useCase.call(CreateRoomParams(playerName: 'Alice'));

      verify(() => socketHandler.init()).called(2);
      verifyNever(() => socketHandler.dispose());
    });
  });
}
