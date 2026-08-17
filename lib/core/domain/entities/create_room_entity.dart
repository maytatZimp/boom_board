import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/entities/player_entity.dart';
import 'package:boom_board/core/domain/entities/spectator_entity.dart';

class CreateRoomEntity {
  final String roomCode;
  final GameMode gameMode;
  final String hostId;
  final List<PlayerEntity> playerList;
  final List<SpectatorEntity> spectatorList;
  final String playerId;
  final String secret;
  final bool isSpectator;

  CreateRoomEntity({
    required this.roomCode,
    required this.gameMode,
    required this.hostId,
    required this.playerList,
    required this.spectatorList,
    required this.playerId,
    required this.secret,
    required this.isSpectator,
  });
}
