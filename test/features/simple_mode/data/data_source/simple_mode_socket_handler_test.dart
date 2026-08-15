import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_handler.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/log_action_type.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/forced_position_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_over_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_reset_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_started_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/phase_changed_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_dropped_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_joined_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_left_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_ready_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/round_resolved_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/mocks.dart';
import '../../../../helpers/test_di.dart';

/// The ten events `init()` binds, in the order the handler registers them.
const boundEvents = <String>[
  'playerJoined',
  'playerLeft',
  'playerDropped',
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
  late SimpleModeSocketHandler handler;

  setUp(() async {
    await setUpTestDependencies();
    socket = FakeSocket();
    socketService = MockSocketService();
    when(() => socketService.socket).thenReturn(socket);
    handler = SimpleModeSocketHandler(socketService: socketService);
  });

  tearDown(tearDownTestDependencies);

  /// Collects everything of type [T] the handler puts on the bus.
  List<T> listenFor<T>() {
    final received = <T>[];
    eventBus.on<T>().listen(received.add);
    return received;
  }

  group('init / dispose', () {
    test('binds a handler for all ten server events', () {
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

  group('onPlayerDropped', () {
    test('maps players, new host and the new log entries', () async {
      final received = listenFor<PlayerDroppedEvent>();

      handler.onPlayerDropped(
        socketEnvelope(<String, dynamic>{
          'droppedPlayerId': 'p-1',
          'newHostId': 'p-2',
          'players': [playerJson(id: 'p-2', name: 'Bob')],
          'newLogs': [actionLogJson(id: 'log-1', type: 'PLAYER_DISCONNECTED')],
        }),
      );
      await pumpEventBus();

      expect(received.single.droppedPlayerId, 'p-1');
      expect(received.single.newHostId, 'p-2');
      expect(received.single.newLogs.single.type, LogActionType.playerDisconnected);
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
      expect(() => handler.onPlayerDropped(1), returnsNormally);
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
