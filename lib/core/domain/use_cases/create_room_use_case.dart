import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/requests/create_room_request.dart';
import 'package:boom_board/core/domain/entities/create_room_entity.dart';
import 'package:boom_board/core/domain/repositories/room_server_repository.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_handler.dart';

class CreateRoomParams {
  final String playerName;

  CreateRoomParams({required this.playerName});
}

class CreateRoomUseCase {
  final RoomServerRepository roomServerRepository;
  final SimpleModeSocketHandler simpleModeSocketHandler;
  final IdentityStore identityStore;

  CreateRoomUseCase({
    required this.roomServerRepository,
    required this.simpleModeSocketHandler,
    required this.identityStore,
  });

  Future<CreateRoomEntity> call(CreateRoomParams params) async {
    // Bind before the request, not after: the server may emit a private
    // roomSnapshot the instant it acks, and a handler bound afterwards could
    // miss it. init() unbinds first, so calling it early is safe.
    simpleModeSocketHandler.init();

    try {
      final result = await roomServerRepository.createRoom(
        CreateRoomRequest(
          playerName: params.playerName,
        ),
      );

      if (result.gameMode != GameMode.simple) {
        simpleModeSocketHandler.dispose();
        return result;
      }

      // A new room replaces whatever room this client was tied to before -- one
      // slot, not a list.
      await identityStore.save(
        playerId: result.playerId,
        secret: result.secret,
        roomCode: result.roomCode,
        playerName: params.playerName,
      );

      return result;
    } catch (_) {
      simpleModeSocketHandler.dispose();
      rethrow;
    }
  }
}
