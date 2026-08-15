import 'package:boom_board/core/exceptions/bb_server_exception.dart';
import 'package:boom_board/core/exceptions/invalid_socket_response_exception.dart';
import 'package:boom_board/core/utils/socket_service.dart';
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
