import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/use_cases/leave_room_use_case.dart';
import 'package:boom_board/core/exceptions/bb_server_offline_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockRoomServerRepository repository;
  late MockSimpleModeSocketHandler socketHandler;
  late MockIdentityStore identityStore;
  late LeaveRoomUseCase useCase;

  setUpAll(registerTestFallbackValues);

  setUp(() {
    repository = MockRoomServerRepository();
    socketHandler = MockSimpleModeSocketHandler();
    identityStore = emptyIdentityStore();
    useCase = LeaveRoomUseCase(
      roomServerRepository: repository,
      simpleModeSocketHandler: socketHandler,
      identityStore: identityStore,
    );
  });

  group('LeaveRoomUseCase', () {
    test('tells the server, then unbinds the simple-mode handlers', () async {
      when(() => repository.leaveRoom()).thenAnswer((_) async {});

      await useCase.call(LeaveRoomParams(gameMode: GameMode.simple));

      verifyInOrder([
        () => repository.leaveRoom(),
        () => socketHandler.dispose(),
      ]);
    });

    test('unbinds exactly once', () async {
      when(() => repository.leaveRoom()).thenAnswer((_) async {});

      await useCase.call(LeaveRoomParams(gameMode: GameMode.simple));

      verify(() => socketHandler.dispose()).called(1);
      verifyNever(() => socketHandler.init());
    });

    test('unbinds the handlers even when the server call fails', () async {
      // The leak this guards: leaveRoom() throws whenever the socket is down
      // (SocketService.emitSocket raises BbServerOfflineException on
      // !socket.connected), SimpleModeController.leaveRoom() only logs the
      // error so the player still walks out of the room, and the ten
      // roundResolved/playerJoined/... handlers stay bound. The next
      // create or join calls init() again, socket.on() appends, and every
      // server event is then handled twice -- duplicate action-log entries
      // and double-applied player mutations.
      when(() => repository.leaveRoom()).thenThrow(
        BbServerOfflineException(
          code: 503,
          errorType: 'SERVER_OFFLINE',
          data: 'offline',
        ),
      );

      await expectLater(
        useCase.call(LeaveRoomParams(gameMode: GameMode.simple)),
        throwsA(isA<BbServerOfflineException>()),
      );

      verify(() => socketHandler.dispose()).called(1);
    });

    test('clears the stored credentials, since there is no seat left to reclaim', () async {
      // Leaving on purpose is the one exit that invalidates the slot. A drop or
      // a reload keeps it -- that is what makes reconnecting possible at all.
      when(() => repository.leaveRoom()).thenAnswer((_) async {});

      await useCase.call(LeaveRoomParams(gameMode: GameMode.simple));

      verify(() => identityStore.clear()).called(1);
    });

    test('clears the credentials even when the server call fails', () async {
      // Leaving while offline is the common case (that is *why* the socket
      // call failed), and the player still walks out of the room.
      when(() => repository.leaveRoom()).thenThrow(
        BbServerOfflineException(code: 503, errorType: 'SERVER_OFFLINE', data: 'offline'),
      );

      await expectLater(
        useCase.call(LeaveRoomParams(gameMode: GameMode.simple)),
        throwsA(isA<BbServerOfflineException>()),
      );

      verify(() => identityStore.clear()).called(1);
    });

    test('still surfaces the server error to the caller', () async {
      // Cleaning up locally must not turn a failed leave into a silent success;
      // the controller needs the throw to log it.
      when(() => repository.leaveRoom()).thenThrow(StateError('boom'));

      await expectLater(
        useCase.call(LeaveRoomParams(gameMode: GameMode.simple)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
