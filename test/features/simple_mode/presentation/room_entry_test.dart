import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/entities/join_room_entity.dart';
import 'package:boom_board/core/domain/entities/player_entity.dart';
import 'package:boom_board/core/domain/use_cases/get_current_player_id_use_case.dart';
import 'package:boom_board/core/domain/use_cases/join_room_use_case.dart';
import 'package:boom_board/core/domain/use_cases/leave_room_use_case.dart';
import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/consume_room_snapshot_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/request_snapshot_use_case.dart';
import 'package:boom_board/features/simple_mode/presentation/arguments/simple_mode_arguments.dart';
import 'package:boom_board/features/simple_mode/presentation/bindings/simple_mode_binding.dart';
import 'package:boom_board/features/simple_mode/presentation/controllers/simple_mode_controller.dart';
import 'package:boom_board/routes/app_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/controller_harness.dart';
import '../../../helpers/mocks.dart';
import '../../../helpers/test_di.dart';

/// Entering the room screen for real: the GetX route, its binding and
/// `SimpleModeController.onInit`, which the controller harness deliberately
/// skips.
///
/// `Get.arguments` is a single global slot that every dialog, bottom sheet and
/// snackbar overwrites while it is open, and the binding reads it a frame after
/// the push that filled it -- so an overlay landing in that gap used to leave a
/// player seated on the server with an empty room code and no listeners, for
/// the rest of the session. These tests pin the recovery.
void main() {
  late MockIdentityStore identityStore;
  late MockRequestSnapshotUseCase requestSnapshot;
  late MockLeaveRoomUseCase leaveRoom;
  late MockJoinRoomUseCase joinRoom;
  late MockConsumeRoomSnapshotUseCase consumeSnapshot;

  setUpAll(registerTestFallbackValues);

  JoinRoomEntity ackFor(String roomCode) {
    return JoinRoomEntity(
      roomCode: roomCode,
      gameMode: GameMode.simple,
      hostId: localId,
      playerList: [
        PlayerEntity(id: localId, name: 'Alice', isAlive: true, hasPositioned: false, isDisconnected: false),
      ],
      spectatorList: const [],
      playerId: localId,
      secret: 's3cret',
      isSpectator: false,
    );
  }

  setUp(() async {
    await setUpTestDependencies();

    identityStore = emptyIdentityStore();
    requestSnapshot = MockRequestSnapshotUseCase();
    leaveRoom = MockLeaveRoomUseCase();
    joinRoom = MockJoinRoomUseCase();
    consumeSnapshot = MockConsumeRoomSnapshotUseCase();
    final getCurrentPlayerId = MockGetCurrentPlayerIdUseCase();

    when(() => requestSnapshot.call()).thenAnswer((_) async {});
    when(() => leaveRoom.call(any())).thenAnswer((_) async {});
    when(() => joinRoom.call(any())).thenAnswer((_) async => ackFor('WXYZ'));
    when(() => consumeSnapshot.call()).thenReturn(null);
    when(() => getCurrentPlayerId.call()).thenReturn(localId);

    GetIt.I.registerSingleton<IdentityStore>(identityStore);
    GetIt.I.registerSingleton<RequestSnapshotUseCase>(requestSnapshot);
    GetIt.I.registerSingleton<LeaveRoomUseCase>(leaveRoom);
    GetIt.I.registerSingleton<JoinRoomUseCase>(joinRoom);
    GetIt.I.registerSingleton<ConsumeRoomSnapshotUseCase>(consumeSnapshot);
    GetIt.I.registerSingleton<GetCurrentPlayerIdUseCase>(getCurrentPlayerId);
  });

  tearDown(() async {
    Get.reset();
    await tearDownTestDependencies();
  });

  void storeCredentialsFor(String roomCode) {
    when(() => identityStore.credentials).thenReturn(
      RoomCredentials(
        playerId: localId,
        secret: 's3cret',
        roomCode: roomCode,
        playerName: 'Alice',
      ),
    );
  }

  // The real binding, but a stand-in for the screen: this is about what the
  // controller comes up holding, not about painting a board.
  Widget app() {
    return GetMaterialApp(
      initialRoute: home,
      getPages: [
        GetPage(name: home, page: () => const Scaffold(body: Text('HOME'))),
        GetPage(
          name: simpleMode,
          page: () => Scaffold(body: Text('ROOM ${Get.find<SimpleModeController>().roomCode}')),
          binding: SimpleModeBinding(),
        ),
      ],
    );
  }

  SimpleModeArguments argsFor(String roomCode) {
    return SimpleModeArguments(
      roomCode: roomCode,
      hostId: localId,
      playerList: [player(id: localId)],
    );
  }

  bool isOnRoomScreen() => find.textContaining('ROOM').evaluate().isNotEmpty;

  String roomScreenText() => (find.textContaining('ROOM').evaluate().first.widget as Text).data!;

  testWidgets('a clean entry takes the room straight from the route arguments', (tester) async {
    await tester.pumpWidget(app());

    Get.toNamed(simpleMode, arguments: argsFor('ABCD'));
    await tester.pumpAndSettle();

    expect(roomScreenText(), 'ROOM ABCD');
    expect(Get.find<SimpleModeController>().playerList, hasLength(1));
    verifyNever(() => requestSnapshot.call());
  });

  testWidgets('arguments lost to an overlay: the room is rebuilt from the credential slot',
      (tester) async {
    await tester.pumpWidget(app());
    storeCredentialsFor('WXYZ');

    // The overlay lands after the push and before the page builds, which is
    // what wipes Get.arguments.
    Get.toNamed(simpleMode, arguments: argsFor('WXYZ'));
    Get.dialog(const Text('anything at all'));
    await tester.pumpAndSettle();

    expect(Get.find<SimpleModeController>().roomCode, 'WXYZ',
        reason: 'the room code must survive the lost arguments');
    expect(isOnRoomScreen(), isTrue, reason: 'the seat is already taken, so we must not bounce home');
    verify(() => requestSnapshot.call()).called(1);
    verifyNever(() => leaveRoom.call(any()));
    // Nothing to show until the snapshot lands, so the board stays behind the
    // reconnect overlay instead of presenting an empty lobby.
    expect(Get.find<SimpleModeController>().isReconnecting, isTrue);
  });

  testWidgets('a snapshot this socket cannot be served falls back to reclaiming the seat',
      (tester) async {
    await tester.pumpWidget(app());
    storeCredentialsFor('WXYZ');
    // What the server answers a socket that holds no seat: the snapshot is
    // served off the binding made at join time, and a socket that dropped and
    // has not rejoined yet has none. The credentials are still good, so the
    // seat is reclaimable -- just the long way round.
    when(() => requestSnapshot.call())
        .thenThrow(BBServerException(code: 403, errorType: 'PLAYER_IS_NOT_IN_A_ROOM'));

    Get.toNamed(simpleMode, arguments: argsFor('WXYZ'));
    Get.dialog(const Text('anything at all'));
    await tester.pumpAndSettle();

    final captured = verify(() => joinRoom.call(captureAny())).captured.single as JoinRoomParams;
    expect(captured.roomCode, 'WXYZ', reason: 'the rejoin aims at the room the credentials name');

    final controller = Get.find<SimpleModeController>();
    expect(controller.connectionState, RoomConnectionState.connected,
        reason: 'the fallback got the seat back, so there is nothing to overlay');
    expect(controller.roomCode, 'WXYZ');
  });

  testWidgets('a rejoin that fails too leaves a way out rather than a spinner', (tester) async {
    await tester.pumpWidget(app());
    storeCredentialsFor('WXYZ');
    when(() => requestSnapshot.call()).thenThrow(Exception('offline'));
    when(() => joinRoom.call(any())).thenThrow(Exception('offline'));

    Get.toNamed(simpleMode, arguments: argsFor('WXYZ'));
    Get.dialog(const Text('anything at all'));
    await tester.pumpAndSettle();

    final controller = Get.find<SimpleModeController>();
    expect(controller.connectionState, RoomConnectionState.reconnectFailed);
    expect(controller.connectionError, isNotNull);
  });

  testWidgets('arguments and credentials both gone: the seat is released before going home',
      (tester) async {
    await tester.pumpWidget(app());

    Get.toNamed(simpleMode, arguments: argsFor('ABCD'));
    Get.dialog(const Text('anything at all'));
    await tester.pumpAndSettle();

    verify(() => leaveRoom.call(any())).called(1);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('the abandoned controller does not poison the next join', (tester) async {
    await tester.pumpWidget(app());

    // Entry 1: nothing to recover from, so it gives up and goes home.
    Get.toNamed(simpleMode, arguments: argsFor('ABCD'));
    Get.dialog(const Text('anything at all'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);

    // Entry 2: an ordinary join. `Get.put` hands back an already-registered
    // instance rather than the fresh one, so if entry 1's controller were still
    // registered this screen would show its empty room code forever.
    Get.toNamed(simpleMode, arguments: argsFor('QRST'));
    await tester.pumpAndSettle();

    expect(roomScreenText(), 'ROOM QRST');
  });
}
