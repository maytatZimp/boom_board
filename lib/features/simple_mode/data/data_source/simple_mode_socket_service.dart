import 'package:boom_board/core/utils/socket_service.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/reset_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/set_position_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/start_game_request.dart';
import 'package:boom_board/features/simple_mode/data/models/requests/throw_bomb_request.dart';

class SimpleModeSocketService {
  final SocketService socketService;

  SimpleModeSocketService({required this.socketService});

  Future<void> startGame(StartGameRequest request) async {
    await socketService.emitSocket(
      actionName: 'startGame',
      data: request.toJson(),
    );
  }

  Future<void> setPosition(SetPositionRequest request) async {
    await socketService.emitSocket(
      actionName: 'setPosition',
      data: request.toJson(),
    );
  }

  Future<ThrowBombResponse?> throwBomb(ThrowBombRequest request) async {
    final res = await socketService.emitSocket(
      actionName: 'throwBomb',
      data: request.toJson(),
    );

    if (res.data != null) {
      return ThrowBombResponse.fromJson(res.data!);
    }
    return null;
  }

  Future<void> requestSnapshot() async {
    await socketService.emitSocket(actionName: 'requestSnapshot');
  }

  Future<void> resetGame(ResetGameRequest request) async {
    await socketService.emitSocket(
      actionName: 'resetGame',
      data: request.toJson(),
    );
  }
}
