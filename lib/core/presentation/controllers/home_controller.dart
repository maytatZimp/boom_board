import 'dart:async';
import 'dart:math' as math;

import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/data/models/enums/game_mode.dart';
import 'package:boom_board/core/domain/constants/home_animation_constant.dart';
import 'package:boom_board/core/domain/entities/enums/home_animation_state.dart';
import 'package:boom_board/core/domain/use_cases/connect_to_server_use_case.dart';
import 'package:boom_board/core/domain/use_cases/create_room_use_case.dart';
import 'package:boom_board/core/domain/use_cases/join_room_use_case.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/core/events/models/socket_connected_error_event.dart';
import 'package:boom_board/core/events/models/socket_connected_event.dart';
import 'package:boom_board/core/events/models/socket_disconnected_event.dart';
import 'package:boom_board/core/events/models/socket_reconnect_attempt_event.dart';
import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/core/domain/entities/spectator_entity.dart';
import 'package:boom_board/core/presentation/models/enums/home_panel_type.dart';
import 'package:boom_board/core/presentation/widgets/retro_dialog.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/socket_event_data_mapper.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_player_entity.dart';
import 'package:boom_board/features/simple_mode/presentation/arguments/simple_mode_arguments.dart';
import 'package:boom_board/routes/app_pages.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

abstract class HomeIds {
  static const connectingIndicator = 'CONNECTING_INDICATOR';
  static const connectErrorText = 'CONNECT_ERROR_TEXT';
  static const panel = 'PANEL';
  static const backgroundId = 'HOME_BACKGROUND';
  static const tagline = 'TAGLINE';
}

class HomeController extends GetxController {
  bool isConnecting = false;
  bool connectedToServer = false;
  HomePanelType panelType = HomePanelType.start;
  String? panelError;

  /// The credential slot left over from a previous session, if any. Its
  /// presence is what turns the start panel into a "Rejoin room ABCD?" prompt.
  RoomCredentials? pendingRejoin;

  TextEditingController playerNameTextFieldCtl = TextEditingController();
  TextEditingController roomCodeTextFieldCtl = TextEditingController();

  StreamSubscription? socketConnectedListener;
  StreamSubscription? socketConnectedErrorListener;
  StreamSubscription? socketDisconnectedListener;
  StreamSubscription? socketReconnectAttemptedListener;

  // Animation variable
  HomeAnimationState currentState = HomeAnimationState.spawning;
  AttackType currentAttackType = AttackType.arcThrow;
  bool _isRunning = true;
  // NORMALIZED COORDINATES (0.0 to 1.0) ---
  double localX = 0.0;
  double localY = 0.0;
  double otherX = 0.0;
  double otherY = 0.0;

  Logger get logger {
    return GetIt.I<Logger>();
  }

  @override
  void onInit() {
    super.onInit();

    _generateNewPositions();
    _startAnimationLoop();
    subscribeEvent();

    // A slot survives reloads and dropped connections, so a fresh app load can
    // land here still owning a seat somewhere.
    pendingRejoin = GetIt.I<IdentityStore>().credentials;
    if (pendingRejoin != null) {
      panelType = HomePanelType.rejoin;
    }

    try {
      isConnecting = true;
      GetIt.I<ConnectToServerUseCase>().call();
    } catch (e, stackTrace) {
      logger.e('Connect to server error.', error: e, stackTrace: stackTrace);
    }
  }

  @override
  void onClose() {
    super.onClose();
    _isRunning = false;
    socketConnectedListener?.cancel();
    socketConnectedErrorListener?.cancel();
    socketDisconnectedListener?.cancel();
    socketReconnectAttemptedListener?.cancel();
  }

