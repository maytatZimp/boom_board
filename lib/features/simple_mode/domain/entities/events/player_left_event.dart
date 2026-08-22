import 'package:boom_board/features/simple_mode/domain/entities/action_log_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';

class PlayerLeftEvent {
  final String playerId;
  final String newHostId;
  final List<SimpleModePlayerEntity> playerList;
  final List<ActionLogEntity> newLogs;

  PlayerLeftEvent({
    required this.playerId,
    required this.newHostId,
    required this.playerList,
    required this.newLogs,
  });

  @override
  String toString() {
    return 'PlayerLeftEvent playerId: $playerId, newHostId: $newHostId, playerList: $playerList, newLogs: $newLogs';
  }
}
