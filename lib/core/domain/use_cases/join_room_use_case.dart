import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/requests/join_room_request.dart';
import 'package:boom_board/core/domain/entities/join_room_entity.dart';
import 'package:boom_board/core/domain/repositories/room_server_repository.dart';
import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_handler.dart';

class JoinRoomParams {
  final String playerName;
  final String roomCode;

  JoinRoomParams({required this.playerName, required this.roomCode});
}

class JoinRoomUseCase {
  final RoomServerRepository roomServerRepository;
  final SimpleModeSocketHandler simpleModeSocketHandler;
  final IdentityStore identityStore;

  JoinRoomUseCase({
    required this.roomServerRepository,
    required this.simpleModeSocketHandler,
    required this.identityStore,
  });

  Future<JoinRoomEntity> call(JoinRoomParams params) async {
    final roomCode = params.roomCode.trim().toUpperCase();

    // Credentials are only ever presented to the room they belong to. Entering
    // any other room sends none, so the server mints a fresh identity -- which
    // is why a `playerId` is not stable across rooms today.
    final creds = identityStore.credentialsFor(roomCode);

    // Bind before the request: on a reconnect or a mid-game entry the server
    // emits a private roomSnapshot immediately after the ack.
    simpleModeSocketHandler.init();

    try {
      final result = await roomServerRepository.joinRoom(
        JoinRoomRequest(
          playerName: params.playerName,
          roomCode: roomCode,
          playerId: creds?.playerId,
          secret: creds?.secret,
        ),
      );

      if (result.gameMode != GameMode.simple) {
        simpleModeSocketHandler.dispose();
        return result;
      }

      await identityStore.save(
        playerId: result.playerId,
        secret: result.secret,
        roomCode: result.roomCode,
        playerName: params.playerName,
      );

      return result;
    } on BBServerException catch (e) {
      simpleModeSocketHandler.dispose();

      // Only drop the slot when it is provably useless: the credentials were
      // rejected, or the room they point at is gone. Anything else (a timeout,
      // a full room) leaves them intact so a retry can still reconnect.
      final wasReplayingCreds = creds != null;
      if (e.errorType == 'SECRET_MISMATCH' || (wasReplayingCreds && e.errorType == 'ROOM_NOT_FOUND')) {
        await identityStore.clear();
      }
      rethrow;
    } catch (_) {
      simpleModeSocketHandler.dispose();
      rethrow;
    }
  }
}
