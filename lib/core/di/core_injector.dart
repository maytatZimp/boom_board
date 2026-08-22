import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/data_source/room_socket_service.dart';
import 'package:boom_board/core/data/repositories/room_server_repository_impl.dart';
import 'package:boom_board/core/domain/repositories/room_server_repository.dart';
import 'package:boom_board/core/domain/use_cases/connect_to_server_use_case.dart';
import 'package:boom_board/core/domain/use_cases/create_room_use_case.dart';
import 'package:boom_board/core/domain/use_cases/get_current_player_id_use_case.dart';
import 'package:boom_board/core/domain/use_cases/join_room_use_case.dart';
import 'package:boom_board/core/domain/use_cases/leave_room_use_case.dart';
import 'package:boom_board/core/utils/logger.dart';
import 'package:boom_board/core/utils/socket_service.dart';
import 'package:boom_board/features/simple_mode/data/data_source/room_snapshot_cache.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_handler.dart';
import 'package:boom_board/features/simple_mode/di/simple_mode_injection.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

Future<void> registerDependencies() async {
  GetIt.I.registerSingleton<Logger>(initLogger());
  GetIt.I.registerSingleton<SocketService>(SocketService());

  // Load the persisted credential slot before anything can ask who we are --
  // GetCurrentPlayerIdUseCase reads it synchronously.
  final identityStore = IdentityStore();
  await identityStore.load();
  GetIt.I.registerSingleton<IdentityStore>(identityStore);

  registerCoreSingletonDependencies();

  registerSimpleModeSingletonDependencies();
  registerSimpleModeFactoryDependencies();

  registerCoreFactoryDependencies();
}

void registerCoreSingletonDependencies() {
  GetIt.I.registerSingleton<RoomSocketService>(
    RoomSocketService(
      socketService: GetIt.I<SocketService>(),
    ),
  );

  GetIt.I.registerSingleton<RoomServerRepository>(
    RoomServerRepositoryImpl(
      socketService: GetIt.I<RoomSocketService>(),
    ),
  );
}

void registerCoreFactoryDependencies() {
  GetIt.I.registerFactory(
    () => ConnectToServerUseCase(
      socketService: GetIt.I<SocketService>(),
    ),
  );

  GetIt.I.registerFactory(
    () => CreateRoomUseCase(
      roomServerRepository: GetIt.I<RoomServerRepository>(),
      simpleModeSocketHandler: GetIt.I<SimpleModeSocketHandler>(),
      identityStore: GetIt.I<IdentityStore>(),
    ),
  );

  GetIt.I.registerFactory(
    () => JoinRoomUseCase(
      roomServerRepository: GetIt.I<RoomServerRepository>(),
      simpleModeSocketHandler: GetIt.I<SimpleModeSocketHandler>(),
      identityStore: GetIt.I<IdentityStore>(),
    ),
  );

  GetIt.I.registerFactory(
    () => LeaveRoomUseCase(
      roomServerRepository: GetIt.I<RoomServerRepository>(),
      simpleModeSocketHandler: GetIt.I<SimpleModeSocketHandler>(),
      roomSnapshotCache: GetIt.I<RoomSnapshotCache>(),
      identityStore: GetIt.I<IdentityStore>(),
    ),
  );

  GetIt.I.registerFactory(
    () => GetCurrentPlayerIdUseCase(
      identityStore: GetIt.I<IdentityStore>(),
    ),
  );
}
