import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/core/data/models/models/spectator_model.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/data/models/models/action_log_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/simple_mode_result_model.dart';

/// The private half of the snapshot: everything about *your own* seat that the
/// public roster doesn't carry. Absent when the recipient is a spectator.
class RoomSnapshotSelfModel {
  final int? x;
  final int? y;
  final bool hasPositioned;
  final Coordinate? bombTarget;
  final int? throwOrder;
  final bool isAlive;

  RoomSnapshotSelfModel({
    required this.x,
    required this.y,
    required this.hasPositioned,
    required this.bombTarget,
    required this.throwOrder,
    required this.isAlive,
  });

  static RoomSnapshotSelfModel fromJson(Map<String, dynamic> json) {
    final target = json['bombTarget'];

    return RoomSnapshotSelfModel(
      x: json['x'],
      y: json['y'],
      hasPositioned: json['hasPositioned'] ?? false,
      bombTarget: target is Map<String, dynamic> ? Coordinate.fromJson(target) : null,
      throwOrder: json['throwOrder'],
      isAlive: json['isAlive'] ?? true,
    );
  }
}

/// Sent privately to a socket that just entered a running room -- a returning
/// player resuming their seat, or a newcomer who arrived mid-game and will
/// spectate. One superset payload, role-gated by [isSpectator] + `isAlive`,
/// because the client already has every render path; this only seeds them.
class RoomSnapshotModel {
  final GameState state;
  final int roundNumber;
  final int boardWidth;
  final int boardHeight;
  final List<Coordinate> destroyedTiles;
  final int timeLimit;

  /// How much of the current phase is left. The phase timer never pauses, so a
  /// client that arrives mid-countdown has to start partway through.
  final int remainingMs;
  final String hostId;
  final List<PlayerModel> playerList;
  final List<SpectatorModel> spectatorList;
  final List<ActionLogModel> logs;
  final bool isSpectator;
  final RoomSnapshotSelfModel? you;
  final List<SimpleModeResultModel> ranking;
  final Coordinate? winnerPosition;

  RoomSnapshotModel({
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

  static RoomSnapshotModel fromJson(Map<String, dynamic> json) {
    final List<Coordinate> destroyedTiles = [];
    if (json['destroyedTiles'] is List) {
      for (final coordinate in json['destroyedTiles']) {
        destroyedTiles.add(Coordinate.fromJson(coordinate));
      }
    }

    final List<ActionLogModel> logs = [];
    if (json['logs'] is List) {
      for (final log in json['logs']) {
        logs.add(ActionLogModel.fromJson(log));
      }
    }

    final List<SimpleModeResultModel> ranking = [];
    if (json['ranking'] is List) {
      for (final entry in json['ranking']) {
        ranking.add(SimpleModeResultModel.fromJson(entry));
      }
    }

    final self = json['you'];
    final winner = json['winnerPosition'];

    return RoomSnapshotModel(
      state: GameState.fromString(json['state']),
      roundNumber: json['roundNumber'] ?? 1,
      boardWidth: json['boardSize']?['width'] ?? 8,
      boardHeight: json['boardSize']?['height'] ?? 8,
      destroyedTiles: destroyedTiles,
      timeLimit: json['timeLimit'] ?? 0,
      remainingMs: json['remainingMs'] ?? 0,
      hostId: json['hostId'] ?? '',
      playerList: PlayerModel.listFromJson(json['players']),
      spectatorList: SpectatorModel.listFromJson(json['spectators']),
      logs: logs,
      isSpectator: json['isSpectator'] ?? false,
      you: self is Map<String, dynamic> ? RoomSnapshotSelfModel.fromJson(self) : null,
      ranking: ranking,
      // The server sends null when there is no living, positioned winner yet.
      winnerPosition: winner is Map<String, dynamic> && winner['x'] != null && winner['y'] != null
          ? Coordinate.fromJson(winner)
          : null,
    );
  }
}
