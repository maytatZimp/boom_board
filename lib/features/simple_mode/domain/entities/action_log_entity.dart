import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/log_action_type.dart';

class ActionLogEntity {
  final String id;
  final LogActionType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  ActionLogEntity({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.data,
  });

  LogBombExplodedData getLogBombExplodedData() {
    if (type == LogActionType.bombExploded) {
      return LogBombExplodedData.fromJson(data);
    } else {
      throw Exception('Log data ($type) is not type ${LogActionType.bombExploded}');
    }
  }

  LogPlayerEliminatedData getLogPlayerEliminatedData() {
    if (type == LogActionType.playerEliminated) {
      return LogPlayerEliminatedData.fromJson(data);
    } else {
      throw Exception('Log data ($type) is not type ${LogActionType.playerEliminated}');
    }
  }

  LogOrbitalLaserFiredData getLogOrbitalLaserFiredData() {
    if (type == LogActionType.orbitalLaserFired) {
      return LogOrbitalLaserFiredData.fromJson(data);
    } else {
      throw Exception('Log data ($type) is not type ${LogActionType.orbitalLaserFired}');
    }
  }

  LogPlayerDisconnectedData getLogPlayerDisconnectedData() {
    if (type == LogActionType.playerDisconnected) {
      return LogPlayerDisconnectedData.fromJson(data);
    } else {
      throw Exception('Log data ($type) is not type ${LogActionType.playerDisconnected}');
    }
  }

  LogPlayerLeftData getLogPlayerLeftData() {
    if (type == LogActionType.playerLeft) {
      return LogPlayerLeftData.fromJson(data);
    } else {
      throw Exception('Log data ($type) is not type ${LogActionType.playerLeft}');
    }
  }

  @override
  String toString() {
    return 'ActionLogEntity type: $type, data: $data';
  }
}

class LogBombExplodedData {
  final String bomberName;
  final String bomberId;
  final int x;
  final int y;

  LogBombExplodedData({
    required this.bomberName,
    required this.bomberId,
    required this.x,
    required this.y,
  });

  static LogBombExplodedData fromJson(Map<String, dynamic> json) {
    return LogBombExplodedData(
      bomberName: json['bomberName'],
      bomberId: json['bomberId'],
      x: json['x'],
      y: json['y'],
    );
  }
}

class LogPlayerEliminatedData {
  final String bomberName;
  final String bomberId;
  final String victimName;
  final String victimId;

  LogPlayerEliminatedData({
    required this.bomberName,
    required this.bomberId,
    required this.victimName,
    required this.victimId,
  });

  static LogPlayerEliminatedData fromJson(Map<String, dynamic> json) {
    return LogPlayerEliminatedData(
      bomberName: json['bomberName'],
      bomberId: json['bomberId'],
      victimName: json['victimName'],
      victimId: json['victimId'],
    );
  }
}

class LogOrbitalLaserFiredData {
  final List<Coordinate> tiles;

  LogOrbitalLaserFiredData({required this.tiles});

  static LogOrbitalLaserFiredData fromJson(Map<String, dynamic> json) {
    final List<Coordinate> tiles = [];
    for (final tile in json['coordinates']) {
      tiles.add(Coordinate.fromJson(tile));
    }

    return LogOrbitalLaserFiredData(tiles: tiles);
  }
}

class LogPlayerDisconnectedData {
  final String playerName;

  LogPlayerDisconnectedData({required this.playerName});

  static LogPlayerDisconnectedData fromJson(Map<String, dynamic> json) {
    return LogPlayerDisconnectedData(playerName: json['playerName']);
  }
}

/// A player who gave up their seat mid-game. Same payload as a disconnect, but
/// a different thing to read: they are off the board for good, not offline.
class LogPlayerLeftData {
  final String playerName;

  LogPlayerLeftData({required this.playerName});

  static LogPlayerLeftData fromJson(Map<String, dynamic> json) {
    return LogPlayerLeftData(playerName: json['playerName']);
  }
}
