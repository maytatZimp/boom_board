import 'package:boom_board/core/data/models/mapper/player_extension.dart';
import 'package:boom_board/core/data/models/mapper/spectator_extension.dart';
import 'package:boom_board/core/data/models/requests/create_room_request.dart';
import 'package:boom_board/core/domain/entities/create_room_entity.dart';

extension CreateRoomExtension on CreateRoomResponse {
  CreateRoomEntity toEntity() {
    return CreateRoomEntity(
      roomCode: roomCode,
      gameMode: gameMode,
      hostId: hostId,
      playerList: playerList.map((e) => e.toEntity()).toList(),
      spectatorList: spectatorList.toEntity(),
      playerId: playerId,
      secret: secret,
      isSpectator: isSpectator,
    );
  }
}

extension CreateRoomEntityExtension on CreateRoomEntity {
  CreateRoomResponse toResponse() {
    return CreateRoomResponse(
      roomCode: roomCode,
      gameMode: gameMode,
      hostId: hostId,
      playerList: playerList.map((e) => e.toModel()).toList(),
      spectatorList: spectatorList.map((e) => e.toModel()).toList(),
      playerId: playerId,
      secret: secret,
      isSpectator: isSpectator,
    );
  }
}
