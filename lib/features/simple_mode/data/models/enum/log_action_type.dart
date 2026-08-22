import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';

enum LogActionType {
  bombExploded,
  playerEliminated,
  orbitalLaserFired,
  playerDisconnected,
  playerReconnected,
  playerLeft
  ;

  static LogActionType fromString(String value) {
    switch (value) {
      case 'BOMB_EXPLODED':
        return bombExploded;
      case 'PLAYER_ELIMINATED':
        return playerEliminated;
      case 'ORBITAL_LASER_FIRED':
        return orbitalLaserFired;
      case 'PLAYER_DISCONNECTED':
        return playerDisconnected;
      case 'PLAYER_RECONNECTED':
        return playerReconnected;
      case 'PLAYER_LEFT':
        return playerLeft;
      default:
        throw InvalidSocketResponseException();
    }
  }

  @override
  String toString() {
    switch (this) {
      case bombExploded:
        return 'BOMB_EXPLODED';
      case playerEliminated:
        return 'PLAYER_ELIMINATED';
      case orbitalLaserFired:
        return 'ORBITAL_LASER_FIRED';
      case playerDisconnected:
        return 'PLAYER_DISCONNECTED';
      case playerReconnected:
        return 'PLAYER_RECONNECTED';
      case playerLeft:
        return 'PLAYER_LEFT';
    }
  }
}
