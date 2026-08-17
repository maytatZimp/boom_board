import 'dart:async';
import 'dart:math' as math;

import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/entities/spectator_entity.dart';
import 'package:boom_board/core/domain/use_cases/get_current_player_id_use_case.dart';
import 'package:boom_board/core/domain/use_cases/join_room_use_case.dart';
import 'package:boom_board/core/domain/use_cases/leave_room_use_case.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/core/events/models/socket_connected_error_event.dart';
import 'package:boom_board/core/events/models/socket_connected_event.dart';
import 'package:boom_board/core/events/models/socket_disconnected_event.dart';
import 'package:boom_board/core/events/models/socket_reconnect_attempt_event.dart';
import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/domain/constants/animation_constant.dart' as anim_constant;
import 'package:boom_board/features/simple_mode/domain/entities/action_log_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/animation/active_bomb_drop_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/animation/active_hide_animation_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/animation/active_tile_animation_entity.dart';
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
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_result_entity.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/consume_room_snapshot_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/reset_game_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/set_position_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/start_game_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/throw_bomb_use_case.dart';
import 'package:boom_board/features/simple_mode/presentation/arguments/simple_mode_arguments.dart';
import 'package:boom_board/routes/app_pages.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

abstract class SimpleModeIds {
  static const String playerListPanel = 'PLAYER_LIST_PANEL';
  static const String actionLogPanel = 'ACTION_LOG_PANEL';
  static const String boardPanel = 'BOARD_PANEL';
  static const String controlPanel = 'CONTROL_PANEL';
  static const String connectionOverlay = 'CONNECTION_OVERLAY';
}

/// How the client currently stands with the server, as far as the player is
/// concerned. Losing the socket no longer means losing the game -- the seat is
/// held server-side, so this only drives an overlay.
enum RoomConnectionState {
  connected,

  /// Socket is down, or up but not yet re-bound to our seat. Auto-retries are
  /// still in play.
  reconnecting,

  /// The socket's retries ran out, or the rejoin was refused. The player now
  /// chooses: retry by hand, or leave.
  reconnectFailed,
}

class SimpleModeController extends GetxController {
  String roomCode = '';
  String hostId = '';
  GameState currentState = GameState.lobby;
  int currentRound = 1;
  List<SimpleModePlayerEntity> playerList = [];
  List<SpectatorEntity> spectatorList = [];
  bool isSpectator = false;
  RoomConnectionState connectionState = RoomConnectionState.connected;
  String? connectionError;
  bool _rejoinInFlight = false;
  List<ActionLogEntity> actionLogList = [];
  List<Coordinate> destroyedTile = [];
  Coordinate? hoveredTile;
  Coordinate? lockedBombTarget;
  Coordinate? winnerPosition;
  bool showEndgameOverlay = true;
  bool hideLocalPlayerIcon = false;
  List<SimpleModeResultEntity> finalRanking = [];
  int currentPhaseTimeLimit = 0;
  String currentTimerKey = '';

  final ScrollController logScrollController = ScrollController();
  StreamSubscription? playerJoinEventSubs;
  StreamSubscription? playerLeftEventSubs;
  StreamSubscription? playerReadyEventSubs;
  StreamSubscription? playerDisconnectedEventSubs;
  StreamSubscription? playerReconnectedEventSubs;
  StreamSubscription? playerRenamedEventSubs;
  StreamSubscription? spectatorJoinedEventSubs;
  StreamSubscription? spectatorLeftEventSubs;
  StreamSubscription? roomSnapshotEventSubs;
  StreamSubscription? gameStartedEventSubs;
  StreamSubscription? phaseChangedEventSubs;
  StreamSubscription? roundResolvedEventSubs;
  StreamSubscription? gameOverEventSubs;
  StreamSubscription? gameResetEventSubs;
  StreamSubscription? socketDisconnectedSubs;
  StreamSubscription? socketErrorSubs;
  StreamSubscription? socketConnectedSubs;
  StreamSubscription? socketReconnectAttemptSubs;
  StreamSubscription? forcedPositionSubs;

  // --- ANIMATION STATE ---
  // We store the coordinates of bombs currently falling
  List<ActiveBombDropEntity> activeBombDrops = [];
  List<ActiveTileAnimationEntity> activeExplosions = [];
  List<ActiveTileAnimationEntity> activeDeaths = [];
  List<ActiveTileAnimationEntity> activeLasers = [];
  List<ActiveHideAnimationEntity> activeHideAnimations = [];

