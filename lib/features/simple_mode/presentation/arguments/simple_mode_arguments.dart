import 'package:boom_board/core/domain/entities/spectator_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';

class SimpleModeArguments {
  final String roomCode;
  final String hostId;
  final List<SimpleModePlayerEntity> playerList;
  final List<SpectatorEntity> spectatorList;

  /// True when the game was already running on entry, so this client watches
  /// rather than plays until the host resets to lobby.
  final bool isSpectator;

  SimpleModeArguments({
    required this.roomCode,
    required this.hostId,
    required this.playerList,
    this.spectatorList = const [],
    this.isSpectator = false,
  });
}
