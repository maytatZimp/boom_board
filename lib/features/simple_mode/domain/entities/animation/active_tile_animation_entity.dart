// Helper class for tile-locked animations (Explosions and Ghosts)
class ActiveTileAnimationEntity {
  final String id;
  final int x;
  final int y;

  /// Only set for death ghosts: the names shown above the skull so everyone
  /// can tell at a glance who just got killed.
  ///
  /// A list because one bomb can kill everyone stacked on its tile, and they
  /// all die on that one tile -- so it is one skull carrying every name rather
  /// than a pile of ghosts drawn pixel-for-pixel on top of each other.
  final List<String> playerNames;

  ActiveTileAnimationEntity({
    required this.id,
    required this.x,
    required this.y,
    this.playerNames = const [],
  });

  @override
  String toString() {
    return 'ActiveTileAnimationEntity id: $id, x: $x, y: $y, playerNames: $playerNames';
  }
}
