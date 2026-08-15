import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/set_position_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/start_game_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/throw_bomb_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/controller_harness.dart';
import '../../../../helpers/mocks.dart';

void main() {
  // _scrollToBottom reaches for WidgetsBinding.instance.
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimpleModeControllerHarness harness;

  setUpAll(registerTestFallbackValues);

  Future<void> buildRoom({
    List<String> otherPlayers = const ['p-2'],
    String? hostId,
    bool localPositioned = false,
    bool localThrewBomb = false,
    int? localX,
    int? localY,
  }) async {
    harness = SimpleModeControllerHarness();
    await harness.setUp(
      hostId: hostId,
      players: [
        player(
          id: localId,
          hasPositioned: localPositioned,
          hasThrowBomb: localThrewBomb,
          x: localX,
          y: localY,
        ),
        ...otherPlayers.map((id) => player(id: id)),
      ],
    );
  }

  tearDown(() => harness.tearDown());

  group('setPosition bounds', () {
    // The board is 8x8 with indices 0..7: simple_mode_screen.dart builds it
    // with itemCount 64, `x = index % 8`, `y = index ~/ 8`. This guard is the
    // only validation between a caller and the server.
    for (final coord in [
      (0, 0),
      (7, 7),
      (0, 7),
      (7, 0),
      (3, 4),
    ]) {
      test('accepts the on-board tile (${coord.$1}, ${coord.$2})', () async {
        await buildRoom();

        harness.controller.setPosition(coord.$1, coord.$2);
        await pumpController();

        verify(() => harness.setPosition.call(any())).called(1);
      });
    }

    for (final coord in [
      (8, 0),
      (0, 8),
      (8, 8),
      (-1, 0),
      (0, -1),
      (9, 9),
    ]) {
      test('rejects the off-board tile (${coord.$1}, ${coord.$2})', () async {
        await buildRoom();

        harness.controller.setPosition(coord.$1, coord.$2);
        await pumpController();

        verifyNever(() => harness.setPosition.call(any()));
        expect(harness.local.hasPositioned, isFalse);
      });
    }
  });

  group('setPosition', () {
    test('sends the room code and coordinates', () async {
      await buildRoom();

      harness.controller.setPosition(3, 5);
      await pumpController();

      final captured = verify(() => harness.setPosition.call(captureAny())).captured.single;

      expect((captured as SetPositionParams).roomCode, 'ABCD');
      expect(captured.x, 3);
      expect(captured.y, 5);
    });

    test('optimistically marks the local player positioned', () async {
      await buildRoom();

      harness.controller.setPosition(3, 5);
      await pumpController();

      expect(harness.local.hasPositioned, isTrue);
      expect(harness.local.x, 3);
      expect(harness.local.y, 5);
    });

    test('clears the hover highlight immediately', () async {
      await buildRoom();
      harness.controller.setHoveredTile(null);

      harness.controller.setPosition(3, 5);
      await pumpController();

      expect(harness.controller.hoveredTile, isNull);
    });

    test('does nothing when the player has already positioned', () async {
      await buildRoom(localPositioned: true, localX: 1, localY: 1);

      harness.controller.setPosition(6, 6);
      await pumpController();

      verifyNever(() => harness.setPosition.call(any()));
      expect(harness.local.x, 1);
      expect(harness.local.y, 1);
    });

    test('rolls the player back when the server call fails', () async {
      await buildRoom();
      when(() => harness.setPosition.call(any())).thenThrow(StateError('offline'));

      harness.controller.setPosition(3, 5);
      await pumpController();

      expect(harness.local.hasPositioned, isFalse);
      expect(harness.local.x, isNull);
      expect(harness.local.y, isNull);
    });

    test('swallows the server error rather than rethrowing', () async {
      await buildRoom();
      when(() => harness.setPosition.call(any())).thenThrow(StateError('offline'));

      expect(() => harness.controller.setPosition(3, 5), returnsNormally);
      await pumpController();
    });

    test('queues a hide animation for the local player on success', () async {
      await buildRoom();

      harness.controller.setPosition(3, 5);
      await pumpController();

      expect(harness.controller.activeHideAnimations, hasLength(1));
      expect(harness.controller.activeHideAnimations.single.playerId, localId);
      expect(harness.controller.activeHideAnimations.single.isLocal, isTrue);
      expect(harness.controller.activeHideAnimations.single.targetX, 3);
      expect(harness.controller.activeHideAnimations.single.targetY, 5);
    });

    test('queues no hide animation when the server call fails', () async {
      await buildRoom();
      when(() => harness.setPosition.call(any())).thenThrow(StateError('offline'));

      harness.controller.setPosition(3, 5);
      await pumpController();

      expect(harness.controller.activeHideAnimations, isEmpty);
    });
  });

  group('throwBomb', () {
    test('sends the room code and coordinates', () async {
      await buildRoom();

      harness.controller.throwBomb(2, 6);
      await pumpController();

      final captured = verify(() => harness.throwBomb.call(captureAny())).captured.single;

      expect((captured as ThrowBombParams).roomCode, 'ABCD');
      expect(captured.x, 2);
      expect(captured.y, 6);
    });

    test('locks the target and records the throw order on success', () async {
      await buildRoom();
      when(() => harness.throwBomb.call(any())).thenAnswer((_) async => 2);

      harness.controller.throwBomb(2, 6);
      await pumpController();

      expect(harness.controller.lockedBombTarget?.x, 2);
      expect(harness.controller.lockedBombTarget?.y, 6);
      expect(harness.local.hasThrowBomb, isTrue);
      expect(harness.local.throwOrder, 2);
    });

    test('accepts a null throw order', () async {
      await buildRoom();
      when(() => harness.throwBomb.call(any())).thenAnswer((_) async => null);

      harness.controller.throwBomb(2, 6);
      await pumpController();

      expect(harness.local.hasThrowBomb, isTrue);
      expect(harness.local.throwOrder, isNull);
    });

    test('does nothing when the player has already thrown', () async {
      await buildRoom(localThrewBomb: true);

      harness.controller.throwBomb(2, 6);
      await pumpController();

      verifyNever(() => harness.throwBomb.call(any()));
    });

    test('leaves the target unlocked when the server call fails', () async {
      await buildRoom();
      when(() => harness.throwBomb.call(any())).thenThrow(StateError('offline'));

      harness.controller.throwBomb(2, 6);
      await pumpController();

      expect(harness.controller.lockedBombTarget, isNull);
      expect(harness.local.hasThrowBomb, isFalse);
    });

  });

  group('throwBomb bounds', () {
    // simple_mode_screen.dart feeds the same (x, y) to setPosition and
    // throwBomb from one tap handler, so the two validate identically.
    for (final coord in [
      (0, 0),
      (7, 7),
      (0, 7),
      (7, 0),
      (3, 4),
    ]) {
      test('accepts the on-board tile (${coord.$1}, ${coord.$2})', () async {
        await buildRoom();

        harness.controller.throwBomb(coord.$1, coord.$2);
        await pumpController();

        verify(() => harness.throwBomb.call(any())).called(1);
      });
    }

    for (final coord in [
      (8, 0),
      (0, 8),
      (8, 8),
      (-1, 0),
      (0, -1),
      (99, -4),
    ]) {
      test('rejects the off-board tile (${coord.$1}, ${coord.$2})', () async {
        await buildRoom();

        harness.controller.throwBomb(coord.$1, coord.$2);
        await pumpController();

        verifyNever(() => harness.throwBomb.call(any()));
        expect(harness.controller.lockedBombTarget, isNull);
        expect(harness.local.hasThrowBomb, isFalse);
      });
    }
  });

  group('startGame', () {
    test('starts when the local player is host and the room has two players', () async {
      await buildRoom(hostId: localId);

      harness.controller.startGame();
      await pumpController();

      final captured = verify(() => harness.startGame.call(captureAny())).captured.single;

      expect((captured as StartGameParams).roomCode, 'ABCD');
    });

    test('does nothing when the local player is not host', () async {
      await buildRoom(hostId: 'p-2');

      harness.controller.startGame();
      await pumpController();

      verifyNever(() => harness.startGame.call(any()));
    });

    test('does nothing with only one player in the room', () async {
      await buildRoom(otherPlayers: const []);

      harness.controller.startGame();
      await pumpController();

      verifyNever(() => harness.startGame.call(any()));
    });

    test('checks the player count before the host check', () async {
      // A lone non-host cannot exist in practice, but the ordering means the
      // count guard short-circuits first either way.
      await buildRoom(otherPlayers: const [], hostId: 'p-2');

      harness.controller.startGame();
      await pumpController();

      verifyNever(() => harness.startGame.call(any()));
    });

    test('swallows a server error', () async {
      await buildRoom();
      when(() => harness.startGame.call(any())).thenThrow(StateError('offline'));

      expect(harness.controller.startGame, returnsNormally);
      await pumpController();
    });
  });

  group('leaveRoom and backToLobby', () {
    test('leaveRoom calls the use case with the simple game mode', () async {
      await buildRoom();

      harness.controller.leaveRoom();
      await pumpController();

      verify(() => harness.leaveRoom.call(any())).called(1);
    });

    test('backToLobby resets the game on the server', () async {
      await buildRoom();

      harness.controller.backToLobby();
      await pumpController();

      verify(() => harness.resetGame.call(any())).called(1);
    });

    test('both swallow server errors', () async {
      await buildRoom();
      when(() => harness.leaveRoom.call(any())).thenThrow(StateError('offline'));
      when(() => harness.resetGame.call(any())).thenThrow(StateError('offline'));

      expect(harness.controller.leaveRoom, returnsNormally);
      expect(harness.controller.backToLobby, returnsNormally);
      await pumpController();
    });
  });

  group('derived state', () {
    test('isHost is true when the host id matches the local socket id', () async {
      await buildRoom(hostId: localId);

      expect(harness.controller.isHost, isTrue);
    });

    test('isHost is false for a non-host', () async {
      await buildRoom(hostId: 'p-2');

      expect(harness.controller.isHost, isFalse);
    });

    test('isHost is false when the socket has no id yet', () async {
      await buildRoom(hostId: localId);
      when(() => harness.getCurrentPlayerId.call()).thenReturn(null);

      // localPlayerId falls back to '', which matches no real host id.
      expect(harness.controller.isHost, isFalse);
      expect(harness.controller.localPlayer, isNull);
    });

    test('localPlayer is null when the local id is not in the room', () async {
      await buildRoom();
      harness.controller.playerList = [player(id: 'p-2')];

      expect(harness.controller.localPlayer, isNull);
    });

    test('getPhaseText reflects the phase', () async {
      await buildRoom();

      harness.controller.currentState = GameState.position;
      expect(harness.controller.getPhaseText(), 'Phase:Hide');

      harness.controller.currentState = GameState.attack;
      expect(harness.controller.getPhaseText(), 'Phase:Attack');

      for (final state in [GameState.lobby, GameState.process, GameState.end]) {
        harness.controller.currentState = state;
        expect(harness.controller.getPhaseText(), '');
      }
    });

    test('toggleEndgameOverlay flips the flag', () async {
      await buildRoom();

      expect(harness.controller.showEndgameOverlay, isTrue);
      harness.controller.toggleEndgameOverlay();
      expect(harness.controller.showEndgameOverlay, isFalse);
      harness.controller.toggleEndgameOverlay();
      expect(harness.controller.showEndgameOverlay, isTrue);
    });
  });
}
