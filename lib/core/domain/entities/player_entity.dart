class PlayerEntity {
  String id;
  String name;
  bool isAlive;
  bool hasPositioned;
  bool isDisconnected;
  int? throwOrder;

  PlayerEntity({
    required this.id,
    required this.name,
    required this.isAlive,
    required this.hasPositioned,
    required this.isDisconnected,
    this.throwOrder,
  });
}
