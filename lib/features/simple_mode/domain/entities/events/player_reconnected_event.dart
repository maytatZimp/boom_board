import 'package:boom_board/features/simple_mode/domain/entities/action_log_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';

class PlayerReconnectedEvent {
  final String playerId;
  final List<SimpleModePlayerEntity> playerList;
  final List<ActionLogEntity> newLogs;

  PlayerReconnectedEvent({
    required this.playerId,
    required this.playerList,
    required this.newLogs,
  });

  @override
  String toString() {
    return 'PlayerReconnectedEvent playerId: $playerId, playerList: $playerList, newLogs: $newLogs';
  }
}
