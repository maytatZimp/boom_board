import 'package:boom_board/core/domain/entities/spectator_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';

class GameResetEvent {
  final List<SimpleModePlayerEntity> playerList;
  final List<SpectatorEntity> spectatorList;
  final String newHostId;

  GameResetEvent({
    required this.playerList,
    required this.spectatorList,
    required this.newHostId,
  });

  @override
  String toString() {
    return 'GameResetEvent playerList: $playerList, spectatorList: $spectatorList, newHostId: $newHostId';
  }
}
