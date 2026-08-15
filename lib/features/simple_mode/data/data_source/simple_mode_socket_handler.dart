import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:boom_board/core/utils/socket_service.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/action_log_mapper.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/explosion_result_extension.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/simple_mode_result_extension.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/socket_event_data_mapper.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/forced_position_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/game_over_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/game_reset_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/game_started_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/phase_changd_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_dropped_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_joined_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_left_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/player_ready_model.dart';
import 'package:boom_board/features/simple_mode/data/models/models/socket_event/round_resolved_model.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/forced_position_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_over_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_reset_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/game_started_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/phase_changed_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_dropped_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_joined_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_left_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_ready_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/round_resolved_event.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

class SimpleModeSocketHandler {
  final SocketService socketService;

  Logger get logger {
    return GetIt.I<Logger>();
  }

  SimpleModeSocketHandler({required this.socketService});

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

    socketService.socket.on('playerDropped', onPlayerDropped);

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

    socketService.socket.off('playerDropped', onPlayerDropped);

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

  void onPlayerDropped(dynamic data) async {
    try {
      _validateSocketEventData(data);

      final dataModel = PlayerDroppedModel.fromJson(getData(data as Map<String, dynamic>));

      eventBus.fire(
        PlayerDroppedEvent(
          droppedPlayerId: dataModel.droppedPlayerId,
          newHostId: dataModel.newHostId,
          playerList: dataModel.playerList.toSimpleModeEntity(),
          newLogs: dataModel.newLogs.map((e) => e.toEntity()).toList(),
        ),
      );
    } catch (e, stackTrace) {
      logger.e('onPlayerDropped error.', error: e, stackTrace: stackTrace);
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
