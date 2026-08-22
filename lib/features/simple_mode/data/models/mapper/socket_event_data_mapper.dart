import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/core/domain/entities/player_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';

// `hasThrowBomb` is derived from `throwOrder` rather than hardcoded: the server
// clears the order at the end of every round, so a null order genuinely means
// "hasn't thrown this round". That keeps mid-round payloads (a disconnect
// broadcast, a reconnect snapshot) from wiping the roster's throw indicators.
extension PlayerModelSimpleModeExtension on List<PlayerModel> {
  List<SimpleModePlayerEntity> toSimpleModeEntity() {
    return map(
      (e) => SimpleModePlayerEntity(
        id: e.id,
        name: e.name,
        isAlive: e.isAlive,
        hasPositioned: e.hasPositioned,
        hasThrowBomb: e.throwOrder != null,
        isDisconnected: e.isDisconnected,
        throwOrder: e.throwOrder,
      ),
    ).toList();
  }
}

extension PlayerEntitySimpleModeExtension on List<PlayerEntity> {
  List<SimpleModePlayerEntity> toSimpleModeEntity() {
    return map(
      (e) => SimpleModePlayerEntity(
        id: e.id,
        name: e.name,
        isAlive: e.isAlive,
        hasPositioned: e.hasPositioned,
        hasThrowBomb: e.throwOrder != null,
        isDisconnected: e.isDisconnected,
        throwOrder: e.throwOrder,
      ),
    ).toList();
  }
}
