import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';

class PlayerReconnectedEvent {
  final String playerId;
  final List<SimpleModePlayerEntity> playerList;

  PlayerReconnectedEvent({
    required this.playerId,
    required this.playerList,
  });

  @override
  String toString() {
    return 'PlayerReconnectedEvent playerId: $playerId, playerList: $playerList';
  }
}
