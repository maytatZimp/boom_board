import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/log_action_type.dart';
import 'package:boom_board/features/simple_mode/domain/constants/animation_constant.dart' as anim;
import 'package:boom_board/features/simple_mode/domain/entities/action_log_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/round_resolved_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/explosion_result_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/controller_harness.dart';
import '../../../../helpers/mocks.dart';

ActionLogEntity log(String id) {
  return ActionLogEntity(
    id: id,
    type: LogActionType.bombExploded,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    data: const <String, dynamic>{},
  );
}

ExplosionResultEntity explosion({
  required String bomberId,
  String? victimId,
  bool isHit = false,
  int x = 3,
  int y = 3,
}) {
  return ExplosionResultEntity(
    bomberId: bomberId,
    victimId: victimId,
    isHit: isHit,
    x: x,
    y: y,
  );
}

RoundResolvedEvent roundEvent({
  required List<ExplosionResultEntity> explosions,
  required List<SimpleModePlayerEntity> players,
  List<Coordinate> destroyedTiles = const [],
  List<Coordinate> newDestroyedTiles = const [],
  List<ActionLogEntity> newLogs = const [],
  int roundNumber = 2,
}) {
  return RoundResolvedEvent(
    explosionList: explosions,
    playerList: players,
    destroyedTiles: destroyedTiles,
    newDestroyedTiles: newDestroyedTiles,
    newLogs: newLogs,
    roundNumber: roundNumber,
  );
}

