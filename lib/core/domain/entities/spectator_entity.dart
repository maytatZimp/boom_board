/// Someone watching a game they aren't in.
///
/// Not a dead player: a dead player is still on the board with a rank, a
/// spectator never had a tile. They join the next game when the host resets.
class SpectatorEntity {
  final String id;
  final String name;

  SpectatorEntity({required this.id, required this.name});

  @override
  String toString() {
    return 'SpectatorEntity id: $id, name: $name';
  }
}
