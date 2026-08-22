import 'dart:async';

import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/core/domain/entities/spectator_entity.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/core/events/models/page_resumed_event.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/log_action_type.dart';
import 'package:boom_board/features/simple_mode/domain/constants/animation_constant.dart' as anim;
import 'package:boom_board/features/simple_mode/domain/entities/action_log_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/room_snapshot_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/round_resolved_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/explosion_result_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:boom_board/features/simple_mode/presentation/controllers/simple_mode_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/controller_harness.dart';
import '../../../../helpers/mocks.dart';

/// Backgrounding mobile Chrome stops the render pipeline but not the clock:
/// the phase keeps draining and rounds keep resolving while nothing is
/// painted. Coming back, the client has to re-read the room rather than carry
/// on from whatever it last believed -- and whatever was mid-animation when it
/// went away must not be allowed to write over that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimpleModeControllerHarness harness;

  setUpAll(registerTestFallbackValues);

  Future<void> buildRoom() async {
    harness = SimpleModeControllerHarness();
    await harness.setUp(players: [player(id: localId), player(id: 'p-2')]);
    harness.subscribe();
  }

  tearDown(() => harness.tearDown());

  group('PageResumedEvent', () {
    test('asks the server for a fresh snapshot', () async {
      await buildRoom();

      eventBus.fire(PageResumedEvent());
      await pumpController();

      verify(() => harness.requestSnapshot.call()).called(1);
    });

    test('stays quiet while disconnected -- the rejoin brings its own snapshot', () async {
      await buildRoom();
      harness.controller.connectionState = RoomConnectionState.reconnecting;

      eventBus.fire(PageResumedEvent());
      await pumpController();

      verifyNever(() => harness.requestSnapshot.call());
    });

    test('a second resume while one is in flight is ignored', () async {
      await buildRoom();

      // Hold the first call open so the second one lands on top of it.
      final gate = Completer<void>();
      when(() => harness.requestSnapshot.call()).thenAnswer((_) => gate.future);

      eventBus.fire(PageResumedEvent());
      await pumpController();
      eventBus.fire(PageResumedEvent());
      await pumpController();

      verify(() => harness.requestSnapshot.call()).called(1);

      gate.complete();
      await pumpController();
    });

    test('a failed resync is swallowed, leaving the overlay to the socket handlers', () async {
      await buildRoom();
      when(() => harness.requestSnapshot.call()).thenThrow(Exception('offline'));

      eventBus.fire(PageResumedEvent());
      await pumpController();

      expect(harness.controller.connectionState, RoomConnectionState.connected);
    });

    test('a later resume is allowed once the first one settled', () async {
      await buildRoom();

      eventBus.fire(PageResumedEvent());
      await pumpController();
      eventBus.fire(PageResumedEvent());
      await pumpController();

      verify(() => harness.requestSnapshot.call()).called(2);
    });
  });

  group('a snapshot landing mid-round', () {
    RoomSnapshotEvent snapshot({
      GameState state = GameState.attack,
      int roundNumber = 9,
      List<SimpleModePlayerEntity>? players,
      List<ActionLogEntity>? logs,
    }) {
      return RoomSnapshotEvent(
        state: state,
        roundNumber: roundNumber,
        boardWidth: 8,
        boardHeight: 8,
        destroyedTiles: const [],
        timeLimit: 30,
        remainingMs: 12000,
        hostId: localId,
        playerList: players ?? [player(id: localId), player(id: 'p-2')],
        spectatorList: const <SpectatorEntity>[],
        logs: logs ?? const [],
        isSpectator: false,
        you: null,
        ranking: const [],
        winnerPosition: null,
      );
    }

    RoundResolvedEvent staleRound() {
      return RoundResolvedEvent(
        explosionList: [
          ExplosionResultEntity(bomberId: 'p-2', victimId: localId, isHit: true, x: 3, y: 3),
        ],
        playerList: [player(id: localId, isAlive: false), player(id: 'p-2')],
        destroyedTiles: [Coordinate(x: 7, y: 7)],
        newDestroyedTiles: [Coordinate(x: 7, y: 7)],
        newLogs: [
          ActionLogEntity(
            id: 'stale-log',
            type: LogActionType.bombExploded,
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
            data: const <String, dynamic>{},
          ),
        ],
        roundNumber: 4,
      );
    }

    // The round sequence spans several seconds of awaits. Backgrounded, it runs
    // to completion unseen -- so by the time it wakes up it is describing a
    // round the server has already moved past.
    test('abandons the round sequence still sitting on an await', () async {
      await buildRoom();

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(staleRound());
        // Mid-sequence: the first bomb is still falling.
        async.elapse(anim.bombDrop ~/ 2);

        harness.controller.applyRoomSnapshot(snapshot(roundNumber: 9));

        // Long enough to drain every timer the abandoned sequence scheduled.
        async.elapse(const Duration(seconds: 12));

        expect(harness.controller.currentRound, 9, reason: 'the snapshot round must survive');
        expect(harness.controller.currentState, GameState.attack);
        expect(harness.controller.destroyedTile, isEmpty);
        expect(harness.controller.actionLogList, isEmpty);
        expect(harness.controller.playerList.firstWhere((p) => p.id == localId).isAlive, isTrue);
      });
    });

    test('an uninterrupted round still applies in full', () async {
      await buildRoom();

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(staleRound());
        async.elapse(const Duration(seconds: 12));

        expect(harness.controller.currentRound, 4);
        expect(harness.controller.destroyedTile, [Coordinate(x: 7, y: 7)]);
        expect(harness.controller.actionLogList.single.id, 'stale-log');
      });
    });
  });
}
