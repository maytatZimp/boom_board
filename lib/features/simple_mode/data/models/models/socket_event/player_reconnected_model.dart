import 'package:boom_board/core/data/models/models/player_model.dart';

class PlayerReconnectedModel {
  final String playerId;
  final List<PlayerModel> playerList;

  PlayerReconnectedModel({
    required this.playerId,
    required this.playerList,
  });

  static PlayerReconnectedModel fromJson(Map<String, dynamic> json) {
    return PlayerReconnectedModel(
      playerId: json['playerId'],
      playerList: PlayerModel.listFromJson(json['players']),
    );
  }
}
