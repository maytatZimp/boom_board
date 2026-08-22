class PlayerRenamedModel {
  final String playerId;
  final String name;

  PlayerRenamedModel({required this.playerId, required this.name});

  static PlayerRenamedModel fromJson(Map<String, dynamic> json) {
    return PlayerRenamedModel(
      playerId: json['playerId'],
      name: json['name'],
    );
  }
}
