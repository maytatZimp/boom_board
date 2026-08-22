import 'package:boom_board/core/data/models/models/spectator_model.dart';
import 'package:boom_board/core/domain/entities/spectator_entity.dart';

extension SpectatorModelExtension on SpectatorModel {
  SpectatorEntity toEntity() {
    return SpectatorEntity(id: id, name: name);
  }
}

extension SpectatorModelListExtension on List<SpectatorModel> {
  List<SpectatorEntity> toEntity() {
    return map((e) => e.toEntity()).toList();
  }
}

extension SpectatorEntityExtension on SpectatorEntity {
  SpectatorModel toModel() {
    return SpectatorModel(id: id, name: name);
  }
}
