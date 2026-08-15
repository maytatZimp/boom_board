import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/core/events/models/socket_connected_error_event.dart';
import 'package:boom_board/core/events/models/socket_connected_event.dart';
import 'package:boom_board/core/events/models/socket_disconnected_event.dart';
import 'package:boom_board/core/events/models/socket_reconnect_attempt_event.dart';
import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/core/exceptions/bb_server_offline_exception.dart';
import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:boom_board/core/utils/app_env.dart';
import 'package:boom_board/core/utils/socket_response.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  late io.Socket socket;
  bool _isInitialized = false;

  Logger get logger {
    return GetIt.I<Logger>();
  }

  void connectToServer() {
    // If a live connection already exists (e.g. returning to the home screen
    // after leaving a room), don't rebuild the socket. The underlying
    // connection is still up, so a fresh `onConnect` would never fire and the
    // caller would wait forever. Just re-announce the connected state.
    if (_isInitialized && socket.connected) {
      logger.d('Socket already connected, re-firing SocketConnectedEvent.');
      eventBus.fire(SocketConnectedEvent());
      return;
    }

    socket = io.io(
      backendUrl,
      io.OptionBuilder()
          .setTransports(['websocket']) // Required for Flutter Web
          .disableAutoConnect()
          .setAckTimeout(5000)
          .setReconnectionAttempts(5)
          .build(),
    );

    _isInitialized = true;
    socket.connect();

    socket.onConnect((_) {
      logger.d('Connected to Boom Board Server!');

      eventBus.fire(SocketConnectedEvent());
    });

    socket.onConnectError((e) {
      logger.e('Connect to Boom Board Server error. $e');
      eventBus.fire(SocketConnectedErrorEvent());
    });

    socket.onDisconnect((_) {
      logger.d('Disconnected');
      eventBus.fire(SocketDisconnectedEvent());
    });

    socket.onReconnectAttempt((e) {
      logger.d('onReconnectAttempt called. Attempt#$e');
      eventBus.fire(SocketReconnectAttemptEvent(attemptCount: e));
    });
  }

  Future<SocketResponse> emitSocket({required String actionName, Map<String, dynamic>? data}) async {
    if (!socket.connected) {
      throw BbServerOfflineException(
        code: 503,
        errorType: 'SERVER_OFFLINE',
        data: 'Cannot connect to the Boom Board server. Please check your internet.',
      );
    }

    try {
      final ackData = await socket.emitWithAckAsync(actionName, data);

      return handleAckData(ackData);
    } on Exception catch (e) {
      if (e.toString().contains('operation has timed out')) {
        throw BbServerOfflineException(
          code: 503,
          errorType: 'SERVER_OFFLINE',
          data: 'Socket call to the Boom Board server timed out. Please check your internet.',
        );
      }
      rethrow;
    }
  }

  SocketResponse handleAckData(dynamic ackData) {
    logger.d('ackData is $ackData runtimeType is ${ackData.runtimeType}');
    if (ackData is Map) {
      if (ackData['code'] == 200) {
        return SocketResponse(data: ackData['data'], code: ackData['code']);
      } else {
        throw BBServerException(code: ackData['code'], errorType: ackData['errorType'], data: ackData['data']);
      }
    } else {
      throw InvalidSocketResponseException();
    }
  }
}
