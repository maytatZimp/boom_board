import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/repositories/room_server_repository.dart';
import 'package:boom_board/features/simple_mode/data/data_source/room_snapshot_cache.dart';
import 'package:boom_board/features/simple_mode/data/data_source/simple_mode_socket_handler.dart';

class LeaveRoomParams {
  final GameMode gameMode;

  LeaveRoomParams({required this.gameMode});
}

class LeaveRoomUseCase {
  final RoomServerRepository roomServerRepository;
  final SimpleModeSocketHandler simpleModeSocketHandler;
  final RoomSnapshotCache roomSnapshotCache;
  final IdentityStore identityStore;

  LeaveRoomUseCase({
    required this.roomServerRepository,
    required this.simpleModeSocketHandler,
    required this.roomSnapshotCache,
    required this.identityStore,
  });

  Future<void> call(LeaveRoomParams params) async {
    // Everything local is dropped *before* the server is told, not after.
    //
    // Callers only log a failed leave and go home regardless, so ordering it the
    // other way meant the local state outlived the intent whenever the socket
    // was down -- and even on the happy path it outlived it for a whole server
    // round-trip. The home screen reads the credential slot the moment it is
    // built, which is well inside that window, so it would offer to rejoin the
    // room the player had just walked out of.
    //
    // Unbinding the handlers matters for the same reason: socket.on() appends,
    // so a bind left over from this room would double-register on the next
    // createRoom/joinRoom and every server event would be handled twice.
    if (params.gameMode == GameMode.simple) {
      simpleModeSocketHandler.dispose();

      // A parked snapshot belongs to the room we are leaving. Nothing else ever
      // clears it, and the next room's controller picks it up on mount -- which
      // would seed a brand-new lobby with a finished game's phase, round number
      // and roster.
      roomSnapshotCache.clear();
    }

    // Leaving on purpose is the one case where the credential slot is dead
    // weight: there is no seat left to reclaim. A drop or a reload keeps it.
    await identityStore.clear();

    await roomServerRepository.leaveRoom();
  }
}