/// Long enough to drain every animation timer the round schedules.
const settle = Duration(seconds: 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimpleModeControllerHarness harness;

  setUpAll(registerTestFallbackValues);

  Future<void> buildRoom({int? localX, int? localY}) async {
    harness = SimpleModeControllerHarness();
    await harness.setUp(
      players: [
        player(id: localId, hasPositioned: true, x: localX, y: localY),
        player(id: 'p-2', hasPositioned: true, x: 5, y: 5),
      ],
    );
  }

  tearDown(() => harness.tearDown());

  group('onRoundResolvedEventReceived', () {
    test('locks the UI into the process phase immediately', () async {
      await buildRoom(localX: 1, localY: 1);
      harness.controller.currentState = GameState.attack;

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: [explosion(bomberId: localId)],
            players: [player(id: localId), player(id: 'p-2')],
          ),
        );

        // Before any animation delay elapses.
        expect(harness.controller.currentState, GameState.process);
        expect(harness.controller.currentPhaseTimeLimit, -1);

        async.elapse(settle);
      });
    });

    test('applies the final list, logs and round number', () async {
      await buildRoom(localX: 1, localY: 1);
      harness.controller.actionLogList = [log('old')];

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: [explosion(bomberId: 'p-2', x: 7, y: 7)],
            players: [player(id: localId), player(id: 'p-2')],
            newLogs: [log('new')],
            roundNumber: 4,
          ),
        );
        async.elapse(settle);
      });

      expect(harness.controller.actionLogList.map((l) => l.id), ['old', 'new']);
      expect(harness.controller.currentRound, 4);
      expect(harness.controller.playerList, hasLength(2));
    });

    test('preserves the local player coordinates across the server sync', () async {
      // The handler replaces playerList wholesale with the server's copy,
      // which carries no x/y, then writes the saved coordinates back. Losing
      // them would blank the local player's tile on the board.
      await buildRoom(localX: 2, localY: 6);

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: [explosion(bomberId: 'p-2', x: 7, y: 7)],
            players: [player(id: localId), player(id: 'p-2')],
          ),
        );
        async.elapse(settle);
      });

      expect(harness.local.x, 2);
      expect(harness.local.y, 6);
    });

    test('marks a hit victim dead', () async {
      await buildRoom(localX: 1, localY: 1);

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: [
              explosion(bomberId: localId, victimId: 'p-2', isHit: true, x: 5, y: 5),
            ],
            players: [player(id: localId), player(id: 'p-2', isAlive: false)],
          ),
        );
        async.elapse(settle);
      });

      expect(harness.playerById('p-2').isAlive, isFalse);
    });

    test('unlocks the local bomb target once its bomb lands', () async {
      await buildRoom(localX: 1, localY: 1);
      harness.controller.lockedBombTarget = Coordinate(x: 5, y: 5);

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: [explosion(bomberId: localId, x: 5, y: 5)],
            players: [player(id: localId), player(id: 'p-2')],
          ),
        );

        async.elapse(anim.bombDrop);
        expect(harness.controller.lockedBombTarget, isNull);

        async.elapse(settle);
      });
    });

    test('scorches the destroyed tiles only after the laser finishes', () async {
      await buildRoom(localX: 1, localY: 1);

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: const [],
            players: [player(id: localId), player(id: 'p-2')],
            destroyedTiles: [Coordinate(x: 4, y: 4)],
            newDestroyedTiles: [Coordinate(x: 4, y: 4)],
          ),
        );

        async.flushMicrotasks();
        expect(harness.controller.activeLasers, hasLength(1));
        expect(harness.controller.destroyedTile, isEmpty);

        async.elapse(anim.destroyedTileDelay);
        expect(harness.controller.destroyedTile, hasLength(1));

        async.elapse(settle);
      });
    });

    test('skips the laser phase when no new tiles were destroyed', () async {
      await buildRoom(localX: 1, localY: 1);

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: const [],
            players: [player(id: localId), player(id: 'p-2')],
            destroyedTiles: [Coordinate(x: 4, y: 4)],
          ),
        );
        async.elapse(settle);

        // destroyedTile is only assigned inside the laser branch, so an
        // unchanged board never picks up the server's cumulative list.
        expect(harness.controller.destroyedTile, isEmpty);
        expect(harness.controller.activeLasers, isEmpty);
      });
    });

    test('processes explosions one at a time', () async {
      await buildRoom(localX: 1, localY: 1);

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: [
              explosion(bomberId: localId, x: 1, y: 2),
              explosion(bomberId: 'p-2', x: 3, y: 4),
            ],
            players: [player(id: localId), player(id: 'p-2')],
          ),
        );

        async.flushMicrotasks();
        expect(harness.controller.activeBombDrops, hasLength(1));
        expect(harness.controller.activeBombDrops.single.targetX, 1);

        // First bomb lands and settles; only then does the second drop.
        async.elapse(anim.bombDrop + anim.explosionSettle);
        expect(harness.controller.activeBombDrops.single.targetX, 3);

        async.elapse(settle);
        expect(harness.controller.activeBombDrops, isEmpty);
      });
    });

    test('drops the local bomb from the local player tile', () async {
      await buildRoom(localX: 2, localY: 6);

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: [explosion(bomberId: localId, x: 5, y: 5)],
            players: [player(id: localId), player(id: 'p-2')],
          ),
        );
        async.flushMicrotasks();

        expect(harness.controller.activeBombDrops.single.startX, 2);
        expect(harness.controller.activeBombDrops.single.startY, 6);

        async.elapse(settle);
      });
    });

    test('drops a remote bomb from off-board', () async {
      // Remote bombers get -1/-1, which the board renders as arriving from
      // outside rather than from a known tile.
      await buildRoom(localX: 2, localY: 6);

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: [explosion(bomberId: 'p-2', x: 5, y: 5)],
            players: [player(id: localId), player(id: 'p-2')],
          ),
        );
        async.flushMicrotasks();

        expect(harness.controller.activeBombDrops.single.startX, -1);
        expect(harness.controller.activeBombDrops.single.startY, -1);

        async.elapse(settle);
      });
    });

    test('leaves no animation state behind once everything settles', () async {
      await buildRoom(localX: 1, localY: 1);

      fakeAsync((async) {
        harness.controller.onRoundResolvedEventReceived(
          roundEvent(
            explosions: [
              explosion(bomberId: localId, victimId: 'p-2', isHit: true, x: 5, y: 5),
            ],
            players: [player(id: localId), player(id: 'p-2', isAlive: false)],
            destroyedTiles: [Coordinate(x: 4, y: 4)],
            newDestroyedTiles: [Coordinate(x: 4, y: 4)],
          ),
        );
        async.elapse(settle);

        expect(harness.controller.activeBombDrops, isEmpty);
        expect(harness.controller.activeExplosions, isEmpty);
        expect(harness.controller.activeDeaths, isEmpty);
        expect(harness.controller.activeLasers, isEmpty);
      });
    });
  });

  group('animation lifecycles', () {
    test('a bomb drop clears itself after the drop duration', () async {
      await buildRoom();

      fakeAsync((async) {
        harness.controller.triggerBombAnimation(localId, 0, 0, 3, 3);
        expect(harness.controller.activeBombDrops, hasLength(1));

        async.elapse(anim.bombDrop);
        expect(harness.controller.activeBombDrops, isEmpty);
      });
    });

    test('two bombs on the same tile clear independently, keyed by id', () async {
      await buildRoom();

      fakeAsync((async) {
        harness.controller.triggerBombAnimation('p-1', 0, 0, 3, 3);
        async.elapse(const Duration(milliseconds: 250));
        harness.controller.triggerBombAnimation('p-2', 0, 0, 3, 3);

        // First bomb's timer fires; the second must survive it.
        async.elapse(const Duration(milliseconds: 250));
        expect(harness.controller.activeBombDrops, hasLength(1));
        expect(harness.controller.activeBombDrops.single.bomberId, 'p-2');

        async.elapse(anim.bombDrop);
        expect(harness.controller.activeBombDrops, isEmpty);
      });
    });

    test('two explosions on the same tile clear together, keyed by coordinate', () async {
      // Characterization of an inconsistency: triggerBombAnimation removes by
      // id, but triggerExplosionEffect removes with (c) => c.x == x && c.y == y.
      // The first timer therefore wipes the later explosion on that tile too,
      // cutting its flash short. Two bombers can target the same tile in one
      // round, so this is reachable. Keying the removal on id, as the bomb
      // animation already does, would fix it.
      await buildRoom();

      fakeAsync((async) {
        harness.controller.triggerExplosionEffect(3, 3);
        async.elapse(const Duration(milliseconds: 250));
        harness.controller.triggerExplosionEffect(3, 3);
        expect(harness.controller.activeExplosions, hasLength(2));

        async.elapse(const Duration(milliseconds: 250));
        expect(harness.controller.activeExplosions, isEmpty);
      });
    });

    test('explosions on different tiles do not clear each other', () async {
      await buildRoom();

      fakeAsync((async) {
        harness.controller.triggerExplosionEffect(3, 3);
        async.elapse(const Duration(milliseconds: 250));
        harness.controller.triggerExplosionEffect(4, 4);

        async.elapse(const Duration(milliseconds: 250));
        expect(harness.controller.activeExplosions.single.x, 4);

        async.elapse(anim.explosion);
        expect(harness.controller.activeExplosions, isEmpty);
      });
    });

    test('death animations share the same coordinate-keyed removal', () async {
      await buildRoom();

      fakeAsync((async) {
        harness.controller.triggerDeathAnimation(2, 2);
        async.elapse(const Duration(milliseconds: 750));
        harness.controller.triggerDeathAnimation(2, 2);

        async.elapse(const Duration(milliseconds: 750));
        expect(harness.controller.activeDeaths, isEmpty);
      });
    });

    test('a laser burst clears every tile at once', () async {
      await buildRoom();

      fakeAsync((async) {
        harness.controller.triggerLaserAnimation([
          Coordinate(x: 1, y: 1),
          Coordinate(x: 2, y: 2),
        ]);
        expect(harness.controller.activeLasers, hasLength(2));

        async.elapse(anim.laserBeam);
        expect(harness.controller.activeLasers, isEmpty);
      });
    });

    test('a hide animation spawns off-board and clears after the sequence', () async {
      await buildRoom();

      fakeAsync((async) {
        harness.controller.triggerHideAnimation(localId, true, targetX: 3, targetY: 3);

        final animation = harness.controller.activeHideAnimations.single;
        // Spawns outside the 0..7 board and walks to an edge cell.
        expect(
          animation.startX < 0 || animation.startX > 7 || animation.startY < 0 || animation.startY > 7,
          isTrue,
        );

        async.elapse(anim.hideSequence);
        expect(harness.controller.activeHideAnimations, isEmpty);
      });
    });

    test('concurrent hide animations clear independently, keyed by id', () async {
      await buildRoom();

      fakeAsync((async) {
        harness.controller.triggerHideAnimation('p-1', false);
        async.elapse(const Duration(milliseconds: 1250));
        harness.controller.triggerHideAnimation('p-2', false);

        async.elapse(const Duration(milliseconds: 1250));
        expect(harness.controller.activeHideAnimations.single.playerId, 'p-2');

        async.elapse(anim.hideSequence);
        expect(harness.controller.activeHideAnimations, isEmpty);
      });
    });
  });
}
