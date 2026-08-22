import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/action_log_model.dart';

/// A player got their client back. Carries a log only when the seat was really
/// being held for them -- a rejoin over a live socket announces nothing.
class PlayerReconnectedModel {
  final String playerId;
  final List<PlayerModel> playerList;
  final List<ActionLogModel> newLogs;

  PlayerReconnectedModel({
    required this.playerId,
    required this.playerList,
    required this.newLogs,
  });

  static PlayerReconnectedModel fromJson(Map<String, dynamic> json) {
    final List<ActionLogModel> newLogs = [];
    if (json['newLogs'] is List) {
      for (final log in json['newLogs']) {
        newLogs.add(ActionLogModel.fromJson(log));
      }
    }

    return PlayerReconnectedModel(
      playerId: json['playerId'],
      playerList: PlayerModel.listFromJson(json['players']),
      newLogs: newLogs,
    );
  }
}
