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
import 'package:boom_board/core/events/models/page_resumed_event.dart';
import 'package:boom_board/core/events/models/socket_connected_error_event.dart';
import 'package:boom_board/core/events/models/socket_connected_event.dart';
import 'package:boom_board/core/events/models/socket_disconnected_event.dart';
import 'package:boom_board/core/events/models/socket_reconnect_attempt_event.dart';
import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/game_state.dart';
import 'package:boom_board/features/simple_mode/data/models/enum/log_action_type.dart';
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
import 'package:boom_board/features/simple_mode/domain/entities/explosion_result_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_result_entity.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/consume_room_snapshot_use_case.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/request_snapshot_use_case.dart';
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
  static const String feedLogPanel = 'FEED_LOG_PANEL';
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
  bool _resyncInFlight = false;
  // Bumped every time authoritative state lands. A round animation captures it
  // when it starts and abandons itself if it changed across an await, so a
  // sequence left mid-flight by a background cannot overwrite the snapshot
  // that superseded it.
  int _roundAnimationGeneration = 0;
  // Animation ids used to be minted from the wall clock, which only held up
  // because every trigger in the round sequence sat behind an await.
  // `triggerLaserAnimation` mints a whole burst inside one synchronous loop,
  // where the clock never ticks -- those ids stayed distinct only because the
  // coordinates baked into them did. A counter is unique by construction, so
  // widget keys no longer depend on where the id happens to be minted.
  int _animationIdCounter = 0;
  /// Every log the server has sent for this game. Nothing on screen reads
  /// it -- it is the round's full record, kept for a history/replay view
  /// later. Only [feedLogList] is shown.
  List<ActionLogEntity> actionLogList = [];

  /// What the player actually reads, in the order it happened: kills, plus
  /// the two ways a player drops out of the game. The chatter -- every bomb
  /// that missed, every laser sweep -- stays in [actionLogList] only.
  List<ActionLogEntity> feedLogList = [];
  List<Coordinate> destroyedTile = [];
  Coordinate? hoveredTile;
  Coordinate? lockedBombTarget;
  Coordinate? winnerPosition;
  bool showEndgameOverlay = true;
  bool hideLocalPlayerIcon = false;
  List<SimpleModeResultEntity> finalRanking = [];
  /// Seconds left in the current phase, and so how long the timer bar has to
  /// finish draining. Not the phase's full length -- a client that arrived
  /// mid-phase gets what is left of it.
  int currentPhaseTimeLimit = 0;

  /// How full the timer bar starts, 0..1. Always 1 for a phase joined at its
  /// start; for one joined late it is the fraction still to run, so the bar
  /// drains at the same rate everyone else's does instead of racing to catch
  /// up from full.
  double currentPhaseStartProgress = 1;
  String currentTimerKey = '';
  int _timerEpoch = 0;

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
  StreamSubscription? pageResumedSubs;

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

  /// The room to present when re-entering. Prefers the credential slot: it
  /// records the last entry the server actually bound this socket to, so if the
  /// two ever disagree (two entries racing each other) the slot is the one that
  /// matches the seat we are trying to reclaim.
  ///
  /// Only ever a bootstrap. A rejoin writes the room it actually landed in back
  /// to [roomCode], so the two can only disagree until the next one completes
  /// -- long enough to aim the rejoin, never long enough to leave the screen
  /// naming one room while the seat lives in another.
  String get _roomToReclaim {
    final stored = GetIt.I<IdentityStore>().credentials?.roomCode;
    if (stored != null && stored.isNotEmpty) return stored;
    return roomCode;
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

    final args = Get.arguments;
    if (args is SimpleModeArguments) {
      roomCode = args.roomCode;
      hostId = args.hostId;
      playerList = args.playerList;
      spectatorList = args.spectatorList;
      isSpectator = args.isSpectator;

      subscribeListener();
    } else if (!_recoverRoomWithoutArguments()) {
      return;
    }

    // A mid-game entry gets its snapshot the instant the server acks, which is
    // before this controller exists. Pick up anything that landed in the gap.
    final pendingSnapshot = GetIt.I<ConsumeRoomSnapshotUseCase>().call();
    if (pendingSnapshot != null) {
      applyRoomSnapshot(pendingSnapshot);
    }
  }

  /// Rebuilds the room from the credential slot when the route arguments are
  /// gone, returning false when there is nothing left to rebuild from.
  ///
  /// The arguments can genuinely go missing: `Get.arguments` is one global slot
  /// that every dialog, bottom sheet and snackbar overwrites while it is open,
  /// and it is read here -- from the route's first build -- a frame *after* the
  /// push that filled it. A frame that never comes (backgrounded mobile Chrome)
  /// stretches that gap indefinitely. The seat on the server is already taken
  /// by then, so bouncing home over it leaves a body on the board that nobody
  /// is driving.
  ///
  /// The credential slot is the copy that can be trusted: create/join both
  /// persist it *before* this route is ever pushed, and it survives a reload.
  /// Everything else the arguments carried -- roster, host, phase, board, our
  /// own tile -- comes back in the snapshot.
  bool _recoverRoomWithoutArguments() {
    final creds = GetIt.I<IdentityStore>().credentials;
    if (creds == null || creds.roomCode.isEmpty) {
      logger.e('Entered the room screen with no arguments and no credentials.');
      _bailOutToHome();
      return false;
    }

    logger.w('Route arguments were lost. Rebuilding room ${creds.roomCode} from the snapshot.');
    roomCode = creds.roomCode;

    subscribeListener();
    _hydrateFromSnapshot();

    return true;
  }

  /// Fills in everything the lost arguments were carrying.
  ///
  /// Until the snapshot lands there is no roster, no host and no phase, so this
  /// borrows the reconnect overlay rather than presenting an empty lobby that
  /// invites taps. `applyRoomSnapshot` clears it.
  ///
  /// A snapshot is the cheap way back in -- it skips the `playerReconnected`
  /// broadcast and the progression re-check a full join fires at everyone else
  /// -- but the server answers it from the binding it made at join time, so it
  /// only works while *this* socket still holds the seat. A socket that dropped
  /// and has not rejoined yet holds nothing, and the request is refused. That
  /// is not a dead end: it just means the seat has to be reclaimed the long
  /// way, which is what `rejoinRoom` does -- with the very credentials this
  /// recovery has already validated, and owning the overlay and the per-error
  /// messaging on the way.
  Future<void> _hydrateFromSnapshot() async {
    connectionState = RoomConnectionState.reconnecting;
    connectionError = null;
    update([SimpleModeIds.connectionOverlay]);

    try {
      await GetIt.I<RequestSnapshotUseCase>().call();
    } catch (e, stackTrace) {
      logger.w('Snapshot rebuild failed. Reclaiming the seat instead.', error: e, stackTrace: stackTrace);
      await rejoinRoom();
    }
  }

  /// Gives up the seat and goes home, for when even the credentials are gone.
  ///
  /// Both halves are deliberate. `leaveRoom` is keyed on the socket rather than
  /// on our identity, so it still releases the seat we can no longer name --
  /// without it the server keeps waiting on a player who is not there and every
  /// round burns the full phase timer. And the redirect is deferred out of the
  /// build: onInit runs while this route is being built, and navigating from
  /// there makes GetX file this controller under the *home* route instead of
  /// this one. It would then never be cleaned up, and since `Get.put` refuses
  /// to replace a live registration, every later join this session would be
  /// handed this same half-built controller -- an empty room code, no
  /// listeners, nothing to play with.
  void _bailOutToHome() {
    leaveRoom();
    WidgetsBinding.instance.addPostFrameCallback((_) => Get.offAllNamed(home));
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
    pageResumedSubs = eventBus.on<PageResumedEvent>().listen(_onPageResumed);
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
    pageResumedSubs?.cancel();
  }

  void resetRound() {
    actionLogList = [];
    feedLogList = [];
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

  /// True when the server refused an action because this socket holds no seat.
  ///
  /// The binding is gone, so nothing this client sends can land until the seat
  /// is reclaimed -- and reclaiming it is the same move the lost-arguments
  /// recovery makes. Worth separating from an ordinary failure, which a retry
  /// of the action itself would fix.
  bool _isUnseated(Object e) => e is BBServerException && e.errorType == 'PLAYER_IS_NOT_IN_A_ROOM';

  void startGame() async {
    if (playerList.length <= 1) return;
    if (isHost) {
      try {
        await GetIt.I<StartGameUseCase>().call(StartGameParams(roomCode: roomCode));
      } catch (e, stackTrace) {
        logger.e('startGame error.', error: e, stackTrace: stackTrace);
        if (_isUnseated(e)) rejoinRoom();
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
      if (_isUnseated(e)) rejoinRoom();
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
    // Through `_applyServerPlayerList`, not a bare assignment: this now fires
    // mid-game too, and the broadcast roster carries no positions -- so taking
    // it raw would blank our own avatar off the board every time anyone left.
    _applyServerPlayerList(event.playerList);
    hostId = event.newHostId;
    _recordLogs(event.newLogs);
    update([SimpleModeIds.playerListPanel, SimpleModeIds.feedLogPanel, SimpleModeIds.controlPanel]);

    if (event.newLogs.isNotEmpty) _scrollToBottom();
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
    _recordLogs(event.newLogs);
    update([SimpleModeIds.playerListPanel, SimpleModeIds.feedLogPanel, SimpleModeIds.controlPanel]);

    _scrollToBottom();
  }

  void onPlayerReconnectedEventReceived(PlayerReconnectedEvent event) {
    logger.d('onPlayerReconnectedEventReceived called with $event');
    _applyServerPlayerList(event.playerList);
    _recordLogs(event.newLogs);
    update([SimpleModeIds.playerListPanel, SimpleModeIds.feedLogPanel, SimpleModeIds.controlPanel]);

    if (event.newLogs.isNotEmpty) _scrollToBottom();
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
    feedLogList = event.logs.where(_isFeedLog).toList();
    finalRanking = event.ranking;
    winnerPosition = event.winnerPosition;
    showEndgameOverlay = event.state == GameState.end;
    lockedBombTarget = null;

    // Clear any animation left mid-flight by the drop; nothing that follows
    // would ever remove it. Bumping the generation also abandons the round
    // sequence driving them -- it is still sitting on an await and would
    // otherwise wake up and write its now-superseded round over this snapshot.
    _roundAnimationGeneration++;
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
      _startPhaseTimer((event.remainingMs / 1000).ceil(), totalSeconds: event.timeLimit);
    } else {
      _clearPhaseTimer();
    }

    connectionState = RoomConnectionState.connected;
    connectionError = null;

    update([
      SimpleModeIds.playerListPanel,
      SimpleModeIds.feedLogPanel,
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

    // This sequence spans several seconds of awaits. If a snapshot lands in
    // the middle of one -- a resync after a background, or a rejoin -- the
    // server's view wins and everything below here is describing a round that
    // has already been replaced.
    final generation = ++_roundAnimationGeneration;

    // Temporarily lock UI into a 'process' state so players can't click things
    currentState = GameState.process;
    _clearPhaseTimer();
    update([SimpleModeIds.controlPanel]);

    int? localPlayerX = localPlayer?.x;
    int? localPlayerY = localPlayer?.y;
    // SEQUENTIAL EXPLOSION LOGIC
    // One iteration per bomb thrown, not per victim -- see `_groupByBomb`. The
    // awaits inside keep the round playing out one bomb at a time.
    for (final hits in _groupByBomb(event.explosionList)) {
      // Every entry in the group shares the bomber and the target tile.
      final bomb = hits.first;

      int startX = -1;
      int startY = -1;

      if (bomb.bomberId == localPlayerId) {
        startX = localPlayerX ?? -1;
        startY = localPlayerY ?? -1;
      }
      triggerBombAnimation(
        bomb.bomberId,
        startX,
        startY,
        bomb.x,
        bomb.y,
      );

      // Wait for the "animation" to finish before evaluating the result
      await Future.delayed(anim_constant.bombDrop);
      if (generation != _roundAnimationGeneration) return;

      if (bomb.bomberId == localPlayerId) {
        lockedBombTarget = null;
      }

      triggerExplosionEffect(bomb.x, bomb.y);

      // Everyone this one bomb killed, in the order the server resolved them.
      final victimNames = <String>[];
      for (final hit in hits) {
        if (!hit.isHit || hit.victimId == null) continue;

        // Update the victim's status in real-time
        final victimIndex = playerList.indexWhere((p) => p.id == hit.victimId);
        if (victimIndex != -1) {
          playerList[victimIndex] = playerList[victimIndex].copyWith(isAlive: false);
          victimNames.add(playerList[victimIndex].name);
        }

        // The kill line lands with the explosion that caused it. Waiting for
        // the tail of this handler would dump every kill of the round on the
        // player at once, seconds after the board already showed them.
        _showKillLogFor(event.newLogs, hit.victimId!);
      }

      if (victimNames.isNotEmpty) {
        update([SimpleModeIds.playerListPanel]);

        // One skull for the tile, carrying every name. They all died on the
        // same tile -- a ghost each would draw them exactly on top of one
        // another, and the name tags would overprint into nothing legible.
        triggerDeathAnimation(bomb.x, bomb.y, playerNames: victimNames);
      }

      await Future.delayed(anim_constant.explosionSettle);
      if (generation != _roundAnimationGeneration) return;
    }

    // --- ORBITAL LASER PHASE ---
    if (event.newDestroyedTiles.isNotEmpty) {
      // Fire the animation!
      triggerLaserAnimation(event.newDestroyedTiles);

      // Wait for the beam to finish firing
      await Future.delayed(anim_constant.destroyedTileDelay);
      if (generation != _roundAnimationGeneration) return;

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
    _recordLogs(event.newLogs);

    currentRound = event.roundNumber;
    update([SimpleModeIds.playerListPanel, SimpleModeIds.feedLogPanel, SimpleModeIds.controlPanel]);

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
      SimpleModeIds.feedLogPanel,
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
    logger.d('Socket is back up. Reclaiming our seat in $_roomToReclaim.');
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
        JoinRoomParams(playerName: localPlayerName, roomCode: _roomToReclaim),
      );

      // Only the fields the snapshot doesn't carry are taken from the ack --
      // the private roomSnapshot that follows is the authoritative view and
      // will overwrite the rest. The room code is one of them, and taking it
      // here is what stops `roomCode` and the credential slot drifting apart:
      // whichever room we actually landed in becomes the only one on record,
      // rather than the screen naming one room while the seat sits in another.
      roomCode = result.roomCode;
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

  void _onPageResumed(PageResumedEvent event) {
    logger.d('Page is back on screen. Re-reading the room.');

    // A drop has its own recovery: rejoinRoom() pulls a snapshot as part of
    // getting the seat back, so asking for a second one here would just race
    // it. Only the socket-survived case is ours to handle.
    if (connectionState != RoomConnectionState.connected) return;

    resyncFromServer();
  }

  /// Re-reads the room from the server and throws away whatever we had.
  ///
  /// The phase clock kept draining while we were backgrounded and rounds may
  /// have resolved unseen, so local state is not stale by a little -- it can be
  /// wrong about which phase we are even in.
  Future<void> resyncFromServer() async {
    if (_resyncInFlight) return;
    _resyncInFlight = true;

    try {
      await GetIt.I<RequestSnapshotUseCase>().call();
    } catch (e, stackTrace) {
      // Nothing to surface: if the socket is genuinely gone the disconnect
      // handler owns the overlay, and if it is merely slow the next resume or
      // reconnect will try again.
      logger.e('resyncFromServer error.', error: e, stackTrace: stackTrace);
    } finally {
      _resyncInFlight = false;
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

  /// Splits a round's explosion list into one entry per bomb thrown.
  ///
  /// The server reports a hit per victim, so a bomb that lands on a tile two
  /// players are sharing arrives as two entries with the same bomber and the
  /// same coordinates. Animating each as its own throw drew two bombs falling
  /// on one tile, flashed the explosion twice, and stretched the round by a
  /// full bomb per extra kill.
  ///
  /// Grouped on consecutive runs rather than by bomber, so the round's order
  /// survives even if a later mode lets a player throw more than once.
  List<List<ExplosionResultEntity>> _groupByBomb(List<ExplosionResultEntity> explosions) {
    final List<List<ExplosionResultEntity>> groups = [];

    for (final explosion in explosions) {
      final current = groups.isEmpty ? null : groups.last;
      final isSameBomb = current != null &&
          current.first.bomberId == explosion.bomberId &&
          current.first.x == explosion.x &&
          current.first.y == explosion.y;

      if (isSameBomb) {
        current.add(explosion);
      } else {
        groups.add([explosion]);
      }
    }

    return groups;
  }

  /// Which log types earn a line on screen. See [feedLogList].
  bool _isFeedLog(ActionLogEntity log) =>
      log.type == LogActionType.playerEliminated ||
      log.type == LogActionType.playerDisconnected ||
      log.type == LogActionType.playerReconnected ||
      log.type == LogActionType.playerLeft;

  bool _isKillLog(ActionLogEntity log) => log.type == LogActionType.playerEliminated;

  /// Keeps the full server log, and mirrors the lines worth showing into the
  /// feed the player reads. Kills already shown mid-animation are skipped, so
  /// calling this with a whole round's logs is safe.
  ///
  /// Paints nothing: every caller is a handler that already updates the feed
  /// panel and scrolls once it has applied the rest of the event, so doing it
  /// per log here would just queue the same repaint and scroll N times over.
  void _recordLogs(List<ActionLogEntity> logs) {
    actionLogList.addAll(logs);
    for (final log in logs) {
      if (_isFeedLog(log)) _appendFeedLog(log);
    }
  }

  /// Shows the kill line for one victim out of the round's logs.
  ///
  /// Matched on the raw payload rather than the typed accessor on purpose:
  /// this runs mid-animation, and a malformed log must not be able to throw
  /// the round sequence off the rails. Anything missed here still gets picked
  /// up by [_recordLogs] at the end of the round.
  void _showKillLogFor(List<ActionLogEntity> roundLogs, String victimId) {
    for (final log in roundLogs) {
      if (_isKillLog(log) && log.data['victimId'] == victimId) {
        // The one caller that has to paint for itself: this lands mid-round,
        // seconds before the handler's own update at the end of the sequence,
        // and the whole point is that the line shows with its explosion.
        if (_appendFeedLog(log)) {
          update([SimpleModeIds.feedLogPanel]);
          _scrollToBottom();
        }
        return;
      }
    }
  }

  /// Adds a line to the feed if it isn't already there, and reports whether it
  /// actually landed -- a kill shown mid-animation is skipped when the round's
  /// full log arrives behind it.
  bool _appendFeedLog(ActionLogEntity log) {
    if (feedLogList.any((e) => e.id == log.id)) return false;
    feedLogList.add(log);
    return true;
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
      id: '${bomberId}_${_animationIdCounter++}',
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
    final id = 'exp_${x}_${y}_${_animationIdCounter++}';
    activeExplosions.add(ActiveTileAnimationEntity(id: id, x: x, y: y));
    update([SimpleModeIds.boardPanel]);

    // Delay for the animation duration. When it finishes, we remove the explosion!
    Future.delayed(anim_constant.explosion, () {
      activeExplosions.removeWhere((c) => c.x == x && c.y == y);
      update([SimpleModeIds.boardPanel]);
    });
  }

  void triggerDeathAnimation(int x, int y, {List<String> playerNames = const []}) {
    final id = 'death_${x}_${y}_${_animationIdCounter++}';
    activeDeaths.add(ActiveTileAnimationEntity(id: id, x: x, y: y, playerNames: playerNames));
    update([SimpleModeIds.boardPanel]);

    // Delay for the animation duration. When it finishes, we remove the ghost!
    Future.delayed(anim_constant.deathGhost, () {
      activeDeaths.removeWhere((c) => c.x == x && c.y == y);
      update([SimpleModeIds.boardPanel]);
    });
  }

  void triggerLaserAnimation(List<Coordinate> tiles) {
    for (var tile in tiles) {
      final id = 'laser_${tile.x}_${tile.y}_${_animationIdCounter++}';
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

  /// Starts the phase clock with [seconds] left to run.
  ///
  /// [totalSeconds] is the phase's full length, and only differs from
  /// [seconds] when we joined it late. Passing both is what lets the bar start
  /// part-drained rather than full: a player resuming at 15s of a 30s phase
  /// sees a half-empty bar emptying at the normal rate, which is exactly what
  /// everyone who never left is looking at.
  void _startPhaseTimer(int seconds, {int? totalSeconds}) {
    final total = totalSeconds ?? seconds;

    currentPhaseTimeLimit = seconds;
    currentPhaseStartProgress = total <= 0 ? 1 : (seconds / total).clamp(0.0, 1.0);
    // A counter, not a timestamp: the key is what remounts the bar, and only a
    // remount reads `currentPhaseStartProgress` at all -- TweenAnimationBuilder
    // ignores a changed `begin` on rebuild. Two calls inside the same
    // millisecond are routine when a resume drains a backlog of buffered
    // events, and a colliding key would silently keep the earlier bar.
    currentTimerKey = 'timer_${currentState}_${++_timerEpoch}';
    update([SimpleModeIds.controlPanel]);
  }

  void _clearPhaseTimer() {
    currentPhaseTimeLimit = -1;
    currentPhaseStartProgress = 1;
  }
}
