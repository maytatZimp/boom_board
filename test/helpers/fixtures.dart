/// Raw wire payloads, keyed exactly as the server sends them.
///
/// Field names here are taken from the `fromJson` readers in lib/ -- note the
/// mismatches between wire keys and Dart field names (`players` ->
/// `playerList`, `phase` -> `state`, `remainingPlayers` -> `playerList`). Each
/// builder returns a fresh mutable map so a test can delete or corrupt a key
/// without affecting the next test.
library;

Map<String, dynamic> playerJson({
  String id = 'player-1',
  String name = 'Alice',
  bool isAlive = true,
  bool hasPositioned = false,
  bool isDisconnected = false,
  int? throwOrder,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'isAlive': isAlive,
    'hasPositioned': hasPositioned,
    'isDisconnected': isDisconnected,
    'throwOrder': throwOrder,
  };
}

Map<String, dynamic> spectatorJson({
  String id = 'spec-1',
  String name = 'Watcher',
}) {
  return <String, dynamic>{'id': id, 'name': name};
}

Map<String, dynamic> coordinateJson({int x = 0, int y = 0}) {
  return <String, dynamic>{'x': x, 'y': y};
}

Map<String, dynamic> explosionJson({
  String bomberId = 'player-1',
  String? victimId,
  bool isHit = false,
  int x = 3,
  int y = 4,
}) {
  return <String, dynamic>{
    'bomberId': bomberId,
    'victimId': victimId,
    'isHit': isHit,
    'x': x,
    'y': y,
  };
}

Map<String, dynamic> resultJson({
  int rank = 1,
  String id = 'player-1',
  String name = 'Alice',
  bool isAlive = true,
  bool isDisconnected = false,
}) {
  return <String, dynamic>{
    'rank': rank,
    'id': id,
    'name': name,
    'isAlive': isAlive,
    'isDisconnected': isDisconnected,
  };
}

Map<String, dynamic> actionLogJson({
  String id = 'log-1',
  String type = 'BOMB_EXPLODED',
  int timestamp = 1700000000000,
  Map<String, dynamic>? data,
}) {
  return <String, dynamic>{
    'id': id,
    'type': type,
    'timestamp': timestamp,
    'data': data ?? <String, dynamic>{'x': 3, 'y': 4},
  };
}

Map<String, dynamic> createRoomResponseJson({
  String roomCode = 'ABCD',
  String gameMode = 'simple',
  String hostId = 'player-1',
  List<Map<String, dynamic>>? players,
  List<Map<String, dynamic>>? spectators,
  String playerId = 'player-1',
  String secret = 'sh-sh-secret',
  bool isSpectator = false,
}) {
  return <String, dynamic>{
    'roomCode': roomCode,
    'gameMode': gameMode,
    'hostId': hostId,
    'players': players ?? [playerJson()],
    'spectators': spectators ?? <Map<String, dynamic>>[],
    'playerId': playerId,
    'secret': secret,
    'isSpectator': isSpectator,
  };
}

Map<String, dynamic> joinRoomResponseJson({
  String roomCode = 'ABCD',
  String gameMode = 'simple',
  String hostId = 'player-1',
  List<Map<String, dynamic>>? players,
  List<Map<String, dynamic>>? spectators,
  String playerId = 'player-2',
  String secret = 'sh-sh-secret',
  bool isSpectator = false,
}) {
  return <String, dynamic>{
    'roomCode': roomCode,
    'gameMode': gameMode,
    'hostId': hostId,
    'players': players ?? [playerJson(), playerJson(id: 'player-2', name: 'Bob')],
    'spectators': spectators ?? <Map<String, dynamic>>[],
    'playerId': playerId,
    'secret': secret,
    'isSpectator': isSpectator,
  };
}

