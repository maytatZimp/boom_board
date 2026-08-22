import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/entities/join_room_entity.dart';
import 'package:boom_board/core/domain/entities/player_entity.dart';
import 'package:boom_board/core/domain/use_cases/join_room_use_case.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/core/events/models/socket_connected_error_event.dart';
import 'package:boom_board/core/events/models/socket_disconnected_event.dart';
import 'package:boom_board/core/events/models/socket_reconnect_attempt_event.dart';
import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/presentation/controllers/simple_mode_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/controller_harness.dart';
import '../../../../helpers/mocks.dart';
import '../../../../helpers/test_di.dart';

/// Losing the socket used to eject the player to the home screen. The seat is
/// now held server-side while they are away, so the client's job changes
/// completely: hold the room, show an overlay, and climb back into the same
/// seat with the stored credentials.
void main() {
  // abandonRoom is the one path here that navigates. Without a binding and
  // testMode, GetX throws on contextless navigation rather than no-opping the
  // way the rest of the controller tests rely on.
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;

  late SimpleModeControllerHarness harness;

  setUpAll(registerTestFallbackValues);

  Future<void> buildRoom() async {
    harness = SimpleModeControllerHarness();
    await harness.setUp(
      players: [player(id: localId, name: 'Alice'), player(id: 'p-2')],
      hostId: localId,
    );
    harness.subscribe();
  }

  JoinRoomEntity rejoinResult({
    String hostId = localId,
    bool isSpectator = false,
    String roomCode = 'ABCD',
  }) {
    return JoinRoomEntity(
      roomCode: roomCode,
      gameMode: GameMode.simple,
      hostId: hostId,
      playerList: [
        PlayerEntity(id: localId, name: 'Alice', isAlive: true, hasPositioned: true, isDisconnected: false),
      ],
      spectatorList: const [],
      playerId: localId,
      secret: 'sh-sh-secret',
      isSpectator: isSpectator,
    );
  }

  tearDown(() async {
    await harness.tearDown();
  });

  group('losing the connection', () {
    test('holds the room and shows the reconnecting overlay', () async {
      await buildRoom();

      eventBus.fire(SocketDisconnectedEvent());
      await pumpEventBus();

      expect(harness.controller.connectionState, RoomConnectionState.reconnecting);
      expect(harness.controller.isConnectionLost, isTrue);
    });

    test('a connect error is treated the same as a drop', () async {
      await buildRoom();

      eventBus.fire(SocketConnectedErrorEvent());
      await pumpEventBus();

      expect(harness.controller.connectionState, RoomConnectionState.reconnecting);
    });

    test('stops the phase timer, since the board is now stale', () async {
      await buildRoom();
      harness.controller.currentState = GameState.attack;
      harness.controller.currentPhaseTimeLimit = 30;

      eventBus.fire(SocketDisconnectedEvent());
      await pumpEventBus();

      expect(harness.controller.currentPhaseTimeLimit, lessThanOrEqualTo(0));
    });

    test('a retry attempt keeps the overlay in the reconnecting state', () async {
      await buildRoom();
      harness.controller.connectionState = RoomConnectionState.reconnectFailed;

      eventBus.fire(SocketReconnectAttemptEvent(attemptCount: 2));
      await pumpEventBus();

      expect(harness.controller.connectionState, RoomConnectionState.reconnecting);
      expect(harness.controller.connectionError, isNull);
    });
  });

  group('rejoinRoom', () {
    test('re-enters the same room under the local display name', () async {
      // The name comes off the roster, which tracks renames, and falls back to
      // the persisted slot after a reload.
      await buildRoom();
      when(() => harness.joinRoom.call(any())).thenAnswer((_) async => rejoinResult());

      await harness.controller.rejoinRoom();

      final captured = verify(() => harness.joinRoom.call(captureAny())).captured.single;
      expect((captured as JoinRoomParams).roomCode, 'ABCD');
      expect(captured.playerName, 'Alice');
    });

    test('clears the overlay once the seat is back', () async {
      await buildRoom();
      when(() => harness.joinRoom.call(any())).thenAnswer((_) async => rejoinResult());

      await harness.controller.rejoinRoom();

      expect(harness.controller.connectionState, RoomConnectionState.connected);
      expect(harness.controller.connectionError, isNull);
    });

    test('picks up a host reassignment that happened while we were away', () async {
      // A returning host does not reclaim the role -- they come back as a
      // normal player.
      await buildRoom();
      when(() => harness.joinRoom.call(any())).thenAnswer((_) async => rejoinResult(hostId: 'p-2'));

      await harness.controller.rejoinRoom();

      expect(harness.controller.hostId, 'p-2');
      expect(harness.controller.isHost, isFalse);
    });

    test('adopts the room the server actually seated us in', () async {
      // The credential slot is what a rejoin aims at, and it can name a
      // different room than the screen is holding -- that is the whole reason
      // the aim is taken from the slot. Taking the room back off the ack is
      // what stops the two drifting for good: without it the screen keeps
      // naming one room while the seat sits in another, and after the server
      // stopped trusting the client's room code that mismatch is silent.
      await buildRoom();
      when(() => harness.identityStore.credentials).thenReturn(
        RoomCredentials(playerId: localId, secret: 's3cret', roomCode: 'WXYZ', playerName: 'Alice'),
      );
      when(() => harness.joinRoom.call(any())).thenAnswer((_) async => rejoinResult(roomCode: 'WXYZ'));

      expect(harness.controller.roomCode, 'ABCD');

      await harness.controller.rejoinRoom();

      final captured = verify(() => harness.joinRoom.call(captureAny())).captured.single as JoinRoomParams;
      expect(captured.roomCode, 'WXYZ', reason: 'the slot names the seat, so it aims the rejoin');
      expect(harness.controller.roomCode, 'WXYZ', reason: 'and the ack settles it for everything after');
    });

    test('comes back as a spectator when the server says so', () async {
      await buildRoom();
      when(() => harness.joinRoom.call(any())).thenAnswer((_) async => rejoinResult(isSpectator: true));

      await harness.controller.rejoinRoom();

      expect(harness.controller.isSpectator, isTrue);
    });

    test('a rejected rejoin explains why and offers a manual retry', () async {
      await buildRoom();
      when(() => harness.joinRoom.call(any())).thenThrow(
        BBServerException(code: 404, errorType: 'ROOM_NOT_FOUND', data: 'gone'),
      );

      await harness.controller.rejoinRoom();

      expect(harness.controller.connectionState, RoomConnectionState.reconnectFailed);
      expect(harness.controller.connectionError, 'That room no longer exists.');
    });

    test('an unverifiable seat is reported rather than silently retried', () async {
      await buildRoom();
      when(() => harness.joinRoom.call(any())).thenThrow(
        BBServerException(code: 403, errorType: 'SECRET_MISMATCH', data: 'nope'),
      );

      await harness.controller.rejoinRoom();

      expect(harness.controller.connectionError, 'Your seat could not be verified.');
    });

    test('an unreachable server leaves a retryable failure', () async {
      await buildRoom();
      when(() => harness.joinRoom.call(any())).thenThrow(StateError('timeout'));

      await harness.controller.rejoinRoom();

      expect(harness.controller.connectionState, RoomConnectionState.reconnectFailed);
      expect(harness.controller.connectionError, 'Could not reach the server.');
    });

    test('never navigates the player home on failure', () async {
      // The old behaviour. The room is still theirs, so an overlay with a
      // retry beats an unrequested bounce to the menu.
      await buildRoom();
      when(() => harness.joinRoom.call(any())).thenThrow(StateError('timeout'));

      await harness.controller.rejoinRoom();

      expect(harness.controller.roomCode, 'ABCD');
      expect(harness.controller.playerList, isNotEmpty);
    });

    test('a second call while one is in flight is ignored', () async {
      // The socket's own retries and the manual button can both fire; two
      // concurrent joins would race two identities into the same seat.
      await buildRoom();
      var calls = 0;
      when(() => harness.joinRoom.call(any())).thenAnswer((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return rejoinResult();
      });

      final first = harness.controller.rejoinRoom();
      harness.controller.rejoinRoom();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, 1);
    });

    test('a later call is allowed once the first one settled', () async {
      await buildRoom();
      when(() => harness.joinRoom.call(any())).thenThrow(StateError('timeout'));

      await harness.controller.rejoinRoom();
      await harness.controller.rejoinRoom();

      verify(() => harness.joinRoom.call(any())).called(2);
    });
  });

  group('abandonRoom', () {
    test('gives up the seat through the leave use case', () async {
      // Which is also what clears the stored credentials -- an explicit leave
      // is the one exit that invalidates them.
      await buildRoom();

      await harness.controller.abandonRoom();

      verify(() => harness.leaveRoom.call(any())).called(1);
    });

    test('still leaves when the server call fails, which it will while offline', () async {
      await buildRoom();
      when(() => harness.leaveRoom.call(any())).thenThrow(StateError('offline'));

      await expectLater(harness.controller.abandonRoom(), completes);
    });
  });
}
