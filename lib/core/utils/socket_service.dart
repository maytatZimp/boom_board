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

/// Builds the app's one socket. Injectable so [SocketService.connectToServer]
/// can be exercised without a server, and without reading `.env`.
typedef SocketFactory = io.Socket Function();

io.Socket _buildAppSocket() {
  return io.io(
    backendUrl,
    io.OptionBuilder()
        .setTransports(['websocket']) // Required for Flutter Web
        .disableAutoConnect()
        .setAckTimeout(5000)
        .setReconnectionAttempts(5)
        .build(),
  );
}

class SocketService {
  SocketService({SocketFactory? socketFactory}) : _socketFactory = socketFactory ?? _buildAppSocket;

  final SocketFactory _socketFactory;

  late io.Socket socket;
  bool _isInitialized = false;

  Logger get logger {
    return GetIt.I<Logger>();
  }

  void connectToServer() {
    // The socket is built exactly once per app run, and every listener below is
    // bound to that one instance.
    //
    // Rebuilding it here would not reuse it. `io.io()` looks up its cache by
    // host, finds the namespace already taken, and treats that as a request for
    // a *separate* connection: a fresh Manager and a fresh Socket, neither of
    // them cached (socket_io_client's `_lookup`, where `sameNamespace` forces
    // `newConnection`). We would reassign `socket` to the new one and lose our
    // only handle on the old -- which is still alive, still carrying the
    // listeners below, and still running its own reconnection loop. It comes
    // back as a second connection the app cannot see or close, firing a second
    // set of events onto the bus and holding a second seat on the server.
    //
    // So a repeat call never rebuilds. There are only two useful things left to
    // do: re-announce a connection the caller may have missed, and nudge a
    // socket that is currently down. `Socket.connect()` is safe to call again --
    // it re-opens a closed manager and its `subEvents()` is a no-op when the
    // subscriptions are already in place.
    if (_isInitialized) {
      if (socket.connected) {
        logger.d('Socket already connected, re-firing SocketConnectedEvent.');
        eventBus.fire(SocketConnectedEvent());
      } else {
        logger.d('Socket exists but is down, reconnecting the existing one.');
        socket.connect();
      }
      return;
    }

    socket = _socketFactory();

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
