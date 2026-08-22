import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/core/domain/entities/spectator_entity.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/log_action_type.dart';
import 'package:boom_board/features/simple_mode/domain/entities/action_log_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/forced_position_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_over_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_reset_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_started_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/phase_changed_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_disconnected_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_joined_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_left_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_ready_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_reconnected_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_renamed_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/room_snapshot_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/spectator_changed_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_result_entity.dart';
import 'package:boom_board/features/simple_mode/presentation/controllers/simple_mode_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/controller_harness.dart';
import '../../../../helpers/mocks.dart';
import '../../../../helpers/test_di.dart';

ActionLogEntity log(String id) {
  return ActionLogEntity(
    id: id,
    type: LogActionType.bombExploded,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    data: const <String, dynamic>{},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimpleModeControllerHarness harness;

  setUpAll(registerTestFallbackValues);

  Future<void> buildRoom({String? hostId}) async {
    harness = SimpleModeControllerHarness();
    await harness.setUp(
      hostId: hostId,
      players: [player(id: localId), player(id: 'p-2')],
    );
  }

  tearDown(() => harness.tearDown());

  group('eventBus wiring', () {
    test('a fired PlayerJoinedEvent reaches the controller once subscribed', () async {
      await buildRoom();
      harness.subscribe();

      eventBus.fire(
        PlayerJoinedEvent(
          playerId: 'p-3',
          playerName: 'Cara',
          playerList: [player(id: localId), player(id: 'p-2'), player(id: 'p-3')],
        ),
      );
      await pumpEventBus();

      expect(harness.controller.playerList, hasLength(3));
    });

    test('nothing reaches the controller after unsubscribe', () async {
      await buildRoom();
      harness.subscribe();
      harness.controller.unsubscribeListener();

      eventBus.fire(
        PlayerJoinedEvent(playerId: 'p-3', playerName: 'Cara', playerList: [player(id: 'p-3')]),
      );
      await pumpEventBus();

      expect(harness.controller.playerList, hasLength(2));
    });
  });

  group('onPlayerJoinedEventReceived', () {
    test('replaces the player list wholesale', () async {
      await buildRoom();

      harness.controller.onPlayerJoinedEventReceived(
        PlayerJoinedEvent(
          playerId: 'p-3',
          playerName: 'Cara',
          playerList: [player(id: localId), player(id: 'p-2'), player(id: 'p-3')],
        ),
      );

      expect(harness.controller.playerList.map((p) => p.id), [localId, 'p-2', 'p-3']);
    });
  });

  group('onPlayerLeftEventReceived', () {
    test('applies the new list and promotes the new host', () async {
      await buildRoom(hostId: 'p-2');
      expect(harness.controller.isHost, isFalse);

      harness.controller.onPlayerLeftEventReceived(
        PlayerLeftEvent(
          playerId: 'p-2',
          newHostId: localId,
          playerList: [player(id: localId)],
          newLogs: const [],
        ),
      );

      expect(harness.controller.playerList, hasLength(1));
      expect(harness.controller.hostId, localId);
      expect(harness.controller.isHost, isTrue);
    });

    test('keeps our own tile when someone leaves mid-game', () async {
      // This event fires mid-game now that leaving removes a player from the
      // board, and the broadcast roster carries no positions -- ours is private.
      // Taking the list raw would blank our avatar off the board every time
      // anyone walked out.
      await buildRoom();
      harness.controller.playerList = [
        player(id: localId, x: 3, y: 4, hasPositioned: true),
        player(id: 'p-2'),
      ];

      harness.controller.onPlayerLeftEventReceived(
        PlayerLeftEvent(
          playerId: 'p-2',
          newHostId: localId,
          playerList: [player(id: localId, hasPositioned: true)],
          newLogs: const [],
        ),
      );

      expect(harness.playerById(localId).x, 3);
      expect(harness.playerById(localId).y, 4);
    });

    test('appends the departure log line', () async {
      await buildRoom();

      harness.controller.onPlayerLeftEventReceived(
        PlayerLeftEvent(
          playerId: 'p-2',
          newHostId: localId,
          playerList: [player(id: localId)],
          newLogs: [
            ActionLogEntity(
              id: 'log-1',
              type: LogActionType.playerLeft,
              timestamp: DateTime.now(),
              data: const {'playerId': 'p-2', 'playerName': 'Bob'},
            ),
          ],
        ),
      );

      expect(harness.controller.actionLogList, hasLength(1));
      expect(harness.controller.actionLogList.single.type, LogActionType.playerLeft);
    });
  });

  group('onPlayerReadyEventReceived', () {
    test('marks a player positioned during the hide phase', () async {
      await buildRoom();
      harness.controller.currentState = GameState.position;

      harness.controller.onPlayerReadyEventReceived(PlayerReadyEvent(playerId: 'p-2'));

      expect(harness.playerById('p-2').hasPositioned, isTrue);
    });

    test('queues a hide animation for a remote player only', () async {
      await buildRoom();
      harness.controller.currentState = GameState.position;

      harness.controller.onPlayerReadyEventReceived(PlayerReadyEvent(playerId: 'p-2'));
      expect(harness.controller.activeHideAnimations, hasLength(1));
      expect(harness.controller.activeHideAnimations.single.isLocal, isFalse);

      // The local player's animation is already queued by setPosition, so the
      // echoed server event must not queue a second one.
      harness.controller.onPlayerReadyEventReceived(PlayerReadyEvent(playerId: localId));
      expect(harness.controller.activeHideAnimations, hasLength(1));
    });

    test('records the throw order during the attack phase', () async {
      await buildRoom();
      harness.controller.currentState = GameState.attack;

      harness.controller.onPlayerReadyEventReceived(
        PlayerReadyEvent(playerId: 'p-2', throwOrder: 3),
      );

      expect(harness.playerById('p-2').hasThrowBomb, isTrue);
      expect(harness.playerById('p-2').throwOrder, 3);
      expect(harness.controller.activeHideAnimations, isEmpty);
    });

    test('ignores an unknown player id', () async {
      await buildRoom();
      harness.controller.currentState = GameState.position;

      harness.controller.onPlayerReadyEventReceived(PlayerReadyEvent(playerId: 'ghost'));

      expect(harness.controller.playerList.every((p) => p.hasPositioned == false), isTrue);
    });

    test('does nothing in the lobby phase', () async {
      await buildRoom();
      harness.controller.currentState = GameState.lobby;

      harness.controller.onPlayerReadyEventReceived(PlayerReadyEvent(playerId: 'p-2'));

      expect(harness.playerById('p-2').hasPositioned, isFalse);
      expect(harness.playerById('p-2').hasThrowBomb, isFalse);
    });
  });

  group('onPlayerDisconnectedEventReceived', () {
    test('applies the list, the new host and appends the logs', () async {
      await buildRoom(hostId: 'p-2');
      harness.controller.actionLogList = [log('old')];

      harness.controller.onPlayerDisconnectedEventReceived(
        PlayerDisconnectedEvent(
          disconnectedPlayerId: 'p-2',
          newHostId: localId,
          playerList: [player(id: localId)],
          newLogs: [log('new-1'), log('new-2')],
        ),
      );

      expect(harness.controller.hostId, localId);
      expect(harness.controller.playerList, hasLength(1));
      expect(harness.controller.actionLogList.map((l) => l.id), ['old', 'new-1', 'new-2']);
    });

    test('leaves the dropped player alive on the board', () async {
      // The whole feature: a disconnect holds the seat rather than eliminating
      // it, so the roster shows offline-but-alive and they can still win.
      await buildRoom();

      harness.controller.onPlayerDisconnectedEventReceived(
        PlayerDisconnectedEvent(
          disconnectedPlayerId: 'p-2',
          newHostId: localId,
          playerList: [player(id: localId), player(id: 'p-2', isDisconnected: true)],
          newLogs: const [],
        ),
      );

      expect(harness.playerById('p-2').isDisconnected, isTrue);
      expect(harness.playerById('p-2').isAlive, isTrue);
    });

    test('keeps the local player on their tile', () async {
      // Positions are private, so a broadcast roster carries no x/y. Applying
      // it naively would blank the local avatar every time anyone dropped.
      await buildRoom();
      harness.controller.playerList = [
        player(id: localId, hasPositioned: true, x: 4, y: 6),
        player(id: 'p-2'),
      ];

      harness.controller.onPlayerDisconnectedEventReceived(
        PlayerDisconnectedEvent(
          disconnectedPlayerId: 'p-2',
          newHostId: localId,
          playerList: [
            player(id: localId, hasPositioned: true),
            player(id: 'p-2', isDisconnected: true),
          ],
          newLogs: const [],
        ),
      );

      expect(harness.local.x, 4);
      expect(harness.local.y, 6);
    });
  });

  group('onPlayerReconnectedEventReceived', () {
    test('clears the disconnected flag from the refreshed roster', () async {
      await buildRoom();
      harness.controller.playerList = [
        player(id: localId),
        player(id: 'p-2', isDisconnected: true),
      ];

      harness.controller.onPlayerReconnectedEventReceived(
        PlayerReconnectedEvent(
          playerId: 'p-2',
          playerList: [player(id: localId), player(id: 'p-2')],
        ),
      );

      expect(harness.playerById('p-2').isDisconnected, isFalse);
    });
  });

  group('onPlayerRenamedEventReceived', () {
    test('renames one roster row and leaves the rest alone', () async {
      await buildRoom();

      harness.controller.onPlayerRenamedEventReceived(
        PlayerRenamedEvent(playerId: 'p-2', name: 'Roberta'),
      );

      expect(harness.playerById('p-2').name, 'Roberta');
      expect(harness.local.name, localId);
    });

    test('renames a spectator when the id is not a player', () async {
      await buildRoom();
      harness.controller.spectatorList = [SpectatorEntity(id: 's-1', name: 'Watcher')];

      harness.controller.onPlayerRenamedEventReceived(
        PlayerRenamedEvent(playerId: 's-1', name: 'Watcher II'),
      );

      expect(harness.controller.spectatorList.single.name, 'Watcher II');
    });

    test('ignores an id that belongs to nobody', () async {
      await buildRoom();

      expect(
        () => harness.controller.onPlayerRenamedEventReceived(
          PlayerRenamedEvent(playerId: 'ghost', name: 'Nobody'),
        ),
        returnsNormally,
      );
    });
  });

  group('spectator events', () {
    test('a joining spectator lands in the spectator list, not the roster', () async {
      // Spectators are not board participants: they have no tile, no rank, and
      // must not count toward the roster the start gate reads.
      await buildRoom();

      harness.controller.onSpectatorJoinedEventReceived(
        SpectatorJoinedEvent(
          spectator: SpectatorEntity(id: 's-1', name: 'Watcher'),
          spectatorList: [SpectatorEntity(id: 's-1', name: 'Watcher')],
        ),
      );

      expect(harness.controller.spectatorList.single.id, 's-1');
      expect(harness.controller.playerList.map((p) => p.id), isNot(contains('s-1')));
    });

    test('a leaving spectator is dropped from the list', () async {
      await buildRoom();
      harness.controller.spectatorList = [SpectatorEntity(id: 's-1', name: 'Watcher')];

      harness.controller.onSpectatorLeftEventReceived(
        SpectatorLeftEvent(spectatorId: 's-1', spectatorList: const []),
      );

      expect(harness.controller.spectatorList, isEmpty);
    });
  });

  group('applyRoomSnapshot', () {
    RoomSnapshotEvent snapshot({
      GameState state = GameState.attack,
      int roundNumber = 3,
      int remainingMs = 12000,
      bool isSpectator = false,
      RoomSnapshotSelf? you,
      List<SimpleModePlayerEntity>? players,
      List<SpectatorEntity>? spectators,
      List<ActionLogEntity>? logs,
      List<SimpleModeResultEntity>? ranking,
      Coordinate? winnerPosition,
    }) {
      return RoomSnapshotEvent(
        state: state,
        roundNumber: roundNumber,
        boardWidth: 8,
        boardHeight: 8,
        destroyedTiles: [Coordinate(x: 0, y: 1)],
        timeLimit: 30,
        remainingMs: remainingMs,
        hostId: localId,
        playerList: players ?? [player(id: localId), player(id: 'p-2')],
        spectatorList: spectators ?? const [],
        logs: logs ?? const [],
        isSpectator: isSpectator,
        you: you,
        ranking: ranking ?? const [],
        winnerPosition: winnerPosition,
      );
    }

    test('rebuilds the public room state a returning client missed', () async {
      await buildRoom();

      harness.controller.applyRoomSnapshot(snapshot(spectators: [SpectatorEntity(id: 's-1', name: 'Watcher')]));

      expect(harness.controller.currentState, GameState.attack);
      expect(harness.controller.currentRound, 3);
      expect(harness.controller.destroyedTile, [Coordinate(x: 0, y: 1)]);
      expect(harness.controller.spectatorList.single.id, 's-1');
    });

    test('restores the local seat from the private `you` block', () async {
      await buildRoom();

      harness.controller.applyRoomSnapshot(
        snapshot(
          you: RoomSnapshotSelf(
            x: 4,
            y: 2,
            hasPositioned: true,
            bombTarget: Coordinate(x: 5, y: 5),
            throwOrder: 1,
            isAlive: true,
          ),
        ),
      );

      expect(harness.local.x, 4);
      expect(harness.local.y, 2);
      expect(harness.local.hasPositioned, isTrue);
      expect(harness.local.hasThrowBomb, isTrue);
      expect(harness.local.throwOrder, 1);
      expect(harness.controller.lockedBombTarget, Coordinate(x: 5, y: 5));
    });

    test('a dead reconnect comes back dead, so existing gating makes them passive', () async {
      await buildRoom();

      harness.controller.applyRoomSnapshot(
        snapshot(
          players: [player(id: localId, isAlive: false), player(id: 'p-2')],
          you: RoomSnapshotSelf(
            x: 4,
            y: 2,
            hasPositioned: true,
            bombTarget: null,
            throwOrder: null,
            isAlive: false,
          ),
        ),
      );

      expect(harness.local.isAlive, isFalse);
      expect(harness.controller.lockedBombTarget, isNull);
    });

    test('replaces the log rather than appending, so nothing is duplicated', () async {
      // The snapshot carries the current round's logs in full.
      await buildRoom();
      harness.controller.actionLogList = [log('already-seen')];

      harness.controller.applyRoomSnapshot(snapshot(logs: [log('already-seen'), log('missed')]));

      expect(harness.controller.actionLogList.map((l) => l.id), ['already-seen', 'missed']);
    });

    test('starts the timer at what is left of the phase, not from full', () async {
      // The phase clock never paused while the client was away.
      await buildRoom();

      harness.controller.applyRoomSnapshot(snapshot(remainingMs: 12450));

      expect(harness.controller.currentPhaseTimeLimit, 13);
    });

    test('starts the bar part-drained so it empties at the normal rate', () async {
      // Half a 30s phase left means a half-empty bar with 15s to run. Starting
      // it full would drain at double speed to catch up, which is what a
      // reconnecting player used to see while everyone else's bar crawled.
      await buildRoom();

      harness.controller.applyRoomSnapshot(snapshot(remainingMs: 15000));

      expect(harness.controller.currentPhaseTimeLimit, 15);
      expect(harness.controller.currentPhaseStartProgress, closeTo(0.5, 0.001));
    });

    test('starts the bar full when the phase is joined at its start', () async {
      await buildRoom();

      harness.controller.applyRoomSnapshot(snapshot(remainingMs: 30000));

      expect(harness.controller.currentPhaseStartProgress, 1);
    });

    test('gets a distinct timer key per phase start, however fast they arrive', () async {
      // The key is the only thing that remounts the bar, and only a remount
      // reads currentPhaseStartProgress -- TweenAnimationBuilder ignores a
      // changed `begin` on rebuild. Draining a backlog of buffered events after
      // a resume puts several of these in the same phase inside one
      // millisecond, so a wall-clock key would collide and silently keep the
      // earlier bar. A burst is the only way to assert that deterministically.
      await buildRoom();

      final keys = <String>{};
      for (var i = 0; i < 50; i++) {
        harness.controller.applyRoomSnapshot(snapshot(remainingMs: 30000 - i));
        keys.add(harness.controller.currentTimerKey);
      }

      expect(keys, hasLength(50));
    });

    test('a later snapshot in the same phase replaces the bar it found', () async {
      await buildRoom();

      harness.controller.applyRoomSnapshot(snapshot(remainingMs: 30000));
      final firstKey = harness.controller.currentTimerKey;

      harness.controller.applyRoomSnapshot(snapshot(remainingMs: 12000));

      expect(harness.controller.currentTimerKey, isNot(firstKey));
      expect(harness.controller.currentPhaseStartProgress, closeTo(0.4, 0.001));
    });

    test('runs no timer in an untimed phase', () async {
      await buildRoom();

      harness.controller.applyRoomSnapshot(snapshot(state: GameState.end, remainingMs: 0));

      expect(harness.controller.currentPhaseTimeLimit, lessThanOrEqualTo(0));
      expect(harness.controller.currentPhaseStartProgress, 1);
    });

    test('seeds the endgame overlay when the game is already over', () async {
      await buildRoom();

      harness.controller.applyRoomSnapshot(
        snapshot(
          state: GameState.end,
          remainingMs: 0,
          ranking: [
            SimpleModeResultEntity(rank: 1, id: localId, name: localId, isAlive: true, isDisconnected: false),
          ],
          winnerPosition: Coordinate(x: 2, y: 5),
        ),
      );

      expect(harness.controller.finalRanking.single.rank, 1);
      expect(harness.controller.winnerPosition, Coordinate(x: 2, y: 5));
      expect(harness.controller.showEndgameOverlay, isTrue);
    });

    test('marks the client a spectator and leaves it without a seat', () async {
      await buildRoom();

      harness.controller.applyRoomSnapshot(
        snapshot(isSpectator: true, players: [player(id: 'p-2'), player(id: 'p-3')]),
      );

      expect(harness.controller.isSpectator, isTrue);
      expect(harness.controller.localPlayer, isNull);
    });

    test('clears the connection overlay, since the snapshot means we are back', () async {
      await buildRoom();
      harness.controller.connectionState = RoomConnectionState.reconnectFailed;
      harness.controller.connectionError = 'whatever';

      harness.controller.applyRoomSnapshot(snapshot());

      expect(harness.controller.connectionState, RoomConnectionState.connected);
      expect(harness.controller.connectionError, isNull);
    });

    test('drops animations left mid-flight by the drop', () async {
      // Nothing that follows a reconnect would ever remove them.
      await buildRoom();
      harness.controller.triggerExplosionEffect(1, 1);
      expect(harness.controller.activeExplosions, isNotEmpty);

      harness.controller.applyRoomSnapshot(snapshot());

      expect(harness.controller.activeExplosions, isEmpty);
      expect(harness.controller.activeBombDrops, isEmpty);
      expect(harness.controller.activeHideAnimations, isEmpty);
    });
  });

  group('onGameStartEventReceived', () {
    test('applies the phase, destroyed tiles and timer', () async {
      await buildRoom();

      harness.controller.onGameStartEventReceived(
        GameStartedEvent(
          boardWidth: 8,
          boardHeight: 8,
          state: GameState.position,
          destroyedTiles: [Coordinate(x: 1, y: 1)],
          timeLimit: 30,
        ),
      );

      expect(harness.controller.currentState, GameState.position);
      expect(harness.controller.destroyedTile, hasLength(1));
      expect(harness.controller.currentPhaseTimeLimit, 30);
      expect(harness.controller.currentPhaseStartProgress, 1, reason: 'a phase joined at its start begins full');
      expect(harness.controller.currentTimerKey, isNotEmpty);
    });
  });

  group('onPhaseChangedEventReceived', () {
    test('entering attack forces everyone positioned and clears throw state', () async {
      await buildRoom();
      harness.controller.currentState = GameState.position;
      harness.controller.playerList = [
        player(id: localId, hasPositioned: true, hasThrowBomb: true, throwOrder: 2),
        player(id: 'p-2', hasPositioned: false, throwOrder: 1),
      ];

      harness.controller.onPhaseChangedEventReceived(
        PhaseChangedEvent(state: GameState.attack, timeLimit: 20),
      );

      expect(harness.controller.currentState, GameState.attack);
      expect(harness.controller.playerList.every((p) => p.hasPositioned), isTrue);
      expect(harness.controller.playerList.every((p) => p.hasThrowBomb == false), isTrue);
      expect(harness.controller.playerList.every((p) => p.throwOrder == null), isTrue);
      expect(harness.controller.currentPhaseTimeLimit, 20);
    });

    test('queues a hide animation only for remote players who never positioned', () async {
      await buildRoom();
      harness.controller.playerList = [
        player(id: localId, hasPositioned: false),
        player(id: 'p-2', hasPositioned: false),
        player(id: 'p-3', hasPositioned: true),
      ];

      harness.controller.onPhaseChangedEventReceived(
        PhaseChangedEvent(state: GameState.attack, timeLimit: 20),
      );

      // p-2 only: the local player is excluded, p-3 already positioned.
      expect(harness.controller.activeHideAnimations, hasLength(1));
      expect(harness.controller.activeHideAnimations.single.playerId, 'p-2');
    });

    test('forces eliminated players positioned too', () async {
      // Characterization: the loop has no isAlive check, so a dead player is
      // marked positioned along with everyone else.
      await buildRoom();
      harness.controller.playerList = [
        player(id: localId),
        player(id: 'p-2', isAlive: false, hasPositioned: false),
      ];

      harness.controller.onPhaseChangedEventReceived(
        PhaseChangedEvent(state: GameState.attack, timeLimit: 20),
      );

      expect(harness.playerById('p-2').hasPositioned, isTrue);
      expect(harness.playerById('p-2').isAlive, isFalse);
    });

    test('a non-attack phase leaves the player list untouched', () async {
      await buildRoom();
      harness.controller.playerList = [player(id: localId, hasThrowBomb: true, throwOrder: 1)];

      harness.controller.onPhaseChangedEventReceived(
        PhaseChangedEvent(state: GameState.position, timeLimit: 30),
      );

      expect(harness.controller.currentState, GameState.position);
      expect(harness.local.hasThrowBomb, isTrue);
      expect(harness.local.throwOrder, 1);
    });

    test('a non-attack phase does not start the timer', () async {
      // _startPhaseTimer only runs on the attack branch, so the hide phase
      // keeps whatever limit gameStarted set.
      await buildRoom();
      harness.controller.currentPhaseTimeLimit = 30;

      harness.controller.onPhaseChangedEventReceived(
        PhaseChangedEvent(state: GameState.position, timeLimit: 99),
      );

      expect(harness.controller.currentPhaseTimeLimit, 30);
    });
  });

  group('onGameOverEventReceived', () {
    test('ends the game and records the ranking', () async {
      await buildRoom();
      harness.controller.lockedBombTarget = Coordinate(x: 1, y: 1);
      harness.controller.showEndgameOverlay = false;

      harness.controller.onGameOverEventReceived(
        GameOverEvent(
          ranking: [
            SimpleModeResultEntity(
              rank: 1,
              id: localId,
              name: 'Alice',
              isAlive: true,
              isDisconnected: false,
            ),
          ],
          winnerPosition: Coordinate(x: 4, y: 4),
        ),
      );

      expect(harness.controller.currentState, GameState.end);
      expect(harness.controller.finalRanking.single.rank, 1);
      expect(harness.controller.winnerPosition, Coordinate(x: 4, y: 4));
      expect(harness.controller.lockedBombTarget, isNull);
      expect(harness.controller.showEndgameOverlay, isTrue);
      expect(harness.controller.currentPhaseTimeLimit, -1);
    });

    test('accepts a winner with no position, which is how the hide phase ends', () async {
      // Reachable since leaving removes a player from the board: the roster can
      // drop to one during `position`, before anyone has picked a tile. The
      // server then has no living, positioned player to point at and sends
      // `winnerPosition: null`, and the survivor's own x/y are still null.
      // Previously the game could only end out of `processRound`, where every
      // living player is guaranteed to hold a tile.
      await buildRoom();
      harness.controller.currentState = GameState.position;
      harness.controller.playerList = [player(id: localId, hasPositioned: false)];

      harness.controller.onGameOverEventReceived(
        GameOverEvent(
          ranking: [
            SimpleModeResultEntity(
              rank: 1,
              id: localId,
              name: 'Alice',
              isAlive: true,
              isDisconnected: false,
            ),
          ],
          winnerPosition: null,
        ),
      );

      expect(harness.controller.currentState, GameState.end);
      expect(harness.controller.finalRanking.single.name, 'Alice');
      expect(harness.controller.winnerPosition, isNull);
      expect(harness.playerById(localId).x, isNull);
    });
  });

  group('onGameResetEventReceived', () {
    test('clears round state and applies the fresh player list', () async {
      await buildRoom();
      harness.controller
        ..currentState = GameState.end
        ..currentRound = 5
        ..actionLogList = [log('a')]
        ..destroyedTile = [Coordinate(x: 1, y: 1)]
        ..lockedBombTarget = Coordinate(x: 2, y: 2)
        ..winnerPosition = Coordinate(x: 3, y: 3)
        ..showEndgameOverlay = false;

      harness.controller.onGameResetEventReceived(
        GameResetEvent(
          playerList: [player(id: localId), player(id: 'p-2')],
          spectatorList: const [],
          newHostId: localId,
        ),
      );

      expect(harness.controller.currentState, GameState.lobby);
      expect(harness.controller.currentRound, 1);
      expect(harness.controller.actionLogList, isEmpty);
      expect(harness.controller.destroyedTile, isEmpty);
      expect(harness.controller.lockedBombTarget, isNull);
      expect(harness.controller.winnerPosition, isNull);
      expect(harness.controller.showEndgameOverlay, isTrue);
      expect(harness.controller.playerList, hasLength(2));
    });
  });

  group('onForcedPositionReceived', () {
    test('positions the local player at the server-chosen tile', () async {
      await buildRoom();

      harness.controller.onForcedPositionReceived(
        ForcedPositionEvent(position: Coordinate(x: 6, y: 2)),
      );

      expect(harness.local.hasPositioned, isTrue);
      expect(harness.local.x, 6);
      expect(harness.local.y, 2);
    });

    test('queues a local hide animation at that tile', () async {
      await buildRoom();

      harness.controller.onForcedPositionReceived(
        ForcedPositionEvent(position: Coordinate(x: 6, y: 2)),
      );

      final anim = harness.controller.activeHideAnimations.single;
      expect(anim.isLocal, isTrue);
      expect(anim.targetX, 6);
      expect(anim.targetY, 2);
    });

    test('does nothing when the local player is not in the room', () async {
      await buildRoom();
      harness.controller.playerList = [player(id: 'p-2')];

      harness.controller.onForcedPositionReceived(
        ForcedPositionEvent(position: Coordinate(x: 6, y: 2)),
      );

      expect(harness.controller.activeHideAnimations, isEmpty);
    });
  });

  group('resetRound', () {
    test('clears round state but leaves the player list alone', () async {
      await buildRoom();
      harness.controller
        ..currentRound = 4
        ..actionLogList = [log('a')];

      harness.controller.resetRound();

      expect(harness.controller.currentRound, 1);
      expect(harness.controller.actionLogList, isEmpty);
      expect(harness.controller.playerList, hasLength(2));
    });
  });
}
