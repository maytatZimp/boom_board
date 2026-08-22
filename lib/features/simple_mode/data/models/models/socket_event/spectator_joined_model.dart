import 'package:boom_board/core/data/models/models/spectator_model.dart';

class SpectatorJoinedModel {
  final SpectatorModel spectator;
  final List<SpectatorModel> spectatorList;

  SpectatorJoinedModel({required this.spectator, required this.spectatorList});

  static SpectatorJoinedModel fromJson(Map<String, dynamic> json) {
    return SpectatorJoinedModel(
      spectator: SpectatorModel.fromJson(json['spectator']),
      spectatorList: SpectatorModel.listFromJson(json['spectators']),
    );
  }
}

class SpectatorLeftModel {
  final String spectatorId;
  final List<SpectatorModel> spectatorList;

  SpectatorLeftModel({required this.spectatorId, required this.spectatorList});

  static SpectatorLeftModel fromJson(Map<String, dynamic> json) {
    return SpectatorLeftModel(
      spectatorId: json['spectatorId'],
      spectatorList: SpectatorModel.listFromJson(json['spectators']),
    );
  }
}
