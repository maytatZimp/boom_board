import 'package:boom_board/core/domain/use_cases/get_current_player_id_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockSocketService socketService;
  late MockSocket socket;
  late GetCurrentPlayerIdUseCase useCase;

  setUp(() {
    socket = MockSocket();
    socketService = MockSocketService();
    when(() => socketService.socket).thenReturn(socket);
    useCase = GetCurrentPlayerIdUseCase(socketService: socketService);
  });

  group('GetCurrentPlayerIdUseCase', () {
    test('returns the socket id', () {
      when(() => socket.id).thenReturn('sock-123');

      expect(useCase.call(), 'sock-123');
    });

    test('returns null before the socket has connected', () {
      // socket.id is only assigned on connect. SimpleModeController.localPlayerId
      // turns this null into '', which makes `isHost` false and `localPlayer`
      // null -- so a disconnected client renders as a non-host spectator rather
      // than crashing.
      when(() => socket.id).thenReturn(null);

      expect(useCase.call(), isNull);
    });
  });
}
