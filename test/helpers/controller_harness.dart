import 'package:boom_board/core/domain/use_cases/get_current_player_id_use_case.dart';
import 'package:boom_board/core/domain/use_cases/leave_room_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/reset_game_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/set_position_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/start_game_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/throw_bomb_use_case.dart';
import 'package:boom_board/features/simple_mode/presentation/controllers/simple_mode_controller.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';
import 'test_di.dart';

/// The id the local player has in every controller test.
const localId = 'p-local';

/// Wires up a [SimpleModeController] against mocked use cases.
///
/// `onInit()` is deliberately never called: it reads `Get.arguments` and calls
/// `Get.offAllNamed(home)` when they are the wrong type, and GetX navigation
/// without a `GetMaterialApp` in the tree silently no-ops rather than throwing,
/// so a test that went through onInit would pass vacuously. Room state is set
/// directly and [SimpleModeControllerHarness.subscribe] binds the listeners.
class SimpleModeControllerHarness {
  late final SimpleModeController controller;
  late final MockGetCurrentPlayerIdUseCase getCurrentPlayerId;
  late final MockStartGameUseCase startGame;
  late final MockSetPositionUseCase setPosition;
  late final MockThrowBombUseCase throwBomb;
  late final MockResetGameUseCase resetGame;
  late final MockLeaveRoomUseCase leaveRoom;

  /// Builds the controller with [players] already in the room.
  ///
  /// [hostId] defaults to [localId], so the local player is host unless a test
  /// says otherwise.
  Future<void> setUp({
    required List<SimpleModePlayerEntity> players,
    String? hostId,
    String roomCode = 'ABCD',
  }) async {
    await setUpTestDependencies();

    getCurrentPlayerId = MockGetCurrentPlayerIdUseCase();
    startGame = MockStartGameUseCase();
    setPosition = MockSetPositionUseCase();
    throwBomb = MockThrowBombUseCase();
    resetGame = MockResetGameUseCase();
    leaveRoom = MockLeaveRoomUseCase();

    when(() => getCurrentPlayerId.call()).thenReturn(localId);
    when(() => startGame.call(any())).thenAnswer((_) async {});
    when(() => setPosition.call(any())).thenAnswer((_) async {});
    when(() => throwBomb.call(any())).thenAnswer((_) async => 1);
    when(() => resetGame.call(any())).thenAnswer((_) async {});
    when(() => leaveRoom.call(any())).thenAnswer((_) async {});

    GetIt.I.registerSingleton<GetCurrentPlayerIdUseCase>(getCurrentPlayerId);
    GetIt.I.registerSingleton<StartGameUseCase>(startGame);
    GetIt.I.registerSingleton<SetPositionUseCase>(setPosition);
    GetIt.I.registerSingleton<ThrowBombUseCase>(throwBomb);
    GetIt.I.registerSingleton<ResetGameUseCase>(resetGame);
    GetIt.I.registerSingleton<LeaveRoomUseCase>(leaveRoom);

    controller = SimpleModeController();
    controller.roomCode = roomCode;
    controller.hostId = hostId ?? localId;
    controller.playerList = players;
  }

  /// Binds the eventBus listeners, as `onInit` would.
  void subscribe() => controller.subscribeListener();

  Future<void> tearDown() async {
    controller.unsubscribeListener();
    await tearDownTestDependencies();
  }

  SimpleModePlayerEntity playerById(String id) {
    return controller.playerList.firstWhere((p) => p.id == id);
  }

  SimpleModePlayerEntity get local => playerById(localId);
}

/// Builds a player, defaulting to a live, un-positioned one.
SimpleModePlayerEntity player({
  required String id,
  String? name,
  bool isAlive = true,
  bool hasPositioned = false,
  bool hasThrowBomb = false,
  bool isDisconnected = false,
  int? x,
  int? y,
  int? throwOrder,
}) {
  return SimpleModePlayerEntity(
    id: id,
    name: name ?? id,
    isAlive: isAlive,
    hasPositioned: hasPositioned,
    hasThrowBomb: hasThrowBomb,
    isDisconnected: isDisconnected,
    x: x,
    y: y,
    throwOrder: throwOrder,
  );
}

/// Lets a fire-and-forget `void ... async` controller method run to completion.
Future<void> pumpController() => Future.delayed(Duration.zero);
