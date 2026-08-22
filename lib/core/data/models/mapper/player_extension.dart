import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/core/domain/entities/player_entity.dart';

extension PlayerModelExtension on PlayerModel {
  PlayerEntity toEntity() {
    return PlayerEntity(
      id: id,
      name: name,
      isAlive: isAlive,
      hasPositioned: hasPositioned,
      isDisconnected: isDisconnected,
      throwOrder: throwOrder,
    );
  }
}

extension PlayerEntityExtension on PlayerEntity {
  PlayerModel toModel() {
    return PlayerModel(
      id: id,
      name: name,
      isAlive: isAlive,
      hasPositioned: hasPositioned,
      isDisconnected: isDisconnected,
      throwOrder: throwOrder,
    );
  }
}