  bool get isHost {
    return hostId == localPlayerId;
  }

  String get localPlayerId {
    return GetIt.I<GetCurrentPlayerIdUseCase>().call() ?? '';
  }

  /// The name to present when re-entering the room. Prefers the roster (it
  /// tracks renames) and falls back to the persisted slot, which is all that
  /// survives a page reload.
  String get localPlayerName {
    return localPlayer?.name ?? GetIt.I<IdentityStore>().credentials?.playerName ?? '';
  }

  bool get isReconnecting => connectionState == RoomConnectionState.reconnecting;

  bool get isConnectionLost => connectionState != RoomConnectionState.connected;

  SimpleModePlayerEntity? get localPlayer {
    try {
      return playerList.firstWhere((p) => p.id == localPlayerId);
    } catch (e) {
      return null;
    }
  }

  Logger get logger {
    return GetIt.I<Logger>();
  }

  @override
  void onInit() {
    super.onInit();
    if (Get.arguments is! SimpleModeArguments) {
      Get.offAllNamed(home);
      return;
    }
    final args = Get.arguments as SimpleModeArguments;
    roomCode = args.roomCode;
    hostId = args.hostId;
    playerList = args.playerList;
    spectatorList = args.spectatorList;
    isSpectator = args.isSpectator;

    subscribeListener();

    // A mid-game entry gets its snapshot the instant the server acks, which is
    // before this controller exists. Pick up anything that landed in the gap.
    final pendingSnapshot = GetIt.I<ConsumeRoomSnapshotUseCase>().call();
    if (pendingSnapshot != null) {
      applyRoomSnapshot(pendingSnapshot);
    }
  }

  @override
  void onClose() {
    super.onClose();

    unsubscribeListener();
  }

  void subscribeListener() {
    playerJoinEventSubs = eventBus.on<PlayerJoinedEvent>().listen(onPlayerJoinedEventReceived);
    playerLeftEventSubs = eventBus.on<PlayerLeftEvent>().listen(onPlayerLeftEventReceived);
    playerReadyEventSubs = eventBus.on<PlayerReadyEvent>().listen(onPlayerReadyEventReceived);
    playerDisconnectedEventSubs = eventBus.on<PlayerDisconnectedEvent>().listen(onPlayerDisconnectedEventReceived);
    playerReconnectedEventSubs = eventBus.on<PlayerReconnectedEvent>().listen(onPlayerReconnectedEventReceived);
    playerRenamedEventSubs = eventBus.on<PlayerRenamedEvent>().listen(onPlayerRenamedEventReceived);
    spectatorJoinedEventSubs = eventBus.on<SpectatorJoinedEvent>().listen(onSpectatorJoinedEventReceived);
    spectatorLeftEventSubs = eventBus.on<SpectatorLeftEvent>().listen(onSpectatorLeftEventReceived);
    roomSnapshotEventSubs = eventBus.on<RoomSnapshotEvent>().listen(onRoomSnapshotEventReceived);
    gameStartedEventSubs = eventBus.on<GameStartedEvent>().listen(onGameStartEventReceived);
    phaseChangedEventSubs = eventBus.on<PhaseChangedEvent>().listen(onPhaseChangedEventReceived);
    roundResolvedEventSubs = eventBus.on<RoundResolvedEvent>().listen(onRoundResolvedEventReceived);
    gameOverEventSubs = eventBus.on<GameOverEvent>().listen(onGameOverEventReceived);
    gameResetEventSubs = eventBus.on<GameResetEvent>().listen(onGameResetEventReceived);
    socketDisconnectedSubs = eventBus.on<SocketDisconnectedEvent>().listen(_onConnectionLostReceived);
    socketErrorSubs = eventBus.on<SocketConnectedErrorEvent>().listen(_onConnectionLostReceived);
    socketConnectedSubs = eventBus.on<SocketConnectedEvent>().listen(_onSocketReconnected);
    socketReconnectAttemptSubs = eventBus.on<SocketReconnectAttemptEvent>().listen(_onReconnectAttempt);
    forcedPositionSubs = eventBus.on<ForcedPositionEvent>().listen(onForcedPositionReceived);
  }

