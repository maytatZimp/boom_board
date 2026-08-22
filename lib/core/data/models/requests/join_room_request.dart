import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/core/data/models/models/spectator_model.dart';

class JoinRoomRequest {
  final String playerName;
  final String roomCode;

  /// Only filled when re-entering the room the stored credential slot belongs
  /// to. For a first-ever entry, or any *other* room, these stay null and the
  /// server treats the request as a brand-new entrant.
  final String? playerId;
  final String? secret;

  JoinRoomRequest({
    required this.playerName,
    required this.roomCode,
    this.playerId,
    this.secret,
  });

  Map<String, dynamic> toJson() {
    return {
      'playerName': playerName,
      'roomCode': roomCode,
      if (playerId != null) 'playerId': playerId,
      if (secret != null) 'secret': secret,
    };
  }
}

class JoinRoomResponse {
  final String roomCode;
  final GameMode gameMode;
  final String hostId;
  final List<PlayerModel> playerList;
  final List<SpectatorModel> spectatorList;

  /// Server-resolved credentials: the same pair back again on a reconnect, or a
  /// freshly minted pair when the server treated this as a new entrant.
  final String playerId;
  final String secret;

  /// True when the game was already running, so this client watches until the
  /// host resets to lobby.
  final bool isSpectator;

  JoinRoomResponse({
    required this.roomCode,
    required this.gameMode,
    required this.hostId,
    required this.playerList,
    required this.spectatorList,
    required this.playerId,
    required this.secret,
    required this.isSpectator,
  });

  static JoinRoomResponse fromJson(Map<String, dynamic> json) {
    final List<PlayerModel> playerList = [];
    for (final data in json['players']) {
      playerList.add(PlayerModel.fromJson(data));
    }
    return JoinRoomResponse(
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
