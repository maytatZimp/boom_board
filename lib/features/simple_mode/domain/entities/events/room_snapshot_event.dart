import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/core/domain/entities/spectator_entity.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/domain/entities/action_log_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_result_entity.dart';

class RoomSnapshotSelf {
  final int? x;
  final int? y;
  final bool hasPositioned;
  final Coordinate? bombTarget;
  final int? throwOrder;
  final bool isAlive;

  RoomSnapshotSelf({
    required this.x,
    required this.y,
    required this.hasPositioned,
    required this.bombTarget,
    required this.throwOrder,
    required this.isAlive,
  });

  @override
  String toString() {
    return 'RoomSnapshotSelf x: $x, y: $y, hasPositioned: $hasPositioned, bombTarget: $bombTarget, throwOrder: $throwOrder, isAlive: $isAlive';
  }
}

class RoomSnapshotEvent {
  final GameState state;
  final int roundNumber;
  final int boardWidth;
  final int boardHeight;
  final List<Coordinate> destroyedTiles;
  final int timeLimit;
  final int remainingMs;
  final String hostId;
  final List<SimpleModePlayerEntity> playerList;
  final List<SpectatorEntity> spectatorList;
  final List<ActionLogEntity> logs;
  final bool isSpectator;
  final RoomSnapshotSelf? you;
  final List<SimpleModeResultEntity> ranking;
  final Coordinate? winnerPosition;

  RoomSnapshotEvent({
    required this.state,
    required this.roundNumber,
    required this.boardWidth,
    required this.boardHeight,
    required this.destroyedTiles,
    required this.timeLimit,
    required this.remainingMs,
    required this.hostId,
    required this.playerList,
    required this.spectatorList,
    required this.logs,
    required this.isSpectator,
    required this.you,
    required this.ranking,
    required this.winnerPosition,
  });

  @override
  String toString() {
    return 'RoomSnapshotEvent state: $state, roundNumber: $roundNumber, isSpectator: $isSpectator, remainingMs: $remainingMs, you: $you, playerList: $playerList, spectatorList: $spectatorList';
  }
}