  void unsubscribeListener() {
    playerJoinEventSubs?.cancel();
    playerLeftEventSubs?.cancel();
    playerReadyEventSubs?.cancel();
    playerDisconnectedEventSubs?.cancel();
    playerReconnectedEventSubs?.cancel();
    playerRenamedEventSubs?.cancel();
    spectatorJoinedEventSubs?.cancel();
    spectatorLeftEventSubs?.cancel();
    roomSnapshotEventSubs?.cancel();
    gameStartedEventSubs?.cancel();
    phaseChangedEventSubs?.cancel();
    roundResolvedEventSubs?.cancel();
    gameOverEventSubs?.cancel();
    gameResetEventSubs?.cancel();
    socketDisconnectedSubs?.cancel();
    socketErrorSubs?.cancel();
    socketConnectedSubs?.cancel();
    socketReconnectAttemptSubs?.cancel();
    forcedPositionSubs?.cancel();
  }

  void resetRound() {
    actionLogList = [];
    destroyedTile = [];
    finalRanking = [];
    showEndgameOverlay = true;
    currentState = GameState.lobby;
    lockedBombTarget = null;
    currentRound = 1;
    winnerPosition = null;
  }

  /// Swaps in a server roster while keeping the one thing the server never
  /// sends back: our own tile. Positions are private, so a broadcast roster
  /// would otherwise blank out the local avatar every time anyone dropped,
  /// returned, or was renamed.
  void _applyServerPlayerList(List<SimpleModePlayerEntity> serverList) {
    final localX = localPlayer?.x;
    final localY = localPlayer?.y;

    playerList = serverList;

    if (localX == null && localY == null) return;
    final index = playerList.indexWhere((p) => p.id == localPlayerId);
    if (index != -1) {
      playerList[index] = playerList[index].copyWith(x: localX, y: localY);
    }
  }

  void startGame() async {
    if (playerList.length <= 1) return;
    if (isHost) {
      try {
        await GetIt.I<StartGameUseCase>().call(StartGameParams(roomCode: roomCode));
      } catch (e, stackTrace) {
        logger.e('startGame error.', error: e, stackTrace: stackTrace);
      }
    }
  }

  void setPosition(int x, int y) async {
    SimpleModePlayerEntity? rollbackPlayerData;
    try {
      if (localPlayer?.hasPositioned == true) return;
      // The board is 8x8 with indices 0..7, so 8 is off-board.
      if (x > 7 || y > 7 || x < 0 || y < 0) return;

      // Optimistic UI update: instantly hide the hover effect
      setHoveredTile(null);

      final index = playerList.indexWhere((e) => e.id == localPlayerId);
      if (index != -1) {
        rollbackPlayerData = playerList[index].copyWith();
        playerList[index] = playerList[index].copyWith(hasPositioned: true, x: x, y: y);
      }
      await GetIt.I<SetPositionUseCase>().call(
        SetPositionParams(
          roomCode: roomCode,
          x: x,
          y: y,
        ),
      );

      update([SimpleModeIds.playerListPanel, SimpleModeIds.boardPanel]);

      triggerHideAnimation(localPlayerId, true, targetX: x, targetY: y);
    } catch (e, stackTrace) {
      logger.e('setPosition error.', error: e, stackTrace: stackTrace);
      final index = playerList.indexWhere((e) => e.id == localPlayerId);
      if (index != -1 && rollbackPlayerData != null) {
        playerList[index] = rollbackPlayerData;
      }
    }
  }

  void throwBomb(int x, int y) async {
    try {
      if (localPlayer?.hasThrowBomb == true) return;
      // The board is 8x8 with indices 0..7, so 8 is off-board. Same guard as
      // setPosition -- one tap handler feeds both, so they validate alike.
      if (x > 7 || y > 7 || x < 0 || y < 0) return;

      setHoveredTile(null);

      final throwOrder = await GetIt.I<ThrowBombUseCase>().call(
        ThrowBombParams(
          roomCode: roomCode,
          x: x,
          y: y,
        ),
      );
      lockedBombTarget = Coordinate(x: x, y: y);
      final index = playerList.indexWhere((e) => e.id == localPlayerId);
      if (index != -1) {
        playerList[index] = playerList[index].copyWith(
          hasThrowBomb: true,
          throwOrder: throwOrder,
        );
      }
      update([SimpleModeIds.playerListPanel]);
    } catch (e, stackTrace) {
      logger.e('throwBomb error.', error: e, stackTrace: stackTrace);
    }
  }