/// The private snapshot sent to a socket entering a running room. A superset
/// payload: `you` is present only for a player, `ranking`/`winnerPosition` only
/// at `end`.
Map<String, dynamic> roomSnapshotJson({
  String state = 'attack',
  int roundNumber = 3,
  int width = 8,
  int height = 8,
  List<Map<String, dynamic>>? destroyedTiles,
  int timeLimit = 30,
  int remainingMs = 12450,
  String hostId = 'player-1',
  List<Map<String, dynamic>>? players,
  List<Map<String, dynamic>>? spectators,
  List<Map<String, dynamic>>? logs,
  bool isSpectator = false,
  Map<String, dynamic>? you,
  List<Map<String, dynamic>>? ranking,
  Map<String, dynamic>? winnerPosition,
}) {
  return <String, dynamic>{
    'state': state,
    'roundNumber': roundNumber,
    'boardSize': <String, dynamic>{'width': width, 'height': height},
    'destroyedTiles': destroyedTiles ?? [coordinateJson(x: 0, y: 1)],
    'timeLimit': timeLimit,
    'remainingMs': remainingMs,
    'hostId': hostId,
    'players': players ?? [playerJson()],
    'spectators': spectators ?? <Map<String, dynamic>>[],
    'logs': logs ?? <Map<String, dynamic>>[],
    'isSpectator': isSpectator,
    // Omitted, not nulled: `you` is absent for a spectator and the endgame
    // fields are absent outside the end phase, which is what the wire does.
    'you': ?you,
    'ranking': ?ranking,
    'winnerPosition': ?winnerPosition,
  };
}

/// The `you` block of a snapshot: everything about the recipient's own seat
/// that the public roster never carries.
Map<String, dynamic> snapshotSelfJson({
  int? x = 4,
  int? y = 2,
  bool hasPositioned = true,
  Map<String, dynamic>? bombTarget,
  int? throwOrder,
  bool isAlive = true,
}) {
  return <String, dynamic>{
    'x': x,
    'y': y,
    'hasPositioned': hasPositioned,
    'bombTarget': bombTarget,
    'throwOrder': throwOrder,
    'isAlive': isAlive,
  };
}

Map<String, dynamic> roundResolvedJson({
  List<Map<String, dynamic>>? explosions,
  List<Map<String, dynamic>>? remainingPlayers,
  List<Map<String, dynamic>>? destroyedTiles,
  List<Map<String, dynamic>>? newDestroyedTiles,
  List<Map<String, dynamic>>? newLogs,
  int roundNumber = 2,
}) {
  return <String, dynamic>{
    'explosions': explosions ?? [explosionJson()],
    'remainingPlayers': remainingPlayers ?? [playerJson()],
    'destroyedTiles': destroyedTiles ?? [coordinateJson(x: 1, y: 1)],
    'newDestroyedTiles': newDestroyedTiles ?? [coordinateJson(x: 1, y: 1)],
    'newLogs': newLogs ?? [actionLogJson()],
    'roundNumber': roundNumber,
  };
}

Map<String, dynamic> gameStartedJson({
  int width = 8,
  int height = 8,
  String state = 'position',
  List<Map<String, dynamic>>? destroyedTiles,
  int timeLimit = 30,
}) {
  return <String, dynamic>{
    'boardSize': <String, dynamic>{'width': width, 'height': height},
    'state': state,
    'destroyedTiles': destroyedTiles ?? <Map<String, dynamic>>[],
    'timeLimit': timeLimit,
  };
}

Map<String, dynamic> gameOverJson({
  List<Map<String, dynamic>>? ranking,
  Map<String, dynamic>? winnerPosition,
}) {
  return <String, dynamic>{
    'ranking': ranking ?? [resultJson()],
    'winnerPosition': winnerPosition ?? coordinateJson(x: 2, y: 5),
  };
}

/// The socket handlers unwrap a `data` envelope before parsing, so anything fed
/// to `SimpleModeSocketHandler.onX` has to be wrapped in this.
Map<String, dynamic> socketEnvelope(Map<String, dynamic> data) {
  return <String, dynamic>{'data': data};
}

/// A successful ack as `SocketService.handleAckData` expects it.
Map<String, dynamic> ackJson({int code = 200, Map<String, dynamic>? data}) {
  return <String, dynamic>{'code': code, 'data': data};
}
