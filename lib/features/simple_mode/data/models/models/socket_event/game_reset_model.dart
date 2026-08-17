import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/core/data/models/models/spectator_model.dart';

class GameResetModel {
  final List<PlayerModel> playerList;

  /// Always empty in practice -- every spectator is promoted into [playerList]
  /// by this point. Sent so the client can clear its own list from the payload
  /// rather than inferring it.
  final List<SpectatorModel> spectatorList;
  final String newHostId;

  GameResetModel({
    required this.playerList,
    required this.spectatorList,
    required this.newHostId,
  });

  static GameResetModel fromJson(Map<String, dynamic> json) {
    return GameResetModel(
      playerList: PlayerModel.listFromJson(json['players']),
      spectatorList: SpectatorModel.listFromJson(json['spectators']),
      newHostId: json['newHostId'] ?? '',
    );
  }
}
