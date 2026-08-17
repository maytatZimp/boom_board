class PlayerModel {
  String id;
  String name;
  bool isAlive;
  bool hasPositioned;
  bool isDisconnected;

  /// Null until this player locks in a bomb for the current round, so it also
  /// answers "have they thrown yet?" -- which is what a mid-game snapshot needs
  /// to rebuild the roster's throw indicators.
  int? throwOrder;

  PlayerModel({
    required this.id,
    required this.name,
    required this.isAlive,
    required this.hasPositioned,
    required this.isDisconnected,
    this.throwOrder,
  });

  static PlayerModel fromJson(Map<String, dynamic> json) {
    return PlayerModel(
      id: json['id'],
      name: json['name'],
      isAlive: json['isAlive'],
      hasPositioned: json['hasPositioned'],
      isDisconnected: json['isDisconnected'],
      throwOrder: json['throwOrder'],
    );
  }

  static List<PlayerModel> listFromJson(dynamic json) {
    if (json is! List) return [];
    return json.map((e) => PlayerModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