  void backToLobby() async {
    try {
      await GetIt.I<ResetGameUseCase>().call(ResetGameParams(roomCode: roomCode));
    } catch (e, stackTrace) {
      logger.e('backToLobby error.', error: e, stackTrace: stackTrace);
    }
  }

  void leaveRoom() async {
    try {
      await GetIt.I<LeaveRoomUseCase>().call(LeaveRoomParams(gameMode: GameMode.simple));
    } catch (e, stackTrace) {
      logger.e('leaveRoom error.', error: e, stackTrace: stackTrace);
    }
  }

  String getPhaseText() {
    if (currentState == GameState.position) {
      return 'Phase:Hide';
    } else if (currentState == GameState.attack) {
      return 'Phase:Attack';
    } else {
      return '';
    }
  }

  void onPlayerJoinedEventReceived(PlayerJoinedEvent event) {
    logger.d('onPlayerJoinedEventReceived called with $event');
    playerList = event.playerList;
    update([SimpleModeIds.playerListPanel, SimpleModeIds.controlPanel]);
  }

  void onPlayerLeftEventReceived(PlayerLeftEvent event) {
    logger.d('onPlayerLeftEventReceived called with $event');
    playerList = event.playerList;
    hostId = event.newHostId;
    update([SimpleModeIds.playerListPanel, SimpleModeIds.controlPanel]);
  }

  void onPlayerReadyEventReceived(PlayerReadyEvent event) {
    logger.d('onPlayerReadyEventReceived called with $event');
    final index = playerList.indexWhere((e) => e.id == event.playerId);
    if (index != -1) {
      if (currentState == GameState.position) {
        playerList[index] = playerList[index].copyWith(hasPositioned: true);

        if (event.playerId != localPlayerId) {
          triggerHideAnimation(event.playerId, false);
        }
      } else if (currentState == GameState.attack) {
        playerList[index] = playerList[index].copyWith(
          hasThrowBomb: true,
          throwOrder: event.throwOrder,
        );
      }
      update([SimpleModeIds.playerListPanel]);
    }
  }

  void onPlayerDisconnectedEventReceived(PlayerDisconnectedEvent event) {
    logger.d('onPlayerDisconnectedEventReceived called with $event');
    // Connection status only. They keep their tile, their life, and their shot
    // at winning -- the roster just shows them as offline.
    _applyServerPlayerList(event.playerList);
    hostId = event.newHostId;
    actionLogList.addAll(event.newLogs);
    update([SimpleModeIds.playerListPanel, SimpleModeIds.actionLogPanel, SimpleModeIds.controlPanel]);

    _scrollToBottom();
  }

  void onPlayerReconnectedEventReceived(PlayerReconnectedEvent event) {
    logger.d('onPlayerReconnectedEventReceived called with $event');
    _applyServerPlayerList(event.playerList);
    update([SimpleModeIds.playerListPanel, SimpleModeIds.controlPanel]);
  }

  void onPlayerRenamedEventReceived(PlayerRenamedEvent event) {
    logger.d('onPlayerRenamedEventReceived called with $event');
    final index = playerList.indexWhere((p) => p.id == event.playerId);
    if (index != -1) {
      playerList[index] = playerList[index].copyWith(name: event.name);
      update([SimpleModeIds.playerListPanel]);
      return;
    }

    final spectatorIndex = spectatorList.indexWhere((s) => s.id == event.playerId);
    if (spectatorIndex != -1) {
      spectatorList[spectatorIndex] = SpectatorEntity(id: event.playerId, name: event.name);
      update([SimpleModeIds.playerListPanel]);
    }
  }

  void onSpectatorJoinedEventReceived(SpectatorJoinedEvent event) {
    logger.d('onSpectatorJoinedEventReceived called with $event');
    spectatorList = event.spectatorList;
    update([SimpleModeIds.playerListPanel]);
  }

  void onSpectatorLeftEventReceived(SpectatorLeftEvent event) {
    logger.d('onSpectatorLeftEventReceived called with $event');
    spectatorList = event.spectatorList;
    update([SimpleModeIds.playerListPanel]);
  }

  void onRoomSnapshotEventReceived(RoomSnapshotEvent event) {
    logger.d('onRoomSnapshotEventReceived called with $event');
    // The cache may still be holding this same snapshot for a controller that
    // is about to mount; drop it, we've handled it.
    GetIt.I<ConsumeRoomSnapshotUseCase>().call();
    applyRoomSnapshot(event);
  }

