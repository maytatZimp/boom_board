import 'package:boom_board/core/data/models/mapper/spectator_extension.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:boom_board/core/utils/socket_service.dart';
import 'package:boom_board/features/simple_mode/data/data_source/room_snapshot_cache.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/action_log_mapper.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/explosion_result_extension.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/simple_mode_result_extension.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/socket_event_data_mapper.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/forced_position_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/game_over_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/game_reset_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/game_started_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/phase_changd_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_disconnected_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_joined_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_left_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_ready_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_reconnected_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_renamed_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/room_snapshot_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/round_resolved_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/spectator_joined_model.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/forced_position_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_over_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_reset_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_started_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/phase_changed_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_disconnected_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_joined_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_left_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_ready_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_reconnected_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_renamed_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/room_snapshot_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/round_resolved_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/spectator_changed_event.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

class SimpleModeSocketHandler {
  final SocketService socketService;
  final RoomSnapshotCache roomSnapshotCache;

  Logger get logger {
    return GetIt.I<Logger>();
  }

  SimpleModeSocketHandler({
    required this.socketService,
    required this.roomSnapshotCache,
  });

  void init() {
    // Rebind from a clean slate. socket.on() appends and there is a single
    // long-lived io.Socket for the whole app, so any bind left over from a
    // previous room would survive into this one and make every server event
    // fire twice -- duplicate action-log entries, double-applied player
    // mutations. Leftovers are easy to produce: leaveRoom() throws whenever
    // the socket is down, and a connection drop navigates home without going
    // through LeaveRoomUseCase at all. Unbinding here covers every route in.
    dispose();

    socketService.socket.on('playerJoined', onPlayerJoined);

    socketService.socket.on('playerLeft', onPlayerLeft);

    socketService.socket.on('playerDisconnected', onPlayerDisconnected);

    socketService.socket.on('playerReconnected', onPlayerReconnected);

    socketService.socket.on('playerRenamed', onPlayerRenamed);

    socketService.socket.on('spectatorJoined', onSpectatorJoined);

    socketService.socket.on('spectatorLeft', onSpectatorLeft);

    socketService.socket.on('roomSnapshot', onRoomSnapshot);

    socketService.socket.on('gameStarted', onGameStarted);

    socketService.socket.on('playerReady', onPlayerReady);

    socketService.socket.on('phaseChanged', onPhaseChanged);

    socketService.socket.on('roundResolved', onRoundResolved);

    socketService.socket.on('gameOver', onGameOver);

    socketService.socket.on('gameReset', onGameReset);

    socketService.socket.on('forcedPosition', onForcedPosition);
  }

  void dispose() {
    socketService.socket.off('playerJoined', onPlayerJoined);

    socketService.socket.off('playerLeft', onPlayerLeft);

    socketService.socket.off('playerDisconnected', onPlayerDisconnected);

    socketService.socket.off('playerReconnected', onPlayerReconnected);

    socketService.socket.off('playerRenamed', onPlayerRenamed);

    socketService.socket.off('spectatorJoined', onSpectatorJoined);

    socketService.socket.off('spectatorLeft', onSpectatorLeft);

    socketService.socket.off('roomSnapshot', onRoomSnapshot);

    socketService.socket.off('gameStarted', onGameStarted);

    socketService.socket.off('playerReady', onPlayerReady);

    socketService.socket.off('phaseChanged', onPhaseChanged);

    socketService.socket.off('roundResolved', onRoundResolved);

    socketService.socket.off('gameOver', onGameOver);

    socketService.socket.off('gameReset', onGameReset);

    socketService.socket.off('forcedPosition', onForcedPosition);
  }

  void _validateSocketEventData(dynamic data) {
    if (data is! Map) {
      throw InvalidSocketResponseException();
    }
  }

  Map<String, dynamic> getData(Map<String, dynamic> data) {
    return data['data'];
  }

