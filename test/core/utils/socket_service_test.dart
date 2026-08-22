import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:boom_board/core/utils/socket_service.dart';
import '../../helpers/mocks.dart';
import 'package:boom_board/core/events/models/socket_connected_event.dart';
import 'package:boom_board/core/events/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_di.dart';

void main() {
  // handleAckData never touches `socket`, so a bare SocketService is enough --
  // but it does resolve GetIt.I<Logger>() on the first line.
  late SocketService socketService;

  setUp(() async {
    await setUpTestDependencies();
    socketService = SocketService();
  });

  tearDown(tearDownTestDependencies);

  group('SocketService.connectToServer', () {
    late List<FakeSocket> built;
    late SocketService service;

    setUp(() {
      built = [];
      service = SocketService(socketFactory: () {
        final socket = FakeSocket();
        built.add(socket);
        return socket;
      });
    });

    test('builds one socket, connects it, and binds each lifecycle listener once', () {
      service.connectToServer();

      expect(built, hasLength(1));
      expect(built.single.connectCalls, 1);
      expect(built.single.handlerCount('connect'), 1);
      expect(built.single.handlerCount('connect_error'), 1);
      expect(built.single.handlerCount('disconnect'), 1);
      expect(built.single.fakeManager.handlerCount('reconnect_attempt'), 1);
    });

    test('never builds a second socket', () {
      // The leak this guards. `io.io()` does not hand back the socket it
      // already made for this host: `_lookup` sees the namespace is taken and
      // treats the call as a request for a separate connection, returning a
      // fresh Manager and Socket. Reassigning `socket` to it would abandon the
      // old one -- still listening, still reconnecting on its own -- as a second
      // connection the app can neither see nor close, firing a duplicate set of
      // bus events and holding a second seat on the server.
      service.connectToServer();
      final first = built.single;

      first.connected = true;
      service.connectToServer();

      first.connected = false;
      service.connectToServer();

      expect(built, hasLength(1));
      expect(service.socket, same(first));
      expect(first.handlerCount('connect'), 1);
      expect(first.fakeManager.handlerCount('reconnect_attempt'), 1);
    });

    test('re-announces an existing connection so a late caller is not left waiting', () async {
      // HomeController flips `isConnecting` on and waits for the bus. Coming
      // back to the home screen with the socket already up fires no fresh
      // `connect`, so without this the panel would spin forever.
      service.connectToServer();
      built.single.connected = true;

      var announced = 0;
      eventBus.on<SocketConnectedEvent>().listen((_) => announced++);

      service.connectToServer();
      await pumpEventBus();

      expect(announced, 1);
      expect(built.single.connectCalls, 1);
    });

    test('nudges the existing socket when it is down instead of announcing', () async {
      service.connectToServer();
      built.single.connected = false;

      var announced = 0;
      eventBus.on<SocketConnectedEvent>().listen((_) => announced++);

      service.connectToServer();
      await pumpEventBus();

      expect(built.single.connectCalls, 2);
      expect(announced, 0, reason: 'the socket is not up yet -- its own connect handler announces it');
    });

    test('the one bound connect handler announces the connection', () async {
      service.connectToServer();

      var announced = 0;
      eventBus.on<SocketConnectedEvent>().listen((_) => announced++);

      built.single.serverEmit('connect', null);
      await pumpEventBus();

      expect(announced, 1, reason: 'a duplicate registration would announce twice');
    });
  });

  group('SocketService.handleAckData', () {
    test('returns a SocketResponse for a 200 ack', () {
      final response = socketService.handleAckData(
        ackJson(code: 200, data: <String, dynamic>{'roomCode': 'ABCD'}),
      );

      expect(response.code, 200);
      expect(response.data, <String, dynamic>{'roomCode': 'ABCD'});
    });

    test('returns a SocketResponse with null data for a 200 ack carrying none', () {
      // Callers such as RoomSocketService.createRoom rely on being handed a
      // response here so they can raise their own error for the null payload.
      final response = socketService.handleAckData(ackJson(code: 200));

      expect(response.code, 200);
      expect(response.data, isNull);
    });

    test('throws BBServerException carrying the server error detail', () {
      expect(
        () => socketService.handleAckData(<String, dynamic>{
          'code': 400,
          'errorType': 'INVALID_PLAYER_NAME',
          'data': 'name too long',
        }),
        throwsA(
          isA<BBServerException>()
              .having((e) => e.code, 'code', 400)
              .having((e) => e.errorType, 'errorType', 'INVALID_PLAYER_NAME')
              .having((e) => e.data, 'data', 'name too long'),
        ),
      );
    });

    test('treats any non-200 code as an error, including 201', () {
      expect(
        () => socketService.handleAckData(<String, dynamic>{
          'code': 201,
          'errorType': 'CREATED',
        }),
        throwsA(isA<BBServerException>()),
      );
    });

    test('throws a raw TypeError, not BBServerException, when code is absent', () {
      // Characterization. An ack with no `code` fails the `== 200` check and
      // falls into the error branch, where `BBServerException.code` is a
      // non-nullable int and the null fails the implicit cast. The result is a
      // TypeError that slips past every `on BBServerException` handler --
      // HomeController.onCreatePressed then reports "Unknown error occurred"
      // instead of the server's actual errorType.
      expect(
        () => socketService.handleAckData(<String, dynamic>{'errorType': 'OOPS'}),
        throwsA(isA<TypeError>()),
      );
    });

    group('non-Map acks', () {
      test('throws InvalidSocketResponseException for a String', () {
        expect(
          () => socketService.handleAckData('pong'),
          throwsA(isA<InvalidSocketResponseException>()),
        );
      });

      test('throws InvalidSocketResponseException for null', () {
        expect(
          () => socketService.handleAckData(null),
          throwsA(isA<InvalidSocketResponseException>()),
        );
      });

      test('throws InvalidSocketResponseException for a List', () {
        expect(
          () => socketService.handleAckData(<dynamic>[]),
          throwsA(isA<InvalidSocketResponseException>()),
        );
      });
    });

    test('accepts a Map<dynamic, dynamic> ack envelope', () {
      // The guard is `ackData is Map`, so an untyped map from the JS interop
      // layer gets through the outer check.
      final response = socketService.handleAckData(<dynamic, dynamic>{'code': 200, 'data': null});

      expect(response.code, 200);
    });

    test('but throws TypeError when that untyped ack carries a data map', () {
      // Characterization of the guard/cast mismatch: `ackData is Map` passes,
      // then `SocketResponse.data` demands a Map<String, dynamic> and the
      // untyped inner map fails the implicit cast. Tightening the guard to
      // `is! Map<String, dynamic>` or copying with Map<String, dynamic>.from
      // would turn this into a clean InvalidSocketResponseException.
      expect(
        () => socketService.handleAckData(<dynamic, dynamic>{
          'code': 200,
          'data': <dynamic, dynamic>{'roomCode': 'ABCD'},
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
