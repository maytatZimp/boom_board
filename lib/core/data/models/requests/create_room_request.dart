import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/core/data/models/models/spectator_model.dart';

class CreateRoomRequest {
  final String playerName;

  CreateRoomRequest({required this.playerName});

  Map<String, dynamic> toJson() {
    return {
      'playerName': playerName,
    };
  }
}

class CreateRoomResponse {
  final String roomCode;
  final GameMode gameMode;
  final String hostId;
  final List<PlayerModel> playerList;
  final List<SpectatorModel> spectatorList;

  /// Server-minted credentials for this client. The only place [secret] ever
  /// appears -- it is never part of any broadcast payload.
  final String playerId;
  final String secret;
  final bool isSpectator;

  CreateRoomResponse({
    required this.roomCode,
    required this.gameMode,
    required this.hostId,
    required this.playerList,
    required this.spectatorList,
    required this.playerId,
    required this.secret,
    required this.isSpectator,
  });

  static CreateRoomResponse fromJson(Map<String, dynamic> json) {
    final List<PlayerModel> playerList = [];
    for (final data in json['players']) {
      playerList.add(PlayerModel.fromJson(data));
    }

    return CreateRoomResponse(
      roomCode: json['roomCode'],
      gameMode: GameMode.fromString(json['gameMode']),
      hostId: json['hostId'],
      playerList: playerList,
      spectatorList: SpectatorModel.listFromJson(json['spectators']),
      playerId: json['playerId'],
      secret: json['secret'],
      isSpectator: json['isSpectator'] ?? false,
    );
  }
}
