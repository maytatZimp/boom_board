import 'package:boom_board/features/simple_mode/domain/entities/action_log_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';

class PlayerDisconnectedEvent {
  final String disconnectedPlayerId;
  final String newHostId;
  final List<SimpleModePlayerEntity> playerList;
  final List<ActionLogEntity> newLogs;

  PlayerDisconnectedEvent({
    required this.disconnectedPlayerId,
    required this.newHostId,
    required this.playerList,
    required this.newLogs,
  });

  @override
  String toString() {
    return 'PlayerDisconnectedEvent disconnectedPlayerId: $disconnectedPlayerId, newHostId: $newHostId, playerList: $playerList, newLogs: $newLogs';
  }
}
