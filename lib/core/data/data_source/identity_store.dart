import 'package:shared_preferences/shared_preferences.dart';

/// The credentials that let this client reclaim its seat in a room.
///
/// [playerId] is public -- the server broadcasts it in every roster. [secret] is
/// the half nobody else ever receives, and is what actually proves ownership on
/// reconnect. Both are bound to [roomCode]: credentials are never presented to
/// a room this client isn't a member of.
class RoomCredentials {
  final String playerId;
  final String secret;
  final String roomCode;

  /// The display name last used in this room. Not part of the credential --
  /// it's stored because every entry request needs a name, and after a page
  /// reload there is no controller left holding the one the user typed.
  final String playerName;

  RoomCredentials({
    required this.playerId,
    required this.secret,
    required this.roomCode,
    required this.playerName,
  });

  @override
  String toString() {
    return 'RoomCredentials playerId: $playerId, roomCode: $roomCode, playerName: $playerName';
  }
}

/// A single room-scoped credential slot, persisted to browser storage.
///
/// Deliberately *not* a list: a client is only ever in one room at a time, so
/// entering a new room overwrites the slot rather than accumulating. The
/// [RoomCredentials.roomCode] records which room the creds belong to, so
/// [credentialsFor] only hands them back when re-entering that exact room.
///
/// Lifecycle: keep the slot while still meaningfully tied to the room (dropped
/// connection, page reload, or between games in the same room); clear it the
/// moment the user deliberately leaves or the room is provably gone.
class IdentityStore {
  static const _playerIdKey = 'bb_player_id';
  static const _secretKey = 'bb_player_secret';
  static const _roomCodeKey = 'bb_room_code';
  static const _playerNameKey = 'bb_player_name';

  RoomCredentials? _cached;
  bool _loaded = false;

  /// Reads the persisted slot into memory. Call once at startup, before
  /// anything asks for the local player id.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final playerId = prefs.getString(_playerIdKey);
    final secret = prefs.getString(_secretKey);
    final roomCode = prefs.getString(_roomCodeKey);
    final playerName = prefs.getString(_playerNameKey);

    if (playerId != null && secret != null && roomCode != null && playerName != null) {
      _cached = RoomCredentials(
        playerId: playerId,
        secret: secret,
        roomCode: roomCode,
        playerName: playerName,
      );
    }
    _loaded = true;
  }

  bool get isLoaded => _loaded;

  RoomCredentials? get credentials => _cached;

  String? get playerId => _cached?.playerId;

  String? get roomCode => _cached?.roomCode;

  /// The creds to replay when entering [roomCode], or null when this is a room
  /// we hold nothing for -- in which case the server mints a fresh identity.
  RoomCredentials? credentialsFor(String roomCode) {
    final creds = _cached;
    if (creds == null) return null;
    if (creds.roomCode.toUpperCase() != roomCode.toUpperCase()) return null;
    return creds;
  }

  Future<void> save({
    required String playerId,
    required String secret,
    required String roomCode,
    required String playerName,
  }) async {
    _cached = RoomCredentials(
      playerId: playerId,
      secret: secret,
      roomCode: roomCode,
      playerName: playerName,
    );
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playerIdKey, playerId);
    await prefs.setString(_secretKey, secret);
    await prefs.setString(_roomCodeKey, roomCode);
    await prefs.setString(_playerNameKey, playerName);
  }

  Future<void> clear() async {
    _cached = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playerIdKey);
    await prefs.remove(_secretKey);
    await prefs.remove(_roomCodeKey);
    await prefs.remove(_playerNameKey);
  }
}