  /// Rebuilds the whole room view from a server snapshot. Used both when
  /// resuming a seat after a drop and when arriving mid-game as a spectator --
  /// the payload is the same, only `isSpectator` and `isAlive` differ.
  void applyRoomSnapshot(RoomSnapshotEvent event) {
    isSpectator = event.isSpectator;
    currentState = event.state;
    currentRound = event.roundNumber;
    destroyedTile = event.destroyedTiles;
    if (event.hostId.isNotEmpty) hostId = event.hostId;
    playerList = event.playerList;
    spectatorList = event.spectatorList;
    // The snapshot carries the current round's logs, so replace rather than
    // append -- appending would duplicate whatever we already saw this round.
    actionLogList = event.logs;
    finalRanking = event.ranking;
    winnerPosition = event.winnerPosition;
    showEndgameOverlay = event.state == GameState.end;
    lockedBombTarget = null;

    // Clear any animation left mid-flight by the drop; nothing that follows
    // would ever remove it.
    activeBombDrops = [];
    activeExplosions = [];
    activeDeaths = [];
    activeLasers = [];
    activeHideAnimations = [];

    final self = event.you;
    if (self != null) {
      final index = playerList.indexWhere((p) => p.id == localPlayerId);
      if (index != -1) {
        playerList[index] = playerList[index].copyWith(
          x: self.x,
          y: self.y,
          hasPositioned: self.hasPositioned,
          hasThrowBomb: self.bombTarget != null,
          throwOrder: self.throwOrder,
          clearThrowOrder: self.throwOrder == null,
          isAlive: self.isAlive,
        );
      }
      lockedBombTarget = self.bombTarget;
    }

    // The phase clock never paused while we were away, so start the bar at
    // whatever is left of it rather than from full.
    final isTimedPhase = event.state == GameState.position || event.state == GameState.attack;
    if (isTimedPhase && event.remainingMs > 0) {
      _startPhaseTimer((event.remainingMs / 1000).ceil());
    } else {
      _clearPhaseTimer();
    }

    connectionState = RoomConnectionState.connected;
    connectionError = null;

    update([
      SimpleModeIds.playerListPanel,
      SimpleModeIds.actionLogPanel,
      SimpleModeIds.boardPanel,
      SimpleModeIds.controlPanel,
      SimpleModeIds.connectionOverlay,
    ]);

    _scrollToBottom();
  }

  void onGameStartEventReceived(GameStartedEvent event) {
    logger.d('onGameStartEventReceived called with $event');
    currentState = event.state;
    destroyedTile = event.destroyedTiles;
    update([SimpleModeIds.controlPanel, SimpleModeIds.boardPanel]);
    _startPhaseTimer(event.timeLimit);
  }

  void onPhaseChangedEventReceived(PhaseChangedEvent event) {
    logger.d('onPhaseChangedEventReceived called with $event');
    currentState = event.state;

    if (currentState == GameState.attack) {
      _startPhaseTimer(event.timeLimit);
      for (int i = 0; i < playerList.length; i++) {
        bool shouldTriggerHideAnimation = playerList[i].hasPositioned == false && playerList[i].id != localPlayerId;
        playerList[i] = playerList[i].copyWith(
          hasThrowBomb: false,
          hasPositioned: true,
          clearThrowOrder: true,
        );
        if (shouldTriggerHideAnimation) {
          triggerHideAnimation(playerList[i].id, false);
        }
      }
      update([SimpleModeIds.playerListPanel]);
    }

    update([SimpleModeIds.controlPanel, SimpleModeIds.boardPanel]);
  }

