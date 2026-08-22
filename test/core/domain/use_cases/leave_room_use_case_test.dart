import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/use_cases/leave_room_use_case.dart';
import 'package:boom_board/core/exceptions/bb_server_offline_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockRoomServerRepository repository;
  late MockSimpleModeSocketHandler socketHandler;
  late MockRoomSnapshotCache snapshotCache;
  late MockIdentityStore identityStore;
  late LeaveRoomUseCase useCase;

  setUpAll(registerTestFallbackValues);

  setUp(() {
    repository = MockRoomServerRepository();
    socketHandler = MockSimpleModeSocketHandler();
    snapshotCache = MockRoomSnapshotCache();
    identityStore = emptyIdentityStore();
    useCase = LeaveRoomUseCase(
      roomServerRepository: repository,
      simpleModeSocketHandler: socketHandler,
      roomSnapshotCache: snapshotCache,
      identityStore: identityStore,
    );
  });

  group('LeaveRoomUseCase', () {
    test('drops everything local before it tells the server', () async {
      // Order matters, and this is the direction that survives failure.
      //
      // Callers do not await this and only log a failure, so anything left
      // until after the server round-trip outlives the intent: the home screen
      // reads the credential slot the moment it is built, well inside that
      // window, and would offer to rejoin the room the player just walked out
      // of. Doing it up front means a leave that never reaches the server still
      // leaves the client cleanly out of the room.
      when(() => repository.leaveRoom()).thenAnswer((_) async {});

      await useCase.call(LeaveRoomParams(gameMode: GameMode.simple));

      verifyInOrder([
        () => socketHandler.dispose(),
        () => snapshotCache.clear(),
        () => identityStore.clear(),
        () => repository.leaveRoom(),
      ]);
    });

    test('has dropped the slot before it yields to the server call', () async {
      // The other half of the ordering guarantee, and the half a `verifyInOrder`
      // cannot see: not just "clear before leaveRoom", but "clear before this
      // future suspends at all".
      //
      // Callers do not await this. SimpleModeScreen fires it and pushes the home
      // route on the very next synchronous line, and HomeController reads the
      // credential slot while it builds -- so an await inserted above
      // identityStore.clear() would put the drop after that read and quietly
      // bring back the "Rejoin room XXXX?" prompt for the room just left.
      // IdentityStore.clear() drops its in-memory copy synchronously, so
      // reaching the call is enough (see identity_store_test.dart).
      when(() => repository.leaveRoom()).thenAnswer((_) async {});

      final pending = useCase.call(LeaveRoomParams(gameMode: GameMode.simple));

      verify(() => socketHandler.dispose()).called(1);
      verify(() => snapshotCache.clear()).called(1);
      verify(() => identityStore.clear()).called(1);
      verifyNever(() => repository.leaveRoom());

      await pending;

      verify(() => repository.leaveRoom()).called(1);
    });

    test('drops the parked room snapshot', () async {
      // The cache holds the last snapshot the server pushed, for a controller
      // that has not mounted yet. Left behind, the *next* room's controller
      // picks it up on mount -- seeding a brand-new lobby with the previous
      // game's phase, round number and roster.
      when(() => repository.leaveRoom()).thenAnswer((_) async {});

      await useCase.call(LeaveRoomParams(gameMode: GameMode.simple));

      verify(() => snapshotCache.clear()).called(1);
    });

    test('drops the parked snapshot even when the server call fails', () async {
      when(() => repository.leaveRoom()).thenThrow(
        BbServerOfflineException(code: 503, errorType: 'SERVER_OFFLINE', data: 'offline'),
      );

      await expectLater(
        useCase.call(LeaveRoomParams(gameMode: GameMode.simple)),
        throwsA(isA<BbServerOfflineException>()),
      );

      verify(() => snapshotCache.clear()).called(1);
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
      // and double-applied player mutations. Unbinding ahead of the server
      // call is what makes this hold no matter how the call ends.
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
