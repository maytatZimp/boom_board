import 'package:boom_board/features/simple_mode/data/data_source/room_snapshot_cache.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/room_snapshot_event.dart';

/// Picks up a `roomSnapshot` that arrived before the game screen was ready.
/// Returns null when there is nothing waiting, which is the normal case for a
/// plain lobby join.
class ConsumeRoomSnapshotUseCase {
  final RoomSnapshotCache roomSnapshotCache;

  ConsumeRoomSnapshotUseCase({required this.roomSnapshotCache});

  RoomSnapshotEvent? call() {
    return roomSnapshotCache.take();
  }
}
