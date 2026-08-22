import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/action_log_model.dart';

/// A player gave up their seat. Unlike a disconnect they are off the board for
/// good -- the roster in here is the whole remaining roster, not a status change.
class PlayerLeftModel {
  final String leftPlayerId;
  final String newHostId;
  final List<PlayerModel> playerList;

  /// Empty in the lobby, where the roster shrinking explains itself. Mid-game
  /// it carries the one log line announcing the departure.
  final List<ActionLogModel> newLogs;

  PlayerLeftModel({
    required this.leftPlayerId,
    required this.newHostId,
    required this.playerList,
    required this.newLogs,
  });

  static PlayerLeftModel fromJson(Map<String, dynamic> json) {
    final List<ActionLogModel> newLogs = [];
    if (json['newLogs'] is List) {
      for (final log in json['newLogs']) {
        newLogs.add(ActionLogModel.fromJson(log));
      }
    }

    return PlayerLeftModel(
      leftPlayerId: json['leftPlayerId'],
      newHostId: json['newHostId'],
      playerList: PlayerModel.listFromJson(json['players']),
      newLogs: newLogs,
    );
  }
}