  void onPlayerJoined(dynamic data) async {
    try {
      logger.d('onPlayerJoined called with data $data runtimeType is ${data.runtimeType}');
      _validateSocketEventData(data);

      final dataModel = PlayerJoinedModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        PlayerJoinedEvent(
          playerId: dataModel.playerId,
          playerName: dataModel.playerName,
          playerList: dataModel.playerList.toSimpleModeEntity(),
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onPlayerJoined error.', error: e, stackTrace: stackTrace);
    }
  }

  void onPlayerLeft(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = PlayerLeftModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        PlayerLeftEvent(
          playerId: dataModel.leftPlayerId,
          newHostId: dataModel.newHostId,
          playerList: dataModel.playerList.toSimpleModeEntity(),
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onPlayerLeft error.', error: e, stackTrace: stackTrace);
    }
  }

  void onPlayerDisconnected(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = PlayerDisconnectedModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        PlayerDisconnectedEvent(
          disconnectedPlayerId: dataModel.disconnectedPlayerId,
          newHostId: dataModel.newHostId,
          playerList: dataModel.playerList.toSimpleModeEntity(),
          newLogs: dataModel.newLogs.map((e) => e.toEntity()).toList(),
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onPlayerDisconnected error.', error: e, stackTrace: stackTrace);
    }
  }

  void onPlayerReconnected(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = PlayerReconnectedModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        PlayerReconnectedEvent(
          playerId: dataModel.playerId,
          playerList: dataModel.playerList.toSimpleModeEntity(),
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onPlayerReconnected error.', error: e, stackTrace: stackTrace);
    }
  }

  void onPlayerRenamed(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = PlayerRenamedModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        PlayerRenamedEvent(playerId: dataModel.playerId, name: dataModel.name),
      );
    } catch (e, stackTrace) {
      logger.e('onPlayerRenamed error.', error: e, stackTrace: stackTrace);
    }
  }

  void onSpectatorJoined(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = SpectatorJoinedModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        SpectatorJoinedEvent(
          spectator: dataModel.spectator.toEntity(),
          spectatorList: dataModel.spectatorList.toEntity(),
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onSpectatorJoined error.', error: e, stackTrace: stackTrace);
    }
  }

  void onSpectatorLeft(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = SpectatorLeftModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        SpectatorLeftEvent(
          spectatorId: dataModel.spectatorId,
          spectatorList: dataModel.spectatorList.toEntity(),
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onSpectatorLeft error.', error: e, stackTrace: stackTrace);
    }
  }

  void onRoomSnapshot(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = RoomSnapshotModel.fromJson(getData(data as Map<String, dynamic>));
      final self = dataModel.you;

      final snapshot = RoomSnapshotEvent(
        state: dataModel.state,
        roundNumber: dataModel.roundNumber,
        boardWidth: dataModel.boardWidth,
        boardHeight: dataModel.boardHeight,
        destroyedTiles: dataModel.destroyedTiles,
        timeLimit: dataModel.timeLimit,
        remainingMs: dataModel.remainingMs,
        hostId: dataModel.hostId,
        playerList: dataModel.playerList.toSimpleModeEntity(),
        spectatorList: dataModel.spectatorList.toEntity(),
        logs: dataModel.logs.map((e) => e.toEntity()).toList(),
        isSpectator: dataModel.isSpectator,
        you: self == null
            ? null
            : RoomSnapshotSelf(
                x: self.x,
                y: self.y,
                hasPositioned: self.hasPositioned,
                bombTarget: self.bombTarget,
                throwOrder: self.throwOrder,
                isAlive: self.isAlive,
              ),
        ranking: dataModel.ranking.map((e) => e.toEntity()).toList(),
        winnerPosition: dataModel.winnerPosition,
      );

      // Park it before firing: on a mid-game entry this lands while the client
      // is still on the home screen, so nothing is listening yet.
      roomSnapshotCache.put(snapshot);
      eventBus.fire(snapshot);
    } catch (e, stackTrace) {
      logger.e('onRoomSnapshot error.', error: e, stackTrace: stackTrace);
    }
  }

  void onGameStarted(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = GameStartedModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        GameStartedEvent(
          boardWidth: dataModel.boardWidth,
          boardHeight: dataModel.boardHeight,
          state: dataModel.state,
          destroyedTiles: dataModel.destroyedTiles,
          timeLimit: dataModel.timeLimit,
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onGameStarted error.', error: e, stackTrace: stackTrace);
    }
  }

  void onPlayerReady(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = PlayerReadyModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        PlayerReadyEvent(
          playerId: dataModel.playerId,
          throwOrder: dataModel.throwOrder,
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onPlayerReady error.', error: e, stackTrace: stackTrace);
    }
  }

  void onPhaseChanged(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = PhaseChangedModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        PhaseChangedEvent(
          state: dataModel.state,
          timeLimit: dataModel.timeLimit,
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onPhaseChanged error.', error: e, stackTrace: stackTrace);
    }
  }

  void onRoundResolved(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = RoundResolvedModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        RoundResolvedEvent(
          explosionList: dataModel.explosionList.map((e) => e.toEntity()).toList(),
          playerList: dataModel.playerList.toSimpleModeEntity(),
          destroyedTiles: dataModel.destroyedTiles,
          newDestroyedTiles: dataModel.newDestroyedTiles,
          newLogs: dataModel.newLogs.map((e) => e.toEntity()).toList(),
          roundNumber: dataModel.roundNumber,
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onRoundResolved error.', error: e, stackTrace: stackTrace);
    }
  }

  void onGameOver(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = GameOverModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        GameOverEvent(
          ranking: dataModel.ranking.map((e) => e.toEntity()).toList(),
          winnerPosition: dataModel.winnerPosition,
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onGameOver error.', error: e, stackTrace: stackTrace);
    }
  }

  void onGameReset(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = GameResetModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        GameResetEvent(
          playerList: dataModel.playerList.toSimpleModeEntity(),
          spectatorList: dataModel.spectatorList.toEntity(),
          newHostId: dataModel.newHostId,
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onGameReset error.', error: e, stackTrace: stackTrace);
    }
  }

  void onForcedPosition(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = ForcedPositionModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        ForcedPositionEvent(
          position: dataModel.position,
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onForcedPosition error.', error: e, stackTrace: stackTrace);
    }
  }
}