  void subscribeEvent() {
    socketConnectedListener = eventBus.on<SocketConnectedEvent>().listen((event) {
      logger.d('SocketConnectedEvent called');
      connectedToServer = true;
      isConnecting = false;
      update([HomeIds.connectingIndicator, HomeIds.connectErrorText, HomeIds.panel]);
    });
    socketConnectedErrorListener = eventBus.on<SocketConnectedErrorEvent>().listen((event) {
      logger.d('SocketConnectedErrorEvent called');
      connectedToServer = false;
      isConnecting = false;
      update([HomeIds.connectingIndicator, HomeIds.connectErrorText, HomeIds.panel]);
    });
    socketDisconnectedListener = eventBus.on<SocketDisconnectedEvent>().listen((event) {
      logger.d('SocketDisconnectedEvent called');
      connectedToServer = false;
      isConnecting = false;
      update([HomeIds.connectingIndicator, HomeIds.connectErrorText, HomeIds.panel]);
    });
    socketReconnectAttemptedListener = eventBus.on<SocketReconnectAttemptEvent>().listen((event) {
      logger.d('SocketReconnectAttemptEvent called');
      connectedToServer = false;
      isConnecting = true;
      update([HomeIds.connectingIndicator, HomeIds.connectErrorText, HomeIds.panel]);
    });
  }

  void onRejoinPressed() async {
    final creds = pendingRejoin;
    if (creds == null) return;

    logger.d('onRejoinPressed called for room ${creds.roomCode}');
    panelError = null;
    update([HomeIds.panel]);

    try {
      final result = await GetIt.I<JoinRoomUseCase>().call(
        JoinRoomParams(playerName: creds.playerName, roomCode: creds.roomCode),
      );

      if (result.gameMode == GameMode.simple) {
        pendingRejoin = null;
        _openSimpleModeRoom(
          roomCode: result.roomCode,
          hostId: result.hostId,
          playerList: result.playerList.toSimpleModeEntity(),
          spectatorList: result.spectatorList,
          isSpectator: result.isSpectator,
        );
      }
    } on BBServerException catch (e, stackTrace) {
      logger.e('Rejoin BBServerException error.', error: e, stackTrace: stackTrace);
      if (e.errorType == 'ROOM_NOT_FOUND') {
        // JoinRoomUseCase already dropped the dead slot; just tell the user.
        pendingRejoin = null;
        panelType = HomePanelType.start;
        panelError = null;
        update([HomeIds.panel]);
        _showRoomGoneDialog(creds.roomCode);
        return;
      } else if (e.errorType == 'SECRET_MISMATCH') {
        pendingRejoin = null;
        panelType = HomePanelType.start;
        panelError = null;
        update([HomeIds.panel]);
        return;
      }
      panelError = 'Could not rejoin room ${creds.roomCode}';
      update([HomeIds.panel]);
    } catch (e, stackTrace) {
      logger.e('Rejoin error.', error: e, stackTrace: stackTrace);
      panelError = 'Could not rejoin room ${creds.roomCode}';
      update([HomeIds.panel]);
    }
  }

  void onDismissRejoinPressed() async {
    logger.d('onDismissRejoinPressed called');
    pendingRejoin = null;
    panelType = HomePanelType.start;
    panelError = null;
    update([HomeIds.panel]);

    // Dismissing is a deliberate "I'm not going back", so the slot goes too.
    await GetIt.I<IdentityStore>().clear();
  }

  void _showRoomGoneDialog(String roomCode) {
    if (Get.isDialogOpen ?? false) return;

    Get.dialog(
      RetroDialog(
        title: 'Room gone',
        message: 'Room $roomCode no longer exists.',
        // Nothing to decide -- the dead slot is already dropped, so this is
        // news, not a question.
        onCancel: null,
        onConfirm: () => Get.back(),
      ),
    );
  }

  void _openSimpleModeRoom({
    required String roomCode,
    required String hostId,
    required List<SimpleModePlayerEntity> playerList,
    required List<SpectatorEntity> spectatorList,
    required bool isSpectator,
  }) {
    Get.toNamed(
      simpleMode,
      arguments: SimpleModeArguments(
        roomCode: roomCode,
        hostId: hostId,
        playerList: playerList,
        spectatorList: spectatorList,
        isSpectator: isSpectator,
      ),
    );
    // Reset home screen.
    onCancelPressed();
  }