  void onRoundResolvedEventReceived(RoundResolvedEvent event) async {
    logger.d('onRoundResolvedEventReceived called with $event');

    // Temporarily lock UI into a 'process' state so players can't click things
    currentState = GameState.process;
    _clearPhaseTimer();
    update([SimpleModeIds.controlPanel]);

    int? localPlayerX = localPlayer?.x;
    int? localPlayerY = localPlayer?.y;
    // SEQUENTIAL EXPLOSION LOGIC
    // Even in a temporary UI, we use async/await inside a loop to process them one-by-one
    for (var explosion in event.explosionList) {
      // NOTE: When you build the real UI, this is where you trigger the
      // visual bomb explosion animation on the specific grid coordinates (explosion.x, explosion.y)

      int startX = -1;
      int startY = -1;

      if (explosion.bomberId == localPlayerId) {
        startX = localPlayerX ?? -1;
        startY = localPlayerY ?? -1;
      }
      triggerBombAnimation(
        explosion.bomberId,
        startX,
        startY,
        explosion.x,
        explosion.y,
      );

      // Wait for the "animation" to finish before evaluating the result
      await Future.delayed(anim_constant.bombDrop);

      if (explosion.bomberId == localPlayerId) {
        lockedBombTarget = null;
      }

      triggerExplosionEffect(explosion.x, explosion.y);

      if (explosion.isHit && explosion.victimId != null) {
        // Update the victim's status in real-time
        final victimIndex = playerList.indexWhere((p) => p.id == explosion.victimId);
        if (victimIndex != -1) {
          playerList[victimIndex] = playerList[victimIndex].copyWith(isAlive: false);
          update([SimpleModeIds.playerListPanel]);

          triggerDeathAnimation(explosion.x, explosion.y);
        }
      }

      await Future.delayed(anim_constant.explosionSettle);
    }

    // --- ORBITAL LASER PHASE ---
    if (event.newDestroyedTiles.isNotEmpty) {
      // Fire the animation!
      triggerLaserAnimation(event.newDestroyedTiles);

      // Wait for the beam to finish firing
      await Future.delayed(anim_constant.destroyedTileDelay);

      // Now permanently scorch the tiles so they stay on fire
      destroyedTile = event.destroyedTiles;
      update([SimpleModeIds.boardPanel]);
    }

    // Final Sync: Ensure our local list perfectly matches the server's master list
    playerList = event.playerList;
    // Replacing the whole player list from server will delete our localPlayer x and y value.
    // This is to put the x and y value back.
    int index = playerList.indexWhere((e) => e.id == localPlayerId);
    final currentPlayer = localPlayer;
    if (index != -1 && currentPlayer != null) {
      playerList[index] = currentPlayer.copyWith(
        x: localPlayerX,
        y: localPlayerY,
      );
    }
    actionLogList.addAll(event.newLogs);

    currentRound = event.roundNumber;
    update([SimpleModeIds.playerListPanel, SimpleModeIds.actionLogPanel, SimpleModeIds.controlPanel]);

    _scrollToBottom();
  }

  void onGameOverEventReceived(GameOverEvent event) {
    logger.d('onGameOverEventReceived called with $event');
    currentState = GameState.end;
    finalRanking = event.ranking;
    winnerPosition = event.winnerPosition;
    showEndgameOverlay = true;
    lockedBombTarget = null;

    _clearPhaseTimer();
    update([SimpleModeIds.controlPanel, SimpleModeIds.boardPanel]);
  }

  void onGameResetEventReceived(GameResetEvent event) {
    logger.d('onGameResetEventReceived called with $event');
    resetRound();
    playerList = event.playerList;
    // Everyone who watched the last game is a player now, so nobody is a
    // spectator going into the lobby.
    spectatorList = event.spectatorList;
    isSpectator = false;
    if (event.newHostId.isNotEmpty) hostId = event.newHostId;
    update([
      SimpleModeIds.controlPanel,
      SimpleModeIds.playerListPanel,
      SimpleModeIds.boardPanel,
      SimpleModeIds.actionLogPanel,
    ]);
  }

  void onForcedPositionReceived(ForcedPositionEvent event) {
    logger.d('onForcedPositionReceived called with $event');
    int index = playerList.indexWhere((e) => e.id == localPlayerId);
    if (index != -1) {
      playerList[index] = playerList[index].copyWith(
        hasPositioned: true,
        x: event.position.x,
        y: event.position.y,
      );
      triggerHideAnimation(
        playerList[index].id,
        true,
        targetX: event.position.x,
        targetY: event.position.y,
      );
    }
  }

  // --- CONNECTION LOSS & RECOVERY ---
  //
  // Dropping the socket no longer means losing the game: the server holds the
  // seat alive on the board, auto-positions it, and simply doesn't throw for
  // it. So a drop shows an overlay and we try to climb back into the same
  // seat -- never a bounce back to the home screen.

