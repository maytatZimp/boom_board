import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_service.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/reset_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/set_position_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/start_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/throw_bomb_request.dart';
import 'package:boom_board/features/simple_mode/domain/repositories/simple_mode_server_repository.dart';

class SimpleModeServerRepositoryImpl implements SimpleModeServerRepository {
  final SimpleModeSocketService socketService;

  SimpleModeServerRepositoryImpl({required this.socketService});

  @override
  Future<void> startGame(StartGameRequest request) async {
    await socketService.startGame(request);
  }

  @override
  Future<void> setPosition(SetPositionRequest request) async {
    await socketService.setPosition(request);
  }

  @override
  Future<ThrowBombResponse?> throwBomb(ThrowBombRequest request) async {
    return await socketService.throwBomb(request);
  }

  @override
  Future<void> requestSnapshot() async {
    await socketService.requestSnapshot();
  }

  @override
  Future<void> resetGame(ResetGameRequest request) async {
    await socketService.resetGame(request);
  }
}
