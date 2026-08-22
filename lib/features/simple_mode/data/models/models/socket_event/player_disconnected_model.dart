import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/action_log_model.dart';

/// A player lost their client mid-game. They are still alive and on the board --
/// this is purely a connection-status change, never a death.
class PlayerDisconnectedModel {
  final String disconnectedPlayerId;
  final String newHostId;
  final List<PlayerModel> playerList;
  final List<ActionLogModel> newLogs;

  PlayerDisconnectedModel({
    required this.disconnectedPlayerId,
    required this.newHostId,
    required this.playerList,
    required this.newLogs,
  });

  static PlayerDisconnectedModel fromJson(Map<String, dynamic> json) {
    final List<ActionLogModel> newLogs = [];
    if (json['newLogs'] is List) {
      for (final log in json['newLogs']) {
        newLogs.add(ActionLogModel.fromJson(log));
      }
    }

    return PlayerDisconnectedModel(
      disconnectedPlayerId: json['disconnectedPlayerId'],
      newHostId: json['newHostId'],
      playerList: PlayerModel.listFromJson(json['players']),
      newLogs: newLogs,
    );
  }
}
