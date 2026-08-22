import 'package:boom_board/core/domain/entities/spectator_entity.dart';

class SpectatorJoinedEvent {
  final SpectatorEntity spectator;
  final List<SpectatorEntity> spectatorList;

  SpectatorJoinedEvent({required this.spectator, required this.spectatorList});

  @override
  String toString() {
    return 'SpectatorJoinedEvent spectator: $spectator, spectatorList: $spectatorList';
  }
}

class SpectatorLeftEvent {
  final String spectatorId;
  final List<SpectatorEntity> spectatorList;

  SpectatorLeftEvent({required this.spectatorId, required this.spectatorList});

  @override
  String toString() {
    return 'SpectatorLeftEvent spectatorId: $spectatorId, spectatorList: $spectatorList';
  }
}
