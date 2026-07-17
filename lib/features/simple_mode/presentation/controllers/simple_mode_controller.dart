import 'dart:async';
import 'dart:math' as math;

import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/use_cases/get_current_player_id_use_case.dart';
import 'package:boom_board/core/domain/use_cases/leave_room_use_case.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/core/events/models/socket_connected_error_event.dart';
import 'package:boom_board/core/events/models/socket_disconnected_event.dart';
import 'package:boom_board/core/style/app_colors.dart';
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
import 'package:boom_board/features/simple_mode/domain/entities/events/player_dropped_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_joined_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_left_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/player_ready_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/events/round_resolved_event.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_result_entity.dart';
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
}

class SimpleModeController extends GetxController {
  String roomCode = '';
  String hostId = '';
  GameState currentState = GameState.lobby;
  int currentRound = 1;
  List<SimpleModePlayerEntity> playerList = [];
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
  StreamSubscription? playerDroppedEventSubs;
  StreamSubscription? gameStartedEventSubs;
  StreamSubscription? phaseChangedEventSubs;
  StreamSubscription? roundResolvedEventSubs;
  StreamSubscription? gameOverEventSubs;
  StreamSubscription? gameResetEventSubs;
  StreamSubscription? socketDisconnectedSubs;
  StreamSubscription? socketErrorSubs;
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

    subscribeListener();
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
    playerDroppedEventSubs = eventBus.on<PlayerDroppedEvent>().listen(onPlayerDroppedEventReceived);
    gameStartedEventSubs = eventBus.on<GameStartedEvent>().listen(onGameStartEventReceived);
    phaseChangedEventSubs = eventBus.on<PhaseChangedEvent>().listen(onPhaseChangedEventReceived);
    roundResolvedEventSubs = eventBus.on<RoundResolvedEvent>().listen(onRoundResolvedEventReceived);
    gameOverEventSubs = eventBus.on<GameOverEvent>().listen(onGameOverEventReceived);
    gameResetEventSubs = eventBus.on<GameResetEvent>().listen(onGameResetEventReceived);
    socketDisconnectedSubs = eventBus.on<SocketDisconnectedEvent>().listen(_onConnectionLostReceived);
    socketErrorSubs = eventBus.on<SocketConnectedErrorEvent>().listen(_onConnectionLostReceived);
    forcedPositionSubs = eventBus.on<ForcedPositionEvent>().listen(onForcedPositionReceived);
  }

  void unsubscribeListener() {
    playerJoinEventSubs?.cancel();
    playerLeftEventSubs?.cancel();
    playerReadyEventSubs?.cancel();
    playerDroppedEventSubs?.cancel();
    gameStartedEventSubs?.cancel();
    phaseChangedEventSubs?.cancel();
    roundResolvedEventSubs?.cancel();
    gameOverEventSubs?.cancel();
    gameResetEventSubs?.cancel();
    socketDisconnectedSubs?.cancel();
    socketErrorSubs?.cancel();
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
      if (x > 8 || y > 8 || x < 0 || y < 0) return;

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

  void onPlayerDroppedEventReceived(PlayerDroppedEvent event) {
    logger.d('onPlayerDroppedEventReceived called with $event');
    playerList = event.playerList;
    hostId = event.newHostId;
    actionLogList.addAll(event.newLogs);
    update([SimpleModeIds.playerListPanel, SimpleModeIds.actionLogPanel, SimpleModeIds.controlPanel]);

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

  void _onConnectionLostReceived(dynamic event) {
    logger.e('Socket disconnected! Navigating back to home screen.');
    Get.offAllNamed(home);

    Get.snackbar(
      'Connection Lost',
      'You have been disconnected from the server.',
      backgroundColor: retroRed,
      colorText: textOrIconColor,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
    );
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
