import 'package:boom_board/core/domain/use_cases/create_room_use_case.dart';
import 'package:boom_board/core/domain/use_cases/join_room_use_case.dart';
import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/core/presentation/controllers/home_controller.dart';
import 'package:boom_board/core/presentation/models/enums/home_panel_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/controller_harness.dart';
import '../../../helpers/mocks.dart';
import '../../../helpers/test_di.dart';

class MockCreateRoomUseCase extends Mock implements CreateRoomUseCase {}

class MockJoinRoomUseCase extends Mock implements JoinRoomUseCase {}

void main() {
  // onInit is never called here: it kicks off an unbounded animation loop and
  // connects the socket. Every method under test is reachable directly.
  TestWidgetsFlutterBinding.ensureInitialized();

  late HomeController controller;
  late MockCreateRoomUseCase createRoom;
  late MockJoinRoomUseCase joinRoom;

  setUpAll(registerTestFallbackValues);

  setUp(() async {
    await setUpTestDependencies();
    createRoom = MockCreateRoomUseCase();
    joinRoom = MockJoinRoomUseCase();
    GetIt.I.registerSingleton<CreateRoomUseCase>(createRoom);
    GetIt.I.registerSingleton<JoinRoomUseCase>(joinRoom);
    controller = HomeController();
  });

  tearDown(tearDownTestDependencies);

  BBServerException serverError(String errorType) {
    return BBServerException(code: 400, errorType: errorType);
  }

  group('panel navigation', () {
    test('onHostPressed opens the host panel and clears any error', () {
      controller.panelError = 'stale';

      controller.onHostPressed();

      expect(controller.panelType, HomePanelType.host);
      expect(controller.panelError, isNull);
    });

    test('onJoinPressed opens the join panel and clears any error', () {
      controller.panelError = 'stale';

      controller.onJoinPressed();

      expect(controller.panelType, HomePanelType.join);
      expect(controller.panelError, isNull);
    });

    test('onCancelPressed returns to start and clears both text fields', () {
      controller.panelType = HomePanelType.join;
      controller.panelError = 'stale';
      controller.playerNameTextFieldCtl.text = 'Alice';
      controller.roomCodeTextFieldCtl.text = 'ABCD';

      controller.onCancelPressed();

      expect(controller.panelType, HomePanelType.start);
      expect(controller.panelError, isNull);
      expect(controller.playerNameTextFieldCtl.text, isEmpty);
      expect(controller.roomCodeTextFieldCtl.text, isEmpty);
    });
  });

  group('onCreatePressed validation', () {
    test('rejects an empty player name without calling the server', () async {
      controller.playerNameTextFieldCtl.text = '';

      controller.onCreatePressed();
      await pumpController();

      expect(controller.panelError, 'Player name required');
      verifyNever(() => createRoom.call(any()));
    });

    test('rejects a whitespace-only player name', () async {
      controller.playerNameTextFieldCtl.text = '   ';

      controller.onCreatePressed();
      await pumpController();

      expect(controller.panelError, 'Player name required');
      verifyNever(() => createRoom.call(any()));
    });

    test('trims the player name before sending it', () async {
      controller.playerNameTextFieldCtl.text = '  Alice  ';
      when(() => createRoom.call(any())).thenThrow(serverError('IGNORED'));

      controller.onCreatePressed();
      await pumpController();

      final captured = verify(() => createRoom.call(captureAny())).captured.single;

      expect((captured as CreateRoomParams).playerName, 'Alice');
    });
  });

  group('onCreatePressed error mapping', () {
    test('maps INVALID_PLAYER_NAME to a length hint', () async {
      controller.playerNameTextFieldCtl.text = 'Alice';
      when(() => createRoom.call(any())).thenThrow(serverError('INVALID_PLAYER_NAME'));

      controller.onCreatePressed();
      await pumpController();

      expect(controller.panelError, 'Player name must be 1 - 20 characters long');
    });

    test('falls back to a generic message for an unmapped server error', () async {
      controller.playerNameTextFieldCtl.text = 'Alice';
      when(() => createRoom.call(any())).thenThrow(serverError('SOMETHING_NEW'));

      controller.onCreatePressed();
      await pumpController();

      expect(controller.panelError, 'Unknown server error occurred');
    });

    test('falls back to a generic message for a non-server error', () async {
      controller.playerNameTextFieldCtl.text = 'Alice';
      when(() => createRoom.call(any())).thenThrow(StateError('socket died'));

      controller.onCreatePressed();
      await pumpController();

      expect(controller.panelError, 'Unknown error occurred');
    });
  });

  group('onJoinConfirmPressed validation', () {
    test('rejects an empty player name without calling the server', () async {
      controller.playerNameTextFieldCtl.text = '';
      controller.roomCodeTextFieldCtl.text = 'ABCD';

      controller.onJoinConfirmPressed();
      await pumpController();

      expect(controller.panelError, 'Player name required');
      verifyNever(() => joinRoom.call(any()));
    });

    test('rejects a room code that is not four characters', () async {
      controller.playerNameTextFieldCtl.text = 'Bob';

      for (final code in ['', 'AB', 'ABCDE']) {
        controller.roomCodeTextFieldCtl.text = code;

        controller.onJoinConfirmPressed();
        await pumpController();

        expect(controller.panelError, 'Invalid room code', reason: 'for "$code"');
      }

      verifyNever(() => joinRoom.call(any()));
    });

    test('accepts a four-character room code', () async {
      controller.playerNameTextFieldCtl.text = 'Bob';
      controller.roomCodeTextFieldCtl.text = 'ABCD';
      when(() => joinRoom.call(any())).thenThrow(serverError('ROOM_NOT_FOUND'));

      controller.onJoinConfirmPressed();
      await pumpController();

      verify(() => joinRoom.call(any())).called(1);
    });

    test('validates the trimmed room code but sends the untrimmed text', () async {
      // The length check runs on `.trim()`, while the request is built from the
      // raw controller text. ' ABCD ' therefore passes validation as 4
      // characters and is sent as 6, which the server can only answer with
      // ROOM_NOT_FOUND. onCreatePressed trims before sending; join does not.
      controller.playerNameTextFieldCtl.text = 'Bob';
      controller.roomCodeTextFieldCtl.text = ' ABCD ';
      when(() => joinRoom.call(any())).thenThrow(serverError('ROOM_NOT_FOUND'));

      controller.onJoinConfirmPressed();
      await pumpController();

      final captured = verify(() => joinRoom.call(captureAny())).captured.single;

      expect((captured as JoinRoomParams).roomCode, ' ABCD ');
    });

    test('sends the player name untrimmed as well', () async {
      // Same asymmetry on the name: validated with .trim().isEmpty, sent raw.
      controller.playerNameTextFieldCtl.text = '  Bob  ';
      controller.roomCodeTextFieldCtl.text = 'ABCD';
      when(() => joinRoom.call(any())).thenThrow(serverError('ROOM_NOT_FOUND'));

      controller.onJoinConfirmPressed();
      await pumpController();

      final captured = verify(() => joinRoom.call(captureAny())).captured.single;

      expect((captured as JoinRoomParams).playerName, '  Bob  ');
    });
  });

  group('onJoinConfirmPressed error mapping', () {
    Future<String?> errorFor(String errorType) async {
      controller.playerNameTextFieldCtl.text = 'Bob';
      controller.roomCodeTextFieldCtl.text = 'ABCD';
      when(() => joinRoom.call(any())).thenThrow(serverError(errorType));

      controller.onJoinConfirmPressed();
      await pumpController();

      return controller.panelError;
    }

    test('maps ROOM_NOT_FOUND, quoting the code', () async {
      expect(await errorFor('ROOM_NOT_FOUND'), 'Room ABCD not found');
    });

    test('maps ROOM_IS_FULL', () async {
      expect(await errorFor('ROOM_IS_FULL'), 'Room is full');
    });

    test('maps ROOM_IS_FULL_OF_SPECTATORS', () async {
      expect(await errorFor('ROOM_IS_FULL_OF_SPECTATORS'), 'Room has too many spectators');
    });

    test('maps SECRET_MISMATCH', () async {
      // The stale slot has already been cleared by the use case, so the advice
      // to retry is real: the next attempt enters as a brand-new player.
      expect(await errorFor('SECRET_MISMATCH'), 'Could not verify your old seat. Try again.');
    });

    test('maps INVALID_PLAYER_NAME', () async {
      expect(await errorFor('INVALID_PLAYER_NAME'), 'Player name must be 1 - 20 characters long');
    });

    test('shows nothing at all for an unmapped server error', () async {
      // Characterization of a gap, not a spec. The join branch has no trailing
      // `else`, unlike onCreatePressed which falls back to "Unknown server
      // error occurred". An unmapped errorType therefore leaves panelError
      // null: the player taps Join, the server refuses, and the panel reports
      // nothing -- a dead end with no feedback. Adding the same else branch
      // create already has would close it.
      expect(await errorFor('SOMETHING_NEW'), isNull);
    });

    test('does map a non-server error to a generic message', () async {
      // The outer catch does have a fallback; only the BBServerException
      // branch is missing one.
      controller.playerNameTextFieldCtl.text = 'Bob';
      controller.roomCodeTextFieldCtl.text = 'ABCD';
      when(() => joinRoom.call(any())).thenThrow(StateError('socket died'));

      controller.onJoinConfirmPressed();
      await pumpController();

      expect(controller.panelError, 'Unknown error occurred');
    });
  });

  group('moveLocalPlayerInward', () {
    // _generateNewPositions is private and only runs from onInit, which also
    // starts the animation loop -- so only the inward walk is reachable here.
    // Both are random, hence the repeated sampling.
    test('walks the local player to 20-30% of the width, clear of the menu', () {
      for (var i = 0; i < 100; i++) {
        controller.moveLocalPlayerInward();

        expect(controller.localX, inInclusiveRange(0.20, 0.30));
      }
    });

    test('nudges Y by no more than 5% either way', () {
      for (var i = 0; i < 100; i++) {
        controller.localY = 0.5;

        controller.moveLocalPlayerInward();

        expect(controller.localY, inInclusiveRange(0.45, 0.55));
      }
    });
  });
}
