import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/repositories/room_server_repository.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_handler.dart';

class LeaveRoomParams {
  final GameMode gameMode;

  LeaveRoomParams({required this.gameMode});
}

class LeaveRoomUseCase {
  final RoomServerRepository roomServerRepository;
  final SimpleModeSocketHandler simpleModeSocketHandler;

  LeaveRoomUseCase({
    required this.roomServerRepository,
    required this.simpleModeSocketHandler,
  });

  Future<void> call(LeaveRoomParams params) async {
    try {
      await roomServerRepository.leaveRoom();
    } finally {
      // Unbind locally even when the server call failed. Callers only log the
      // error and leave the room anyway, so keeping the handlers bound would
      // double-register them on the next createRoom/joinRoom -- socket.on()
      // appends, so every server event would then be handled twice.
      if (params.gameMode == GameMode.simple) {
        simpleModeSocketHandler.dispose();
      }
    }
  }
}