  void onHostPressed() {
    logger.d('onHostPressed called');
    panelError = null;
    panelType = HomePanelType.host;
    update([HomeIds.panel]);
  }

  void onJoinPressed() {
    logger.d('onJoinPressed called');
    panelError = null;
    panelType = HomePanelType.join;
    update([HomeIds.panel]);
  }

  void onCreatePressed() async {
    logger.d('onCreatePressed called');
    try {
      panelError = null; // Clear previous errors
      update([HomeIds.panel]);

      if (playerNameTextFieldCtl.text.trim().isEmpty) {
        panelError = 'Player name required';
        update([HomeIds.panel]);
        return;
      }

      final result = await GetIt.I<CreateRoomUseCase>().call(
        CreateRoomParams(
          playerName: playerNameTextFieldCtl.text.trim(),
        ),
      );
      logger.d('create result from server is ${result.roomCode}');
      if (result.gameMode == GameMode.simple) {
        pendingRejoin = null;
        _openSimpleModeRoom(
          roomCode: result.roomCode,
          hostId: result.hostId,
          playerList: result.playerList.toSimpleModeEntity(),
          spectatorList: result.spectatorList,
          isSpectator: result.isSpectator,
        );
      }
    } on BBServerException catch (e, stackTrace) {
      logger.e('SimpleModeCreateRoomUseCase BBServerException error.', error: e, stackTrace: stackTrace);
      if (e.errorType == 'INVALID_PLAYER_NAME') {
        panelError = 'Player name must be 1 - 20 characters long';
      } else {
        panelError = 'Unknown server error occurred';
      }
      update([HomeIds.panel]);
    } catch (e, stackTrace) {
      logger.e('SimpleModeCreateRoomUseCase error.', error: e, stackTrace: stackTrace);
      panelError = 'Unknown error occurred';
      update([HomeIds.panel]);
    }
  }

  void onJoinConfirmPressed() async {
    logger.d('onJoinConfirmPressed called');
    try {
      panelError = null; // Clear previous errors
      update([HomeIds.panel]);

      // 1. Client-Side Validation
      if (playerNameTextFieldCtl.text.trim().isEmpty) {
        panelError = 'Player name required';
        update([HomeIds.panel]);
        return;
      }
      if (roomCodeTextFieldCtl.text.trim().length != 4) {
        panelError = 'Invalid room code';
        update([HomeIds.panel]);
        return;
      }

      final result = await GetIt.I<JoinRoomUseCase>().call(
        JoinRoomParams(
          playerName: playerNameTextFieldCtl.text,
          roomCode: roomCodeTextFieldCtl.text,
        ),
      );
      logger.d('join result from server is ${result.playerList} gameMode is ${result.gameMode}');
      if (result.gameMode == GameMode.simple) {
        pendingRejoin = null;
        _openSimpleModeRoom(
          roomCode: result.roomCode,
          hostId: result.hostId,
          playerList: result.playerList.toSimpleModeEntity(),
          spectatorList: result.spectatorList,
          isSpectator: result.isSpectator,
        );
      }
    } on BBServerException catch (e, stackTrace) {
      logger.e('SimpleModeJoinRoomUseCase BBServerException error.', error: e, stackTrace: stackTrace);
      if (e.errorType == 'ROOM_NOT_FOUND') {
        panelError = 'Room ${roomCodeTextFieldCtl.text} not found';
      } else if (e.errorType == 'ROOM_IS_FULL') {
        panelError = 'Room is full';
      } else if (e.errorType == 'ROOM_IS_FULL_OF_SPECTATORS') {
        panelError = 'Room has too many spectators';
      } else if (e.errorType == 'SECRET_MISMATCH') {
        // Stale creds for this room were just cleared -- a plain retry now
        // enters as a new player.
        panelError = 'Could not verify your old seat. Try again.';
      } else if (e.errorType == 'INVALID_PLAYER_NAME') {
        panelError = 'Player name must be 1 - 20 characters long';
      }
      update([HomeIds.panel]);
    } catch (e, stackTrace) {
      logger.e('SimpleModeJoinRoomUseCase error.', error: e, stackTrace: stackTrace);
      panelError = 'Unknown error occurred';
      update([HomeIds.panel]);
    }
  }

