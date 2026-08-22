import 'package:boom_board/features/simple_mode/domain/entities/events/room_snapshot_event.dart';

/// Holds the most recent `roomSnapshot` so it survives the gap between the
/// join ack and the game controller mounting.
///
/// The server sends the snapshot the moment it acks a mid-game entry, but the
/// client is still on the home screen at that point -- the controller that
/// consumes it doesn't exist yet, and the event bus doesn't replay. Whoever
/// mounts next calls [take] to pick it up.
class RoomSnapshotCache {
  RoomSnapshotEvent? _pending;

  void put(RoomSnapshotEvent snapshot) {
    _pending = snapshot;
  }

  /// Returns the pending snapshot and clears it, so it is applied exactly once.
  RoomSnapshotEvent? take() {
    final snapshot = _pending;
    _pending = null;
    return snapshot;
  }

  void clear() {
    _pending = null;
  }
}