  void _onConnectionLostReceived(dynamic event) {
    logger.d('Connection lost. Holding the room and attempting to reconnect.');
    if (connectionState == RoomConnectionState.connected) {
      connectionState = RoomConnectionState.reconnecting;
      connectionError = null;
      _clearPhaseTimer();
      update([SimpleModeIds.connectionOverlay, SimpleModeIds.controlPanel]);
    }
  }

  void _onReconnectAttempt(SocketReconnectAttemptEvent event) {
    logger.d('Reconnect attempt #${event.attemptCount}');
    if (connectionState != RoomConnectionState.reconnecting) {
      connectionState = RoomConnectionState.reconnecting;
      connectionError = null;
      update([SimpleModeIds.connectionOverlay, SimpleModeIds.controlPanel]);
    }
  }

  void _onSocketReconnected(SocketConnectedEvent event) {
    logger.d('Socket is back up. Reclaiming our seat in $roomCode.');
    // The socket came back with a fresh id and no idea who we are, so the seat
    // is only ours again once joinRoom validates the stored credentials.
    rejoinRoom();
  }

  /// Re-enters the room with the stored credentials. Drives both the automatic
  /// retry after the socket reconnects and the manual "Reconnect" button.
  Future<void> rejoinRoom() async {
    if (_rejoinInFlight) return;
    _rejoinInFlight = true;

    connectionState = RoomConnectionState.reconnecting;
    connectionError = null;
    update([SimpleModeIds.connectionOverlay]);

    try {
      final result = await GetIt.I<JoinRoomUseCase>().call(
        JoinRoomParams(playerName: localPlayerName, roomCode: roomCode),
      );

      // Only the fields the snapshot doesn't carry are taken from the ack --
      // the private roomSnapshot that follows is the authoritative view and
      // will overwrite the rest.
      isSpectator = result.isSpectator;
      hostId = result.hostId;

      connectionState = RoomConnectionState.connected;
      connectionError = null;
      update([SimpleModeIds.connectionOverlay, SimpleModeIds.controlPanel, SimpleModeIds.playerListPanel]);
    } on BBServerException catch (e, stackTrace) {
      logger.e('rejoinRoom rejected by server.', error: e, stackTrace: stackTrace);
      connectionState = RoomConnectionState.reconnectFailed;
      connectionError = switch (e.errorType) {
        'ROOM_NOT_FOUND' => 'That room no longer exists.',
        'SECRET_MISMATCH' => 'Your seat could not be verified.',
        'ROOM_IS_FULL' || 'ROOM_IS_FULL_OF_SPECTATORS' => 'The room is full.',
        _ => 'The server refused the rejoin.',
      };
      update([SimpleModeIds.connectionOverlay]);
    } catch (e, stackTrace) {
      logger.e('rejoinRoom error.', error: e, stackTrace: stackTrace);
      connectionState = RoomConnectionState.reconnectFailed;
      connectionError = 'Could not reach the server.';
      update([SimpleModeIds.connectionOverlay]);
    } finally {
      _rejoinInFlight = false;
    }
  }

  /// Escape hatch from the reconnect overlay: give up the seat and go home.
  Future<void> abandonRoom() async {
    try {
      await GetIt.I<LeaveRoomUseCase>().call(LeaveRoomParams(gameMode: GameMode.simple));
    } catch (e, stackTrace) {
      // Expected while offline -- the use case still unbinds and clears the
      // stored credentials, which is the part that matters here.
      logger.d('abandonRoom leaveRoom failed (offline). $e $stackTrace');
    }
    Get.offAllNamed(home);
  }

  void setHoveredTile(Coordinate? tile) {
    hoveredTile = tile;
    update([SimpleModeIds.boardPanel]);
  }

