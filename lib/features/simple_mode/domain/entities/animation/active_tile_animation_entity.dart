// Helper class for tile-locked animations (Explosions and Ghosts)
class ActiveTileAnimationEntity {
  final String id;
  final int x;
  final int y;

  /// Only set for death ghosts: the name shown above the skull so everyone can
  /// tell at a glance who just got killed.
  final String? playerName;

  ActiveTileAnimationEntity({
    required this.id,
    required this.x,
    required this.y,
    this.playerName,
  });

  @override
  String toString() {
    return 'ActiveTileAnimationEntity id: $id, x: $x, y: $y, playerName: $playerName';
  }
}
