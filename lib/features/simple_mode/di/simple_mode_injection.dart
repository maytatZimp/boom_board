import 'package:boom_board/core/utils/socket_service.dart';
import 'package:boom_board/features/simple_mode/data/data_source/room_snapshot_cache.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_handler.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_service.dart';
import 'package:boom_board/features/simple_mode/data/repositories/simple_mode_server_repository_impl.dart';
import 'package:boom_board/features/simple_mode/domain/repositories/simple_mode_server_repository.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/consume_room_snapshot_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/request_snapshot_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/reset_game_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/set_position_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/start_game_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/throw_bomb_use_case.dart';
import 'package:get_it/get_it.dart';

void registerSimpleModeSingletonDependencies() {
  GetIt.I.registerSingleton<SimpleModeSocketService>(
    SimpleModeSocketService(
      socketService: GetIt.I<SocketService>(),
    ),
  );
  GetIt.I.registerSingleton<SimpleModeServerRepository>(
    SimpleModeServerRepositoryImpl(
      socketService: GetIt.I<SimpleModeSocketService>(),
    ),
  );
  GetIt.I.registerSingleton<RoomSnapshotCache>(RoomSnapshotCache());
  GetIt.I.registerSingleton<SimpleModeSocketHandler>(
    SimpleModeSocketHandler(
      socketService: GetIt.I<SocketService>(),
      roomSnapshotCache: GetIt.I<RoomSnapshotCache>(),
    ),
  );
}

void registerSimpleModeFactoryDependencies() {
  GetIt.I.registerFactory<ResetGameUseCase>(
    () => ResetGameUseCase(
      simpleModeServerRepository: GetIt.I<SimpleModeServerRepository>(),
    ),
  );

  GetIt.I.registerFactory<RequestSnapshotUseCase>(
    () => RequestSnapshotUseCase(
      simpleModeServerRepository: GetIt.I<SimpleModeServerRepository>(),
    ),
  );

  GetIt.I.registerFactory<SetPositionUseCase>(
    () => SetPositionUseCase(
      simpleModeServerRepository: GetIt.I<SimpleModeServerRepository>(),
    ),
  );

  GetIt.I.registerFactory<StartGameUseCase>(
    () => StartGameUseCase(
      simpleModeServerRepository: GetIt.I<SimpleModeServerRepository>(),
    ),
  );

  GetIt.I.registerFactory<ThrowBombUseCase>(
    () => ThrowBombUseCase(
      simpleModeServerRepository: GetIt.I<SimpleModeServerRepository>(),
    ),
  );

  GetIt.I.registerFactory<ConsumeRoomSnapshotUseCase>(
    () => ConsumeRoomSnapshotUseCase(
      roomSnapshotCache: GetIt.I<RoomSnapshotCache>(),
    ),
  );
}
