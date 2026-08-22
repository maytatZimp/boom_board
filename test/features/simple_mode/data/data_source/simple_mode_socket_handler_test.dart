import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/features/simple_mode/data/data_source/room_snapshot_cache.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_handler.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/log_action_type.dart';
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
import 'package:boom_board/features/simple_mode/domain/entities/events/round_resolved_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/spectator_changed_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/mocks.dart';
import '../../../../helpers/test_di.dart';

/// Every event `init()` binds, in the order the handler registers them.
const boundEvents = <String>[
  'playerJoined',
  'playerLeft',
  'playerDisconnected',
  'playerReconnected',
  'playerRenamed',
  'spectatorJoined',
  'spectatorLeft',
  'roomSnapshot',
  'gameStarted',
  'playerReady',
  'phaseChanged',
  'roundResolved',
  'gameOver',
  'gameReset',
  'forcedPosition',
];

void main() {
  late MockSocketService socketService;
  late FakeSocket socket;
  late RoomSnapshotCache snapshotCache;
  late SimpleModeSocketHandler handler;

  setUp(() async {
    await setUpTestDependencies();
    socket = FakeSocket();
    socketService = MockSocketService();
    when(() => socketService.socket).thenReturn(socket);
    snapshotCache = RoomSnapshotCache();
    handler = SimpleModeSocketHandler(socketService: socketService, roomSnapshotCache: snapshotCache);
  });

  tearDown(tearDownTestDependencies);

  /// Collects everything of type [T] the handler puts on the bus.
  List<T> listenFor<T>() {
    final received = <T>[];
    eventBus.on<T>().listen(received.add);
    return received;
  }

  group('init / dispose', () {
    test('binds a handler for every server event', () {
      handler.init();

      for (final event in boundEvents) {
        expect(socket.handlerCount(event), 1, reason: '$event should be bound once');
      }
    });

    test('dispose unbinds every event it bound', () {
      handler.init();
      handler.dispose();

      for (final event in boundEvents) {
        expect(socket.handlerCount(event), 0, reason: '$event should be unbound');
      }
    });

    test('dispose before init is a no-op rather than an error', () {
      expect(handler.dispose, returnsNormally);
    });

    test('a repeated init still leaves exactly one handler per event', () {
      // socket.on() appends and nothing else deduplicates, so init() unbinds
      // first. Without that, an init() reached without an intervening
      // dispose() -- a failed leaveRoom, or a connection drop that navigates
      // home on its own -- would double every binding.
      handler.init();
      handler.init();
      handler.init();

      for (final event in boundEvents) {
        expect(socket.handlerCount(event), 1, reason: '$event should still be bound once');
      }
    });

    test('a single dispose after a repeated init unbinds everything', () async {
      // off() removes the first identity match only, so cleanup would not be
      // symmetric with a double registration. init() being idempotent is what
      // keeps one dispose() enough.
      handler.init();
      handler.init();
      handler.dispose();

      expect(socket.handlerCount('playerJoined'), 0);

      final received = listenFor<PlayerJoinedEvent>();
      socket.serverEmit('playerJoined', socketEnvelope(playerJoinedPayload()));
      await pumpEventBus();

      expect(received, isEmpty);
    });

    test('a repeated init does not duplicate event delivery', () async {
      // The symptom this guards: duplicated action-log entries and
      // double-applied player mutations from one server message.
      handler.init();
      handler.init();

      final received = listenFor<PlayerJoinedEvent>();
      socket.serverEmit('playerJoined', socketEnvelope(playerJoinedPayload()));
      await pumpEventBus();

      expect(received, hasLength(1));
    });

    test('init after dispose rebinds, so a rejoined room still gets events', () async {
      // The unbind-then-rebind cycle a leave/rejoin goes through.
      handler.init();
      handler.dispose();
      handler.init();

      final received = listenFor<PlayerJoinedEvent>();
      socket.serverEmit('playerJoined', socketEnvelope(playerJoinedPayload()));
      await pumpEventBus();

      expect(received, hasLength(1));
    });
  });

  group('end-to-end through a bound socket', () {
    test('a server playerJoined message reaches the eventBus', () async {
      handler.init();
      final received = listenFor<PlayerJoinedEvent>();

      socket.serverEmit('playerJoined', socketEnvelope(playerJoinedPayload()));
      await pumpEventBus();

      expect(received.single.playerId, 'p-2');
      expect(received.single.playerName, 'Bob');
    });

    test('nothing reaches the eventBus after dispose', () async {
      handler.init();
      handler.dispose();
      final received = listenFor<PlayerJoinedEvent>();

      socket.serverEmit('playerJoined', socketEnvelope(playerJoinedPayload()));
      await pumpEventBus();

      expect(received, isEmpty);
    });
  });

  group('onPlayerJoined', () {
    test('maps the payload onto a PlayerJoinedEvent', () async {
      final received = listenFor<PlayerJoinedEvent>();

      handler.onPlayerJoined(socketEnvelope(playerJoinedPayload()));
      await pumpEventBus();

      expect(received.single.playerId, 'p-2');
      expect(received.single.playerName, 'Bob');
      expect(received.single.playerList, hasLength(2));
      expect(received.single.playerList.every((p) => p.hasThrowBomb == false), isTrue);
    });

    test('reads the id and name keys, not playerId and playerName', () async {
      // PlayerJoinedModel maps json['id'] -> playerId, json['name'] ->
      // playerName. A rename on either side would silently null these out.
      final received = listenFor<PlayerJoinedEvent>();

      handler.onPlayerJoined(socketEnvelope(playerJoinedPayload(id: 'x-1', name: 'Zoe')));
      await pumpEventBus();

      expect(received.single.playerId, 'x-1');
      expect(received.single.playerName, 'Zoe');
    });
  });

  group('onPlayerLeft', () {
    test('maps the payload including the promoted host', () async {
      final received = listenFor<PlayerLeftEvent>();

      handler.onPlayerLeft(
        socketEnvelope(<String, dynamic>{
          'leftPlayerId': 'p-1',
          'newHostId': 'p-2',
          'players': [playerJson(id: 'p-2', name: 'Bob')],
        }),
      );
      await pumpEventBus();

      expect(received.single.playerId, 'p-1');
      expect(received.single.newHostId, 'p-2');
      expect(received.single.playerList.single.id, 'p-2');
    });
  });

  group('onPlayerDisconnected', () {
    test('maps players, new host and the new log entries', () async {
      final received = listenFor<PlayerDisconnectedEvent>();

      handler.onPlayerDisconnected(
        socketEnvelope(<String, dynamic>{
          'disconnectedPlayerId': 'p-1',
          'newHostId': 'p-2',
          'players': [playerJson(id: 'p-2', name: 'Bob')],
          'newLogs': [actionLogJson(id: 'log-1', type: 'PLAYER_DISCONNECTED')],
        }),
      );
      await pumpEventBus();

      expect(received.single.disconnectedPlayerId, 'p-1');
      expect(received.single.newHostId, 'p-2');
      expect(received.single.newLogs.single.type, LogActionType.playerDisconnected);
    });

    test('keeps the dropped player alive in the mapped roster', () async {
      // A disconnect is a connection-status change, never a death -- the wire
      // payload says so and the mapper must not editorialise.
      final received = listenFor<PlayerDisconnectedEvent>();

      handler.onPlayerDisconnected(
        socketEnvelope(<String, dynamic>{
          'disconnectedPlayerId': 'p-1',
          'newHostId': 'p-2',
          'players': [playerJson(id: 'p-1', isAlive: true, isDisconnected: true)],
          'newLogs': <Map<String, dynamic>>[],
        }),
      );
      await pumpEventBus();

      expect(received.single.playerList.single.isAlive, isTrue);
      expect(received.single.playerList.single.isDisconnected, isTrue);
    });

    test('tolerates a null newLogs', () async {
      // The server sends null rather than [] when there is nothing to log.
      final received = listenFor<PlayerDisconnectedEvent>();

      handler.onPlayerDisconnected(
        socketEnvelope(<String, dynamic>{
          'disconnectedPlayerId': 'p-1',
          'newHostId': 'p-2',
          'players': [playerJson(id: 'p-1')],
          'newLogs': null,
        }),
      );
      await pumpEventBus();

      expect(received.single.newLogs, isEmpty);
    });
  });

  group('onPlayerReconnected', () {
    test('maps the returning player and the refreshed roster', () async {
      final received = listenFor<PlayerReconnectedEvent>();

      handler.onPlayerReconnected(
        socketEnvelope(<String, dynamic>{
          'playerId': 'p-1',
          'players': [playerJson(id: 'p-1', isAlive: true, isDisconnected: false)],
        }),
      );
      await pumpEventBus();

      expect(received.single.playerId, 'p-1');
      expect(received.single.playerList.single.isDisconnected, isFalse);
    });
  });

  group('onPlayerRenamed', () {
    test('maps the id and the new display name', () async {
      final received = listenFor<PlayerRenamedEvent>();

      handler.onPlayerRenamed(
        socketEnvelope(<String, dynamic>{'playerId': 'p-1', 'name': 'Alice II'}),
      );
      await pumpEventBus();

      expect(received.single.playerId, 'p-1');
      expect(received.single.name, 'Alice II');
    });
  });

  group('onSpectatorJoined / onSpectatorLeft', () {
    test('maps the arriving spectator and the full list', () async {
      final received = listenFor<SpectatorJoinedEvent>();

      handler.onSpectatorJoined(
        socketEnvelope(<String, dynamic>{
          'spectator': spectatorJson(id: 's-1', name: 'Watcher'),
          'spectators': [spectatorJson(id: 's-1', name: 'Watcher')],
        }),
      );
      await pumpEventBus();

      expect(received.single.spectator.id, 's-1');
      expect(received.single.spectatorList.single.name, 'Watcher');
    });

    test('maps a departing spectator down to an empty list', () async {
      final received = listenFor<SpectatorLeftEvent>();

      handler.onSpectatorLeft(
        socketEnvelope(<String, dynamic>{
          'spectatorId': 's-1',
          'spectators': <Map<String, dynamic>>[],
        }),
      );
      await pumpEventBus();

      expect(received.single.spectatorId, 's-1');
      expect(received.single.spectatorList, isEmpty);
    });
  });

  group('onRoomSnapshot', () {
    test('maps the public room state a returning client needs', () async {
      final received = listenFor<RoomSnapshotEvent>();

      handler.onRoomSnapshot(
        socketEnvelope(
          roomSnapshotJson(
            state: 'attack',
            roundNumber: 3,
            remainingMs: 12450,
            players: [playerJson(id: 'p-1', throwOrder: 1)],
            spectators: [spectatorJson()],
          ),
        ),
      );
      await pumpEventBus();

      final snapshot = received.single;
      expect(snapshot.state, GameState.attack);
      expect(snapshot.roundNumber, 3);
      expect(snapshot.remainingMs, 12450);
      expect(snapshot.spectatorList.single.id, 'spec-1');
      // throwOrder is what tells the roster this player has already thrown.
      expect(snapshot.playerList.single.hasThrowBomb, isTrue);
    });

    test('maps the private `you` block for a player', () async {
      final received = listenFor<RoomSnapshotEvent>();

      handler.onRoomSnapshot(
        socketEnvelope(
          roomSnapshotJson(
            you: snapshotSelfJson(x: 4, y: 2, bombTarget: coordinateJson(x: 5, y: 5), throwOrder: 1),
          ),
        ),
      );
      await pumpEventBus();

      final self = received.single.you!;
      expect(self.x, 4);
      expect(self.y, 2);
      expect(self.bombTarget, Coordinate(x: 5, y: 5));
      expect(self.throwOrder, 1);
    });

    test('leaves `you` null for a spectator', () async {
      // A spectator has no seat, so the private block is simply absent rather
      // than sent full of nulls.
      final received = listenFor<RoomSnapshotEvent>();

      handler.onRoomSnapshot(socketEnvelope(roomSnapshotJson(isSpectator: true)));
      await pumpEventBus();

      expect(received.single.isSpectator, isTrue);
      expect(received.single.you, isNull);
    });

    test('maps ranking and winner position when the game is over', () async {
      final received = listenFor<RoomSnapshotEvent>();

      handler.onRoomSnapshot(
        socketEnvelope(
          roomSnapshotJson(
            state: 'end',
            ranking: [resultJson(rank: 1, id: 'p-1')],
            winnerPosition: coordinateJson(x: 2, y: 5),
          ),
        ),
      );
      await pumpEventBus();

      expect(received.single.state, GameState.end);
      expect(received.single.ranking.single.rank, 1);
      expect(received.single.winnerPosition, Coordinate(x: 2, y: 5));
    });

    test('tolerates a null winner position', () async {
      // The server sends null when no living, positioned player exists yet.
      final received = listenFor<RoomSnapshotEvent>();

      handler.onRoomSnapshot(
        socketEnvelope(roomSnapshotJson(state: 'end', ranking: [resultJson()])),
      );
      await pumpEventBus();

      expect(received.single.winnerPosition, isNull);
    });

    test('parks the snapshot in the cache as well as firing it', () async {
      // On a mid-game entry this lands while the client is still on the home
      // screen, so the bus has no listener yet and the cache is the only copy.
      handler.onRoomSnapshot(socketEnvelope(roomSnapshotJson()));
      await pumpEventBus();

      final cached = snapshotCache.take();
      expect(cached, isNotNull);
      expect(cached!.roundNumber, 3);
    });

    test('the cache hands a snapshot out exactly once', () async {
      handler.onRoomSnapshot(socketEnvelope(roomSnapshotJson()));
      await pumpEventBus();

      expect(snapshotCache.take(), isNotNull);
      expect(snapshotCache.take(), isNull);
    });
  });

  group('onGameStarted', () {
    test('maps the flattened board size, state and time limit', () async {
      final received = listenFor<GameStartedEvent>();

      handler.onGameStarted(
        socketEnvelope(gameStartedJson(width: 8, height: 8, state: 'position', timeLimit: 30)),
      );
      await pumpEventBus();

      expect(received.single.boardWidth, 8);
      expect(received.single.boardHeight, 8);
      expect(received.single.state, GameState.position);
      expect(received.single.timeLimit, 30);
      expect(received.single.destroyedTiles, isEmpty);
    });
  });

  group('onPlayerReady', () {
    test('maps a ready player carrying a throw order', () async {
      final received = listenFor<PlayerReadyEvent>();

      handler.onPlayerReady(
        socketEnvelope(<String, dynamic>{'playerId': 'p-1', 'throwOrder': 2}),
      );
      await pumpEventBus();

      expect(received.single.playerId, 'p-1');
      expect(received.single.throwOrder, 2);
    });

    test('tolerates an absent throwOrder during the hide phase', () async {
      // throwOrder is only meaningful in the attack phase, so the position
      // phase sends this event without it.
      final received = listenFor<PlayerReadyEvent>();

      handler.onPlayerReady(socketEnvelope(<String, dynamic>{'playerId': 'p-1'}));
      await pumpEventBus();

      expect(received.single.throwOrder, isNull);
    });
  });

  group('onPhaseChanged', () {
    test('reads the phase key into state', () async {
      // The wire key is `phase`; the Dart field is `state`.
      final received = listenFor<PhaseChangedEvent>();

      handler.onPhaseChanged(
        socketEnvelope(<String, dynamic>{'phase': 'attack', 'timeLimit': 20}),
      );
      await pumpEventBus();

      expect(received.single.state, GameState.attack);
      expect(received.single.timeLimit, 20);
    });

    test('drops the event when the phase is unknown', () async {
      final received = listenFor<PhaseChangedEvent>();

      handler.onPhaseChanged(
        socketEnvelope(<String, dynamic>{'phase': 'sudden_death', 'timeLimit': 20}),
      );
      await pumpEventBus();

      expect(received, isEmpty);
    });
  });

  group('onRoundResolved', () {
    test('maps explosions, players, tiles, logs and the round number', () async {
      final received = listenFor<RoundResolvedEvent>();

      handler.onRoundResolved(
        socketEnvelope(
          roundResolvedJson(
            explosions: [
              explosionJson(bomberId: 'p-1', victimId: 'p-2', isHit: true, x: 4, y: 4),
            ],
            remainingPlayers: [playerJson(id: 'p-1')],
            destroyedTiles: [coordinateJson(x: 1, y: 1), coordinateJson(x: 2, y: 2)],
            newDestroyedTiles: [coordinateJson(x: 2, y: 2)],
            newLogs: [actionLogJson(id: 'log-1')],
            roundNumber: 3,
          ),
        ),
      );
      await pumpEventBus();

      final event = received.single;
      expect(event.explosionList.single.victimId, 'p-2');
      expect(event.explosionList.single.isHit, isTrue);
      expect(event.playerList.single.id, 'p-1');
      expect(event.destroyedTiles, hasLength(2));
      expect(event.newDestroyedTiles.single, Coordinate(x: 2, y: 2));
      expect(event.newLogs.single.id, 'log-1');
      expect(event.roundNumber, 3);
    });

    test('drops the whole event when one player entry is malformed', () async {
      // A partial round would desync the board from the server, so the
      // all-or-nothing parse is the safer failure -- but it is silent.
      final received = listenFor<RoundResolvedEvent>();
      final bad = playerJson(id: 'p-2')..remove('isAlive');

      handler.onRoundResolved(
        socketEnvelope(roundResolvedJson(remainingPlayers: [playerJson(), bad])),
      );
      await pumpEventBus();

      expect(received, isEmpty);
    });
  });

  group('onGameOver', () {
    test('maps the ranking and the winner position', () async {
      final received = listenFor<GameOverEvent>();

      handler.onGameOver(
        socketEnvelope(
          gameOverJson(
            ranking: [resultJson(rank: 1, id: 'p-1'), resultJson(rank: 2, id: 'p-2')],
            winnerPosition: coordinateJson(x: 6, y: 3),
          ),
        ),
      );
      await pumpEventBus();

      expect(received.single.ranking.map((r) => r.rank), [1, 2]);
      expect(received.single.winnerPosition, Coordinate(x: 6, y: 3));
    });
  });

  group('onGameReset', () {
    test('maps the reset player list with throw state cleared', () async {
      final received = listenFor<GameResetEvent>();

      handler.onGameReset(
        socketEnvelope(<String, dynamic>{
          'players': [playerJson(id: 'p-1'), playerJson(id: 'p-2')],
        }),
      );
      await pumpEventBus();

      expect(received.single.playerList, hasLength(2));
      expect(received.single.playerList.every((p) => p.hasThrowBomb == false), isTrue);
    });
  });

  group('onForcedPosition', () {
    test('reads the coordinate off the payload root, not a nested key', () async {
      // ForcedPositionModel passes the whole payload to Coordinate.fromJson,
      // so x and y sit at the top level of `data`.
      final received = listenFor<ForcedPositionEvent>();

      handler.onForcedPosition(socketEnvelope(coordinateJson(x: 5, y: 7)));
      await pumpEventBus();

      expect(received.single.position, Coordinate(x: 5, y: 7));
    });
  });

  group('malformed payloads are swallowed', () {
    test('a non-Map payload fires nothing', () async {
      final received = listenFor<PlayerJoinedEvent>();

      handler.onPlayerJoined('not a map');
      await pumpEventBus();

      expect(received, isEmpty);
    });

    test('a null payload fires nothing', () async {
      final received = listenFor<PlayerJoinedEvent>();

      handler.onPlayerJoined(null);
      await pumpEventBus();

      expect(received, isEmpty);
    });

    test('a payload with no data envelope fires nothing', () async {
      // getData() returns json['data'] with no null check, so a missing
      // envelope becomes fromJson(null) -- caught and logged, event dropped.
      final received = listenFor<PlayerJoinedEvent>();

      handler.onPlayerJoined(<String, dynamic>{'id': 'p-1', 'name': 'Alice'});
      await pumpEventBus();

      expect(received, isEmpty);
    });

    test('an untyped Map<dynamic, dynamic> fires nothing', () async {
      // Characterization of the guard/cast mismatch: _validateSocketEventData
      // only checks `data is! Map`, so an untyped map from the JS interop layer
      // passes the guard and then fails the `as Map<String, dynamic>` cast one
      // line later. The handler catches it and the event vanishes silently --
      // the game simply stops reacting, with nothing surfaced to the player.
      // Tightening the guard to `is! Map<String, dynamic>`, or copying with
      // Map<String, dynamic>.from, would make the intent explicit.
      final received = listenFor<PlayerJoinedEvent>();

      handler.onPlayerJoined(<dynamic, dynamic>{'data': playerJoinedPayload()});
      await pumpEventBus();

      expect(received, isEmpty);
    });

    test('every handler swallows a non-Map payload without throwing', () {
      // Each handler owns its own try/catch; none may escape and kill the
      // socket's receive loop.
      expect(() => handler.onPlayerJoined(1), returnsNormally);
      expect(() => handler.onPlayerLeft(1), returnsNormally);
      expect(() => handler.onPlayerDisconnected(1), returnsNormally);
      expect(() => handler.onPlayerReconnected(1), returnsNormally);
      expect(() => handler.onPlayerRenamed(1), returnsNormally);
      expect(() => handler.onSpectatorJoined(1), returnsNormally);
      expect(() => handler.onSpectatorLeft(1), returnsNormally);
      expect(() => handler.onRoomSnapshot(1), returnsNormally);
      expect(() => handler.onGameStarted(1), returnsNormally);
      expect(() => handler.onPlayerReady(1), returnsNormally);
      expect(() => handler.onPhaseChanged(1), returnsNormally);
      expect(() => handler.onRoundResolved(1), returnsNormally);
      expect(() => handler.onGameOver(1), returnsNormally);
      expect(() => handler.onGameReset(1), returnsNormally);
      expect(() => handler.onForcedPosition(1), returnsNormally);
    });
  });
}

Map<String, dynamic> playerJoinedPayload({String id = 'p-2', String name = 'Bob'}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'players': [playerJson(id: 'p-1'), playerJson(id: id, name: name)],
  };
}
