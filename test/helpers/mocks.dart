import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/data_source/room_socket_service.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/requests/create_room_request.dart';
import 'package:boom_board/core/data/models/requests/join_room_request.dart';
import 'package:boom_board/core/domain/repositories/room_server_repository.dart';
import 'package:boom_board/core/domain/use_cases/create_room_use_case.dart';
import 'package:boom_board/core/domain/use_cases/get_current_player_id_use_case.dart';
import 'package:boom_board/core/domain/use_cases/join_room_use_case.dart';
import 'package:boom_board/core/domain/use_cases/leave_room_use_case.dart';
import 'package:boom_board/core/utils/socket_service.dart';
import 'package:boom_board/features/simple_mode/data/data_source/room_snapshot_cache.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_handler.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_service.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/reset_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/set_position_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/start_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/throw_bomb_request.dart';
import 'package:boom_board/features/simple_mode/domain/repositories/simple_mode_server_repository.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/consume_room_snapshot_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/request_snapshot_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/reset_game_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/set_position_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/start_game_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/throw_bomb_use_case.dart';
import 'package:mocktail/mocktail.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// None of the collaborators below are abstract except the two repositories,
// but mocktail can implement concrete classes, so no interface extraction is
// needed to fake SocketService, the socket services, or the use cases.

class MockSocketService extends Mock implements SocketService {}

class MockSocket extends Mock implements io.Socket {}

/// A socket that really registers handlers, so tests can drive the full
/// "server pushes an event -> handler parses it -> eventBus fires" path
/// instead of asserting that `on` was called with something.
///
/// `on`/`off` mirror socket_io_common's EventEmitter exactly: `on` appends to a
/// per-event list, and `off` removes the *first* identity match only. That
/// second detail is what makes a double `init()` survive a single `dispose()`,
/// so the fake has to reproduce it rather than smooth it over.
class FakeSocket extends Mock implements io.Socket {
  final Map<String, List<dynamic Function(dynamic)>> handlers = {};

  @override
  Function() on(String event, dynamic Function(dynamic) handler) {
    handlers.putIfAbsent(event, () => []).add(handler);
    return () => off(event, handler);
  }

  @override
  void off(String event, [dynamic Function(dynamic)? handler]) {
    if (handler == null) {
      handlers.remove(event);
      return;
    }
    handlers[event]?.remove(handler);
    if (handlers[event]?.isEmpty == true) handlers.remove(event);
  }

  /// Simulates the server pushing [event] down to this client.
  void serverEmit(String event, dynamic data) {
    for (final handler in List.of(handlers[event] ?? const [])) {
      handler(data);
    }
  }

  /// How many handlers are currently bound to [event].
  int handlerCount(String event) => handlers[event]?.length ?? 0;
}

class MockRoomSocketService extends Mock implements RoomSocketService {}

class MockRoomServerRepository extends Mock implements RoomServerRepository {}

class MockSimpleModeSocketService extends Mock implements SimpleModeSocketService {}

class MockSimpleModeServerRepository extends Mock implements SimpleModeServerRepository {}

class MockSimpleModeSocketHandler extends Mock implements SimpleModeSocketHandler {}

class MockIdentityStore extends Mock implements IdentityStore {}

class MockRoomSnapshotCache extends Mock implements RoomSnapshotCache {}

class MockConsumeRoomSnapshotUseCase extends Mock implements ConsumeRoomSnapshotUseCase {}

class MockGetCurrentPlayerIdUseCase extends Mock implements GetCurrentPlayerIdUseCase {}

class MockJoinRoomUseCase extends Mock implements JoinRoomUseCase {}

class MockLeaveRoomUseCase extends Mock implements LeaveRoomUseCase {}

/// An [IdentityStore] mock with every method already stubbed for the common
/// "nothing stored yet" case, so tests only stub what they actually assert on.
MockIdentityStore emptyIdentityStore() {
  final store = MockIdentityStore();
  when(() => store.credentials).thenReturn(null);
  when(() => store.playerId).thenReturn(null);
  when(() => store.roomCode).thenReturn(null);
  when(() => store.credentialsFor(any())).thenReturn(null);
  when(
    () => store.save(
      playerId: any(named: 'playerId'),
      secret: any(named: 'secret'),
      roomCode: any(named: 'roomCode'),
      playerName: any(named: 'playerName'),
    ),
  ).thenAnswer((_) async {});
  when(() => store.clear()).thenAnswer((_) async {});
  return store;
}

class MockStartGameUseCase extends Mock implements StartGameUseCase {}

class MockSetPositionUseCase extends Mock implements SetPositionUseCase {}

class MockThrowBombUseCase extends Mock implements ThrowBombUseCase {}

class MockRequestSnapshotUseCase extends Mock implements RequestSnapshotUseCase {}

class MockResetGameUseCase extends Mock implements ResetGameUseCase {}

/// mocktail's `any()` needs a registered fallback for every non-primitive
/// argument type. Call once from `setUpAll`.
void registerTestFallbackValues() {
  // Request objects, for stubbing the socket services and repositories.
  registerFallbackValue(CreateRoomRequest(playerName: ''));
  registerFallbackValue(JoinRoomRequest(playerName: '', roomCode: ''));
  registerFallbackValue(StartGameRequest(roomCode: ''));
  registerFallbackValue(SetPositionRequest(roomCode: '', x: 0, y: 0));
  registerFallbackValue(ThrowBombRequest(roomCode: '', x: 0, y: 0));
  registerFallbackValue(ResetGameRequest(roomCode: ''));

  // Use-case params, for stubbing the use cases the controllers resolve.
  registerFallbackValue(CreateRoomParams(playerName: ''));
  registerFallbackValue(JoinRoomParams(playerName: '', roomCode: ''));
  registerFallbackValue(LeaveRoomParams(gameMode: GameMode.simple));
  registerFallbackValue(StartGameParams(roomCode: ''));
  registerFallbackValue(SetPositionParams(roomCode: '', x: 0, y: 0));
  registerFallbackValue(ThrowBombParams(roomCode: '', x: 0, y: 0));
  registerFallbackValue(ResetGameParams(roomCode: ''));
}