  void _scrollToBottom() {
    // We use addPostFrameCallback because we need to wait for Flutter to
    // actually build the new log text widgets before we can scroll past them!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (logScrollController.hasClients) {
        logScrollController.animateTo(
          logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void toggleEndgameOverlay() {
    showEndgameOverlay = !showEndgameOverlay;
    // We update both the board (to hide the overlay) and the control panel (to change the button text)
    update([SimpleModeIds.boardPanel, SimpleModeIds.controlPanel]);
  }

  void toggleHideLocalPlayerIcon() {
    hideLocalPlayerIcon = !hideLocalPlayerIcon;
    // We update both the board (to hide the icon) and the control panel (to change the button text)
    update([SimpleModeIds.boardPanel, SimpleModeIds.controlPanel]);
  }

  // Helper to trigger the animation
  void triggerBombAnimation(String bomberId, int startX, int startY, int targetX, int targetY) {
    final drop = ActiveBombDropEntity(
      id: DateTime.now().millisecondsSinceEpoch.toString() + bomberId,
      bomberId: bomberId,
      startX: startX,
      startY: startY,
      targetX: targetX,
      targetY: targetY,
    );

    activeBombDrops.add(drop);
    update([SimpleModeIds.boardPanel]);

    // Delay for the animation duration. When it finishes, we remove the bomb!
    Future.delayed(anim_constant.bombDrop, () {
      activeBombDrops.removeWhere((b) => b.id == drop.id);
      update([SimpleModeIds.boardPanel]);
    });
  }

  void triggerExplosionEffect(int x, int y) {
    final id = 'exp_${x}_${y}_${DateTime.now().millisecondsSinceEpoch}';
    activeExplosions.add(ActiveTileAnimationEntity(id: id, x: x, y: y));
    update([SimpleModeIds.boardPanel]);

    // Delay for the animation duration. When it finishes, we remove the explosion!
    Future.delayed(anim_constant.explosion, () {
      activeExplosions.removeWhere((c) => c.x == x && c.y == y);
      update([SimpleModeIds.boardPanel]);
    });
  }

  void triggerDeathAnimation(int x, int y) {
    final id = 'death_${x}_${y}_${DateTime.now().millisecondsSinceEpoch}';
    activeDeaths.add(ActiveTileAnimationEntity(id: id, x: x, y: y));
    update([SimpleModeIds.boardPanel]);

    // Delay for the animation duration. When it finishes, we remove the ghost!
    Future.delayed(anim_constant.deathGhost, () {
      activeDeaths.removeWhere((c) => c.x == x && c.y == y);
      update([SimpleModeIds.boardPanel]);
    });
  }

  void triggerLaserAnimation(List<Coordinate> tiles) {
    for (var tile in tiles) {
      final id = 'laser_${tile.x}_${tile.y}_${DateTime.now().millisecondsSinceEpoch}';
      activeLasers.add(ActiveTileAnimationEntity(id: id, x: tile.x, y: tile.y));
    }
    update([SimpleModeIds.boardPanel]);

    // Delay for the animation duration. When it finishes, we remove the laser!
    Future.delayed(anim_constant.laserBeam, () {
      activeLasers.clear(); // Clear all lasers at once
      update([SimpleModeIds.boardPanel]);
    });
  }

  void triggerHideAnimation(String playerId, bool isLocal, {int? targetX, int? targetY}) {
    final random = math.Random();
    final side = random.nextInt(4); // 0: Top, 1: Right, 2: Bottom, 3: Left

    int startX, startY, edgeX, edgeY;
    final randPos = random.nextInt(8); // Random position along the chosen side

    if (side == 0) {
      // Spawns Top
      startX = randPos;
      startY = -2;
      edgeX = randPos;
      edgeY = -1;
    } else if (side == 1) {
      // Spawns Right
      startX = 9;
      startY = randPos;
      edgeX = 8;
      edgeY = randPos;
    } else if (side == 2) {
      // Spawns Bottom
      startX = randPos;
      startY = 9;
      edgeX = randPos;
      edgeY = 8;
    } else {
      // Spawns Left
      startX = -2;
      startY = randPos;
      edgeX = -1;
      edgeY = randPos;
    }

    final anim = ActiveHideAnimationEntity(
      id: 'hide_${playerId}_${DateTime.now().millisecondsSinceEpoch}',
      playerId: playerId,
      isLocal: isLocal,
      startX: startX,
      startY: startY,
      edgeX: edgeX,
      edgeY: edgeY,
      targetX: targetX,
      targetY: targetY,
    );

    activeHideAnimations.add(anim);
    update([SimpleModeIds.boardPanel]);

    Future.delayed(anim_constant.hideSequence, () {
      activeHideAnimations.removeWhere((a) => a.id == anim.id);
      update([SimpleModeIds.boardPanel]);
    });
  }

  void _startPhaseTimer(int seconds) {
    currentPhaseTimeLimit = seconds;
    currentTimerKey = 'timer_${currentState}_${DateTime.now().millisecondsSinceEpoch}';
    update([SimpleModeIds.controlPanel]);
  }

  void _clearPhaseTimer() {
    currentPhaseTimeLimit = -1;
  }
}