  void onCancelPressed() {
    logger.d('onCancelPressed called');
    panelError = null;
    panelType = HomePanelType.start;
    playerNameTextFieldCtl.clear();
    roomCodeTextFieldCtl.clear();
    update([HomeIds.panel]);
  }

  // --- THE STATE MACHINE ---
  void _startAnimationLoop() async {
    // Wait a tiny bit on first load so it doesn't start instantly before the screen renders
    await Future.delayed(HomeAnimationConstant.betweenLoopDelay);

    while (_isRunning) {
      // 1. Spawning
      currentState = HomeAnimationState.spawning;
      update([HomeIds.backgroundId, HomeIds.tagline]);
      await Future.delayed(HomeAnimationConstant.spawn);
      if (!_isRunning) break;

      // 2. Repositioning (Walking/Fading)
      moveLocalPlayerInward();
      currentState = HomeAnimationState.repositioning;
      update([HomeIds.backgroundId, HomeIds.tagline]);
      await Future.delayed(HomeAnimationConstant.walk);
      if (!_isRunning) break;

      currentState = HomeAnimationState.waiting;
      update([HomeIds.backgroundId, HomeIds.tagline]);
      await Future.delayed(HomeAnimationConstant.betweenLoopDelay);
      if (!_isRunning) break;

      // 3. Attacking (Bomb in air)
      currentState = HomeAnimationState.attacking;
      update([HomeIds.backgroundId, HomeIds.tagline]);
      await Future.delayed(HomeAnimationConstant.bombFlight); // Time it takes bomb to hit
      if (!_isRunning) break;

      // 4. Exploding
      currentState = HomeAnimationState.exploding;
      update([HomeIds.backgroundId, HomeIds.tagline]);
      await Future.delayed(HomeAnimationConstant.explosion); // Time the explosion lasts
      if (!_isRunning) break;

      // 5. Celebrating (Victory sprite)
      currentState = HomeAnimationState.celebrating;
      update([HomeIds.backgroundId, HomeIds.tagline]);
      await Future.delayed(HomeAnimationConstant.celebrate); // Let them flex for a bit
      if (!_isRunning) break;

      // 6. Resetting (Everything fades to black)
      currentState = HomeAnimationState.resetting;
      update([HomeIds.backgroundId, HomeIds.tagline]);
      await Future.delayed(HomeAnimationConstant.reset);
      if (!_isRunning) break;

      // --- LOOP COMPLETE: Toggle the attack type for the next round! ---
      // --- Calculate fresh positions for the next loop! ---
      _generateNewPositions();
      currentAttackType = currentAttackType == AttackType.arcThrow ? AttackType.verticalDrop : AttackType.arcThrow;
      await Future.delayed(HomeAnimationConstant.betweenLoopDelay);
    }
  }

  // --- THE MATH: SAFE ZONE CALCULATION ---
  void _generateNewPositions() {
    final random = math.Random();

    // Local player spawns on the Left (between 5% and 15% of screen width)
    localX = 0.05 + random.nextDouble() * 0.05;
    // Y is anywhere in the middle 60% of the screen height
    localY = 0.20 + random.nextDouble() * 0.60;

    // Other player spawns on the Right (between 85% and 95% of screen width)
    otherX = 0.85 + random.nextDouble() * 0.10;
    otherY = 0.20 + random.nextDouble() * 0.60;
  }

  // Helper to move the local player slightly inward during the reposition phase
  void moveLocalPlayerInward() {
    final random = math.Random();
    // Move to 20%-30% of the screen (still safely away from the center menu)
    localX = 0.20 + random.nextDouble() * 0.10;
    localY = localY + (random.nextDouble() * 0.10 - 0.05); // Slight Y shift
  }
}
