/// A returning player typed a different display name. Identity is the
/// [playerId], so the name is just a label that can change under it.
class PlayerRenamedEvent {
  final String playerId;
  final String name;

  PlayerRenamedEvent({required this.playerId, required this.name});

  @override
  String toString() {
    return 'PlayerRenamedEvent playerId: $playerId, name: $name';
  }
}
